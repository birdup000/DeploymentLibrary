# Install MIT App Inventor Emulator Setup (Windows)
# Downloads from the official MIT Windows setup page and silently installs or updates the emulator/USB setup tools.
$ErrorActionPreference = 'Stop'

$packageName = "MIT App Inventor Emulator Setup"
$setupPageUrl = "https://appinventor.mit.edu/explore/ai2/windows.html"
$installerFileName = "MIT_App_Inventor_Tools_win_setup64.exe"
$tempDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("MITAppInventor-" + [guid]::NewGuid().ToString())
$installerPath = Join-Path $tempDirectory $installerFileName

function Wait-AppInventorSetupProcess {
    param([int]$TimeoutSeconds = 600)

    $processName = [System.IO.Path]::GetFileNameWithoutExtension($installerFileName)
    $processes = @(Get-Process -Name $processName -ErrorAction SilentlyContinue)
    if ($processes.Count -eq 0) {
        return
    }

    Write-Host "Waiting for an existing $packageName installer process to finish..."
    try {
        $processes | Wait-Process -Timeout $TimeoutSeconds -ErrorAction Stop
    }
    catch {
        throw "Timed out waiting for an existing $packageName installer process to finish."
    }
}

function Get-AppInventorDownloadUrl {
    Write-Host "Resolving $packageName download from $setupPageUrl..."
    $page = Invoke-WebRequest -Uri $setupPageUrl -UseBasicParsing
    $content = $page.Content

    $downloadPattern = '<a\s+[^>]*href=["'']([^"'']+)["''][^>]*>\s*Download the installer\.?\s*</a>'
    $downloadMatch = [regex]::Match($content, $downloadPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if (-not $downloadMatch.Success) {
        $shortLinkPattern = 'href=["'']([^"'']*appinv\.us/aisetup[^"'']*)["'']'
        $downloadMatch = [regex]::Match($content, $shortLinkPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    }

    if (-not $downloadMatch.Success) {
        throw "Could not find the MIT App Inventor setup download link on $setupPageUrl."
    }

    $href = [System.Net.WebUtility]::HtmlDecode($downloadMatch.Groups[1].Value)
    $downloadUri = [Uri]::new([Uri]$setupPageUrl, $href)
    return $downloadUri.AbsoluteUri
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
    Wait-AppInventorSetupProcess
    New-Item -Path $tempDirectory -ItemType Directory -Force | Out-Null

    Invoke-AppInventorUninstall -UninstallString (Get-AppInventorUninstallString)
    $installerUrl = Get-AppInventorDownloadUrl

    Write-Host "Downloading $packageName..."
    Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing

    Write-Host "Installing $packageName..."
    $process = Start-Process -FilePath $installerPath -ArgumentList "/S" -Wait -NoNewWindow -PassThru
    if ($process.ExitCode -ne 0) {
        throw "$packageName installer failed with exit code $($process.ExitCode)."
    }

    Write-Host "$packageName install/update completed successfully."
    New-WebAppStartMenuShortcut -ShortcutName "MIT App Inventor" -Url "https://ai2.appinventor.mit.edu/"
    Write-Host "A logout or reboot may be required before aiStarter is available for all users."
}
finally {
    Remove-Item $tempDirectory -Recurse -Force -ErrorAction SilentlyContinue
}
