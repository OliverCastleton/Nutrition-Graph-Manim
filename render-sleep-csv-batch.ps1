param(
    [string]$CsvPath = (Join-Path $PSScriptRoot "Inputs\Sleep.csv"),
    [int]$TargetSleepMin = 480,
    [string]$OutputPrefix = "sleep",
    [string]$RenderSleepScriptPath = (Join-Path $PSScriptRoot "render-garmin-sleep.ps1"),
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
        "dd-MM-yy",
        "d-M-yy",
        "yyyy-MM-dd",
        "dd/MM/yyyy",
        "MM/dd/yyyy"
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

function Convert-DurationToMinutes {
    param([Parameter(Mandatory = $true)][string]$Value)

    $raw = $Value.Trim()
    if ([string]::IsNullOrWhiteSpace($raw) -or $raw -eq "--") {
        return $null
    }

    $h = 0
    $m = 0

    if ($raw -match "(?i)(\d+)\s*h") {
        $h = [int]$Matches[1]
    }
    if ($raw -match "(?i)(\d+)\s*min") {
        $m = [int]$Matches[1]
    }

    if ($h -eq 0 -and $m -eq 0) {
        return $null
    }

    return ($h * 60 + $m)
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
    throw "Sleep CSV not found: $CsvPath"
}

if (-not (Test-Path -LiteralPath $RenderSleepScriptPath)) {
    throw "render-garmin-sleep.ps1 not found: $RenderSleepScriptPath"
}

$rows = Import-Csv -LiteralPath $CsvPath
if (-not $rows -or $rows.Count -eq 0) {
    throw "No rows found in $CsvPath"
}

$rendered = 0
$skipped = [System.Collections.Generic.List[string]]::new()

foreach ($row in $rows) {
    try {
        $dateRaw = Get-ValueByName -Row $row -Names @("Sleep Score 4 Weeks", "Date")
        $durationRaw = Get-ValueByName -Row $row -Names @("Duration")

        if ([string]::IsNullOrWhiteSpace([string]$dateRaw)) {
            continue
        }

        $date = Convert-ToDate -Value ([string]$dateRaw)
        $dateKey = $date.ToString("yyyy-MM-dd")
        $missingDuration = [string]::IsNullOrWhiteSpace([string]$durationRaw) -or [string]$durationRaw -eq "--"

        $totalSleep = if ($missingDuration) {
            0
        }
        else {
            Convert-DurationToMinutes -Value ([string]$durationRaw)
        }

        if ($null -eq $totalSleep -or $totalSleep -lt 0) {
            throw "Duration is empty or invalid."
        }

        # Estimate stage minutes because exported Sleep.csv does not include deep/light/REM split.
        $deep = [int][Math]::Round($totalSleep * 0.22)
        $light = [int][Math]::Round($totalSleep * 0.56)
        $rem = [int][Math]::Round($totalSleep * 0.22)
        $delta = $totalSleep - ($deep + $light + $rem)
        $light += $delta

        $awake = 0
        $outputName = "{0}_{1}" -f $OutputPrefix, $dateKey

        if ($missingDuration) {
            Write-Warning "Sleep: $dateKey has no duration in CSV; rendering placeholder with 0m"
        }

        Write-Host "Sleep: $dateKey -> $outputName (total ${totalSleep}m)"

        if (-not $DryRun) {
            & $RenderSleepScriptPath `
                -Date $dateKey `
                -TargetSleepMin $TargetSleepMin `
                -TotalSleepMin $totalSleep `
                -DeepMin $deep `
                -LightMin $light `
                -RemMin $rem `
                -AwakeMin $awake `
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
        $label = if ($row.PSObject.Properties["Sleep Score 4 Weeks"]) { [string]$row."Sleep Score 4 Weeks" } else { "<no-date>" }
        $skipped.Add("$label ($($_.Exception.Message))")
    }
}

Write-Host "Sleep batch complete. Rendered: $rendered"
if ($skipped.Count -gt 0) {
    Write-Warning "Skipped rows:"
    foreach ($item in $skipped) {
        Write-Warning " - $item"
    }
}
