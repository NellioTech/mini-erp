// 薄轉接層：只轉呼叫 api_* 預存程序，不含任何商業邏輯
const express = require('express');
const sql = require('mssql');
const path = require('path');
const cfg = require('./config');

const app = express();
const pool = new sql.ConnectionPool(cfg).connect();
const NAME = /^[\p{L}\p{N}_]+$/u;

async function call(proc, params) {
  if (!/^api_[\p{L}\p{N}_]+$/u.test(proc)) throw Object.assign(new Error('不允許的程序'), { status: 404 });
  const req = (await pool).request();
  for (const [k, v] of Object.entries(params)) {
    if (!NAME.test(k)) throw Object.assign(new Error('參數名稱不合法'), { status: 400 });
    req.input(k, sql.NVarChar(sql.MAX), v == null ? null : typeof v === 'string' ? v : JSON.stringify(v));
  }
  const r = await req.execute(proc);
  return r.recordset?.[0]?.json ?? 'null';
}

async function handle(res, proc, params) {
  try {
    res.type('application/json').send(await call(proc, params));
  } catch (e) {
    // SQL 拒絕（商業規則）→ 422，前端不重傳；連線類錯誤 → 503，前端稍後重傳
    const status = e.status || (e.number ? 422 : 503);
    res.status(status).json({ error: e.message });
  }
}

app.use(express.json({ limit: '2mb' }));
app.get('/api/:proc', (req, res) => handle(res, req.params.proc, req.query));
app.post('/api/:proc', (req, res) => handle(res, req.params.proc, req.body || {}));
app.use(express.static(path.join(__dirname, 'public')));

const port = process.env.PORT || 3000;
app.listen(port, () => console.log(`ERP PWA: http://localhost:${port}`));
