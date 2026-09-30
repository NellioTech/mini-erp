/* ============================================================
   03 商業邏輯：庫存同步程序 + 各單據觸發程序
   ============================================================ */

/* 依單據清單重建 庫存異動明細，並重算受影響 倉庫/物料 的 每日庫存餘額；不允許負庫存 */
CREATE OR ALTER PROCEDURE sp_庫存異動_同步 @單據 dbo.單據清單 READONLY
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @影響 TABLE (倉庫代碼 nvarchar(20), 物料編號 nvarchar(20));
    DECLARE @msg nvarchar(2000);

    SELECT @msg = N'倉庫不屬於單據工廠：' + STRING_AGG(CONCAT(v.單據編號, N'/', v.單據項次, N' 倉庫 ', v.倉庫代碼), N'；')
    FROM 庫存異動來源 v
    JOIN (SELECT DISTINCT 異動類型, 單據編號 FROM @單據) s ON s.異動類型 = v.異動類型 AND s.單據編號 = v.單據編號
    JOIN 工廠倉庫維護 w ON w.倉庫代碼 = v.倉庫代碼
    WHERE v.單據工廠 IS NOT NULL AND v.單據工廠 <> w.工廠代碼;
    IF @msg IS NOT NULL THROW 50010, @msg, 1;

    DELETE m OUTPUT deleted.倉庫代碼, deleted.物料編號 INTO @影響
    FROM 庫存異動明細 m
    JOIN (SELECT DISTINCT 異動類型, 單據編號 FROM @單據) s ON s.異動類型 = m.異動類型 AND s.單據編號 = m.單據編號;

    INSERT 庫存異動明細 (異動日期, 異動類型, 單據編號, 單據項次, 參考編號, 工廠代碼, 倉庫代碼, 物料編號, 異動數量, 備註說明)
    OUTPUT inserted.倉庫代碼, inserted.物料編號 INTO @影響
    SELECT v.異動日期, v.異動類型, v.單據編號, v.單據項次, v.參考編號, w.工廠代碼, v.倉庫代碼, v.物料編號, v.異動數量, v.備註說明
    FROM 庫存異動來源 v
    JOIN (SELECT DISTINCT 異動類型, 單據編號 FROM @單據) s ON s.異動類型 = v.異動類型 AND s.單據編號 = v.單據編號
    JOIN 工廠倉庫維護 w ON w.倉庫代碼 = v.倉庫代碼;

    DELETE b FROM 每日庫存餘額 b
    WHERE EXISTS (SELECT 1 FROM @影響 a WHERE a.倉庫代碼 = b.倉庫代碼 AND a.物料編號 = b.物料編號);

    INSERT 每日庫存餘額 (餘額日期, 工廠代碼, 物料編號, 倉庫代碼, 期初數量, 本期入庫, 本期出庫, 期末數量)
    SELECT 異動日期, 工廠代碼, 物料編號, 倉庫代碼, 累計 - 入庫 + 出庫, 入庫, 出庫, 累計
    FROM (SELECT *, SUM(入庫 - 出庫) OVER (PARTITION BY 物料編號, 倉庫代碼 ORDER BY 異動日期 ROWS UNBOUNDED PRECEDING) AS 累計
          FROM (SELECT m.異動日期, MAX(m.工廠代碼) AS 工廠代碼, m.倉庫代碼, m.物料編號,
                       SUM(IIF(m.異動數量 > 0,  m.異動數量, 0)) AS 入庫,
                       SUM(IIF(m.異動數量 < 0, -m.異動數量, 0)) AS 出庫
                FROM 庫存異動明細 m
                WHERE EXISTS (SELECT 1 FROM @影響 a WHERE a.倉庫代碼 = m.倉庫代碼 AND a.物料編號 = m.物料編號)
                GROUP BY m.異動日期, m.倉庫代碼, m.物料編號) x) y;

    SELECT @msg = N'庫存不足：' + STRING_AGG(CONCAT(倉庫代碼, N'/', 物料編號, N' 於 ', CONVERT(char(10), 餘額日期, 23), N' 期末 ', 期末數量), N'；')
    FROM (SELECT TOP (5) b.* FROM 每日庫存餘額 b
          WHERE b.期末數量 < 0
            AND EXISTS (SELECT 1 FROM @影響 a WHERE a.倉庫代碼 = b.倉庫代碼 AND a.物料編號 = b.物料編號)
          ORDER BY b.餘額日期) x;
    IF @msg IS NOT NULL THROW 50011, @msg, 1;
