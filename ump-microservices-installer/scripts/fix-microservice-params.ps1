[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [string]$HadoopHome = 'C:\hadoop',
    [string]$NacosUrl = 'http://127.0.0.1:8848'
)

$ErrorActionPreference = 'Continue'

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
} else {
    $ProjectRoot = (Resolve-Path $ProjectRoot).Path
}

$microRoot = Join-Path $ProjectRoot 'item project\MicroServices'
$logFile = Join-Path $ProjectRoot 'fix-microservices.log'

function Write-Log([string]$msg) {
    $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
    Add-Content -Path $logFile -Value $line -Encoding UTF8
    Write-Output $line
}

if (Test-Path $logFile) { Clear-Content $logFile }
Write-Log 'fix microservice params begin'

$services = @(
    @{ Name = 'umbp-modules-system'; Module = 'umbp-System';  Jar = 'umbp-modules-system.jar' },
    @{ Name = 'umbp-gateway';        Module = 'umbp-gateway'; Jar = 'umbp-gateway.jar' },
    @{ Name = 'ump-base-server';     Module = 'umbp-base';    Jar = 'ump-base-server.jar' },
    @{ Name = 'ump-mdas-server';     Module = 'umbp-mdas';    Jar = 'ump-mdas-server.jar' },
    @{ Name = 'ump-mdms-server';     Module = 'umbp-mdms';    Jar = 'ump-mdms-server.jar' }
)

foreach ($s in $services) {
    $jarPath = Join-Path $microRoot "$($s.Module)\$($s.Jar)"
    $params = '-Dfile.encoding=utf-8 ' +
        '-Xms512m -Xmx1024m ' +
        '-XX:MetaspaceSize=128m -XX:MaxMetaspaceSize=512m ' +
        '-Dhadoop.home.dir="' + $HadoopHome + '" ' +
        '--add-opens java.base/java.lang=ALL-UNNAMED ' +
        '--add-opens java.base/java.math=ALL-UNNAMED ' +
        '-jar "' + $jarPath + '"'

    $regKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("SYSTEM\CurrentControlSet\Services\$($s.Name)\Parameters", $true)
    if ($regKey) {
        $regKey.SetValue('AppParameters', $params, [Microsoft.Win32.RegistryValueKind]::String)
        $regKey.Close()
        Write-Log "$($s.Name) AppParameters fixed"
    } else {
        Write-Log "$($s.Name) Parameters key not found"
    }
}

foreach ($s in $services) {
    $svc = Get-Service -Name $s.Name -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -ne 'Stopped') {
        try {
            Stop-Service -Name $s.Name -Force -ErrorAction Stop
            Write-Log "$($s.Name) stopped before restart"
        } catch {
            Write-Log "$($s.Name) stop failed: $($_.Exception.Message)"
        }
    }
}

foreach ($s in $services) {
    try {
        Start-Service -Name $s.Name
        Write-Log "$($s.Name) start requested"
    } catch {
        Write-Log "$($s.Name) start failed: $($_.Exception.Message)"
    }
    Start-Sleep -Seconds 30
}

Start-Sleep -Seconds 60

try {
    $r = Invoke-WebRequest -UseBasicParsing -Uri ($NacosUrl + '/nacos/v1/ns/service/list?pageNo=1&pageSize=100') -TimeoutSec 10
    Write-Log "nacos service list: $($r.Content)"
} catch {
    Write-Log "nacos service list failed: $($_.Exception.Message)"
}

Write-Log 'fix microservice params done'

