param(
    [Parameter(Mandatory = $true)]
    [string]$ConsumerKey,

    [Parameter(Mandatory = $true)]
    [string]$ConsumerSecret,

    [string]$Callback = "oob",
    [string]$TokenOutputPath = (Join-Path $PSScriptRoot "fatsecret-oauth1-token.json")
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

        $kv = $pair -split "=", 2
        $k = [Uri]::UnescapeDataString($kv[0])
        $v = if ($kv.Count -gt 1) { [Uri]::UnescapeDataString($kv[1]) } else { "" }
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
        $pairs.Add("$(ConvertTo-Rfc3986 $key)=$(ConvertTo-Rfc3986 ([string]$AllParams[$key]))")
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

function Invoke-SignedOAuth1 {
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
    foreach ($k in $RequestParams.Keys) { $allParams[$k] = [string]$RequestParams[$k] }
    foreach ($k in $oauth.Keys) { $allParams[$k] = [string]$oauth[$k] }

    $oauth.oauth_signature = New-OAuthSignature -HttpMethod $HttpMethod -Url $Url -AllParams $allParams -ConsumerSecret $ConsumerSecret -TokenSecret $TokenSecret

    $combinedParams = @{}
    foreach ($k in $RequestParams.Keys) { $combinedParams[$k] = [string]$RequestParams[$k] }
    foreach ($k in $oauth.Keys) { $combinedParams[$k] = [string]$oauth[$k] }

    if ($HttpMethod -eq "GET") {
        $uriBuilder = [System.UriBuilder]::new($Url)
        $queryParts = [System.Collections.Generic.List[string]]::new()
        foreach ($k in ($combinedParams.Keys | Sort-Object)) {
            $queryParts.Add("$(ConvertTo-Rfc3986 $k)=$(ConvertTo-Rfc3986 ([string]$combinedParams[$k]))")
        }
        $uriBuilder.Query = $queryParts -join "&"
        return Invoke-WebRequest -Method Get -Uri $uriBuilder.Uri.AbsoluteUri -UseBasicParsing
    }

    return Invoke-WebRequest -Method Post -Uri $Url -ContentType "application/x-www-form-urlencoded" -Body $combinedParams -UseBasicParsing
}

$requestTokenUrl = "https://authentication.fatsecret.com/oauth/request_token"
$authorizeBaseUrl = "https://authentication.fatsecret.com/oauth/authorize"
$accessTokenUrl = "https://authentication.fatsecret.com/oauth/access_token"

Write-Host "Step 1/3: Requesting temporary request token..."
$requestTokenResponse = Invoke-SignedOAuth1 `
    -HttpMethod "POST" `
    -Url $requestTokenUrl `
    -ConsumerKey $ConsumerKey `
    -ConsumerSecret $ConsumerSecret `
    -ExtraOAuthParams @{ oauth_callback = $Callback }

$requestTokenData = Parse-QueryString -Text $requestTokenResponse.Content
if (-not $requestTokenData.ContainsKey("oauth_token") -or -not $requestTokenData.ContainsKey("oauth_token_secret")) {
    throw "Request token response did not contain oauth_token and oauth_token_secret."
}

$requestToken = [string]$requestTokenData.oauth_token
$requestTokenSecret = [string]$requestTokenData.oauth_token_secret

$authUrl = "{0}?oauth_token={1}" -f $authorizeBaseUrl, (ConvertTo-Rfc3986 $requestToken)

Write-Host "Step 2/3: Authorize this app in your browser:"
Write-Host $authUrl
Write-Host "If your callback is 'oob', copy the oauth_verifier shown by FatSecret."

$oauthVerifier = Read-Host "Paste oauth_verifier"
if ([string]::IsNullOrWhiteSpace($oauthVerifier)) {
    throw "oauth_verifier is required."
}

Write-Host "Step 3/3: Exchanging request token for access token..."
$accessTokenResponse = Invoke-SignedOAuth1 `
    -HttpMethod "GET" `
    -Url $accessTokenUrl `
    -ConsumerKey $ConsumerKey `
    -ConsumerSecret $ConsumerSecret `
    -Token $requestToken `
    -TokenSecret $requestTokenSecret `
    -RequestParams @{ oauth_verifier = $oauthVerifier }

$accessData = Parse-QueryString -Text $accessTokenResponse.Content
if (-not $accessData.ContainsKey("oauth_token") -or -not $accessData.ContainsKey("oauth_token_secret")) {
    throw "Access token response did not contain oauth_token and oauth_token_secret."
}

$result = [pscustomobject]@{
    consumer_key       = $ConsumerKey
    consumer_secret    = $ConsumerSecret
    oauth_token        = [string]$accessData.oauth_token
    oauth_token_secret = [string]$accessData.oauth_token_secret
    created_utc        = [DateTime]::UtcNow.ToString("o")
}

$result | ConvertTo-Json -Depth 5 | Out-File -LiteralPath $TokenOutputPath -Encoding utf8

Write-Host "Saved token data to: $TokenOutputPath"
Write-Host "You can now run render-fatsecret-api-range.ps1 without passing token parameters."
