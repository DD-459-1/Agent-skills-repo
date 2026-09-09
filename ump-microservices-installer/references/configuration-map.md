# 配置地图

新增服务、中间件或修改启动参数时先查这里，避免把地址、端口、路径写散。

## 1. 路径

项目根目录默认：

```text
C:\Code\Skill make\Automated installation of UMP microservices
```

主要目录：

```text
<project>\item project\MicroServices\
<project>\item project\MiddleWare\
<project>\item project\SQL\
<project>\result skill\ump-microservices-installer\
```

skill 内脚本默认把 `ProjectRoot` 解析为脚本所在位置向上三级。skill 被移到其他目录后必须显式传 `-ProjectRoot`。

## 2. Windows 服务

### 微服务

| Windows 服务名 | 模块目录 | jar | Nacos 应用名 | HTTP 端口 |
| --- | --- | --- | --- | --- |
| `umbp-modules-system` | `umbp-System` | `umbp-modules-system.jar` | `umbp-system` | 8081 |
| `umbp-gateway` | `umbp-gateway` | `umbp-gateway.jar` | `umbp-gateway` | 8080 |
| `ump-base-server` | `umbp-base` | `ump-base-server.jar` | `ump-base` | 8026 |
| `ump-mdas-server` | `umbp-mdas` | `ump-mdas-server.jar` | `ump-mdas` | 8046 |
| `ump-mdms-server` | `umbp-mdms` | `ump-mdms-server.jar` | `ump-mdms` | 8036 |

启动顺序：system -> gateway -> base -> mdas -> mdms。

### 中间件

| Windows 服务名 | 自带目录 | 注册方式 | 端口 |
| --- | --- | --- | --- |
| `Nacos` | `MiddleWare\nacos2.2.1` | NSSM 包装 `bin\startup.cmd` | 8848 / 9848 |
| `ActiveMQ` | `MiddleWare\apache-activemq-5.15.12` | 官方 wrapper | 61616 / 8161 / 61624 |
| `Redis` | `MiddleWare\Redis-6.2.19-Windows-x64-msys2-with-Service` | `RedisService.exe -c redis.conf` | 6379 |
| `Nginx` | `MiddleWare\nginx-1.19.1` | NSSM 包装 `nginx.exe -p <dir>` | 80 |

## 3. 微服务注册参数

Java：

```text
C:\Program Files\Java\jdk-17\bin\java.exe
```

JVM 参数：

```text
-Dfile.encoding=utf-8
-Xms512m -Xmx1024m
-XX:MetaspaceSize=128m -XX:MaxMetaspaceSize=512m
-Dhadoop.home.dir=C:\hadoop
--add-opens java.base/java.lang=ALL-UNNAMED
--add-opens java.base/java.math=ALL-UNNAMED
-jar "<完整 jar 路径>"
```

日志：

```text
<module>\log\<service>.stdout.log
<module>\log\<service>.stderr.log
```

应用自身日志继续放在 `<module>\logs\`，不要与注册日志混用。

## 4. Nacos

服务配置：

```text
server.port=8848
db.url.0=jdbc:sqlserver://127.0.0.1:1433;databaseName=AMISTELCO;encrypt=true;trustServerCertificate=true
nacos.core.auth.enabled=false
```

数据库账号写在 Nacos `conf\application.properties`。凭据按用户要求获取，不写死在 skill 脚本中。

主要 dataId：

```text
application-dev.yml
application-ump-dev.yml
server-port.yml
ump-base-dev.yml
ump-mdas-dev.yml
ump-mdms-dev.yml
umbp-gateway-dev.yml
umbp-system-dev.yml
ump-activemq-dev.yml
ump-all-dev.yml
```

`server-port.yml`：

```text
base 8026, mdas 8046, mdms 8036
sts 8056, message 8066, all 8006, demo 8016
```

## 5. 关键地址替换

本机适配时曾使用的替换：

| 旧值 | 新值 | 使用位置 |
| --- | --- | --- |
| `172.23.139.156` | `127.0.0.1` | Nacos 中 Redis、DB、gateway、domain、ActiveMQ |
| `172.21.29.143` | 按业务确认 | mdas FTP、历史配置，未盲目替换 |
| 数据库用户 `amistelco` | `sa` 或用户确认账号 | Nacos 业务数据源 |

本机网卡地址可能包括：

```text
172.21.29.28
192.168.5.1
192.168.47.1
10.14.244.182
```

判断“旧 IP”时先运行 `ipconfig`，不要把当前有效网卡 IP 一律当作旧值。

## 6. 账号密码

- SQL Server：运行建库、清锁、授权前询问用户。
- Nacos：默认 `auth.enabled=false`；若启用认证，需要控制台/API 账密时询问用户。
- ActiveMQ：连接 broker 需要账密时询问用户，不要复用默认 admin 假设。
- 业务系统登录账号：不猜测，不修改，只报告。

## 7. 扩展清单

新增一个微服务时需要同步：

1. `register-services.ps1` 的 `$services`。
2. `start-microservices.ps1` 的启动顺序和 app 名。
3. `fix-microservice-params.ps1` 的修复列表。
4. `verify-services.ps1` 的端口和 Nacos 服务名。
5. 本文件的 Windows 服务表。
6. `references/workflow.md` 的验证标准。

新增一个中间件时需要同步：

1. 注册脚本和启动脚本。
2. 本文件的中间件表。
3. 排障手册中的日志路径和已知问题。

