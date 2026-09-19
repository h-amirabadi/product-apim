# راهنمای گام‌به‌گام: اجرای WSO2 API Manager 4.7.0 (پروفایل all-in-one) روی Oracle XE 21c

## پیش‌نیازهایی که باید روی سیستم داشته باشی (قبل از شروع تأیید کن)

| مورد | وضعیت لازم |
|---|---|
| Docker + docker compose (یا docker desktop) | نصب و فعال |
| `curl` یا `wget` برای دانلود JDBC درایور (در صورت نیاز) | نصب |
| `unzip` | نصب |
| `sqlplus` یا `sqlcl` (Oracle client) – اختیاری ولی توصیه می‌شود | نصب یا از داخل کانتینر Oracle اجرا می‌شود |
| `sudo` دسترسی | لازم برای bind کردن پورت‌های کمتر از 1024 نیست، ولی برای برخی تنظیمات لازم می‌شود |
| Java JDK 21 + `JAVA_HOME` | طبق گفته‌ی خودت آماده است |
| حداقل RAM آزاد روی هاست | 4 گیگ برای WSO2 + 2 گیگ برای Oracle = **6 گیگ** |
| پورت‌های آزاد روی هاست | `1521` (Oracle), `9443` (WSO2 mgmt https), `9763` (WSO2 http), `8243` (WSO2 https nio)، `9099/8099/9021/8021` (وب‌سوکت) |

---

## مرحله ۰ – ساختار فعلی پروژه (برای آگاهی)

این مخزن شامل چهار پروفایل است:

```
product-apim/
├── all-in-one-apim/      ← پروفایلی که تو انتخاب کردی (همه چی یک‌جا)
├── api-control-plane/    ← فقط Publisher + Devportal + Key Manager
├── gateway/              ← فقط Gateway Worker
├── traffic-manager/      ← فقط Throttling
```

برای هر پروفایل zip از قبل در مسیر `*/modules/distribution/product/target/` ساخته شده. چون تو فقط all-in-one می‌خواهی، فقط با این یک zip کار داریم:

```
all-in-one-apim/modules/distribution/product/target/wso2am-4.7.0-SNAPSHOT.zip
```

---

## مرحله ۱ – اوراکل XE 21c را در داکر بالا بیاور

### ۱.۱ پوشه‌ی کاری بساز

```bash
mkdir -p ~/wso2-oracle-setup
cd ~/wso2-oracle-setup
mkdir -p oracle-data oracle-init
```

پوشه‌ی `oracle-data` برای نگه‌داری دیتای اوراکل روی هاست است (پایدار می‌ماند اگر کانتینر پاک شود).
پوشه‌ی `oracle-init` بعداً برای اسکریپت‌های init اوراکل استفاده می‌شود.

### ۱.۲ ایمیج Oracle XE را بکش

```bash
docker pull container-registry.oracle.com/database/express:21.3.0-xe
```

> اگر خطای لاگین گرفت، یعنی باید با حساب Oracle وارد شوی:
> ```bash
> docker login container-registry.oracle.com
> ```
> و بعد دوباره `pull` کن.

### ۱.۳ کانتینر Oracle XE را اجرا کن

```bash
docker run -d \
  --name apim-oracle \
  --restart unless-stopped \
  -p 1521:1521 \
  -p 5500:5500 \
  -e ORACLE_PWD=Oracle123 \
  -e ORACLE_CHARACTERSET=AL32UTF8 \
  -v ~/wso2-oracle-setup/oracle-data:/opt/oracle/oradata \
  -v ~/wso2-oracle-setup/oracle-init:/opt/oracle/scripts/setup \
  container-registry.oracle.com/database/express:21.3.0-xe
```

**توضیح پارامترها:**

| پارامتر | کار |
|---|---|
| `--name apim-oracle` | نام کانتینر |
| `-p 1521:1521` | پورت پیش‌فرض Oracle listener (Pluggable) |
| `-p 5500:5500` | پورت Enterprise Manager Express (EM Express) – اختیاری ولی مفید برای مرورگر |
| `-e ORACLE_PWD=Oracle123` | رمز عبور کاربران `SYS`، `SYSTEM` و `PDBADMIN` |
| `-e ORACLE_CHARACTERSET=AL32UTF8` | character set استاندارد که WSO2 نیاز دارد |
| `-v .../oracle-data:/opt/oracle/oradata` | نگهداری persistent دیتابیس‌ها روی هاست |
| `-v .../oracle-init:/opt/oracle/scripts/setup` | ماونت اسکریپت‌های init (اگر خواستی بعداً استفاده کنی) |

