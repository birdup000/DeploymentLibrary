# Deploy ezlocalai - Local AI Inference Server (Windows)
# Clones ezlocalai, creates a Python venv, installs it, configures env vars, and starts the server.
$ErrorActionPreference = "Stop"

# Configuration from environment variables with defaults
$InstallDir = if ($env:EZLOCALAI_INSTALL_DIR) { $env:EZLOCALAI_INSTALL_DIR } else { "C:\ezlocalai" }
$DefaultModel = if ($env:EZLOCALAI_DEFAULT_MODEL) { $env:EZLOCALAI_DEFAULT_MODEL } else { "unsloth/Qwen3.5-4B-GGUF" }
$MaxTokens = if ($env:EZLOCALAI_MAX_TOKENS) { $env:EZLOCALAI_MAX_TOKENS } else { "40000" }
$Port = if ($env:EZLOCALAI_PORT) { $env:EZLOCALAI_PORT } else { "8091" }
$ApiKey = if ($env:EZLOCALAI_API_KEY) { $env:EZLOCALAI_API_KEY } else { "" }
$WhisperModel = if ($env:EZLOCALAI_WHISPER_MODEL) { $env:EZLOCALAI_WHISPER_MODEL } else { "large-v3" }
$ImgModel = if ($env:EZLOCALAI_IMG_MODEL) { $env:EZLOCALAI_IMG_MODEL } else { "Tongyi-MAI/Z-Image-Turbo" }
$TtsEnabled = if ($env:EZLOCALAI_TTS_ENABLED) { $env:EZLOCALAI_TTS_ENABLED } else { "true" }
$SttEnabled = if ($env:EZLOCALAI_STT_ENABLED) { $env:EZLOCALAI_STT_ENABLED } else { "true" }
$QuantType = if ($env:EZLOCALAI_QUANT_TYPE) { $env:EZLOCALAI_QUANT_TYPE } else { "Q4_K_XL" }
$BatchSize = if ($env:EZLOCALAI_BATCH_SIZE) { $env:EZLOCALAI_BATCH_SIZE } else { "2048" }
$VoiceServer = if ($env:EZLOCALAI_VOICE_SERVER) { $env:EZLOCALAI_VOICE_SERVER } else { "" }
$ImageServer = if ($env:EZLOCALAI_IMAGE_SERVER) { $env:EZLOCALAI_IMAGE_SERVER } else { "" }
$TextServer = if ($env:EZLOCALAI_TEXT_SERVER) { $env:EZLOCALAI_TEXT_SERVER } else { "" }
$RepoUrl = "https://github.com/DevXT-LLC/ezlocalai.git"

# If IMG_MODEL doesn't contain a "/", treat it as disabled (empty)
if ($ImgModel -notmatch '/') {
    $ImgModel = ""
}

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  ezlocalai Deployment Script (Windows)" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Install directory: $InstallDir"
Write-Host "Default model:     $DefaultModel"
Write-Host "Max tokens:        $MaxTokens"
Write-Host "Port:              $Port"
Write-Host ""

# ------------------------------------------------------------------
# 1. Ensure Python is available
# ------------------------------------------------------------------
$PythonCmd = $null
foreach ($candidate in @("python3", "python", "py")) {
    try {
        $result = & $candidate --version 2>&1
        if ($LASTEXITCODE -eq 0) {
            $PythonCmd = $candidate
            break
        }
    } catch { }
}

if (-not $PythonCmd) {
    Write-Host "ERROR: Python not found. Please install Python 3.11+ first." -ForegroundColor Red
    Write-Host "You can use the 'install-python' deployment script."
    exit 1
}

$PythonVer = & $PythonCmd --version 2>&1
Write-Host "Using Python: $PythonCmd ($PythonVer)"

# ------------------------------------------------------------------
# 2. Ensure git is available
# ------------------------------------------------------------------
try {
    & git --version | Out-Null
} catch {
    Write-Host "ERROR: git is not installed. Please install git first." -ForegroundColor Red
    exit 1
}

# ------------------------------------------------------------------
# 3. Clone or update the repository
# ------------------------------------------------------------------
if (Test-Path "$InstallDir\.git") {
    Write-Host "Updating existing ezlocalai installation..."
    Set-Location $InstallDir
    & git pull --ff-only 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "WARNING: git pull failed, continuing with existing code." -ForegroundColor Yellow
    }
} else {
    Write-Host "Cloning ezlocalai repository..."
    if (-not (Test-Path (Split-Path $InstallDir -Parent))) {
        New-Item -ItemType Directory -Path (Split-Path $InstallDir -Parent) -Force | Out-Null
    }
    & git clone $RepoUrl $InstallDir
    Set-Location $InstallDir
}

# ------------------------------------------------------------------
# 4. Create / update virtual environment
# ------------------------------------------------------------------
$VenvDir = Join-Path $InstallDir ".venv"
if (-not (Test-Path $VenvDir)) {
    Write-Host "Creating virtual environment..."
    & $PythonCmd -m venv $VenvDir
}

# Activate venv
$ActivateScript = Join-Path $VenvDir "Scripts\Activate.ps1"
. $ActivateScript
Write-Host "Virtual environment active: $VenvDir"

# Upgrade pip
& pip install --upgrade pip -q

