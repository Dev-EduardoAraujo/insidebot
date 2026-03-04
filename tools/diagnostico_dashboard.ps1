# Script de diagnostico para Trading Dashboard
# Verifica configuracao de rede e firewall

param(
    [string]$ServerHost = "192.168.15.21",
    [int]$Port = 8788
)

Write-Host "===================================================" -ForegroundColor Cyan
Write-Host "  Diagnostico - Trading Dashboard" -ForegroundColor Cyan
Write-Host "===================================================" -ForegroundColor Cyan
Write-Host ""

# 1. Verifica IPs da maquina
Write-Host "[1] Enderecos IP da maquina:" -ForegroundColor Yellow
$ips = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.*" }
foreach ($ip in $ips) {
    Write-Host "    $($ip.IPAddress) - $($ip.InterfaceAlias)" -ForegroundColor White
}
Write-Host ""

# 2. Verifica se a porta esta em uso
Write-Host "[2] Verificando porta $Port..." -ForegroundColor Yellow
$portInUse = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue
if ($portInUse) {
    Write-Host "    Porta $Port esta EM USO" -ForegroundColor Green
    Write-Host "    Processo: PID $($portInUse.OwningProcess)" -ForegroundColor Gray
    $process = Get-Process -Id $portInUse.OwningProcess -ErrorAction SilentlyContinue
    if ($process) {
        Write-Host "    Nome: $($process.ProcessName)" -ForegroundColor Gray
    }
} else {
    Write-Host "    Porta $Port NAO esta em uso" -ForegroundColor Red
    Write-Host "    O servidor precisa estar rodando!" -ForegroundColor Yellow
}
Write-Host ""

# 3. Verifica regra de firewall
Write-Host "[3] Verificando regra de firewall..." -ForegroundColor Yellow
$firewallRule = Get-NetFirewallRule -DisplayName "Trading Dashboard Server" -ErrorAction SilentlyContinue
if ($firewallRule) {
    Write-Host "    Regra encontrada: $($firewallRule.DisplayName)" -ForegroundColor Green
    Write-Host "    Status: $($firewallRule.Enabled)" -ForegroundColor Gray
    Write-Host "    Acao: $($firewallRule.Action)" -ForegroundColor Gray
} else {
    Write-Host "    Regra NAO encontrada!" -ForegroundColor Red
    Write-Host "    Execute: .\tools\configurar_firewall_dashboard.ps1 (como Admin)" -ForegroundColor Yellow
}
Write-Host ""

# 4. Testa conexao local
Write-Host "[4] Testando conexao local..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "http://127.0.0.1:$Port" -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop
    Write-Host "    Conexao local: OK" -ForegroundColor Green
} catch {
    Write-Host "    Conexao local: FALHOU" -ForegroundColor Red
    Write-Host "    Erro: $($_.Exception.Message)" -ForegroundColor Gray
}
Write-Host ""

# 5. Instrucoes
Write-Host "===================================================" -ForegroundColor Cyan
Write-Host "  Instrucoes" -ForegroundColor Cyan
Write-Host "===================================================" -ForegroundColor Cyan
Write-Host ""

if (-not $portInUse) {
    Write-Host "1. Inicie o servidor:" -ForegroundColor Yellow
    Write-Host "   powershell -ExecutionPolicy Bypass -File .\tools\iniciar_trading_dashboard.ps1" -ForegroundColor White
    Write-Host ""
}

if (-not $firewallRule) {
    Write-Host "2. Configure o firewall (como Administrador):" -ForegroundColor Yellow
    Write-Host "   powershell -ExecutionPolicy Bypass -File .\tools\configurar_firewall_dashboard.ps1" -ForegroundColor White
    Write-Host ""
}

Write-Host "3. Acesse de outra maquina:" -ForegroundColor Yellow
foreach ($ip in $ips) {
    Write-Host "   http://$($ip.IPAddress):$Port" -ForegroundColor White
}
Write-Host ""

Write-Host "4. Se ainda nao funcionar, verifique:" -ForegroundColor Yellow
Write-Host "   - Antivirus pode estar bloqueando" -ForegroundColor Gray
Write-Host "   - Firewall de terceiros (Norton, McAfee, etc)" -ForegroundColor Gray
Write-Host "   - Rede pode ter isolamento entre dispositivos" -ForegroundColor Gray
Write-Host ""

pause