### ۱.۴ صبر کن تا Oracle کاملاً آماده شود (مهم!)

اولین بار بالا آمدن Oracle XE بین ۵ تا ۱۰ دقیقه طول می‌کشد. چک کن:

```bash
docker logs -f apim-oracle
```

دنبال این خط بگرد (یعنی آماده است):

```
DATABASE IS READY TO USE!
```

وقتی این خط را دیدی، `Ctrl+C` بزن.

### ۱.۵ از طریق sqlplus داخل کانتینر تست کن

```bash
docker exec -it apim-oracle bash -lc "sqlplus sys/Oracle123@//localhost:1521/XEPDB1 as sysdba"
```

در محیط `SQL>` دستور زیر را بزن:

```sql
SHOW PDBS;
SELECT name, open_mode FROM v$pdbs;
EXIT;
```

باید PDB با نام `XEPDB1` را در حالت `READ WRITE` ببینی. اگر `READ WRITE` بود، اوراکل آماده است.

اگر `sqlplus` خطای connection داد، احتمالاً هنوز کاملاً بالا نیامده. چند دقیقه دیگر صبر کن و دوباره تست کن.

---

## مرحله ۲ – ساختن دیتابیس‌ها و کاربران مورد نیاز WSO2

WSO2 APIM 4.7.0 در حالت all-in-one به **۳ دیتابیس** نیاز دارد (deployment.toml پیش‌فرض پروژه، مسیر `all-in-one-apim/modules/distribution/product/src/main/conf/deployment.toml`):

| نام در deployment.toml | کاربرد | نام دیتابیس/PDB User |
|---|---|---|
| `[database.apim_db]` | اطلاعات API Manager (Publisher/Devportal/Gateway) | `apim_db` |
| `[database.shared_db]` | User Manager + Registry + داده‌های اشتراکی | `shared_db` |
| `[database.local]` (پیش‌فرض H2) | WSO2CARBON_DB – اختیاری، توصیه می‌شود H2 بماند | – |

همچنین `WSO2_MB_STORE_DB` (برای message broker داخلی) – طبق داکیومنت رسمی WSO2 بهتر است **H2 بماند** و تغییر نکند.

### ۲.۱ فایل ساخت کاربران و اسکیما را بساز

فایل `~/wso2-oracle-setup/oracle-init/01-create-users.sql` را با محتوای زیر بساز:

```sql
-- وصل به PDB پیش‌فرض
ALTER SESSION SET CONTAINER = XEPDB1;

-- ۱) shared_db
CREATE USER shared_db IDENTIFIED BY shared_db ACCOUNT UNLOCK
  DEFAULT TABLESPACE USERS
  TEMPORARY TABLESPACE TEMP
  QUOTA UNLIMITED ON USERS;
GRANT CONNECT, RESOURCE, CREATE VIEW, CREATE SEQUENCE, CREATE TRIGGER,
      CREATE PROCEDURE, CREATE SYNONYM, CREATE TABLE, CREATE TYPE
      TO shared_db;
GRANT DBA TO shared_db;
ALTER USER shared_db ENABLE EDITIONS;
COMMIT;

-- ۲) apim_db
CREATE USER apim_db IDENTIFIED BY apim_db ACCOUNT UNLOCK
  DEFAULT TABLESPACE USERS
  TEMPORARY TABLESPACE TEMP
  QUOTA UNLIMITED ON USERS;
GRANT CONNECT, RESOURCE, CREATE VIEW, CREATE SEQUENCE, CREATE TRIGGER,
      CREATE PROCEDURE, CREATE SYNONYM, CREATE TABLE, CREATE TYPE
      TO apim_db;
GRANT DBA TO apim_db;
ALTER USER apim_db ENABLE EDITIONS;
COMMIT;
```

> **نکته مهم:** رمزها در این مثال ساده (`shared_db` / `apim_db`) هستند تا با نمونه‌ی پیش‌فرض پروژه هماهنگ باشند. در محیط production حتماً رمزهای قوی بگذار و متناظراً در `deployment.toml` هم عوض کن.

### ۲.۲ اجرای اسکریپت ساخت کاربران

