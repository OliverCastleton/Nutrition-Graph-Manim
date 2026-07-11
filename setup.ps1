[CmdletBinding()]
param(
    [string]$VenvDir = ".venv"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$projectRoot = $PSScriptRoot
$venvPath = Join-Path $projectRoot $VenvDir
$requirementsPath = Join-Path $projectRoot "requirements.txt"

if (-not (Get-Command -Name "python" -ErrorAction SilentlyContinue)) {
    throw "Python is not available in PATH. Install Python 3.11+ and retry."
}

if (-not (Test-Path -LiteralPath $requirementsPath)) {
    throw "Missing requirements file: $requirementsPath"
}

if (-not (Test-Path -LiteralPath $venvPath)) {
    Write-Host "Creating virtual environment at $venvPath"
    python -m venv $venvPath
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create virtual environment."
    }
}

$pythonExe = Join-Path $venvPath "Scripts\python.exe"
if (-not (Test-Path -LiteralPath $pythonExe)) {
    throw "Virtual environment python not found: $pythonExe"
}

Write-Host "Upgrading pip/setuptools/wheel..."
& $pythonExe -m pip install --upgrade pip setuptools wheel
if ($LASTEXITCODE -ne 0) {
    throw "Failed to upgrade pip tools."
}

Write-Host "Installing project dependencies..."
& $pythonExe -m pip install -r $requirementsPath
if ($LASTEXITCODE -ne 0) {
    throw "Dependency installation failed."
}

Write-Host "Setup complete."
Write-Host "Activate with: .\\.venv\\Scripts\\Activate.ps1"
Write-Host "If PowerShell blocks activation, run once: Set-ExecutionPolicy -Scope CurrentUser RemoteSigned"
