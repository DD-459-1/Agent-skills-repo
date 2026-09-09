# 标准安装工作流

目标：从项目自带文件把整套 UMP 环境在本机注册为 Windows 服务并成功启动。

## 0. 环境检查

运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\check-environment.ps1"
```

重点确认：

- Windows 64 位（AMD64）。
- JDK 17 可执行，默认 `C:\Program Files\Java\jdk-17\bin\java.exe`。
- NSSM 2.24 的 `win64\nssm.exe` 可用。
- `C:\hadoop` 存在（mdas/mdms 启动参数需要）。
- SQL Server 服务为 `MSSQLSERVER`，1433 可连接。
- 5 个 jar 都在对应模块目录，且是 Spring Boot 可执行包。

检查后先修正明显缺口，不要直接注册。

## 1. 数据库

1. 数据库脚本由用户提供，运行前询问目标库名和 SQL Server 连接凭据。
2. Codex 沙箱内运行 sqlcmd 会因 TLS 报“客户端不支持加密”，必须使用沙箱外执行并请用户授权。
3. 建库命令参考：

```powershell
sqlcmd -S Localhost -U <user> -P <password> -C -i "<project>\item project\SQL\script.sql"
```

4. 建库后用 `sys.databases`、`INFORMATION_SCHEMA.TABLES`、`CONFIG_INFO` 验证。
5. 当前 UMP 业务库是 `AMISTELCO`，其中保存 Nacos 配置中心数据。

## 2. 注册 Windows 服务

### 2.1 替换旧中间件

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\replace-middleware.ps1" -ProjectRoot "<project>"
```

该脚本：

- 停止并取消旧 Nacos / ActiveMQ Windows 服务，不删除旧目录。
- 用项目目录注册 Nacos（NSSM 包装 `nacos2.2.1\bin\startup.cmd`）。
- 用项目目录注册 ActiveMQ（官方 wrapper，`InstallService.bat`）。

### 2.2 注册 Redis、Nginx、微服务

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\register-services.ps1" -ProjectRoot "<project>"
```

该脚本：

- Redis 使用自带 `RedisService.exe -c redis.conf`。
- Nginx 使用 NSSM 运行 `nginx.exe -p "<nginx目录>"`。
- 5 个微服务使用 JDK 17 + `java -jar`，stdout/stderr 分开写入模块 `log\`。

所有注册/启动脚本需要管理员权限。在 Codex 中通过 UAC 提权运行，避免用普通沙箱进程直接执行。

## 3. 配置适配

服务注册前先检查 Nacos 中配置和 bootstrap 是否残留旧机器信息。

### 3.1 检查 Nacos 配置

```powershell
Invoke-WebRequest 'http://127.0.0.1:8848/nacos/v1/cs/configs?search=accurate&dataId=&group=&pageNo=1&pageSize=200&tenant='
```

确认 `totalCount=71`，并筛选旧 IP：

```text
172.23.139.156
172.21.29.143
172.21.29.121
```

### 3.2 修改 Nacos 业务配置

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\update-nacos-configs.ps1" `
  -NacosUrl http://127.0.0.1:8848 `
  -OldHost 172.23.139.156 `
  -NewHost 127.0.0.1 `
  -OldDbUser amistelco `
  -NewDbUser sa
```

该脚本更新 `application-ump-dev.yml`、`umbp-system-dev.yml`、`umbp-gateway-dev.yml`、`ump-activemq-dev.yml`。

### 3.3 检查 bootstrap.yml

- Nacos `server-addr` 应为本机 `127.0.0.1:8848`。
- system 模块的 `gateway` 应为本机地址 `http://127.0.0.1:8080`。
- 日志路径不能指向旧机器盘符。
- MongoDB、FTP、9899 等外部服务地址如果本机没有，先报告用户确认，不要盲目改成 localhost。

## 4. 启动顺序

先核心中间件，Nginx 先保持停止：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\start-core.ps1" -ProjectRoot "<project>"
```

再启动微服务：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\start-microservices.ps1" -ProjectRoot "<project>"
```

依赖顺序：

```text
umbp-modules-system -> umbp-gateway -> ump-base-server -> ump-mdas-server -> ump-mdms-server
```

最后启动 Nginx：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\fix-nginx.ps1" -ProjectRoot "<project>"
```

Spring Boot 服务正常约 30 秒内完成启动。不要无意义地等数分钟。

## 5. 验证

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\verify-services.ps1" -ProjectRoot "<project>"
```

成功标准：

- 9 个服务全部 Running：Redis、Nacos、ActiveMQ、Nginx、5 个微服务。
- 端口可达：6379、8848、61616、8161、80、8080、8081、8026、8036、8046。
- Nacos 服务列表有 5 个服务，各至少 1 个实例：

```text
ump-base, umbp-gateway, ump-mdas, ump-mdms, umbp-system
```

- `http://127.0.0.1/` 返回 HTTP 200。

## 6. 更新记录

每完成一个阶段，同步更新项目根目录的 `INSTALL_NOTES.md`。后续制作或扩展 skill 时以此为基础。

