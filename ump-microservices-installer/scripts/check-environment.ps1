[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [string]$JavaPath = 'C:\Program Files\Java\jdk-17\bin\java.exe',
    [string]$NssmPath = 'C:\APP\nssm\nssm-2.24\win64\nssm.exe',
    [string]$HadoopHome = 'C:\hadoop'
)

$ErrorActionPreference = 'SilentlyContinue'

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $defaultRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
    $ProjectRoot = $defaultRoot
} else {
    $ProjectRoot = (Resolve-Path $ProjectRoot).Path
}

$item = Join-Path $ProjectRoot 'item project'
$micro = Join-Path $item 'MicroServices'
$middle = Join-Path $item 'MiddleWare'

function Line([string]$label, [bool]$ok, [string]$detail = '') {
    $state = if ($ok) { 'OK' } else { 'MISSING' }
    if ($detail) { "{0,-24} {1,-8} {2}" -f $label, $state, $detail }
    else { "{0,-24} {1}" -f $label, $state }
}

"System"
Line 'OS architecture' $true ("$env:PROCESSOR_ARCHITECTURE, Is64Bit=$([Environment]::Is64BitOperatingSystem)")
Line 'Java' (Test-Path $JavaPath) $JavaPath
Line 'Maven' ([bool](Get-Command mvn)) ''
Line 'Node' ([bool](Get-Command node)) ''
Line 'NSSM win64' (Test-Path $NssmPath) $NssmPath
Line 'Hadoop home' (Test-Path $HadoopHome) $HadoopHome
Line 'Project item dir' (Test-Path $item) $item

""
"SQL Server"
$mssql = Get-Service MSSQLSERVER
Line 'MSSQLSERVER service' ([bool]$mssql) ("Status=" + $mssql.Status)
$sqlPort = Test-NetConnection -ComputerName 127.0.0.1 -Port 1433 -InformationLevel Quiet -WarningAction SilentlyContinue
Line 'SQL Server 1433' $sqlPort ''

""
"Middleware"
$mw = @(
    @('nacos2.2.1', 'bin\startup.cmd'),
    @('apache-activemq-5.15.12', 'bin\win64\InstallService.bat'),
    @('Redis-6.2.19-Windows-x64-msys2-with-Service', 'RedisService.exe'),
    @('nginx-1.19.1', 'nginx.exe')
)
foreach ($m in $mw) {
    $p = Join-Path $middle "$($m[0])\$($m[1])"
    Line $m[0] (Test-Path $p) $p
}

""
"Microservice jars"
$jars = @(
    @('umbp-base', 'ump-base-server.jar'),
    @('umbp-gateway', 'umbp-gateway.jar'),
    @('umbp-mdas', 'ump-mdas-server.jar'),
    @('umbp-mdms', 'ump-mdms-server.jar'),
    @('umbp-System', 'umbp-modules-system.jar')
)
foreach ($j in $jars) {
    $p = Join-Path $micro "$($j[0])\$($j[1])"
    $exists = Test-Path $p
    $size = if ($exists) { '{0:N1} MB' -f ((Get-Item $p).Length / 1MB) } else { '' }
    Line $j[0] $exists $size
}

""
"Existing services"
$serviceNames = @(
    'MSSQLSERVER'
    'Redis'
    'Nacos'
    'ActiveMQ'
    'Nginx'
    'ump-base-server'
    'umbp-gateway'
    'ump-mdas-server'
    'ump-mdms-server'
    'umbp-modules-system'
)
foreach ($s in $serviceNames) {
    $svc = Get-Service -Name $s -ErrorAction Stop
    Write-Output ('{0,-24} {1,-8} {2}' -f $s, $(if ($svc) { 'OK' } else { 'MISSING' }), $(if ($svc) { $svc.Status.ToString() } else { '' }))
}
