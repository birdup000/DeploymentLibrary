# Update Google Chrome Enterprise (Windows)
# Reinstalls the latest Chrome Enterprise MSI and refreshes optional Chrome ADMX/ADML policy templates.
$ErrorActionPreference = 'Stop'

$packageName = "Google Chrome Enterprise"
$installerUrl = "https://dl.google.com/chrome/install/GoogleChromeStandaloneEnterprise64.msi"
$policyTemplatesUrl = "https://dl.google.com/dl/edgedl/chrome/policy/policy_templates.zip"
$installPolicyTemplates = if ($env:INSTALL_POLICY_TEMPLATES -eq "false") { $false } else { $true }
$policyTemplateLanguage = if ([string]::IsNullOrWhiteSpace($env:POLICY_TEMPLATE_LANGUAGE)) { "en-US" } else { $env:POLICY_TEMPLATE_LANGUAGE.Trim() }
$installerPath = Join-Path $env:TEMP "GoogleChromeStandaloneEnterprise64.msi"
$policyZipPath = Join-Path $env:TEMP "chrome_policy_templates.zip"
$extractPath = Join-Path $env:TEMP "chrome_policy_templates"

function Install-ChromePolicyTemplates {
    Write-Host "Downloading Chrome Enterprise policy templates..."
    Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue
    Invoke-WebRequest -Uri $policyTemplatesUrl -OutFile $policyZipPath -UseBasicParsing
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

try {
    Write-Host "Downloading latest $packageName..."
    Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing

    Write-Host "Updating $packageName..."
    $process = Start-Process msiexec.exe -ArgumentList "/i", "`"$installerPath`"", "/qn", "/norestart" -Wait -NoNewWindow -PassThru
    if ($process.ExitCode -ne 0) {
        throw "$packageName update failed with exit code $($process.ExitCode)."
    }

    if ($installPolicyTemplates) {
        Install-ChromePolicyTemplates
    }

    Write-Host "$packageName update completed successfully."
}
finally {
    Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
    Remove-Item $policyZipPath -Force -ErrorAction SilentlyContinue
    Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue
}
