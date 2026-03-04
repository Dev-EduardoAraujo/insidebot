# BASELINE ESTAVEL - 2026-02-26

## Fonte

- JSON de trades:
  - `C:\Users\Eduardo\AppData\Roaming\MetaQuotes\Tester\0C70BAF49107A81D87101E046DBD933C\Agent-127.0.0.1-3000\MQL5\Files\Prime_botV2_Trades_XAUUSD.h_start_20250102_010000_end_20260225_235959_saved_20260225_235959.json`
- Relatorio gerado:
  - `docs/relatorios/operacoes/0201_2502-LimitOfDeposit100k.md`
- Timestamp de geracao:
  - `2026-02-26 16:28:27`

## Resumo executivo

- Total de operacoes: `296`
- TP / SL / BE: `205 / 91 / 0`
- TurnOf: `69` (gatilhos de TurnOf: `72`)
- Operacoes com ADON: `131` (ADONs executados: `131`)
- Win rate: `69.26%`
- Profit Factor: `2.01`
- Lucro liquido oficial (compativel com Tester): `82053.12`
- Saldo final oficial: `182053.12`
- Max Drawdown (sequencia por exit_time): `4794.17` (`4.41%`)
- Max DD intraday flutuante: `3076.69` (`2.14%` do saldo do dia)
- Max DD+Limit: `3699.85`

## Estado da documentacao atualizado neste marco

- `README.md` atualizado com:
  - status de referencia da versao estavel
  - parametros completos de DD (incluindo `DrawdownPercentReference` e `ForceDayBalanceDDWhenUnderInitialDeposit`)
  - logs diarios `DD OPEN` e `DD OPEN SHORT`
  - secao de dashboard com dropdown de DD Open diario
- `ROADMAP.md` atualizado com secao de baseline `2026-02-26`
- `tools/trading_dashboard/README.md` atualizado com o novo dropdown `DD Open Diario (Saldo e Limites)` e campo de API `dd_open_daily`
