# Install Xbox Game Bar (Windows)
# Installs Xbox Game Bar from the Microsoft Store via WinGet.
$ErrorActionPreference = 'Stop'

$packageName = "Xbox Game Bar"
$packageId = "9NZKPSTSNW4P"
$source = "msstore"

function Get-WingetPath {
    $command = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $candidatePaths = @(
        "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe",
        "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe",
        "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_x86__8wekyb3d8bbwe\winget.exe",
        "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_arm64__8wekyb3d8bbwe\winget.exe"
    )

    foreach ($path in $candidatePaths) {
        $match = Get-Item $path -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($match) {
            return $match.FullName
        }
    }

    throw "WinGet is required but winget.exe could not be found. Install or repair Microsoft App Installer first."
}

$winget = Get-WingetPath
$arguments = @("install", "--id", $packageId, "--exact", "--source", $source, "--silent", "--accept-package-agreements", "--accept-source-agreements")

Write-Host "Installing $packageName..."
& $winget @arguments
if ($LASTEXITCODE -ne 0) {
    throw "$packageName install failed with exit code $LASTEXITCODE."
}

Write-Host "$packageName installed successfully."