END
GO

/* ================= SD ================= */
CREATE OR ALTER TRIGGER tr_訂單出貨明細 ON 訂單出貨明細 AFTER INSERT, UPDATE, DELETE AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM inserted) AND NOT EXISTS (SELECT 1 FROM deleted) RETURN;
    IF EXISTS (SELECT 1 FROM inserted i
               JOIN 訂單出貨主檔 h ON h.出貨編號 = i.出貨編號
               JOIN 客戶訂單主檔 o ON o.訂單編號 = i.訂單編號
               WHERE h.客戶編號 <> o.客戶編號)
        THROW 50001, N'出貨單客戶與訂單客戶不一致', 1;

    UPDATE d SET 出貨數量 = ISNULL((SELECT SUM(x.出貨數量) FROM 訂單出貨明細 x
                                    WHERE x.訂單編號 = d.訂單編號 AND x.訂單項次 = d.訂單項次), 0)
    FROM 客戶訂單明細 d
    JOIN (SELECT 訂單編號, 訂單項次 FROM inserted UNION SELECT 訂單編號, 訂單項次 FROM deleted) k
      ON k.訂單編號 = d.訂單編號 AND k.訂單項次 = d.訂單項次;

    DECLARE @單據 dbo.單據清單;
    INSERT @單據 SELECT N'訂單出貨', 出貨編號 FROM inserted UNION SELECT N'訂單出貨', 出貨編號 FROM deleted;
    EXEC sp_庫存異動_同步 @單據;
END
GO
CREATE OR ALTER TRIGGER tr_訂單出貨主檔 ON 訂單出貨主檔 AFTER UPDATE AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM inserted h
               JOIN 訂單出貨明細 i ON i.出貨編號 = h.出貨編號
               JOIN 客戶訂單主檔 o ON o.訂單編號 = i.訂單編號
               WHERE h.客戶編號 <> o.客戶編號)
        THROW 50001, N'出貨單客戶與訂單客戶不一致', 1;
    DECLARE @單據 dbo.單據清單;
    INSERT @單據 SELECT N'訂單出貨', 出貨編號 FROM inserted;
    EXEC sp_庫存異動_同步 @單據;
END
GO
CREATE OR ALTER TRIGGER tr_出貨退回明細 ON 出貨退回明細 AFTER INSERT, UPDATE, DELETE AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM inserted) AND NOT EXISTS (SELECT 1 FROM deleted) RETURN;
    IF EXISTS (SELECT 1 FROM inserted i
               JOIN 出貨退回主檔 h ON h.退回編號 = i.退回編號
               JOIN 客戶訂單主檔 o ON o.訂單編號 = i.訂單編號
               WHERE h.客戶編號 <> o.客戶編號)
        THROW 50002, N'退回單客戶與訂單客戶不一致', 1;

    UPDATE d SET 退回數量 = ISNULL((SELECT SUM(x.退回數量) FROM 出貨退回明細 x
                                    WHERE x.訂單編號 = d.訂單編號 AND x.訂單項次 = d.訂單項次), 0)
    FROM 客戶訂單明細 d
    JOIN (SELECT 訂單編號, 訂單項次 FROM inserted UNION SELECT 訂單編號, 訂單項次 FROM deleted) k
      ON k.訂單編號 = d.訂單編號 AND k.訂單項次 = d.訂單項次;

    DECLARE @單據 dbo.單據清單;
    INSERT @單據 SELECT N'出貨退回', 退回編號 FROM inserted UNION SELECT N'出貨退回', 退回編號 FROM deleted;
    EXEC sp_庫存異動_同步 @單據;
