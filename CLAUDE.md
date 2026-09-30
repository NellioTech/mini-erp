# CLAUDE.md

ERP 庫存管理系統（SD/MM/IM/PP），PWA 前端 + SQL Server 2022。使用者以繁體中文溝通，資料庫物件一律用中文命名。

## 最高原則
**極大化 SQL Server、極少化前端。能用 T-SQL 物件（資料表約束、觸發程序、視圖、函數、預存程序）解決的，絕不寫在前端或 Node。**
- 檢核 → CHECK / FK / 觸發程序 `THROW 5xxxx, N'中文訊息', 1`
- 計算、過帳、編號 → 觸發程序 / `api_儲存`
- 報表 → 視圖；需輸入條件的 → inline 表值函數（參數自動變成畫面上的輸入欄）
- 選單、欄位、下拉、唯讀 → `功能表`、`欄位設定`、`系統欄位`/`系統參數` 視圖
- `server.js` 只轉呼叫 `api_*`；`public/app.js` 只畫畫面 + 待傳佇列。不要在這兩處加商業邏輯。

## 指令
```bash
npm run db        # 部署 db/*.sql；01_tables 僅在未建表時執行，02~06 皆 CREATE OR ALTER 可重跑
npm run db:reset  # 刪庫重建（會清空資料，執行前先確認）
npm run seed      # 空資料庫時建立示範資料 + 負向測試 + 驗證
npm test          # EXEC sp_驗證，逐條檢查驗證準則
npm start         # http://localhost:3000
```
連線設定在 `.env`（不進版控，範本 `.env.example`）。

## 結構
- `db/01_tables.sql` 資料表與約束（改動既有表需另寫 ALTER 或 db:reset）
- `db/02_views.sql` 中繼資料視圖、庫存異動來源、報表視圖、樞紐函數
- `db/03_triggers.sql` `sp_庫存異動_同步` + 各單據觸發程序
- `db/04_menu.sql` 功能表、欄位設定
- `db/05_api.sql` `api_*` 與 `sp_合併JSON`、`sp_錯誤轉譯`
- `db/06_verify.sql` `sp_驗證`
- `test/seed.js`、`test/verify.js`；`public/` PWA（app.js / sw.js / style.css）

## 關鍵機制
- **過帳**：明細觸發程序以「重算 SUM」回寫（非增量），見 README 表格。
- **庫存帳**：`庫存異動來源` 視圖定義所有影響庫存的單據與正負號；觸發程序把受影響單據丟給 `sp_庫存異動_同步` 重建 `庫存異動明細` 與 `每日庫存餘額`，負庫存 THROW。新增影響庫存的單據時：加入該視圖 UNION + 寫明細/主檔觸發程序。
- **API**：`api_儲存` 以 `同步請求紀錄` 做冪等；表頭單一主鍵且 `功能表.單號前綴` 有值時自動編號（前綴+yyyyMMdd+3碼）；明細項次空白自動編 0010、0020…；未送出的舊明細刪除。
- **唯讀欄位**：由觸發程序回寫的欄位登錄於 `欄位設定`，前端不送出。`功能表.明細唯讀=1` 時不合併明細（生產工單明細由 BOM 展開）。

## 驗證準則（`sp_驗證` 必須全數通過）
過帳 6 條累加一致；每日庫存餘額逐列 `期初+本期入庫-本期出庫=期末`；每日供需餘額逐列 `在手+供給入庫-需求入庫=可用`。改動邏輯後務必跑 `npm test`（有示範資料時）或 `npm run db:reset && npm run seed`。

## 工作流程
- 線上部署：Render（`render.yaml` Blueprint），push 到 main 自動重新部署；DB 帳密在 Render 環境變數。
- Repo：https://github.com/NellioTech/mini-erp（公開，勿提交 .env）；版本以 git tag `vX.Y.Z` 標記。
- 每完成一個段落：更新 README.md / CLAUDE.md / SKILL.md / AGENT.md → commit → push 到 GitHub，並回報 repo 與 release 連結。
- 新增功能的步驟見 `SKILL.md`。
