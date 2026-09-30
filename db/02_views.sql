/* ============================================================
   02 視圖：系統中繼資料、庫存異動來源、報表
   ============================================================ */

/* 前端依此自動產生畫面：欄位、型別、主鍵、下拉參照、唯讀 */
CREATE OR ALTER VIEW 系統欄位 AS
SELECT o.name AS 表名,
       c.name AS 欄位名,
       c.column_id AS 順序,
       t.name AS 型別,
       CASE WHEN t.name IN ('nvarchar','nchar') THEN c.max_length / 2
            WHEN t.name IN ('varchar','char')   THEN c.max_length END AS 長度,
       t.name + CASE WHEN t.name IN ('nvarchar','nchar') THEN '(' + IIF(c.max_length = -1, 'max', CAST(c.max_length / 2 AS varchar(10))) + ')'
                     WHEN t.name IN ('varchar','char')   THEN '(' + IIF(c.max_length = -1, 'max', CAST(c.max_length AS varchar(10))) + ')'
                     WHEN t.name IN ('decimal','numeric') THEN '(' + CAST(c.precision AS varchar(3)) + ',' + CAST(c.scale AS varchar(3)) + ')'
                     ELSE '' END AS SQL型別,
       c.is_nullable AS 可空,
       CAST(IIF(pk.column_id IS NULL, 0, 1) AS bit) AS 主鍵,
       fk.參照表,
       CAST(IIF(c.is_identity = 1 OR c.is_computed = 1 OR r.欄位名 IS NOT NULL OR o.type IN ('V','IF','TF'), 1, 0) AS bit) AS 唯讀
FROM sys.objects o
JOIN sys.columns c ON c.object_id = o.object_id
JOIN sys.types   t ON t.user_type_id = c.user_type_id
LEFT JOIN (SELECT ic.object_id, ic.column_id
           FROM sys.indexes i
           JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
           WHERE i.is_primary_key = 1) pk ON pk.object_id = o.object_id AND pk.column_id = c.column_id
OUTER APPLY (SELECT TOP (1) OBJECT_NAME(f.referenced_object_id) AS 參照表
             FROM sys.foreign_key_columns fc
             JOIN sys.foreign_keys f ON f.object_id = fc.constraint_object_id
             WHERE fc.parent_object_id = o.object_id AND fc.parent_column_id = c.column_id
               AND (SELECT COUNT(*) FROM sys.foreign_key_columns x WHERE x.constraint_object_id = f.object_id) = 1) fk
LEFT JOIN 欄位設定 r ON r.表名 = o.name AND r.欄位名 = c.name AND r.唯讀 = 1
WHERE o.type IN ('U','V','IF','TF') AND o.schema_id = SCHEMA_ID('dbo') AND o.is_ms_shipped = 0;
GO

/* 報表函數的輸入參數（例：年度），前端據此產生查詢條件欄位 */
CREATE OR ALTER VIEW 系統參數 AS
SELECT o.name AS 表名, STUFF(p.name, 1, 1, '') AS 參數名, p.parameter_id AS 順序, t.name AS 型別
FROM sys.objects o
JOIN sys.parameters p ON p.object_id = o.object_id AND p.parameter_id > 0
JOIN sys.types t ON t.user_type_id = p.user_type_id
WHERE o.type IN ('IF','TF') AND o.schema_id = SCHEMA_ID('dbo');
GO

/* 所有影響庫存的單據，正數入庫、負數出庫。庫存異動明細由此同步。 */
CREATE OR ALTER VIEW 庫存異動來源 AS
SELECT N'訂單出貨' AS 異動類型, h.出貨日期 AS 異動日期, CAST(NULL AS nvarchar(20)) AS 單據工廠,
       d.出貨編號 AS 單據編號, d.出貨項次 AS 單據項次, d.訂單編號 AS 參考編號,
       d.物料編號, d.倉庫代碼, -d.出貨數量 AS 異動數量, d.備註說明
