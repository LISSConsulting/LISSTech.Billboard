$script:BinDir = Join-Path $PSScriptRoot 'Bin'
$script:BillboardExe = Join-Path $script:BinDir 'Billboard.exe'
$script:ServiceUIExe = Join-Path $script:BinDir 'ServiceUI.exe'

function ConvertTo-BillboardArgs {
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)][string]$Type,
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Message,
        [int]$Timeout,
        [switch]$Modal,
        [string]$Theme,
        [hashtable[]]$Buttons,
        [string]$Illustration,
        [string]$MspName,
        [string]$MspLogo,
        [string]$PipeName
    )

    $cliArgs = [System.Collections.Generic.List[string]]::new()
    $cliArgs.Add('--type');    $cliArgs.Add($Type.ToLower())
    $cliArgs.Add('--title');   $cliArgs.Add($Title)
    $cliArgs.Add('--message'); $cliArgs.Add($Message)

    if ($PSBoundParameters.ContainsKey('Timeout')) {
        $cliArgs.Add('--timeout'); $cliArgs.Add($Timeout.ToString())
    }

    if ($Modal) {
        $cliArgs.Add('--modal')
    }

    if ($PSBoundParameters.ContainsKey('Theme') -and $Theme) {
        $cliArgs.Add('--theme'); $cliArgs.Add($Theme.ToLower())
    }

    if ($PSBoundParameters.ContainsKey('Buttons') -and $Buttons) {
        $parts = foreach ($btn in $Buttons) {
            if (-not $btn.ContainsKey('Label') -or [string]::IsNullOrWhiteSpace($btn['Label'])) {
                throw [System.ArgumentException]::new("Each button must have a non-empty 'Label' key.")
            }
            if (-not $btn.ContainsKey('Value') -or [string]::IsNullOrWhiteSpace($btn['Value'])) {
                throw [System.ArgumentException]::new("Each button must have a non-empty 'Value' key.")
            }
            $label = $btn['Label'].Trim()
            $value = $btn['Value'].Trim()
            $style = if ($btn.ContainsKey('Style')) { $btn['Style'].ToString().ToLower() } else { 'ghost' }
            "${label}:${value}:${style}"
        }
        $cliArgs.Add('--buttons'); $cliArgs.Add($parts -join ';')
    }

    if ($PSBoundParameters.ContainsKey('Illustration') -and $Illustration) {
        $cliArgs.Add('--illustration'); $cliArgs.Add($Illustration)
    }

    if ($PSBoundParameters.ContainsKey('MspName') -and $MspName) {
        $cliArgs.Add('--msp-name'); $cliArgs.Add($MspName)
    }

    if ($PSBoundParameters.ContainsKey('MspLogo') -and $MspLogo) {
        $cliArgs.Add('--msp-logo'); $cliArgs.Add($MspLogo)
    }

    if ($PSBoundParameters.ContainsKey('PipeName') -and $PipeName) {
        $cliArgs.Add('--pipe'); $cliArgs.Add($PipeName)
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
        [Parameter(Mandatory)][string[]]$BillboardArgs
    )

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
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)][string]$PipeName,
        [int]$TimeoutSeconds = 15
    )

    $pipe = $null
    $reader = $null
    try {
        $pipe = [System.IO.Pipes.NamedPipeClientStream]::new(
            '.',
            $PipeName,
            [System.IO.Pipes.PipeDirection]::In
        )
        $pipe.Connect($TimeoutSeconds * 1000)
        $reader = [System.IO.StreamReader]::new($pipe, [System.Text.Encoding]::UTF8)
        $json = $reader.ReadToEnd()
        return $json | ConvertFrom-Json
    } finally {
        if ($reader) { $reader.Dispose() }
        if ($pipe)   { $pipe.Dispose() }
    }
}

