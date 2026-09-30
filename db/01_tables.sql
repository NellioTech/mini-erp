/* ============================================================
   01 資料表：組織架構 / 主數據 / 交易數據 / 報表資料表 / 系統表
   ============================================================ */

/* ---------- 系統 ---------- */
CREATE TYPE dbo.單據清單 AS TABLE (異動類型 nvarchar(20) NOT NULL, 單據編號 nvarchar(20) NOT NULL);
GO
CREATE TABLE 功能表 (
    功能代碼 nvarchar(20)  NOT NULL CONSTRAINT PK_功能表 PRIMARY KEY,
    模組     nvarchar(10)  NOT NULL,
    模組名稱 nvarchar(20)  NOT NULL,
    分類     nvarchar(20)  NOT NULL,
    功能名稱 nvarchar(20)  NOT NULL,
    類型     nvarchar(10)  NOT NULL CONSTRAINT CK_功能表_類型 CHECK (類型 IN (N'維護', N'報表')),
    主檔     sysname       NOT NULL,
    明細檔   sysname       NULL,
    明細唯讀 bit           NOT NULL DEFAULT 0,
    單號前綴 nvarchar(6)   NULL,
    排序     int           NOT NULL
);
CREATE TABLE 欄位設定 (          -- 由觸發程序回寫的欄位，前端不可輸入
    表名   sysname NOT NULL,
    欄位名 sysname NOT NULL,
    唯讀   bit     NOT NULL DEFAULT 1,
    CONSTRAINT PK_欄位設定 PRIMARY KEY (表名, 欄位名)
);
CREATE TABLE 同步請求紀錄 (      -- 離線重傳冪等：同一請求編號只執行一次
    請求編號 uniqueidentifier NOT NULL CONSTRAINT PK_同步請求紀錄 PRIMARY KEY,
    功能代碼 nvarchar(20)     NOT NULL,
    動作     nvarchar(10)     NOT NULL,
    資料     nvarchar(max)    NULL,
    結果     nvarchar(max)    NOT NULL,
    建立時間 datetime2(0)     NOT NULL DEFAULT sysdatetime()
);

/* ---------- 組織架構 ---------- */
CREATE TABLE 工廠代碼維護 (
    工廠代碼 nvarchar(20) NOT NULL CONSTRAINT PK_工廠代碼維護 PRIMARY KEY,
    備註說明 nvarchar(20) NULL
);
CREATE TABLE 銷售組織維護 (
    銷售組織 nvarchar(20) NOT NULL CONSTRAINT PK_銷售組織維護 PRIMARY KEY,
    備註說明 nvarchar(20) NULL,
    工廠代碼 nvarchar(20) NULL CONSTRAINT FK_銷售組織_工廠 REFERENCES 工廠代碼維護   -- 新增：訂單需求歸屬工廠（每日供需餘額用）
);
CREATE TABLE 採購組織維護 (
    採購組織 nvarchar(20) NOT NULL CONSTRAINT PK_採購組織維護 PRIMARY KEY,
    備註說明 nvarchar(20) NULL,
    工廠代碼 nvarchar(20) NULL CONSTRAINT FK_採購組織_工廠 REFERENCES 工廠代碼維護   -- 新增：採購供給歸屬工廠（每日供需餘額用）
);
CREATE TABLE 工廠倉庫維護 (
    工廠代碼 nvarchar(20) NOT NULL CONSTRAINT FK_工廠倉庫_工廠 REFERENCES 工廠代碼維護,
    倉庫代碼 nvarchar(20) NOT NULL CONSTRAINT PK_工廠倉庫維護 PRIMARY KEY,   -- 倉庫代碼唯一
    備註說明 nvarchar(20) NULL
);

