# AGENT.md

給 AI 代理（Claude Code、Codex、Copilot 等）的專案指引。完整說明見 `CLAUDE.md`，新增功能流程見 `SKILL.md`。

## 專案
ERP 庫存管理系統：SD 訂單、MM 採購、IM 庫存、PP 生產。PWA（`public/`）+ Node 薄轉接（`server.js`）+ SQL Server 2022（`db/`）。

## 規則
1. 商業邏輯只能寫在 SQL Server（約束、觸發程序、視圖、函數、預存程序）。`server.js` 與 `public/app.js` 不加商業邏輯。
2. 資料庫物件、欄位一律繁體中文命名，與規格一致；錯誤訊息以 `THROW 5xxxx, N'中文訊息', 1` 回傳。
3. 前端所有寫入走 `api_儲存` / `api_刪除`，必帶 `請求編號`（冪等、斷線重傳）。
4. 不要把 `.env`（資料庫帳密）加入版控。
5. `npm run db:reset` 會刪除整個資料庫，執行前需確認。

## 驗證
```bash
npm run db      # 部署（可重跑）
npm test        # sp_驗證：過帳累加、每日庫存餘額、每日供需餘額逐列公式，全部需「通過」
```

## 交付
前端靜態檔另由 GitHub Pages（main / root）發佈，後端網址見 `public/env.js`。
線上部署由 `render.yaml`（Render）處理，push main 即自動部署；不要把帳密寫進 render.yaml。
Repo：https://github.com/NellioTech/mini-erp（公開）。版本以 git tag `vX.Y.Z` 標記。
每完成一個段落：更新 README.md / CLAUDE.md / SKILL.md / AGENT.md → commit → push GitHub → 回報 repo 與 release 連結。
