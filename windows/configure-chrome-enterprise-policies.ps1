# Configure Google Chrome Enterprise Policies (Windows)
# Manages machine-level Chrome Enterprise policy registry settings.
$ErrorActionPreference = 'Stop'

$chromePolicyPath = "HKLM:\SOFTWARE\Policies\Google\Chrome"
$googleUpdatePolicyPath = "HKLM:\SOFTWARE\Policies\Google\Update"

function Ensure-RegistryKey {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
}

function ConvertTo-PolicyHashtable {
    param([Parameter(ValueFromPipeline = $true)]$InputObject)

    if ($null -eq $InputObject) {
        return $null
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        $hashtable = @{}
        foreach ($key in $InputObject.Keys) {
            $hashtable[$key] = ConvertTo-PolicyHashtable $InputObject[$key]
        }
        return $hashtable
    }

    if ($InputObject -is [pscustomobject]) {
        $hashtable = @{}
        foreach ($property in $InputObject.PSObject.Properties) {
            $hashtable[$property.Name] = ConvertTo-PolicyHashtable $property.Value
        }
        return $hashtable
    }

    if ($InputObject -is [System.Array]) {
        return ,@($InputObject | ForEach-Object { ConvertTo-PolicyHashtable $_ })
    }

    return $InputObject
}

function Get-RegistryPropertyType {
    param(
        [object]$Value,
        [string]$ExplicitType
    )

    if (-not [string]::IsNullOrWhiteSpace($ExplicitType)) {
        switch ($ExplicitType.ToLowerInvariant()) {
            "string" { return "String" }
            "expandstring" { return "ExpandString" }
            "dword" { return "DWord" }
            "qword" { return "QWord" }
            "multistring" { return "MultiString" }
            default { throw "Unsupported registry value type '$ExplicitType'." }
        }
    }

    if ($Value -is [bool]) {
        return "DWord"
    }

    if ($Value -is [byte] -or $Value -is [int16] -or $Value -is [int32]) {
        return "DWord"
    }

    if ($Value -is [int64]) {
        if ($Value -ge [int32]::MinValue -and $Value -le [int32]::MaxValue) {
            return "DWord"
        }

        return "QWord"
    }

    return "String"
}

function Convert-RegistryValue {
    param(
        [object]$Value,
        [string]$PropertyType
    )

    switch ($PropertyType) {
        "DWord" {
            if ($Value -is [bool]) {
                return [int]$Value
            }

            return [int]$Value
        }
        "QWord" {
            return [long]$Value
        }
        "MultiString" {
            if ($Value -is [System.Array]) {
                return [string[]]$Value
            }

            return [string[]]@([string]$Value)
        }
        default {
            if ($Value -is [string]) {
                return $Value
            }

            return ($Value | ConvertTo-Json -Compress -Depth 20)
        }
    }
}

function Remove-PolicyValue {
    param(
        [string]$BasePath,
        [string]$Name
    )

    Ensure-RegistryKey -Path $BasePath

    Remove-ItemProperty -Path $BasePath -Name $Name -ErrorAction SilentlyContinue

    $childKeyPath = Join-Path $BasePath $Name
    if (Test-Path $childKeyPath) {
        Remove-Item -Path $childKeyPath -Recurse -Force
    }
}

function Set-PolicyList {
    param(
        [string]$BasePath,
        [string]$Name,
        [array]$Values
    )

    Remove-PolicyValue -BasePath $BasePath -Name $Name

    $listPath = Join-Path $BasePath $Name
    Ensure-RegistryKey -Path $listPath

    $index = 1
    foreach ($value in $Values) {
        $propertyType = Get-RegistryPropertyType -Value $value
        $registryValue = Convert-RegistryValue -Value $value -PropertyType $propertyType
        New-ItemProperty -Path $listPath -Name ([string]$index) -Value $registryValue -PropertyType $propertyType -Force | Out-Null
        $index++
    }

    Write-Host "Set list policy $Name with $($Values.Count) value(s)."
}