/* ---------- 主數據 ---------- */
CREATE TABLE 客戶資料維護 (
    客戶編號 nvarchar(20) NOT NULL CONSTRAINT PK_客戶資料維護 PRIMARY KEY,
    備註說明 nvarchar(20) NULL
);
CREATE TABLE 廠商資料維護 (
    廠商編號 nvarchar(20) NOT NULL CONSTRAINT PK_廠商資料維護 PRIMARY KEY,
    備註說明 nvarchar(20) NULL
);
CREATE TABLE 物料資料維護 (
    物料編號 nvarchar(20) NOT NULL CONSTRAINT PK_物料資料維護 PRIMARY KEY,
    備註說明 nvarchar(20) NULL
);
CREATE TABLE 物管資料維護 (
    物管編號 nvarchar(20) NOT NULL CONSTRAINT PK_物管資料維護 PRIMARY KEY,
    備註說明 nvarchar(20) NULL
);
CREATE TABLE 用量清單維護 (
    主階編號 nvarchar(20) NOT NULL CONSTRAINT FK_用量清單_主階 REFERENCES 物料資料維護,
    子階編號 nvarchar(20) NOT NULL CONSTRAINT FK_用量清單_子階 REFERENCES 物料資料維護,
    標準用量 int          NOT NULL CONSTRAINT CK_用量清單_標準用量須大於0 CHECK (標準用量 > 0),
    備註說明 nvarchar(20) NULL,
    CONSTRAINT PK_用量清單維護 PRIMARY KEY (主階編號, 子階編號),
    CONSTRAINT CK_用量清單_主子階不可相同 CHECK (主階編號 <> 子階編號)
);

