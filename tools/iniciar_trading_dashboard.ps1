param(
    [string]$ServerHost = "0.0.0.0",
    [int]$Port = 8788,
    [string]$ReportsDir = "docs\relatorios\operacoes"
)

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "  prime_bot Trading Dashboard" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptPath

Push-Location $projectRoot

Write-Host "Iniciando servidor..." -ForegroundColor Yellow
Write-Host "Host: $ServerHost" -ForegroundColor Gray
Write-Host "Port: $Port" -ForegroundColor Gray
Write-Host "Reports: $ReportsDir" -ForegroundColor Gray
Write-Host ""

python "$scriptPath\trading_dashboard_server.py" --host $ServerHost --port $Port --reports-dir $ReportsDir

Pop-Location
