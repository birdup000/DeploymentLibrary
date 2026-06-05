# Install Windows Sound Recorder (Windows)
# Installs or repairs the Windows 11 Sound Recorder inbox app without relying on the WinGet msstore source.
$ErrorActionPreference = 'Stop'

$packageName = "Windows Sound Recorder"
$appxPackageName = "Microsoft.WindowsSoundRecorder"
$packageFamilyName = "Microsoft.WindowsSoundRecorder_8wekyb3d8bbwe"
$storeProductId = "9WZDNCRFHWKN"
$displayCatalogUrl = "https://displaycatalog.mp.microsoft.com/v7.0/products/lookup?alternateId=PackageFamilyName&Value=$packageFamilyName&market=US&languages=en-US&fieldsTemplate=Details"
$startMenuShortcutName = "Windows Sound Recorder"
$shortcutSearchPatterns = @("Windows Sound Recorder*.lnk", "Sound Recorder*.lnk", "Voice Recorder*.lnk")
$executableNames = @()
$executableCandidatePaths = @()
$appDisplayNamePatterns = @("*Windows Sound Recorder*", "*Sound Recorder*", "*Voice Recorder*")
$fallbackAppUserModelId = "Microsoft.WindowsSoundRecorder_8wekyb3d8bbwe!App"

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

function Test-RunningAsSystem {
    return [System.Security.Principal.WindowsIdentity]::GetCurrent().IsSystem
}

function Test-SoundRecorderInstalled {
    $installedPackages = @(Get-AppxPackage -Name $appxPackageName -AllUsers -ErrorAction SilentlyContinue)
    if ($installedPackages.Count -gt 0) {
        return $true
    }

    if (Find-InstalledExecutable -ExecutableNames $executableNames -CandidatePaths $executableCandidatePaths) {
        return $true
    }

    $appUserModelId = Get-InstalledAppUserModelId -DisplayNamePatterns $appDisplayNamePatterns
    return -not [string]::IsNullOrWhiteSpace($appUserModelId)
}

function Test-SoundRecorderProvisioned {
    $provisionedPackage = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -eq $appxPackageName } |
        Select-Object -First 1

    return $null -ne $provisionedPackage
}

function Get-SoundRecorderWindowsAppsDirectory {
    $windowsAppsRoot = Join-Path $env:ProgramFiles "WindowsApps"
    if (-not (Test-Path -LiteralPath $windowsAppsRoot)) {
        return $null
    }

    return Get-ChildItem -Path $windowsAppsRoot -Directory -Filter "$appxPackageName_*" -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending |
        Select-Object -First 1
}

function Register-SoundRecorderManifest {
    param([string]$ManifestPath)

    if (Test-RunningAsSystem) {
        Write-Host "Skipping Add-AppxPackage -Register because deployment is running as SYSTEM."
        return $false
    }

    if (-not (Test-Path -LiteralPath $ManifestPath)) {
        return $false
    }

    Add-AppxPackage -Register -DisableDevelopmentMode -Path $ManifestPath -ErrorAction Stop | Out-Null
    return $true
}

function Provision-SoundRecorderPackage {
    param(
        [string]$BundlePath,
        [string[]]$DependencyPaths = @()
    )

    if (-not (Test-Path -LiteralPath $BundlePath)) {
        return $false
    }

    Write-Host "Provisioning $packageName for all users from $BundlePath..."
    if ($DependencyPaths.Count -gt 0) {
        Add-AppxProvisionedPackage -Online -PackagePath $BundlePath -DependencyPackagePath $DependencyPaths -SkipLicense -Regions All -ErrorAction Stop | Out-Null
    }
    else {
        Add-AppxProvisionedPackage -Online -PackagePath $BundlePath -SkipLicense -Regions All -ErrorAction Stop | Out-Null
    }

    return $true
}

function Repair-SoundRecorderRegistration {
    if (Test-RunningAsSystem) {
        if (Test-SoundRecorderInstalled -or Test-SoundRecorderProvisioned) {
            Write-Host "$packageName is already available. Skipping user-context re-registration while running as SYSTEM."
            return $true
        }

        return $false
    }

    $repaired = $false
    $installedPackages = @(Get-AppxPackage -Name $appxPackageName -AllUsers -ErrorAction SilentlyContinue)

    foreach ($installedPackage in $installedPackages) {
        if ([string]::IsNullOrWhiteSpace($installedPackage.InstallLocation)) {
            continue
        }

        $manifestPath = Join-Path $installedPackage.InstallLocation "AppxManifest.xml"
        if (-not (Test-Path -LiteralPath $manifestPath)) {
            continue
        }

        Write-Host "Re-registering $packageName for package $($installedPackage.PackageFullName)..."
        if (Register-SoundRecorderManifest -ManifestPath $manifestPath) {
            $repaired = $true
        }
    }

    return $repaired
}

