[CmdletBinding()]
param(
    [int]$TargetCal = 3400,
    [int]$TotalCal  = 3000,
    [int]$Protein   = 160,
    [int]$Carbs     = 300,
    [int]$Fat       = 71,
    [string]$Output = "macro_output",
    [ValidateSet("l", "m", "h")][string]$Quality = "h",
    [switch]$Transparent,
    [string]$EnvFilePath = (Join-Path $PSScriptRoot ".env")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "scripts\common.ps1")
Import-EnvFile -Path $EnvFilePath

$scenePath = Join-Path $PSScriptRoot "macro_tracker.py"

[Environment]::SetEnvironmentVariable("TARGET_CAL", $TargetCal.ToString(), "Process")
[Environment]::SetEnvironmentVariable("TOTAL_CAL", $TotalCal.ToString(), "Process")
[Environment]::SetEnvironmentVariable("PROTEIN", $Protein.ToString(), "Process")
[Environment]::SetEnvironmentVariable("CARBS", $Carbs.ToString(), "Process")
[Environment]::SetEnvironmentVariable("FAT", $Fat.ToString(), "Process")

Invoke-ManimScene `
    -ProjectRoot $PSScriptRoot `
    -SceneScript $scenePath `
    -SceneName "MacroTracker" `
    -OutputName $Output `
    -Quality $Quality `
    -Transparent:$Transparent
