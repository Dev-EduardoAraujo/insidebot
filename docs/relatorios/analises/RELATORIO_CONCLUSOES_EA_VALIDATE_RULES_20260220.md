# RELATORIO DE CONCLUSOES - VALIDACAO BACKTEST VS LIVE

Data: 2026-02-20
Projeto: `bot_MT5`
EA analisado: `sliced/SlicedEA.mq5`
Fonte de recomendacoes: `ea_validate_rules`

## 1) Objetivo

Avaliar se as consideracoes do especialista fazem sentido para o SlicedEA, o que ja esta implementado, o que ainda falta, e qual o impacto esperado ao aplicar cada melhoria.

## 2) Metodo de avaliacao

1. Leitura completa do documento `ea_validate_rules`.
2. Auditoria do codigo atual do EA (`SlicedEA.mq5`).
3. Mapeamento item a item: Aderente, Parcial, ou Gap.
4. Analise de impacto tecnico e operacional sem alterar logica de sinal.

## 3) Resumo executivo

Conclusao geral:
- As recomendacoes do especialista fazem sentido para reduzir divergencia backtest/live.
- O EA ja tem boa base de controle de estado, overnight, addon e logging de trade.
- Os principais gaps estao na camada de execucao real (tick size, stop/freeze, retry/backoff, touch vs fill, resync de startup).

Classificacao geral:
- Aderente: 6 temas
- Parcial: 8 temas
- Gap: 7 temas

Ponto importante de contexto:
- O documento do especialista assume LIMIT-only.
- O SlicedEA atual nao e LIMIT-only: ele usa mercado em varios caminhos (entrada com RR suficiente, virada, virada overnight, addon).
- Portanto, parte da analise LIMIT-only precisa ser adaptada para o comportamento hibrido atual.

## 4) Matriz consolidada (recomendacao x estado atual)

| Tema do especialista | Faz sentido no SlicedEA? | Estado atual | Evidencia no codigo | Impacto ao aplicar |
|---|---|---|---|---|
| Touch != Fill (LIMIT) | Sim | Gap | Fluxo LIMIT sem metrica touch/fill estruturada (`CheckPendingOrderExecution`, linhas 860-995) | Melhora diagnostico; nao muda sinal |
| Partial Fill | Sim | Parcial | `DONE_PARTIAL` aceito em addon/close (`1938`, `2341`), mas nao em todos fluxos de abertura/virada (`764`, `842`, `3231`, `3340`) | Pode evitar perda de eventos de execucao parcial |
| Spread variavel | Sim | Parcial | Usa BID/ASK em entradas e verificacoes, mas sem coleta estruturada de spread por evento | Mais visibilidade; possivel filtro futuro |
| Retcodes + retry/backoff | Sim | Gap | Ha logs de retcode, sem politica de retry por tipo de erro | Menos falhas operacionais, possivel atraso de execucao |
| Latencia e ordem de eventos | Sim | Parcial | Fluxo serial e flags ajudam, mas sem camada dedicada de latencia/retry | Menos race conditions em live |
| Stop Level / Freeze Level | Sim | Gap | Nao ha checagem explicita de `SYMBOL_TRADE_STOPS_LEVEL` e `SYMBOL_TRADE_FREEZE_LEVEL` antes de enviar/modificar | Reduz rejeicoes, pode reduzir trades executados |
| Tick size e normalizacao | Sim | Gap | Normaliza por `SYMBOL_DIGITS` (`750-752`, `806-810`, `3214-3216`, `3330-3332`) | Menos `INVALID_PRICE`; pequena mudanca de preco final |
| Leitura de propriedades do simbolo | Sim | Parcial | Le volume/point/tick value no `OnInit` (`179-184`), mas nao le stops/freeze/filling mode dinamico | Execucao mais aderente ao broker |
| Servidor como fonte da verdade | Sim | Parcial | Forte no fechamento/overnight/historico (`2471+`, `2681+`), mas sem resync completo no startup | Mais resiliencia apos restart |
| Idempotencia anti-duplicidade | Sim | Parcial | Flags/tickets (`g_pendingOrderPlaced`, `g_currentTicket`, arrays) ajudam, sem chave persistente de intencao | Menos risco de duplicidade em cenarios extremos |
| Controle de concorrencia de trade | Sim | Parcial | `SetAsyncMode(false)` no `OnInit` (`189`) e fluxo serial, sem fila formal de acoes | Mais determinismo |
| Definicao BID/ASK para LIMIT touch | Sim | Parcial | Usa BID/ASK para cancelamento por alvo (`894-925`), mas nao loga touch formal | Diagnostico de misses de fill |
| Expiracao por horario de servidor | Sim | Aderente | LIMIT com `ORDER_TIME_DAY` (`838-840`) e tempo principal por `TimeCurrent` | Boa aderencia operacional |
| Politica de erro por retcode | Sim | Gap | Nao ha switch por retcode com acao definida | Menor resiliencia em live |
| Conectividade terminal/servidor | Sim | Gap | Nao ha tratamento `TERMINAL_CONNECTED` | Risco de estado inconsistente em desconexao |
| Metrics de execucao (touch/fill/delay) | Sim | Gap | JSON de trade e rico, mas sem telemetria de tentativa de ordem | Diagnostico incompleto de divergencia |
| Execution emulator (tester) | Sim | Gap | Nao implementado | Backtest pode ficar otimista vs live |
| Logs de run params | Sim | Aderente | `BuildRunConfigJson` grava params usados (`3643+`) | Excelente para reproducibilidade |
| Sem sobrescrever logs | Sim | Aderente | Nome unico por `BuildUniqueFileName` (`3627+`) | Evita perda de historico |
| Limites de DD diario/max | Sim | Aderente | Bloqueio percentual e absoluto (`1202+`) e checks no addon (`1862+`) | Controla risco operacional |

