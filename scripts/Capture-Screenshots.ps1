#Requires -Version 5.1
<#
.SYNOPSIS
    Captures screenshots of all Billboard notification variants for docs/marketing.
.DESCRIPTION
    Run on a clean VM with 1920x1080 resolution for best results.
    The module must be imported or available in PSModulePath.
.EXAMPLE
    Import-Module LISSTech.Billboard
    powershell -STA -File Capture-Screenshots.ps1
#>
param(
    [string]$OutputDir = (Join-Path $PSScriptRoot 'screenshots')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if (-not (Get-Module LISSTech.Billboard)) {
    Import-Module LISSTech.Billboard -ErrorAction Stop
}

if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }
$branding = New-BillboardBranding 'LISS Consulting'

# Minimize everything for a clean background
$shell = New-Object -ComObject Shell.Application
$shell.MinimizeAll()
Start-Sleep -Seconds 2

# Create one persistent STA runspace for all notifications.
# WPF Application is a singleton -- reusing one runspace avoids lifecycle issues.
$rs = [runspacefactory]::CreateRunspace()
$rs.ApartmentState = 'STA'
$rs.ThreadOptions = 'ReuseThread'
$rs.Open()

function Capture-Notification {
    param(
        [LISSTech.Billboard.Models.BillboardConfig]$Notification,
        [string]$FileName,
        [int]$DelayMs = 2200
    )

    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript({
        param($n)
        Add-Type -AssemblyName PresentationFramework
        $null = [LISSTech.Billboard.BillboardService]::Show($n)
    }).AddArgument($Notification)

    $handle = $ps.BeginInvoke()
    Start-Sleep -Milliseconds $DelayMs

    # Capture full screen
    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = [System.Drawing.Bitmap]::new($bounds.Width, $bounds.Height)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
    $g.Dispose()

    $path = Join-Path $OutputDir "$FileName.png"
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()

    Write-Host "   OK $FileName.png" -ForegroundColor Green

    # Wait for notification to dismiss
    $null = $handle.AsyncWaitHandle.WaitOne(15000)
    try { $ps.EndInvoke($handle) } catch {}
    $ps.Dispose()
}

$themeKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
$desktopKey = 'HKCU:\Control Panel\Desktop'
$colorsKey = 'HKCU:\Control Panel\Colors'

Add-Type @"
using System.Runtime.InteropServices;
public class Wallpaper {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
    public const int SPI_SETDESKWALLPAPER = 0x0014;
    public const int SPIF_UPDATEINIFILE = 0x01;
    public const int SPIF_SENDCHANGE = 0x02;
}
"@

function Set-WindowsTheme([bool]$Dark) {
    $val = if ($Dark) { 0 } else { 1 }
    Set-ItemProperty $themeKey -Name 'AppsUseLightTheme' -Value $val
    Set-ItemProperty $themeKey -Name 'SystemUsesLightTheme' -Value $val

    # Set solid desktop color (no wallpaper image)
    [Wallpaper]::SystemParametersInfo([Wallpaper]::SPI_SETDESKWALLPAPER, 0, '', [Wallpaper]::SPIF_UPDATEINIFILE -bor [Wallpaper]::SPIF_SENDCHANGE) | Out-Null

    if ($Dark) {
        # Dark charcoal background
        Set-ItemProperty $colorsKey -Name 'Background' -Value '26 26 36'
    } else {
        # Light warm gray background
        Set-ItemProperty $colorsKey -Name 'Background' -Value '235 235 230'
    }

    # Force desktop refresh
    [Wallpaper]::SystemParametersInfo([Wallpaper]::SPI_SETDESKWALLPAPER, 0, '', [Wallpaper]::SPIF_UPDATEINIFILE -bor [Wallpaper]::SPIF_SENDCHANGE) | Out-Null
    Start-Sleep -Milliseconds 2000
}

# Save current state to restore later
$origApps = (Get-ItemProperty $themeKey).AppsUseLightTheme
$origSystem = (Get-ItemProperty $themeKey).SystemUsesLightTheme
$origWallpaper = (Get-ItemProperty $desktopKey).Wallpaper
$origBgColor = (Get-ItemProperty $colorsKey).Background

Write-Host "`nCapturing Billboard screenshots" -ForegroundColor Cyan
Write-Host "   Output: $OutputDir" -ForegroundColor DarkGray
Write-Host ""

# -- Dark theme screenshots --

Write-Host "   Switching to dark theme..." -ForegroundColor DarkGray
Set-WindowsTheme -Dark $true

Write-Host "   Toasts (dark):" -ForegroundColor DarkGray

Capture-Notification -FileName 'toast-info-dark' -Notification (
    New-BillboardNotification -Type Info `
        -Title 'Microsoft Teams Updated' `
        -Message 'Microsoft Teams has been updated to version **1.7.00.26264**. No action is required -- the update has already been applied. New features include improved meeting controls and faster file sharing.' `
        -Branding $branding -Theme Dark -Timeout 10
)

Capture-Notification -FileName 'toast-alert-dark' -Notification (
    New-BillboardNotification -Type Alert `
        -Title 'Password Expiring Soon' `
        -Message 'Your Active Directory password will expire in **3 days** (April 11, 2026).' `
        -Branding $branding -Theme Dark -Timeout 10
)