/* ---------- SD 交易 ---------- */
CREATE TABLE 客戶訂單主檔 (
    訂單編號 nvarchar(20) NOT NULL CONSTRAINT PK_客戶訂單主檔 PRIMARY KEY,
    訂單日期 date         NOT NULL,
    銷售組織 nvarchar(20) NOT NULL CONSTRAINT FK_客戶訂單_銷售組織 REFERENCES 銷售組織維護,
    客戶編號 nvarchar(20) NOT NULL CONSTRAINT FK_客戶訂單_客戶 REFERENCES 客戶資料維護,
    備註說明 nvarchar(20) NULL
);
CREATE TABLE 客戶訂單明細 (
    訂單編號 nvarchar(20) NOT NULL CONSTRAINT FK_客戶訂單明細_主檔 REFERENCES 客戶訂單主檔 ON DELETE CASCADE,
    訂單項次 nvarchar(04) NOT NULL,
    物料編號 nvarchar(20) NOT NULL CONSTRAINT FK_客戶訂單明細_物料 REFERENCES 物料資料維護,
    訂單數量 int          NOT NULL CONSTRAINT CK_客戶訂單明細_訂單數量須大於0 CHECK (訂單數量 > 0),
    出貨數量 int          NOT NULL DEFAULT 0,
    退回數量 int          NOT NULL DEFAULT 0,
    預定交期 date         NULL,
    備註說明 nvarchar(20) NULL,
    CONSTRAINT PK_客戶訂單明細 PRIMARY KEY (訂單編號, 訂單項次),
    CONSTRAINT UQ_客戶訂單明細_物料 UNIQUE (訂單編號, 訂單項次, 物料編號),
    CONSTRAINT CK_客戶訂單明細_出貨超過訂單 CHECK (出貨數量 - 退回數量 <= 訂單數量),
    CONSTRAINT CK_客戶訂單明細_退回超過出貨 CHECK (退回數量 >= 0 AND 退回數量 <= 出貨數量)
);
CREATE TABLE 訂單出貨主檔 (
    出貨編號 nvarchar(20) NOT NULL CONSTRAINT PK_訂單出貨主檔 PRIMARY KEY,
    出貨日期 date         NOT NULL,
    銷售組織 nvarchar(20) NOT NULL CONSTRAINT FK_訂單出貨_銷售組織 REFERENCES 銷售組織維護,
    客戶編號 nvarchar(20) NOT NULL CONSTRAINT FK_訂單出貨_客戶 REFERENCES 客戶資料維護,
    備註說明 nvarchar(20) NULL
);
CREATE TABLE 訂單出貨明細 (
    出貨編號 nvarchar(20) NOT NULL CONSTRAINT FK_訂單出貨明細_主檔 REFERENCES 訂單出貨主檔 ON DELETE CASCADE,
    出貨項次 nvarchar(04) NOT NULL,
    訂單編號 nvarchar(20) NOT NULL,
    訂單項次 nvarchar(04) NOT NULL,
    物料編號 nvarchar(20) NOT NULL,
    倉庫代碼 nvarchar(20) NOT NULL CONSTRAINT FK_訂單出貨明細_倉庫 REFERENCES 工廠倉庫維護,
    出貨數量 int          NOT NULL CONSTRAINT CK_訂單出貨明細_出貨數量須大於0 CHECK (出貨數量 > 0),
    備註說明 nvarchar(20) NULL,
    CONSTRAINT PK_訂單出貨明細 PRIMARY KEY (出貨編號, 出貨項次),
    CONSTRAINT FK_訂單出貨明細_訂單項次物料 FOREIGN KEY (訂單編號, 訂單項次, 物料編號)
        REFERENCES 客戶訂單明細 (訂單編號, 訂單項次, 物料編號)
);
CREATE TABLE 出貨退回主檔 (
    退回編號 nvarchar(20) NOT NULL CONSTRAINT PK_出貨退回主檔 PRIMARY KEY,
    退回日期 date         NOT NULL,
    銷售組織 nvarchar(20) NOT NULL CONSTRAINT FK_出貨退回_銷售組織 REFERENCES 銷售組織維護,
    客戶編號 nvarchar(20) NOT NULL CONSTRAINT FK_出貨退回_客戶 REFERENCES 客戶資料維護,
    備註說明 nvarchar(20) NULL
);
CREATE TABLE 出貨退回明細 (
    退回編號 nvarchar(20) NOT NULL CONSTRAINT FK_出貨退回明細_主檔 REFERENCES 出貨退回主檔 ON DELETE CASCADE,
    退回項次 nvarchar(04) NOT NULL,
    訂單編號 nvarchar(20) NOT NULL,
    訂單項次 nvarchar(04) NOT NULL,
    物料編號 nvarchar(20) NOT NULL,
    倉庫代碼 nvarchar(20) NOT NULL CONSTRAINT FK_出貨退回明細_倉庫 REFERENCES 工廠倉庫維護,
    退回數量 int          NOT NULL CONSTRAINT CK_出貨退回明細_退回數量須大於0 CHECK (退回數量 > 0),
    備註說明 nvarchar(20) NULL,
    CONSTRAINT PK_出貨退回明細 PRIMARY KEY (退回編號, 退回項次),
    CONSTRAINT FK_出貨退回明細_訂單項次物料 FOREIGN KEY (訂單編號, 訂單項次, 物料編號)
        REFERENCES 客戶訂單明細 (訂單編號, 訂單項次, 物料編號)
);

