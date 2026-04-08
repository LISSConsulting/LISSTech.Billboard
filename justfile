set shell := ["pwsh", "-NoProfile", "-Command"]
set dotenv-load

# Paths
release_dir := justfile_directory() / "Release/LISSTech.Billboard"
assembly_dir := release_dir / "Assembly"
bin_dir := release_dir / "Bin"

# Code signing (set CODE_SIGNING_CERTIFICATE_THUMBPRINT in .env or environment)
signing_thumbprint := env("CODE_SIGNING_CERTIFICATE_THUMBPRINT", "")
timestamp_url      := "http://timestamp.digicert.com"
sign_description   := "LISSTech Billboard"

# PSGallery (set PSGALLERY_API_KEY in .env or environment)
psgallery_key := env("PSGALLERY_API_KEY", "")

[private]
default:
    @just --list

# ── Build ───────────────────────────────────────────────────────────────────

# Build DLL + exe (Debug)
[script('pwsh', '-NoProfile')]
[extension('.ps1')]
build:
    $ErrorActionPreference = 'Stop'
    Write-Host "`n🔨 Building LISSTech.Billboard (Debug)" -ForegroundColor Cyan
    & dotnet build 'src/LISSTech.Billboard/LISSTech.Billboard.csproj' -c Debug -nologo -v:q
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    & dotnet build 'src/LISSTech.Billboard.Host/LISSTech.Billboard.Host.csproj' -c Debug -nologo -v:q
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    Write-Host "   ✅ Build complete" -ForegroundColor Green

# Build Release and assemble PS module in Release/
[script('pwsh', '-NoProfile')]
[extension('.ps1')]
publish:
    $ErrorActionPreference = 'Stop'
    $outDir = '{{ release_dir }}'
    $assemblyDir = '{{ assembly_dir }}'
    $binDir = '{{ bin_dir }}'

    if (Test-Path $outDir) { Remove-Item $outDir -Recurse -Force }
    New-Item -ItemType Directory -Path $assemblyDir -Force | Out-Null
    New-Item -ItemType Directory -Path $binDir -Force | Out-Null

    Write-Host "`n📦 Assembling module (Release)" -ForegroundColor Cyan

    & dotnet publish 'src/LISSTech.Billboard/LISSTech.Billboard.csproj' -c Release -o $assemblyDir -nologo -v:q
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    & dotnet publish 'src/LISSTech.Billboard.Host/LISSTech.Billboard.Host.csproj' -c Release -o $binDir -nologo -v:q
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    Get-ChildItem $binDir -Filter '*.pdb' | Remove-Item -Force

    $serviceUI = '{{ justfile_directory() }}/vendor/ServiceUI.exe'
    if (Test-Path $serviceUI) {
        Copy-Item $serviceUI $binDir -Force
    } else {
        Write-Warning "ServiceUI.exe not found at $serviceUI — skipping"
    }

    Copy-Item 'LISSTech.Billboard.psd1' $outDir -Force
    Copy-Item 'LISSTech.Billboard.psm1' $outDir -Force

    $dll = Get-Item (Join-Path $assemblyDir 'LISSTech.Billboard.dll')
    $exe = Get-Item (Join-Path $binDir 'Billboard.exe')
    Write-Host ("   LISSTech.Billboard.dll  {0,6:N0} KB" -f ($dll.Length / 1KB)) -ForegroundColor DarkGray
    Write-Host ("   Billboard.exe           {0,6:N0} KB" -f ($exe.Length / 1KB)) -ForegroundColor DarkGray
    Write-Host "   LISSTech.Billboard.psd1" -ForegroundColor DarkGray
    Write-Host "   LISSTech.Billboard.psm1" -ForegroundColor DarkGray
    Write-Host "   Module assembled at: $outDir" -ForegroundColor Green

# ── Test ────────────────────────────────────────────────────────────────────

