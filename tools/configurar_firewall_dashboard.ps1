# Script para configurar firewall do Windows para o Trading Dashboard
# Execute como Administrador

param(
    [int]$Port = 8788
)

Write-Host "===================================================" -ForegroundColor Cyan
Write-Host "  Configuracao de Firewall - Trading Dashboard" -ForegroundColor Cyan
Write-Host "===================================================" -ForegroundColor Cyan
Write-Host ""

# Verifica se esta rodando como administrador
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "ERRO: Este script precisa ser executado como Administrador!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Clique com botao direito no PowerShell e selecione 'Executar como Administrador'" -ForegroundColor Yellow
    Write-Host ""
    pause
    exit 1
}

Write-Host "Configurando regra de firewall para porta $Port..." -ForegroundColor Yellow
Write-Host ""

# Remove regra existente se houver
$existingRule = Get-NetFirewallRule -DisplayName "Trading Dashboard Server" -ErrorAction SilentlyContinue
if ($existingRule) {
    Write-Host "Removendo regra existente..." -ForegroundColor Gray
    Remove-NetFirewallRule -DisplayName "Trading Dashboard Server"
}

# Cria nova regra
try {
    New-NetFirewallRule -DisplayName "Trading Dashboard Server" `
                        -Direction Inbound `
                        -Protocol TCP `
                        -LocalPort $Port `
                        -Action Allow `
                        -Profile Any `
                        -Description "Permite acesso ao Trading Dashboard na rede local"
    
    Write-Host "Regra de firewall criada com sucesso!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Porta $Port liberada para acesso na rede local" -ForegroundColor Green
    Write-Host ""
} catch {
    Write-Host "ERRO ao criar regra de firewall: $_" -ForegroundColor Red
    Write-Host ""
    pause
    exit 1
}

Write-Host "Configuracao concluida!" -ForegroundColor Cyan
Write-Host ""
Write-Host "Agora inicie o servidor com:" -ForegroundColor Yellow
Write-Host "  powershell -ExecutionPolicy Bypass -File .\tools\iniciar_trading_dashboard.ps1" -ForegroundColor White
Write-Host ""
Write-Host "E acesse de outra maquina usando:" -ForegroundColor Yellow
Write-Host "  http://192.168.15.21:$Port" -ForegroundColor White
Write-Host ""
pause
