# Install MakeCode Arcade Web App Shortcut (Windows)
# Creates all-users Desktop and Start Menu shortcuts for a configurable web app.
$ErrorActionPreference = 'Stop'

$shortcutName = if ([string]::IsNullOrWhiteSpace($env:SHORTCUT_NAME)) { "MakeCode Arcade" } else { $env:SHORTCUT_NAME.Trim() }
$appUrl = if ([string]::IsNullOrWhiteSpace($env:SHORTCUT_URL)) { "https://arcade.makecode.com/" } else { $env:SHORTCUT_URL.Trim() }

function Get-SafeShortcutFileName {
    param([string]$Name)

    $safeName = ($Name -replace '[\x00-\x1F<>:"/\\|?*]', '-').Trim().TrimEnd(".")
    if ([string]::IsNullOrWhiteSpace($safeName)) {
        throw "SHORTCUT_NAME does not contain any valid Windows filename characters."
    }

    return $safeName
}

function Resolve-ShortcutUrl {
    param([string]$Url)

    [Uri]$uri = $null
    if (-not [Uri]::TryCreate($Url, [UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -notin @("http", "https")) {
        throw "SHORTCUT_URL must be an absolute http or https URL."
    }

    return $uri.AbsoluteUri
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

function New-WebAppShortcut {
    param(
        [string]$ShortcutPath,
        [string]$Url,
        [string]$EdgePath,
        [string]$DisplayName
    )

    $directory = Split-Path $ShortcutPath -Parent
    New-Item -Path $directory -ItemType Directory -Force | Out-Null

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($ShortcutPath)

    if ($EdgePath) {
        $shortcut.TargetPath = $EdgePath
        $shortcut.Arguments = "--app=$Url"
        $shortcut.IconLocation = "$EdgePath,0"
    }
    else {
        $shortcut.TargetPath = "$env:WINDIR\System32\rundll32.exe"
        $shortcut.Arguments = "url.dll,FileProtocolHandler $Url"
        $shortcut.IconLocation = "$env:WINDIR\System32\shell32.dll,220"
    }

    $shortcut.Description = "Open $DisplayName"
    $shortcut.WorkingDirectory = $env:WINDIR
    $shortcut.Save()
}

$shortcutFileName = Get-SafeShortcutFileName -Name $shortcutName
$appUrl = Resolve-ShortcutUrl -Url $appUrl

$desktopDirectory = [Environment]::GetFolderPath("CommonDesktopDirectory")
if ([string]::IsNullOrWhiteSpace($desktopDirectory)) {
    $desktopDirectory = Join-Path $env:PUBLIC "Desktop"
}

$programsDirectory = [Environment]::GetFolderPath("CommonPrograms")
if ([string]::IsNullOrWhiteSpace($programsDirectory)) {
    $programsDirectory = Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs"
}

$edgePath = Get-EdgePath
$shortcutPaths = @(
    (Join-Path $desktopDirectory "$shortcutFileName.lnk"),
    (Join-Path $programsDirectory "Web Apps\$shortcutFileName.lnk")
)

foreach ($shortcutPath in $shortcutPaths) {
    Write-Host "Creating shortcut: $shortcutPath"
    New-WebAppShortcut -ShortcutPath $shortcutPath -Url $appUrl -EdgePath $edgePath -DisplayName $shortcutName
}

Write-Host "$shortcutName shortcuts created successfully for $appUrl."
