# Update Google Chrome Enterprise (Windows)
# Reinstalls the latest Chrome Enterprise MSI and refreshes optional Chrome ADMX/ADML policy templates.
$ErrorActionPreference = 'Stop'

$packageName = "Google Chrome Enterprise"
$installerUrl = "https://dl.google.com/chrome/install/GoogleChromeStandaloneEnterprise64.msi"
$policyTemplatesUrl = "https://dl.google.com/dl/edgedl/chrome/policy/policy_templates.zip"
$installPolicyTemplates = if ($env:INSTALL_POLICY_TEMPLATES -eq "false") { $false } else { $true }
$policyTemplateLanguage = if ([string]::IsNullOrWhiteSpace($env:POLICY_TEMPLATE_LANGUAGE)) { "en-US" } else { $env:POLICY_TEMPLATE_LANGUAGE.Trim() }
$tempDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("ChromeEnterprise-" + [guid]::NewGuid().ToString())
$installerPath = Join-Path $tempDirectory "GoogleChromeStandaloneEnterprise64.msi"
$policyZipPath = Join-Path $tempDirectory "chrome_policy_templates.zip"
$extractPath = Join-Path $tempDirectory "chrome_policy_templates"

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
        [string]$Activity = "Download",
        [int]$RetryCount = 3
    )

    $lastError = $null
    for ($attempt = 1; $attempt -le $RetryCount; $attempt++) {
        if ($attempt -gt 1) {
            Write-Host "$Activity retry $attempt of $RetryCount..."
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
                    Write-Host "$Activity size: $(Format-ByteSize -Bytes $totalBytes)"
                }
                else {
                    Write-Host "$Activity started (total size unknown)."
                }

                while (($bytesRead = $responseStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                    $fileStream.Write($buffer, 0, $bytesRead)
                    $downloadedBytes += $bytesRead

                    $now = Get-Date
                    if ((($now - $lastReportTime).TotalSeconds -ge 5) -or (($downloadedBytes - $lastReportBytes) -ge 10485760)) {
                        if ($totalBytes -gt 0) {
                            $percent = [math]::Round(($downloadedBytes / $totalBytes) * 100, 1)
                            Write-Host "$Activity progress: $(Format-ByteSize -Bytes $downloadedBytes) / $(Format-ByteSize -Bytes $totalBytes) ($percent%)"
                        }
                        else {
                            Write-Host "$Activity progress: $(Format-ByteSize -Bytes $downloadedBytes) downloaded"
                        }

                        $lastReportTime = $now
                        $lastReportBytes = $downloadedBytes
                    }
                }

                Write-Host "$Activity complete: $(Format-ByteSize -Bytes $downloadedBytes)"
                return
            }
            finally {
                if ($fileStream) { $fileStream.Dispose() }
                if ($responseStream) { $responseStream.Dispose() }
                if ($response) { $response.Dispose() }
            }
        }
        catch {
            $lastError = $_
            Remove-Item -Path $OutFile -Force -ErrorAction SilentlyContinue
            Write-Warning "$Activity attempt $attempt failed: $($_.Exception.Message)"
        }
    }

    throw "Failed to download $Uri after $RetryCount attempts. $($lastError.Exception.Message)"
}

function Enter-DeploymentMutex {
    param(
        [System.Threading.Mutex]$Mutex,
        [string]$Activity,
        [int]$TimeoutMinutes = 45
    )

    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    while ((Get-Date) -lt $deadline) {
        if ($Mutex.WaitOne([TimeSpan]::FromSeconds(15))) {
            return $true
        }

        Write-Host "$Activity is waiting for another Chrome Enterprise deployment to finish..."
    }

    return $false
}

function Invoke-ChromeEnterpriseMsiInstall {
    param(
        [string]$InstallerPath,
        [string]$Verb = "Installing",
        [int]$MaxAttempts = 20
    )

    $successExitCodes = @(0, 3010)

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        Write-Host "$Verb $packageName (attempt $attempt of $MaxAttempts)..."
        $process = Start-Process msiexec.exe -ArgumentList "/i", "`"$InstallerPath`"", "/qn", "/norestart" -Wait -NoNewWindow -PassThru

        if ($process.ExitCode -in $successExitCodes) {
            return
        }

        if ($process.ExitCode -eq 1618) {
            Write-Host "Windows Installer is busy with another installation (exit 1618). Waiting 30 seconds..."
            Start-Sleep -Seconds 30
            continue
        }

        throw "$packageName update failed with exit code $($process.ExitCode)."
    }

    throw "$packageName update failed after $MaxAttempts attempts because Windows Installer remained busy."
}

function Install-ChromePolicyTemplates {
    Write-Host "Downloading Chrome Enterprise policy templates..."
    Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue
    Save-FileWithProgress -Uri $policyTemplatesUrl -OutFile $policyZipPath -Activity "Policy templates download"
    Expand-Archive -Path $policyZipPath -DestinationPath $extractPath -Force

    $admxSource = Join-Path $extractPath "windows\admx"
    if (-not (Test-Path $admxSource)) {
        throw "Chrome policy template archive did not contain windows\admx."
    }

    $policyDefinitionsPath = Join-Path $env:WINDIR "PolicyDefinitions"
    $languageSource = Join-Path $admxSource $policyTemplateLanguage
    if (-not (Test-Path $languageSource)) {
        Write-Host "Policy template language '$policyTemplateLanguage' not found. Falling back to en-US."
        $languageSource = Join-Path $admxSource "en-US"
    }

    $languageName = Split-Path $languageSource -Leaf
    $languageDestination = Join-Path $policyDefinitionsPath $languageName

    New-Item -Path $policyDefinitionsPath -ItemType Directory -Force | Out-Null
    New-Item -Path $languageDestination -ItemType Directory -Force | Out-Null

    Copy-Item -Path (Join-Path $admxSource "*.admx") -Destination $policyDefinitionsPath -Force
    Copy-Item -Path (Join-Path $languageSource "*.adml") -Destination $languageDestination -Force

    Write-Host "Chrome Enterprise policy templates refreshed in $policyDefinitionsPath."
}

$deploymentMutex = $null
$deploymentMutexAcquired = $false

try {
    $deploymentMutex = New-Object System.Threading.Mutex($false, "Global\DeploymentLibrary-ChromeEnterprise-Install")
    Write-Host "Waiting for any other Chrome Enterprise deployment to finish..."
    $deploymentMutexAcquired = Enter-DeploymentMutex -Mutex $deploymentMutex -Activity "Chrome Enterprise update"
    if (-not $deploymentMutexAcquired) {
        throw "Timed out waiting for another Chrome Enterprise deployment to finish."
    }

    New-Item -Path $tempDirectory -ItemType Directory -Force | Out-Null

    Write-Host "Downloading latest $packageName..."
    Save-FileWithProgress -Uri $installerUrl -OutFile $installerPath -Activity "Chrome Enterprise MSI download"

    Invoke-ChromeEnterpriseMsiInstall -InstallerPath $installerPath -Verb "Updating"

    if ($installPolicyTemplates) {
        Install-ChromePolicyTemplates
    }

    Write-Host "$packageName update completed successfully."
}
finally {
    if ($deploymentMutexAcquired) {
        $deploymentMutex.ReleaseMutex() | Out-Null
    }

    if ($deploymentMutex) {
        $deploymentMutex.Dispose()
    }

    Remove-Item $tempDirectory -Recurse -Force -ErrorAction SilentlyContinue
}
