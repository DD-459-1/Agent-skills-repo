[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [string]$NacosUrl = 'http://127.0.0.1:8848'
)

$ErrorActionPreference = 'SilentlyContinue'

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
} else {
    $ProjectRoot = (Resolve-Path $ProjectRoot).Path
}

$services = 'Redis', 'Nacos', 'ActiveMQ', 'Nginx',
    'ump-base-server', 'umbp-gateway', 'ump-mdas-server', 'ump-mdms-server', 'umbp-modules-system'
$ports = 6379, 8848, 61616, 8161, 80, 8080, 8081, 8026, 8036, 8046

"Windows services"
foreach ($s in $services) {
    $svc = Get-Service -Name $s
    $status = if ($svc) { $svc.Status.ToString() } else { 'NOT_FOUND' }
    "{0,-24} {1}" -f $s, $status
}

""
"TCP ports"
foreach ($p in $ports) {
    $ok = Test-NetConnection -ComputerName 127.0.0.1 -Port $p -InformationLevel Quiet -WarningAction SilentlyContinue
    "{0,-10} {1}" -f $p, $(if ($ok) { 'OK' } else { 'FAIL' })
}

""
"Nacos"
try {
    $r = Invoke-WebRequest -UseBasicParsing -Uri ($NacosUrl + '/nacos/v1/console/health/readiness') -TimeoutSec 10
    "readiness $($r.StatusCode) $($r.Content)"
} catch {
    "readiness FAILED $($_.Exception.Message)"
}

$appNames = 'ump-base', 'umbp-gateway', 'ump-mdas', 'ump-mdms', 'umbp-system'
foreach ($name in $appNames) {
    try {
        $u = $NacosUrl + '/nacos/v1/ns/instance/list?serviceName=' + $name
        $j = (Invoke-WebRequest -UseBasicParsing -Uri $u -TimeoutSec 10).Content | ConvertFrom-Json
        $count = if ($j.hosts) { @($j.hosts).Count } else { 0 }
        "{0,-20} instances={1}" -f $name, $count
    } catch {
        "{0,-20} FAILED" -f $name
    }
}

""
"Nginx"
try {
    $r = Invoke-WebRequest -UseBasicParsing -Uri 'http://127.0.0.1/' -TimeoutSec 8
    "http://127.0.0.1/ $($r.StatusCode)"
} catch {
    "http://127.0.0.1/ FAILED $($_.Exception.Message)"
}

