Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Import-EnvFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [switch]$OverwriteExisting
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    Get-Content -LiteralPath $Path | ForEach-Object {
        $line = $_.Trim()
        if ([string]::IsNullOrWhiteSpace($line)) { return }
        if ($line.StartsWith("#")) { return }

        $parts = $line -split "=", 2
        if ($parts.Count -ne 2) { return }

        $name = $parts[0].Trim()
        $value = $parts[1].Trim().Trim('"').Trim("'")
        if ([string]::IsNullOrWhiteSpace($name)) { return }

        if (-not $OverwriteExisting -and -not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name, "Process"))) {
            return
        }

        [Environment]::SetEnvironmentVariable($name, $value, "Process")
    }
}

function New-DirectoryIfMissing {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        $null = New-Item -ItemType Directory -Path $Path -Force
    }
}

function Assert-CommandAvailable {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$CommandName)

    if (-not (Get-Command -Name $CommandName -ErrorAction SilentlyContinue)) {
        throw "Required command '$CommandName' is not available in PATH."
    }
}

function Invoke-ManimScene {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$SceneScript,
        [Parameter(Mandatory = $true)][string]$SceneName,
        [Parameter(Mandatory = $true)][string]$OutputName,
        [ValidateSet("l", "m", "h")][string]$Quality = "h",
        [switch]$Transparent,
        [string]$MediaDir = "outputs/manim"
    )

    Assert-CommandAvailable -CommandName "manim"

    if (-not (Test-Path -LiteralPath $SceneScript)) {
        throw "Scene script not found: $SceneScript"
    }

    $resolvedMediaDir = Join-Path $ProjectRoot $MediaDir
    New-DirectoryIfMissing -Path $resolvedMediaDir

    $args = @("-q$Quality")
    if ($Transparent) {
        $args += "--transparent"
    }

    $args += @("--media_dir", $resolvedMediaDir, $SceneScript, $SceneName, "-o", $OutputName)

    Push-Location $ProjectRoot
    try {
        & manim @args
        if ($LASTEXITCODE -ne 0) {
            throw "manim exited with code $LASTEXITCODE"
        }
    }
    finally {
        Pop-Location
    }
}
