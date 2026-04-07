$script:AssemblyDir = Join-Path $PSScriptRoot 'Assembly'
$script:BinDir = Join-Path $PSScriptRoot 'Bin'
$script:BillboardDll = Join-Path $script:AssemblyDir 'LISSTech.Billboard.dll'
$script:BillboardExe = Join-Path $script:BinDir 'Billboard.exe'
$script:ServiceUIExe = Join-Path $script:BinDir 'ServiceUI.exe'

# Load the DLL assembly
Add-Type -Path $script:BillboardDll

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

        [ValidateSet('Auto', 'Light', 'Dark')]
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
    $config.GetType().GetProperty('Modal').SetValue($config, [bool]$Modal)
    $config.GetType().GetProperty('Theme').SetValue($config, [LISSTech.Billboard.Models.ThemeMode]::$Theme)
    $config.GetType().GetProperty('Buttons').SetValue($config, $buttonList)

    if ($PSBoundParameters.ContainsKey('Timeout')) {
        $config.GetType().GetProperty('Timeout').SetValue($config, [Nullable[int]]$Timeout)
    }

    if ($Branding) {
        $config.GetType().GetProperty('Branding').SetValue($config, $Branding)
    }

    if ($PSBoundParameters.ContainsKey('Illustration') -and $Illustration) {
        $illusValue = if ($Illustration -eq 'none') { $null } else { $Illustration }
        $config.GetType().GetProperty('Illustration').SetValue($config, $illusValue)
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
        $cliArgs = ConvertTo-CliArgs $Notification
        $exe, $cliArgs = Resolve-AsUserCommand $cliArgs

        $quotedArgs = $cliArgs | ForEach-Object { if ($_ -match ' ') { "`"$_`"" } else { $_ } }
        $startParams = @{ FilePath = $exe; ArgumentList = $quotedArgs; NoNewWindow = $true }

        if ($PassThru) {
            return Start-Process @startParams -PassThru
        }
        $null = Start-Process @startParams
        return
    }

    if ($PassThru) {
        Write-Warning '-PassThru is only supported with -AsUser. Showing notification synchronously.'
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

    # Force modal for Request
    $Notification.GetType().GetProperty('Modal').SetValue($Notification, $true)

    if ($AsUser -and (Test-IsSystem)) {
        $pipeName = New-BillboardPipeName
        $Notification.GetType().GetProperty('PipeName').SetValue($Notification, $pipeName)

        $cliArgs = ConvertTo-CliArgs $Notification
        $exe, $cliArgs = Resolve-AsUserCommand $cliArgs

        $quotedArgs = $cliArgs | ForEach-Object { if ($_ -match ' ') { "`"$_`"" } else { $_ } }
        $process = Start-Process -FilePath $exe -ArgumentList $quotedArgs -NoNewWindow -PassThru

        try {
            return Read-BillboardPipe -PipeName $pipeName -TimeoutSeconds 300
        } catch {
            if (-not $process.HasExited) {
                $null = $process.WaitForExit(15000)
                if (-not $process.HasExited) { $process.Kill() }
            }
            $exitCode = $process.ExitCode
            if ($exitCode -eq 100) {
                throw "Billboard exited with error (exit code 100). Pipe read also failed: $_"
            }
            return [LISSTech.Billboard.Models.BillboardResult]::FromDismiss()
        }
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

    $args = [System.Collections.Generic.List[string]]::new()
    $args.Add('--type');    $args.Add($Config.Type.ToString().ToLower())
    $args.Add('--title');   $args.Add($Config.Title)
    $args.Add('--message'); $args.Add($Config.Message)

    if ($Config.Timeout) {
        $args.Add('--timeout'); $args.Add($Config.Timeout.ToString())
    }
    if ($Config.Modal) { $args.Add('--modal') }
    if ($Config.Theme -ne [LISSTech.Billboard.Models.ThemeMode]::Auto) {
        $args.Add('--theme'); $args.Add($Config.Theme.ToString().ToLower())
    }
    if ($Config.Branding) {
        if ($Config.Branding.Name) {
            $args.Add('--msp-name'); $args.Add($Config.Branding.Name)
        }
        if ($Config.Branding.Logo) {
            $args.Add('--msp-logo'); $args.Add($Config.Branding.Logo)
        }
    }
    if ($Config.Illustration) {
        $args.Add('--illustration'); $args.Add($Config.Illustration)
    }
    if ($Config.PipeName) {
        $args.Add('--pipe'); $args.Add($Config.PipeName)
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
        $args.Add('--buttons'); $args.Add($parts -join ';')
    }

    return $args.ToArray()
}

function Test-IsSystem {
    [OutputType([bool])]
    param()
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    return $identity.User.Value -eq 'S-1-5-18'
}

function Resolve-AsUserCommand {
    [OutputType([object[]])]
    param([Parameter(Mandatory)][string[]]$BillboardArgs)

    if (-not (Test-IsSystem)) {
        Write-Warning '-AsUser specified but not running as SYSTEM. Launching Billboard directly.'
        return @($script:BillboardExe, $BillboardArgs)
    }

    if (-not (Test-Path $script:ServiceUIExe)) {
        throw [System.IO.FileNotFoundException]::new("ServiceUI.exe not found at '$script:ServiceUIExe'.")
    }

    $wrappedArgs = @('-process:explorer.exe', $script:BillboardExe) + $BillboardArgs
    return @($script:ServiceUIExe, $wrappedArgs)
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