END
GO
CREATE OR ALTER TRIGGER tr_出貨退回主檔 ON 出貨退回主檔 AFTER UPDATE AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM inserted h
               JOIN 出貨退回明細 i ON i.退回編號 = h.退回編號
               JOIN 客戶訂單主檔 o ON o.訂單編號 = i.訂單編號
               WHERE h.客戶編號 <> o.客戶編號)
        THROW 50002, N'退回單客戶與訂單客戶不一致', 1;
    DECLARE @單據 dbo.單據清單;
    INSERT @單據 SELECT N'出貨退回', 退回編號 FROM inserted;
    EXEC sp_庫存異動_同步 @單據;
END
GO

/* ================= MM ================= */
CREATE OR ALTER TRIGGER tr_採購收貨明細 ON 採購收貨明細 AFTER INSERT, UPDATE, DELETE AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM inserted) AND NOT EXISTS (SELECT 1 FROM deleted) RETURN;
    IF EXISTS (SELECT 1 FROM inserted i
               JOIN 採購收貨主檔 h ON h.收貨編號 = i.收貨編號
               JOIN 廠商採購主檔 o ON o.採購編號 = i.採購編號
               WHERE h.廠商編號 <> o.廠商編號)
        THROW 50003, N'收貨單廠商與採購單廠商不一致', 1;

    UPDATE d SET 收貨數量 = ISNULL((SELECT SUM(x.收貨數量) FROM 採購收貨明細 x
                                    WHERE x.採購編號 = d.採購編號 AND x.採購項次 = d.採購項次), 0)
    FROM 廠商採購明細 d
    JOIN (SELECT 採購編號, 採購項次 FROM inserted UNION SELECT 採購編號, 採購項次 FROM deleted) k
      ON k.採購編號 = d.採購編號 AND k.採購項次 = d.採購項次;

    DECLARE @單據 dbo.單據清單;
    INSERT @單據 SELECT N'採購收貨', 收貨編號 FROM inserted UNION SELECT N'採購收貨', 收貨編號 FROM deleted;
    EXEC sp_庫存異動_同步 @單據;
END
GO
CREATE OR ALTER TRIGGER tr_採購收貨主檔 ON 採購收貨主檔 AFTER UPDATE AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM inserted h
               JOIN 採購收貨明細 i ON i.收貨編號 = h.收貨編號
               JOIN 廠商採購主檔 o ON o.採購編號 = i.採購編號
               WHERE h.廠商編號 <> o.廠商編號)
        THROW 50003, N'收貨單廠商與採購單廠商不一致', 1;
    DECLARE @單據 dbo.單據清單;
    INSERT @單據 SELECT N'採購收貨', 收貨編號 FROM inserted;
    EXEC sp_庫存異動_同步 @單據;
END
GO
CREATE OR ALTER TRIGGER tr_收貨退回明細 ON 收貨退回明細 AFTER INSERT, UPDATE, DELETE AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM inserted) AND NOT EXISTS (SELECT 1 FROM deleted) RETURN;
    IF EXISTS (SELECT 1 FROM inserted i
               JOIN 收貨退回主檔 h ON h.退回編號 = i.退回編號
               JOIN 廠商採購主檔 o ON o.採購編號 = i.採購編號
               WHERE h.廠商編號 <> o.廠商編號)
        THROW 50004, N'退回單廠商與採購單廠商不一致', 1;

    UPDATE d SET 退回數量 = ISNULL((SELECT SUM(x.退回數量) FROM 收貨退回明細 x
                                    WHERE x.採購編號 = d.採購編號 AND x.採購項次 = d.採購項次), 0)
    FROM 廠商採購明細 d
    JOIN (SELECT 採購編號, 採購項次 FROM inserted UNION SELECT 採購編號, 採購項次 FROM deleted) k
      ON k.採購編號 = d.採購編號 AND k.採購項次 = d.採購項次;

    DECLARE @單據 dbo.單據清單;
    INSERT @單據 SELECT N'收貨退回', 退回編號 FROM inserted UNION SELECT N'收貨退回', 退回編號 FROM deleted;
    EXEC sp_庫存異動_同步 @單據;