/* ---------- MM 交易 ---------- */
CREATE TABLE 廠商採購主檔 (
    採購編號 nvarchar(20) NOT NULL CONSTRAINT PK_廠商採購主檔 PRIMARY KEY,
    採購日期 date         NOT NULL,
    採購組織 nvarchar(20) NOT NULL CONSTRAINT FK_廠商採購_採購組織 REFERENCES 採購組織維護,
    廠商編號 nvarchar(20) NOT NULL CONSTRAINT FK_廠商採購_廠商 REFERENCES 廠商資料維護,
    備註說明 nvarchar(20) NULL
);
CREATE TABLE 廠商採購明細 (
    採購編號 nvarchar(20) NOT NULL CONSTRAINT FK_廠商採購明細_主檔 REFERENCES 廠商採購主檔 ON DELETE CASCADE,
    採購項次 nvarchar(04) NOT NULL,
    物料編號 nvarchar(20) NOT NULL CONSTRAINT FK_廠商採購明細_物料 REFERENCES 物料資料維護,
    採購數量 int          NOT NULL CONSTRAINT CK_廠商採購明細_採購數量須大於0 CHECK (採購數量 > 0),
    收貨數量 int          NOT NULL DEFAULT 0,
    退回數量 int          NOT NULL DEFAULT 0,
    預定交期 date         NULL,
    備註說明 nvarchar(20) NULL,
    CONSTRAINT PK_廠商採購明細 PRIMARY KEY (採購編號, 採購項次),
    CONSTRAINT UQ_廠商採購明細_物料 UNIQUE (採購編號, 採購項次, 物料編號),
    CONSTRAINT CK_廠商採購明細_收貨超過採購 CHECK (收貨數量 - 退回數量 <= 採購數量),
    CONSTRAINT CK_廠商採購明細_退回超過收貨 CHECK (退回數量 >= 0 AND 退回數量 <= 收貨數量)
);
CREATE TABLE 採購收貨主檔 (
    收貨編號 nvarchar(20) NOT NULL CONSTRAINT PK_採購收貨主檔 PRIMARY KEY,
    收貨日期 date         NOT NULL,
    採購組織 nvarchar(20) NOT NULL CONSTRAINT FK_採購收貨_採購組織 REFERENCES 採購組織維護,
    廠商編號 nvarchar(20) NOT NULL CONSTRAINT FK_採購收貨_廠商 REFERENCES 廠商資料維護,
    備註說明 nvarchar(20) NULL
);
CREATE TABLE 採購收貨明細 (
    收貨編號 nvarchar(20) NOT NULL CONSTRAINT FK_採購收貨明細_主檔 REFERENCES 採購收貨主檔 ON DELETE CASCADE,
    收貨項次 nvarchar(04) NOT NULL,
    採購編號 nvarchar(20) NOT NULL,
    採購項次 nvarchar(04) NOT NULL,
    物料編號 nvarchar(20) NOT NULL,
    倉庫代碼 nvarchar(20) NOT NULL CONSTRAINT FK_採購收貨明細_倉庫 REFERENCES 工廠倉庫維護,
    收貨數量 int          NOT NULL CONSTRAINT CK_採購收貨明細_收貨數量須大於0 CHECK (收貨數量 > 0),
    備註說明 nvarchar(20) NULL,
    CONSTRAINT PK_採購收貨明細 PRIMARY KEY (收貨編號, 收貨項次),
    CONSTRAINT FK_採購收貨明細_採購項次物料 FOREIGN KEY (採購編號, 採購項次, 物料編號)
        REFERENCES 廠商採購明細 (採購編號, 採購項次, 物料編號)
);
CREATE TABLE 收貨退回主檔 (
    退回編號 nvarchar(20) NOT NULL CONSTRAINT PK_收貨退回主檔 PRIMARY KEY,
    退回日期 date         NOT NULL,
    採購組織 nvarchar(20) NOT NULL CONSTRAINT FK_收貨退回_採購組織 REFERENCES 採購組織維護,
    廠商編號 nvarchar(20) NOT NULL CONSTRAINT FK_收貨退回_廠商 REFERENCES 廠商資料維護,
    備註說明 nvarchar(20) NULL
);
CREATE TABLE 收貨退回明細 (
    退回編號 nvarchar(20) NOT NULL CONSTRAINT FK_收貨退回明細_主檔 REFERENCES 收貨退回主檔 ON DELETE CASCADE,
    退回項次 nvarchar(04) NOT NULL,
    採購編號 nvarchar(20) NOT NULL,
    採購項次 nvarchar(04) NOT NULL,
    物料編號 nvarchar(20) NOT NULL,
    倉庫代碼 nvarchar(20) NOT NULL CONSTRAINT FK_收貨退回明細_倉庫 REFERENCES 工廠倉庫維護,
    退回數量 int          NOT NULL CONSTRAINT CK_收貨退回明細_退回數量須大於0 CHECK (退回數量 > 0),
    備註說明 nvarchar(20) NULL,
    CONSTRAINT PK_收貨退回明細 PRIMARY KEY (退回編號, 退回項次),
    CONSTRAINT FK_收貨退回明細_採購項次物料 FOREIGN KEY (採購編號, 採購項次, 物料編號)
        REFERENCES 廠商採購明細 (採購編號, 採購項次, 物料編號)
);

