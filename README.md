# prime_botV2 (MT5)

Documentacao tecnica baseada no estado atual de `sliced/prime_botV2.mq5`.

## Escopo

`prime_botV2` e um EA de breakout de canal de abertura com:
- modo normal e modo sliced
- fallback opcional para M15
- entrada por `MARKET` ou `LIMIT` com RR minimo
- estrategia PCM (segunda operacao apos TP da first_op)
- turnof com pre-armamento por `STOP` em conta hedge
- politica de overnight (manter, fechar, permitir novo ciclo)
- add-on em flutuacao negativa
- limites de drawdown percentual e absoluto
- logs JSON de trades, no-trades e DD tick a tick

## Estrutura

- EA principal: `sliced/prime_botV2.mq5`
- EA legado/referencia: `sliced/prime_bot.mq5`
- EA comercial: `sliced/InsideBot.mq5`
- Script de relatorio: `gerar_relatorio_operacoes_json.ps1`
- Dashboard local: `tools/trading_dashboard_server.py`, `tools/iniciar_trading_dashboard.ps1`
- Servidor de licenca: `tools/insidebot_license_server.py`
- Admin de licenca: `tools/gerenciar_insidebot_licencas.ps1`
- Documentos: `README.md`, `ROADMAP.md`
- Relatorios: `docs/relatorios/`

## Licenciamento InsideBot

- Dominio de validacao: `https://insidebotcontrol.com.br`
- Endpoint consumido pelo EA: `POST /api/v1/license/validate`
- Documento canonico de licencas:
  - `docs/InsideBot_CONTROLE_DE_LICENCAS.md`
- Guia completo de deploy e operacao:
  - `docs/InsideBot_LICENSE_SERVER_SETUP.md`
  - `docs/InsideBot_SEGURANCA_COMERCIAL.md`
  - `docs/InsideBot_DEPLOY_VPS_GITHUB_CHECKLIST.md`
  - `docs/InsideBot_DEPLOY_VPS_ONLY_LICENSE_SERVER.md`

## Versao do EA

- Arquivo: `sliced/prime_botV2.mq5`
- `#property version`: `1.05`
- Nome de log (`g_programName`): derivado do nome do EA compilado (ex.: `Prime_botV2`)

## Status de referencia (2026-03-03)

- Esta documentacao foi revisada contra o codigo atual de `sliced/prime_botV2.mq5`.
- Para baseline de resultado, use os relatorios em `docs/relatorios/operacoes/` gerados a partir do JSON salvo do tester mais recente.

## Fluxo principal de runtime

`OnTick()` executa nesta ordem:
1. Captura `g_backtestStartTime` no primeiro tick.
2. Atualiza DD por equity (`UpdateDrawdownMetrics`).
3. Atualiza DD tick a tick (`UpdateTickDrawdownTracking`).
4. Monitor de seguranca de SL (`EnforceStopLossSafetyMonitor`, fase pre).
5. Verifica virada de dia (`CheckNewDay`).
6. Consolida fechamento de posicoes e logging (`CheckPositionStatus`).
7. Monitor de seguranca de SL (fase post-check) e kill-switch.
8. Aplica politica de nao manter overnight (`ApplyNoOvernightPolicy`).
9. Sincroniza visuais de canal entre graficos do simbolo (`SyncChannelVisualsAcrossSymbolCharts`).
10. Rebalanceia fila de pendentes por budget DD+LIMIT (`EnforcePendingQueueByDDBudget`).
11. Processa estrategia (`ProcessStrategy`).
12. Monitor final de seguranca de SL (fase post-strategy).

## Logica operacional

### Canal e validacao

- Canal com `OpeningChannelBars` velas (padrao `4`) a partir de `OpeningHour:OpeningMinute`.
- Base em `ChannelTimeframe`.
- Fallback para M15 somente se:
  - `EnableM15Fallback = true`
  - timeframe base em M5
  - range inicial abaixo de `MinChannelRange`.
- Regras de range:
  - `< MinChannelRange`: no trade
  - `> SlicedThreshold`: modo sliced (`CA = C1`)
  - `> MaxChannelRange` e `<= SlicedThreshold`: no trade
  - entre min e max: operavel em modo normal.

### Entrada principal e RR

- Primeira entrada limitada por `FirstEntryMaxHour`.
- Breakout por fechamento da vela anterior no timeframe ativo.
- RR:
  - `RR >= MinRiskReward`: entrada imediata (market ou limit marketable, conforme modo).
  - `RR < MinRiskReward`: calcula e posiciona `LIMIT` para atingir RR minimo.

### turnof

- Ocorre apos SL com `EnableReversal = true`.
- Respeita `MaxEntryHour` e flags:
  - `AllowReversalAfterMaxEntryHour`
  - `RearmCanceledReversalNextDay`.
