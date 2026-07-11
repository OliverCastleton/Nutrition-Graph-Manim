param(
    [string]$InputsDir = (Join-Path $PSScriptRoot "Inputs"),
    [int]$NutritionTargetCal = 3400,
    [int]$SleepTargetMin = 480,
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
    & $foodScript -CsvPath $foodCsv -DefaultTargetCal $NutritionTargetCal -OutputPrefix "nutrition" -DryRun
}
else {
    & $foodScript -CsvPath $foodCsv -DefaultTargetCal $NutritionTargetCal -OutputPrefix "nutrition"
}

Write-Host "Starting sleep batch from $sleepCsv"
if ($DryRun) {
    & $sleepScript -CsvPath $sleepCsv -TargetSleepMin $SleepTargetMin -OutputPrefix "sleep" -DryRun
}
else {
    & $sleepScript -CsvPath $sleepCsv -TargetSleepMin $SleepTargetMin -OutputPrefix "sleep"
}

Write-Host "All batch renders completed."
