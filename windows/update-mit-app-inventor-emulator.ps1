# Update MIT App Inventor Emulator Setup (Windows)
# Reinstalls the latest MIT App Inventor emulator/USB setup tools.
$ErrorActionPreference = 'Stop'

$packageName = "MIT App Inventor Emulator Setup"
$setupLink = "https://appinv.us/aisetup_windows"
$installerPath = Join-Path $env:TEMP "MIT_App_Inventor_Tools_win_setup.exe"

function Get-AppInventorDownloadUrl {
    $request = [System.Net.WebRequest]::Create($setupLink)
    $request.AllowAutoRedirect = $false
    $response = $request.GetResponse()

    try {
        $location = $response.Headers["Location"]
    }
    finally {
        $response.Close()
    }

    if ($location -notmatch "/share/([^/?#]+)") {
        throw "Could not resolve MIT App Inventor setup download from $setupLink."
    }

    return "https://files.appinventor.mit.edu/api/public/dl/$($matches[1])"
}

function Get-AppInventorUninstallString {
    $registryPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    $entry = Get-ItemProperty $registryPaths -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -match "App Inventor" -or $_.DisplayName -match "MIT.*Inventor" } |
        Select-Object -First 1

    if ($entry -and $entry.UninstallString) {
        return $entry.UninstallString
    }

    $knownUninstallers = @(
        "$env:ProgramFiles\AppInventor\uninstall.exe",
        "${env:ProgramFiles(x86)}\AppInventor\uninstall.exe"
    )

    foreach ($path in $knownUninstallers) {
        if (Test-Path $path) {
            return "`"$path`""
        }
    }

    return $null
}

function Invoke-AppInventorUninstall {
    param([string]$UninstallString)

    if ([string]::IsNullOrWhiteSpace($UninstallString)) {
        Write-Host "No existing $packageName installation found."
        return
    }

    if ($UninstallString -match '^\s*"([^"]+)"\s*(.*)$') {
        $filePath = $matches[1]
        $arguments = $matches[2]
    }
    elseif ($UninstallString -match '^\s*(\S+)\s*(.*)$') {
        $filePath = $matches[1]
        $arguments = $matches[2]
    }
    else {
        throw "Could not parse uninstall command: $UninstallString"
    }

    if ($arguments -notmatch '(^|\s)/S(\s|$)') {
        $arguments = "$arguments /S".Trim()
    }

    Write-Host "Uninstalling existing $packageName..."
    $process = Start-Process -FilePath $filePath -ArgumentList $arguments -Wait -NoNewWindow -PassThru
    if ($process.ExitCode -ne 0) {
        throw "$packageName uninstall failed with exit code $($process.ExitCode)."
    }
}

try {
    Invoke-AppInventorUninstall -UninstallString (Get-AppInventorUninstallString)
    $installerUrl = Get-AppInventorDownloadUrl

    Write-Host "Downloading $packageName..."
    Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing

    Write-Host "Installing $packageName..."
    $process = Start-Process -FilePath $installerPath -ArgumentList "/S" -Wait -NoNewWindow -PassThru
    if ($process.ExitCode -ne 0) {
        throw "$packageName installer failed with exit code $($process.ExitCode)."
    }

    Write-Host "$packageName update completed successfully."
    Write-Host "A logout or reboot is recommended before using aiStarter or the emulator."
}
finally {
    Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
}
