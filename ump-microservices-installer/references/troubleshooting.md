# 排障手册

按“现象 -> 根因 -> 处理 -> 验证”记录。遇到问题先按当前阶段定位，不要直接重装。

## 1. SQL Server

### 1.1 服务 Running，但 1433 未监听，sqlcmd 连不上

现象：`Get-Service MSSQLSERVER` 为 Running，但 1433 不通。

根因：TCP/IP 协议虽启用，具体 IP 条目未启用；本机曾经是 `IP1 Enabled=0`。

处理：

1. 读取：

```powershell
Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQLServer\SuperSocketNetLib\Tcp\IP1'
```

2. 将 `Enabled` 改为 1，并重启 `MSSQLSERVER` 服务。需要管理员权限，普通沙箱进程做不到，应通过 UAC 提权。
3. 验证：

```powershell
Test-NetConnection -ComputerName 127.0.0.1 -Port 1433 -InformationLevel Quiet
```

### 1.2 Codex 沙箱 sqlcmd 报“客户端不支持加密”

现象：`-E` 和 `-U/-P` 都报 TLS 错误；用户自己的 cmd 里同一命令正常。

根因：Codex 沙箱进程的 SSL 上下文不完整，不是 SQL Server 或密码问题。

处理：数据库命令改在沙箱外执行，并向用户请求授权。不要反复改 SQL Server 加密配置。

### 1.3 配置中的数据库账号在本机不存在

现象：微服务日志出现 `Login failed for user 'amistelco'`，或直接验证该账号登录失败。

处理：

- 先只读检查登录：`sys.server_principals`。
- 本机有效账号由用户确认。不要自己创建账号或猜测密码。
- 需要改 Nacos 配置时，把业务数据源 `username` 改为用户确认的账号。

## 2. Nacos

### 2.1 微服务能拉配置但配置是另一台机器的内容

现象：Nacos 配置列表只有 demo 配置，或没有 `application-ump-dev.yml` 等 UMP 配置。

根因：旧 Nacos 服务连接 `Nacos_config`；项目 Nacos 连接的是 `AMISTELCO`。

处理：

1. 用项目自带 Nacos，取消旧服务注册，不要沿用旧机器安装目录。
2. 检查 Nacos `application.properties` 的 `db.url.0`，应指向 SQL Server 的 `AMISTELCO`。
3. 用 `GET /nacos/v1/cs/configs` 检查 totalCount，应为 71。

### 2.2 配置中心还保留旧 IP

现象：gateway 启动日志连接旧 IP 的 Redis 超时；数据库、ActiveMQ 连接旧 IP 失败。

处理：

- 先列出所有含 IP 的配置，不要只改一个 dataId。
- 将本机中间件地址统一为 `127.0.0.1`。
- 外部业务地址（FTP、9899 等）本机没有时，先问用户，不要盲改。
- 改完配置后重启相关微服务，不能只依赖动态刷新。

### 2.3 Nacos 服务列表为空或缺少服务

现象：配置中心正常，但 `GET /nacos/v1/ns/service/list` 返回 0 或缺某个服务。

处理顺序：

1. 确认 Windows 服务状态不是 Paused/Stopped。
2. 查看 `<module>\log\<service>.stderr.log` 和 `.stdout.log` 尾部。
3. 确认启动参数 jar 路径完整，尤其路径带空格时必须带引号。
4. 确认 `bootstrap.yml` 中 Nacos 地址为 `127.0.0.1:8848`。
5. 服务正常启动后约 30 秒应完成注册。

## 3. NSSM 与 Windows 服务

### 3.1 `Unable to access jarfile C:\Code\Skill`

根因：注册脚本通过 PowerShell 调用 `nssm set AppParameters` 时，路径引号被剥掉，java 只收到第一段路径。

处理：

- 检查：

```powershell
Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\<service>\Parameters' |
  Select-Object -ExpandProperty AppParameters
```

- 修复：用注册表 API 直写含引号的完整路径。
- 已封装在 `fix-microservice-params.ps1`；注册脚本也应始终用注册表 API 写 `AppParameters`。

### 3.2 Nginx 服务一直 Paused，80 未监听

根因：Nginx `-p` 参数路径带空格且引号丢失，nginx 找不到 prefix，启动后立即退出。

处理：

- `nginx.exe -t -p "<nginx目录>\"` 先验证配置语法。
- 修复 NSSM `AppParameters` 为 `-p "<完整目录>"`。
- 设置 `AppStdout`/`AppStderr` 后再启动。
- 已封装在 `fix-nginx.ps1`。

## 4. ActiveMQ

### 4.1 启动失败：Failed to bind to 61614

现象：wrapper 服务退出，日志显示绑定 `0.0.0.0:61614` 失败。

根因：本机有其他进程（例如 TBProtect）占用 61614。

处理：

- 不要停止用户的安全软件。
- 将 `activemq.xml` 中 ws connector 端口改为未占用端口（本机曾改为 61624）。
- 重启 ActiveMQ 后验证 61616、8161、新 ws 端口。

## 5. 微服务启动

### 5.1 gateway 连接 Redis 超时

日志类似：

```text
ConnectTimeoutException ... 172.23.139.156:6379
```

处理：Nacos 中 gateway 的 Redis host 改为 `127.0.0.1`，重启 gateway。

### 5.2 mdms 一直 Waiting for changelog lock

现象：mdms 服务 Running，但 Nacos 无 `ump-mdms`，日志反复等待。

根因：Flowable 事件引擎的 `FLW_EV_DATABASECHANGELOGLOCK` 残留 `LOCKED=1`。

处理：

1. 先查锁：

```sql
SELECT ID, LOCKED, LOCKGRANTED, LOCKEDBY
FROM FLW_EV_DATABASECHANGELOGLOCK;
```

2. 停止 mdms，清锁，再启动：

```sql
UPDATE FLW_EV_DATABASECHANGELOGLOCK
SET LOCKED=0, LOCKGRANTED=NULL, LOCKEDBY=NULL
WHERE ID=1;
```

3. 已封装在 `fix-mdms-lock.ps1`。数据库账号密码由用户提供，脚本不内置凭据。

### 5.3 system 启动失败或外部地址不可用

检查点：

- system gateway 是否仍为旧 IP。
- logging path 是否指向不存在的旧盘符。
- MongoDB 本机未安装时，先确认是否强依赖；不要在未确认时自行安装或注释配置。
- license、企业微信、9899 等外部服务是否本机不可达。

## 6. 快速定位日志

微服务注册日志位置：

```text
<project>\item project\MicroServices\<module>\log\<service>.stdout.log
<project>\item project\MicroServices\<module>\log\<service>.stderr.log
```

中间件日志：

- Nacos：`nacos2.2.1\logs\nacos.log`、`bin\nacos_console.log`
- ActiveMQ：`apache-activemq-5.15.12\data\wrapper.log`、`activemq.log`
- Nginx：`nginx-1.19.1\logs\error.log`、`log\nginx.stderr.log`
- Redis：由 RedisService 输出，必要时用 `redis-cli ping`

