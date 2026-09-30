---
name: erp-tsql-feature
description: 在本 ERP 專案新增或修改功能（維護畫面、單據、過帳規則、報表、樞紐分析）時使用。說明如何只用 T-SQL 物件完成，讓前端自動產生畫面。
---

# 以 T-SQL 新增 ERP 功能

前端完全由資料庫中繼資料驅動，**新增功能通常不需要改任何 JS**。

## A. 新增主數據 / 組織維護畫面
1. `db/01_tables.sql`：建表，必須有 `PRIMARY KEY`；參照其他主檔用單欄 `FOREIGN KEY`（前端自動變下拉）。
2. `db/04_menu.sql`：`功能表` 加一列，`類型=N'維護'`、`主檔=表名`、`明細檔=NULL`。
3. 既有資料庫：另寫 ALTER/CREATE 腳本執行，或 `npm run db:reset`（清資料）。然後 `npm run db`。

## B. 新增單據（主檔 + 明細）
1. 主檔單欄主鍵 `xx編號`；明細主鍵 `(xx編號, xx項次 nvarchar(04))`，明細對主檔 `FK ... ON DELETE CASCADE`。
2. `功能表`：`主檔`、`明細檔`、`單號前綴`（2 碼，自動編號用）。
3. 數量上限用 CHECK，約束命名 `CK_表名_說明文字`（錯誤訊息會顯示說明文字）。
4. 參照來源單據明細用複合 FK（例：`(訂單編號, 訂單項次, 物料編號)` → 來源表的 UNIQUE），確保物料一致。

## C. 新增過帳規則
在來源明細表寫 `AFTER INSERT, UPDATE, DELETE` 觸發程序：
```sql
UPDATE d SET 目標數量 = ISNULL((SELECT SUM(x.數量) FROM 來源明細 x WHERE x.鍵 = d.鍵), 0)
FROM 目標表 d JOIN (SELECT 鍵 FROM inserted UNION SELECT 鍵 FROM deleted) k ON k.鍵 = d.鍵;
```
- 一律「重算 SUM」而非增量，並把目標欄位加入 `欄位設定`（唯讀）。
- 若影響庫存：`庫存異動來源` 視圖加一段 UNION ALL（入庫正、出庫負），觸發程序收集單號呼叫 `sp_庫存異動_同步`；主檔也要 `AFTER UPDATE` 觸發程序（日期變更）。
- 在 `db/06_verify.sql` 的 `sp_驗證` 加一條對應檢查。

## D. 新增報表
- 無輸入條件：建視圖，`功能表` 加 `類型=N'報表'`、`主檔=視圖名`。
- 需輸入條件（年度、日期…）：建 **inline 表值函數**，參數即畫面輸入欄，名稱 `年度` 會預填今年。
- 樞紐：函數內用 `PIVOT`，參考 `訂單出退樞紐`。

## E. 完成檢查
```bash
npm run db && npm test            # 或 npm run db:reset && npm run seed
```
更新 README.md / CLAUDE.md / AGENT.md，commit 並 push 到 GitHub，回報連結。