چون فایل داخل `oracle-init` ماونت شده (در مرحله ۱.۳)، Oracle به طور خودکار اسکریپت‌های `*.sql` و `*.sh` داخل `/opt/oracle/scripts/setup` را فقط در **اولین** اجرای کانتینر (وقتی دیتا خالی است) اجرا می‌کند. اگر قبلاً کانتینر را بدون این فایل بالا آوردی، الان دیگر اجرا نمی‌شود. پس دو راه داری:

**راه ۱ (تمیز، فقط اگر دیتای مهمی نداری):** کانتینر را پاک کن و از نو بالا بیاور:
```bash
docker stop apim-oracle
docker rm apim-oracle
rm -rf ~/wso2-oracle-setup/oracle-data/*
docker run -d --name apim-oracle ... (همان دستور مرحله ۱.۳)
```

**راه ۲ (توصیه‌شده):** اسکریپت را دستی اجرا کن:
```bash
docker cp ~/wso2-oracle-setup/oracle-init/01-create-users.sql apim-oracle:/tmp/
docker exec -it apim-oracle bash -lc "sqlplus sys/Oracle123@//localhost:1521/XEPDB1 as sysdba @/tmp/01-create-users.sql"
```

از sqlplus خارج شو (`EXIT;`) و حالا چک کن کاربران ساخته شده‌اند:

```bash
docker exec -it apim-oracle bash -lc "sqlplus sys/Oracle123@//localhost:1521/XEPDB1 as sysdba"
```

```sql
SELECT username, account_status FROM dba_users WHERE username IN ('APIM_DB','SHARED_DB');
EXIT;
```

باید هر دو را با `OPEN` ببینی.

### ۲.۳ تست اتصال با هر کاربر

```bash
docker exec -it apim-oracle bash -lc "sqlplus apim_db/apim_db@//localhost:1521/XEPDB1"
```

```sql
SELECT 'APIM_DB ok' AS status FROM dual;
EXIT;
```

```bash
docker exec -it apim-oracle bash -lc "sqlplus shared_db/shared_db@//localhost:1521/XEPDB1"
```

```sql
SELECT 'SHARED_DB ok' AS status FROM dual;
EXIT;
```

اگر هر دو پیام `ok` برگشت، مرحله ۲ تمام است.

---

## مرحله ۳ – آماده‌سازی توزیع WSO2 APIM

### ۳.۱ فایل zip را در هاست اکسترکت کن

```bash
cd ~/wso2-oracle-setup
cp /media/pc-58/Local\ Disk/MyFiles/IdeaProjects/wso2/h-amirabadi/product-apim/all-in-one-apim/modules/distribution/product/target/wso2am-4.7.0-SNAPSHOT.zip .
unzip wso2am-4.7.0-SNAPSHOT.zip
```

حالا باید پوشه‌ی `wso2am-4.7.0-SNAPSHOT/` ساخته شده باشد. این پوشه را به مسیر استاندارد منتقل کن:

```bash
sudo mv wso2am-4.7.0-SNAPSHOT /opt/wso2am-4.7.0
sudo chown -R $USER:$USER /opt/wso2am-4.7.0
```

از این به بعد هر جا `<API-M_HOME>` می‌بینی، یعنی `/opt/wso2am-4.7.0`.

### ۳.۲ ساختار اصلی پوشه را بشناس

```
/opt/wso2am-4.7.0
├── bin/                            ← اسکریپت‌های start/stop
├── repository/
│   ├── conf/
│   │   └── deployment.toml         ← فایل اصلی پیکربندی
│   ├── components/lib/             ← ojdbc11 jar از قبل اینجاست
│   └── database/                   ← H2 پیش‌فرض (دست نزن)
├── dbscripts/
│   ├── oracle.sql                  ← اسکریپت shared_db (WSO2_SHARED_DB)
│   ├── apimgt/oracle.sql           ← اسکریپت apim_db (WSO2AM_DB)
│   └── mb-store/h2-mb.sql          ← MB store – لازم نیست تغییر بدهی
└── lib/                            ← jar های WSO2
```

### ۳.۳ تأیید JDBC driver

```bash
ls /opt/wso2am-4.7.0/repository/components/lib/ | grep -i ojdbc
```

باید چیزی شبیه `ojdbc11-21.9.0.0.jar` ببینی. اگر نبود، از سایت Oracle دانلود کن (ojdbc11.jar مناسب JDK 21) و در همین پوشه بگذار.