/* ---------- IM 交易 ---------- */
CREATE TABLE 物料預留主檔 (
    預留編號 nvarchar(20) NOT NULL CONSTRAINT PK_物料預留主檔 PRIMARY KEY,
    預留日期 date         NOT NULL,
    工廠代碼 nvarchar(20) NOT NULL CONSTRAINT FK_物料預留_工廠 REFERENCES 工廠代碼維護,
    物管編號 nvarchar(20) NOT NULL CONSTRAINT FK_物料預留_物管 REFERENCES 物管資料維護,
    備註說明 nvarchar(20) NULL
);
CREATE TABLE 物料預留明細 (
    預留編號 nvarchar(20) NOT NULL CONSTRAINT FK_物料預留明細_主檔 REFERENCES 物料預留主檔 ON DELETE CASCADE,
    預留項次 nvarchar(04) NOT NULL,
    物料編號 nvarchar(20) NOT NULL CONSTRAINT FK_物料預留明細_物料 REFERENCES 物料資料維護,
    預留數量 int          NOT NULL CONSTRAINT CK_物料預留明細_預留數量須大於0 CHECK (預留數量 > 0),
    預定交期 date         NULL,
    備註說明 nvarchar(20) NULL,
    CONSTRAINT PK_物料預留明細 PRIMARY KEY (預留編號, 預留項次)
);
CREATE TABLE 庫存領用主檔 (
    領用編號 nvarchar(20) NOT NULL CONSTRAINT PK_庫存領用主檔 PRIMARY KEY,
    領用日期 date         NOT NULL,
    工廠代碼 nvarchar(20) NOT NULL CONSTRAINT FK_庫存領用_工廠 REFERENCES 工廠代碼維護,
    物管編號 nvarchar(20) NOT NULL CONSTRAINT FK_庫存領用_物管 REFERENCES 物管資料維護,
    備註說明 nvarchar(20) NULL
);
CREATE TABLE 庫存領用明細 (
    領用編號 nvarchar(20) NOT NULL CONSTRAINT FK_庫存領用明細_主檔 REFERENCES 庫存領用主檔 ON DELETE CASCADE,
    領用項次 nvarchar(04) NOT NULL,
    物料編號 nvarchar(20) NOT NULL CONSTRAINT FK_庫存領用明細_物料 REFERENCES 物料資料維護,
    倉庫代碼 nvarchar(20) NOT NULL CONSTRAINT FK_庫存領用明細_倉庫 REFERENCES 工廠倉庫維護,
    領用數量 int          NOT NULL CONSTRAINT CK_庫存領用明細_領用數量須大於0 CHECK (領用數量 > 0),
    備註說明 nvarchar(20) NULL,
    CONSTRAINT PK_庫存領用明細 PRIMARY KEY (領用編號, 領用項次)
);
CREATE TABLE 庫存繳庫主檔 (
    繳庫編號 nvarchar(20) NOT NULL CONSTRAINT PK_庫存繳庫主檔 PRIMARY KEY,
    繳庫日期 date         NOT NULL,
    工廠代碼 nvarchar(20) NOT NULL CONSTRAINT FK_庫存繳庫_工廠 REFERENCES 工廠代碼維護,
    物管編號 nvarchar(20) NOT NULL CONSTRAINT FK_庫存繳庫_物管 REFERENCES 物管資料維護,
    備註說明 nvarchar(20) NULL
);
CREATE TABLE 庫存繳庫明細 (
    繳庫編號 nvarchar(20) NOT NULL CONSTRAINT FK_庫存繳庫明細_主檔 REFERENCES 庫存繳庫主檔 ON DELETE CASCADE,
    繳庫項次 nvarchar(04) NOT NULL,
    物料編號 nvarchar(20) NOT NULL CONSTRAINT FK_庫存繳庫明細_物料 REFERENCES 物料資料維護,
    倉庫代碼 nvarchar(20) NOT NULL CONSTRAINT FK_庫存繳庫明細_倉庫 REFERENCES 工廠倉庫維護,
    繳庫數量 int          NOT NULL CONSTRAINT CK_庫存繳庫明細_繳庫數量須大於0 CHECK (繳庫數量 > 0),
    備註說明 nvarchar(20) NULL,
    CONSTRAINT PK_庫存繳庫明細 PRIMARY KEY (繳庫編號, 繳庫項次)
);