function Install-SoundRecorderFromWindowsApps {
    if (Test-SoundRecorderProvisioned) {
        Write-Host "$packageName is already provisioned for all users."
        return $true
    }

    $packageDirectory = Get-SoundRecorderWindowsAppsDirectory
    if (-not $packageDirectory) {
        return $false
    }

    if (Test-RunningAsSystem) {
        Write-Host "Sound Recorder package files are present, but SYSTEM cannot perform user-context registration from $($packageDirectory.FullName)."
        return $false
    }

    $manifestPath = Join-Path $packageDirectory.FullName "AppxManifest.xml"
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        return $false
    }

    Write-Host "Registering $packageName from $($packageDirectory.FullName)..."
    return Register-SoundRecorderManifest -ManifestPath $manifestPath
}

function Install-SoundRecorderFromProvisionedPackage {
    $provisionedPackage = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -eq $appxPackageName } |
        Select-Object -First 1

    if (-not $provisionedPackage) {
        return $false
    }

    Write-Host "$packageName is provisioned for all users as $($provisionedPackage.PackageName)."
    return $true
}

function Get-WindowsStorePackageVersion {
    param([string]$VersionString)

    if ([string]::IsNullOrWhiteSpace($VersionString)) {
        return [version]"0.0.0.0"
    }

    $normalizedVersion = $VersionString
    if ($normalizedVersion -match '^(\d{4})\.(\d+)') {
        $year = [int]$Matches[1]
        if ($year -ge 2000 -and $year -le 2099) {
            $normalizedVersion = "11.$($Matches[2]).0.0"
        }
    }

    try {
        return [version]$normalizedVersion
    }
    catch {
        return [version]"0.0.0.0"
    }
}

function Get-LatestSoundRecorderCatalogPackage {
    $catalogResponse = Invoke-RestMethod -Uri $displayCatalogUrl -Method Get -ErrorAction Stop
    $catalogPackages = @()

    foreach ($product in @($catalogResponse.Products)) {
        foreach ($skuAvailability in @($product.DisplaySkuAvailabilities)) {
            foreach ($availability in @($skuAvailability.Availabilities)) {
                foreach ($package in @($availability.Packages)) {
                    if ($package.PackageFamilyName -ne $packageFamilyName) {
                        continue
                    }

                    if ($package.PackageFormat -notin @("MsixBundle", "AppxBundle", "EAppxBundle")) {
                        continue
                    }

                    $catalogPackages += [PSCustomObject]@{
                        PackageFullName = $package.PackageFullName
                        PackageFormat = $package.PackageFormat
                        ContentId = $package.ContentId
                        Version = Get-WindowsStorePackageVersion -VersionString (($package.PackageFullName -split '_')[1])
                    }
                }
            }
        }
    }

    return $catalogPackages |
        Sort-Object -Property Version -Descending |
        Select-Object -First 1
}