---

## مرحله ۴ – اجرای اسکریپت‌های ساخت جداول روی Oracle

### ۴.۱ اسکریپت shared_db (User Manager + Registry)

```bash
docker cp /opt/wso2am-4.7.0/dbscripts/oracle.sql apim-oracle:/tmp/oracle-shared.sql
docker exec -it apim-oracle bash -lc "sqlplus shared_db/shared_db@//localhost:1521/XEPDB1"
```

```sql
-- اتصال به PDB و اجرای اسکریپت
@/tmp/oracle-shared.sql
```

> **نکته مهم:** sqlplus با `@` اسکریپت را اجرا می‌کند. هر خطایی دیدی، **متن خطا** را یادداشت کن. خطاهای `ORA-00955` یعنی جدول/sequence از قبل وجود دارد (معمولاً مهم نیست) ولی `ORA-00942` یعنی مشکل权限 است.

وقتی تمام شد:

```sql
SELECT table_name FROM user_tables ORDER BY table_name;
EXIT;
```

باید چند ده جدول (مربوط به Identity و Registry) لیست شود.

### ۴.۲ اسکریپت apim_db (اطلاعات API Manager)

```bash
docker cp /opt/wso2am-4.7.0/dbscripts/apimgt/oracle.sql apim-oracle:/tmp/oracle-apim.sql
docker exec -it apim-oracle bash -lc "sqlplus apim_db/apim_db@//localhost:1521/XEPDB1"
```

```sql
@/tmp/oracle-apim.sql
```

> **نکته:** اگر از Oracle 21c یا 23c استفاده می‌کنی، فایل `oracle_23c.sql` هم در همان پوشه هست که با نوع داده‌های جدیدتر سازگارتر است. ولی `oracle.sql` هم در 21c کار می‌کند.

وقتی تمام شد:

```sql
SELECT COUNT(*) AS tbl_count FROM user_tables;
EXIT;
```

انتظار می‌رود عدد بین ۲۰۰ تا ۴۰۰ باشد (تعداد زیادی جدول API Manager).

### ۴.۳ (اختیاری ولی توصیه‌شده) WSO2CARBON_DB را هم بساز

این دیتابیس اختیاری است. اگر می‌خواهی کاملاً external باشد:

فایل `~/wso2-oracle-setup/oracle-init/02-create-carbon.sql`:
```sql
ALTER SESSION SET CONTAINER = XEPDB1;
CREATE USER carbon_db IDENTIFIED BY carbon_db ACCOUNT UNLOCK
  DEFAULT TABLESPACE USERS
  TEMPORARY TABLESPACE TEMP
  QUOTA UNLIMITED ON USERS;
GRANT CONNECT, RESOURCE, CREATE VIEW, CREATE SEQUENCE, CREATE TRIGGER,
      CREATE PROCEDURE, CREATE SYNONYM, CREATE TABLE, CREATE TYPE
      TO carbon_db;
GRANT DBA TO carbon_db;
COMMIT;
```

سپس:
```bash
docker exec -it apim-oracle bash -lc "sqlplus sys/Oracle123@//localhost:1521/XEPDB1 as sysdba @/tmp/02-create-carbon.sql"
docker cp /opt/wso2am-4.7.0/dbscripts/oracle.sql apim-oracle:/tmp/oracle-carbon.sql
docker exec -it apim-oracle bash -lc "sqlplus carbon_db/carbon_db@//localhost:1521/XEPDB1"
@/tmp/oracle-carbon.sql
EXIT;
```

(اگر این مرحله را انجام ندهی، WSO2CARBON_DB به صورت H2 داخلی می‌ماند که در حالت development مشکلی ندارد.)

---

## مرحله ۵ – ویرایش deployment.toml

### ۵.۱ فایل فعلی را بکاپ بگیر

```bash
sudo cp /opt/wso2am-4.7.0/repository/conf/deployment.toml /opt/wso2am-4.7.0/repository/conf/deployment.toml.bak
```

### ۵.۲ تنظیم host اوراکل

WSO2 روی **هاست** (bare metal) اجرا می‌شود و Oracle در **داکر** است. WSO2 باید بتواند از هاست به اوراکل داخل داکر وصل شود.

میزبان `localhost` در داخل کانتینر داکر یعنی خود کانتینر. WSO2 وقتی از بیرون به اوراکل وصل می‌شود، باید IP هاست داکر را بدهد. ساده‌ترین راه:

