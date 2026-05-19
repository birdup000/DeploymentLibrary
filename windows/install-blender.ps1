# Install Blender (Windows)
# Installs the latest Blender release via WinGet with an official MSI fallback.
$ErrorActionPreference = 'Stop'

$packageName = "Blender"
$packageId = "BlenderFoundation.Blender"
$startMenuShortcutName = "Blender"
$shortcutSearchPatterns = @("Blender*.lnk")
$executableNames = @("blender.exe")
$executableCandidatePaths = @(
    "$env:ProgramFiles\Blender Foundation\Blender *\blender.exe",
    "${env:ProgramFiles(x86)}\Blender Foundation\Blender *\blender.exe"
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

function Get-BlenderWindowsArchitecture {
    $architecture = $env:PROCESSOR_ARCHITEW6432
    if ([string]::IsNullOrWhiteSpace($architecture)) {
        $architecture = $env:PROCESSOR_ARCHITECTURE
    }

    if ($architecture -eq "ARM64") {
        return "arm64"
    }

    return "x64"
}

function Get-BlenderOfficialInstaller {
    param([string]$Architecture)

    $releaseBaseUrl = "https://download.blender.org/release"
    $releaseIndex = Invoke-WebRequest -Uri "$releaseBaseUrl/" -UseBasicParsing

    $releaseFolders = [regex]::Matches($releaseIndex.Content, 'href="(?<folder>Blender(?<version>\d+\.\d+)/)"') |
        ForEach-Object {
            [PSCustomObject]@{
                Folder = $_.Groups["folder"].Value
                Version = [version]$_.Groups["version"].Value
            }
        } |
        Sort-Object -Property Version -Descending

    foreach ($releaseFolder in $releaseFolders) {
        $folderUrl = "$releaseBaseUrl/$($releaseFolder.Folder)"
        try {
            $folderIndex = Invoke-WebRequest -Uri $folderUrl -UseBasicParsing
        }
        catch {
            Write-Warning "Could not read Blender release folder $folderUrl. $($_.Exception.Message)"
            continue
        }

        $installerPattern = 'href="(?<file>blender-(?<version>\d+\.\d+\.\d+)-windows-' + [regex]::Escape($Architecture) + '\.msi)"'
        $installers = [regex]::Matches($folderIndex.Content, $installerPattern) |
            ForEach-Object {
                $version = $_.Groups["version"].Value
                $fileName = $_.Groups["file"].Value
                [PSCustomObject]@{
                    FileName = $fileName
                    Version = [version]$version
                    InstallerUrl = "$folderUrl$fileName"
                    ChecksumUrl = "$folderUrl" + "blender-$version.sha256"
                }
            } |
            Sort-Object -Property Version -Descending

        $installer = $installers | Select-Object -First 1
        if ($installer) {
            return $installer
        }
    }

    throw "Could not find an official Blender Windows $Architecture MSI at $releaseBaseUrl."
}

function Get-BlenderOfficialChecksum {
    param(
        [string]$ChecksumUrl,
        [string]$FileName
    )

    try {
        $checksumContent = (Invoke-WebRequest -Uri $ChecksumUrl -UseBasicParsing).Content
    }
    catch {
        Write-Warning "Could not download Blender checksum file $ChecksumUrl. $($_.Exception.Message)"
        return $null
    }

    $checksumPattern = "(?im)^(?<hash>[a-f0-9]{64})\s+$([regex]::Escape($FileName))$"
    $checksumMatch = [regex]::Match($checksumContent, $checksumPattern)
    if ($checksumMatch.Success) {
        return $checksumMatch.Groups["hash"].Value.ToLowerInvariant()
    }

    Write-Warning "Could not find a SHA-256 checksum for $FileName in $ChecksumUrl."
    return $null
}

function Install-BlenderFromOfficialMsi {
    $architecture = Get-BlenderWindowsArchitecture
    $installer = Get-BlenderOfficialInstaller -Architecture $architecture
    $tempDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("BlenderInstall-" + [guid]::NewGuid().ToString())

    New-Item -Path $tempDirectory -ItemType Directory -Force | Out-Null
    try {
        $installerPath = Join-Path $tempDirectory $installer.FileName
        Write-Host "Downloading $packageName $($installer.Version) for Windows $architecture..."
        Invoke-WebRequest -Uri $installer.InstallerUrl -OutFile $installerPath -UseBasicParsing

        if (-not (Test-Path $installerPath)) {
            throw "Downloaded Blender installer was not found at $installerPath."
        }

        $expectedHash = Get-BlenderOfficialChecksum -ChecksumUrl $installer.ChecksumUrl -FileName $installer.FileName
        if (-not [string]::IsNullOrWhiteSpace($expectedHash)) {
            $actualHash = (Get-FileHash -Path $installerPath -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($actualHash -ne $expectedHash) {
                throw "Blender installer SHA-256 mismatch. Expected $expectedHash but found $actualHash."
            }
        }

        Write-Host "Installing $packageName $($installer.Version) from official MSI..."
        $msiArguments = "/i `"$installerPath`" /quiet /norestart"
        $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $msiArguments -Wait -PassThru
        if ($process.ExitCode -ne 0) {
            throw "$packageName MSI installer failed with exit code $($process.ExitCode)."
        }
    }
    finally {
        Remove-Item -Path $tempDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-WingetPackageInstall {
    param(
        [string]$WingetPath,
        [string[]]$Arguments
    )

    Write-Host "Installing $packageName..."
    & $WingetPath @Arguments 2>&1 | ForEach-Object { Write-Host $_ }
    $exitCode = $LASTEXITCODE
    if ($exitCode -eq 0) {
        return $true
    }

    if (($exitCode -eq -2147024894) -or ($exitCode -eq 2147942402)) {
        Write-Warning "$packageName install via WinGet failed with exit code $exitCode (0x80070002: file not found). Falling back to the official Blender MSI."
    }
    else {
        Write-Warning "$packageName install via WinGet failed with exit code $exitCode. Falling back to the official Blender MSI."
    }

    return $false
}

$wingetInstalled = $false
$arguments = @("install", "--id", $packageId, "--exact", "--source", $source, "--silent", "--accept-package-agreements", "--accept-source-agreements")

try {
    $winget = Get-WingetPath
    $wingetInstalled = Invoke-WingetPackageInstall -WingetPath $winget -Arguments $arguments
}
catch {
    Write-Warning "WinGet install path could not be used. $($_.Exception.Message)"
}

if (-not $wingetInstalled) {
    Install-BlenderFromOfficialMsi
}

Write-Host "$packageName installed successfully."
Ensure-StartMenuShortcut -ShortcutName $startMenuShortcutName -SearchPatterns $shortcutSearchPatterns -ExecutableNames $executableNames -CandidatePaths $executableCandidatePaths -AppDisplayNamePatterns $appDisplayNamePatterns -FallbackAppUserModelId $fallbackAppUserModelId
