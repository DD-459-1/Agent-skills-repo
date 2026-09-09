[CmdletBinding()]
param(
    [string]$NacosUrl = 'http://127.0.0.1:8848',
    [string]$OldHost = '172.23.139.156',
    [string]$NewHost = '127.0.0.1',
    [string]$OldDbUser = 'amistelco',
    [string]$NewDbUser = 'sa'
)

$ErrorActionPreference = 'Stop'

$base = $NacosUrl.TrimEnd('/') + '/nacos/v1/cs/configs'
$ids = 'application-ump-dev.yml', 'umbp-system-dev.yml', 'umbp-gateway-dev.yml', 'ump-activemq-dev.yml'

foreach ($id in $ids) {
    $url = $base + '?dataId=' + $id + '&group=DEFAULT_GROUP&tenant='
    $r = Invoke-WebRequest -UseBasicParsing -Uri $url -TimeoutSec 10
    $content = $r.Content
    $new = $content -replace [regex]::Escape($OldHost), $NewHost
    if ($id -in 'application-ump-dev.yml', 'umbp-system-dev.yml') {
        $pattern = '(?m)^(\s*)username:\s*' + [regex]::Escape($OldDbUser) + '\s*$'
        $new = $new -replace $pattern, '$1username: ' + $NewDbUser
    }

    $body = @{
        dataId  = $id
        group   = 'DEFAULT_GROUP'
        content = $new
        type    = 'yaml'
    }
    $p = Invoke-WebRequest -UseBasicParsing -Method Post -Body $body -Uri $base -TimeoutSec 15
    "{0} : {1} {2}" -f $id, $p.StatusCode, $p.Content
}