**اگر روی لینوکس هستی و داکر روی host network معمولی است:** آدرس `localhost` از سمت WSO2 به Oracle درون کانتینر وصل می‌شود، چون پورت `1521` کانتینر روی هاست مپ شده. پس `localhost:1521` در `deployment.toml` درست است.

**اگر نشد:** باید IP هاست داکر را پیدا کنی:
```bash
# در لینوکس معمولاً docker0 اینترفیس است:
ip -4 addr show docker0 | grep inet
# یا
hostname -I
```
و در `deployment.toml` به جای `localhost` آن IP را بگذار.

### ۵.۳ deployment.toml را ویرایش کن

```bash
sudo nano /opt/wso2am-4.7.0/repository/conf/deployment.toml
```

تغییرات زیر را اعمال کن (یکی‌یکی پیدا و جایگزین کن):

#### الف) اتصال Oracle برای apim_db (هم اکنون از پیش تنظیم شده، فقط verify کن)

```toml
[database.apim_db]
type = "oracle"
url = "jdbc:oracle:thin:@localhost:1521/XEPDB1"
username = "apim_db"
password = "apim_db"
driver = "oracle.jdbc.driver.OracleDriver"
validationQuery = "SELECT 1 FROM DUAL"
pool_options.maxActive = 80
pool_options.maxWait = 60000
pool_options.minIdle = 5
```

> اگر `localhost` کار نکرد، به IP هاست داکر تغییر بده (مثلاً `url = "jdbc:oracle:thin:@172.17.0.1:1521/XEPDB1"`).

#### ب) اتصال Oracle برای shared_db (هم اکنون تنظیم شده)

```toml
[database.shared_db]
type = "oracle"
url = "jdbc:oracle:thin:@localhost:1521/XEPDB1"
username = "shared_db"
password = "shared_db"
driver = "oracle.jdbc.driver.OracleDriver"
validationQuery = "SELECT 1 FROM DUAL"
pool_options.maxActive = 80
pool_options.maxWait = 60000
pool_options.minIdle = 5
```

#### ج) (اختیاری) تغییر WSO2CARBON_DB به Oracle

اگر مرحله ۴.۳ را انجام دادی، خط `database.local` را به این تغییر بده:

```toml
[database.local]
type = "oracle"
url = "jdbc:oracle:thin:@localhost:1521/XEPDB1"
username = "carbon_db"
password = "carbon_db"
driver = "oracle.jdbc.driver.OracleDriver"
validationQuery = "SELECT 1 FROM DUAL"
```

در غیر این صورت، همان H2 پیش‌فرض را نگه‌دار.

#### د) hostname سرور WSO2 را تنظیم کن (برای اینکه URL ها درست باشند)

اگر می‌خواهی از مرورگر هاست یا سایر ماشین‌ها به WSO2 وصل شوی، `localhost` کافی نیست. پیدا کن `[server]` و:

```toml
[server]
hostname = "localhost"   ← اگر فقط از خود هاست تست می‌کنی، همین خوب است
#hostname = "your-server-ip"  ← اگر می‌خواهی از شبکه وصل شوی
```

#### ه) timezone جاوا

برای جلوگیری از خطای احتمالی `timezone region not found` (مخصوصاً اگر ساعت سیستم درست تنظیم نشده)، در شروع اسکریپت `api-manager.sh` این خط اضافه می‌شود (در مرحله ۶ توضیح می‌دهم).

فایل را ذخیره کن (`Ctrl+O`, `Enter`, `Ctrl+X`).

### ۵.۴ (اختیاری ولی مهم برای دیباگ اولیه) Hostname verification در keystore

اگر با خطای `SSL hostname verification` مواجه شدی، در `deployment.toml` اضافه کن:

```toml
[transport.https]
hostname_verifier = "AllowAll"
```

> **هشدار:** این تنظیم فقط برای محیط development/local است. در production نگذار.

---

## مرحله ۶ – تنظیم java options (timezone)

WSO2 داخلی به timezone نیاز دارد. برای اوراکل، بهتر است صراحتاً تنظیم شود:

```bash
sudo nano /opt/wso2am-4.7.0/bin/api-manager.sh
```

دنبال بلوک مربوط به `JAVA_OPTS` بگرد (معمولاً در ابتدای فایل است). خطی شبیه این پیدا می‌کنی:

