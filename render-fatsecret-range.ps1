param(
    [Parameter(Mandatory = $true)]
    [datetime]$StartDate,

    [Parameter(Mandatory = $true)]
    [datetime]$EndDate,

    [Parameter(Mandatory = $true)]
    [string]$CsvPath,

    [int]$DefaultTargetCal = 3400,
    [string]$OutputPrefix = "macro",
    [string]$RenderScriptPath = (Join-Path $PSScriptRoot "render.ps1")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Convert-ToDate {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    $trimmed = $Value.Trim()
    $patterns = @(
        "yyyy-MM-dd",
        "dd/MM/yyyy",
        "MM/dd/yyyy",
        "d/M/yyyy",
        "M/d/yyyy",
        "dd-MM-yyyy",
        "MM-dd-yyyy",
        "d MMM yyyy",
        "dd MMM yyyy",
        "MMMM d yyyy",
        "MMMM dd yyyy"
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
    if ([datetime]::TryParse($trimmed, [ref]$fallback)) {
        return $fallback.Date
    }

    throw "Unable to parse date '$Value'."
}

function Convert-ToInt {
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Value,
        [Parameter(Mandatory = $true)]
        [string]$FieldName
    )

    if ($null -eq $Value) {
        throw "Missing value for '$FieldName'."
    }

    $raw = $Value.ToString().Trim()
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw "Empty value for '$FieldName'."
    }

    $clean = ($raw -replace "[^0-9.,-]", "")
    $clean = $clean -replace ",", "."

    $number = 0.0
    if (-not [double]::TryParse(
        $clean,
        [Globalization.NumberStyles]::Float,
        [Globalization.CultureInfo]::InvariantCulture,
        [ref]$number
    )) {
        throw "Could not parse numeric value '$raw' for '$FieldName'."
    }

    return [int][Math]::Round($number)
}

function Get-PropertyValue {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Row,
        [Parameter(Mandatory = $true)]
        [string[]]$CandidateNames,
        [switch]$Required
    )

    foreach ($name in $CandidateNames) {
        $prop = $Row.PSObject.Properties[$name]
        if ($null -ne $prop -and -not [string]::IsNullOrWhiteSpace([string]$prop.Value)) {
            return $prop.Value
        }
    }

    if ($Required) {
        throw "Could not find required column. Tried: $($CandidateNames -join ', ')"
    }

    return $null
}

if ($StartDate.Date -gt $EndDate.Date) {
    throw "StartDate must be less than or equal to EndDate."
}

if (-not (Test-Path -LiteralPath $CsvPath)) {
    throw "CSV file not found: $CsvPath"
}

if (-not (Test-Path -LiteralPath $RenderScriptPath)) {
    throw "render.ps1 not found: $RenderScriptPath"
}

$rows = Import-Csv -LiteralPath $CsvPath
if (-not $rows -or $rows.Count -eq 0) {
    throw "CSV file has no rows: $CsvPath"
}

$byDate = @{}
foreach ($row in $rows) {
    $dateValue = Get-PropertyValue -Row $row -CandidateNames @("Date", "Day", "LogDate", "EntryDate") -Required
    $dateKey = (Convert-ToDate -Value ([string]$dateValue)).ToString("yyyy-MM-dd")
    $byDate[$dateKey] = $row
}

$renderedCount = 0
$skippedDates = [System.Collections.Generic.List[string]]::new()

for ($d = $StartDate.Date; $d -le $EndDate.Date; $d = $d.AddDays(1)) {
    $dateKey = $d.ToString("yyyy-MM-dd")
    if (-not $byDate.ContainsKey($dateKey)) {
        $skippedDates.Add($dateKey)
        continue
    }

    $row = $byDate[$dateKey]

    $totalCal = Convert-ToInt -Value (Get-PropertyValue -Row $row -CandidateNames @("Calories", "TotalCalories", "Calorie", "EnergyKcal") -Required) -FieldName "Calories"
    $protein = Convert-ToInt -Value (Get-PropertyValue -Row $row -CandidateNames @("Protein", "ProteinG", "Protein(g)") -Required) -FieldName "Protein"
    $carbs = Convert-ToInt -Value (Get-PropertyValue -Row $row -CandidateNames @("Carbs", "Carbohydrate", "Carbohydrates", "CarbsG", "Carbohydrate(g)") -Required) -FieldName "Carbs"
    $fat = Convert-ToInt -Value (Get-PropertyValue -Row $row -CandidateNames @("Fat", "FatG", "Fat(g)") -Required) -FieldName "Fat"

    $targetRaw = Get-PropertyValue -Row $row -CandidateNames @("TargetCal", "TargetCalories", "GoalCalories")
    $targetCal = if ($null -ne $targetRaw) {
        Convert-ToInt -Value $targetRaw -FieldName "TargetCal"
    }
    else {
        $DefaultTargetCal
    }

    $outputName = "{0}_{1}" -f $OutputPrefix, $dateKey

    Write-Host "Rendering $dateKey -> $outputName"
    & $RenderScriptPath `
        -TargetCal $targetCal `
        -TotalCal $totalCal `
        -Protein $protein `
        -Carbs $carbs `
        -Fat $fat `
        -Output $outputName `
        -Quality "h" `
        -Transparent

    if ($LASTEXITCODE -ne 0) {
        throw "Render failed for $dateKey with exit code $LASTEXITCODE"
    }

    $renderedCount++
}

Write-Host "Completed. Rendered $renderedCount day(s)."
if ($skippedDates.Count -gt 0) {
    Write-Warning "Skipped dates with no CSV row: $($skippedDates -join ', ')"
}
