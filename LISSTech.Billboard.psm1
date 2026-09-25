$script:BinDir = Join-Path $PSScriptRoot 'Bin'
$script:BillboardExe = Join-Path $script:BinDir 'Billboard.exe'
$script:ServiceUIExe = Join-Path $script:BinDir 'ServiceUI.exe'

# ── Builder Cmdlets ──────────────────────────────────────────────────────────

function New-BillboardButton {
    [CmdletBinding()]
    [OutputType([LISSTech.Billboard.Models.ButtonDefinition])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Label,

        [Parameter(Mandatory)]
        [string]$Value,

        [ValidateSet('Ghost', 'Primary', 'Danger')]
        [string]$Style = 'Ghost',

        [string]$Defer
    )

    $button = [LISSTech.Billboard.Models.ButtonDefinition]::new()
    $button.GetType().GetProperty('Label').SetValue($button, $Label)
    $button.GetType().GetProperty('Value').SetValue($button, $Value)
    $button.GetType().GetProperty('Style').SetValue($button, [LISSTech.Billboard.Models.ButtonStyle]::$Style)

    if ($PSBoundParameters.ContainsKey('Defer') -and $Defer) {
        $button.GetType().GetProperty('Defer').SetValue($button, (ConvertTo-DeferTimeSpan $Defer))
    }

    return $button
}

function New-BillboardBranding {
    [CmdletBinding()]
    [OutputType([LISSTech.Billboard.Models.BrandingConfig])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [string]$Logo
    )

    $branding = [LISSTech.Billboard.Models.BrandingConfig]::new()
    $branding.GetType().GetProperty('Name').SetValue($branding, $Name)
    if ($PSBoundParameters.ContainsKey('Logo') -and $Logo) {
        $branding.GetType().GetProperty('Logo').SetValue($branding, $Logo)
    }

    return $branding
}

function New-BillboardInput {
    [CmdletBinding()]
    [OutputType([LISSTech.Billboard.Models.InputDefinition])]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$Label = 'Response',

        [string]$Placeholder,

        [string]$DefaultValue,

        [switch]$Required,

        [switch]$Multiline,

        [ValidateRange(1, 10000)]
        [int]$MaxLength = 1024
    )

    if ($PSBoundParameters.ContainsKey('DefaultValue') -and $DefaultValue.Length -gt $MaxLength) {
        throw 'DefaultValue cannot exceed MaxLength.'
    }

    $definition = [LISSTech.Billboard.Models.InputDefinition]::new()
    $definition.GetType().GetProperty('Label').SetValue($definition, $Label)
    $definition.GetType().GetProperty('Required').SetValue($definition, [bool]$Required)
    $definition.GetType().GetProperty('Multiline').SetValue($definition, [bool]$Multiline)
    $definition.GetType().GetProperty('MaxLength').SetValue($definition, $MaxLength)
    if ($PSBoundParameters.ContainsKey('Placeholder')) {
        $definition.GetType().GetProperty('Placeholder').SetValue($definition, $Placeholder)
    }
    if ($PSBoundParameters.ContainsKey('DefaultValue')) {
        $definition.GetType().GetProperty('DefaultValue').SetValue($definition, $DefaultValue)
    }

    return $definition
}

function New-BillboardNotification {
    [CmdletBinding()]
    [OutputType([LISSTech.Billboard.Models.BillboardConfig])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateSet('Info', 'Warn', 'Alert', 'Critical', 'Question')]
        [string]$Type,

        [Parameter(Mandatory, Position = 1)]
        [string]$Title,

        [Parameter(Mandatory, Position = 2)]
        [string]$Message,

        [LISSTech.Billboard.Models.ButtonDefinition[]]$Buttons,

        [LISSTech.Billboard.Models.BrandingConfig]$Branding,

        [Alias('Input')]
        [LISSTech.Billboard.Models.InputDefinition]$ResponseInput,

        [ValidateSet('Auto', 'Light', 'Dark', 'StarryNight', 'WaterLilies', 'GreatWave')]
        [string]$Theme = 'Auto',

        [int]$Timeout,

        [switch]$Modal,

        [string]$Illustration
    )

    $buttonList = [System.Collections.Generic.List[LISSTech.Billboard.Models.ButtonDefinition]]::new()
    if ($Buttons) {
        foreach ($b in $Buttons) { $buttonList.Add($b) }
    }

    $config = [LISSTech.Billboard.Models.BillboardConfig]::new()
    $config.GetType().GetProperty('Type').SetValue($config, [LISSTech.Billboard.Models.NotificationType]::$Type)
    $config.GetType().GetProperty('Title').SetValue($config, $Title)
    $config.GetType().GetProperty('Message').SetValue($config, $Message)
    $config.GetType().GetProperty('Modal').SetValue($config, [bool]($Modal -or $ResponseInput))
    $config.GetType().GetProperty('Theme').SetValue($config, [LISSTech.Billboard.Models.ThemeMode]::$Theme)
    $config.GetType().GetProperty('Buttons').SetValue($config, $buttonList)

    if ($PSBoundParameters.ContainsKey('Timeout')) {
        $config.GetType().GetProperty('Timeout').SetValue($config, [Nullable[int]]$Timeout)
    }

    if ($Branding) {
        $config.GetType().GetProperty('Branding').SetValue($config, $Branding)
    }
    if ($ResponseInput) {
        $config.GetType().GetProperty('Input').SetValue($config, $ResponseInput)
    }


    if ($PSBoundParameters.ContainsKey('Illustration') -and $Illustration) {
        $config.GetType().GetProperty('Illustration').SetValue($config, $Illustration)
    }

    return $config
}