```bash
JAVA_OPTS="$JAVA_OPTS -Xms256m -Xmx1024m ..."
```

یک خط بعد از آن اضافه کن:

```bash
JAVA_OPTS="$JAVA_OPTS -Duser.timezone='+03:30' -Dfile.encoding=UTF-8"
```

> عدد `+03:30` را با timezone خودت تنظیم کن (مثلاً `+00:00` برای UTC، `+03:30` برای تهران، `+04:30` برای کابل). برای production بهتر است `+00:00` (UTC) باشد.

ذخیره کن.

---

## مرحله ۷ – شروع WSO2 API Manager

### ۷.۱ مطمئن شو Oracle سالم است

```bash
docker ps | grep apim-oracle    # باید در حالت Up باشد
docker logs --tail 20 apim-oracle
```

### ۷.۲ WSO2 را شروع کن

```bash
cd /opt/wso2am-4.7.0/bin
./api-manager.sh
```

> اگر می‌خواهی در background اجرا شود:
> ```bash
> ./api-manager.sh --start
> ```
> و برای دیدن لاگ:
> ```bash
> tail -f /opt/wso2am-4.7.0/repository/logs/wso2carbon.log
> ```

### ۷.۳ صبر کن تا کامل بالا بیاید

WSO2 اولین بار بین ۲ تا ۵ دقیقه طول می‌کشد. در ترمینال دنبال این خط‌ها بگرد:

```
INFO - Startup Finalizer               WSO2 Carbon started in n.nnn sec
INFO - CarbonServerManager             Server           WSO2 API Manager       started
```

اگر خطایی دیدی:
- `ORA-...` ← مشکل اتصال به Oracle. بررسی کن `deployment.toml` و Oracle
- `BindException: Address already in use` ← پورت اشغال است: `sudo lsof -i :9443` و process را بکش
- `ClassNotFoundException: oracle.jdbc.driver.OracleDriver` ← ojdbc jar نیست، به `repository/components/lib/` اضافه کن
- `timezone region not found` ← به مرحله ۶ برو

### ۷.۴ وضعیت WSO2 را از Oracle چک کن

```bash
docker exec -it apim-oracle bash -lc "sqlplus shared_db/shared_db@//localhost:1521/XEPDB1"
```

```sql
SELECT username FROM all_users WHERE created > SYSDATE - 1/24;
EXIT;
```

> این query لیست sessionهای فعال را می‌دهد. در زمان استارت WSO2 باید sessionهایی از WSO2 ببینی.

---

## مرحله ۸ – تأیید نهایی از مرورگر

| URL | چه چیزی است |
|---|---|
| https://localhost:9443/publisher | API Publisher (نام کاربری: `admin` / رمز: `admin`) |
| https://localhost:9443/devportal | Developer Portal |
| https://localhost:9443/admin | Admin Portal |
| https://localhost:9443/carbon | Carbon Console |
| https://localhost:8243 | Gateway HTTPS (NIO) |
| http://localhost:9763 | Gateway HTTP (NIO) |

اگر hostname سرور را عوض کردی، `localhost` را با آن IP جایگزین کن.

> **هشدار مرورگر:** WSO2 از self-signed certificate استفاده می‌کند. مرورگر اخطار می‌دهد. باید `Advanced` → `Proceed to ...` را بزنی.

---

## مرحله ۹ – تست واقعی (smoke test)

### ۹.۱ از طریق Publisher یک API ساده بساز

1. وارد `https://localhost:9443/publisher` با `admin/admin` شو
2. `+ Create API` → `Design a New API`
3. نام `TestAPI`، Context `/test`، Version `1.0.0` بگذار
4. Endpoint: مثلاً `http://httpbin.org/get`
5. ذخیره کن، بعد `Lifecycle` را به `PUBLISHED` تغییر بده

### ۹.۲ از Devportal subscribe کن

1. وارد `https://localhost:9443/devportal` با `admin/admin` شو
2. `TestAPI` را پیدا و Subscribe کن
3. یک Application بساز (مثلاً `DefaultApp`) و توکن JWT بگیر

### ۹.۳ صدا بزن

```bash
curl -k -H "Authorization: Bearer <YOUR_TOKEN>" https://localhost:8243/test/1.0.0/get
```

