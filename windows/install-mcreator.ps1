# Install MCreator (Windows)
# Installs or updates MCreator 2025.2 from the official GitHub release.
$ErrorActionPreference = 'Stop'

$packageName = "MCreator"
$packageVersion = "2025.2"
$releaseVersion = "2025.2.28610"
$installerFileName = "MCreator.2025.2.Windows.64bit.exe"
$installerUrl = "https://github.com/MCreator/MCreator/releases/download/$releaseVersion/$installerFileName"
$expectedSha256 = "95968b2793403eaa331123c944017c703cb74f203b2a2b6817cc12463c534666"
$startMenuShortcutName = "MCreator"
$shortcutSearchPatterns = @("MCreator*.lnk")
$executableNames = @("MCreator.exe")
$executableCandidatePaths = @(
    "$env:ProgramFiles\MCreator\MCreator.exe",
    "${env:ProgramFiles(x86)}\MCreator\MCreator.exe",
    "$env:ProgramFiles\Pylo\MCreator\MCreator.exe",
    "${env:ProgramFiles(x86)}\Pylo\MCreator\MCreator.exe",
    "$env:SystemDrive\Pylo\MCreator*\MCreator.exe",
    "$env:LOCALAPPDATA\Programs\MCreator\MCreator.exe",
    "$env:ProgramFiles\MCreator*\MCreator.exe",
    "${env:ProgramFiles(x86)}\MCreator*\MCreator.exe"
)

function Get-CommonProgramsDirectory {
    $programsDirectory = [Environment]::GetFolderPath("CommonPrograms")
    if ([string]::IsNullOrWhiteSpace($programsDirectory)) {
        $programsDirectory = Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs"
    }

    return $programsDirectory
}

function Get-ShortcutSearchRoots {
    $roots = @()
    $commonPrograms = Get-CommonProgramsDirectory
    if (-not [string]::IsNullOrWhiteSpace($commonPrograms)) {
        $roots += $commonPrograms
    }

    if (-not [string]::IsNullOrWhiteSpace($env:APPDATA)) {
        $roots += (Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs")
    }

    if (-not [string]::IsNullOrWhiteSpace($env:ProgramData)) {
        $roots += (Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs")
    }

    return $roots | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path $_) } | Select-Object -Unique
}

function Copy-ExistingStartMenuShortcut {
    param(
        [string]$ShortcutName,
        [string[]]$SearchPatterns
    )

    $programsDirectory = Get-CommonProgramsDirectory
    $shortcutPath = Join-Path $programsDirectory "$ShortcutName.lnk"
    if (Test-Path $shortcutPath) {
        return $shortcutPath
    }

    $patterns = @($SearchPatterns) + @("$ShortcutName.lnk")
    $patterns = $patterns | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

    foreach ($root in Get-ShortcutSearchRoots) {
        foreach ($pattern in $patterns) {
            $match = Get-ChildItem -Path $root -Filter $pattern -File -Recurse -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1
            if ($match) {
                New-Item -Path $programsDirectory -ItemType Directory -Force | Out-Null
                Copy-Item -Path $match.FullName -Destination $shortcutPath -Force
                return $shortcutPath
            }
        }
    }

    return $null
}

function Get-AppPathExecutable {
    param([string[]]$ExecutableNames)

    $registryRoots = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths"
    )

    foreach ($registryRoot in $registryRoots) {
        foreach ($executableName in @($ExecutableNames)) {
            if ([string]::IsNullOrWhiteSpace($executableName)) {
                continue
            }

            $keyPath = Join-Path $registryRoot $executableName
            if (-not (Test-Path $keyPath)) {
                continue
            }

            $value = (Get-Item -Path $keyPath).GetValue("")
            if (-not $value) {
                continue
            }

            $targetPath = [Environment]::ExpandEnvironmentVariables(($value -as [string]).Trim('"'))
            if (Test-Path $targetPath) {
                return $targetPath
            }
        }
    }

    return $null
}

function Get-FirstExistingPath {
    param([string[]]$CandidatePaths)

    foreach ($candidatePath in @($CandidatePaths)) {
        if ([string]::IsNullOrWhiteSpace($candidatePath)) {
            continue
        }

        $match = Get-Item -Path $candidatePath -ErrorAction SilentlyContinue |
            Where-Object { -not $_.PSIsContainer } |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if ($match) {
            return $match.FullName
        }
    }

    return $null
}

function Find-InstalledExecutable {
    $targetPath = Get-AppPathExecutable -ExecutableNames $executableNames
    if ($targetPath) {
        return $targetPath
    }

    $targetPath = Get-FirstExistingPath -CandidatePaths $executableCandidatePaths
    if ($targetPath) {
        return $targetPath
    }

    $searchRoots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA, (Join-Path $env:SystemDrive "Pylo")) |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path $_) } |
        Select-Object -Unique

    foreach ($root in $searchRoots) {
        foreach ($executableName in @($executableNames)) {
            $match = Get-ChildItem -Path $root -Filter $executableName -File -Recurse -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1
            if ($match) {
                return $match.FullName
            }
        }
    }

    return $null
}

function New-StartMenuShortcut {
    param(
        [string]$ShortcutName,
        [string]$TargetPath
    )

    $programsDirectory = Get-CommonProgramsDirectory
    New-Item -Path $programsDirectory -ItemType Directory -Force | Out-Null

    $shortcutPath = Join-Path $programsDirectory "$ShortcutName.lnk"
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $TargetPath
    $shortcut.Description = "Open $ShortcutName"
    $shortcut.WorkingDirectory = Split-Path $TargetPath -Parent
    $shortcut.IconLocation = "$TargetPath,0"
    $shortcut.Save()
    return $shortcutPath
}

function Ensure-StartMenuShortcut {
    $shortcutPath = Copy-ExistingStartMenuShortcut -ShortcutName $startMenuShortcutName -SearchPatterns $shortcutSearchPatterns
    if ($shortcutPath) {
        Write-Host "Start Menu shortcut available: $shortcutPath"
        return
    }

    $targetPath = Find-InstalledExecutable
    if (-not $targetPath) {
        Write-Warning "Could not create a Start Menu shortcut for $startMenuShortcutName because MCreator.exe was not found."
        return
    }

    $shortcutPath = New-StartMenuShortcut -ShortcutName $startMenuShortcutName -TargetPath $targetPath
    Write-Host "Created Start Menu shortcut: $shortcutPath"
}

$tempDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("MCreatorInstall-" + [guid]::NewGuid().ToString())
$installerPath = Join-Path $tempDirectory $installerFileName

try {
    New-Item -Path $tempDirectory -ItemType Directory -Force | Out-Null

    Write-Host "Downloading $packageName $packageVersion from $installerUrl..."
    Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing

    $actualSha256 = (Get-FileHash -Path $installerPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualSha256 -ne $expectedSha256) {
        throw "$packageName installer SHA-256 mismatch. Expected $expectedSha256 but found $actualSha256."
    }

    Write-Host "Installing $packageName $packageVersion..."
    $process = Start-Process -FilePath $installerPath -ArgumentList "/S" -Wait -NoNewWindow -PassThru
    if ($process.ExitCode -ne 0) {
        throw "$packageName installer failed with exit code $($process.ExitCode)."
    }

    Write-Host "$packageName $packageVersion install/update completed successfully."
    Ensure-StartMenuShortcut
}
finally {
    Remove-Item -Path $tempDirectory -Recurse -Force -ErrorAction SilentlyContinue
}