/* ---------- PP 交易 ---------- */
CREATE TABLE 生產工單主檔 (
    工單編號 nvarchar(20) NOT NULL CONSTRAINT PK_生產工單主檔 PRIMARY KEY,
    工單日期 date         NOT NULL,
    工廠代碼 nvarchar(20) NOT NULL CONSTRAINT FK_生產工單_工廠 REFERENCES 工廠代碼維護,
    物料編號 nvarchar(20) NOT NULL CONSTRAINT FK_生產工單_物料 REFERENCES 物料資料維護,  -- 新增：生產品項（BOM 展開、入庫比對用）
    預定完工 date         NULL,
    生產數量 int          NOT NULL CONSTRAINT CK_生產工單_生產數量須大於0 CHECK (生產數量 > 0),
    入庫數量 int          NOT NULL DEFAULT 0,
    物管編號 nvarchar(20) NOT NULL CONSTRAINT FK_生產工單_物管 REFERENCES 物管資料維護,
    備註說明 nvarchar(20) NULL,
    CONSTRAINT UQ_生產工單_物料 UNIQUE (工單編號, 物料編號),
    CONSTRAINT CK_生產工單_入庫超過生產 CHECK (入庫數量 >= 0 AND 入庫數量 <= 生產數量)
);
CREATE TABLE 生產工單明細 (
    工單編號 nvarchar(20) NOT NULL CONSTRAINT FK_生產工單明細_主檔 REFERENCES 生產工單主檔 ON DELETE CASCADE,
    工單項次 nvarchar(04) NOT NULL,
    物料編號 nvarchar(20) NOT NULL CONSTRAINT FK_生產工單明細_物料 REFERENCES 物料資料維護,
    應領用量 int          NOT NULL,
    已領用量 int          NOT NULL DEFAULT 0,
    預定領料 date         NULL,
    備註說明 nvarchar(20) NULL,
    CONSTRAINT PK_生產工單明細 PRIMARY KEY (工單編號, 工單項次),
    CONSTRAINT UQ_生產工單明細_物料 UNIQUE (工單編號, 物料編號),
    CONSTRAINT CK_生產工單明細_領料超過應領 CHECK (已領用量 >= 0 AND 已領用量 <= 應領用量)
);
CREATE TABLE 工單入庫主檔 (
    入庫編號 nvarchar(20) NOT NULL CONSTRAINT PK_工單入庫主檔 PRIMARY KEY,
    入庫日期 date         NOT NULL,
    工廠代碼 nvarchar(20) NOT NULL CONSTRAINT FK_工單入庫_工廠 REFERENCES 工廠代碼維護,
    物管編號 nvarchar(20) NOT NULL CONSTRAINT FK_工單入庫_物管 REFERENCES 物管資料維護,
    備註說明 nvarchar(20) NULL
);
CREATE TABLE 工單入庫明細 (
    入庫編號 nvarchar(20) NOT NULL CONSTRAINT FK_工單入庫明細_主檔 REFERENCES 工單入庫主檔 ON DELETE CASCADE,
    入庫項次 nvarchar(04) NOT NULL,
    工單編號 nvarchar(20) NOT NULL,
    物料編號 nvarchar(20) NOT NULL,
    倉庫代碼 nvarchar(20) NOT NULL CONSTRAINT FK_工單入庫明細_倉庫 REFERENCES 工廠倉庫維護,
    入庫數量 int          NOT NULL CONSTRAINT CK_工單入庫明細_入庫數量須大於0 CHECK (入庫數量 > 0),
    備註說明 nvarchar(20) NULL,
    CONSTRAINT PK_工單入庫明細 PRIMARY KEY (入庫編號, 入庫項次),
    CONSTRAINT FK_工單入庫明細_工單物料 FOREIGN KEY (工單編號, 物料編號)
        REFERENCES 生產工單主檔 (工單編號, 物料編號)
);
CREATE TABLE 工單領料主檔 (
    領料編號 nvarchar(20) NOT NULL CONSTRAINT PK_工單領料主檔 PRIMARY KEY,
    領料日期 date         NOT NULL,
    工廠代碼 nvarchar(20) NOT NULL CONSTRAINT FK_工單領料_工廠 REFERENCES 工廠代碼維護,
    物管編號 nvarchar(20) NOT NULL CONSTRAINT FK_工單領料_物管 REFERENCES 物管資料維護,
    備註說明 nvarchar(20) NULL
);
CREATE TABLE 工單領料明細 (
    領料編號 nvarchar(20) NOT NULL CONSTRAINT FK_工單領料明細_主檔 REFERENCES 工單領料主檔 ON DELETE CASCADE,
    領料項次 nvarchar(04) NOT NULL,
    工單編號 nvarchar(20) NOT NULL,
    物料編號 nvarchar(20) NOT NULL,
    倉庫代碼 nvarchar(20) NOT NULL CONSTRAINT FK_工單領料明細_倉庫 REFERENCES 工廠倉庫維護,
    領料數量 int          NOT NULL CONSTRAINT CK_工單領料明細_領料數量須大於0 CHECK (領料數量 > 0),
    備註說明 nvarchar(20) NULL,
    CONSTRAINT PK_工單領料明細 PRIMARY KEY (領料編號, 領料項次),
    CONSTRAINT FK_工單領料明細_工單物料 FOREIGN KEY (工單編號, 物料編號)
        REFERENCES 生產工單明細 (工單編號, 物料編號)
);