END
GO
CREATE OR ALTER TRIGGER tr_收貨退回主檔 ON 收貨退回主檔 AFTER UPDATE AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM inserted h
               JOIN 收貨退回明細 i ON i.退回編號 = h.退回編號
               JOIN 廠商採購主檔 o ON o.採購編號 = i.採購編號
               WHERE h.廠商編號 <> o.廠商編號)
        THROW 50004, N'退回單廠商與採購單廠商不一致', 1;
    DECLARE @單據 dbo.單據清單;
    INSERT @單據 SELECT N'收貨退回', 退回編號 FROM inserted;
    EXEC sp_庫存異動_同步 @單據;
END
GO

/* ================= IM ================= */
CREATE OR ALTER TRIGGER tr_庫存領用明細 ON 庫存領用明細 AFTER INSERT, UPDATE, DELETE AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM inserted) AND NOT EXISTS (SELECT 1 FROM deleted) RETURN;
    DECLARE @單據 dbo.單據清單;
    INSERT @單據 SELECT N'庫存領用', 領用編號 FROM inserted UNION SELECT N'庫存領用', 領用編號 FROM deleted;
    EXEC sp_庫存異動_同步 @單據;
END
GO
CREATE OR ALTER TRIGGER tr_庫存領用主檔 ON 庫存領用主檔 AFTER UPDATE AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @單據 dbo.單據清單;
    INSERT @單據 SELECT N'庫存領用', 領用編號 FROM inserted;
    EXEC sp_庫存異動_同步 @單據;
END
GO
CREATE OR ALTER TRIGGER tr_庫存繳庫明細 ON 庫存繳庫明細 AFTER INSERT, UPDATE, DELETE AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM inserted) AND NOT EXISTS (SELECT 1 FROM deleted) RETURN;
    DECLARE @單據 dbo.單據清單;
    INSERT @單據 SELECT N'庫存繳庫', 繳庫編號 FROM inserted UNION SELECT N'庫存繳庫', 繳庫編號 FROM deleted;
    EXEC sp_庫存異動_同步 @單據;
END
GO
CREATE OR ALTER TRIGGER tr_庫存繳庫主檔 ON 庫存繳庫主檔 AFTER UPDATE AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @單據 dbo.單據清單;
    INSERT @單據 SELECT N'庫存繳庫', 繳庫編號 FROM inserted;
    EXEC sp_庫存異動_同步 @單據;
END
GO

/* ================= PP ================= */
/* 工單建立或改生產品項/數量時，依用量清單自動展開 生產工單明細 */
CREATE OR ALTER TRIGGER tr_生產工單主檔 ON 生產工單主檔 AFTER INSERT, UPDATE AS
BEGIN
    SET NOCOUNT ON;
    IF NOT (UPDATE(物料編號) OR UPDATE(生產數量) OR UPDATE(工單日期)) RETURN;

    DELETE d FROM 生產工單明細 d
    JOIN inserted w ON w.工單編號 = d.工單編號
    WHERE d.已領用量 = 0
      AND NOT EXISTS (SELECT 1 FROM 用量清單維護 b WHERE b.主階編號 = w.物料編號 AND b.子階編號 = d.物料編號);

    UPDATE d SET 應領用量 = b.標準用量 * w.生產數量
    FROM 生產工單明細 d
    JOIN inserted w ON w.工單編號 = d.工單編號
    JOIN 用量清單維護 b ON b.主階編號 = w.物料編號 AND b.子階編號 = d.物料編號;

    INSERT 生產工單明細 (工單編號, 工單項次, 物料編號, 應領用量, 預定領料)
    SELECT w.工單編號,
           RIGHT(N'0000' + CAST(ISNULL((SELECT MAX(TRY_CAST(x.工單項次 AS int)) FROM 生產工單明細 x WHERE x.工單編號 = w.工單編號), 0)
                               + 10 * ROW_NUMBER() OVER (PARTITION BY w.工單編號 ORDER BY b.子階編號) AS nvarchar(10)), 4),
           b.子階編號, b.標準用量 * w.生產數量, w.工單日期
    FROM inserted w
    JOIN 用量清單維護 b ON b.主階編號 = w.物料編號
    WHERE NOT EXISTS (SELECT 1 FROM 生產工單明細 d WHERE d.工單編號 = w.工單編號 AND d.物料編號 = b.子階編號);