# ── Action Cmdlets ───────────────────────────────────────────────────────────

function Show-Billboard {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [LISSTech.Billboard.Models.BillboardConfig]$Notification,

        [switch]$AsUser,
        [switch]$PassThru
    )

    if ($AsUser -and (Test-IsSystem)) {
        $existingIds = @(Get-Process -Name 'Billboard' -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty Id)
        $cliArgs = ConvertTo-CliArgs $Notification
        $exe, $cliArgs = Resolve-AsUserCommand $cliArgs -NoWait

        $quotedArgs = $cliArgs | ForEach-Object { if ($_ -match '\s') { "`"$_`"" } else { $_ } }
        $serviceUiProcess = Start-Process -FilePath $exe -ArgumentList $quotedArgs -NoNewWindow -PassThru

        if (-not $serviceUiProcess.WaitForExit(15000)) {
            throw 'ServiceUI did not finish launching Billboard within 15 seconds.'
        }

        $billboardProcess = $null
        $launchDeadline = [DateTime]::UtcNow.AddSeconds(10)
        do {
            $billboardProcess = Get-Process -Name 'Billboard' -ErrorAction SilentlyContinue |
                Where-Object { $_.Id -notin $existingIds -and $_.SessionId -ne 0 } |
                Select-Object -First 1
            if (-not $billboardProcess) { Start-Sleep -Milliseconds 100 }
        } while (-not $billboardProcess -and [DateTime]::UtcNow -lt $launchDeadline)

        if (-not $billboardProcess) {
            throw "ServiceUI did not create Billboard in an interactive user session (exit code $($serviceUiProcess.ExitCode)). Ensure a user is logged on and can read the module directory."
        }

        if ($PassThru) { return $billboardProcess }
        return
    }
    if ($AsUser -and [System.Diagnostics.Process]::GetCurrentProcess().SessionId -eq 0) {
        throw '-AsUser requires LocalSystem when called from a non-interactive RMM session.'
    }


    if ($PassThru) {
        Write-Warning '-PassThru is only supported when -AsUser routes through ServiceUI from SYSTEM. Showing notification synchronously.'
    }

    [LISSTech.Billboard.BillboardService]::Show($Notification)
}

function Request-Billboard {
    [CmdletBinding()]
    [OutputType([LISSTech.Billboard.Models.BillboardResult])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [LISSTech.Billboard.Models.BillboardConfig]$Notification,

        [switch]$AsUser
    )

    if ($AsUser -and (Test-IsSystem)) {
        $pipeName = New-BillboardPipeName
        $Notification.GetType().GetProperty('PipeName', [System.Reflection.BindingFlags]'NonPublic,Instance').SetValue($Notification, $pipeName)

        $cliArgs = ConvertTo-CliArgs $Notification
        $exe, $cliArgs = Resolve-AsUserCommand $cliArgs

        $quotedArgs = $cliArgs | ForEach-Object { if ($_ -match '\s') { "`"$_`"" } else { $_ } }
        $process = Start-Process -FilePath $exe -ArgumentList $quotedArgs -NoNewWindow -PassThru

        if ($process.WaitForExit(2000)) {
            throw "ServiceUI exited before Billboard connected (exit code $($process.ExitCode)). Ensure a user is logged on and can read the module directory."
        }

        try {
            return Read-BillboardPipe -PipeName $pipeName -TimeoutSeconds 300
        } catch {
            if (-not $process.HasExited -and -not $process.WaitForExit(15000)) {
                $process.Kill()
                $process.WaitForExit()
            }

            $exitCode = $process.ExitCode
            if ($exitCode -eq 100) {
                throw "Billboard exited with error (exit code 100). Pipe read also failed: $_"
            }
            if ($exitCode -notin @(0, 1, 2)) {
                throw "ServiceUI failed to run Billboard in the interactive user session (exit code $exitCode). Pipe read also failed: $_"
            }
            return [LISSTech.Billboard.Models.BillboardResult]::FromDismiss()
        }
    }
    if ($AsUser -and [System.Diagnostics.Process]::GetCurrentProcess().SessionId -eq 0) {
        throw '-AsUser requires LocalSystem when called from a non-interactive RMM session.'
    }


    return [LISSTech.Billboard.BillboardService]::Show($Notification)
}

# ── Deferral ─────────────────────────────────────────────────────────────────

function Register-BillboardDeferral {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ScriptPath,

        [Parameter(Mandatory)]
        [TimeSpan]$Delay,

        [string]$TaskNamePrefix = 'LISSTech.Billboard.Defer'
    )

    $taskName = "${TaskNamePrefix}.$([guid]::NewGuid().ToString('N').Substring(0, 8))"
    $triggerTime = (Get-Date).Add($Delay)

    $trigger = New-ScheduledTaskTrigger -Once -At $triggerTime
    $action = New-ScheduledTaskAction -Execute 'pwsh.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""
    $settings = New-ScheduledTaskSettingsSet -DeleteExpiredTaskAfter '00:05:00' -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest

    Register-ScheduledTask -TaskName $taskName -Trigger $trigger -Action $action `
        -Settings $settings -Principal $principal -Force | Out-Null

    Write-Verbose "Deferral scheduled: $taskName at $($triggerTime.ToString('yyyy-MM-dd HH:mm:ss'))"
}

# ── Internal Helpers ─────────────────────────────────────────────────────────

function ConvertTo-DeferTimeSpan {
    [OutputType([TimeSpan])]
    param([Parameter(Mandatory)][string]$Duration)

    $d = $Duration.Trim().ToLower()
    if ($d -match '^(\d+)m$') { return [TimeSpan]::FromMinutes([int]$Matches[1]) }
    if ($d -match '^(\d+)h$') { return [TimeSpan]::FromHours([int]$Matches[1]) }
    if ($d -match '^(\d+)d$') { return [TimeSpan]::FromDays([int]$Matches[1]) }
    throw "Invalid defer duration '$Duration'. Use format: 30m, 1h, 4h, 1d, 7d."
}

function ConvertTo-CliArgs {
    [OutputType([string[]])]
    param([Parameter(Mandatory)][LISSTech.Billboard.Models.BillboardConfig]$Config)

    $cliArgs = [System.Collections.Generic.List[string]]::new()
    $cliArgs.Add('--type');    $cliArgs.Add($Config.Type.ToString().ToLower())
    $cliArgs.Add('--title');   $cliArgs.Add($Config.Title)
    $cliArgs.Add('--message'); $cliArgs.Add($Config.Message)

    if ($null -ne $Config.Timeout) {
        $cliArgs.Add('--timeout'); $cliArgs.Add($Config.Timeout.ToString())
    }
    if ($Config.Modal) { $cliArgs.Add('--modal') }
    if ($Config.Theme -ne [LISSTech.Billboard.Models.ThemeMode]::Auto) {
        $cliArgs.Add('--theme'); $cliArgs.Add($Config.Theme.ToString().ToLower())
    }
    if ($Config.Branding) {
        if ($Config.Branding.Name) {
            $cliArgs.Add('--msp-name'); $cliArgs.Add($Config.Branding.Name)
        }
        if ($Config.Branding.Logo) {
            $cliArgs.Add('--msp-logo'); $cliArgs.Add($Config.Branding.Logo)
        }
    }
    if ($Config.Illustration) {
        $cliArgs.Add('--illustration'); $cliArgs.Add($Config.Illustration)
    }
    if ($Config.Input) {
        $cliArgs.Add('--input-label'); $cliArgs.Add($Config.Input.Label)
        if ($null -ne $Config.Input.Placeholder) {
            $cliArgs.Add('--input-placeholder'); $cliArgs.Add($Config.Input.Placeholder)
        }
        if ($null -ne $Config.Input.DefaultValue) {
            $cliArgs.Add('--input-default'); $cliArgs.Add($Config.Input.DefaultValue)
        }
        if ($Config.Input.Required) { $cliArgs.Add('--input-required') }
        if ($Config.Input.Multiline) { $cliArgs.Add('--input-multiline') }
        $cliArgs.Add('--input-max-length'); $cliArgs.Add($Config.Input.MaxLength.ToString())
    }
    $pipeName = $Config.GetType().GetProperty('PipeName', [System.Reflection.BindingFlags]'NonPublic,Instance').GetValue($Config)
    if ($pipeName) {
        $cliArgs.Add('--pipe'); $cliArgs.Add($pipeName)
    }
    if ($Config.Buttons.Count -gt 0) {
        $parts = foreach ($btn in $Config.Buttons) {
            $spec = "$($btn.Label):$($btn.Value):$($btn.Style.ToString().ToLower())"
            if ($btn.Defer) {
                $defer = if ($btn.Defer.TotalDays -ge 1) { "$([int]$btn.Defer.TotalDays)d" }
                    elseif ($btn.Defer.TotalHours -ge 1) { "$([int]$btn.Defer.TotalHours)h" }
                    else { "$([int]$btn.Defer.TotalMinutes)m" }
                $spec += ":defer=$defer"
            }
            $spec
        }
        $cliArgs.Add('--buttons'); $cliArgs.Add($parts -join ';')
    }

    return $cliArgs.ToArray()
}

function Test-IsSystem {
    [OutputType([bool])]
    param()
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    return $identity.User.Value -eq 'S-1-5-18'
}

function Resolve-AsUserCommand {
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][string[]]$BillboardArgs,
        [switch]$NoWait
    )

    if (-not (Test-IsSystem)) {
        if ([System.Diagnostics.Process]::GetCurrentProcess().SessionId -eq 0) {
            throw '-AsUser requires LocalSystem when called from a non-interactive RMM session.'
        }
        Write-Warning '-AsUser specified from an interactive non-SYSTEM session. Launching Billboard directly.'
        return @($script:BillboardExe, $BillboardArgs)
    }
    $explorer = Get-Process -Name 'explorer' -ErrorAction SilentlyContinue |
        Where-Object { $_.SessionId -ne 0 } |
        Select-Object -First 1
    if (-not $explorer) {
        throw 'ServiceUI could not find an interactive Explorer session. A user must be logged on before using -AsUser.'
    }


    if (-not (Test-Path -LiteralPath $script:ServiceUIExe -PathType Leaf)) {
        throw [System.IO.FileNotFoundException]::new("ServiceUI.exe not found at '$script:ServiceUIExe'.")
    }
    if (-not (Test-Path -LiteralPath $script:BillboardExe -PathType Leaf)) {
        throw [System.IO.FileNotFoundException]::new("Billboard.exe not found at '$script:BillboardExe'.")
    }

    $payload = [LISSTech.Billboard.Services.CliParser]::EncodePayload($BillboardArgs)
    $wrappedArgs = [System.Collections.Generic.List[string]]::new()
    if ($NoWait) { $wrappedArgs.Add('-nowait') }
    $wrappedArgs.Add('-process:explorer.exe')
    $wrappedArgs.Add($script:BillboardExe)
    $wrappedArgs.Add('--payload')
    $wrappedArgs.Add($payload)
    return @($script:ServiceUIExe, $wrappedArgs.ToArray())
}

function New-BillboardPipeName {
    [OutputType([string])]
    param()
    return "LISSTech.Billboard.$([guid]::NewGuid().ToString('N').Substring(0, 8))"
}

function Read-BillboardPipe {
    [OutputType([LISSTech.Billboard.Models.BillboardResult])]
    param(
        [Parameter(Mandatory)][string]$PipeName,
        [int]$TimeoutSeconds = 300
    )

    $pipe = $null
    $reader = $null
    try {
        $pipe = [System.IO.Pipes.NamedPipeClientStream]::new('.', $PipeName, [System.IO.Pipes.PipeDirection]::In)
        $pipe.Connect($TimeoutSeconds * 1000)
        $reader = [System.IO.StreamReader]::new($pipe, [System.Text.Encoding]::UTF8)
        $json = $reader.ReadToEnd()
        return $json | ConvertFrom-Json
    } finally {
        if ($reader) { $reader.Dispose() }
        if ($pipe)   { $pipe.Dispose() }
    }
}
