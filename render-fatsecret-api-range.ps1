param(
    [Parameter(Mandatory = $true)]
    [datetime]$StartDate,

    [Parameter(Mandatory = $true)]
    [datetime]$EndDate,

    [string]$ConsumerKey,
    [string]$ConsumerSecret,
    [string]$AccessToken,
    [string]$AccessTokenSecret,

    [string]$TokenFilePath = (Join-Path $PSScriptRoot "fatsecret-oauth1-token.json"),

    [int]$DefaultTargetCal = 3400,
    [string]$OutputPrefix = "fatsecret",
    [string]$RenderScriptPath = (Join-Path $PSScriptRoot "render.ps1"),

    [string]$MethodName = "profile.food_entries.get.v1",
    [string]$DateParamName = "date_int",
    [switch]$UseIsoDate,
    [switch]$VerboseApi
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function ConvertTo-Rfc3986 {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value)

    $escaped = [Uri]::EscapeDataString($Value)
    $escaped = $escaped.Replace("+", "%20").Replace("*", "%2A").Replace("%7E", "~")
    return $escaped
}

function Parse-QueryString {
    param([Parameter(Mandatory = $true)][string]$Text)

    $map = @{}
    foreach ($pair in ($Text -split "&")) {
        if ([string]::IsNullOrWhiteSpace($pair)) {
            continue
        }

        $chunks = $pair -split "=", 2
        $k = [Uri]::UnescapeDataString($chunks[0])
        $v = if ($chunks.Count -gt 1) { [Uri]::UnescapeDataString($chunks[1]) } else { "" }
        $map[$k] = $v
    }

    return $map
}

function New-OAuthSignature {
    param(
        [Parameter(Mandatory = $true)][ValidateSet("GET", "POST")][string]$HttpMethod,
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][hashtable]$AllParams,
        [Parameter(Mandatory = $true)][string]$ConsumerSecret,
        [AllowEmptyString()][string]$TokenSecret = ""
    )

    $pairs = [System.Collections.Generic.List[string]]::new()
    foreach ($key in ($AllParams.Keys | Sort-Object)) {
        $value = [string]$AllParams[$key]
        $pairs.Add("$(ConvertTo-Rfc3986 $key)=$(ConvertTo-Rfc3986 $value)")
    }

    $normalized = $pairs -join "&"
    $base = "{0}&{1}&{2}" -f $HttpMethod.ToUpperInvariant(), (ConvertTo-Rfc3986 $Url), (ConvertTo-Rfc3986 $normalized)
    $signingKey = "{0}&{1}" -f (ConvertTo-Rfc3986 $ConsumerSecret), (ConvertTo-Rfc3986 $TokenSecret)

    $hmac = [System.Security.Cryptography.HMACSHA1]::new([Text.Encoding]::ASCII.GetBytes($signingKey))
    try {
        $hash = $hmac.ComputeHash([Text.Encoding]::ASCII.GetBytes($base))
        return [Convert]::ToBase64String($hash)
    }
    finally {
        $hmac.Dispose()
    }
}

function New-OAuthHeader {
    param([Parameter(Mandatory = $true)][hashtable]$OAuthParams)

    $parts = [System.Collections.Generic.List[string]]::new()
    foreach ($key in ($OAuthParams.Keys | Sort-Object)) {
        $encoded = ConvertTo-Rfc3986 ([string]$OAuthParams[$key])
        $parts.Add($key + '="' + $encoded + '"')
    }

    return "OAuth " + ($parts -join ", ")
}

