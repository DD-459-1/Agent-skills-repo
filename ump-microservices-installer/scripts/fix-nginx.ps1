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

$nginxDir = Join-Path $ProjectRoot 'item project\MiddleWare\nginx-1.19.1'
$logFile = Join-Path $ProjectRoot 'fix-nginx.log'

function Write-Log([string]$msg) {
    $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
    Add-Content -Path $logFile -Value $line -Encoding UTF8
    Write-Output $line
}

if (Test-Path $logFile) { Clear-Content $logFile }
Write-Log 'fix nginx begin'

$nginxLogDir = Join-Path $nginxDir 'log'
if (-not (Test-Path $nginxLogDir)) {
    New-Item -ItemType Directory -Path $nginxLogDir | Out-Null
}

$reg = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SYSTEM\CurrentControlSet\Services\Nginx\Parameters', $true)
if ($reg) {
    $reg.SetValue('AppParameters', ('-p "' + $nginxDir + '"'), [Microsoft.Win32.RegistryValueKind]::String)
    $reg.SetValue('AppStdout', (Join-Path $nginxLogDir 'nginx.stdout.log'), [Microsoft.Win32.RegistryValueKind]::String)
    $reg.SetValue('AppStderr', (Join-Path $nginxLogDir 'nginx.stderr.log'), [Microsoft.Win32.RegistryValueKind]::String)
    $reg.SetValue('AppStdoutCreationDisposition', 4, [Microsoft.Win32.RegistryValueKind]::DWord)
    $reg.SetValue('AppStderrCreationDisposition', 4, [Microsoft.Win32.RegistryValueKind]::DWord)
    $reg.Close()
    Write-Log 'Nginx AppParameters fixed with quotes'
} else {
    Write-Log 'Nginx Parameters key not found'
}

$svc = Get-Service -Name 'Nginx' -ErrorAction SilentlyContinue
if ($svc -and $svc.Status -ne 'Stopped') {
    try {
        Stop-Service -Name 'Nginx' -Force -ErrorAction Stop
        Start-Sleep -Seconds 3
        Write-Log 'Nginx reset to stopped'
    } catch {
        Write-Log "Nginx stop failed: $($_.Exception.Message)"
    }
}

try {
    Start-Service -Name 'Nginx'
    Write-Log 'Nginx start requested'
} catch {
    Write-Log "Nginx start failed: $($_.Exception.Message)"
}

Start-Sleep -Seconds 10

$s = Get-Service -Name 'Nginx'
Write-Log "Nginx service status: $($s.Status)"
$portOk = Test-NetConnection -ComputerName 127.0.0.1 -Port 80 -InformationLevel Quiet -WarningAction SilentlyContinue
Write-Log "port 80 reachable: $portOk"

if (Test-Path "$nginxLogDir\nginx.stderr.log") {
    Get-Content "$nginxLogDir\nginx.stderr.log" -Tail 10 -ErrorAction SilentlyContinue | ForEach-Object { Write-Log "nginx stderr: $_" }
}

Write-Log 'fix nginx done'