- Em conta hedge, usa pre-armamento por `BuyStop`/`SellStop` quando aplicavel.
- Pode usar fallback para mercado conforme:
  - `AllowMarketFallbackReversal`
  - `AllowMarketFallbackOvernightReversal`.

### Estrategia PCM

- So e armada apos TP de uma operacao principal nao-PCM (`SchedulePCMActivationFromTP`).
- Opcionalmente, pode ser armada em dia NoTrade quando LIMIT e cancelada por alvo projetado (`EnablePCMOnNoTradeLimitTarget`).
- O novo CA e recalculado a partir da vela que contem o TP, no timeframe de referencia:
  - `PCMReferenceTimeframe = PERIOD_M1 | PERIOD_M5 | PERIOD_M15`.
- Contagem de velas do CA: `PCMChannelBars` (minimo efetivo de 4).
- Parametros de range do canal PCM:
  - usar os parametros principais (`PCMUseMainChannelRangeParams = true`)
  - ou usar parametros proprios (`PCMMinChannelRange`, `PCMMaxChannelRange`, `PCMSlicedThreshold`).
- Filtro opcional de vela grande:
  - `PCMEnableSkipLargeCandle = true`
  - se range da vela > `PCMMaxCandlePoints`, reinicia a contagem a partir da vela seguinte.
- Limites de PCM:
  - `PCMMaxOperationsPerDay`
  - `EnablePCMHourLimit`, `PCMEntryMaxHour`, `PCMEntryMaxMinute`
  - `PCMIgnoreFirstEntryMaxHour`.
- Regra de risco:
  - usa `PCMRiskPercent` (fallback para `RiskPercent` se `PCMRiskPercent <= 0`).
- Gestao de posicao PCM:
  - `BreakEven` com gatilho em `% da distancia ate TP` (`PCMBreakEvenTriggerPercent`)
  - `TraillingStop` para consolidacao parcial de ganho.
- Regra de reversao:
  - operacao PCM nao gera turnof.

### Overnight

- `KeepPositionsOvernight = true`: mantem posicoes abertas.
- `KeepPositionsOvernight = false`: fecha/cancela antes do fechamento do mercado (`CloseMinutesBeforeMarketClose`).
- `AllowTradeWithOvernight = true`: permite novo ciclo mesmo com snapshot overnight.
- `EnableOvernightReversal`: habilita turnof para fechamento overnight em SL.

### Add-on negativo

- `EnableNegativeAddOn` ativa add-on por flutuacao adversa.
- `NegativeAddTriggerPercent` define gatilho (% da distancia entrada -> SL).
- `NegativeAddLotMultiplier` atua como teto opcional sobre o lote calculado pelo risco ate o SL.
- Pode usar:
  - mesmo SL/TP (`NegativeAddUseSameSLTP`)
  - ajuste de TP pos add-on (`EnableNegativeAddTPAdjustment`)
  - ajuste em turnof (`NegativeAddTPAdjustOnReversal`).

### DD e bloqueios

Bloqueios de risco:
- `DrawdownPercentReference`
- `ForceDayBalanceDDWhenUnderInitialDeposit`
- `MaxDailyDrawdownPercent`
- `MaxDrawdownPercent`
- `MaxDailyDrawdownAmount`
- `MaxDrawdownAmount`

Com limite atingido, o EA bloqueia novas exposicoes e pode cancelar pendentes.

Controle DD+LIMIT projetado:
- considera flutuacao atual, risco ate SL das posicoes abertas, risco das LIMIT pendentes e risco candidato da nova ordem.
- aplica fila de prioridade de risco para pendentes:
  - `FIRST`
  - `ADON`
  - `TURNOF`
- quando necessario, cancela pendentes de menor prioridade antes de bloquear a nova candidatura.

Controle de seguranca de SL:
- monitor continuo detecta posicao sem SL valida.
- em caso critico, ativa kill-switch (`g_killSwitchNoSLActive`) e bloqueia novas ordens.

Quando `ForceDayBalanceDDWhenUnderInitialDeposit = true` e o saldo no inicio do dia estiver abaixo do deposito inicial, a base percentual de DD diario e maximo passa a ser forcosamente o saldo do dia.

Logs diarios de DD no Journal:
- `DD OPEN [OnInit|ResetDaily] ...` (log completo com base e referencia efetiva)
- `DD OPEN SHORT [OnInit|ResetDaily] ...` (saldo do dia + limites permitidos)

## Parametros (defaults atuais em `prime_botV2.mq5`)