# ------------------------------------------------------------------
# 4b. Install uv for faster package management
# ------------------------------------------------------------------
$UvAvailable = $false
try {
    & pip install uv -q 2>$null
    $UvAvailable = $true
    Write-Host "Using uv for fast package installation."
} catch {
    Write-Host "uv not available, using pip (slower but functional)."
}

function Pkg-Install {
    if ($UvAvailable) {
        & uv pip install @Args
    } else {
        & pip install @Args
    }
}

# ------------------------------------------------------------------
# 5. Install ezlocalai in editable mode
# ------------------------------------------------------------------
Write-Host "Installing ezlocalai..."
Set-Location $InstallDir
Pkg-Install -e . -q

# ------------------------------------------------------------------
# 6. Write environment configuration
# ------------------------------------------------------------------
$EnvFile = Join-Path $InstallDir ".env"
Write-Host "Writing environment configuration to $EnvFile..."

@"
# ezlocalai configuration - generated by deployment script
DEFAULT_MODEL=$DefaultModel
LLM_MAX_TOKENS=$MaxTokens
EZLOCALAI_URL=http://0.0.0.0:$Port
EZLOCALAI_API_KEY=$ApiKey
WHISPER_MODEL=$WhisperModel
IMG_MODEL=$ImgModel
TTS_ENABLED=$TtsEnabled
STT_ENABLED=$SttEnabled
QUANT_TYPE=$QuantType
LLM_BATCH_SIZE=$BatchSize
VOICE_SERVER=$VoiceServer
IMAGE_SERVER=$ImageServer
TEXT_SERVER=$TextServer
"@ | Set-Content -Path $EnvFile -Encoding UTF8

Write-Host "Configuration written."

# ------------------------------------------------------------------
# 7. Create management wrapper scripts
# ------------------------------------------------------------------
$ScriptsDir = Join-Path $InstallDir "scripts"
if (-not (Test-Path $ScriptsDir)) {
    New-Item -ItemType Directory -Path $ScriptsDir -Force | Out-Null
}

@'
@echo off
set "SCRIPT_DIR=%~dp0.."
call "%SCRIPT_DIR%\.venv\Scripts\activate.bat"
cd /d "%SCRIPT_DIR%"
ezlocalai start %*
'@ | Set-Content -Path (Join-Path $ScriptsDir "start.bat") -Encoding ASCII

@'
@echo off
set "SCRIPT_DIR=%~dp0.."
call "%SCRIPT_DIR%\.venv\Scripts\activate.bat"
cd /d "%SCRIPT_DIR%"
ezlocalai stop
'@ | Set-Content -Path (Join-Path $ScriptsDir "stop.bat") -Encoding ASCII

@'
@echo off
set "SCRIPT_DIR=%~dp0.."
call "%SCRIPT_DIR%\.venv\Scripts\activate.bat"
cd /d "%SCRIPT_DIR%"
ezlocalai restart %*
'@ | Set-Content -Path (Join-Path $ScriptsDir "restart.bat") -Encoding ASCII

@'
@echo off
set "SCRIPT_DIR=%~dp0.."
call "%SCRIPT_DIR%\.venv\Scripts\activate.bat"
cd /d "%SCRIPT_DIR%"
ezlocalai status
'@ | Set-Content -Path (Join-Path $ScriptsDir "status.bat") -Encoding ASCII

@'
@echo off
set "SCRIPT_DIR=%~dp0.."
call "%SCRIPT_DIR%\.venv\Scripts\activate.bat"
cd /d "%SCRIPT_DIR%"
ezlocalai logs -f
'@ | Set-Content -Path (Join-Path $ScriptsDir "logs.bat") -Encoding ASCII

Write-Host ""
Write-Host "=============================================" -ForegroundColor Green
Write-Host "  ezlocalai Deployment Complete!" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Installation directory: $InstallDir"
Write-Host "Virtual environment:    $VenvDir"
Write-Host "Configuration file:     $EnvFile"
Write-Host ""
Write-Host "Management commands (activate venv first):"
Write-Host "  $VenvDir\Scripts\activate.bat"
Write-Host "  ezlocalai start        # Start the server"
Write-Host "  ezlocalai stop         # Stop the server"
Write-Host "  ezlocalai restart      # Restart the server"
Write-Host "  ezlocalai status       # Check server status"
Write-Host "  ezlocalai logs -f      # Follow server logs"
Write-Host ""
Write-Host "Or use the wrapper scripts:"
Write-Host "  $ScriptsDir\start.bat"
Write-Host "  $ScriptsDir\stop.bat"
Write-Host "  $ScriptsDir\restart.bat"
Write-Host "  $ScriptsDir\status.bat"
Write-Host "  $ScriptsDir\logs.bat"
Write-Host ""
$LocalIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notmatch 'Loopback' -and $_.IPAddress -ne '127.0.0.1' } | Select-Object -First 1).IPAddress
if (-not $LocalIP) { $LocalIP = "localhost" }
Write-Host "Server will be available at: http://${LocalIP}:$Port"

# Start the server
Write-Host ""
Write-Host "Starting ezlocalai..."
. (Join-Path $VenvDir "Scripts\Activate.ps1")
Set-Location $InstallDir
& ezlocalai start --model $DefaultModel
