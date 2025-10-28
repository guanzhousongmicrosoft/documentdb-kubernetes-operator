# kubectl-documentdb installation script for Windows
# Auto-detects architecture
param(
    [string]$Version = "latest"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = 'SilentlyContinue'

$REPO = "guanzhousongmicrosoft/documentdb-kubernetes-operator"

# Detect architecture
$ARCH = "amd64"
try {
    $osArch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
    if ($osArch -eq [System.Runtime.InteropServices.Architecture]::Arm64) {
        $ARCH = "arm64"
    }
} catch {
    # Fallback detection
    if ([Environment]::Is64BitOperatingSystem) {
        $ARCH = "amd64"
    } else {
        Write-Error "Unsupported architecture: 32-bit Windows is not supported"
        exit 1
    }
}

$PLATFORM = "windows-$ARCH"
$BINARY = "kubectl-documentdb.exe"
$ARCHIVE = "kubectl-documentdb-$PLATFORM.zip"

# Construct download URL
if ($Version -eq "latest") {
    $URL = "https://github.com/$REPO/releases/latest/download/$ARCHIVE"
    Write-Host "Installing latest version of kubectl-documentdb for $PLATFORM..." -ForegroundColor Cyan
} else {
    $URL = "https://github.com/$REPO/releases/download/$Version/$ARCHIVE"
    Write-Host "Installing kubectl-documentdb $Version for $PLATFORM..." -ForegroundColor Cyan
}

# Download
Write-Host "Downloading from: $URL" -ForegroundColor Gray
try {
    Invoke-WebRequest -Uri $URL -OutFile $ARCHIVE -UseBasicParsing
} catch {
    Write-Error "Failed to download: $_"
    exit 1
}

# Extract
Write-Host "Extracting..." -ForegroundColor Cyan
try {
    Expand-Archive -Path $ARCHIVE -DestinationPath . -Force
} catch {
    Write-Error "Failed to extract: $_"
    Remove-Item $ARCHIVE -ErrorAction SilentlyContinue
    exit 1
}

# Install
$InstallPath = "$env:USERPROFILE\bin"
Write-Host "Installing to $InstallPath..." -ForegroundColor Cyan

if (-not (Test-Path $InstallPath)) {
    New-Item -ItemType Directory -Path $InstallPath | Out-Null
}

try {
    Move-Item -Path $BINARY -Destination $InstallPath -Force
} catch {
    Write-Error "Failed to install: $_"
    Remove-Item $ARCHIVE -ErrorAction SilentlyContinue
    exit 1
}

# Add to PATH if not already there
$CurrentPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($CurrentPath -notlike "*$InstallPath*") {
    [Environment]::SetEnvironmentVariable("Path", "$CurrentPath;$InstallPath", "User")
    Write-Host "Added $InstallPath to PATH" -ForegroundColor Green
    Write-Host "Please restart your terminal for PATH changes to take effect" -ForegroundColor Yellow
}

# Cleanup
Write-Host "Cleaning up..." -ForegroundColor Cyan
Remove-Item $ARCHIVE -ErrorAction SilentlyContinue

# Success
Write-Host ""
Write-Host "✓ kubectl-documentdb installed successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "Get started:" -ForegroundColor Cyan
Write-Host "  kubectl documentdb --help"
Write-Host ""
if ($CurrentPath -notlike "*$InstallPath*") {
    Write-Host "Note: Restart your terminal for the installation to take effect" -ForegroundColor Yellow
}
