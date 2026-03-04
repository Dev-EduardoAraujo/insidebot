param(
    [ValidateSet("health", "list", "upsert", "revoke", "unrevoke", "extend")]
    [string]$Action = "health",

    [string]$BaseUrl = "http://127.0.0.1:8090",
    [string]$AdminKey = "",

    [string]$Token = "",
    [string]$CustomerName = "",
    [string]$ExpiresAt = "",
    [string]$AllowedLogins = "",
    [string]$AllowedServers = "",
    [string]$Notes = "",
    [int]$Days = 0,
    [int]$Limit = 200
)

if ([string]::IsNullOrWhiteSpace($AdminKey)) {
    $AdminKey = $env:INSIDEBOT_LICENSE_ADMIN_KEY
}

function Split-List([string]$text) {
    if ([string]::IsNullOrWhiteSpace($text)) { return @() }
    return $text.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
}

function Invoke-Api([string]$Method, [string]$Path, $Body = $null, [bool]$UseAdmin = $true) {
    $uri = "$BaseUrl$Path"
    $headers = @{}
    if ($UseAdmin) {
        if ([string]::IsNullOrWhiteSpace($AdminKey)) {
            throw "AdminKey ausente. Use -AdminKey ou INSIDEBOT_LICENSE_ADMIN_KEY."
        }
        $headers["X-Admin-Key"] = $AdminKey
    }
    if ($null -eq $Body) {
        return Invoke-RestMethod -Method $Method -Uri $uri -Headers $headers -TimeoutSec 20
    }
    $jsonBody = $Body | ConvertTo-Json -Depth 8
    return Invoke-RestMethod -Method $Method -Uri $uri -Headers $headers -Body $jsonBody -ContentType "application/json" -TimeoutSec 20
}

try {
    switch ($Action) {
        "health" {
            $resp = Invoke-Api -Method "GET" -Path "/api/health" -UseAdmin:$false
            $resp | ConvertTo-Json -Depth 8
        }
        "list" {
            $tokenQuery = ""
            if (-not [string]::IsNullOrWhiteSpace($Token)) {
                $tokenEscaped = [uri]::EscapeDataString($Token)
                $tokenQuery = "&token=$tokenEscaped"
            }
            $resp = Invoke-Api -Method "GET" -Path "/api/v1/admin/licenses?limit=$Limit&offset=0$tokenQuery"
            $resp | ConvertTo-Json -Depth 8
        }
        "upsert" {
            if ([string]::IsNullOrWhiteSpace($Token)) { throw "Use -Token." }
            if ([string]::IsNullOrWhiteSpace($CustomerName)) { throw "Use -CustomerName." }
            if ([string]::IsNullOrWhiteSpace($ExpiresAt)) { throw "Use -ExpiresAt (ex: 2026-12-31 23:59:59)." }
            $body = @{
                token = $Token
                customer_name = $CustomerName
                expires_at = $ExpiresAt
                allowed_logins = (Split-List $AllowedLogins)
                allowed_servers = (Split-List $AllowedServers)
                notes = $Notes
                active = $true
                revoked = $false
            }
            $resp = Invoke-Api -Method "POST" -Path "/api/v1/admin/license/upsert" -Body $body
            $resp | ConvertTo-Json -Depth 8
        }
        "revoke" {
            if ([string]::IsNullOrWhiteSpace($Token)) { throw "Use -Token." }
            $body = @{ token = $Token; revoked = $true }
            $resp = Invoke-Api -Method "POST" -Path "/api/v1/admin/license/revoke" -Body $body
            $resp | ConvertTo-Json -Depth 8
        }
        "unrevoke" {
            if ([string]::IsNullOrWhiteSpace($Token)) { throw "Use -Token." }
            $body = @{ token = $Token; revoked = $false }
            $resp = Invoke-Api -Method "POST" -Path "/api/v1/admin/license/revoke" -Body $body
            $resp | ConvertTo-Json -Depth 8
        }
        "extend" {
            if ([string]::IsNullOrWhiteSpace($Token)) { throw "Use -Token." }
            if ($Days -eq 0 -and [string]::IsNullOrWhiteSpace($ExpiresAt)) {
                throw "Use -Days N ou -ExpiresAt."
            }
            $body = @{ token = $Token }
            if ($Days -ne 0) { $body["days"] = $Days }
            if (-not [string]::IsNullOrWhiteSpace($ExpiresAt)) { $body["expires_at"] = $ExpiresAt }
            $resp = Invoke-Api -Method "POST" -Path "/api/v1/admin/license/extend" -Body $body
            $resp | ConvertTo-Json -Depth 8
        }
    }
}
catch {
    Write-Error $_
    exit 1
}