function Invoke-FatSecretOAuth1Method {
    param(
        [Parameter(Mandatory = $true)][ValidateSet("GET", "POST")][string]$HttpMethod,
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$ConsumerKey,
        [Parameter(Mandatory = $true)][string]$ConsumerSecret,
        [string]$Token,
        [string]$TokenSecret,
        [hashtable]$RequestParams = @{},
        [hashtable]$ExtraOAuthParams = @{}
    )

    $oauth = @{
        oauth_consumer_key     = $ConsumerKey
        oauth_nonce            = [Guid]::NewGuid().ToString("N")
        oauth_signature_method = "HMAC-SHA1"
        oauth_timestamp        = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds().ToString()
        oauth_version          = "1.0"
    }

    if (-not [string]::IsNullOrWhiteSpace($Token)) {
        $oauth.oauth_token = $Token
    }

    foreach ($k in $ExtraOAuthParams.Keys) {
        $oauth[$k] = [string]$ExtraOAuthParams[$k]
    }

    $allParams = @{}
    foreach ($k in $RequestParams.Keys) {
        $allParams[$k] = [string]$RequestParams[$k]
    }
    foreach ($k in $oauth.Keys) {
        $allParams[$k] = [string]$oauth[$k]
    }

    $signature = New-OAuthSignature -HttpMethod $HttpMethod -Url $Url -AllParams $allParams -ConsumerSecret $ConsumerSecret -TokenSecret $TokenSecret
    $oauth.oauth_signature = $signature
    $authHeader = New-OAuthHeader -OAuthParams $oauth

    $headers = @{ Authorization = $authHeader }

    if ($HttpMethod -eq "GET") {
        $uriBuilder = [System.UriBuilder]::new($Url)
        $queryParts = [System.Collections.Generic.List[string]]::new()
        foreach ($k in ($RequestParams.Keys | Sort-Object)) {
            $queryParts.Add("$(ConvertTo-Rfc3986 $k)=$(ConvertTo-Rfc3986 ([string]$RequestParams[$k]))")
        }
        $uriBuilder.Query = $queryParts -join "&"
        return Invoke-RestMethod -Method Get -Uri $uriBuilder.Uri.AbsoluteUri -Headers $headers
    }

    return Invoke-RestMethod -Method Post -Uri $Url -Headers $headers -ContentType "application/x-www-form-urlencoded" -Body $RequestParams
}

function Get-PropValue {
    param(
        [AllowNull()][object]$Object,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($null -eq $Object) {
        return $null
    }

    foreach ($p in $Object.PSObject.Properties) {
        if ($p.Name -ieq $Name) {
            return $p.Value
        }
    }

    return $null
}

function Convert-ToDouble {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) {
        return $null
    }

    $raw = $Value.ToString().Trim()
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return $null
    }

    $clean = ($raw -replace "[^0-9.,-]", "") -replace ",", "."
    if ([string]::IsNullOrWhiteSpace($clean)) {
        return $null
    }

    $number = 0.0
    if ([double]::TryParse($clean, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$number)) {
        return $number
    }

    return $null
}

function Resolve-PathValues {
    param(
        [AllowNull()][object]$Root,
        [Parameter(Mandatory = $true)][string[]]$Paths
    )

    foreach ($path in $Paths) {
        $nodes = @($Root)
        $segments = $path -split "\."

        foreach ($seg in $segments) {
            $next = @()
            foreach ($n in $nodes) {
                if ($null -eq $n) {
                    continue
                }

                if ($n -is [System.Collections.IEnumerable] -and -not ($n -is [string])) {
                    foreach ($item in $n) {
                        $v = Get-PropValue -Object $item -Name $seg
                        if ($null -ne $v) {
                            $next += $v
                        }
                    }
                    continue
                }

                $v = Get-PropValue -Object $n -Name $seg
                if ($null -ne $v) {
                    $next += $v
                }
            }

            $nodes = $next
            if ($nodes.Count -eq 0) {
                break
            }
        }

        if ($nodes.Count -eq 0) {
            continue
        }

        $sum = 0.0
        $hits = 0
        foreach ($v in $nodes) {
            if ($v -is [System.Collections.IEnumerable] -and -not ($v -is [string])) {
                foreach ($inner in $v) {
                    $n = Convert-ToDouble -Value $inner
                    if ($null -ne $n) {
                        $sum += $n
                        $hits++
                    }
                }
                continue
            }

            $n = Convert-ToDouble -Value $v
            if ($null -ne $n) {
                $sum += $n
                $hits++
            }
        }

        if ($hits -gt 0) {
            return $sum
        }
    }

    return $null
}