# Run xUnit tests
[script('pwsh', '-NoProfile')]
[extension('.ps1')]
test:
    $ErrorActionPreference = 'Stop'
    Write-Host "`n🧪 Running tests" -ForegroundColor Cyan
    & dotnet test 'tests/LISSTech.Billboard.Tests/LISSTech.Billboard.Tests.csproj' --nologo -v:q
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# Visual smoke test — 20 variants (5 types × 2 modes × 2 themes) via PS module
[script('pwsh', '-NoProfile')]
[extension('.ps1')]
smoke:
    $ErrorActionPreference = 'Stop'
    $moduleDir = '{{ release_dir }}'
    $manifest = Join-Path $moduleDir 'LISSTech.Billboard.psd1'
    if (-not (Test-Path $manifest)) {
        Write-Host "`n❌ Module not found — run 'just publish' first." -ForegroundColor Red
        exit 1
    }

    Import-Module $manifest -Force

    Write-Host "`n🔍 Visual smoke test" -ForegroundColor Cyan

    $branding = New-BillboardBranding 'LISS Consulting'
    $types   = @('Info', 'Warn', 'Alert', 'Critical', 'Question')
    $themes  = @('Light', 'Dark')
    $modes   = @($false, $true)

    $scenarios = @{
        Info = @{
            Title   = 'Microsoft Teams Updated'
            Message = 'Microsoft Teams has been updated to version **1.7.00.26264**. No action is required — the update has already been applied. New features include improved meeting controls and faster file sharing.'
        }
        Warn = @{
            Title   = 'Storage Running Low'
            Message = "Your system drive **C:\\** has **4.2 GB** of free space remaining. When free space drops below 2 GB, system performance may degrade and Windows updates will stop installing.`n`n- Clear temporary files via *Disk Cleanup*`n- Move large files to **OneDrive** or a network share`n- Contact the helpdesk if you need assistance"
        }
        Alert = @{
            Title   = 'Password Expiring Soon'
            Message = 'Your Active Directory password will expire in **3 days** (April 11, 2026). Please change your password before it expires to avoid being locked out of your account and VPN access.'
        }
        Critical = @{
            Title   = 'Endpoint Protection Disabled'
            Message = "**Microsoft Defender** real-time protection has been disabled on this device. This leaves your system vulnerable to malware and other threats.`n`nIf you did not disable it intentionally, your device may already be compromised. Contact the helpdesk **immediately**."
        }
        Question = @{
            Title   = 'Restart Required'
            Message = 'A security update for **Windows 11** requires a restart to finish installing. This update patches a critical vulnerability (CVE-2026-21001) and should be applied as soon as possible.'
        }
    }

    $variants = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($type in $types) {
        foreach ($theme in $themes) {
            foreach ($modal in $modes) {
                $variants.Add(@{ Type = $type; Theme = $theme; Modal = $modal })
            }
        }
    }

    $total = $variants.Count
    for ($i = 0; $i -lt $total; $i++) {
        $v = $variants[$i]
        $s = $scenarios[$v.Type]
        $mode = if ($v.Modal) { 'modal' } else { 'toast' }
        $label = '{0}/{1}  {2} · {3} · {4}' -f ($i + 1), $total, $v.Type.ToLower(), $mode, $v.Theme.ToLower()
        Write-Host "   $label" -ForegroundColor DarkGray

        $params = @{
            Type     = $v.Type
            Title    = $s.Title
            Message  = $s.Message
            Branding = $branding
            Theme    = $v.Theme
            Timeout  = 4
        }
        if ($v.Modal) { $params.Modal = $true }

        if ($v.Type -eq 'Question') {
            $params.Timeout = 0
            $params.Buttons = @(
                New-BillboardButton 'Restart Now' -Value restart -Style Primary
                New-BillboardButton 'Remind in 4 Hours' -Value defer -Style Ghost -Defer 4h
            )
            $result = Request-Billboard (New-BillboardNotification @params)
            $clicked = if ($result.Timeout) { 'timeout' } elseif ($result.Dismissed) { 'dismissed' } else { $result.Button }
            Write-Host "      → $clicked" -ForegroundColor DarkGray
        } else {
            $null = Show-Billboard (New-BillboardNotification @params)
        }
    }

    Write-Host "   ✅ All $total variants shown." -ForegroundColor Green
    Write-Host ""

# ── Sign ────────────────────────────────────────────────────────────────────