function Test-RegistrySubKeyPolicyMapValue {
    param([object]$Value)

    if ($null -eq $Value) {
        return $true
    }

    if ($Value -is [System.Collections.IDictionary] -and $Value.ContainsKey("value")) {
        return $true
    }

    if ($Value -is [string] -or $Value -is [bool] -or $Value -is [byte] -or $Value -is [int16] -or $Value -is [int32] -or $Value -is [int64]) {
        return $true
    }

    if ($Value -is [System.Array]) {
        foreach ($item in $Value) {
            if ($item -isnot [string]) {
                return $false
            }
        }

        return $true
    }

    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($entry in $Value.GetEnumerator()) {
            if (-not (Test-RegistrySubKeyPolicyMapValue -Value $entry.Value)) {
                return $false
            }
        }

        return $true
    }

    return $false
}

function Set-PolicySubKeyMap {
    param(
        [string]$BasePath,
        [string]$Name,
        [System.Collections.IDictionary]$Map
    )

    Remove-PolicyValue -BasePath $BasePath -Name $Name

    $childPath = Join-Path $BasePath $Name
    Ensure-RegistryKey -Path $childPath

    foreach ($entry in $Map.GetEnumerator()) {
        Set-PolicyValue -BasePath $childPath -Name $entry.Key -Value $entry.Value
    }

    Write-Host "Set policy tree $Name."
}

function Set-PolicyValue {
    param(
        [string]$BasePath,
        [string]$Name,
        [object]$Value,
        [string]$ExplicitType
    )

    Ensure-RegistryKey -Path $BasePath

    if ($null -eq $Value) {
        Remove-PolicyValue -BasePath $BasePath -Name $Name
        Write-Host "Removed policy $Name."
        return
    }

    if ($Value -is [System.Array]) {
        if ($Value.Count -eq 0) {
            Remove-PolicyValue -BasePath $BasePath -Name $Name
            Write-Host "Cleared list policy $Name."
            return
        }

        $containsOnlyStrings = $true
        foreach ($item in $Value) {
            if ($item -isnot [string]) {
                $containsOnlyStrings = $false
                break
            }
        }

        if ($containsOnlyStrings) {
            Set-PolicyList -BasePath $BasePath -Name $Name -Values $Value
            return
        }

        Remove-PolicyValue -BasePath $BasePath -Name $Name
        $jsonValue = $Value | ConvertTo-Json -Compress -Depth 20
        New-ItemProperty -Path $BasePath -Name $Name -Value $jsonValue -PropertyType String -Force | Out-Null
        Write-Host "Set policy $Name."
        return
    }

    if ($Value -is [System.Collections.IDictionary] -and $Value.ContainsKey("value")) {
        $valueType = if ($Value.ContainsKey("type")) { [string]$Value["type"] } else { $ExplicitType }
        Set-PolicyValue -BasePath $BasePath -Name $Name -Value $Value["value"] -ExplicitType $valueType
        return
    }

    if ($Value -is [System.Collections.IDictionary]) {
        if (Test-RegistrySubKeyPolicyMapValue -Value $Value) {
            Set-PolicySubKeyMap -BasePath $BasePath -Name $Name -Map $Value
            return
        }

        $Value = $Value | ConvertTo-Json -Compress -Depth 20
        $ExplicitType = "String"
    }

    Remove-PolicyValue -BasePath $BasePath -Name $Name

    $propertyType = Get-RegistryPropertyType -Value $Value -ExplicitType $ExplicitType
    $registryValue = Convert-RegistryValue -Value $Value -PropertyType $propertyType
    New-ItemProperty -Path $BasePath -Name $Name -Value $registryValue -PropertyType $propertyType -Force | Out-Null

    Write-Host "Set policy $Name."
}

function Set-PolicyObject {
    param(
        [string]$BasePath,
        [string]$Json
    )

    if ([string]::IsNullOrWhiteSpace($Json)) {
        return
    }

    try {
        $parsedPolicies = ConvertFrom-Json -InputObject $Json
    }
    catch {
        throw "Invalid policy JSON: $($_.Exception.Message)"
    }

    $policies = ConvertTo-PolicyHashtable $parsedPolicies
    foreach ($policyName in $policies.Keys) {
        Set-PolicyValue -BasePath $BasePath -Name $policyName -Value $policies[$policyName]
    }
}

function Invoke-ComputerPolicyUpdate {
    Write-Host "Running gpupdate for computer policies..."
    & gpupdate.exe /target:computer /force 2>&1 | Out-Host

    if ($LASTEXITCODE -ne 0) {
        Write-Warning "gpupdate exited with code $LASTEXITCODE. Registry policies were still written. Policy refresh may require domain membership or a reboot."
    }
}

