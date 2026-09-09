---
name: ump-microservices-installer
description: Install, register, configure, start, verify, and troubleshoot the UMP Windows microservices deployment (Nacos, ActiveMQ, Redis, Nginx, and five Spring Boot services). Use when working with this project's item project directory or extending its installer.
---

# UMP Microservices Installer

用于在 Windows 上安装、注册、启动和排查 UMP 微服务套件。目标工程结构如下：

```text
item project/
|-- MicroServices/   # 5 个 Spring Boot jar 及其 bootstrap.yml
|-- MiddleWare/      # Nacos、ActiveMQ、Redis、Nginx 自带包
`-- SQL/             # 建库脚本
```

## 固定规则

- 所有中间件必须使用 `item project/MiddleWare` 下自带版本。若本机已有旧 Windows 服务，只取消注册旧服务（不删除旧目录），再用项目自带目录重新注册。
- 数据库是 SQL Server，不是 MySQL。Nacos 配置中心持久化在 SQL Server 的 `AMISTELCO` 库，UMP 配置共 71 条。
- 微服务必须用 `java -jar` 注册，不要依赖原来的启动 bat。stdout 和 stderr 分两个文件写到各模块的 `log/`；已有 `logs/` 是应用自身日志，不要混用。
- 启动顺序：Redis -> Nacos -> ActiveMQ；`umbp-modules-system` -> `umbp-gateway` -> `ump-base-server` / `ump-mdas-server` / `ump-mdms-server`；Nginx 最后。
- 服务注册、启动、修改注册表需要管理员权限。在 Codex 中执行 `sqlcmd` 时，沙箱进程的 TLS 层不可用，必须在沙箱外执行并让用户授权。
- 不要猜测或复用默认账号密码。任何数据库、Nacos 控制台、ActiveMQ 或业务登录需要账密时，先停下来询问用户。
- 含空格的服务参数（jar 路径、nginx `-p` 路径）不能用 PowerShell 调用 `nssm set` 写入，引号会丢失。必须用注册表 API 直接写 `AppParameters`。

## 工作流程

先读 [references/workflow.md](references/workflow.md)，按顺序完成环境检查、建库、注册服务、配置适配、启动和验证。

遇到启动失败、端口异常、Nacos 无实例时，先读 [references/troubleshooting.md](references/troubleshooting.md)，不要凭印象跳过诊断。

需要修改服务表、Nacos dataId、端口、中间件版本或旧机器地址时，读 [references/configuration-map.md](references/configuration-map.md)。

## 脚本

脚本都在 [scripts/](scripts/) 下。运行前先看脚本顶部参数说明：

- `check-environment.ps1`：检查 Windows 架构、JDK、NSSM、SQL Server、中间件、jar 和现有服务。
- `replace-middleware.ps1`：删除旧 Nacos/ActiveMQ 服务，注册项目自带版本。
- `register-services.ps1`：注册 Redis、Nginx 和 5 个微服务，并写好分离日志。
- `start-core.ps1`：启动 Redis/Nacos/ActiveMQ，并把 Nginx 复位为停止状态。
- `start-microservices.ps1`：按依赖顺序启动 5 个微服务并检查 Nacos。
- `update-nacos-configs.ps1`：把 Nacos 配置中心中的旧机器 IP/数据库账号替换为本机值。
- `fix-microservice-params.ps1`：修复微服务 NSSM 参数并重启。
- `fix-mdms-lock.ps1`：清理 Flowable changelog 残留锁并重启 mdms。
- `fix-nginx.ps1`：修复 Nginx NSSM 参数并重启。
- `verify-services.ps1`：统一验证服务、端口、HTTP 和 Nacos 实例。
- `invoke-elevated.ps1`：从普通 PowerShell 用 UAC 提权运行其他脚本，例如 `invoke-elevated.ps1 -ScriptPath ".\register-services.ps1" -ScriptArguments "-ProjectRoot","<项目根目录>"`。

所有涉及注册/启动的脚本都要在管理员 PowerShell 中运行；Codex 环境可先让用户通过 UAC 授权。默认 `-ProjectRoot` 从脚本所在位置向上三级解析；如果 skill 被移动到其他目录，必须显式传入项目根目录。

## 扩展方式

- 新增微服务：在 `register-services.ps1`、`start-microservices.ps1`、`fix-microservice-params.ps1` 的服务表中增加 Name/Module/Jar。
- 新增中间件：在 `replace-middleware.ps1` 或 `register-services.ps1` 中增加注册块，并更新 `references/configuration-map.md`。
- 新增排障案例：追加到 `references/troubleshooting.md`，保留“现象、根因、处理、验证”结构。
- 新增脚本：放在 `scripts/`，在本文件脚本清单中登记，并写清参数和运行权限要求。