END
GO
CREATE OR ALTER TRIGGER tr_工單領料明細 ON 工單領料明細 AFTER INSERT, UPDATE, DELETE AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM inserted) AND NOT EXISTS (SELECT 1 FROM deleted) RETURN;
    IF EXISTS (SELECT 1 FROM inserted i
               JOIN 工單領料主檔 h ON h.領料編號 = i.領料編號
               JOIN 生產工單主檔 w ON w.工單編號 = i.工單編號
               WHERE h.工廠代碼 <> w.工廠代碼)
        THROW 50005, N'領料單工廠與工單工廠不一致', 1;

    UPDATE d SET 已領用量 = ISNULL((SELECT SUM(x.領料數量) FROM 工單領料明細 x
                                    WHERE x.工單編號 = d.工單編號 AND x.物料編號 = d.物料編號), 0)
    FROM 生產工單明細 d
    JOIN (SELECT 工單編號, 物料編號 FROM inserted UNION SELECT 工單編號, 物料編號 FROM deleted) k
      ON k.工單編號 = d.工單編號 AND k.物料編號 = d.物料編號;

    DECLARE @單據 dbo.單據清單;
    INSERT @單據 SELECT N'工單領料', 領料編號 FROM inserted UNION SELECT N'工單領料', 領料編號 FROM deleted;
    EXEC sp_庫存異動_同步 @單據;
END
GO
CREATE OR ALTER TRIGGER tr_工單領料主檔 ON 工單領料主檔 AFTER UPDATE AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @單據 dbo.單據清單;
    INSERT @單據 SELECT N'工單領料', 領料編號 FROM inserted;
    EXEC sp_庫存異動_同步 @單據;
END
GO
CREATE OR ALTER TRIGGER tr_工單入庫明細 ON 工單入庫明細 AFTER INSERT, UPDATE, DELETE AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM inserted) AND NOT EXISTS (SELECT 1 FROM deleted) RETURN;
    IF EXISTS (SELECT 1 FROM inserted i
               JOIN 工單入庫主檔 h ON h.入庫編號 = i.入庫編號
               JOIN 生產工單主檔 w ON w.工單編號 = i.工單編號
               WHERE h.工廠代碼 <> w.工廠代碼)
        THROW 50006, N'入庫單工廠與工單工廠不一致', 1;

    UPDATE w SET 入庫數量 = ISNULL((SELECT SUM(x.入庫數量) FROM 工單入庫明細 x WHERE x.工單編號 = w.工單編號), 0)
    FROM 生產工單主檔 w
    JOIN (SELECT 工單編號 FROM inserted UNION SELECT 工單編號 FROM deleted) k ON k.工單編號 = w.工單編號;

    DECLARE @單據 dbo.單據清單;
    INSERT @單據 SELECT N'工單入庫', 入庫編號 FROM inserted UNION SELECT N'工單入庫', 入庫編號 FROM deleted;
    EXEC sp_庫存異動_同步 @單據;
END
GO
CREATE OR ALTER TRIGGER tr_工單入庫主檔 ON 工單入庫主檔 AFTER UPDATE AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @單據 dbo.單據清單;
    INSERT @單據 SELECT N'工單入庫', 入庫編號 FROM inserted;
    EXEC sp_庫存異動_同步 @單據;
END
GO
