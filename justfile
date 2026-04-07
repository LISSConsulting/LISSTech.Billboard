set shell := ["pwsh", "-NoProfile", "-Command"]
set dotenv-load

release_dir := justfile_directory() / "Release/LISSTech.Billboard"

[private]
default:
    @just --list

# Build DLL + exe (Debug)
[script('pwsh', '-NoProfile')]
[extension('.ps1')]
build:
    $ErrorActionPreference = 'Stop'
    Write-Host 'Building LISSTech.Billboard...' -ForegroundColor Cyan
    & dotnet build 'src/LISSTech.Billboard/LISSTech.Billboard.csproj' -c Debug -nologo -v:q
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    & dotnet build 'src/LISSTech.Billboard.Host/LISSTech.Billboard.Host.csproj' -c Debug -nologo -v:q
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    Write-Host '  Build complete (Debug)' -ForegroundColor Green

# Build Release and assemble PS module in Release/
[script('pwsh', '-NoProfile')]
[extension('.ps1')]
publish:
    $ErrorActionPreference = 'Stop'
    $outDir = '{{ release_dir }}'
    $assemblyDir = Join-Path $outDir 'Assembly'
    $binDir = Join-Path $outDir 'Bin'

    # Clean
    if (Test-Path $outDir) { Remove-Item $outDir -Recurse -Force }
    New-Item -ItemType Directory -Path $assemblyDir -Force | Out-Null
    New-Item -ItemType Directory -Path $binDir -Force | Out-Null

    Write-Host 'Publishing LISSTech.Billboard...' -ForegroundColor Cyan

    # Build DLL
    & dotnet publish 'src/LISSTech.Billboard/LISSTech.Billboard.csproj' -c Release -o $assemblyDir -nologo -v:q
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    # Build exe
    & dotnet publish 'src/LISSTech.Billboard.Host/LISSTech.Billboard.Host.csproj' -c Release -o $binDir -nologo -v:q
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    # Remove build artifacts that aren't needed at runtime
    Get-ChildItem $binDir -Filter '*.pdb' | Remove-Item -Force

    # Copy ServiceUI.exe to Bin/
    $serviceUI = '{{ justfile_directory() }}/vendor/ServiceUI.exe'
    if (Test-Path $serviceUI) {
        Copy-Item $serviceUI $binDir -Force
    } else {
        Write-Warning "ServiceUI.exe not found at $serviceUI — skipping"
    }

    # Copy PS module files
    Copy-Item 'LISSTech.Billboard.psd1' $outDir -Force
    Copy-Item 'LISSTech.Billboard.psm1' $outDir -Force

    $dllSize = '{0:N0} KB' -f ((Get-Item (Join-Path $assemblyDir 'LISSTech.Billboard.dll')).Length / 1KB)
    $exeSize = '{0:N0} KB' -f ((Get-Item (Join-Path $binDir 'Billboard.exe')).Length / 1KB)
    Write-Host "  LISSTech.Billboard.dll ($dllSize)" -ForegroundColor Green
    Write-Host "  Billboard.exe ($exeSize)" -ForegroundColor Green
    Write-Host "  Module assembled at: $outDir" -ForegroundColor Green

# Run xUnit tests
[script('pwsh', '-NoProfile')]
[extension('.ps1')]
test:
    $ErrorActionPreference = 'Stop'
    & dotnet test 'tests/LISSTech.Billboard.Tests/LISSTech.Billboard.Tests.csproj' --nologo -v:q
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# Remove Release/ and obj/ directories
[script('pwsh', '-NoProfile')]
[extension('.ps1')]
clean:
    $ErrorActionPreference = 'Stop'
    @('Release', 'src/LISSTech.Billboard/obj', 'src/LISSTech.Billboard/bin',
      'src/LISSTech.Billboard.Host/obj', 'src/LISSTech.Billboard.Host/bin',
      'tests/LISSTech.Billboard.Tests/obj', 'tests/LISSTech.Billboard.Tests/bin'
    ) | ForEach-Object {
        if (Test-Path $_) {
            Remove-Item $_ -Recurse -Force
            Write-Host "  Removed $_" -ForegroundColor Yellow
        }
    }