function Get-StoreDownloadLinks {
    param([string]$ProductId)

    $userAgent = [Microsoft.PowerShell.Commands.PSUserAgent]::Chrome
    $apiUrl = "https://store.rg-adguard.net/api/GetFiles"
    $requestType = if ($ProductId -like "*_*") { "PackageFamilyName" } else { "ProductId" }
    $body = @{
        type = $requestType
        url = $ProductId
        ring = "Retail"
        lang = "en-US"
    }

    if (-not $script:StoreDownloadWebSession) {
        $apiHost = ([uri]$apiUrl).GetLeftPart([System.UriPartial]::Authority)
        Invoke-WebRequest -Uri $apiHost -UserAgent $userAgent -SessionVariable storeDownloadWebSession -UseBasicParsing | Out-Null
        $script:StoreDownloadWebSession = $storeDownloadWebSession
    }

    $response = Invoke-WebRequest -Method Post -Uri $apiUrl -ContentType "application/x-www-form-urlencoded" -Body $body -UserAgent $userAgent -WebSession $script:StoreDownloadWebSession -UseBasicParsing
    $matches = [regex]::Matches($response.Content, '<a href="(?<url>[^"]+)">(?<name>[^<]+\.(?:msix|msixbundle|appx|appxbundle))</a>', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

    $links = @()
    foreach ($match in $matches) {
        $links += [PSCustomObject]@{
            Url = $match.Groups["url"].Value
            Name = $match.Groups["name"].Value
        }
    }

    return $links
}

function Get-SoundRecorderStoreDownloadLinks {
    param([System.Object[]]$DownloadLinks)

    $architecture = switch ($env:PROCESSOR_ARCHITECTURE) {
        "AMD64" { "x64" }
        "ARM64" { "arm64" }
        default { $env:PROCESSOR_ARCHITECTURE.ToLowerInvariant() }
    }

    $selectedLinks = [System.Collections.Generic.List[object]]::new()

    $dependencyGroups = $DownloadLinks |
        Where-Object { $_.Name -notlike "$appxPackageName*" } |
        Group-Object -Property { ($_.Name -split '_')[0] }

    foreach ($dependencyGroup in $dependencyGroups) {
        $dependencyMatch = $dependencyGroup.Group |
            Where-Object { $_.Name -like "*_$architecture*" -or $_.Name -like "*_neutral_*" } |
            Sort-Object -Property Name -Descending |
            Select-Object -First 1
        if ($dependencyMatch) {
            [void]$selectedLinks.Add($dependencyMatch)
        }
    }

    $mainBundle = $DownloadLinks |
        Where-Object { $_.Name -like "$appxPackageName*" -and $_.Name -like "*$architecture*" -and $_.Name -like "*.msixbundle" } |
        Select-Object -First 1
    if (-not $mainBundle) {
        $mainBundle = $DownloadLinks |
            Where-Object { $_.Name -like "$appxPackageName*" -and $_.Name -like "*_neutral_*" -and $_.Name -like "*.msixbundle" } |
            Select-Object -First 1
    }
    if (-not $mainBundle) {
        $mainBundle = $DownloadLinks |
            Where-Object { $_.Name -like "$appxPackageName*" -and $_.Name -like "*.msixbundle" } |
            Select-Object -First 1
    }

    if ($mainBundle) {
        [void]$selectedLinks.Add($mainBundle)
    }

    return $selectedLinks.ToArray()
}

function Save-StorePackageFile {
    param(
        [string]$Url,
        [string]$DestinationDirectory
    )

    $fileName = Split-Path $Url -Leaf
    if ([string]::IsNullOrWhiteSpace($fileName)) {
        $fileName = "WindowsSoundRecorder.msixbundle"
    }

    $destinationPath = Join-Path $DestinationDirectory $fileName
    Invoke-WebRequest -Uri $Url -OutFile $destinationPath -UseBasicParsing
    return $destinationPath
}

function Install-SoundRecorderPackageFiles {
    param([string[]]$PackagePaths)

    $bundlePath = $PackagePaths |
        Where-Object { $_ -match '\.(msixbundle|appxbundle)$' } |
        Select-Object -First 1

    if (-not $bundlePath) {
        throw "No Sound Recorder app bundle was downloaded."
    }

    $dependencyPaths = $PackagePaths |
        Where-Object { $_ -ne $bundlePath -and $_ -match '\.(msix|appx)$' }

    Provision-SoundRecorderPackage -BundlePath $bundlePath -DependencyPaths @($dependencyPaths) | Out-Null

    if (-not (Test-RunningAsSystem)) {
        Write-Host "Registering $packageName for the current user..."
        Add-AppxPackage -Path $bundlePath -ErrorAction Stop | Out-Null
    }
    else {
        Write-Host "Provisioned $packageName for all users. Existing users receive it automatically; new users get it on first sign-in."
    }
}

function Install-SoundRecorderFromStoreDownload {
    $catalogPackage = Get-LatestSoundRecorderCatalogPackage
    if ($catalogPackage) {
        Write-Host "Latest Windows 11 Sound Recorder package from Microsoft catalog: $($catalogPackage.PackageFullName)"
    }

    $downloadLinks = @(Get-StoreDownloadLinks -ProductId $storeProductId)
    if ($downloadLinks.Count -eq 0) {
        $downloadLinks = @(Get-StoreDownloadLinks -ProductId $packageFamilyName)
    }

    $preferredLinks = @(Get-SoundRecorderStoreDownloadLinks -DownloadLinks $downloadLinks)
    if ($preferredLinks.Count -eq 0) {
        throw "Could not resolve a Microsoft Store download link for $packageName."
    }

    $tempDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("SoundRecorderInstall-" + [guid]::NewGuid().ToString())
    New-Item -Path $tempDirectory -ItemType Directory -Force | Out-Null

    try {
        $downloadedPaths = @()
        foreach ($link in $preferredLinks) {
            Write-Host "Downloading $($link.Name)..."
            $downloadedPaths += Save-StorePackageFile -Url $link.Url -DestinationDirectory $tempDirectory
        }

        Install-SoundRecorderPackageFiles -PackagePaths $downloadedPaths
        return $true
    }
    finally {
        Remove-Item -Path $tempDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Test-SoundRecorderReady {
    return (Test-SoundRecorderInstalled -or Test-SoundRecorderProvisioned)
}

function Install-SoundRecorderApp {
    if (Test-SoundRecorderReady) {
        if (Repair-SoundRecorderRegistration) {
            Write-Host "$packageName install/repair completed successfully."
            return
        }
    }

    $installActions = @(
        { Install-SoundRecorderFromProvisionedPackage },
        { Install-SoundRecorderFromStoreDownload },
        { Repair-SoundRecorderRegistration },
        { Install-SoundRecorderFromWindowsApps }
    )

    foreach ($installAction in $installActions) {
        try {
            if (& $installAction) {
                if (Test-SoundRecorderReady) {
                    Write-Host "$packageName install/repair completed successfully."
                    return
                }
            }
        }
        catch {
            Write-Warning "$packageName install step failed. $($_.Exception.Message)"
        }
    }

    throw "$packageName could not be installed or repaired. Ensure Microsoft Store endpoints are reachable or restore the inbox app from the Windows image."
}

Install-SoundRecorderApp
Ensure-StartMenuShortcut -ShortcutName $startMenuShortcutName -SearchPatterns $shortcutSearchPatterns -ExecutableNames $executableNames -CandidatePaths $executableCandidatePaths -AppDisplayNamePatterns $appDisplayNamePatterns -FallbackAppUserModelId $fallbackAppUserModelId
