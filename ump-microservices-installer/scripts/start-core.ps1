[CmdletBinding()]
param(
    [string]$ProjectRoot = ''
)

$ErrorActionPreference = 'Continue'

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
} else {
    $ProjectRoot = (Resolve-Path $ProjectRoot).Path
}

$logFile = Join-Path $ProjectRoot 'start-services.log'

function Write-Log([string]$msg) {
    $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
    Add-Content -Path $logFile -Value $line -Encoding UTF8
    Write-Output $line
}

if (Test-Path $logFile) { Clear-Content $logFile }
Write-Log 'core middleware start begin (nginx deferred)'

$nginx = Get-Service -Name 'Nginx' -ErrorAction SilentlyContinue
if ($nginx -and $nginx.Status -ne 'Stopped') {
    try {
        Stop-Service -Name 'Nginx' -Force -ErrorAction Stop
        Write-Log 'Nginx reset to stopped'
    } catch {
        Write-Log "Nginx stop failed: $($_.Exception.Message)"
    }
}

foreach ($s in 'Redis', 'Nacos', 'ActiveMQ') {
    $svc = Get-Service -Name $s -ErrorAction SilentlyContinue
    if (-not $svc) {
        Write-Log "$s service not found"
        continue
    }
    if ($svc.Status -eq 'Running') {
        Write-Log "$s already running"
    } else {
        try {
            Start-Service -Name $s
            Write-Log "$s start requested"
        } catch {
            Write-Log "$s start failed: $($_.Exception.Message)"
        }
    }
}

function Wait-Port([int]$port, [string]$name, [int]$timeoutSec = 120) {
    $deadline = (Get-Date).AddSeconds($timeoutSec)
    $ok = $false
    while ((Get-Date) -lt $deadline) {
        if (Test-NetConnection -ComputerName 127.0.0.1 -Port $port -InformationLevel Quiet -WarningAction SilentlyContinue) {
            $ok = $true
            break
        }
        Start-Sleep -Seconds 3
    }
    if ($ok) {
        Write-Log "$name listening on $port"
    } else {
        Write-Log "$name NOT listening on $port after $timeoutSec s"
    }
}

Wait-Port 6379 'Redis'
Wait-Port 8848 'Nacos'
Wait-Port 61616 'ActiveMQ'
Wait-Port 8161 'ActiveMQ web'

try {
    $r = Invoke-WebRequest -UseBasicParsing -Uri 'http://127.0.0.1:8848/nacos/v1/console/health/readiness' -TimeoutSec 10
    Write-Log "nacos readiness: $($r.StatusCode) $($r.Content)"
} catch {
    Write-Log "nacos readiness failed: $($_.Exception.Message)"
}

try {
    $c = Invoke-WebRequest -UseBasicParsing -Uri 'http://127.0.0.1:8848/nacos/v1/cs/configs?search=accurate&dataId=&group=&pageNo=1&pageSize=200&tenant=' -TimeoutSec 10
    $json = $c.Content | ConvertFrom-Json
    Write-Log "nacos config totalCount: $($json.totalCount)"
} catch {
    Write-Log "nacos config list failed: $($_.Exception.Message)"
}

Write-Log 'core middleware start done'

