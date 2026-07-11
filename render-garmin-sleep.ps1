[CmdletBinding()]
param(
    [string]$Date = (Get-Date).ToString("yyyy-MM-dd"),
    [int]$TargetSleepMin = 480,
    [string]$Output = "sleep_output",
    [ValidateSet("l", "m", "h")][string]$Quality = "h",
    [switch]$Transparent,
    [int]$TotalSleepMin = 430,
    [int]$DeepMin = 95,
    [int]$LightMin = 240,
    [int]$RemMin = 95,
    [int]$AwakeMin = 25
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "scripts\common.ps1")

$SceneScript = Join-Path $PSScriptRoot "sleep_tracker.py"

$env:TARGET_SLEEP_MIN = $TargetSleepMin
$env:SLEEP_DATE = $Date
$env:SLEEP_TITLE = "Sleep Recovery"

$env:TOTAL_SLEEP_MIN = $TotalSleepMin
$env:DEEP_MIN = $DeepMin
$env:LIGHT_MIN = $LightMin
$env:REM_MIN = $RemMin
$env:AWAKE_MIN = $AwakeMin

Invoke-ManimScene `
    -ProjectRoot $PSScriptRoot `
    -SceneScript $SceneScript `
    -SceneName "SleepTracker" `
    -OutputName $Output `
    -Quality $Quality `
    -Transparent:$Transparent
