param(
    [int]$TargetCal = 3400,
    [int]$TotalCal  = 3000,
    [int]$Protein   = 160,
    [int]$Carbs     = 300,
    [int]$Fat       = 71,
    [string]$Output = "macro_output",
    [string]$Quality = "h",
    [switch]$Transparent
)

$ScriptDir = "C:\Users\Utente\Documents\GitHub\timelapse-scripts\Nutrition-Graph-Manim"

$env:TARGET_CAL = $TargetCal
$env:TOTAL_CAL  = $TotalCal
$env:PROTEIN    = $Protein
$env:CARBS      = $Carbs
$env:FAT        = $Fat

$qualityFlag = "-pq$Quality"
$transparentFlag = if ($Transparent) { "--transparent" } else { "" }

Push-Location $ScriptDir

if ($Transparent) {
    manim $qualityFlag --transparent "$ScriptDir\macro_tracker.py" MacroTracker -o $Output
} else {
    manim $qualityFlag "$ScriptDir\macro_tracker.py" MacroTracker -o $Output
}

Pop-Location