اگر جواب `httpbin.org/get` را گرفتی، یعنی کل مسیر (Publisher → Key Manager → Gateway → Oracle → ...) درست کار می‌کند.

### ۹.۴ بررسی لاگ‌ها

- لاگ WSO2: `/opt/wso2am-4.7.0/repository/logs/wso2carbon.log`
- لاگ Oracle: `docker logs -f apim-oracle`
- لاگ خطای خاص API: `tail -f /opt/wso2am-4.7.0/repository/logs/wso2carbon.log | grep -i error`

---

## مرحله ۱۰ – توقف و نگهداری

### توقف WSO2

```bash
cd /opt/wso2am-4.7.0/bin
./api-manager.sh stop
```

### توقف Oracle

```bash
docker stop apim-oracle
```

### بعداً دوباره راه‌اندازی

```bash
# Oracle
docker start apim-oracle

# صبر کن Oracle کامل بالا بیاید
docker logs -f apim-oracle
# وقتی "DATABASE IS READY TO USE!" دیدی: Ctrl+C

# WSO2
cd /opt/wso2am-4.7.0/bin
./api-manager.sh
```

### حذف کامل (با احتیاط!)

```bash
# WSO2
sudo rm -rf /opt/wso2am-4.7.0

# Oracle (همه دیتا پاک می‌شود)
docker stop apim-oracle
docker rm apim-oracle
rm -rf ~/wso2-oracle-setup/oracle-data
```

---

## خلاصه‌ی سریع – فقط دستورها

اگر می‌خواهی همه را در یک اسکریپت بریزی (مفید برای تکرار):

```bash
#!/bin/bash
set -e

# --- 1) Oracle up
docker run -d --name apim-oracle --restart unless-stopped \
  -p 1521:1521 -p 5500:5500 \
  -e ORACLE_PWD=Oracle123 \
  -e ORACLE_CHARACTERSET=AL32UTF8 \
  -v ~/wso2-oracle-setup/oracle-data:/opt/oracle/oradata \
  -v ~/wso2-oracle-setup/oracle-init:/opt/oracle/scripts/setup \
  container-registry.oracle.com/database/express:21.3.0-xe

echo "Waiting for Oracle to be ready (5-10 min)..."
until docker logs apim-oracle 2>&1 | grep -q "DATABASE IS READY TO USE"; do
  sleep 15
done
echo "Oracle ready."

# --- 2) Create users
cat > ~/wso2-oracle-setup/oracle-init/01-create-users.sql <<'SQL'
ALTER SESSION SET CONTAINER = XEPDB1;
CREATE USER shared_db IDENTIFIED BY shared_db ACCOUNT UNLOCK
  DEFAULT TABLESPACE USERS TEMPORARY TABLESPACE TEMP QUOTA UNLIMITED ON USERS;
GRANT CONNECT, RESOURCE, CREATE VIEW, CREATE SEQUENCE, CREATE TRIGGER,
      CREATE PROCEDURE, CREATE SYNONYM, CREATE TABLE, CREATE TYPE TO shared_db;
GRANT DBA TO shared_db;
ALTER USER shared_db ENABLE EDITIONS;
CREATE USER apim_db IDENTIFIED BY apim_db ACCOUNT UNLOCK
  DEFAULT TABLESPACE USERS TEMPORARY TABLESPACE TEMP QUOTA UNLIMITED ON USERS;
GRANT CONNECT, RESOURCE, CREATE VIEW, CREATE SEQUENCE, CREATE TRIGGER,
      CREATE PROCEDURE, CREATE SYNONYM, CREATE TABLE, CREATE TYPE TO apim_db;
GRANT DBA TO apim_db;
ALTER USER apim_db ENABLE EDITIONS;
COMMIT;
SQL

# چون init فقط اولین بار اجرا می‌شود، دستی اجرا می‌کنیم:
docker cp ~/wso2-oracle-setup/oracle-init/01-create-users.sql apim-oracle:/tmp/
docker exec -i apim-oracle bash -lc "sqlplus sys/Oracle123@//localhost:1521/XEPDB1 as sysdba @/tmp/01-create-users.sql"

# --- 3) Extract WSO2
cd /opt && sudo unzip -o ~/wso2am-4.7.0-SNAPSHOT.zip
sudo chown -R $USER:$USER /opt/wso2am-4.7.0

# --- 4) Run dbscripts
docker cp /opt/wso2am-4.7.0/dbscripts/oracle.sql apim-oracle:/tmp/oracle-shared.sql
docker exec -i apim-oracle bash -lc "sqlplus shared_db/shared_db@//localhost:1521/XEPDB1 @/tmp/oracle-shared.sql"

docker cp /opt/wso2am-4.7.0/dbscripts/apimgt/oracle.sql apim-oracle:/tmp/oracle-apim.sql
docker exec -i apim-oracle bash -lc "sqlplus apim_db/apim_db@//localhost:1521/XEPDB1 @/tmp/oracle-apim.sql"

# --- 5) deployment.toml is already configured in source; only override if needed

# --- 6) Start WSO2
cd /opt/wso2am-4.7.0/bin && ./api-manager.sh
```