FROM 訂單出貨明細 d JOIN 訂單出貨主檔 h ON h.出貨編號 = d.出貨編號
UNION ALL
SELECT N'出貨退回', h.退回日期, NULL, d.退回編號, d.退回項次, d.訂單編號, d.物料編號, d.倉庫代碼, d.退回數量, d.備註說明
FROM 出貨退回明細 d JOIN 出貨退回主檔 h ON h.退回編號 = d.退回編號
UNION ALL
SELECT N'採購收貨', h.收貨日期, NULL, d.收貨編號, d.收貨項次, d.採購編號, d.物料編號, d.倉庫代碼, d.收貨數量, d.備註說明
FROM 採購收貨明細 d JOIN 採購收貨主檔 h ON h.收貨編號 = d.收貨編號
UNION ALL
SELECT N'收貨退回', h.退回日期, NULL, d.退回編號, d.退回項次, d.採購編號, d.物料編號, d.倉庫代碼, -d.退回數量, d.備註說明
FROM 收貨退回明細 d JOIN 收貨退回主檔 h ON h.退回編號 = d.退回編號
UNION ALL
SELECT N'庫存領用', h.領用日期, h.工廠代碼, d.領用編號, d.領用項次, NULL, d.物料編號, d.倉庫代碼, -d.領用數量, d.備註說明
FROM 庫存領用明細 d JOIN 庫存領用主檔 h ON h.領用編號 = d.領用編號
UNION ALL
SELECT N'庫存繳庫', h.繳庫日期, h.工廠代碼, d.繳庫編號, d.繳庫項次, NULL, d.物料編號, d.倉庫代碼, d.繳庫數量, d.備註說明
FROM 庫存繳庫明細 d JOIN 庫存繳庫主檔 h ON h.繳庫編號 = d.繳庫編號
UNION ALL
SELECT N'工單領料', h.領料日期, h.工廠代碼, d.領料編號, d.領料項次, d.工單編號, d.物料編號, d.倉庫代碼, -d.領料數量, d.備註說明
FROM 工單領料明細 d JOIN 工單領料主檔 h ON h.領料編號 = d.領料編號
UNION ALL
SELECT N'工單入庫', h.入庫日期, h.工廠代碼, d.入庫編號, d.入庫項次, d.工單編號, d.物料編號, d.倉庫代碼, d.入庫數量, d.備註說明
FROM 工單入庫明細 d JOIN 工單入庫主檔 h ON h.入庫編號 = d.入庫編號;
GO

/* ---------- SD 報表 ---------- */
CREATE OR ALTER VIEW 已訂未出明細 AS
SELECT d.訂單編號, d.訂單項次, h.訂單日期, h.銷售組織, h.客戶編號, d.物料編號,
       d.訂單數量, d.出貨數量, d.退回數量, d.訂單數量 - d.出貨數量 + d.退回數量 AS 未出數量,
       d.預定交期, d.備註說明
FROM 客戶訂單明細 d JOIN 客戶訂單主檔 h ON h.訂單編號 = d.訂單編號
WHERE d.訂單數量 - d.出貨數量 + d.退回數量 > 0;
GO
CREATE OR ALTER VIEW 訂單出退分析 AS
SELECT N'出貨' AS 類型, h.出貨日期 AS 單據日期, d.出貨編號 AS 單據編號, d.出貨項次 AS 單據項次,
       h.銷售組織, h.客戶編號, d.訂單編號, d.訂單項次, d.物料編號, d.倉庫代碼,
       d.出貨數量 AS 數量, d.出貨數量 AS 淨出貨量, d.備註說明
FROM 訂單出貨明細 d JOIN 訂單出貨主檔 h ON h.出貨編號 = d.出貨編號
UNION ALL
SELECT N'退回', h.退回日期, d.退回編號, d.退回項次,
       h.銷售組織, h.客戶編號, d.訂單編號, d.訂單項次, d.物料編號, d.倉庫代碼,
       d.退回數量, -d.退回數量, d.備註說明
FROM 出貨退回明細 d JOIN 出貨退回主檔 h ON h.退回編號 = d.退回編號;
GO

