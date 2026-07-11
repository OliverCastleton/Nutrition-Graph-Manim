param(
    [string]$Date = (Get-Date).ToString("yyyy-MM-dd"),
    [int]$TargetSleepMin = 480,
    [string]$Output = "sleep_output",
    [string]$Quality = "h",
    [switch]$Transparent,
    [switch]$UseGarmin,
    [int]$TotalSleepMin = 430,
    [int]$DeepMin = 95,
    [int]$LightMin = 240,
    [int]$RemMin = 95,
    [int]$AwakeMin = 25
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptDir = "C:\Users\Utente\Documents\GitHub\timelapse-scripts\Nutrition-Graph-Manim"
$FetchScript = Join-Path $ScriptDir "garmin_sleep_fetch.py"
$SceneScript = Join-Path $ScriptDir "sleep_tracker.py"

$env:TARGET_SLEEP_MIN = $TargetSleepMin
$env:SLEEP_DATE = $Date
$env:SLEEP_TITLE = "Sleep Recovery"

if ($UseGarmin) {
    if (-not (Test-Path -LiteralPath $FetchScript)) {
        throw "garmin_sleep_fetch.py not found: $FetchScript"
    }

    $fetchOutput = python $FetchScript --date $Date --target $TargetSleepMin --format env
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to fetch Garmin sleep data for $Date"
    }

    foreach ($line in $fetchOutput) {
        if ($line -match "^[A-Z_]+=.*$") {
            $pair = $line.Split("=", 2)
            if ($pair.Count -eq 2 -and -not [string]::IsNullOrWhiteSpace($pair[0])) {
                [Environment]::SetEnvironmentVariable($pair[0].Trim(), $pair[1].Trim(), "Process")
            }
        }
    }
}
else {
    $env:TOTAL_SLEEP_MIN = $TotalSleepMin
    $env:DEEP_MIN = $DeepMin
    $env:LIGHT_MIN = $LightMin
    $env:REM_MIN = $RemMin
    $env:AWAKE_MIN = $AwakeMin
}

$qualityFlag = "-pq$Quality"

Push-Location $ScriptDir
try {
    if ($Transparent) {
        manim $qualityFlag --transparent $SceneScript SleepTracker -o $Output
    }
    else {
        manim $qualityFlag $SceneScript SleepTracker -o $Output
    }
}
finally {
    Pop-Location
}