Capture-Notification -FileName 'toast-question-dark' -Notification (
    New-BillboardNotification -Type Question `
        -Title 'Restart Required' `
        -Message 'A security update for **Windows 11** requires a restart.' `
        -Branding $branding -Theme Dark -Timeout 10 `
        -Buttons @(
            New-BillboardButton 'Restart Now' -Value restart -Style Primary
            New-BillboardButton 'Remind in 4 Hours' -Value defer -Style Ghost -Defer 4h
        )
)

Write-Host "   Modals (dark):" -ForegroundColor DarkGray

Capture-Notification -FileName 'modal-warn-dark' -Notification (
    New-BillboardNotification -Type Warn `
        -Title 'Storage Running Low' `
        -Message "Your system drive **C:\** has **4.2 GB** of free space remaining. When free space drops below 2 GB, system performance may degrade and Windows updates will stop installing.`n`n- Clear temporary files via *Disk Cleanup*`n- Move large files to **OneDrive** or a network share`n- Contact the helpdesk if you need assistance" `
        -Branding $branding -Theme Dark -Timeout 10 -Modal
)

Capture-Notification -FileName 'modal-critical-dark' -Notification (
    New-BillboardNotification -Type Critical `
        -Title 'Endpoint Protection Disabled' `
        -Message "**Microsoft Defender** real-time protection has been disabled on this device. This leaves your system vulnerable to malware and other threats.`n`nIf you did not disable it intentionally, your device may already be compromised. Contact the helpdesk **immediately**." `
        -Branding $branding -Theme Dark -Timeout 10 -Modal
)

Capture-Notification -FileName 'modal-question-dark' -Notification (
    New-BillboardNotification -Type Question `
        -Title 'Restart Required' `
        -Message 'A security update for **Windows 11** requires a restart to finish installing. This update patches a critical vulnerability (CVE-2026-21001) and should be applied as soon as possible.' `
        -Branding $branding -Theme Dark -Timeout 10 -Modal `
        -Buttons @(
            New-BillboardButton 'Restart Now' -Value restart -Style Primary
            New-BillboardButton 'Remind in 4 Hours' -Value defer -Style Ghost -Defer 4h
        )
)

# -- Switch to light theme --

Write-Host ""
Write-Host "   Switching to light theme..." -ForegroundColor DarkGray
Set-WindowsTheme -Dark $false

Write-Host "   Toasts (light):" -ForegroundColor DarkGray

Capture-Notification -FileName 'toast-warn-light' -Notification (
    New-BillboardNotification -Type Warn `
        -Title 'Storage Running Low' `
        -Message "Your system drive **C:\** has **4.2 GB** of free space remaining. When free space drops below 2 GB, system performance may degrade." `
        -Branding $branding -Theme Light -Timeout 10
)

Capture-Notification -FileName 'toast-critical-light' -Notification (
    New-BillboardNotification -Type Critical `
        -Title 'Endpoint Protection Disabled' `
        -Message '**Microsoft Defender** real-time protection has been disabled on this device.' `
        -Branding $branding -Theme Light -Timeout 10
)

Write-Host "   Modals (light):" -ForegroundColor DarkGray

Capture-Notification -FileName 'modal-info-light' -Notification (
    New-BillboardNotification -Type Info `
        -Title 'Microsoft Teams Updated' `
        -Message 'Microsoft Teams has been updated to version **1.7.00.26264**. No action is required -- the update has already been applied.' `
        -Branding $branding -Theme Light -Timeout 10 -Modal
)

Capture-Notification -FileName 'modal-alert-light' -Notification (
    New-BillboardNotification -Type Alert `
        -Title 'Password Expiring Soon' `
        -Message 'Your Active Directory password will expire in **3 days** (April 11, 2026). Please change your password before it expires to avoid being locked out.' `
        -Branding $branding -Theme Light -Timeout 10 -Modal
)

Capture-Notification -FileName 'modal-question-light' -Notification (
    New-BillboardNotification -Type Question `
        -Title 'Chrome Update Available' `
        -Message 'Google Chrome **131.0.6778** is ready to install. The browser will restart after updating.' `
        -Branding $branding -Theme Light -Timeout 10 -Modal `
        -Buttons @(
            New-BillboardButton 'Update Now' -Value update -Style Primary
            New-BillboardButton 'Remind Tomorrow' -Value defer -Style Ghost -Defer 1d
        )
)

# Cleanup -- restore original theme and wallpaper
Set-ItemProperty $themeKey -Name 'AppsUseLightTheme' -Value $origApps
Set-ItemProperty $themeKey -Name 'SystemUsesLightTheme' -Value $origSystem
Set-ItemProperty $colorsKey -Name 'Background' -Value $origBgColor
if ($origWallpaper) {
    [Wallpaper]::SystemParametersInfo([Wallpaper]::SPI_SETDESKWALLPAPER, 0, $origWallpaper, [Wallpaper]::SPIF_UPDATEINIFILE -bor [Wallpaper]::SPIF_SENDCHANGE) | Out-Null
} else {
    [Wallpaper]::SystemParametersInfo([Wallpaper]::SPI_SETDESKWALLPAPER, 0, '', [Wallpaper]::SPIF_UPDATEINIFILE -bor [Wallpaper]::SPIF_SENDCHANGE) | Out-Null
}
$rs.Close()
$shell.UndoMinimizeAll()

Write-Host ""
Write-Host "   Screenshots saved to: $OutputDir" -ForegroundColor Green
Write-Host ""
