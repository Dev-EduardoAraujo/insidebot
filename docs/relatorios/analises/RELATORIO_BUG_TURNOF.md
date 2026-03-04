# 🐛 RELATÓRIO DE BUG - Viradas de Mão Não Logadas

**Data:** 18/02/2026  
**Projeto:** SlicedEA - Expert Advisor MetaTrader 5  
**Versão:** 1.01  
**Arquivo:** `sliced/SlicedEA.mq5`  
**Severidade:** ALTA - Perda de dados críticos para análise

---

## 📋 RESUMO EXECUTIVO

As operações de **turnof** (reversal trades) estão sendo **executadas corretamente** no MetaTrader 5, mas **NÃO estão sendo registradas nos logs JSON** com a flag `"is_reversal": true`. 

Todas as 100+ operações no backtest aparecem com `"is_reversal": false`, mesmo quando o histórico do MT5 mostra claramente operações com comentário "turnof".

---

## 🔍 EVIDÊNCIAS DO PROBLEMA

### Histórico MT5 (Screenshot_78)
Operações com comentário **"turnof"** identificadas:
- Ticket #36 - turnof
- Ticket #54 - turnof  
- Ticket #60 - turnof
- Ticket #64 - turnof
- Ticket #72 - turnof
- Ticket #80 - turnof

### Log JSON Atual
```json
// TODAS as 131 operações aparecem assim:
{
  "is_reversal": false,
  "triggered_reversal": true/false
}

// NENHUMA operação tem:
{
  "is_reversal": true  // ← DEVERIA EXISTIR
}
```

### Arquivo de Log
- **Caminho:** `C:\Users\Eduardo\AppData\Roaming\MetaQuotes\Tester\...\SlicedEA_Trades_XAUUSD.h_20260218_235959.json`
- **Total de Trades:** 131
- **Viradas de Mão Esperadas:** ~28 (baseado em `triggered_reversal: true`)
- **Viradas de Mão Logadas:** 0

---

## 🎯 COMPORTAMENTO ESPERADO vs REAL

### ✅ Esperado
Quando uma turnof é executada:
1. `ExecuteReversal()` é chamado
2. Flag `g_tradeReversal = true` é definida
3. Operação é executada com comentário "turnof"
4. Ao fechar, `LogTrade()` registra com `"is_reversal": true`

### ❌ Real
1. ✅ `ExecuteReversal()` é chamado (confirmado pelos tickets no MT5)
2. ✅ Flag `g_tradeReversal = true` é definida (código presente)
3. ✅ Operação é executada (tickets existem)
4. ❌ `LogTrade()` registra com `"is_reversal": false` (BUG)

---

## 🔧 ARQUITETURA DO SISTEMA DE LOGGING

### Variáveis Globais Relevantes
```mql5
// Linha ~70-75
datetime g_tradeEntryTime = 0;
double g_tradeEntryPrice = 0;
bool g_tradeSliced = false;
bool g_tradeReversal = false;  // ← FLAG CRÍTICA
```

### Fluxo de Execução

#### 1. Primeira Operação Fecha com SL
```mql5
CheckPositionStatus() {
  // Detecta que posição fechou
  // Verifica se foi SL
  if(wasStopLoss && EnableReversal) {
    ExecuteReversal();  // ← Chama virada
  }
}
```

#### 2. turnof é Executada
```mql5
ExecuteReversal() {
  // Define flags
  g_tradeEntryTime = TimeCurrent();
  g_tradeEntryPrice = price;
  g_tradeReversal = true;  // ← DEFINE AQUI
  g_tradeSliced = (g_cycle1Direction == "BOTH");
  g_firstTradeStopLoss = stopLoss;
  g_firstTradeTakeProfit = takeProfit;
  
  // Executa ordem
  trade.Buy/Sell(..., "turnof");
}
```

#### 3. Virada Fecha e Deve Ser Logada
```mql5
CheckPositionStatus() {
  // Detecta que virada fechou
  
  // PROBLEMA: Aqui g_tradeReversal pode estar false
  LogTrade(exitTime, exitPrice, profit, hitTP);
}
```

#### 4. Função de Log
```mql5
LogTrade(...) {
  // Usa g_tradeReversal para criar JSON
  tradeJson += "\"is_reversal\": " + (g_tradeReversal ? "true" : "false");
  
  // PROBLEMA: g_tradeReversal está false quando deveria ser true
}
```