> **یادآوری مهم:** این اسکریپت فقط initialization را انجام می‌دهد. ویرایش `deployment.toml` و `api-manager.sh` (برای timezone) را **دستی** انجام بده یا با `sed` به اسکریپت اضافه کن.

---

## نکات عیب‌یابی رایج

| علامت | علت محتمل | راه‌حل |
|---|---|---|
| `ORA-01017: invalid username/password` | رمز اشتباه یا PDB اشتباه | چک کن `XEPDB1` در URL باشد، رمز را در `sqlplus` هم امتحان کن |
| `ORA-12505: TNS:listener does not currently know of SID given in connect descriptor` | `XE` به جای `XEPDB1` | `url` را به `jdbc:oracle:thin:@localhost:1521/XEPDB1` عوض کن |
| `ORA-00942: table or view does not exist` | اسکریپت dbscript اجرا نشده | دوباره مرحله ۴ را اجرا کن |
| `Could not create connection to database server` | WSO2 از هاست به Oracle در داکر وصل نمی‌شود | IP هاست داکر را در `url` بگذار (مثل `172.17.0.1:1521`) |
| `timezone region not found` | timezone جاوا تنظیم نشده | مرحله ۶ را انجام بده |
| مرورگر `Unable to connect` | پورت 9443 بسته است یا WSO2 بالا نیامده | `sudo ss -tlnp \| grep 9443` بزن، `wso2carbon.log` را چک کن |
| خطای `host name verification` SSL | hostname سرور WSO2 با cert یکی نیست | در `deployment.toml` موقتاً `hostname_verifier = "AllowAll"` بگذار (فقط dev) |
| WSO2 خیلی کند بالا می‌آید | RAM کم | `JAVA_OPTS` در `api-manager.sh` را به `-Xms512m -Xmx2048m` افزایش بده |

---

## نکات امنیتی production (اگر بعداً خواستی production کنی)

1. **رمزهای پیش‌فرض را عوض کن:** `admin/admin`، `apim_db/apim_db`، `shared_db/shared_db` و حتماً `ORACLE_PWD`
2. **cert واقعی بگذار** به جای self-signed (مراجعه به مستندات WSO2 در مورد تغییر keystore)
3. **`hostname_verifier = "AllowAll"` را حذف کن**
4. **پورت Oracle (1521) را از بیرون expose نکن** – فقط از شبکه‌ی داخلی داکر قابل دسترسی باشد
5. **WSO2 را پشت reverse proxy (nginx/apache) بگذار** برای SSL termination
6. **backup منظم** از volume `oracle-data` بگیر
7. **WSO2 Analytics** (ELK) اگر نیاز داری فعال کن (`apim.analytics.enable = true`)

---

## خلاصه‌ی نهایی

| مرحله | کار | زمان تقریبی |
|---|---|---|
| ۱ | Oracle XE در داکر | 10 دقیقه (اولین بار بیشتر) |
| ۲ | ساخت کاربران Oracle | 2 دقیقه |
| ۳ | Extract فایل WSO2 zip | 1 دقیقه |
| ۴ | اجرای dbscript روی Oracle | 5 دقیقه |
| ۵ | ویرایش deployment.toml | 5 دقیقه |
| ۶ | تنظیم JAVA_OPTS | 1 دقیقه |
| ۷ | شروع WSO2 | 2-5 دقیقه |
| ۸ | تست در مرورگر | 5 دقیقه |
| ۹ | smoke test واقعی | 10 دقیقه |
| **مجموع** | | **~40 دقیقه** |

اگر در هر مرحله به مشکل خوردی، خروجی خطا را یادداشت کن و به من بگو تا دقیق‌تر راهنمایی کنم.
