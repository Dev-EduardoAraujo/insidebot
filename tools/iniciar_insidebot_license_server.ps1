param(
    [string]$BindHost = "0.0.0.0",
    [int]$Port = 8090,
    [string]$DbPath = "tools\license_data\licenses.db",
    [string]$AdminKey = "",
    [string]$LogLevel = "INFO"
)

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Resolve-Path (Join-Path $scriptRoot "..")
$serverScript = Join-Path $scriptRoot "insidebot_license_server.py"

if (-not [System.IO.Path]::IsPathRooted($DbPath)) {
    $DbPath = Join-Path $projectRoot $DbPath
}

if ([string]::IsNullOrWhiteSpace($AdminKey)) {
    $AdminKey = $env:INSIDEBOT_LICENSE_ADMIN_KEY
}

if ([string]::IsNullOrWhiteSpace($AdminKey)) {
    Write-Error "Defina -AdminKey ou a variavel INSIDEBOT_LICENSE_ADMIN_KEY."
    exit 1
}

$env:INSIDEBOT_LICENSE_ADMIN_KEY = $AdminKey
$env:INSIDEBOT_LICENSE_DB = $DbPath
$env:INSIDEBOT_LICENSE_HOST = $BindHost
$env:INSIDEBOT_LICENSE_PORT = "$Port"
$env:INSIDEBOT_LICENSE_LOG_LEVEL = $LogLevel

Write-Host "Iniciando InsideBot License Server em http://${BindHost}:${Port}" -ForegroundColor Green
Write-Host "DB: $DbPath" -ForegroundColor Cyan

Push-Location $projectRoot
try {
    python $serverScript --host $BindHost --port $Port --db-path $DbPath --log-level $LogLevel
}
finally {
    Pop-Location
}
