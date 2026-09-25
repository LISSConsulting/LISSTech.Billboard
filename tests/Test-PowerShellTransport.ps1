$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path $PSScriptRoot -Parent
$assemblyPath = Join-Path $repositoryRoot 'src/LISSTech.Billboard/bin/Debug/net472/LISSTech.Billboard.dll'
$modulePath = Join-Path $repositoryRoot 'LISSTech.Billboard.psm1'

[Reflection.Assembly]::LoadFrom($assemblyPath) | Out-Null
$module = Import-Module $modulePath -Force -PassThru

try {
    $notification = New-BillboardNotification `
        -Type Alert `
        -Title 'Persistent alert' `
        -Message 'This notification must not dismiss automatically.' `
        -Timeout 0 `
        -Modal

    $cliArgs = @(& $module {
        param($Config)
        ConvertTo-CliArgs $Config
    } $notification)

    $parsed = [LISSTech.Billboard.Services.CliParser]::Parse([string[]]$cliArgs)
    if ($parsed.Timeout -ne 0 -or $parsed.EffectiveTimeout -ne 0) {
        throw "Explicit zero timeout was not preserved by the host argument transport."
    }

    Write-Host 'Passed: explicit zero timeout survives the PowerShell-to-host transport.'
}
finally {
    Remove-Module $module -Force
}