/* ---------- 報表資料表（由觸發程序維護，不可手動輸入） ---------- */
CREATE TABLE 庫存異動明細 (
    異動序號 bigint IDENTITY NOT NULL CONSTRAINT PK_庫存異動明細 PRIMARY KEY,
    異動日期 date         NOT NULL,
    異動類型 nvarchar(20) NOT NULL,
    單據編號 nvarchar(20) NOT NULL,
    單據項次 nvarchar(04) NOT NULL,
    參考編號 nvarchar(20) NULL,
    工廠代碼 nvarchar(20) NOT NULL,
    倉庫代碼 nvarchar(20) NOT NULL,
    物料編號 nvarchar(20) NOT NULL,
    異動數量 int          NOT NULL,
    備註說明 nvarchar(20) NULL,
    建立時間 datetime2(0) NOT NULL DEFAULT sysdatetime(),
    INDEX IX_庫存異動明細_單據 (異動類型, 單據編號),
    INDEX IX_庫存異動明細_倉庫物料 (倉庫代碼, 物料編號, 異動日期)
);
CREATE TABLE 每日庫存餘額 (      -- 逐列：期初數量 + 本期入庫 - 本期出庫 = 期末數量
    餘額日期 date         NOT NULL,
    工廠代碼 nvarchar(20) NOT NULL,
    物料編號 nvarchar(20) NOT NULL,
    倉庫代碼 nvarchar(20) NOT NULL,
    期初數量 int          NOT NULL,
    本期入庫 int          NOT NULL,
    本期出庫 int          NOT NULL,
    期末數量 int          NOT NULL,
    CONSTRAINT PK_每日庫存餘額 PRIMARY KEY (物料編號, 倉庫代碼, 餘額日期),
    CONSTRAINT CK_每日庫存餘額_餘額公式 CHECK (期初數量 + 本期入庫 - 本期出庫 = 期末數量)
);