---

## 🧪 TENTATIVAS DE CORREÇÃO REALIZADAS

### Tentativa #1: Recuperação do Histórico
**Objetivo:** Buscar dados do histórico quando `g_tradeEntryTime == 0`

```mql5
// CheckPositionStatus() - Linha ~1050
if(entryTime == 0 && HistorySelectByPosition(g_currentTicket)) {
  // Buscar dados do deal de entrada
  // Verificar comentário para detectar virada
  string comment = HistoryDealGetString(dealTicket, DEAL_COMMENT);
  if(StringFind(comment, "Virada") >= 0) {
    isReversal = true;
  }
}
```

**Resultado:** ❌ Não funcionou

### Tentativa #2: Preservação de Flags
**Objetivo:** Garantir que flags sejam preservadas durante o log

```mql5
// CheckPositionStatus() - Linha ~1070
bool isReversal = g_tradeReversal;
bool isSliced = g_tradeSliced;

// Restaurar temporariamente
g_tradeReversal = isReversal;
g_tradeSliced = isSliced;
LogTrade(...);
```

**Resultado:** ❌ Não funcionou

### Tentativa #3: Debug Logs
**Objetivo:** Adicionar logs para rastrear o estado das flags

```mql5
// ExecuteReversal() - Linha ~1200
Print("📋 FLAGS DEFINIDAS: g_tradeReversal=", g_tradeReversal, 
      " | g_tradeSliced=", g_tradeSliced);

// CheckPositionStatus() - Linha ~1045
Print("📋 DEBUG ANTES DE LOGAR:");
Print("  g_tradeReversal=", g_tradeReversal);
Print("  g_tradeSliced=", g_tradeSliced);
```

**Resultado:** ❌ Não funcionou (logs não foram verificados ainda)

---

## 🤔 HIPÓTESES SOBRE A CAUSA RAIZ

### Hipótese #1: Reset Diário Prematura
**Descrição:** `ResetDaily()` pode estar zerando as flags antes do log

```mql5
// ResetDaily() - Linha ~1250
if(!hasAnyOvernight) {
  g_tradeEntryTime = 0;
  g_tradeEntryPrice = 0;
  g_tradeSliced = false;
  g_tradeReversal = false;  // ← PODE SER RESETADO CEDO DEMAIS
}
```

**Probabilidade:** ALTA  
**Impacto:** Se a virada fecha no dia seguinte, flags são resetadas

### Hipótese #2: Ordem de Execução no OnTick()
**Descrição:** `CheckNewDay()` pode executar antes de `CheckPositionStatus()`

```mql5
void OnTick() {
  CheckNewDay();           // ← Reseta flags primeiro?
  CheckPositionStatus();   // ← Tenta logar depois?
  ProcessStrategy();
}
```

**Probabilidade:** MÉDIA  
**Impacto:** Flags resetadas antes do log ser gerado

### Hipótese #3: Posições Overnight
**Descrição:** Viradas que viram overnight perdem as flags

```mql5
// ResetDaily() - Linha ~1280
if(g_currentTicket > 0 && PositionSelectByTicket(g_currentTicket)) {
  // Move para overnight
  g_overnightTicket = g_currentTicket;
  g_currentTicket = 0;
  
  // MAS: flags podem não ser preservadas corretamente
}
```

**Probabilidade:** ALTA  
**Impacto:** Viradas overnight não são identificadas como reversal

### Hipótese #4: Múltiplas Chamadas de LogTrade()
**Descrição:** `LogTrade()` pode ser chamado múltiplas vezes, sobrescrevendo dados

**Probabilidade:** BAIXA  
**Impacto:** Primeira chamada correta, segunda incorreta

### Hipótese #5: Problema no Backtest vs Live
**Descrição:** Comportamento diferente em backtest (modo visual vs rápido)

**Probabilidade:** MÉDIA  
**Impacto:** Flags não persistem entre ticks no backtest

---

## 🔬 INVESTIGAÇÃO NECESSÁRIA

### 1. Análise de Logs do Terminal
**Ação:** Executar backtest e capturar TODOS os prints do terminal

**Buscar por:**
```
"📋 FLAGS DEFINIDAS: g_tradeReversal=true"
"📋 DEBUG ANTES DE LOGAR: g_tradeReversal=true"
"✅ turnof executada!"
"🔔 Posição XXX foi fechada"
```

