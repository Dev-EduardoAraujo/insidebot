# Solução de Problemas - Acesso Remoto ao Trading Dashboard

## Problema: Não consigo acessar o dashboard de outra máquina na rede

### Diagnóstico Rápido

Execute o script de diagnóstico:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\diagnostico_dashboard.ps1
```

Este script verifica:
- IPs da máquina
- Se a porta 8788 está em uso
- Regras de firewall
- Conectividade local

---

## Solução Passo a Passo

### 1. Configure o Firewall do Windows

**Execute como Administrador:**

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\configurar_firewall_dashboard.ps1
```

Isso cria uma regra permitindo conexões na porta 8788.

### 2. Inicie o Servidor Corretamente

**Certifique-se de usar `--host 0.0.0.0`:**

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\iniciar_trading_dashboard.ps1
```

O script já usa `0.0.0.0` por padrão, que permite conexões externas.

**OU inicie manualmente:**

```powershell
python .\tools\trading_dashboard_server.py --host 0.0.0.0 --port 8788 --reports-dir docs\relatorios\operacoes
```

### 3. Verifique o IP da Máquina Servidor

No PowerShell:

```powershell
ipconfig
```

Procure por "Endereço IPv4" (ex: 192.168.15.21)

### 4. Acesse de Outra Máquina

No navegador da outra máquina:

```
http://192.168.15.21:8788
```

---

## Checklist de Problemas Comuns

### ❌ Servidor iniciado com 127.0.0.1

**Problema:** Servidor só aceita conexões locais

**Solução:** Reinicie com `--host 0.0.0.0`

### ❌ Firewall do Windows bloqueando

**Problema:** Windows bloqueia conexões externas na porta

**Solução:** Execute `configurar_firewall_dashboard.ps1` como Admin

### ❌ Antivírus bloqueando

**Problema:** Antivírus de terceiros pode bloquear

**Solução:** Adicione exceção para Python ou porta 8788

### ❌ Isolamento de rede

**Problema:** Roteador com isolamento AP ativado

**Solução:** Desative "AP Isolation" nas configurações do roteador

### ❌ IP mudou

**Problema:** DHCP atribuiu novo IP à máquina

**Solução:** Verifique o IP atual com `ipconfig`

---

## Comandos Úteis

### Verificar se o servidor está rodando:

```powershell
netstat -ano | findstr :8788
```

### Testar conexão local:

```powershell
curl http://127.0.0.1:8788
```

### Ver regras de firewall:

```powershell
Get-NetFirewallRule -DisplayName "Trading Dashboard Server"
```

### Remover regra de firewall:

```powershell
Remove-NetFirewallRule -DisplayName "Trading Dashboard Server"
```

---

## Configuração Avançada

### Usar IP fixo em vez de 0.0.0.0:

```powershell
python .\tools\trading_dashboard_server.py --host 192.168.15.21 --port 8788 --reports-dir docs\relatorios\operacoes
```

### Mudar porta (se 8788 estiver em uso):

```powershell
python .\tools\trading_dashboard_server.py --host 0.0.0.0 --port 8080 --reports-dir docs\relatorios\operacoes
```

Não esqueça de atualizar a regra de firewall para a nova porta!

---

## Ainda não funciona?

1. **Desative temporariamente o firewall do Windows** para testar:
   - Painel de Controle → Sistema e Segurança → Firewall do Windows → Ativar ou desativar
   - Se funcionar, o problema é o firewall

2. **Verifique antivírus de terceiros:**
   - Norton, McAfee, Avast, etc podem bloquear
   - Adicione exceção para Python.exe

3. **Teste com outro dispositivo:**
   - Tente acessar de outro computador/celular na mesma rede
   - Se funcionar em um mas não em outro, o problema é no dispositivo cliente

4. **Verifique configurações do roteador:**
   - Acesse painel do roteador (geralmente 192.168.0.1 ou 192.168.1.1)
   - Procure por "AP Isolation", "Client Isolation" ou "Isolamento de Rede"
   - Desative se estiver ativo

---

## Logs do Servidor

O servidor mostra no console:

```
Trading Dashboard Server running at http://0.0.0.0:8788
Project root: C:\Users\Eduardo\PycharmProjects\bot_MT5
Reports directory: C:\Users\Eduardo\PycharmProjects\bot_MT5\docs\relatorios\operacoes
```

Se mostrar `http://127.0.0.1:8788`, está errado! Precisa ser `0.0.0.0`.
