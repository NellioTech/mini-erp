/* ============================================================
   05 API 預存程序：前端只呼叫 api_*，一律回傳單欄 json
   ============================================================ */

/* 將系統錯誤轉成可讀訊息後重拋（須在 CATCH 內呼叫） */
CREATE OR ALTER PROCEDURE sp_錯誤轉譯
AS
BEGIN
    DECLARE @no int = ERROR_NUMBER(), @msg nvarchar(2048) = ERROR_MESSAGE(), @cn sysname, @p1 int, @p2 int;
    IF @no IN (547, 2627, 2601)
    BEGIN
        SET @p1 = CHARINDEX('"', @msg);
        SET @p2 = CHARINDEX('"', @msg, @p1 + 1);
        IF @p1 > 0 AND @p2 > @p1 SET @cn = SUBSTRING(@msg, @p1 + 1, @p2 - @p1 - 1);
        IF @no = 547 AND EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = @cn)
            SELECT @msg = N'資料關聯檢查失敗：' + OBJECT_NAME(f.parent_object_id) + N'（'
                        + (SELECT STRING_AGG(COL_NAME(c.parent_object_id, c.parent_column_id), N'+') FROM sys.foreign_key_columns c WHERE c.constraint_object_id = f.object_id)
                        + N'）須存在於 ' + OBJECT_NAME(f.referenced_object_id) + N'，或資料仍被引用而無法刪改'
            FROM sys.foreign_keys f WHERE f.name = @cn;
        ELSE IF @no = 547 AND @cn LIKE N'CK[_]%'
            SET @msg = N'資料檢查失敗：' + REPLACE(SUBSTRING(@cn, 4, 200), N'_', N' ');
        ELSE IF @no IN (2627, 2601)
            SET @msg = N'資料重複，主鍵已存在（' + ISNULL(@cn, N'') + N'）';
    END
    ELSE IF @no = 515
        SET @msg = N'必填欄位未輸入：' + @msg;
    THROW 50000, @msg, 1;
END
GO