/* ---------- MM 報表 ---------- */
CREATE OR ALTER VIEW 已採未交明細 AS
SELECT d.採購編號, d.採購項次, h.採購日期, h.採購組織, h.廠商編號, d.物料編號,
       d.採購數量, d.收貨數量, d.退回數量, d.採購數量 - d.收貨數量 + d.退回數量 AS 未交數量,
       d.預定交期, d.備註說明
FROM 廠商採購明細 d JOIN 廠商採購主檔 h ON h.採購編號 = d.採購編號
WHERE d.採購數量 - d.收貨數量 + d.退回數量 > 0;
GO
CREATE OR ALTER VIEW 採購收退分析 AS
SELECT N'收貨' AS 類型, h.收貨日期 AS 單據日期, d.收貨編號 AS 單據編號, d.收貨項次 AS 單據項次,
       h.採購組織, h.廠商編號, d.採購編號, d.採購項次, d.物料編號, d.倉庫代碼,
       d.收貨數量 AS 數量, d.收貨數量 AS 淨收貨量, d.備註說明
FROM 採購收貨明細 d JOIN 採購收貨主檔 h ON h.收貨編號 = d.收貨編號
UNION ALL
SELECT N'退回', h.退回日期, d.退回編號, d.退回項次,
       h.採購組織, h.廠商編號, d.採購編號, d.採購項次, d.物料編號, d.倉庫代碼,
       d.退回數量, -d.退回數量, d.備註說明
FROM 收貨退回明細 d JOIN 收貨退回主檔 h ON h.退回編號 = d.退回編號;
GO

/* ---------- 樞紐分析：輸入年度，縱軸對象、橫軸月份，統計 數量 ---------- */
CREATE OR ALTER FUNCTION 訂單出退樞紐 (@年度 int)
RETURNS TABLE AS RETURN
SELECT 客戶編號,
       ISNULL([1],0) AS [01月], ISNULL([2],0) AS [02月], ISNULL([3],0) AS [03月], ISNULL([4],0) AS [04月],
       ISNULL([5],0) AS [05月], ISNULL([6],0) AS [06月], ISNULL([7],0) AS [07月], ISNULL([8],0) AS [08月],
       ISNULL([9],0) AS [09月], ISNULL([10],0) AS [10月], ISNULL([11],0) AS [11月], ISNULL([12],0) AS [12月],
       ISNULL([1],0)+ISNULL([2],0)+ISNULL([3],0)+ISNULL([4],0)+ISNULL([5],0)+ISNULL([6],0)
      +ISNULL([7],0)+ISNULL([8],0)+ISNULL([9],0)+ISNULL([10],0)+ISNULL([11],0)+ISNULL([12],0) AS 全年合計
FROM (SELECT 客戶編號, MONTH(單據日期) AS 月份, 數量            -- 出貨數量 + 退回數量
      FROM 訂單出退分析 WHERE YEAR(單據日期) = ISNULL(@年度, YEAR(GETDATE()))) s
PIVOT (SUM(數量) FOR 月份 IN ([1],[2],[3],[4],[5],[6],[7],[8],[9],[10],[11],[12])) p;
GO
CREATE OR ALTER FUNCTION 採購收退樞紐 (@年度 int)
RETURNS TABLE AS RETURN
SELECT 廠商編號,
       ISNULL([1],0) AS [01月], ISNULL([2],0) AS [02月], ISNULL([3],0) AS [03月], ISNULL([4],0) AS [04月],
       ISNULL([5],0) AS [05月], ISNULL([6],0) AS [06月], ISNULL([7],0) AS [07月], ISNULL([8],0) AS [08月],
       ISNULL([9],0) AS [09月], ISNULL([10],0) AS [10月], ISNULL([11],0) AS [11月], ISNULL([12],0) AS [12月],
       ISNULL([1],0)+ISNULL([2],0)+ISNULL([3],0)+ISNULL([4],0)+ISNULL([5],0)+ISNULL([6],0)
      +ISNULL([7],0)+ISNULL([8],0)+ISNULL([9],0)+ISNULL([10],0)+ISNULL([11],0)+ISNULL([12],0) AS 全年合計
FROM (SELECT 廠商編號, MONTH(單據日期) AS 月份, 數量            -- 收貨數量 + 退回數量
      FROM 採購收退分析 WHERE YEAR(單據日期) = ISNULL(@年度, YEAR(GETDATE()))) s
