[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [string]$JavaPath = 'C:\Program Files\Java\jdk-17\bin\java.exe',
    [string]$NssmPath = 'C:\APP\nssm\nssm-2.24\win64\nssm.exe',
    [string]$HadoopHome = 'C:\hadoop'
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
} else {
    $ProjectRoot = (Resolve-Path $ProjectRoot).Path
}

$root = Join-Path $ProjectRoot 'item project'
$logFile = Join-Path $ProjectRoot 'register-services.log'

function Write-Log([string]$msg) {
    $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
    Add-Content -Path $logFile -Value $line -Encoding UTF8
    Write-Output $line
}

if (Test-Path $logFile) { Clear-Content $logFile }
Write-Log 'register services begin'

$redisDir = Join-Path $root 'MiddleWare\Redis-6.2.19-Windows-x64-msys2-with-Service'
$redisExe = Join-Path $redisDir 'RedisService.exe'
$redisConf = Join-Path $redisDir 'redis.conf'
if (Get-Service -Name 'Redis' -ErrorAction SilentlyContinue) {
    Write-Log 'Redis service already exists, skip'
} else {
    $redisCmd = 'sc.exe create Redis binpath="\"' + $redisExe + '\" -c \"' + $redisConf + '\"" start=demand'
    cmd /c $redisCmd
    if ($LASTEXITCODE -eq 0) {
        Write-Log 'Redis registered'
    } else {
        Write-Log "Redis sc create failed, exit=$LASTEXITCODE"
    }
}

$nginxDir = Join-Path $root 'MiddleWare\nginx-1.19.1'
$nginxExe = Join-Path $nginxDir 'nginx.exe'
if (Get-Service -Name 'Nginx' -ErrorAction SilentlyContinue) {
    Write-Log 'Nginx service already exists, skip'
} else {
    & $NssmPath install Nginx $nginxExe
    & $NssmPath set Nginx AppDirectory $nginxDir
    & $NssmPath set Nginx Start SERVICE_DEMAND_START
    Write-Log 'Nginx registered'
}

$nginxLogDir = Join-Path $nginxDir 'log'
if (-not (Test-Path $nginxLogDir)) {
    New-Item -ItemType Directory -Path $nginxLogDir | Out-Null
}
$nginxReg = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SYSTEM\CurrentControlSet\Services\Nginx\Parameters', $true)
if ($nginxReg) {
    $nginxReg.SetValue('AppParameters', ('-p "' + $nginxDir + '"'), [Microsoft.Win32.RegistryValueKind]::String)
    $nginxReg.SetValue('AppStdout', (Join-Path $nginxLogDir 'nginx.stdout.log'), [Microsoft.Win32.RegistryValueKind]::String)
    $nginxReg.SetValue('AppStderr', (Join-Path $nginxLogDir 'nginx.stderr.log'), [Microsoft.Win32.RegistryValueKind]::String)
    $nginxReg.SetValue('AppStdoutCreationDisposition', 4, [Microsoft.Win32.RegistryValueKind]::DWord)
    $nginxReg.SetValue('AppStderrCreationDisposition', 4, [Microsoft.Win32.RegistryValueKind]::DWord)
    $nginxReg.Close()
}

$services = @(
    @{ Name = 'ump-base-server';     Module = 'umbp-base';    Jar = 'ump-base-server.jar' },
    @{ Name = 'umbp-gateway';        Module = 'umbp-gateway'; Jar = 'umbp-gateway.jar' },
    @{ Name = 'ump-mdas-server';     Module = 'umbp-mdas';    Jar = 'ump-mdas-server.jar' },
    @{ Name = 'ump-mdms-server';     Module = 'umbp-mdms';    Jar = 'ump-mdms-server.jar' },
    @{ Name = 'umbp-modules-system'; Module = 'umbp-System';  Jar = 'umbp-modules-system.jar' }
)

foreach ($s in $services) {
    $dir = Join-Path $root "MicroServices\$($s.Module)"
    $jarPath = Join-Path $dir $s.Jar
    $logDir = Join-Path $dir 'log'
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir | Out-Null
    }

    $params = '-Dfile.encoding=utf-8 ' +
        '-Xms512m -Xmx1024m ' +
        '-XX:MetaspaceSize=128m -XX:MaxMetaspaceSize=512m ' +
        '-Dhadoop.home.dir="' + $HadoopHome + '" ' +
        '--add-opens java.base/java.lang=ALL-UNNAMED ' +
        '--add-opens java.base/java.math=ALL-UNNAMED ' +
        '-jar "' + $jarPath + '"'

    if (Get-Service -Name $s.Name -ErrorAction SilentlyContinue) {
        Write-Log "$($s.Name) service exists, refresh parameters"
    } else {
        & $NssmPath install $s.Name $JavaPath
        if ($LASTEXITCODE -ne 0) {
            Write-Log "$($s.Name) nssm install failed, exit=$LASTEXITCODE"
            continue
        }
        Write-Log "$($s.Name) registered"
    }

    & $NssmPath set $s.Name AppDirectory $dir
    & $NssmPath set $s.Name AppStdout (Join-Path $logDir ($s.Name + '.stdout.log'))
    & $NssmPath set $s.Name AppStderr (Join-Path $logDir ($s.Name + '.stderr.log'))
    & $NssmPath set $s.Name AppStdoutCreationDisposition 4
    & $NssmPath set $s.Name AppStderrCreationDisposition 4
    & $NssmPath set $s.Name Start SERVICE_DEMAND_START

    $regKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("SYSTEM\CurrentControlSet\Services\$($s.Name)\Parameters", $true)
    if ($regKey) {
        $regKey.SetValue('AppParameters', $params, [Microsoft.Win32.RegistryValueKind]::String)
        $regKey.Close()
    }
}

Write-Log 'register services done'

