# prime_botV2 Trading Dashboard

Dashboard local para visualizar relatorios markdown gerados a partir dos JSON do `prime_botV2`.

## Arquivos

- `tools/trading_dashboard/index.html`
- `tools/trading_dashboard/styles.css`
- `tools/trading_dashboard/app.js`
- `tools/trading_dashboard_server.py`
- `tools/iniciar_trading_dashboard.ps1`

## Como iniciar

### Opcao 1: PowerShell (atalho do projeto)

```powershell
cd C:\Users\Eduardo\PycharmProjects\bot_MT5
powershell -ExecutionPolicy Bypass -File .\tools\iniciar_trading_dashboard.ps1
```

Com parametros:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\iniciar_trading_dashboard.ps1 -ServerHost 0.0.0.0 -Port 8788 -ReportsDir "docs\relatorios\operacoes"
```

### Opcao 2: Python direto

```powershell
cd C:\Users\Eduardo\PycharmProjects\bot_MT5
python .\tools\trading_dashboard_server.py --host 127.0.0.1 --port 8788 --reports-dir docs\relatorios\operacoes
```

## Acesso

- Local: `http://127.0.0.1:8788`
- Rede local (se iniciar com `-ServerHost 0.0.0.0`): `http://<ip-da-maquina>:8788`

## O que o servidor lista

- Endpoint `/api/reports` lista todos os arquivos `.md` do diretorio configurado.
- Nao ha filtro por prefixo de nome.

## Secoes de relatorio esperadas

O parser foi feito para markdown gerado por `gerar_relatorio_operacoes_json.ps1` e extrai:
- `Resumo Geral`
- `Metricas de Performance`
- `DD Tick a Tick`
- `DD Open Diario (Saldo e Limites)`
- `Resumo Mensal`
- tabelas de operacoes (`Detalhado`, `TP`, `SL`, `turnof`, `AddOn`)
- `Dias sem Operacao (NoTrade)`.

Na secao `Dias sem Operacao`, o dashboard suporta relatorios com as colunas novas:
- `Faltou LIMIT (pts)`
- `RR Max`
- `RR Min`

Novo dropdown de DD:
- `DD Open Diario (Saldo e Limites)` mostra, por dia:
  - `Saldo Inicio Dia`
  - `DD Max Diario Permitido`
  - `DD Max Geral Permitido`

API:
- `/api/report` agora inclui `dd_open_daily` para alimentar esse dropdown.

## Troubleshooting

### Porta em uso

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\iniciar_trading_dashboard.ps1 -Port 8789
```

### Relatorios nao aparecem

1. Confirme o caminho em `-ReportsDir`.
2. Confirme que existem arquivos `.md` no diretorio.
3. Abra `http://127.0.0.1:8788/api/reports` para validar retorno JSON.

### Erro de parse

1. Gere o markdown novamente com `gerar_relatorio_operacoes_json.ps1`.
2. Verifique se os titulos de secao estao completos no arquivo.
