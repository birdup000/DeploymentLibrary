# Install Blender (Windows)
# Installs or updates the latest Blender release via WinGet with an official MSI fallback.
$ErrorActionPreference = 'Stop'

$packageName = "Blender"
$packageId = "BlenderFoundation.Blender"
$startMenuShortcutName = "Blender"
$startMenuProgramsSubfolder = "Blender Foundation"
$shortcutSearchPatterns = @("Blender*.lnk")
$executableNames = @("blender.exe")
$executableCandidatePaths = @(
    "$env:ProgramFiles\Blender Foundation\Blender *\blender.exe",
    "${env:ProgramFiles(x86)}\Blender Foundation\Blender *\blender.exe"
)
$appDisplayNamePatterns = @("Blender*")
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
        [string]$IconLocation = "",
        [string]$ProgramsSubfolder = ""
    )

    $programsDirectory = Get-CommonProgramsDirectory
    if (-not [string]::IsNullOrWhiteSpace($ProgramsSubfolder)) {
        $programsDirectory = Join-Path $programsDirectory $ProgramsSubfolder
    }

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

function Get-BlenderInstallDirectory {
    $registryRoots = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    $bestMatch = $null
    foreach ($registryRoot in $registryRoots) {
        $entries = Get-ChildItem -Path $registryRoot -ErrorAction SilentlyContinue
        foreach ($entry in $entries) {
            $properties = Get-ItemProperty -Path $entry.PSPath -ErrorAction SilentlyContinue
            if (-not $properties -or [string]::IsNullOrWhiteSpace($properties.DisplayName) -or $properties.DisplayName -notlike "Blender*") {
                continue
            }

            $installLocation = ($properties.InstallLocation -as [string])
            if ([string]::IsNullOrWhiteSpace($installLocation)) {
                continue
            }

            $installLocation = [Environment]::ExpandEnvironmentVariables($installLocation.Trim().TrimEnd('\'))
            if (-not (Test-Path $installLocation)) {
                continue
            }

            if (-not $bestMatch -or $properties.DisplayName.Length -gt $bestMatch.DisplayName.Length) {
                $bestMatch = [PSCustomObject]@{
                    DisplayName = $properties.DisplayName
                    InstallLocation = $installLocation
                }
            }
        }
    }

    if ($bestMatch) {
        return $bestMatch.InstallLocation
    }

    return $null
}

function Get-BlenderExecutableCandidatePaths {
    $candidatePaths = [System.Collections.Generic.List[string]]::new()
    foreach ($path in @($executableCandidatePaths)) {
        if (-not [string]::IsNullOrWhiteSpace($path)) {
            [void]$candidatePaths.Add($path)
        }
    }

    $installDirectory = Get-BlenderInstallDirectory
    if ($installDirectory) {
        [void]$candidatePaths.Add((Join-Path $installDirectory "blender.exe"))
    }

    return $candidatePaths | Select-Object -Unique
}

function Test-ApplicationDetected {
    $candidatePaths = Get-BlenderExecutableCandidatePaths
    if (Find-InstalledExecutable -ExecutableNames $executableNames -CandidatePaths $candidatePaths) {
        return $true
    }

    $appUserModelId = Get-InstalledAppUserModelId -DisplayNamePatterns $appDisplayNamePatterns
    return -not [string]::IsNullOrWhiteSpace($appUserModelId)
}

function New-DesktopShortcut {
    param(
        [string]$ShortcutName,
        [string]$TargetPath,
        [string]$IconLocation = ""
    )

    $desktopDirectory = [Environment]::GetFolderPath("CommonDesktopDirectory")
    if ([string]::IsNullOrWhiteSpace($desktopDirectory)) {
        $desktopDirectory = Join-Path $env:PUBLIC "Desktop"
    }

    New-Item -Path $desktopDirectory -ItemType Directory -Force | Out-Null

    $shortcutPath = Join-Path $desktopDirectory "$ShortcutName.lnk"
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $TargetPath
    $shortcut.Description = "Open $ShortcutName"
    $shortcut.WorkingDirectory = Split-Path $TargetPath -Parent
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
        [string]$FallbackAppUserModelId = "",
        [string]$ProgramsSubfolder = ""
    )

    $shortcutPath = Copy-ExistingStartMenuShortcut -ShortcutName $ShortcutName -SearchPatterns $SearchPatterns
    if ($shortcutPath) {
        Write-Host "Start Menu shortcut available: $shortcutPath"
        return $true
    }

    $targetPath = Find-InstalledExecutable -ExecutableNames $ExecutableNames -CandidatePaths $CandidatePaths
    if ($targetPath) {
        $shortcutPath = New-StartMenuShortcut -ShortcutName $ShortcutName -TargetPath $targetPath -ProgramsSubfolder $ProgramsSubfolder
        Write-Host "Created Start Menu shortcut: $shortcutPath"
        return $true
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
            -IconLocation "$env:WINDIR\System32\shell32.dll,220" `
            -ProgramsSubfolder $ProgramsSubfolder
        Write-Host "Created Start Menu shortcut: $shortcutPath"
        return $true
    }

    Write-Warning "Could not create a Start Menu shortcut for $ShortcutName because no installed executable or app identifier was found."
    return $false
}

function Ensure-DesktopShortcut {
    param(
        [string]$ShortcutName,
        [string[]]$ExecutableNames = @(),
        [string[]]$CandidatePaths = @()
    )

    $desktopDirectory = [Environment]::GetFolderPath("CommonDesktopDirectory")
    if ([string]::IsNullOrWhiteSpace($desktopDirectory)) {
        $desktopDirectory = Join-Path $env:PUBLIC "Desktop"
    }

    $shortcutPath = Join-Path $desktopDirectory "$ShortcutName.lnk"
    if (Test-Path $shortcutPath) {
        Write-Host "Desktop shortcut available: $shortcutPath"
        return $true
    }

    $targetPath = Find-InstalledExecutable -ExecutableNames $ExecutableNames -CandidatePaths $CandidatePaths
    if (-not $targetPath) {
        Write-Warning "Could not create a Desktop shortcut for $ShortcutName because blender.exe was not found."
        return $false
    }

    $shortcutPath = New-DesktopShortcut -ShortcutName $ShortcutName -TargetPath $targetPath
    Write-Host "Created Desktop shortcut: $shortcutPath"
    return $true
}

function Ensure-ApplicationShortcuts {
    $shortcutReady = $false
    for ($attempt = 1; $attempt -le 6; $attempt++) {
        if ($attempt -gt 1) {
            Write-Host "Waiting for Blender files to become available (attempt $attempt of 6)..."
            Start-Sleep -Seconds 5
        }

        $candidatePaths = Get-BlenderExecutableCandidatePaths
        $startMenuReady = Ensure-StartMenuShortcut `
            -ShortcutName $startMenuShortcutName `
            -SearchPatterns $shortcutSearchPatterns `
            -ExecutableNames $executableNames `
            -CandidatePaths $candidatePaths `
            -AppDisplayNamePatterns $appDisplayNamePatterns `
            -FallbackAppUserModelId $fallbackAppUserModelId `
            -ProgramsSubfolder $startMenuProgramsSubfolder
        $desktopReady = Ensure-DesktopShortcut `
            -ShortcutName $startMenuShortcutName `
            -ExecutableNames $executableNames `
            -CandidatePaths $candidatePaths

        if ($startMenuReady) {
            $shortcutReady = $true
            if (-not $desktopReady) {
                Write-Warning "Blender is available in the Start Menu apps list, but a Desktop shortcut could not be created."
            }

            break
        }
    }

    if (-not $shortcutReady) {
        throw "Blender was installed but a Start Menu shortcut could not be created."
    }
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

function Format-ByteSize {
    param([long]$Bytes)

    if ($Bytes -ge 1GB) {
        return "{0:N1} GB" -f ($Bytes / 1GB)
    }

    if ($Bytes -ge 1MB) {
        return "{0:N1} MB" -f ($Bytes / 1MB)
    }

    if ($Bytes -ge 1KB) {
        return "{0:N1} KB" -f ($Bytes / 1KB)
    }

    return "$Bytes bytes"
}

function Save-FileWithProgress {
    param(
        [string]$Uri,
        [string]$OutFile,
        [int]$RetryCount = 3
    )

    $lastError = $null
    for ($attempt = 1; $attempt -le $RetryCount; $attempt++) {
        if ($attempt -gt 1) {
            Write-Host "Retrying download (attempt $attempt of $RetryCount)..."
            Start-Sleep -Seconds 5
        }

        try {
            $request = [System.Net.HttpWebRequest]::Create($Uri)
            $request.UserAgent = "XTS DeploymentLibrary"
            $request.AllowAutoRedirect = $true
            $request.Timeout = 30000
            $request.ReadWriteTimeout = 30000

            $response = $request.GetResponse()
            $responseStream = $response.GetResponseStream()
            $fileStream = [System.IO.File]::Create($OutFile)

            try {
                $buffer = New-Object byte[] 1048576
                $totalBytes = [long]$response.ContentLength
                $downloadedBytes = [long]0
                $lastReportTime = Get-Date
                $lastReportBytes = [long]0

                if ($totalBytes -gt 0) {
                    Write-Host "Download size: $(Format-ByteSize -Bytes $totalBytes)"
                }

                while (($bytesRead = $responseStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                    $fileStream.Write($buffer, 0, $bytesRead)
                    $downloadedBytes += $bytesRead

                    $now = Get-Date
                    if ((($now - $lastReportTime).TotalSeconds -ge 10) -or (($downloadedBytes - $lastReportBytes) -ge 52428800)) {
                        if ($totalBytes -gt 0) {
                            $percent = [math]::Round(($downloadedBytes / $totalBytes) * 100, 1)
                            Write-Host "Downloaded $(Format-ByteSize -Bytes $downloadedBytes) of $(Format-ByteSize -Bytes $totalBytes) ($percent%)."
                        }
                        else {
                            Write-Host "Downloaded $(Format-ByteSize -Bytes $downloadedBytes)."
                        }

                        $lastReportTime = $now
                        $lastReportBytes = $downloadedBytes
                    }
                }

                Write-Host "Downloaded $(Format-ByteSize -Bytes $downloadedBytes)."
                return
            }
            finally {
                if ($fileStream) {
                    $fileStream.Dispose()
                }

                if ($responseStream) {
                    $responseStream.Dispose()
                }

                if ($response) {
                    $response.Dispose()
                }
            }
        }
        catch {
            $lastError = $_
            Remove-Item -Path $OutFile -Force -ErrorAction SilentlyContinue
            Write-Warning "Download attempt $attempt failed. $($_.Exception.Message)"
        }
    }

    throw "Failed to download $Uri after $RetryCount attempts. $($lastError.Exception.Message)"
}

function Install-BlenderFromOfficialMsi {
    $architecture = Get-BlenderWindowsArchitecture
    $installer = Get-BlenderOfficialInstaller -Architecture $architecture
    $tempDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("BlenderInstall-" + [guid]::NewGuid().ToString())

    New-Item -Path $tempDirectory -ItemType Directory -Force | Out-Null
    try {
        $installerPath = Join-Path $tempDirectory $installer.FileName
        Write-Host "Downloading $packageName $($installer.Version) for Windows $architecture..."
        Save-FileWithProgress -Uri $installer.InstallerUrl -OutFile $installerPath

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
        $msiArguments = "/i `"$installerPath`" ALLUSERS=1 /qn /norestart"
        $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $msiArguments -Wait -PassThru
        if ($process.ExitCode -ne 0) {
            throw "$packageName MSI installer failed with exit code $($process.ExitCode)."
        }
    }
    finally {
        Remove-Item -Path $tempDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
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

function Test-NoUpdateAvailable {
    param([string]$Output)

    return $Output -match "No applicable update|No available upgrade|No newer package versions|No upgrade available"
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

    if ($exitCode -eq 0) {
        return $true
    }

    if ($Action -eq "upgrade" -and (Test-NoUpdateAvailable -Output ($output | Out-String))) {
        Write-Host "$packageName is already up to date."
        return $true
    }

    if (($exitCode -eq -2147024894) -or ($exitCode -eq 2147942402)) {
        Write-Warning "$packageName $Action via WinGet failed with exit code $exitCode (0x80070002: file not found). Falling back to the official Blender MSI."
    }
    else {
        Write-Warning "$packageName $Action via WinGet failed with exit code $exitCode. Falling back to the official Blender MSI."
    }

    return $false
}

$wingetActionSucceeded = $false

try {
    $winget = Get-WingetPath
    $wingetPackageInstalled = Test-WingetPackageInstalled -WingetPath $winget -PackageId $packageId -Source $source
    $applicationDetected = $wingetPackageInstalled -or (Test-ApplicationDetected)
    $action = if ($applicationDetected) { "upgrade" } else { "install" }
    $wingetActionSucceeded = Invoke-WingetPackageCommand -WingetPath $winget -Action $action
}
catch {
    Write-Warning "WinGet install/update path could not be used. $($_.Exception.Message)"
}

if (-not $wingetActionSucceeded) {
    Install-BlenderFromOfficialMsi
}
elseif (-not (Test-ApplicationDetected)) {
    Write-Warning "WinGet reported success but Blender was not detected on disk. Running the official MSI to repair the installation."
    Install-BlenderFromOfficialMsi
}

Write-Host "$packageName install/update completed successfully."
Ensure-ApplicationShortcuts