### `--- Parametros de Gatilho e Canal ---`
- `OpeningHour = 0`
- `OpeningMinute = 0`
- `FirstEntryMaxHour = 16`
- `MaxEntryHour = 16`
- `ChannelTimeframe = PERIOD_M5`
- `OpeningChannelBars = 4`
- `EnableM15Fallback = true`
- `MinChannelRange = 2.5`
- `MaxChannelRange = 14.99`
- `SlicedThreshold = 15.0`
- `BreakoutMinTolerancePoints = 0.0`

### `--- Parametros de Stop ---`
- `StopLossIncrement = 20.0`

### `--- Parametros de TP ---`
- `TPMultiplier = 2.0`
- `TPReductionPercent = 10.0`

### `--- Parametros de TP (Complementar) ---`
- `SlicedMultiplier = 1.0`

### `--- Parametros de Risco e Retorno ---`
- `RiskPercent = 1.0`
- `UseInitialDepositForRisk = false`
- `FixedLotAllEntries = 0.0`
- `MinRiskReward = 0.85`
- `DrawdownPercentReference = DD_REF_DAY_BALANCE`
- `ForceDayBalanceDDWhenUnderInitialDeposit = true`
- `MaxDailyDrawdownPercent = 4.0`
- `MaxDrawdownPercent = 8.0`
- `MaxDailyDrawdownAmount = 0.0`
- `MaxDrawdownAmount = 0.0`
- `EnableVerboseDDLogs = true`
- `DDVerboseLogIntervalSeconds = 60`

### `--- Parametros de turnof ---`
- `EnableReversal = true`
- `EnableOvernightReversal = true`
- `ReversalMultiplier = 1.0`
- `ReversalSLDistanceFactor = 3.0`
- `ReversalTPDistanceFactor = 2.8`
- `AllowReversalAfterMaxEntryHour = false`
- `RearmCanceledReversalNextDay = false`

### `--- PCM - Ativacao e Fluxo ---`
- `EnablePCM = false`
- `EnablePCMOnNoTradeLimitTarget = false`
- `PCMMaxOperationsPerDay = 1`
- `PCMIgnoreFirstEntryMaxHour = false`
- `EnablePCMHourLimit = false`
- `PCMEntryMaxHour = 23`
- `PCMEntryMaxMinute = 59`

### `--- PCM - Canal ---`
- `PCMUseMainChannelRangeParams = true`
- `PCMMinChannelRange = 2.5`
- `PCMMaxChannelRange = 14.99`
- `PCMSlicedThreshold = 15.0`
- `PCMChannelBars = 4`
- `PCMReferenceTimeframe = PERIOD_M5`
- `PCMEnableSkipLargeCandle = false`
- `PCMMaxCandlePoints = 0.0`

### `--- PCM - Risco e Alvos ---`
- `PCMRiskPercent = 1.0`
- `PCMTPReductionPercent = 10.0`
- `PCMNegativeAddTPDistancePercent = 100.0`

### `--- PCM - Gestao de Posicao ---`
- `BreakEven = false`
- `PCMBreakEvenTriggerPercent = 50.0`
- `TraillingStop = false`

### `--- PCM - Diagnostico ---`
- `EnablePCMVerboseLogs = true`
- `PCMVerboseIntervalSeconds = 60`

### `--- Parametros de Overnight ---`
- `AllowTradeWithOvernight = true`
- `KeepPositionsOvernight = true`
- `KeepPositionsOverWeekend = true`
- `CloseMinutesBeforeMarketClose = 30`

### `--- Modo de Execucao ---`
- `StrictLimitOnly = true`
- `PreferLimitMainEntry = true`
- `PreferLimitReversal = true`
- `PreferLimitOvernightReversal = true`
- `PreferLimitNegativeAddOn = true`
- `AllowMarketFallbackReversal = false`
- `AllowMarketFallbackOvernightReversal = false`

### `--- Parametros de Adicao em Flutuacao Negativa ---`
- `EnableNegativeAddOn = true`
- `NegativeAddMaxEntries = 1`
- `NegativeAddTriggerPercent = 65.0`
- `NegativeAddLotMultiplier = 0.6`
- `NegativeAddUseSameSLTP = true`
- `EnableNegativeAddTPAdjustment = true`
- `NegativeAddTPDistancePercent = 100.0`
- `NegativeAddTPAdjustOnReversal = false`
- `EnableNegativeAddDebugLogs = true`
- `NegativeAddDebugIntervalSeconds = 60`

### `--- Parametros de Interface e Log ---`
- `DrawChannels = true`
- `EnableLogging = true`
- `MagicNumber = 654321`

## Logs JSON gerados pelo EA

No `OnDeinit`, com `EnableLogging=true`, salva:
- `<EA_NAME>_Trades_<SYMBOL>_start_<...>_end_<...>_saved_<...>.json`
- `<EA_NAME>_NoTrades_<SYMBOL>_start_<...>_end_<...>_saved_<...>.json`

