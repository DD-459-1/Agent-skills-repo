[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [string]$NssmPath = 'C:\APP\nssm\nssm-2.24\win64\nssm.exe'
)

$ErrorActionPreference = 'Continue'

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
} else {
    $ProjectRoot = (Resolve-Path $ProjectRoot).Path
}

$root = Join-Path $ProjectRoot 'item project'
$logFile = Join-Path $ProjectRoot 'replace-middleware.log'

function Write-Log([string]$msg) {
    $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
    Add-Content -Path $logFile -Value $line -Encoding UTF8
    Write-Output $line
}

if (Test-Path $logFile) { Clear-Content $logFile }
Write-Log 'replace middleware begin'

foreach ($svcName in 'Nacos', 'ActiveMQ') {
    $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
    if (-not $svc) {
        Write-Log "$svcName service not found, nothing to remove"
        continue
    }
    if ($svc.Status -ne 'Stopped') {
        try {
            Stop-Service -Name $svcName -Force -ErrorAction Stop
            Start-Sleep -Seconds 5
            Write-Log "$svcName stopped"
        } catch {
            Write-Log "$svcName stop failed: $($_.Exception.Message)"
        }
    }
    sc.exe delete $svcName | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Log "$svcName old service deleted"
    } else {
        Write-Log "$svcName delete returned exit=$LASTEXITCODE"
    }
}

$nacosDir = Join-Path $root 'MiddleWare\nacos2.2.1'
if (Get-Service -Name 'Nacos' -ErrorAction SilentlyContinue) {
    Write-Log 'Nacos service still exists, skip install'
} else {
    & $NssmPath install Nacos (Join-Path $nacosDir 'bin\startup.cmd')
    if ($LASTEXITCODE -eq 0) {
        & $NssmPath set Nacos AppDirectory (Join-Path $nacosDir 'bin')
        & $NssmPath set Nacos AppStdout (Join-Path $nacosDir 'bin\nacos_console.log')
        & $NssmPath set Nacos AppStderr (Join-Path $nacosDir 'bin\nacos_console.log')
        & $NssmPath set Nacos Start SERVICE_DEMAND_START
        Write-Log "Nacos registered from project: $nacosDir"
    } else {
        Write-Log "Nacos nssm install failed, exit=$LASTEXITCODE"
    }
}

$mqDir = Join-Path $root 'MiddleWare\apache-activemq-5.15.12'
if (Get-Service -Name 'ActiveMQ' -ErrorAction SilentlyContinue) {
    Write-Log 'ActiveMQ service still exists, skip install'
} else {
    $installBat = Join-Path $mqDir 'bin\win64\InstallService.bat'
    & cmd /c "`"$installBat`""
    if ($LASTEXITCODE -eq 0) {
        Write-Log "ActiveMQ registered from project: $mqDir"
    } else {
        Write-Log "ActiveMQ InstallService.bat returned exit=$LASTEXITCODE"
    }
}

Write-Log 'replace middleware done'