## 5) Observacoes tecnicas relevantes do codigo atual

## 5.1 Pontos fortes

1. Controle de risco por DD ja bem distribuido no fluxo:
- `ProcessStrategy` (`351`)
- aberturas (`695`, `745`, `798`)
- pendente executada (`974`)
- viradas (`3180`, `3275`)
- addon com limites percentuais e absolutos (`1862-1890`)

2. Logging de trades robusto para analise estatistica:
- `trigger_time`, `entry_execution_type`, `channel_definition_time`, `max_floating_profit`, `max_floating_drawdown`, `max_adverse_to_sl_percent`, blocos addon e `run_config`.

3. Tratamento overnight evoluido:
- snapshots por ticket (`AddOvernightLogSnapshot`, `2115+`)
- log de fechamento overnight com recuperacao de historico (`LogClosedOvernightTrade`, `2471+`)

4. Nao sobrescrever arquivos:
- `BuildUniqueFileName` com sufixo `_run_N` (`3627-3641`)

## 5.2 Gaps principais para reduzir divergencia live

1. Falta de normalizacao por tick size do simbolo.
2. Falta de validacao explicita de stop/freeze level.
3. Falta de retry/backoff por retcode.
4. Falta de telemetria touch/fill e latencia de ordem.
5. Falta de resync completo no startup (rebuild por magic+symbol).
6. Filling mode fixo (`ORDER_FILLING_IOC`) sem adaptacao por simbolo/conta (`188`).

## 6) O que pode ser aplicado e impacto no funcionamento

## 6.1 Aplicar primeiro (baixo risco estrategico)

1. `RoundToTick` por `SYMBOL_TRADE_TICK_SIZE` para preco/SL/TP.
- Impacto: melhora tecnica de envio de ordem.
- Efeito em resultado: pequeno ajuste de preco de execucao.

2. Validacao pre-trade de stop level e freeze level.
- Impacto: menos ordens rejeitadas.
- Efeito em resultado: alguns trades podem ser bloqueados/adiados quando inviaveis.

3. Politica de retcode com retry/backoff controlado.
- Impacto: maior robustez em live.
- Efeito em resultado: possivel atraso em ordens sob instabilidade.

4. Telemetria de execucao (tentativa, retcode, bid/ask/spread, tempo).
- Impacto: melhora de diagnostico.
- Efeito em resultado: nenhum direto (somente log).

## 6.2 Aplicar em segunda etapa (impacto moderado)

1. Resync no startup:
- Reconstruir estado de ordens/posicoes pelo servidor (magic+symbol).
- Impacto: reduz divergencia apos restart/desconexao.

2. Harmonizar tratamento de `DONE_PARTIAL` em todos os fluxos de abertura/virada.
- Impacto: evita perda de estados de execucao parcial.

3. Selecao dinamica de filling mode por capacidade do simbolo.
- Impacto: menos incompatibilidades por broker.

## 6.3 Aplicar para validacao de laboratorio (nao live)

1. Execution Emulator no tester (fill miss, latencia, reject, partial).
- Impacto: backtest mais conservador e mais proximo do live.
- Efeito em resultado: normalmente reduz PnL de backtest e aumenta realismo.

## 7) Itens do especialista que nao se aplicam 100% como descritos

1. Premissa LIMIT-only.
- O SlicedEA atual e hibrido (MARKET + LIMIT), entao:
  - analise touch/fill continua importante para LIMIT,
  - mas divergencia live tambem depende dos fluxos MARKET (entrada, virada, addon).

2. Slippage apenas em saida.
- No SlicedEA, entradas a mercado tambem sao relevantes e devem entrar no diagnostico de execucao.

## 8) Risco de nao tratar os gaps

1. Divergencia persistente entre backtest e live por motivos tecnicos.
2. Dificuldade para explicar perdas de fill/rejeicoes com dados objetivos.
3. Maior chance de comportamento inconsistente apos restart/desconexao.
4. Backtest otimista sem representar friccao real de execucao.

## 9) Conclusao final

As recomendacoes do especialista sao tecnicamente corretas para o objetivo de aproximar backtest de live.

Para o SlicedEA atual:
- Boa parte da base de estado/log/risco ja existe e esta madura.
- Os principais ganhos agora estao na camada de execucao (validacoes pre-trade, retcode policy, tick size, resync e telemetria de execucao).
- Isso pode ser aplicado sem mudar a regra de sinal do bot, mas pode reduzir quantidade de trades executados em cenarios que hoje passariam com validacoes menos estritas.

Em resumo: as melhorias sao aplicaveis, recomendadas e devem aumentar confiabilidade operacional em live.

