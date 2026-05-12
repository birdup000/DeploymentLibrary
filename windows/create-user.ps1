# Create Local User (Windows)
$newUser = $env:NEW_USERNAME
$password = $env:NEW_PASSWORD

if (-not $newUser) {
    Write-Host "ERROR: NEW_USERNAME environment variable is required."
    exit 1
}

Write-Host "Creating local user: $newUser"

try {
    if ($password) {
        $securePass = ConvertTo-SecureString $password -AsPlainText -Force
        New-LocalUser -Name $newUser -Password $securePass -FullName $newUser -Description "Created via XT Systems" -ErrorAction Stop
        Write-Host "Password set successfully."
    } else {
        New-LocalUser -Name $newUser -NoPassword -FullName $newUser -Description "Created via XT Systems" -ErrorAction Stop
        Write-Host "User created without a password."
    }
    Write-Host "User $newUser created successfully."
} catch {
    Write-Host "ERROR: Failed to create user. $_"
    exit 1
}
