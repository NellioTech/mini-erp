/* ============================================================
   06 驗證準則：EXEC sp_驗證 → 每條規則的違反筆數（全部 0 才算通過）
   ============================================================ */
CREATE OR ALTER PROCEDURE sp_驗證
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @r TABLE (序 int, 規則 nvarchar(100), 違反筆數 int, 範例 nvarchar(400));

    INSERT @r SELECT 1, N'訂單出貨明細.出貨數量 依 訂單編號+訂單項次 累加到 客戶訂單明細.出貨數量', COUNT(*), MIN(CONCAT(訂單編號, N'/', 訂單項次))
    FROM 客戶訂單明細 d
    WHERE d.出貨數量 <> ISNULL((SELECT SUM(x.出貨數量) FROM 訂單出貨明細 x WHERE x.訂單編號 = d.訂單編號 AND x.訂單項次 = d.訂單項次), 0);

    INSERT @r SELECT 2, N'出貨退回明細.退回數量 依 訂單編號+訂單項次 累加到 客戶訂單明細.退回數量', COUNT(*), MIN(CONCAT(訂單編號, N'/', 訂單項次))
    FROM 客戶訂單明細 d
    WHERE d.退回數量 <> ISNULL((SELECT SUM(x.退回數量) FROM 出貨退回明細 x WHERE x.訂單編號 = d.訂單編號 AND x.訂單項次 = d.訂單項次), 0);

    INSERT @r SELECT 3, N'採購收貨明細.收貨數量 依 採購編號+採購項次 累加到 廠商採購明細.收貨數量', COUNT(*), MIN(CONCAT(採購編號, N'/', 採購項次))
    FROM 廠商採購明細 d
    WHERE d.收貨數量 <> ISNULL((SELECT SUM(x.收貨數量) FROM 採購收貨明細 x WHERE x.採購編號 = d.採購編號 AND x.採購項次 = d.採購項次), 0);

    INSERT @r SELECT 4, N'收貨退回明細.退回數量 依 採購編號+採購項次 累加到 廠商採購明細.退回數量', COUNT(*), MIN(CONCAT(採購編號, N'/', 採購項次))
    FROM 廠商採購明細 d
    WHERE d.退回數量 <> ISNULL((SELECT SUM(x.退回數量) FROM 收貨退回明細 x WHERE x.採購編號 = d.採購編號 AND x.採購項次 = d.採購項次), 0);

    INSERT @r SELECT 5, N'工單入庫明細.入庫數量 依 工單編號 累加到 生產工單主檔.入庫數量', COUNT(*), MIN(工單編號)
    FROM 生產工單主檔 w
    WHERE w.入庫數量 <> ISNULL((SELECT SUM(x.入庫數量) FROM 工單入庫明細 x WHERE x.工單編號 = w.工單編號), 0);

    INSERT @r SELECT 6, N'工單領料明細.領料數量 依 工單編號+物料編號 累加到 生產工單明細.已領用量', COUNT(*), MIN(CONCAT(工單編號, N'/', 物料編號))
    FROM 生產工單明細 d
    WHERE d.已領用量 <> ISNULL((SELECT SUM(x.領料數量) FROM 工單領料明細 x WHERE x.工單編號 = d.工單編號 AND x.物料編號 = d.物料編號), 0);

    INSERT @r SELECT 7, N'每日庫存餘額：期初數量 + 本期入庫 - 本期出庫 = 期末數量', COUNT(*), MIN(CONCAT(物料編號, N'/', 倉庫代碼, N'/', 餘額日期))
    FROM 每日庫存餘額 WHERE 期初數量 + 本期入庫 - 本期出庫 <> 期末數量;

    INSERT @r SELECT 8, N'每日庫存餘額：期初數量 = 前一日期末數量（首日為 0）', COUNT(*), MIN(CONCAT(物料編號, N'/', 倉庫代碼, N'/', 餘額日期))
    FROM (SELECT *, LAG(期末數量, 1, 0) OVER (PARTITION BY 物料編號, 倉庫代碼 ORDER BY 餘額日期) AS 前期末 FROM 每日庫存餘額) x
    WHERE 期初數量 <> 前期末;

    INSERT @r SELECT 9, N'每日庫存餘額：最後期末數量 = 庫存異動明細合計', COUNT(*), MIN(CONCAT(物料編號, N'/', 倉庫代碼))
    FROM (SELECT 物料編號, 倉庫代碼, SUM(異動數量) AS 合計 FROM 庫存異動明細 GROUP BY 物料編號, 倉庫代碼) m
    WHERE m.合計 <> ISNULL((SELECT TOP (1) b.期末數量 FROM 每日庫存餘額 b WHERE b.物料編號 = m.物料編號 AND b.倉庫代碼 = m.倉庫代碼 ORDER BY b.餘額日期 DESC), 0);

    INSERT @r SELECT 10, N'每日供需餘額：在手數量 + 供給入庫 - 需求入庫 = 可用數量', COUNT(*), MIN(CONCAT(物料編號, N'/', 工廠代碼, N'/', 日期))
    FROM 每日供需餘額 WHERE 在手數量 + 供給入庫 - 需求入庫 <> 可用數量;

    INSERT @r SELECT 11, N'每日供需餘額：在手數量 = 前一列可用數量（首列為今日在手庫存）', COUNT(*), MIN(CONCAT(物料編號, N'/', 工廠代碼, N'/', 日期))
    FROM (SELECT *, LAG(可用數量) OVER (PARTITION BY 物料編號, 工廠代碼 ORDER BY 日期) AS 前可用,
                 ROW_NUMBER() OVER (PARTITION BY 物料編號, 工廠代碼 ORDER BY 日期) AS rn
          FROM 每日供需餘額) x
    WHERE (rn > 1 AND 在手數量 <> 前可用)
       OR (rn = 1 AND 在手數量 <> ISNULL((SELECT SUM(m.異動數量) FROM 庫存異動明細 m WHERE m.物料編號 = x.物料編號 AND m.工廠代碼 = x.工廠代碼), 0));

    SELECT 序, 規則, 違反筆數, 範例, IIF(違反筆數 = 0, N'通過', N'失敗') AS 結果 FROM @r ORDER BY 序;
END
GO