function Collect-MacroObjects {
    param(
        [AllowNull()][object]$Node,
        [int]$Depth = 0,
        [ref]$Out
    )

    if ($null -eq $Node) {
        return
    }

    if ($Node -is [System.Collections.IEnumerable] -and -not ($Node -is [string])) {
        foreach ($item in $Node) {
            Collect-MacroObjects -Node $item -Depth $Depth -Out $Out
        }
        return
    }

    $keys = @()
    foreach ($p in $Node.PSObject.Properties) {
        $keys += $p.Name.ToLowerInvariant()
    }

    $hasMacro = ($keys -contains "calories") -or ($keys -contains "protein") -or ($keys -contains "carbs") -or ($keys -contains "carbohydrate") -or ($keys -contains "carbohydrates") -or ($keys -contains "fat")
    if ($hasMacro) {
        $Out.Value.Add([pscustomobject]@{ Depth = $Depth; Obj = $Node })
    }

    foreach ($p in $Node.PSObject.Properties) {
        $value = $p.Value
        if ($null -eq $value -or $value -is [string]) {
            continue
        }
        Collect-MacroObjects -Node $value -Depth ($Depth + 1) -Out $Out
    }
}

function Get-MacroBreakdown {
    param([Parameter(Mandatory = $true)][object]$Response)

    $caloriesPaths = @(
        "food_entries.summary.calories",
        "food_entries.total_calories",
        "food_entries.calories",
        "summary.calories",
        "calories"
    )
    $proteinPaths = @(
        "food_entries.summary.protein",
        "food_entries.total_protein",
        "food_entries.protein",
        "summary.protein",
        "protein"
    )
    $carbsPaths = @(
        "food_entries.summary.carbohydrates",
        "food_entries.summary.carbohydrate",
        "food_entries.total_carbohydrates",
        "food_entries.total_carbohydrate",
        "food_entries.carbs",
        "food_entries.carbohydrates",
        "carbohydrates",
        "carbohydrate",
        "carbs"
    )
    $fatPaths = @(
        "food_entries.summary.fat",
        "food_entries.total_fat",
        "food_entries.fat",
        "summary.fat",
        "fat"
    )

    $calories = Resolve-PathValues -Root $Response -Paths $caloriesPaths
    $protein = Resolve-PathValues -Root $Response -Paths $proteinPaths
    $carbs = Resolve-PathValues -Root $Response -Paths $carbsPaths
    $fat = Resolve-PathValues -Root $Response -Paths $fatPaths

    if ($null -eq $calories -or $null -eq $protein -or $null -eq $carbs -or $null -eq $fat) {
        $objects = [System.Collections.Generic.List[object]]::new()
        Collect-MacroObjects -Node $Response -Depth 0 -Out ([ref]$objects)

        if ($objects.Count -gt 0) {
            $deepest = ($objects | Measure-Object -Property Depth -Maximum).Maximum
            $selected = $objects | Where-Object { $_.Depth -eq $deepest }

            $sumCal = 0.0
            $sumProtein = 0.0
            $sumCarbs = 0.0
            $sumFat = 0.0

            foreach ($entry in $selected) {
                $o = $entry.Obj
                $vCal = Convert-ToDouble (Get-PropValue -Object $o -Name "calories")
                $vProtein = Convert-ToDouble (Get-PropValue -Object $o -Name "protein")
                $vCarbs = Convert-ToDouble (Get-PropValue -Object $o -Name "carbs")
                if ($null -eq $vCarbs) {
                    $vCarbs = Convert-ToDouble (Get-PropValue -Object $o -Name "carbohydrate")
                }
                if ($null -eq $vCarbs) {
                    $vCarbs = Convert-ToDouble (Get-PropValue -Object $o -Name "carbohydrates")
                }
                $vFat = Convert-ToDouble (Get-PropValue -Object $o -Name "fat")

                if ($null -ne $vCal) { $sumCal += $vCal }
                if ($null -ne $vProtein) { $sumProtein += $vProtein }
                if ($null -ne $vCarbs) { $sumCarbs += $vCarbs }
                if ($null -ne $vFat) { $sumFat += $vFat }
            }

            if ($null -eq $calories -and $sumCal -gt 0) { $calories = $sumCal }
            if ($null -eq $protein -and $sumProtein -ge 0) { $protein = $sumProtein }
            if ($null -eq $carbs -and $sumCarbs -ge 0) { $carbs = $sumCarbs }
            if ($null -eq $fat -and $sumFat -ge 0) { $fat = $sumFat }
        }
    }

    if ($null -eq $calories) {
        throw "Could not extract calories from API response. Use -VerboseApi to inspect payload structure."
    }

    $proteinValue = if ($null -ne $protein) { $protein } else { 0.0 }
    $carbsValue = if ($null -ne $carbs) { $carbs } else { 0.0 }
    $fatValue = if ($null -ne $fat) { $fat } else { 0.0 }

    return [pscustomobject]@{
        Calories = [int][Math]::Round($calories)
        Protein  = [int][Math]::Round($proteinValue)
        Carbs    = [int][Math]::Round($carbsValue)
        Fat      = [int][Math]::Round($fatValue)
    }
}

