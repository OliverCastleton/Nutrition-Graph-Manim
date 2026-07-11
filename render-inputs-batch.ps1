param(
    [string]$InputsDir = (Join-Path $PSScriptRoot "Inputs"),
    [int]$NutritionTargetCal = 3400,
    [int]$SleepTargetMin = 480,
    [ValidateSet("l", "m", "h")][string]$Quality = "h",
    [switch]$Transparent,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$foodScript = Join-Path $PSScriptRoot "render-foodlog-batch.ps1"
$sleepScript = Join-Path $PSScriptRoot "render-sleep-csv-batch.ps1"

$foodCsv = Join-Path $InputsDir "FoodLog.CSV"
$sleepCsv = Join-Path $InputsDir "Sleep.csv"

if (-not (Test-Path -LiteralPath $foodScript)) {
    throw "Missing script: $foodScript"
}
if (-not (Test-Path -LiteralPath $sleepScript)) {
    throw "Missing script: $sleepScript"
}

Write-Host "Starting nutrition batch from $foodCsv"
if ($DryRun) {
    & $foodScript -CsvPath $foodCsv -DefaultTargetCal $NutritionTargetCal -OutputPrefix "nutrition" -Quality $Quality -Transparent:$Transparent -DryRun
}
else {
    & $foodScript -CsvPath $foodCsv -DefaultTargetCal $NutritionTargetCal -OutputPrefix "nutrition" -Quality $Quality -Transparent:$Transparent
}

Write-Host "Starting sleep batch from $sleepCsv"
if ($DryRun) {
    & $sleepScript -CsvPath $sleepCsv -TargetSleepMin $SleepTargetMin -OutputPrefix "sleep" -Quality $Quality -Transparent:$Transparent -DryRun
}
else {
    & $sleepScript -CsvPath $sleepCsv -TargetSleepMin $SleepTargetMin -OutputPrefix "sleep" -Quality $Quality -Transparent:$Transparent
}

Write-Host "All batch renders completed. Outputs are under outputs/manim/."