PIVOT (SUM(數量) FOR 月份 IN ([1],[2],[3],[4],[5],[6],[7],[8],[9],[10],[11],[12])) p;
GO

/* ---------- PP 報表：未結供給 / 需求（訂單、採購依組織對應工廠） ---------- */
CREATE OR ALTER VIEW 庫存在途明細 AS
SELECT N'供給' AS 供需, N'採購未交' AS 來源, g.工廠代碼, d.採購編號 AS 單據編號, d.採購項次 AS 單據項次,
       d.物料編號, d.預定交期 AS 預定日期, d.採購數量 - d.收貨數量 + d.退回數量 AS 數量
FROM 廠商採購明細 d JOIN 廠商採購主檔 h ON h.採購編號 = d.採購編號 JOIN 採購組織維護 g ON g.採購組織 = h.採購組織
WHERE d.採購數量 - d.收貨數量 + d.退回數量 > 0
UNION ALL
SELECT N'供給', N'工單未入', h.工廠代碼, h.工單編號, N'', h.物料編號, h.預定完工, h.生產數量 - h.入庫數量
FROM 生產工單主檔 h WHERE h.生產數量 - h.入庫數量 > 0
UNION ALL
SELECT N'需求', N'訂單未出', g.工廠代碼, d.訂單編號, d.訂單項次, d.物料編號, d.預定交期, d.訂單數量 - d.出貨數量 + d.退回數量
FROM 客戶訂單明細 d JOIN 客戶訂單主檔 h ON h.訂單編號 = d.訂單編號 JOIN 銷售組織維護 g ON g.銷售組織 = h.銷售組織
WHERE d.訂單數量 - d.出貨數量 + d.退回數量 > 0
UNION ALL
SELECT N'需求', N'物料預留', h.工廠代碼, d.預留編號, d.預留項次, d.物料編號, d.預定交期, d.預留數量
FROM 物料預留明細 d JOIN 物料預留主檔 h ON h.預留編號 = d.預留編號
UNION ALL
SELECT N'需求', N'工單未領', h.工廠代碼, d.工單編號, d.工單項次, d.物料編號, d.預定領料, d.應領用量 - d.已領用量
FROM 生產工單明細 d JOIN 生產工單主檔 h ON h.工單編號 = d.工單編號 WHERE d.應領用量 - d.已領用量 > 0;
GO
/* 逐列：在手數量 + 供給入庫 - 需求入庫 = 可用數量；首列在手 = 今日庫存，之後在手 = 前一列可用；逾期單據併入今日 */
CREATE OR ALTER VIEW 每日供需餘額 AS
WITH 事件 AS (
    SELECT 工廠代碼, 物料編號, CAST(GETDATE() AS date) AS 日期, SUM(異動數量) AS 現有, 0 AS 供給, 0 AS 需求
    FROM 庫存異動明細 GROUP BY 工廠代碼, 物料編號
    UNION ALL
    SELECT ISNULL(工廠代碼, N'(未指定)'), 物料編號,
           IIF(ISNULL(預定日期, '19000101') < CAST(GETDATE() AS date), CAST(GETDATE() AS date), 預定日期),
           0, IIF(供需 = N'供給', 數量, 0), IIF(供需 = N'需求', 數量, 0)
    FROM 庫存在途明細
), 逐日 AS (
    SELECT 工廠代碼, 物料編號, 日期, SUM(現有) AS 現有, SUM(供給) AS 供給入庫, SUM(需求) AS 需求入庫
    FROM 事件 GROUP BY 工廠代碼, 物料編號, 日期
), 累計 AS (
    SELECT *, SUM(現有 + 供給入庫 - 需求入庫) OVER (PARTITION BY 工廠代碼, 物料編號 ORDER BY 日期 ROWS UNBOUNDED PRECEDING) AS 可用數量
    FROM 逐日
)
SELECT 物料編號, 工廠代碼, 日期, 可用數量 - 供給入庫 + 需求入庫 AS 在手數量, 供給入庫, 需求入庫, 可用數量
FROM 累計;
GO
