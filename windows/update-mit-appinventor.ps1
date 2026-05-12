# Update MIT App Inventor Setup Tools (Windows)
# Downloads the latest setup tools and runs the MIT App Inventor installer in update mode.
$ErrorActionPreference = 'Stop'

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "MIT App Inventor Setup Tools must be updated from an elevated PowerShell session."
    }
}

function Get-AppInventorInstallerUrl {
    if ($env:APPINVENTOR_INSTALLER_URL) {
        return $env:APPINVENTOR_INSTALLER_URL
    }

    $setupPageUrl = "https://appinventor.mit.edu/explore/ai2/windows.html"
    $fallbackUrl = "https://appinv.us/aisetup_win_30_265.exe"

    Write-Host "Resolving latest MIT App Inventor Windows installer..."
    try {
        $page = Invoke-WebRequest -Uri $setupPageUrl -UseBasicParsing
        $match = [regex]::Match($page.Content, "https?://appinv\.us/aisetup_win_[^`"'<> ]+\.exe")
        if ($match.Success) {
            return $match.Value
        }

        $link = $page.Links | Where-Object { $_.href -match "aisetup_win_.*\.exe$" } | Select-Object -First 1
        if ($link) {
            if ($link.href -match "^https?://") {
                return $link.href
            }

            $baseUri = [System.Uri]$setupPageUrl
            return (New-Object -TypeName System.Uri -ArgumentList $baseUri, $link.href).AbsoluteUri
        }
    } catch {
        Write-Warning "Could not resolve latest installer from MIT setup page: $($_.Exception.Message)"
    }

    Write-Warning "Using fallback MIT App Inventor installer URL: $fallbackUrl"
    return $fallbackUrl
}

function Stop-AppInventorProcesses {
    $processes = Get-Process -Name "aiStarter" -ErrorAction SilentlyContinue
    if ($processes) {
        Write-Host "Stopping aiStarter before update..."
        $processes | Stop-Process -Force -ErrorAction SilentlyContinue
    }
}

if (-not [Environment]::Is64BitOperatingSystem) {
    throw "The current MIT App Inventor Windows setup tools require 64-bit Windows."
}

Assert-Administrator
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$installScope = if ($env:APPINVENTOR_INSTALL_SCOPE) { $env:APPINVENTOR_INSTALL_SCOPE.ToLowerInvariant() } else { "all" }
if ($installScope -notin @("all", "current")) {
    throw "APPINVENTOR_INSTALL_SCOPE must be 'all' or 'current'."
}

$autoReboot = $env:AUTO_REBOOT -eq "true"
$installerUrl = Get-AppInventorInstallerUrl
$installerUri = [System.Uri]$installerUrl
$installerFileName = Split-Path -Path $installerUri.AbsolutePath -Leaf
if (-not $installerFileName) {
    $installerFileName = "MIT_App_Inventor_Tools_win_setup64.exe"
}

$installerPath = Join-Path $env:TEMP $installerFileName

try {
    Stop-AppInventorProcesses

    Write-Host "Downloading MIT App Inventor Setup Tools update..."
    Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing

    Write-Host "Updating MIT App Inventor Setup Tools..."
    $arguments = @("/S", "/update", "/user=$installScope", "/skiplicense")
    $process = Start-Process -FilePath $installerPath -ArgumentList $arguments -Wait -NoNewWindow -PassThru
    if ($process.ExitCode -ne 0) {
        throw "MIT App Inventor updater exited with code $($process.ExitCode)."
    }
} finally {
    Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
}

Write-Host "MIT App Inventor Setup Tools update complete."
if ($autoReboot) {
    Write-Host "AUTO_REBOOT=true; rebooting to complete the update."
    Restart-Computer -Force
} else {
    Write-Host "A logout or reboot is recommended before using the updated App Inventor emulator/USB tools."
}
