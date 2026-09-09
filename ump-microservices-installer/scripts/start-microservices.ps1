[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [string]$NacosUrl = 'http://127.0.0.1:8848'
)

$ErrorActionPreference = 'Continue'

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
} else {
    $ProjectRoot = (Resolve-Path $ProjectRoot).Path
}

$microRoot = Join-Path $ProjectRoot 'item project\MicroServices'
$logFile = Join-Path $ProjectRoot 'start-microservices.log'

function Write-Log([string]$msg) {
    $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
    Add-Content -Path $logFile -Value $line -Encoding UTF8
    Write-Output $line
}

if (Test-Path $logFile) { Clear-Content $logFile }
Write-Log 'microservices start begin'

$services = 'umbp-modules-system', 'umbp-gateway', 'ump-base-server', 'ump-mdas-server', 'ump-mdms-server'
foreach ($s in $services) {
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
    Start-Sleep -Seconds 30
}

Write-Log 'waiting 60s for nacos registration'
Start-Sleep -Seconds 60

try {
    $r = Invoke-WebRequest -UseBasicParsing -Uri ($NacosUrl + '/nacos/v1/ns/service/list?pageNo=1&pageSize=100') -TimeoutSec 10
    Write-Log "nacos service list: $($r.Content)"
} catch {
    Write-Log "nacos service list failed: $($_.Exception.Message)"
}

$appNames = 'ump-base', 'umbp-gateway', 'ump-mdas', 'ump-mdms', 'umbp-system'
foreach ($name in $appNames) {
    try {
        $u = $NacosUrl + '/nacos/v1/ns/instance/list?serviceName=' + $name
        $j = (Invoke-WebRequest -UseBasicParsing -Uri $u -TimeoutSec 10).Content | ConvertFrom-Json
        $count = if ($j.hosts) { @($j.hosts).Count } else { 0 }
        Write-Log "nacos instance $name : $count"
    } catch {
        Write-Log "nacos instance $name check failed: $($_.Exception.Message)"
    }
}

$modules = @(
    @{ Svc = 'umbp-modules-system'; Dir = 'umbp-System' },
    @{ Svc = 'umbp-gateway';        Dir = 'umbp-gateway' },
    @{ Svc = 'ump-base-server';     Dir = 'umbp-base' },
    @{ Svc = 'ump-mdas-server';     Dir = 'umbp-mdas' },
    @{ Svc = 'ump-mdms-server';     Dir = 'umbp-mdms' }
)
foreach ($m in $modules) {
    $logPath = Join-Path $microRoot "$($m.Dir)\log\$($m.Svc).stdout.log"
    if (Test-Path $logPath) {
        $tail = Get-Content $logPath -Tail 5 -ErrorAction SilentlyContinue
        Write-Log "--- $($m.Svc) stdout tail ---"
        if ($tail) { $tail | ForEach-Object { Write-Log $_ } }
    } else {
        Write-Log "$($m.Svc) stdout log not created yet"
    }
}

Write-Log 'microservices start done'

