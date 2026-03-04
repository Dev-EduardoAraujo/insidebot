param(
    [Parameter(Mandatory = $true)]
    [string]$Token,

    [Parameter(Mandatory = $true)]
    [string]$Cliente,

    [string]$LicenseUrl = "https://insidebotcontrol.com.br",
    [string]$SourceFile = "sliced\InsideBot.mq5"
)

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Resolve-Path (Join-Path $scriptRoot "..")
if (-not [System.IO.Path]::IsPathRooted($SourceFile)) {
    $SourceFile = Join-Path $projectRoot $SourceFile
}

if (-not (Test-Path $SourceFile)) {
    Write-Error "Arquivo nao encontrado: $SourceFile"
    exit 1
}

$content = Get-Content -Path $SourceFile -Raw -Encoding UTF8

$escapedToken = $Token.Replace("\", "\\").Replace('"', '\"')
$escapedCliente = $Cliente.Replace("\", "\\").Replace('"', '\"')
$escapedUrl = $LicenseUrl.Replace("\", "\\").Replace('"', '\"')

$content = [regex]::Replace($content, 'string\s+LicenseServerBaseUrl\s*=\s*".*?";', "string   LicenseServerBaseUrl = `"$escapedUrl`";")
$content = [regex]::Replace($content, 'string\s+LicenseToken\s*=\s*".*?";', "string   LicenseToken = `"$escapedToken`";")
$content = [regex]::Replace($content, 'string\s+LicensedCustomerName\s*=\s*".*?";', "string   LicensedCustomerName = `"$escapedCliente`";")
$content = [regex]::Replace($content, 'bool\s+EnableLicenseValidation\s*=\s*(true|false);', "bool     EnableLicenseValidation = true;")
$content = [regex]::Replace($content, 'bool\s+EnforceLiveHedgeAccount\s*=\s*(true|false);', "bool     EnforceLiveHedgeAccount = true;")

Set-Content -Path $SourceFile -Value $content -Encoding UTF8

Write-Host "Release aplicada em $SourceFile" -ForegroundColor Green
Write-Host "Cliente: $Cliente"
Write-Host "URL: $LicenseUrl"
Write-Host "Token: $Token"