if ($StartDate.Date -gt $EndDate.Date) {
    throw "StartDate must be less than or equal to EndDate."
}

if (-not (Test-Path -LiteralPath $RenderScriptPath)) {
    throw "render.ps1 not found: $RenderScriptPath"
}

if (([string]::IsNullOrWhiteSpace($ConsumerKey) -or [string]::IsNullOrWhiteSpace($ConsumerSecret) -or [string]::IsNullOrWhiteSpace($AccessToken) -or [string]::IsNullOrWhiteSpace($AccessTokenSecret)) -and (Test-Path -LiteralPath $TokenFilePath)) {
    $tokenJson = Get-Content -LiteralPath $TokenFilePath -Raw | ConvertFrom-Json
    if ([string]::IsNullOrWhiteSpace($ConsumerKey)) { $ConsumerKey = [string]$tokenJson.consumer_key }
    if ([string]::IsNullOrWhiteSpace($ConsumerSecret)) { $ConsumerSecret = [string]$tokenJson.consumer_secret }
    if ([string]::IsNullOrWhiteSpace($AccessToken)) { $AccessToken = [string]$tokenJson.oauth_token }
    if ([string]::IsNullOrWhiteSpace($AccessTokenSecret)) { $AccessTokenSecret = [string]$tokenJson.oauth_token_secret }
}

if ([string]::IsNullOrWhiteSpace($ConsumerKey) -or [string]::IsNullOrWhiteSpace($ConsumerSecret) -or [string]::IsNullOrWhiteSpace($AccessToken) -or [string]::IsNullOrWhiteSpace($AccessTokenSecret)) {
    throw "Missing OAuth1 credentials. Pass keys/tokens as parameters or provide TokenFilePath with those fields."
}

$apiUrl = "https://platform.fatsecret.com/rest/server.api"
$rendered = 0

for ($d = $StartDate.Date; $d -le $EndDate.Date; $d = $d.AddDays(1)) {
    $dateKey = $d.ToString("yyyy-MM-dd")
    $dateValue = if ($UseIsoDate) { $dateKey } else { $d.ToString("yyyyMMdd") }

    $requestParams = @{
        method = $MethodName
        format = "json"
    }
    $requestParams[$DateParamName] = $dateValue

    Write-Host "Fetching FatSecret data for $dateKey"

    $response = Invoke-FatSecretOAuth1Method `
        -HttpMethod "GET" `
        -Url $apiUrl `
        -ConsumerKey $ConsumerKey `
        -ConsumerSecret $ConsumerSecret `
        -Token $AccessToken `
        -TokenSecret $AccessTokenSecret `
        -RequestParams $requestParams

    if ($VerboseApi) {
        $payloadFile = Join-Path $PSScriptRoot ("fatsecret-payload-{0}.json" -f $dateKey)
        $response | ConvertTo-Json -Depth 30 | Out-File -LiteralPath $payloadFile -Encoding utf8
        Write-Host "Saved API payload to $payloadFile"
    }

    $macros = Get-MacroBreakdown -Response $response
    $outputName = "{0}_{1}" -f $OutputPrefix, $dateKey

    Write-Host "Rendering $dateKey => calories=$($macros.Calories), protein=$($macros.Protein), carbs=$($macros.Carbs), fat=$($macros.Fat)"

    & $RenderScriptPath `
        -TargetCal $DefaultTargetCal `
        -TotalCal $macros.Calories `
        -Protein $macros.Protein `
        -Carbs $macros.Carbs `
        -Fat $macros.Fat `
        -Output $outputName `
        -Quality "h" `
        -Transparent

    if ($LASTEXITCODE -ne 0) {
        throw "Render failed for $dateKey with exit code $LASTEXITCODE"
    }

    $rendered++
}

Write-Host "Completed API range render. Rendered $rendered day(s)."
