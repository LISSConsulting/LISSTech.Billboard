#Requires -Version 5.1
<#
.SYNOPSIS
    Captures screenshots of all Billboard notification variants for docs/marketing.
.DESCRIPTION
    Run on a clean VM with 1920x1080 resolution for best results.
    Requires the module to be published first (just publish).
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

# Use already-imported module or auto-discover from PSModulePath
if (-not (Get-Module LISSTech.Billboard)) {
    Import-Module LISSTech.Billboard -ErrorAction Stop
}

if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }
$branding = New-BillboardBranding 'LISS Consulting'

# Minimize everything for a clean background
$shell = New-Object -ComObject Shell.Application
$shell.MinimizeAll()
Start-Sleep -Seconds 2

function Capture-Notification {
    param(
        [LISSTech.Billboard.Models.BillboardConfig]$Notification,
        [string]$FileName,
        [int]$DelayMs = 2200
    )

    # Show in a background STA runspace
    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = 'STA'
    $rs.ThreadOptions = 'ReuseThread'
    $rs.Open()

    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript({
        param($n)
        Add-Type -AssemblyName PresentationFramework
        [LISSTech.Billboard.BillboardService]::Show($n)
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
    $rs.Close()
}

Write-Host "`nCapturing Billboard screenshots" -ForegroundColor Cyan
Write-Host "   Output: $OutputDir" -ForegroundColor DarkGray
Write-Host ""

# ── Toasts ──────────────────────────────────────────────────────────────────

Write-Host "   Toasts:" -ForegroundColor DarkGray

Capture-Notification -FileName 'toast-info-dark' -Notification (
    New-BillboardNotification -Type Info `
        -Title 'Microsoft Teams Updated' `
        -Message 'Microsoft Teams has been updated to version **1.7.00.26264**. No action is required — the update has already been applied. New features include improved meeting controls and faster file sharing.' `
        -Branding $branding -Theme Dark -Timeout 10
)

Capture-Notification -FileName 'toast-warn-light' -Notification (
    New-BillboardNotification -Type Warn `
        -Title 'Storage Running Low' `
        -Message "Your system drive **C:\** has **4.2 GB** of free space remaining. When free space drops below 2 GB, system performance may degrade." `
        -Branding $branding -Theme Light -Timeout 10
)

Capture-Notification -FileName 'toast-alert-dark' -Notification (
    New-BillboardNotification -Type Alert `
        -Title 'Password Expiring Soon' `
        -Message 'Your Active Directory password will expire in **3 days** (April 11, 2026).' `
        -Branding $branding -Theme Dark -Timeout 10
)

Capture-Notification -FileName 'toast-critical-light' -Notification (
    New-BillboardNotification -Type Critical `
        -Title 'Endpoint Protection Disabled' `
        -Message '**Microsoft Defender** real-time protection has been disabled on this device.' `
        -Branding $branding -Theme Light -Timeout 10
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

# ── Modals ──────────────────────────────────────────────────────────────────

Write-Host "   Modals:" -ForegroundColor DarkGray

Capture-Notification -FileName 'modal-info-light' -Notification (
    New-BillboardNotification -Type Info `
        -Title 'Microsoft Teams Updated' `
        -Message 'Microsoft Teams has been updated to version **1.7.00.26264**. No action is required — the update has already been applied.' `
        -Branding $branding -Theme Light -Timeout 10 -Modal
)

Capture-Notification -FileName 'modal-warn-dark' -Notification (
    New-BillboardNotification -Type Warn `
        -Title 'Storage Running Low' `
        -Message "Your system drive **C:\** has **4.2 GB** of free space remaining. When free space drops below 2 GB, system performance may degrade and Windows updates will stop installing.`n`n- Clear temporary files via *Disk Cleanup*`n- Move large files to **OneDrive** or a network share`n- Contact the helpdesk if you need assistance" `
        -Branding $branding -Theme Dark -Timeout 10 -Modal
)

Capture-Notification -FileName 'modal-alert-light' -Notification (
    New-BillboardNotification -Type Alert `
        -Title 'Password Expiring Soon' `
        -Message 'Your Active Directory password will expire in **3 days** (April 11, 2026). Please change your password before it expires to avoid being locked out.' `
        -Branding $branding -Theme Light -Timeout 10 -Modal
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

# Restore windows
$shell.UndoMinimizeAll()

Write-Host ""
Write-Host "   Screenshots saved to: $OutputDir" -ForegroundColor Green
Write-Host "   Run on a clean 1920x1080 VM for best results." -ForegroundColor DarkGray
Write-Host ""
