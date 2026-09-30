// 測試共用：與前端相同，只透過 api_* 預存程序存取
const sql = require('mssql');
const { randomUUID } = require('crypto');
const cfg = require('../config');

let pool;
const connect = async () => (pool ||= await new sql.ConnectionPool(cfg).connect());
async function api(proc, params = {}) {
  const r = (await connect()).request();
  for (const [k, v] of Object.entries(params)) r.input(k, sql.NVarChar(sql.MAX), typeof v === 'string' ? v : JSON.stringify(v));
  return JSON.parse((await r.execute(proc)).recordset[0].json);
}
const save = (code, 主檔, 明細 = [], id = randomUUID()) => api('api_儲存', { 請求編號: id, 功能代碼: code, 資料: { 主檔, 明細 } });
async function verify() {
  const rows = (await (await connect()).request().execute('sp_驗證')).recordset;
  for (const r of rows) console.log(`${r.結果 === '通過' ? '✓' : '✗'} ${r.序}. ${r.規則}${r.違反筆數 ? `（${r.違反筆數} 筆，例：${r.範例}）` : ''}`);
  return rows.every(r => r.違反筆數 === 0);
}
const close = () => pool?.close();
module.exports = { api, save, verify, close, randomUUID };