function Show-Billboard {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Info', 'Warn', 'Alert', 'Critical', 'Question')]
        [string]$Type,

        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter(Mandatory)]
        [string]$Message,

        [int]$Timeout,
        [switch]$Modal,

        [ValidateSet('Auto', 'Light', 'Dark')]
        [string]$Theme,

        [hashtable[]]$Buttons,
        [string]$Illustration,
        [string]$MspName,
        [string]$MspLogo,
        [switch]$AsUser,
        [switch]$PassThru
    )

    if (-not (Test-Path $script:BillboardExe)) {
        throw [System.IO.FileNotFoundException]::new("Billboard.exe not found at '$script:BillboardExe'.")
    }

    $buildParams = @{
        Type    = $Type
        Title   = $Title
        Message = $Message
    }
    if ($PSBoundParameters.ContainsKey('Timeout'))      { $buildParams['Timeout']      = $Timeout }
    if ($Modal)                                          { $buildParams['Modal']        = $true }
    if ($PSBoundParameters.ContainsKey('Theme'))         { $buildParams['Theme']        = $Theme }
    if ($PSBoundParameters.ContainsKey('Buttons'))       { $buildParams['Buttons']      = $Buttons }
    if ($PSBoundParameters.ContainsKey('Illustration'))  { $buildParams['Illustration'] = $Illustration }
    if ($PSBoundParameters.ContainsKey('MspName'))       { $buildParams['MspName']      = $MspName }
    if ($PSBoundParameters.ContainsKey('MspLogo'))       { $buildParams['MspLogo']      = $MspLogo }

    $cliArgs = ConvertTo-BillboardArgs @buildParams

    $exe = $script:BillboardExe
    if ($AsUser) {
        $exe, $cliArgs = Resolve-AsUserCommand -BillboardArgs $cliArgs
    }

    # Start-Process -ArgumentList joins array elements with spaces without quoting,
    # so arguments containing spaces must be explicitly quoted.
    $quotedArgs = $cliArgs | ForEach-Object { if ($_ -match ' ') { "`"$_`"" } else { $_ } }

    $startParams = @{
        FilePath     = $exe
        ArgumentList = $quotedArgs
        NoNewWindow  = $true
    }

    if ($PassThru) {
        return Start-Process @startParams -PassThru
    }
    $null = Start-Process @startParams
}

function Request-Billboard {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Info', 'Warn', 'Alert', 'Critical', 'Question')]
        [string]$Type,

        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter(Mandatory)]
        [string]$Message,

        [int]$Timeout,

        [ValidateSet('Auto', 'Light', 'Dark')]
        [string]$Theme,

        [hashtable[]]$Buttons,
        [string]$Illustration,
        [string]$MspName,
        [string]$MspLogo,
        [switch]$AsUser
    )

    if (-not (Test-Path $script:BillboardExe)) {
        throw [System.IO.FileNotFoundException]::new("Billboard.exe not found at '$script:BillboardExe'.")
    }

    $pipeName = New-BillboardPipeName

    $buildParams = @{
        Type     = $Type
        Title    = $Title
        Message  = $Message
        Modal    = $true
        PipeName = $pipeName
    }
    if ($PSBoundParameters.ContainsKey('Timeout'))      { $buildParams['Timeout']      = $Timeout }
    if ($PSBoundParameters.ContainsKey('Theme'))         { $buildParams['Theme']        = $Theme }
    if ($PSBoundParameters.ContainsKey('Buttons'))       { $buildParams['Buttons']      = $Buttons }
    if ($PSBoundParameters.ContainsKey('Illustration'))  { $buildParams['Illustration'] = $Illustration }
    if ($PSBoundParameters.ContainsKey('MspName'))       { $buildParams['MspName']      = $MspName }
    if ($PSBoundParameters.ContainsKey('MspLogo'))       { $buildParams['MspLogo']      = $MspLogo }

    $cliArgs = ConvertTo-BillboardArgs @buildParams

    $exe = $script:BillboardExe
    if ($AsUser) {
        $exe, $cliArgs = Resolve-AsUserCommand -BillboardArgs $cliArgs
    }

    $quotedArgs = $cliArgs | ForEach-Object { if ($_ -match ' ') { "`"$_`"" } else { $_ } }
    $process = Start-Process -FilePath $exe -ArgumentList $quotedArgs -NoNewWindow -PassThru

    try {
        $result = Read-BillboardPipe -PipeName $pipeName -TimeoutSeconds 15
        return $result
    } catch {
        # Pipe failed — fall back to exit code
        if (-not $process.HasExited) {
            $null = $process.WaitForExit(15000)
            if (-not $process.HasExited) {
                $process.Kill()
            }
        }
        $exitCode = $process.ExitCode
        if ($exitCode -eq 100) {
            throw "Billboard exited with an error (exit code 100). Pipe read also failed: $_"
        }
        return [PSCustomObject]@{
            Button    = $null
            Value     = $null
            Index     = -1
            Dismissed = $exitCode -eq 1 -or $exitCode -eq 2
            Timeout   = $exitCode -eq 2
            Timestamp = [DateTimeOffset]::UtcNow
        }
    }
}
