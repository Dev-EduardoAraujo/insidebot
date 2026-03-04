# Auditoria Operacional para Comercializacao - prime_botV2

Data: 2026-03-03  
Arquivo auditado: `sliced/prime_botV2.mq5`

## Escopo da auditoria
- Risco de estouro de regras de DD (diario, maximo, DD+LIMIT).
- Risco de loop infinito ou envio repetido de ordens.
- Risco operacional grave em runtime live.

## Parecer executivo
- O EA esta tecnicamente robusto em varios pontos (validacao de SL antes de envio, kill-switch para posicao sem SL, checagem DD+LIMIT pre-open e pos-open, protecoes anti-repeticao).
- Nao recomendo comercializar como "protection-grade" para conta live sem corrigir os achados `CRITICO` e `ALTO` abaixo.

## Achados

### CRITICO-1: Limites de DD podem ser "resetados" ao reiniciar o EA
- Impacto: em live, reiniciar o EA no meio do dia redefine baseline de DD diario e pico de DD maximo. Isso pode permitir nova exposicao apesar de perda acumulada no dia.
- Evidencia:
  - `sliced/prime_botV2.mq5:2545`
  - `sliced/prime_botV2.mq5:2546`
  - `sliced/prime_botV2.mq5:10294`
  - `sliced/prime_botV2.mq5:10295`
  - `sliced/prime_botV2.mq5:164`
  - `sliced/prime_botV2.mq5:2934`
- Causa: estado de DD e baseline diario nao persistem entre reinicios.

### ALTO-1: DD diario/maximo nao e "latched" apos breach
- Impacto: se DD ultrapassa limite e depois recupera, o bloqueio pode deixar de atuar e o bot volta a operar. Em regras estritas de risco (prop/live), isso e inadequado.
- Evidencia:
  - `sliced/prime_botV2.mq5:6103`
  - `sliced/prime_botV2.mq5:6115`
  - `sliced/prime_botV2.mq5:6124`
  - `sliced/prime_botV2.mq5:6462`
- Causa: o bloqueio usa drawdown corrente, sem memorizar breach do dia/sessao.

### ALTO-2: Politica sem overnight depende de tick no horario de corte
- Impacto: se nao houver tick apos `triggerTime` antes do fechamento, posicoes/pendentes podem passar overnight mesmo com politica de fechamento ativa.
- Evidencia:
  - `sliced/prime_botV2.mq5:2822`
  - `sliced/prime_botV2.mq5:2842`
  - `sliced/prime_botV2.mq5:8634`
  - `sliced/prime_botV2.mq5:8646`
  - `sliced/prime_botV2.mq5:8665`
- Causa: enforcement ocorre em `OnTick` apenas.

### ALTO-3: DD+LIMIT contabiliza ordens sem SL como risco zero
- Impacto: em conta com ordens/posicoes sem SL, o risco projetado pode ficar subestimado e permitir novas entradas acima do risco real.
- Evidencia:
  - `sliced/prime_botV2.mq5:5588`
  - `sliced/prime_botV2.mq5:5618`
  - `sliced/prime_botV2.mq5:5658`
  - `sliced/prime_botV2.mq5:5660`
  - `sliced/prime_botV2.mq5:5742`
  - `sliced/prime_botV2.mq5:5743`
- Causa: quando SL falta, o sistema conta ocorrencia (`missingSL`) mas nao imputa risco financeiro.

### MEDIO-1: Anti-duplicacao de envio e temporal e volatil
- Impacto: em retcodes ambiguos/reconexao/restart, pode haver nova tentativa de envio apos cooldown curto, gerando potencial duplicidade operacional.
- Evidencia:
  - `sliced/prime_botV2.mq5:5074`
  - `sliced/prime_botV2.mq5:5089`
  - `sliced/prime_botV2.mq5:5092`
  - `sliced/prime_botV2.mq5:5024`
  - `sliced/prime_botV2.mq5:10300`
- Causa: guarda de idempotencia em memoria, com cooldown de segundos, sem persistencia transacional.

### MEDIO-2: Recuperacao de estado com direcoes opostas e parcial
- Impacto: ao reiniciar com exposicoes opostas (mesmo magic/symbol), o EA adota apenas a direcao mais recente e pode deixar exposicao fora do ciclo gerenciado.
- Evidencia:
  - `sliced/prime_botV2.mq5:5322`
  - `sliced/prime_botV2.mq5:5410`
  - `sliced/prime_botV2.mq5:5427`
  - `sliced/prime_botV2.mq5:5470`
- Causa: estrategia de recovery prioriza "ticket mais recente" em conflito de direcao.

## Verificacoes de seguranca que passaram
- Nao identifiquei loop infinito estrutural no codigo principal.
- Loops `while` encontrados tem condicao de saida:
  - `sliced/prime_botV2.mq5:1317`
  - `sliced/prime_botV2.mq5:5904`
  - `sliced/prime_botV2.mq5:10528`
- Envio de ordem passa por validacao de SL nos fluxos principais de entrada/turnof/ADON/pendentes.
- Existe kill-switch para anomalia de SL em posicao/pendente:
  - `sliced/prime_botV2.mq5:8505`
  - `sliced/prime_botV2.mq5:8604`

## Recomendacoes para liberar comercialmente
1. Persistir baseline de DD diario e pico maximo por data/sessao (GlobalVariable/File), restaurando no `OnInit`.
2. Implementar latch de breach:
   - `daily_breached_today`
   - `max_breached_session`
   Uma vez atingido, bloquear novas entradas ate reset formal definido.
3. Endurecer no-overnight:
   - adicionar `OnTimer` para enforcement de cutoff independente de tick.
   - opcionalmente fechar antecipado com margem de seguranca adicional.
4. Em DD+LIMIT, quando `openMissingSLCount > 0` ou `pendingMissingSLCount > 0`, bloquear novas entradas por fail-safe.
5. Idempotencia forte:
   - chave persistida por intencao de ordem (nonce/UUID de estrategia) e reconciliacao apos restart.
6. Em recovery com direcoes opostas:
   - bloquear trading e exigir saneamento automatico ou manual antes de continuar.

## Conclusao
- Estado atual: bom para pesquisa/backtest e operacao assistida.
- Para comercializacao com promessa de controle de risco robusto em live, faltam hardenings obrigatorios nos itens `CRITICO` e `ALTO`.
