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

function Get-CommonProgramsDirectory {
    $programsDirectory = [Environment]::GetFolderPath("CommonPrograms")
    if ([string]::IsNullOrWhiteSpace($programsDirectory)) {
        $programsDirectory = Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs"
    }

    return $programsDirectory
}

function Get-EdgePath {
    $candidatePaths = @(
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
        "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe"
    )

    foreach ($path in $candidatePaths) {
        if (Test-Path $path) {
            return $path
        }
    }

    return $null
}

function New-WebAppStartMenuShortcut {
    param(
        [string]$ShortcutName,
        [string]$Url
    )

    [Uri]$uri = $null
    if (-not [Uri]::TryCreate($Url, [UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -notin @("http", "https")) {
        throw "MIT App Inventor Start Menu URL must be an absolute http or https URL."
    }

    $programsDirectory = Get-CommonProgramsDirectory
    New-Item -Path $programsDirectory -ItemType Directory -Force | Out-Null

    $shortcutPath = Join-Path $programsDirectory "$ShortcutName.lnk"
    $edgePath = Get-EdgePath
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)

    if ($edgePath) {
        $shortcut.TargetPath = $edgePath
        $shortcut.Arguments = "--app=$($uri.AbsoluteUri)"
        $shortcut.IconLocation = "$edgePath,0"
    }
    else {
        $shortcut.TargetPath = "$env:WINDIR\System32\rundll32.exe"
        $shortcut.Arguments = "url.dll,FileProtocolHandler $($uri.AbsoluteUri)"
        $shortcut.IconLocation = "$env:WINDIR\System32\shell32.dll,220"
    }

    $shortcut.Description = "Open $ShortcutName"
    $shortcut.WorkingDirectory = $env:WINDIR
    $shortcut.Save()
    Write-Host "Created Start Menu shortcut: $shortcutPath"
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
    New-WebAppStartMenuShortcut -ShortcutName "MIT App Inventor" -Url "https://ai2.appinventor.mit.edu/"
    Write-Host "A logout or reboot may be required before aiStarter is available for all users."
}
finally {
    Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
}
