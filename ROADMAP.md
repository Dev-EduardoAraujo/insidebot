# ROADMAP TECNICO - prime_botV2

Baseado no estado atual de `sliced/prime_botV2.mq5` (versao `1.05`).

Objetivo: reduzir divergencia backtest vs live e evoluir observabilidade sem alterar a logica de sinal.

## 0) Atualizacao de baseline (2026-03-03)

- Documentacao revisada contra `sliced/prime_botV2.mq5` atual.
- DD com fallback de referencia ativo:
  - `ForceDayBalanceDDWhenUnderInitialDeposit = true` forca base no saldo do dia quando `saldo_inicio_dia < deposito_inicial`.
- Controle DD+LIMIT em fila ativo:
  - projeta risco de posicoes abertas + pendentes + candidato antes de aceitar novas exposicoes.
- Logs diarios de DD ativos:
  - `DD OPEN [...]` (completo)
  - `DD OPEN SHORT [...]` (resumo rapido)

## 1) Estado atual confirmado no codigo

### 1.1 Funcionalidades ativas
- Canal de abertura com numero de velas configuravel (`OpeningChannelBars`, padrao 4) e fallback M15 opcional.
- Modo normal e modo sliced.
- Entrada principal por RR com bloqueio de horario (`FirstEntryMaxHour`).
- Controle de execucao por tipo de operacao:
  - `StrictLimitOnly`
  - `PreferLimitMainEntry`
  - `PreferLimitReversal`
  - `PreferLimitOvernightReversal`
  - `PreferLimitNegativeAddOn`.
- turnof pre-armada por `STOP` em conta hedge, com fallback de mercado configuravel.
- Estrategia PCM completa:
  - armada apos TP da operacao principal
  - armamento opcional por evento no-trade LIMIT alvo (`EnablePCMOnNoTradeLimitTarget`)
  - canal recalculado a partir da vela do TP
  - timeframe de referencia configuravel (`M1/M5/M15`)
  - filtro opcional de candle grande
  - break even e trailling stop.
- Overnight com opcao de manter/fechar e opcao de operar com snapshot overnight.
- Add-on negativo no modo runtime e no modo por ordens LIMIT.
- Limites de DD diario/maximo em percentual e em valor absoluto.
- Lote fixo opcional para todas as entradas (`FixedLotAllEntries`).
- Base de risco opcional pelo deposito inicial (`UseInitialDepositForRisk`).
- Validacao broker de niveis (`SYMBOL_TRADE_STOPS_LEVEL`/`SYMBOL_TRADE_FREEZE_LEVEL`) em send/modify.
- Filling mode dinamico por simbolo (`IOC`/`FOK`/`RETURN`).
- Recuperacao de estado no startup via leitura de ordens/posicoes do broker (`RecoverRuntimeStateFromBroker`).
- Logs JSON de trades/no-trades com `tick_drawdown` e `run_config.selected_parameters`.

### 1.2 Robustez e observabilidade ja implementadas
- Suporte a multiplas posicoes por operacao (hedging/add-on) com agregacao de PnL.
- Snapshot de overnight para continuidade entre dias.
- Nome de arquivo unico de log (`_run_N`) para evitar sobrescrita.
- Encadeamento de operacao por `operation_chain_id` e codigos:
  - `first_opN`
  - `turn_opN`
  - `pcm_opN`
  - `add_opN`.
- Normalizacao de preco por tick size (`SYMBOL_TRADE_TICK_SIZE`).
- Telemetria de no-trade para LIMIT cancelada por alvo atingido antes do fill:
  - `missing_to_limit_points`
  - `rr_max_reached`
  - `rr_min_required`
  - `event_type = LIMIT_CANCELED_TARGET_REACHED`
  - `pcm_armed_from_notrade`.
- Kill-switch de seguranca para posicao sem SL valida.

## 2) Matriz de gap tecnico

Legenda:
- `OK`: implementado
- `PARCIAL`: implementado com limitacoes
- `GAP`: nao implementado

| Tema | Status | Observacao tecnica |
|---|---|---|
| Controle de DD diario/max (% e absoluto) | OK | Bloqueios aplicados em entradas, pendentes, turnof e add-on |
| Log detalhado de trade e parametros | OK | Inclui trigger, addon, cadeia de operacao, MFE/MAE, custos |
| DD tick a tick + DD+LIMIT | OK | Blocos `tick_drawdown.summary` e `tick_drawdown.daily` |
| Suporte overnight + politica sem overnight | OK | Fechamento por janela + snapshots |
| turnof com pre-armamento | OK | `BuyStop/SellStop` + adocao do ticket acionado |
| Estrategia PCM | OK | Armamento por TP, novo CA por candle do TP, limites de horario/quantidade |
| Telemetria de LIMIT cancelada em no-trade | PARCIAL | Coberta no evento de alvo atingido antes do fill; ainda pode expandir para mais contextos |
| Deteccao de SL/TP | PARCIAL | Boa cobertura com fallback por distancia em cenarios limite |
| Idempotencia de envio | PARCIAL | Flags e tickets reduzem duplicidade; sem chave persistente global |
| Reconciliacao de estado no startup | PARCIAL | Recupera estado principal, mas sem trilha persistida entre reinicios abruptos |
| Tratamento de retcode por politica | PARCIAL | Sem retry/backoff estruturado por classe de erro |
| Partial fill handling | OK | `TRADE_RETCODE_DONE_PARTIAL` aceito como sucesso operacional |
| Validacao `STOPS_LEVEL`/`FREEZE_LEVEL` | OK | Checagem ativa para send/modify |
| Filling mode adaptativo por simbolo | OK | Resolve automaticamente `IOC/FOK/RETURN` conforme simbolo |
| Tratamento de conectividade e resync | GAP | Sem politica dedicada de pausa/resync |

## 3) Prioridades recomendadas

### P0 - Hardening operacional (sem alterar sinal)
1. Adicionar retry/backoff por classe de retcode transiente.
2. Adicionar politica de pausa/rearm em perda de conectividade.
3. Evoluir idempotencia para chave persistida entre reinicios.

### P1 - Observabilidade de execucao
1. Expandir telemetria de LIMIT cancelada para todos os contextos (turnof/overnight/add-on/PCM).
2. Log estruturado de ordem (`send/cancel/modify/fill`) com bid/ask/spread.
3. Metricas de LIMIT por contexto: `touch_count`, `fill_count`, `miss_fill_count`, `touch_to_fill_ms`.
4. Relatorio de reconciliacao entre estado local e estado do servidor apos restart.

### P2 - Paridade de teste
1. Emulacao opcional de execucao no tester (latencia, miss fill, parcial).
2. Protocolo A/B/C de comparacao (baseline, spread stress, emulator).
3. Comparacao padrao com conta demo no mesmo broker/servidor.

## 4) Regras para preservar logica de sinal

1. Nao alterar regra de canal, breakout, sliced e fallback M15.
2. Nao alterar formula base de RR nem criterio de entrada de sinal.
3. Nao alterar o conceito de PCM/turnof/add-on; atuar na camada de execucao/controle.
4. Priorizar robustez operacional, logging e consistencia de estado.

## 5) Criterio de pronto

1. P0 implementado sem regressao no baseline.
2. P1 implementado com trilha suficiente para auditar cada trade.
3. Divergencias backtest vs demo explicadas por friccao de execucao.
4. Runbook atualizado para operacao em conta real.