**Objetivo:** Confirmar se flags estão sendo definidas e quando são perdidas

### 2. Rastreamento de Estado
**Ação:** Adicionar log em TODOS os pontos que modificam `g_tradeReversal`

**Locais:**
- `ExecuteReversal()` - Define como true
- `ResetDaily()` - Pode resetar para false
- `ExecuteMarketOrder()` - Define como false (primeira operação)
- Qualquer outro local que modifique a variável

### 3. Teste Isolado
**Ação:** Criar versão simplificada que APENAS:
1. Executa primeira operação
2. Força SL
3. Executa virada
4. Loga resultado

**Objetivo:** Isolar o problema sem complexidade de overnight, M15, etc

### 4. Comparação de Tickets
**Ação:** Cruzar dados do MT5 com o log JSON

**Criar tabela:**
| Ticket | Comentário MT5 | is_reversal JSON | Match? |
|--------|----------------|------------------|--------|
| 36     | turnof  | false            | ❌     |
| 54     | turnof  | false            | ❌     |

### 5. Análise de Timing
**Ação:** Verificar QUANDO cada função é chamada

**Adicionar timestamps:**
```mql5
Print("[", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS), "] ExecuteReversal()");
Print("[", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS), "] ResetDaily()");
Print("[", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS), "] LogTrade()");
```

---

## 📊 DADOS PARA ANÁLISE

### Configuração do Backtest
```
Símbolo: XAUUSD
Período: 01/07/2025 - 18/02/2026 (7.5 meses)
Timeframe: M5
EnableReversal: true
ReversalMultiplier: 2.0
AllowTradeWithOvernight: true
EnableLogging: true
```

### Estatísticas
- Total de Operações: 131
- Operações com `triggered_reversal: true`: 28
- Operações com `is_reversal: true`: 0 ❌
- Win Rate: 67%
- Profit Factor: 1.55

### Arquivos Relevantes
1. **Código Fonte:** `C:\Users\Eduardo\PycharmProjects\bot_MT5\sliced\SlicedEA.mq5`
2. **Log JSON:** `C:\Users\Eduardo\AppData\Roaming\MetaQuotes\Tester\...\SlicedEA_Trades_XAUUSD.h_20260218_235959.json`
3. **Screenshot:** `Screenshot_78` (histórico MT5 com comentários)

---

## 🎯 SOLUÇÃO ESPERADA

### Comportamento Correto
Quando uma turnof fecha, o log deve conter:

```json
{
  "date": "2025.07.23",
  "entry_time": "2025.07.23 04:16",
  "exit_time": "2025.07.23 08:30",
  "direction": "ORDER_TYPE_SELL",
  "is_reversal": true,        // ← DEVE SER TRUE
  "triggered_reversal": false,
  "result": "TP",
  "profit": 850.00
}
```

### Critérios de Sucesso
1. ✅ Todas as viradas de mão têm `"is_reversal": true`
2. ✅ Número de viradas no log = número de viradas no MT5
3. ✅ Flags preservadas mesmo com overnight
4. ✅ Funciona em backtest e live

---

## 🚨 IMPACTO DO BUG

### Análise Comprometida
- ❌ Impossível calcular win rate de viradas de mão
- ❌ Impossível avaliar efetividade da estratégia de reversal
- ❌ Dados de performance incompletos
- ❌ Decisões de otimização baseadas em dados incorretos

### Financeiro
- ⚠️ Estratégia pode estar perdendo dinheiro em viradas
- ⚠️ Sem dados, impossível saber se desabilitar reversal seria melhor

---

## 📝 PRÓXIMOS PASSOS RECOMENDADOS

### Prioridade CRÍTICA
1. **Executar novo backtest com logs de debug ativos**
   - Capturar TODOS os prints do terminal
   - Salvar em arquivo de texto
   - Analisar sequência de eventos

2. **Rastrear estado de `g_tradeReversal`**
   - Adicionar log em TODA modificação da variável
   - Identificar ONDE e QUANDO ela é resetada incorretamente

3. **Testar cenário isolado**
   - Criar EA simplificado apenas para testar virada
   - Confirmar que problema existe mesmo em código mínimo

### Prioridade ALTA
4. **Revisar lógica de overnight**
   - Verificar se flags são preservadas corretamente
   - Testar com `AllowTradeWithOvernight = false`