# Sign DLLs, exe, and PS module files in Release/
[script('pwsh', '-NoProfile')]
[extension('.ps1')]
sign:
    $ErrorActionPreference = 'Stop'
    $thumbprint = '{{ signing_thumbprint }}'
    if (-not $thumbprint) {
        Write-Host "`n⏭️  Skipping signing (no certificate)" -ForegroundColor Yellow
        exit 0
    }

    $cert = Get-ChildItem Cert:\CurrentUser\My, Cert:\LocalMachine\My -CodeSigningCert |
        Where-Object Thumbprint -eq $thumbprint |
        Select-Object -First 1
    if (-not $cert) {
        Write-Host "`n❌ Certificate with thumbprint $thumbprint not found" -ForegroundColor Red
        exit 1
    }

    $cn = $cert.Subject -replace '^CN=', '' -replace ',.*', ''
    Write-Host "`n🔏 Signing binaries and module" -ForegroundColor Cyan
    Write-Host "   Certificate: $cn" -ForegroundColor DarkGray
    Write-Host "   Thumbprint:  $($thumbprint.Substring(0,8))..." -ForegroundColor DarkGray

    $outDir = '{{ release_dir }}'
    $assemblyDir = '{{ assembly_dir }}'
    $binDir = '{{ bin_dir }}'
    $tsUrl = '{{ timestamp_url }}'
    $desc = '{{ sign_description }}'

    # PowerShell files (Authenticode)
    foreach ($file in @(
        (Join-Path $outDir 'LISSTech.Billboard.psd1'),
        (Join-Path $outDir 'LISSTech.Billboard.psm1')
    )) {
        $name = [System.IO.Path]::GetFileName($file)
        Set-AuthenticodeSignature -FilePath $file -Certificate $cert `
            -TimestampServer $tsUrl -HashAlgorithm SHA256 | Out-Null
        if ((Get-AuthenticodeSignature $file).Status -ne 'Valid') {
            Write-Host "   ❌ $name" -ForegroundColor Red; exit 1
        }
        Write-Host "   ✅ $name" -ForegroundColor Green
    }

    # Binaries (signtool)
    foreach ($file in @(
        (Join-Path $assemblyDir 'LISSTech.Billboard.dll'),
        (Join-Path $binDir 'Billboard.exe')
    )) {
        $name = [System.IO.Path]::GetFileName($file)
        $out = & signtool sign /sha1 $thumbprint /d $desc /fd sha256 /tr $tsUrl /td sha256 /a /ph $file 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "   ❌ $name" -ForegroundColor Red
            Write-Host $out -ForegroundColor DarkGray
            exit $LASTEXITCODE
        }
        Write-Host "   ✅ $name" -ForegroundColor Green
    }

# ── Release ─────────────────────────────────────────────────────────────────

# Build Release, sign, and assemble final module
[script('pwsh', '-NoProfile')]
[extension('.ps1')]
release: test publish sign
    $dll = Get-Item '{{ assembly_dir }}/LISSTech.Billboard.dll'
    $exe = Get-Item '{{ bin_dir }}/Billboard.exe'
    $version = (Import-PowerShellDataFile '{{ release_dir }}/LISSTech.Billboard.psd1').ModuleVersion
    Write-Host ""
    Write-Host "🚀 Release complete" -ForegroundColor Green
    Write-Host ("   LISSTech.Billboard.dll  {0,6:N0} KB" -f ($dll.Length / 1KB)) -ForegroundColor DarkGray
    Write-Host ("   Billboard.exe           {0,6:N0} KB" -f ($exe.Length / 1KB)) -ForegroundColor DarkGray
    Write-Host "   Version                 $version" -ForegroundColor DarkGray
    Write-Host ""

# ── Publish ─────────────────────────────────────────────────────────────────

# Publish module to PowerShell Gallery (standalone, for retries)
[script('pwsh', '-NoProfile')]
[extension('.ps1')]
publish-gallery:
    $ErrorActionPreference = 'Stop'
    $psKey = '{{ psgallery_key }}'
    if (-not $psKey) {
        Write-Host "`n❌ PSGALLERY_API_KEY not set" -ForegroundColor Red
        exit 1
    }

    $moduleDir = '{{ release_dir }}'
    $manifest = Join-Path $moduleDir 'LISSTech.Billboard.psd1'
    if (-not (Test-Path $manifest)) {
        Write-Host "`n❌ Module not found — run 'just release' first." -ForegroundColor Red
        exit 1
    }

    $version = (Import-PowerShellDataFile $manifest).ModuleVersion
    Write-Host "`n📤 Publishing LISSTech.Billboard v$version to PSGallery" -ForegroundColor Cyan

    Publish-Module -Path $moduleDir -NuGetApiKey $psKey -ErrorAction Stop
    Write-Host "   ✅ LISSTech.Billboard v$version published" -ForegroundColor Green
    Write-Host ""

# ── Clean ───────────────────────────────────────────────────────────────────

# Remove Release/ and obj/ directories
[script('pwsh', '-NoProfile')]
[extension('.ps1')]
clean:
    $ErrorActionPreference = 'Stop'
    Write-Host "`n🧹 Cleaning" -ForegroundColor Cyan
    @('Release', 'src/LISSTech.Billboard/obj', 'src/LISSTech.Billboard/bin',
      'src/LISSTech.Billboard.Host/obj', 'src/LISSTech.Billboard.Host/bin',
      'tests/LISSTech.Billboard.Tests/obj', 'tests/LISSTech.Billboard.Tests/bin'
    ) | ForEach-Object {
        if (Test-Path $_) {
            Remove-Item $_ -Recurse -Force
            Write-Host "   Removed $_" -ForegroundColor DarkGray
        }
    }
