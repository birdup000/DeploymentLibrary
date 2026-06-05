# Install CapCut (Windows)
# Installs or updates the latest CapCut release via WinGet.
$ErrorActionPreference = 'Stop'

$packageName = "CapCut"
$packageId = "ByteDance.CapCut"
$startMenuShortcutName = "CapCut"
$shortcutSearchPatterns = @("CapCut*.lnk")
$executableNames = @("CapCut.exe")
$executableCandidatePaths = @(
    "$env:ProgramFiles\CapCut\CapCut.exe",
    "${env:ProgramFiles(x86)}\CapCut\CapCut.exe",
    "$env:LOCALAPPDATA\CapCut\Apps\CapCut.exe",
    "$env:LOCALAPPDATA\Programs\CapCut\CapCut.exe",
    "$env:SystemDrive\Users\*\AppData\Local\CapCut\Apps\CapCut.exe",
    "$env:SystemDrive\Users\*\AppData\Local\Programs\CapCut\CapCut.exe"
)
$appDisplayNamePatterns = @()
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
        [string]$PackageId,
        [string]$Source
    )

    $listArguments = @("list", "--id", $PackageId, "--exact")
    if (-not [string]::IsNullOrWhiteSpace($Source)) {
        $listArguments += @("--source", $Source)
    }

    $output = & $WingetPath @listArguments 2>&1
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        return $false
    }

    $outputText = $output | Out-String
    return $outputText -match [regex]::Escape($PackageId)
}

function Test-ApplicationDetected {
    if (Find-InstalledExecutable -ExecutableNames $executableNames -CandidatePaths $executableCandidatePaths) {
        return $true
    }

    $appUserModelId = Get-InstalledAppUserModelId -DisplayNamePatterns $appDisplayNamePatterns
    if (-not [string]::IsNullOrWhiteSpace($appUserModelId)) {
        return $true
    }

    return $false
}

function Invoke-WingetPackageCommand {
    param(
        [string]$WingetPath,
        [string]$Action
    )

    $arguments = @($Action, "--id", $packageId, "--exact", "--source", $source, "--silent", "--accept-package-agreements", "--accept-source-agreements")
    $verb = if ($Action -eq "upgrade") { "Updating" } else { "Installing" }
    Write-Host "$verb $packageName..."

    $output = & $WingetPath @arguments 2>&1
    $exitCode = $LASTEXITCODE
    $output | ForEach-Object { Write-Host $_ }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = ($output | Out-String)
    }
}

function Test-NoUpdateAvailable {
    param([string]$Output)

    return $Output -match "No applicable update|No available upgrade|No newer package versions|No upgrade available"
}

$winget = Get-WingetPath
$wingetPackageInstalled = Test-WingetPackageInstalled -WingetPath $winget -PackageId $packageId -Source $source
$applicationDetected = $wingetPackageInstalled -or (Test-ApplicationDetected)
$action = if ($applicationDetected) { "upgrade" } else { "install" }

$result = Invoke-WingetPackageCommand -WingetPath $winget -Action $action
if ($result.ExitCode -ne 0) {
    if ($action -eq "upgrade" -and (Test-NoUpdateAvailable -Output $result.Output)) {
        Write-Host "$packageName is already up to date."
    }
    elseif ($action -eq "upgrade" -and $applicationDetected) {
        Write-Warning "$packageName update failed with exit code $($result.ExitCode). Trying install to repair or refresh the package."
        $result = Invoke-WingetPackageCommand -WingetPath $winget -Action "install"
        if ($result.ExitCode -ne 0) {
            if ($applicationDetected -or (Test-ApplicationDetected)) {
                Write-Host "$packageName is installed. Continuing to ensure Start Menu shortcut."
            }
            else {
                throw "$packageName install failed with exit code $($result.ExitCode)."
            }
        }
        else {
            Write-Host "$packageName install/repair completed successfully."
        }
    }
    elseif ($action -eq "install" -and ($applicationDetected -or (Test-ApplicationDetected))) {
        Write-Host "$packageName is installed. Continuing to ensure Start Menu shortcut."
    }
    else {
        throw "$packageName $action failed with exit code $($result.ExitCode)."
    }
}
elseif ($action -eq "upgrade") {
    Write-Host "$packageName update completed successfully."
}
else {
    Write-Host "$packageName installed successfully."
}

Ensure-StartMenuShortcut -ShortcutName $startMenuShortcutName -SearchPatterns $shortcutSearchPatterns -ExecutableNames $executableNames -CandidatePaths $executableCandidatePaths -AppDisplayNamePatterns $appDisplayNamePatterns -FallbackAppUserModelId $fallbackAppUserModelId
