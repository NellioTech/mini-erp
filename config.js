// 資料庫連線：讀取專案根目錄 .env（不進版控，範本見 .env.example）
try { process.loadEnvFile(); } catch {}
module.exports = {
  server: process.env.DB_SERVER,
  port: Number(process.env.DB_PORT || 1433),
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
  options: { encrypt: false, trustServerCertificate: true },
  pool: { max: 10 },
  connectionTimeout: 15000,
  requestTimeout: 30000,
};
