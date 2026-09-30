// 建立資料庫並依序執行 db/*.sql。01_tables 只在尚未建表時執行；02 之後皆可重複執行。
// --reset 會先刪除整個資料庫（資料全失）。
const fs = require('fs'), path = require('path'), sql = require('mssql');
const cfg = require('../config');

(async () => {
  const master = await new sql.ConnectionPool({ ...cfg, database: 'master' }).connect();
  const db = cfg.database.replace(/]/g, ']]');
  if (process.argv.includes('--reset')) {
    await master.query(`IF DB_ID(N'${cfg.database}') IS NOT NULL BEGIN ALTER DATABASE [${db}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [${db}]; END`);
    console.log('已刪除資料庫', cfg.database);
  }
  await master.query(`IF DB_ID(N'${cfg.database}') IS NULL CREATE DATABASE [${db}] COLLATE Chinese_Taiwan_Stroke_CI_AS`);
  await master.close();

  const pool = await new sql.ConnectionPool(cfg).connect();
  const files = fs.readdirSync(__dirname).filter(f => /^\d+_.*\.sql$/.test(f)).sort();
  const hasSchema = (await pool.query("SELECT OBJECT_ID(N'功能表') AS id")).recordset[0].id != null;
  for (const f of files) {
    if (f.startsWith('01_') && hasSchema) { console.log('-', f, '（資料表已存在，略過）'); continue; }
    const batches = fs.readFileSync(path.join(__dirname, f), 'utf8').split(/^\s*GO\s*$/im).filter(b => b.trim());
    for (const [i, b] of batches.entries()) {
      try { await pool.batch(b); }
      catch (e) { console.error(`✗ ${f} 第 ${i + 1} 批：${e.message}`); process.exit(1); }
    }
    console.log('✓', f);
  }
  await pool.close();
})().catch(e => { console.error(e.message); process.exit(1); });
