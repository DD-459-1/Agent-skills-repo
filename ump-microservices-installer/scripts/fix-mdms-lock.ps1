[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [string]$SqlServer = 'localhost',
    [string]$Database = 'AMISTELCO',
    [string]$SqlUser = '',
    [string]$SqlPassword = '',
    [string]$NacosUrl = 'http://127.0.0.1:8848'
)

$ErrorActionPreference = 'Continue'

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
} else {
    $ProjectRoot = (Resolve-Path $ProjectRoot).Path
}

$logFile = Join-Path $ProjectRoot 'fix-mdms.log'

function Write-Log([string]$msg) {
    $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
    Add-Content -Path $logFile -Value $line -Encoding UTF8
    Write-Output $line
}

if (Test-Path $logFile) { Clear-Content $logFile }
Write-Log 'fix mdms changelog lock begin'

if ([string]::IsNullOrWhiteSpace($SqlUser) -or [string]::IsNullOrWhiteSpace($SqlPassword)) {
    Write-Log 'SQL credentials are required. Ask the user before running this script.'
    throw 'SqlUser and SqlPassword are required.'
}

$svc = Get-Service -Name 'ump-mdms-server' -ErrorAction SilentlyContinue
if ($svc -and $svc.Status -ne 'Stopped') {
    try {
        Stop-Service -Name 'ump-mdms-server' -Force -ErrorAction Stop
        Start-Sleep -Seconds 8
        Write-Log 'ump-mdms-server stopped'
    } catch {
        Write-Log "ump-mdms-server stop failed: $($_.Exception.Message)"
    }
}

$query = 'SET NOCOUNT ON; UPDATE FLW_EV_DATABASECHANGELOGLOCK SET LOCKED=0, LOCKGRANTED=NULL, LOCKEDBY=NULL WHERE ID=1; SELECT ID, LOCKED FROM FLW_EV_DATABASECHANGELOGLOCK;'
& sqlcmd -S $SqlServer -U $SqlUser -P $SqlPassword -C -d $Database -Q $query -W
Write-Log "clear lock sqlcmd exit=$LASTEXITCODE"

try {
    Start-Service -Name 'ump-mdms-server'
    Write-Log 'ump-mdms-server start requested'
} catch {
    Write-Log "ump-mdms-server start failed: $($_.Exception.Message)"
}

Start-Sleep -Seconds 45

try {
    $u = $NacosUrl + '/nacos/v1/ns/instance/list?serviceName=ump-mdms'
    $j = (Invoke-WebRequest -UseBasicParsing -Uri $u -TimeoutSec 10).Content | ConvertFrom-Json
    $count = if ($j.hosts) { @($j.hosts).Count } else { 0 }
    Write-Log "nacos instance ump-mdms : $count"
} catch {
    Write-Log "nacos instance ump-mdms check failed: $($_.Exception.Message)"
}

Write-Log 'fix mdms changelog lock done'

