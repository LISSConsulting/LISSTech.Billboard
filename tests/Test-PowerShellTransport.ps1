$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path $PSScriptRoot -Parent
$assemblyPath = Join-Path $repositoryRoot 'src/LISSTech.Billboard/bin/Debug/net472/LISSTech.Billboard.dll'
$modulePath = Join-Path $repositoryRoot 'LISSTech.Billboard.psm1'

if (-not ('DelayedBillboardPipeServer' -as [type])) {
    Add-Type -TypeDefinition @'
using System.IO;
using System.IO.Pipes;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

public static class DelayedBillboardPipeServer
{
    public static Task WriteAfterDelayAsync(string pipeName, string json, int delayMilliseconds)
    {
        return Task.Run(async () =>
        {
            await Task.Delay(delayMilliseconds).ConfigureAwait(false);
            using (var pipe = new NamedPipeServerStream(
                pipeName,
                PipeDirection.Out,
                1,
                PipeTransmissionMode.Byte,
                PipeOptions.Asynchronous))
            {
                await pipe.WaitForConnectionAsync().ConfigureAwait(false);
                using (var writer = new StreamWriter(pipe, new UTF8Encoding(false)))
                {
                    await writer.WriteAsync(json).ConfigureAwait(false);
                }
            }
        });
    }
}
'@
}

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

    $pipeName = "LISSTech.Billboard.Test.$([guid]::NewGuid().ToString('N'))"
    $expectedJson = '{"button":"Thanks, Marcin!","value":"dismissed","index":0,"dismissed":false,"timeout":false}'
    $serverTask = [DelayedBillboardPipeServer]::WriteAfterDelayAsync($pipeName, $expectedJson, 250)
    $result = & $module {
        param($Name)
        Read-BillboardPipe -PipeName $Name -TimeoutSeconds 0
    } $pipeName
    $null = $serverTask.GetAwaiter().GetResult()

    if ($result.Value -ne 'dismissed' -or $result.Button -ne 'Thanks, Marcin!') {
        throw 'An unlimited pipe wait did not return the delayed Billboard response.'
    }

    Write-Host 'Passed: timeout zero waits for a delayed named-pipe response.'
}
finally {
    Remove-Module $module -Force
}