/* 將 JSON 陣列合併進資料表；指定 @範圍欄/@範圍值 時視為單據明細：自動帶入表頭鍵、自動編項次、刪除未送出的項次 */
CREATE OR ALTER PROCEDURE sp_合併JSON
    @表名 sysname, @資料 nvarchar(max), @範圍欄 sysname = NULL, @範圍值 nvarchar(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @with nvarchar(max), @on nvarchar(max), @set nvarchar(max), @icol nvarchar(max), @ival nvarchar(max),
            @項次欄 sysname, @sql nvarchar(max);

    SELECT @with = STRING_AGG(CAST(QUOTENAME(欄位名) + N' ' + SQL型別 + N' ''$."' + 欄位名 + N'"''' AS nvarchar(max)), N',') WITHIN GROUP (ORDER BY 順序),
           @icol = STRING_AGG(CAST(QUOTENAME(欄位名) AS nvarchar(max)), N',') WITHIN GROUP (ORDER BY 順序),
           @ival = STRING_AGG(CAST(N's.' + QUOTENAME(欄位名) AS nvarchar(max)), N',') WITHIN GROUP (ORDER BY 順序)
    FROM 系統欄位 WHERE 表名 = @表名 AND 唯讀 = 0;
    SELECT @on  = STRING_AGG(CAST(N't.' + QUOTENAME(欄位名) + N'=s.' + QUOTENAME(欄位名) AS nvarchar(max)), N' AND ')
    FROM 系統欄位 WHERE 表名 = @表名 AND 主鍵 = 1;
    SELECT @set = STRING_AGG(CAST(N't.' + QUOTENAME(欄位名) + N'=s.' + QUOTENAME(欄位名) AS nvarchar(max)), N',')
    FROM 系統欄位 WHERE 表名 = @表名 AND 主鍵 = 0 AND 唯讀 = 0;
    IF @with IS NULL OR @on IS NULL THROW 50200, N'資料表不可維護', 1;

    SET @sql = N'SELECT CAST(j.[key] AS int) AS _序, s.* INTO #s FROM OPENJSON(@資料) j CROSS APPLY OPENJSON(j.value) WITH (' + @with + N') s;';

    IF @範圍欄 IS NOT NULL
    BEGIN
        SELECT @項次欄 = 欄位名 FROM 系統欄位 WHERE 表名 = @表名 AND 主鍵 = 1 AND 欄位名 <> @範圍欄;
        SET @sql += N'
UPDATE #s SET ' + QUOTENAME(@範圍欄) + N' = @範圍值;
DECLARE @m int = ISNULL((SELECT MAX(v) FROM (SELECT TRY_CAST(' + QUOTENAME(@項次欄) + N' AS int) AS v FROM ' + QUOTENAME(@表名) + N' WHERE ' + QUOTENAME(@範圍欄) + N' = @範圍值
                                             UNION ALL SELECT TRY_CAST(' + QUOTENAME(@項次欄) + N' AS int) FROM #s) x), 0);
WITH n AS (SELECT ' + QUOTENAME(@項次欄) + N' AS 項次, ROW_NUMBER() OVER (ORDER BY _序) AS rn FROM #s WHERE NULLIF(LTRIM(' + QUOTENAME(@項次欄) + N'), N'''') IS NULL)
UPDATE n SET 項次 = RIGHT(N''0000'' + CAST(@m + rn * 10 AS nvarchar(10)), 4);';
    END

    SET @sql += N'
MERGE ' + QUOTENAME(@表名) + N' AS t USING #s AS s ON ' + @on
        + ISNULL(N' WHEN MATCHED THEN UPDATE SET ' + @set, N'')
        + N' WHEN NOT MATCHED BY TARGET THEN INSERT (' + @icol + N') VALUES (' + @ival + N')'
        + IIF(@範圍欄 IS NULL, N'', N' WHEN NOT MATCHED BY SOURCE AND t.' + QUOTENAME(@範圍欄) + N' = @範圍值 THEN DELETE')
        + N';';

    EXEC sp_executesql @sql, N'@資料 nvarchar(max), @範圍值 nvarchar(20)', @資料, @範圍值;
END
GO

/* 主功能表：模組 > 分類 > 功能 */
CREATE OR ALTER PROCEDURE api_功能表
AS
BEGIN
    SET NOCOUNT ON;
    SELECT (
        SELECT m.模組, m.模組名稱,
               (SELECT c.分類,
                       (SELECT f.功能代碼, f.功能名稱, f.類型 FROM 功能表 f
                        WHERE f.模組 = m.模組 AND f.分類 = c.分類 ORDER BY f.排序 FOR JSON PATH) AS 功能
                FROM (SELECT 分類, MIN(排序) AS s FROM 功能表 WHERE 模組 = m.模組 GROUP BY 分類) c
                ORDER BY c.s FOR JSON PATH) AS 分類清單
        FROM (SELECT 模組, 模組名稱, MIN(排序) AS s FROM 功能表 GROUP BY 模組, 模組名稱) m
        ORDER BY m.s FOR JSON PATH
    ) AS json;
END
GO

/* 功能定義：欄位、型別、主鍵、參照、唯讀 → 前端據此自動產生表單 */
CREATE OR ALTER PROCEDURE api_功能定義 @功能代碼 nvarchar(20)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT (
        SELECT f.功能代碼, f.模組名稱, f.分類, f.功能名稱, f.類型, f.主檔, f.明細檔, f.明細唯讀, f.單號前綴,
               (SELECT 欄位名, 型別, 長度, 可空, 主鍵, 參照表, 唯讀 FROM 系統欄位 WHERE 表名 = f.主檔 ORDER BY 順序 FOR JSON PATH) AS 主檔欄位,
               (SELECT 欄位名, 型別, 長度, 可空, 主鍵, 參照表, 唯讀 FROM 系統欄位 WHERE 表名 = f.明細檔 ORDER BY 順序 FOR JSON PATH) AS 明細欄位,
               (SELECT 參數名, 型別 FROM 系統參數 WHERE 表名 = f.主檔 ORDER BY 順序 FOR JSON PATH) AS 參數欄位,
               (SELECT l.層級, l.來源, l.標題,
                       (SELECT 欄位名, 型別 FROM 系統欄位 WHERE 表名 = l.來源 ORDER BY 順序 FOR JSON PATH) AS 欄位
                FROM 報表層級 l WHERE l.功能代碼 = f.功能代碼 ORDER BY l.層級 FOR JSON PATH) AS 層級,
               JSON_QUERY((SELECT r.來源, r.標題,
                       (SELECT 欄位名, 型別 FROM 系統欄位 WHERE 表名 = r.來源 ORDER BY 順序 FOR JSON PATH) AS 欄位
                FROM 明細參照 r WHERE r.功能代碼 = f.功能代碼 FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)) AS 參照
        FROM 功能表 f WHERE f.功能代碼 = @功能代碼
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    ) AS json;
END
GO

/* 查詢：無 @主鍵 → 清單（可關鍵字；報表函數以 @參數 JSON 傳入，如 {"年度":2026}）；有 @主鍵 → 單據表頭 + 明細 */
CREATE OR ALTER PROCEDURE api_查詢 @功能代碼 nvarchar(20), @關鍵字 nvarchar(100) = NULL, @主鍵 nvarchar(100) = NULL, @參數 nvarchar(max) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @主檔 sysname, @明細檔 sysname, @鍵欄 sysname, @項次欄 sysname, @sql nvarchar(max), @out nvarchar(max), @order nvarchar(max), @cols nvarchar(max);
    SELECT @主檔 = 主檔, @明細檔 = 明細檔 FROM 功能表 WHERE 功能代碼 = @功能代碼;
    IF @主檔 IS NULL THROW 50100, N'功能代碼不存在', 1;

    SELECT @order = STRING_AGG(CAST(QUOTENAME(欄位名) + N' DESC' AS nvarchar(max)), N',') WITHIN GROUP (ORDER BY 順序)
    FROM 系統欄位 WHERE 表名 = @主檔 AND 主鍵 = 1;
    SET @order = ISNULL(@order, IIF(OBJECT_ID(@主檔, 'IF') IS NULL, N'1, 2, 3', N'1'));

    DECLARE @來源 nvarchar(max) = QUOTENAME(@主檔);
    IF EXISTS (SELECT 1 FROM 系統參數 WHERE 表名 = @主檔)
        SELECT @來源 += N'(' + STRING_AGG(CAST(N'TRY_CAST(JSON_VALUE(@參數, N''$."' + 參數名 + N'"'') AS '
                     + IIF(型別 IN ('nvarchar','varchar','nchar','char'), 型別 + N'(4000)', 型別) + N')' AS nvarchar(max)), N',') WITHIN GROUP (ORDER BY 順序) + N')'
        FROM 系統參數 WHERE 表名 = @主檔;

    IF NULLIF(@主鍵, N'') IS NULL
    BEGIN
        SELECT @cols = STRING_AGG(CAST(QUOTENAME(欄位名) AS nvarchar(max)), N',') FROM 系統欄位 WHERE 表名 = @主檔;
        SET @sql = N'SET @out = (SELECT TOP (500) * FROM ' + @來源
                 + IIF(NULLIF(@關鍵字, N'') IS NULL, N'', N' WHERE CONCAT_WS(N''|'',' + @cols + N') LIKE N''%'' + @關鍵字 + N''%''')
                 + N' ORDER BY ' + @order + N' FOR JSON PATH, INCLUDE_NULL_VALUES);';
    END
    ELSE
    BEGIN
        SELECT @鍵欄 = 欄位名 FROM 系統欄位 WHERE 表名 = @主檔 AND 主鍵 = 1;
        SELECT @項次欄 = 欄位名 FROM 系統欄位 WHERE 表名 = @明細檔 AND 主鍵 = 1 AND 欄位名 <> @鍵欄;
        SET @sql = N'SET @out = (SELECT JSON_QUERY((SELECT * FROM ' + QUOTENAME(@主檔) + N' WHERE ' + QUOTENAME(@鍵欄) + N' = @主鍵 FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES)) AS 主檔'
                 + IIF(@明細檔 IS NULL, N'', N', JSON_QUERY(ISNULL((SELECT * FROM ' + QUOTENAME(@明細檔) + N' WHERE ' + QUOTENAME(@鍵欄) + N' = @主鍵 ORDER BY ' + QUOTENAME(@項次欄) + N' FOR JSON PATH, INCLUDE_NULL_VALUES), N''[]'')) AS 明細')
                 + N' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);';
    END
    EXEC sp_executesql @sql, N'@關鍵字 nvarchar(100), @主鍵 nvarchar(100), @參數 nvarchar(max), @out nvarchar(max) OUTPUT', @關鍵字, @主鍵, @參數, @out OUTPUT;
    SELECT ISNULL(@out, N'[]') AS json;
END
GO

/* 下拉選項：只開放被外鍵參照的表 */
CREATE OR ALTER PROCEDURE api_選項 @表名 sysname
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM 系統欄位 WHERE 參照表 = @表名) THROW 50120, N'不提供此選項', 1;
    DECLARE @k sysname = (SELECT TOP (1) 欄位名 FROM 系統欄位 WHERE 表名 = @表名 AND 主鍵 = 1 ORDER BY 順序), @sql nvarchar(max), @out nvarchar(max);
    SET @sql = N'SET @out = (SELECT ' + QUOTENAME(@k) + N' AS 值, '
             + IIF(EXISTS (SELECT 1 FROM 系統欄位 WHERE 表名 = @表名 AND 欄位名 = N'備註說明'), N'備註說明', N'NULL') + N' AS 說明 FROM '
             + QUOTENAME(@表名) + N' ORDER BY ' + QUOTENAME(@k) + N' FOR JSON PATH);';
    EXEC sp_executesql @sql, N'@out nvarchar(max) OUTPUT', @out OUTPUT;
    SELECT ISNULL(@out, N'[]') AS json;
END
GO

/* 儲存（新增/修改）：@請求編號 由手機端產生，重傳時不會重複執行 */
CREATE OR ALTER PROCEDURE api_儲存 @請求編號 uniqueidentifier, @功能代碼 nvarchar(20), @資料 nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @結果 nvarchar(max) = (SELECT 結果 FROM 同步請求紀錄 WHERE 請求編號 = @請求編號);
    IF @結果 IS NOT NULL BEGIN SELECT @結果 AS json; RETURN; END;

    BEGIN TRY
        DECLARE @主檔 sysname, @明細檔 sysname, @明細唯讀 bit, @前綴 nvarchar(6), @鍵欄 sysname, @鍵值 nvarchar(20),
                @主檔資料 nvarchar(max), @明細資料 nvarchar(max), @sql nvarchar(max), @n int, @字首 nvarchar(20), @msg nvarchar(200);
        SELECT @主檔 = 主檔, @明細檔 = 明細檔, @明細唯讀 = 明細唯讀, @前綴 = 單號前綴 FROM 功能表 WHERE 功能代碼 = @功能代碼 AND 類型 = N'維護';
        IF @主檔 IS NULL THROW 50100, N'功能代碼不存在或不可維護', 1;
        IF ISJSON(@資料) = 0 THROW 50101, N'資料格式錯誤', 1;
        SET @主檔資料 = JSON_QUERY(@資料, N'$."主檔"');
        SET @明細資料 = ISNULL(JSON_QUERY(@資料, N'$."明細"'), N'[]');
        IF @主檔資料 IS NULL THROW 50101, N'缺少主檔資料', 1;
        IF (SELECT COUNT(*) FROM 系統欄位 WHERE 表名 = @主檔 AND 主鍵 = 1) = 1
            SELECT @鍵欄 = 欄位名 FROM 系統欄位 WHERE 表名 = @主檔 AND 主鍵 = 1;

        BEGIN TRAN;
        IF @鍵欄 IS NOT NULL
        BEGIN
            SET @鍵值 = NULLIF(LTRIM(RTRIM(JSON_VALUE(@主檔資料, N'$."' + @鍵欄 + N'"'))), N'');
            IF @鍵值 IS NULL AND @前綴 IS NOT NULL
            BEGIN   -- 自動編號：前綴 + yyyyMMdd + 3 碼流水
                SET @字首 = @前綴 + CONVERT(char(8), GETDATE(), 112);
                SET @sql = N'SELECT @n = ISNULL(MAX(TRY_CAST(RIGHT(' + QUOTENAME(@鍵欄) + N', 3) AS int)), 0) + 1 FROM ' + QUOTENAME(@主檔)
                         + N' WITH (UPDLOCK, HOLDLOCK) WHERE ' + QUOTENAME(@鍵欄) + N' LIKE @字首 + N''___''';
                EXEC sp_executesql @sql, N'@字首 nvarchar(20), @n int OUTPUT', @字首, @n OUTPUT;
                SET @鍵值 = @字首 + RIGHT(N'000' + CAST(@n AS nvarchar(10)), 3);
                SET @主檔資料 = JSON_MODIFY(@主檔資料, N'$."' + @鍵欄 + N'"', @鍵值);
            END
            IF @鍵值 IS NULL BEGIN SET @msg = N'請輸入' + @鍵欄; THROW 50102, @msg, 1; END
        END

        SET @主檔資料 = N'[' + @主檔資料 + N']';
        EXEC sp_合併JSON @主檔, @主檔資料;
        IF @明細檔 IS NOT NULL AND @明細唯讀 = 0
            EXEC sp_合併JSON @明細檔, @明細資料, @鍵欄, @鍵值;

        SET @結果 = (SELECT CAST(1 AS bit) AS 成功, @鍵值 AS 主鍵 FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES);
        INSERT 同步請求紀錄 (請求編號, 功能代碼, 動作, 資料, 結果) VALUES (@請求編號, @功能代碼, N'儲存', @資料, @結果);
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        EXEC sp_錯誤轉譯;
    END CATCH
    SELECT @結果 AS json;
END
GO

/* 刪除：@主鍵 為主鍵欄位的 JSON 物件；單據表頭刪除時明細連動刪除 */
CREATE OR ALTER PROCEDURE api_刪除 @請求編號 uniqueidentifier, @功能代碼 nvarchar(20), @主鍵 nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @結果 nvarchar(max) = (SELECT 結果 FROM 同步請求紀錄 WHERE 請求編號 = @請求編號);
    IF @結果 IS NOT NULL BEGIN SELECT @結果 AS json; RETURN; END;

    BEGIN TRY
        DECLARE @主檔 sysname, @with nvarchar(max), @on nvarchar(max), @sql nvarchar(max), @n int;
        SELECT @主檔 = 主檔 FROM 功能表 WHERE 功能代碼 = @功能代碼 AND 類型 = N'維護';
        IF @主檔 IS NULL THROW 50100, N'功能代碼不存在或不可維護', 1;
        SELECT @with = STRING_AGG(CAST(QUOTENAME(欄位名) + N' ' + SQL型別 + N' ''$."' + 欄位名 + N'"''' AS nvarchar(max)), N','),
               @on   = STRING_AGG(CAST(N't.' + QUOTENAME(欄位名) + N'=s.' + QUOTENAME(欄位名) AS nvarchar(max)), N' AND ')
        FROM 系統欄位 WHERE 表名 = @主檔 AND 主鍵 = 1;

        BEGIN TRAN;
        SET @sql = N'DELETE t FROM ' + QUOTENAME(@主檔) + N' t JOIN OPENJSON(@k) WITH (' + @with + N') s ON ' + @on + N'; SET @n = @@ROWCOUNT;';
        DECLARE @k nvarchar(max) = N'[' + @主鍵 + N']';
        EXEC sp_executesql @sql, N'@k nvarchar(max), @n int OUTPUT', @k, @n OUTPUT;
        SET @結果 = (SELECT CAST(1 AS bit) AS 成功, @n AS 筆數 FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        INSERT 同步請求紀錄 (請求編號, 功能代碼, 動作, 資料, 結果) VALUES (@請求編號, @功能代碼, N'刪除', @主鍵, @結果);
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        EXEC sp_錯誤轉譯;
    END CATCH
    SELECT @結果 AS json;
END
GO

/* 報表多層鑽取：@上層 為上一層被點選的整列（JSON），依 報表層級關聯 篩選本層 */
CREATE OR ALTER PROCEDURE api_鑽取 @功能代碼 nvarchar(20), @層級 int, @上層 nvarchar(max) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @來源 sysname, @排序 nvarchar(200), @where nvarchar(max), @sql nvarchar(max), @out nvarchar(max);
    SELECT @來源 = 來源, @排序 = 排序 FROM 報表層級 WHERE 功能代碼 = @功能代碼 AND 層級 = @層級;
    IF @來源 IS NULL THROW 50130, N'報表層級不存在', 1;
    SELECT @where = STRING_AGG(CAST(QUOTENAME(k.本層欄位) + N' = TRY_CAST(JSON_VALUE(@上層, N''$."' + k.上層欄位 + N'"'') AS ' + c.SQL型別 + N')' AS nvarchar(max)), N' AND ')
    FROM 報表層級關聯 k JOIN 系統欄位 c ON c.表名 = @來源 AND c.欄位名 = k.本層欄位
    WHERE k.功能代碼 = @功能代碼 AND k.層級 = @層級;
    SET @sql = N'SET @out = (SELECT TOP (1000) * FROM ' + QUOTENAME(@來源) + ISNULL(N' WHERE ' + @where, N'')
             + N' ORDER BY ' + ISNULL(@排序, N'1') + N' FOR JSON PATH, INCLUDE_NULL_VALUES);';
    EXEC sp_executesql @sql, N'@上層 nvarchar(max), @out nvarchar(max) OUTPUT', @上層, @out OUTPUT;
    SELECT ISNULL(@out, N'[]') AS json;
END
GO

/* 明細參照來源：以表頭已填的值篩選（如客戶編號），每列附 _帶入（明細欄位）與 _表頭（回填表頭） */
CREATE OR ALTER PROCEDURE api_參照來源 @功能代碼 nvarchar(20), @表頭 nvarchar(max) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @來源 sysname, @where nvarchar(max), @明細 nvarchar(max), @頭 nvarchar(max), @sql nvarchar(max), @out nvarchar(max);
    SELECT @來源 = 來源 FROM 明細參照 WHERE 功能代碼 = @功能代碼;
    IF @來源 IS NULL THROW 50140, N'此功能沒有參照來源', 1;
    SELECT @where = STRING_AGG(CAST(N'(JSON_VALUE(@表頭, N''$."' + 目標欄位 + N'"'') IS NULL OR s.' + QUOTENAME(來源欄位)
                  + N' = JSON_VALUE(@表頭, N''$."' + 目標欄位 + N'"''))' AS nvarchar(max)), N' AND ')
    FROM 明細參照欄位 WHERE 功能代碼 = @功能代碼 AND 位置 = N'表頭';
    SELECT @明細 = STRING_AGG(CAST(N's.' + QUOTENAME(來源欄位) + N' AS ' + QUOTENAME(目標欄位) AS nvarchar(max)), N',')
    FROM 明細參照欄位 WHERE 功能代碼 = @功能代碼 AND 位置 = N'明細';
    SELECT @頭 = STRING_AGG(CAST(N's.' + QUOTENAME(來源欄位) + N' AS ' + QUOTENAME(目標欄位) AS nvarchar(max)), N',')
    FROM 明細參照欄位 WHERE 功能代碼 = @功能代碼 AND 位置 = N'表頭';
    SET @sql = N'SET @out = (SELECT TOP (500) s.*, JSON_QUERY((SELECT ' + @明細 + N' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)) AS _帶入'
             + ISNULL(N', JSON_QUERY((SELECT ' + @頭 + N' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)) AS _表頭', N'')
             + N' FROM ' + QUOTENAME(@來源) + N' s' + ISNULL(N' WHERE ' + @where, N'')
             + N' ORDER BY 1, 2 FOR JSON PATH, INCLUDE_NULL_VALUES);';
    EXEC sp_executesql @sql, N'@表頭 nvarchar(max), @out nvarchar(max) OUTPUT', @表頭, @out OUTPUT;
    SELECT ISNULL(@out, N'[]') AS json;
END
GO