function Split-PolicyList {
    param(
        [string]$Value,
        [string]$SeparatorPattern = '[\r\n;,]'
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return @()
    }

    return @(
        $Value -split $SeparatorPattern |
            ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
}

function Set-OptionalDWordPolicy {
    param(
        [string]$Name,
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return
    }

    switch ($Value.ToLowerInvariant()) {
        "true" { Set-PolicyValue -BasePath $chromePolicyPath -Name $Name -Value 1 -ExplicitType "DWord" }
        "false" { Set-PolicyValue -BasePath $chromePolicyPath -Name $Name -Value 0 -ExplicitType "DWord" }
        default { Set-PolicyValue -BasePath $chromePolicyPath -Name $Name -Value ([int]$Value) -ExplicitType "DWord" }
    }
}

foreach ($policyName in (Split-PolicyList -Value $env:REMOVE_CHROME_POLICIES)) {
    Remove-PolicyValue -BasePath $chromePolicyPath -Name $policyName
    Write-Host "Removed Chrome policy $policyName."
}

foreach ($policyName in (Split-PolicyList -Value $env:REMOVE_CHROME_UPDATE_POLICIES)) {
    Remove-PolicyValue -BasePath $googleUpdatePolicyPath -Name $policyName
    Write-Host "Removed Chrome Update policy $policyName."
}

if (-not [string]::IsNullOrWhiteSpace($env:CHROME_HOMEPAGE_URL)) {
    Set-PolicyValue -BasePath $chromePolicyPath -Name "HomepageLocation" -Value $env:CHROME_HOMEPAGE_URL.Trim() -ExplicitType "String"
    Set-PolicyValue -BasePath $chromePolicyPath -Name "HomepageIsNewTabPage" -Value 0 -ExplicitType "DWord"
}

$startupUrls = Split-PolicyList -Value $env:CHROME_STARTUP_URLS
if ($startupUrls.Count -gt 0) {
    Set-PolicyValue -BasePath $chromePolicyPath -Name "RestoreOnStartup" -Value 4 -ExplicitType "DWord"
    Set-PolicyList -BasePath $chromePolicyPath -Name "RestoreOnStartupURLs" -Values $startupUrls
}

$extensionForceList = Split-PolicyList -Value $env:CHROME_EXTENSION_INSTALL_FORCELIST
if ($extensionForceList.Count -gt 0) {
    Set-PolicyList -BasePath $chromePolicyPath -Name "ExtensionInstallForcelist" -Values $extensionForceList
}

$urlBlocklist = Split-PolicyList -Value $env:CHROME_URL_BLOCKLIST
if ($urlBlocklist.Count -gt 0) {
    Set-PolicyList -BasePath $chromePolicyPath -Name "URLBlocklist" -Values $urlBlocklist
}

$urlAllowlist = Split-PolicyList -Value $env:CHROME_URL_ALLOWLIST
if ($urlAllowlist.Count -gt 0) {
    Set-PolicyList -BasePath $chromePolicyPath -Name "URLAllowlist" -Values $urlAllowlist
}

Set-OptionalDWordPolicy -Name "BookmarkBarEnabled" -Value $env:CHROME_BOOKMARK_BAR_ENABLED
Set-OptionalDWordPolicy -Name "MetricsReportingEnabled" -Value $env:CHROME_METRICS_REPORTING_ENABLED
Set-OptionalDWordPolicy -Name "PasswordManagerEnabled" -Value $env:CHROME_PASSWORD_MANAGER_ENABLED
Set-OptionalDWordPolicy -Name "SafeBrowsingProtectionLevel" -Value $env:CHROME_SAFE_BROWSING_PROTECTION_LEVEL
Set-OptionalDWordPolicy -Name "BrowserSignin" -Value $env:CHROME_BROWSER_SIGNIN

Set-PolicyObject -BasePath $chromePolicyPath -Json $env:CHROME_POLICIES_JSON
Set-PolicyObject -BasePath $googleUpdatePolicyPath -Json $env:CHROME_UPDATE_POLICIES_JSON

if ($env:RUN_GPUPDATE -eq "true") {
    Invoke-ComputerPolicyUpdate
}

Write-Host "Chrome Enterprise policy configuration complete."
Write-Host "Registry policies were written under $chromePolicyPath and $googleUpdatePolicyPath."
Write-Host "Review active browser policy state at chrome://policy after Chrome refreshes policies."
