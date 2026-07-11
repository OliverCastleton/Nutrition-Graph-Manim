param(
    [string]$CsvPath = (Join-Path $PSScriptRoot "Inputs\FoodLog.CSV"),
    [int]$DefaultTargetCal = 3400,
    [string]$OutputPrefix = "nutrition",
    [string]$RenderScriptPath = (Join-Path $PSScriptRoot "render.ps1"),
    [ValidateSet("l", "m", "h")][string]$Quality = "h",
    [switch]$Transparent,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Convert-ToDate {
    param([Parameter(Mandatory = $true)][string]$Value)

    $trimmed = $Value.Trim()
    $patterns = @(
        "dddd, MMMM d, yyyy",
        "dddd, MMMM dd, yyyy",
        "yyyy-MM-dd",
        "dd/MM/yyyy",
        "MM/dd/yyyy",
        "dd-MM-yyyy",
        "MM-dd-yyyy"
    )

    foreach ($pattern in $patterns) {
        $parsed = [datetime]::MinValue
        if ([datetime]::TryParseExact(
            $trimmed,
            $pattern,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AllowWhiteSpaces,
            [ref]$parsed
        )) {
            return $parsed.Date
        }
    }

    $fallback = [datetime]::MinValue
    if ([datetime]::TryParse($trimmed, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AllowWhiteSpaces, [ref]$fallback)) {
        return $fallback.Date
    }

    throw "Unable to parse date '$Value'."
}

function Convert-ToInt {
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory = $true)][string]$FieldName
    )

    if ($null -eq $Value) {
        throw "Missing value for '$FieldName'."
    }

    $raw = $Value.ToString().Trim()
    if ([string]::IsNullOrWhiteSpace($raw) -or $raw -eq "--") {
        throw "Missing/empty value for '$FieldName'."
    }

    $clean = ($raw -replace "[^0-9.,-]", "") -replace ",", "."
    $num = 0.0
    if (-not [double]::TryParse($clean, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$num)) {
        throw "Could not parse '$raw' for '$FieldName'."
    }

    return [int][Math]::Round($num)
}

function Get-ValueByName {
    param(
        [Parameter(Mandatory = $true)][psobject]$Row,
        [Parameter(Mandatory = $true)][string[]]$Names,
        [switch]$Required
    )

    foreach ($name in $Names) {
        $prop = $Row.PSObject.Properties[$name]
        if ($null -ne $prop -and -not [string]::IsNullOrWhiteSpace([string]$prop.Value) -and [string]$prop.Value -ne "--") {
            return $prop.Value
        }
    }

    if ($Required) {
        throw "Required column missing. Tried: $($Names -join ', ')"
    }

    return $null
}

if (-not (Test-Path -LiteralPath $CsvPath)) {
    throw "Food CSV not found: $CsvPath"
}

if (-not (Test-Path -LiteralPath $RenderScriptPath)) {
    throw "render.ps1 not found: $RenderScriptPath"
}

$rows = Import-Csv -LiteralPath $CsvPath
if (-not $rows -or $rows.Count -eq 0) {
    throw "No rows found in $CsvPath"
}

$rendered = 0
$skipped = [System.Collections.Generic.List[string]]::new()

foreach ($row in $rows) {
    try {
        $dateRaw = Get-ValueByName -Row $row -Names @("Date") -Required
        $date = Convert-ToDate -Value ([string]$dateRaw)
        $dateKey = $date.ToString("yyyy-MM-dd")

        $cal = Convert-ToInt -Value (Get-ValueByName -Row $row -Names @("Cals ( kcal)", "Calories", "TotalCalories", "Calorie", "EnergyKcal") -Required) -FieldName "Calories"
        $protein = Convert-ToInt -Value (Get-ValueByName -Row $row -Names @("Prot( g)", "Protein", "ProteinG", "Protein(g)") -Required) -FieldName "Protein"
        $carbs = Convert-ToInt -Value (Get-ValueByName -Row $row -Names @("Carbs( g)", "Carbs", "Carbohydrate", "Carbohydrates", "CarbsG", "Carbohydrate(g)") -Required) -FieldName "Carbs"
        $fat = Convert-ToInt -Value (Get-ValueByName -Row $row -Names @("Fat( g)", "Fat", "FatG", "Fat(g)") -Required) -FieldName "Fat"

        $targetRaw = Get-ValueByName -Row $row -Names @("TargetCal", "TargetCalories", "GoalCalories")
        $targetCal = if ($null -ne $targetRaw) {
            Convert-ToInt -Value $targetRaw -FieldName "TargetCalories"
        }
        else {
            $DefaultTargetCal
        }

        $outputName = "{0}_{1}" -f $OutputPrefix, $dateKey
        Write-Host "Nutrition: $dateKey -> $outputName"

        if (-not $DryRun) {
            & $RenderScriptPath `
                -TargetCal $targetCal `
                -TotalCal $cal `
                -Protein $protein `
                -Carbs $carbs `
                -Fat $fat `
                -Output $outputName `
                -Quality $Quality `
                -Transparent:$Transparent

            if ($LASTEXITCODE -ne 0) {
                throw "Render failed with exit code $LASTEXITCODE"
            }
        }

        $rendered++
    }
    catch {
        $label = if ($row.PSObject.Properties["Date"]) { [string]$row.Date } else { "<no-date>" }
        $skipped.Add("$label ($($_.Exception.Message))")
    }
}

Write-Host "Nutrition batch complete. Rendered: $rendered"
if ($skipped.Count -gt 0) {
    Write-Warning "Skipped rows:"
    foreach ($item in $skipped) {
        Write-Warning " - $item"
    }
}
