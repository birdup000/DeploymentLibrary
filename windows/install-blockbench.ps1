# Install Blockbench Desktop (Windows)
# Installs the latest Blockbench desktop release via WinGet.
$ErrorActionPreference = 'Stop'

$packageName = "Blockbench Desktop"
$packageId = "JannisX11.Blockbench"
$startMenuShortcutName = "Blockbench"
$shortcutSearchPatterns = @("Blockbench*.lnk")
$executableNames = @("Blockbench.exe")
$executableCandidatePaths = @(
    "$env:ProgramFiles\Blockbench\Blockbench.exe",
    "${env:ProgramFiles(x86)}\Blockbench\Blockbench.exe",
    "$env:LOCALAPPDATA\Programs\Blockbench\Blockbench.exe",
    "$env:SystemDrive\Users\*\AppData\Local\Programs\Blockbench\Blockbench.exe"
)
$appDisplayNamePatterns = @("Blockbench*")
$fallbackAppUserModelId = ""

$source = "winget"

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

    $usersDirectory = if (-not [string]::IsNullOrWhiteSpace($env:SystemDrive)) { Join-Path $env:SystemDrive "Users" } else { $null }
    if (-not [string]::IsNullOrWhiteSpace($usersDirectory) -and (Test-Path $usersDirectory)) {
        Get-ChildItem -Path $usersDirectory -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $roots += (Join-Path $_.FullName "AppData\Roaming\Microsoft\Windows\Start Menu\Programs")
        }
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
    param(
        [string[]]$ExecutableNames,
        [string[]]$CandidatePaths
    )

    $targetPath = Get-AppPathExecutable -ExecutableNames $ExecutableNames
    if ($targetPath) {
        return $targetPath
    }

    $targetPath = Get-FirstExistingPath -CandidatePaths $CandidatePaths
    if ($targetPath) {
        return $targetPath
    }

    $searchRoots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA) |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path $_) } |
        Select-Object -Unique

    foreach ($root in $searchRoots) {
        foreach ($executableName in @($ExecutableNames)) {
            if ([string]::IsNullOrWhiteSpace($executableName)) {
                continue
            }

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

function Get-InstalledAppUserModelId {
    param([string[]]$DisplayNamePatterns)

    if (-not (Get-Command Get-StartApps -ErrorAction SilentlyContinue)) {
        return $null
    }

    $startApps = @(Get-StartApps)
    foreach ($pattern in @($DisplayNamePatterns)) {
        if ([string]::IsNullOrWhiteSpace($pattern)) {
            continue
        }

        $match = $startApps |
            Where-Object { $_.Name -like $pattern } |
            Sort-Object Name |
            Select-Object -First 1
        if ($match) {
            return $match.AppID
        }
    }

    return $null
}

function New-StartMenuShortcut {
    param(
        [string]$ShortcutName,
        [string]$TargetPath,
        [string]$Arguments = "",
        [string]$WorkingDirectory = "",
        [string]$IconLocation = ""
    )

    $programsDirectory = Get-CommonProgramsDirectory
    New-Item -Path $programsDirectory -ItemType Directory -Force | Out-Null

    $shortcutPath = Join-Path $programsDirectory "$ShortcutName.lnk"
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $TargetPath
    if (-not [string]::IsNullOrWhiteSpace($Arguments)) {
        $shortcut.Arguments = $Arguments
    }

    $shortcut.Description = "Open $ShortcutName"
    if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
        $shortcut.WorkingDirectory = $WorkingDirectory
    }
    elseif (Test-Path $TargetPath) {
        $shortcut.WorkingDirectory = Split-Path $TargetPath -Parent
    }

    if (-not [string]::IsNullOrWhiteSpace($IconLocation)) {
        $shortcut.IconLocation = $IconLocation
    }
    elseif (Test-Path $TargetPath) {
        $shortcut.IconLocation = "$TargetPath,0"
    }

    $shortcut.Save()
    return $shortcutPath
}

function Ensure-StartMenuShortcut {
    param(
        [string]$ShortcutName,
        [string[]]$SearchPatterns = @(),
        [string[]]$ExecutableNames = @(),
        [string[]]$CandidatePaths = @(),
        [string[]]$AppDisplayNamePatterns = @(),
        [string]$FallbackAppUserModelId = ""
    )

    $shortcutPath = Copy-ExistingStartMenuShortcut -ShortcutName $ShortcutName -SearchPatterns $SearchPatterns
    if ($shortcutPath) {
        Write-Host "Start Menu shortcut available: $shortcutPath"
        return
    }

    $targetPath = Find-InstalledExecutable -ExecutableNames $ExecutableNames -CandidatePaths $CandidatePaths
    if ($targetPath) {
        $shortcutPath = New-StartMenuShortcut -ShortcutName $ShortcutName -TargetPath $targetPath
        Write-Host "Created Start Menu shortcut: $shortcutPath"
        return
    }

    $appUserModelId = Get-InstalledAppUserModelId -DisplayNamePatterns $AppDisplayNamePatterns
    if ([string]::IsNullOrWhiteSpace($appUserModelId)) {
        $appUserModelId = $FallbackAppUserModelId
    }

    if (-not [string]::IsNullOrWhiteSpace($appUserModelId)) {
        $shortcutPath = New-StartMenuShortcut `
            -ShortcutName $ShortcutName `
            -TargetPath "$env:WINDIR\explorer.exe" `
            -Arguments "shell:AppsFolder\$appUserModelId" `
            -WorkingDirectory $env:WINDIR `
            -IconLocation "$env:WINDIR\System32\shell32.dll,220"
        Write-Host "Created Start Menu shortcut: $shortcutPath"
        return
    }

    Write-Warning "Could not create a Start Menu shortcut for $ShortcutName because no installed executable or app identifier was found."
}

function Test-WingetPackageInstalled {
    param(
        [string]$WingetPath,
        [string]$PackageId
    )

    $listArguments = @("list", "--id", $PackageId, "--exact")
    $output = & $WingetPath @listArguments 2>&1
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        return $false
    }

    $outputText = $output | Out-String
    return $outputText -match [regex]::Escape($PackageId)
}

function Test-BlockbenchInstalled {
    param(
        [string]$WingetPath,
        [string]$PackageId
    )

    if (Test-WingetPackageInstalled -WingetPath $WingetPath -PackageId $PackageId) {
        return $true
    }

    if (Find-InstalledExecutable -ExecutableNames $executableNames -CandidatePaths $executableCandidatePaths) {
        return $true
    }

    $appUserModelId = Get-InstalledAppUserModelId -DisplayNamePatterns $appDisplayNamePatterns
    return -not [string]::IsNullOrWhiteSpace($appUserModelId)
}

$winget = Get-WingetPath
$isInstalled = Test-BlockbenchInstalled -WingetPath $winget -PackageId $packageId

if ($isInstalled) {
    Write-Host "$packageName is already installed."
}
else {
    $arguments = @("install", "--id", $packageId, "--exact", "--source", $source, "--silent", "--accept-package-agreements", "--accept-source-agreements")

    Write-Host "Installing $packageName..."
    & $winget @arguments
    $installExitCode = $LASTEXITCODE
    if ($installExitCode -ne 0) {
        if (Test-BlockbenchInstalled -WingetPath $winget -PackageId $packageId) {
            Write-Host "$packageName is installed. Continuing to ensure Start Menu shortcut."
        }
        else {
            throw "$packageName install failed with exit code $installExitCode."
        }
    }
    else {
        Write-Host "$packageName installed successfully."
    }
}

Ensure-StartMenuShortcut -ShortcutName $startMenuShortcutName -SearchPatterns $shortcutSearchPatterns -ExecutableNames $executableNames -CandidatePaths $executableCandidatePaths -AppDisplayNamePatterns $appDisplayNamePatterns -FallbackAppUserModelId $fallbackAppUserModelId
