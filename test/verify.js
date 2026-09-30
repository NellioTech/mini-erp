// npm test：對目前資料庫逐條檢查驗證準則（sp_驗證）
const { verify, close } = require('./lib');
verify().then(ok => { close(); console.log(ok ? '\n全部通過' : '\n有規則未通過'); process.exit(ok ? 0 : 1); })
  .catch(e => { console.error(e.message); process.exit(1); });
