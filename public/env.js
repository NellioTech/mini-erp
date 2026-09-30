// API 位址：與 server.js 同網域時留空；GitHub Pages 靜態版改連 Render 後端（網址不同請修改此處）
window.ERP_API = location.hostname.endsWith('github.io') ? 'https://mini-erp.onrender.com' : '';
