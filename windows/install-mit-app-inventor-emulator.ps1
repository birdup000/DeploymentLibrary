# Install MIT App Inventor Emulator Setup (Windows)
# Downloads and silently installs the MIT App Inventor emulator/USB setup tools.
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

try {
    $installerUrl = Get-AppInventorDownloadUrl

    Write-Host "Downloading $packageName..."
    Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing

    Write-Host "Installing $packageName..."
    $process = Start-Process -FilePath $installerPath -ArgumentList "/S" -Wait -NoNewWindow -PassThru
    if ($process.ExitCode -ne 0) {
        throw "$packageName installer failed with exit code $($process.ExitCode)."
    }

    Write-Host "$packageName installed successfully."
    Write-Host "A logout or reboot may be required before aiStarter is available for all users."
}
finally {
    Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
}
