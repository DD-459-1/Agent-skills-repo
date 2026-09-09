[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ScriptPath,
    [string[]]$ScriptArguments = @()
)

$resolved = (Resolve-Path $ScriptPath).Path
$quotedArgs = $ScriptArguments | ForEach-Object {
    if ($_ -match '\s' -and $_ -notmatch '^".*"$') {
        '"' + $_ + '"'
    } else {
        $_
    }
}
$joinedArgs = $quotedArgs -join ' '
$command = '-NoProfile -ExecutionPolicy Bypass -File "' + $resolved + '"'
if ($joinedArgs) {
    $command += ' ' + $joinedArgs
}

Start-Process powershell -Verb RunAs -ArgumentList $command -Wait -WindowStyle Hidden