5. **Comparar backtest vs live**
   - Testar em conta demo
   - Verificar se problema persiste

### Prioridade MÉDIA
6. **Refatorar sistema de logging**
   - Considerar salvar flags em estrutura separada
   - Implementar sistema de persistência mais robusto

---

## 🔧 CÓDIGO RELEVANTE

### ExecuteReversal() - Linha ~1180
```mql5
void ExecuteReversal() {
  // ... validações ...
  
  if(result && trade.ResultRetcode() == TRADE_RETCODE_DONE) {
    g_currentTicket = trade.ResultOrder();
    g_currentOrderType = reversalType;
    g_reversalTradeExecuted = true;
    
    // CRÍTICO: Define flags aqui
    g_tradeEntryTime = TimeCurrent();
    g_tradeEntryPrice = price;
    g_tradeReversal = true;  // ← DEVE PERMANECER TRUE
    g_tradeSliced = (g_cycle1Direction == "BOTH");
    g_firstTradeStopLoss = stopLoss;
    g_firstTradeTakeProfit = takeProfit;
  }
}
```

### CheckPositionStatus() - Linha ~1000
```mql5
void CheckPositionStatus() {
  if(!PositionSelectByTicket(g_currentTicket)) {
    // Posição fechou
    
    // PROBLEMA: g_tradeReversal pode estar false aqui
    if(EnableLogging) {
      LogTrade(TimeCurrent(), exitPrice, profit, !wasStopLoss);
    }
  }
}
```

### LogTrade() - Linha ~1350
```mql5
void LogTrade(...) {
  // USA g_tradeReversal para criar JSON
  tradeJson += "\"is_reversal\": " + (g_tradeReversal ? "true" : "false");
  
  // PROBLEMA: Valor está incorreto
}
```

### ResetDaily() - Linha ~1230
```mql5
void ResetDaily() {
  // SUSPEITO: Pode resetar flags prematuramente
  if(!hasAnyOvernight) {
    g_tradeReversal = false;  // ← PODE SER O PROBLEMA
  }
}
```

---

## 💡 SUGESTÕES DE CORREÇÃO

### Opção 1: Persistência Explícita
```mql5
// Criar estrutura para armazenar dados da operação
struct TradeData {
  datetime entryTime;
  double entryPrice;
  bool isReversal;
  bool isSliced;
};

TradeData g_currentTradeData;

// Salvar ao executar
void ExecuteReversal() {
  g_currentTradeData.isReversal = true;
  // ...
}

// Usar ao logar
void LogTrade() {
  bool isReversal = g_currentTradeData.isReversal;
  // ...
}
```

### Opção 2: Detecção pelo Comentário
```mql5
// Sempre buscar do histórico
void LogTrade() {
  string comment = GetDealComment(g_currentTicket);
  bool isReversal = (StringFind(comment, "Virada") >= 0);
  // ...
}
```

### Opção 3: Flag Persistente
```mql5
// Usar variável que NÃO é resetada
ulong g_reversalTicket = 0;  // Ticket da virada

void ExecuteReversal() {
  g_reversalTicket = trade.ResultOrder();
}

void LogTrade() {
  bool isReversal = (g_currentTicket == g_reversalTicket);
}
```

---

## 📞 CONTATO E INFORMAÇÕES

**Desenvolvedor:** Eduardo  
**Projeto:** bot_MT5  
**Plataforma:** MetaTrader 5  
**Linguagem:** MQL5  
**Data do Relatório:** 18/02/2026

---

## ✅ CHECKLIST PARA O ESPECIALISTA

- [ ] Ler todo o relatório
- [ ] Executar backtest com logs de debug
- [ ] Capturar e analisar prints do terminal
- [ ] Identificar ONDE `g_tradeReversal` é resetado incorretamente
- [ ] Identificar QUANDO isso acontece (timing)
- [ ] Testar cenário isolado (EA simplificado)
- [ ] Implementar correção
- [ ] Validar com novo backtest
- [ ] Confirmar que viradas aparecem com `is_reversal: true`
- [ ] Documentar solução encontrada

---

**FIM DO RELATÓRIO**

*Este documento contém todas as informações necessárias para investigação profunda e resolução do bug. Favor investigar com atenção especial às hipóteses #1 e #3, que parecem mais prováveis.*