Se o nome existir, usa sufixo `_run_N`.

### Trade JSON (campos principais)

- Tempo: `date`, `entry_time`, `trigger_time`, `exit_time`
- Execucao: `direction`, `entry_execution_type`, `timeframe`
- Preco: `entry_price`, `exit_price`, `stop_loss`, `take_profit`
- Canal: `channel_definition_time`, `channel_range`
- Flags: `is_sliced`, `is_reversal`, `is_pcm_operation`, `is_add_operation`, `triggered_reversal`
- Flags PCM de gestao: `pcm_break_even_applied`, `pcm_trailling_stop_applied`
- Encadeamento:
  - `operation_chain_id`, `operation_chain_code`
  - `operation_code` (`first_opN`, `turn_opN`, `pcm_opN`)
  - `add_operation_code` (`add_opN`)
  - `is_first_operation`, `is_turn_operation`
- Add-on: `addon_count`, `addon_total_lots`, `addon_avg_entry_price`, `addon_profit`, `has_addon`
- Metricas: `risk_reward`, `max_adverse_to_sl_percent`, `max_favorable_to_tp_percent`, `max_floating_profit`, `max_floating_drawdown`
- Resultado financeiro:
  - `result`
  - `profit_gross`, `swap`, `commission`, `fee`, `costs_total`
  - `profit_net` e `profit` (mesmo valor liquido)

### No-trades JSON (campos)

Cada item de `no_trade_days` contem:
- Base: `date`, `reason`, `channel_range`, `timeframe`
- Contexto expandido (quando aplicavel):
  - `event_type`, `entry_direction`
  - `limit_price`, `closest_price`, `stop_loss`, `take_profit`
  - `missing_to_limit_points`
  - `rr_max_reached`
  - `rr_min_required`
  - `pcm_armed_from_notrade`

Observacao: os campos de LIMIT cancelada sao preenchidos no evento de cancelamento de pendente por alvo atingido antes do fill (`LIMIT_CANCELED_TARGET_REACHED`) no contexto de primeira entrada.

### Tick drawdown no JSON

Bloco `tick_drawdown.summary` inclui:
- `max_intraday_floating_dd`
- `max_intraday_floating_dd_percent_of_day_balance`
- `max_intraday_dd_plus_limit`
- `max_floating_positions_in_day`, dia e horario do pico

Bloco `tick_drawdown.daily` inclui por dia:
- `day_start_balance`
- `max_floating_dd` e `% sobre saldo do dia`
- `max_pending_limit_risk`
- `max_dd_plus_limit`
- `pending_limit_count_at_combined_peak`
- `max_floating_positions` e horario

Os arquivos tambem incluem `run_config.selected_parameters` com os parametros usados.

## Geracao de relatorio

Script:
- `gerar_relatorio_operacoes_json.ps1`

Uso basico:
```powershell
powershell -ExecutionPolicy Bypass -File .\gerar_relatorio_operacoes_json.ps1 `
  -JsonPath "C:\...\Prime_botV2_Trades_...json"
```

Uso com no-trades explicito:
```powershell
powershell -ExecutionPolicy Bypass -File .\gerar_relatorio_operacoes_json.ps1 `
  -JsonPath "C:\...\Prime_botV2_Trades_...json" `
  -NoTradesJsonPath "C:\...\Prime_botV2_NoTrades_...json"
```

A secao `Dias sem Operacao (NoTrade)` do markdown inclui:
- total de dias sem operacao
- total de LIMIT cancelada antes do fill
- medias de `missing_to_limit_points` e `rr_max_reached` (quando disponiveis)
- tabela detalhada com colunas `Faltou LIMIT (pts)`, `RR Max`, `RR Min`

## Dashboard local

Iniciar:
```powershell
powershell -ExecutionPolicy Bypass -File .\tools\iniciar_trading_dashboard.ps1 -ServerHost 0.0.0.0 -Port 8788 -ReportsDir docs\relatorios\operacoes
```

Acesso local:
- `http://127.0.0.1:8788`

Acesso na rede local (se firewall permitir):
- `http://<ip-da-maquina>:8788`

No dashboard, o dropdown `DD Open Diario (Saldo e Limites)` mostra:
- saldo de abertura de cada dia
- limite maximo diario permitido
- limite maximo geral permitido

## Limites tecnicos atuais

- Sem retry/backoff estruturado por classe de retcode transiente.
- Sem camada dedicada de resiliencia de conectividade (ex.: circuito de pausa/rearm por desconexao).
- Em visualizacao do tester, abrir/forcar chart espelho M1 para PCM pode depender de limitacao do ambiente.

Detalhes de evolucao: `ROADMAP.md`.
