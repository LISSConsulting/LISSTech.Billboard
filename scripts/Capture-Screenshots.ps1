#Requires -Version 5.1
<#
.SYNOPSIS
    Captures screenshots of all Billboard notification variants for docs/marketing.
.DESCRIPTION
    Run on a clean VM with 1920x1080 resolution for best results.
    The module must be installed or the exe must be available.
.EXAMPLE
    powershell -File Capture-Screenshots.ps1 -ExePath .\Bin\Billboard.exe
#>
param(
    [string]$ExePath,
    [string]$OutputDir = (Join-Path $PSScriptRoot 'screenshots')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Find the exe
if (-not $ExePath) {
    # Try module path
    $mod = Get-Module LISSTech.Billboard -ListAvailable | Select-Object -First 1
    if ($mod) {
        $ExePath = Join-Path (Split-Path $mod.Path) 'Bin\Billboard.exe'
    }
}
if (-not $ExePath -or -not (Test-Path $ExePath)) {
    Write-Error "Billboard.exe not found. Pass -ExePath or install the module."
    return
}

if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }

# Minimize everything for a clean background
$shell = New-Object -ComObject Shell.Application
$shell.MinimizeAll()
Start-Sleep -Seconds 2

function Capture-Notification {
    param(
        [string]$FileName,
        [string]$Args,
        [int]$DelayMs = 4000
    )

    $proc = Start-Process -FilePath $ExePath -ArgumentList $Args -PassThru
    Start-Sleep -Milliseconds $DelayMs

    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = [System.Drawing.Bitmap]::new($bounds.Width, $bounds.Height)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
    $g.Dispose()

    $path = Join-Path $OutputDir "$FileName.png"
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()

    Write-Host "   OK $FileName.png" -ForegroundColor Green

    if (-not $proc.HasExited) { $proc.WaitForExit(12000) }
    if (-not $proc.HasExited) { $proc.Kill() }
}

Write-Host "`nCapturing Billboard screenshots" -ForegroundColor Cyan
Write-Host "   Output: $OutputDir" -ForegroundColor DarkGray
Write-Host "   Exe:    $ExePath" -ForegroundColor DarkGray
Write-Host ""

$msp = '--msp-name "LISS Consulting"'

# -- Dark theme screenshots --

Write-Host "   Toasts (dark):" -ForegroundColor DarkGray

Capture-Notification 'toast-info-dark' "--type info --title `"Microsoft Teams Updated`" --message `"Microsoft Teams has been updated to version **1.7.00.26264**. No action is required.`" --theme dark --timeout 10 $msp"

Capture-Notification 'toast-alert-dark' "--type alert --title `"Password Expiring Soon`" --message `"Your Active Directory password will expire in **3 days** (April 11, 2026).`" --theme dark --timeout 10 $msp"

Capture-Notification 'toast-question-dark' "--type question --title `"Restart Required`" --message `"A security update for **Windows 11** requires a restart.`" --theme dark --timeout 10 --buttons `"Restart Now:restart:primary;Remind in 4 Hours:defer:ghost:defer=4h`" $msp"

Write-Host "   Modals (dark):" -ForegroundColor DarkGray

Capture-Notification 'modal-warn-dark' "--type warn --title `"Storage Running Low`" --message `"Your system drive has **4.2 GB** of free space remaining.`" --theme dark --timeout 10 --modal $msp"

Capture-Notification 'modal-critical-dark' "--type critical --title `"Endpoint Protection Disabled`" --message `"**Microsoft Defender** real-time protection has been disabled on this device.`" --theme dark --timeout 10 --modal $msp"

Capture-Notification 'modal-question-dark' "--type question --title `"Restart Required`" --message `"A security update for **Windows 11** requires a restart to finish installing.`" --theme dark --timeout 10 --modal --buttons `"Restart Now:restart:primary;Remind in 4 Hours:defer:ghost:defer=4h`" $msp"

# -- Pause for theme switch --

Write-Host ""
Write-Host "   >> Switch Windows to LIGHT theme (Settings > Personalization > Colors)" -ForegroundColor Yellow
Write-Host "   >> Set a light/white desktop wallpaper" -ForegroundColor Yellow
Write-Host "   >> Press Enter when ready..." -ForegroundColor Yellow
$null = Read-Host

$shell.MinimizeAll()
Start-Sleep -Seconds 6

# -- Light theme screenshots --

Write-Host "   Toasts (light):" -ForegroundColor DarkGray

Capture-Notification 'toast-warn-light' "--type warn --title `"Storage Running Low`" --message `"Your system drive has **4.2 GB** of free space remaining.`" --theme light --timeout 10 $msp"

Capture-Notification 'toast-critical-light' "--type critical --title `"Endpoint Protection Disabled`" --message `"**Microsoft Defender** real-time protection has been disabled.`" --theme light --timeout 10 $msp"

Write-Host "   Modals (light):" -ForegroundColor DarkGray

Capture-Notification 'modal-info-light' "--type info --title `"Microsoft Teams Updated`" --message `"Microsoft Teams has been updated to version **1.7.00.26264**. No action is required.`" --theme light --timeout 10 --modal $msp"

Capture-Notification 'modal-alert-light' "--type alert --title `"Password Expiring Soon`" --message `"Your password will expire in **3 days**. Please change it before it expires.`" --theme light --timeout 10 --modal $msp"

Capture-Notification 'modal-question-light' "--type question --title `"Chrome Update Available`" --message `"Google Chrome **131.0.6778** is ready to install.`" --theme light --timeout 10 --modal --buttons `"Update Now:update:primary;Remind Tomorrow:defer:ghost:defer=1d`" $msp"

# Cleanup
$shell.UndoMinimizeAll()

Write-Host ""
Write-Host "   Screenshots saved to: $OutputDir" -ForegroundColor Green
Write-Host ""
