//+------------------------------------------------------------------+
//|                                                   prime_bot.mq5 |
//|                               Estrategia de Canais - Prime Bot   |
//+------------------------------------------------------------------+
#property copyright "Bot MT5"
#property version   "1.05"
#property strict

#include <Trade/Trade.mqh>
CTrade trade;

//--- Parametros de entrada
input group "--- Parametros de Gatilho e Canal ---"
input int      OpeningHour = 0;             // Horario de abertura (hora GMT)
input int      OpeningMinute = 0;           // Horario de abertura (minuto)
input int      FirstEntryMaxHour = 16;      // Horario limite para primeira entrada do dia (hora)
input int      MaxEntryHour = 16;           // Horario limite para entrada (hora)
input ENUM_TIMEFRAMES ChannelTimeframe = PERIOD_M5;  // Timeframe do canal de abertura
input bool     EnableM15Fallback = true;    // Usar M15 se M5 < range minimo
input double   MinChannelRange = 2.5;       // Range minimo do canal
input double   MaxChannelRange = 14.99;     // Range maximo do canal (para projecao)
input double   SlicedThreshold = 15.0;      // Range para modo sliced (CA = C1)
input double   BreakoutMinTolerancePoints = 0.0; // Tolerancia minima (em pontos) para confirmar rompimento

input group "--- Parametros de Stop ---"
input double   StopLossIncrement = 20.0;    // Incremento do SL (%)

input group "--- Parametros de TP ---"
input double   TPMultiplier = 2.0;          // Multiplicador do TP
input double   TPReductionPercent = 10.0;   // Reducao do TP (%)

input group "--- Parametros de TP (Complementar) ---"
input double   SlicedMultiplier = 1.0;     // Multiplicador TP/SL no modo sliced

input group "--- Parametros de Risco e Retorno ---"
input double   RiskPercent = 1.0;           // Risco por operacao (%)
input bool     UseInitialDepositForRisk = false; // Usar deposito inicial da conta como base fixa do risco
input double   FixedLotAllEntries = 0.0;    // Lote fixo para first/turnof/add-on (0 usa risco dinamico)
input double   MinRiskReward = 0.85;        // RR minimo para entrada
input double   MaxDailyDrawdownPercent = 4.0; // Limite de DD diario em % (0 desativa)
input double   MaxDrawdownPercent = 8.0;      // Limite de DD maximo em % (0 desativa)
input double   MaxDailyDrawdownAmount = 0.0;  // Limite de DD diario absoluto (0 desativa)
input double   MaxDrawdownAmount = 0.0;       // Limite de DD maximo absoluto (0 desativa)

input group "--- Parametros de turnof ---"
input bool     EnableReversal = true;       // Habilitar turnof
input bool     EnableOvernightReversal = true;  // Habilitar turnof para fechamento overnight em SL
input double   ReversalMultiplier = 1.0;    // Multiplicador do range na turnof
input double   ReversalSLDistanceFactor = 3.0; // Fator da distancia do SL na turnof (x sobre multiplicador base)
input double   ReversalTPDistanceFactor = 2.8; // Fator da distancia do TP na turnof (x sobre multiplicador base)
input bool     AllowReversalAfterMaxEntryHour = false; // Permitir turnof apos horario limite de entrada
input bool     RearmCanceledReversalNextDay = false;   // Rearmar virada cancelada por horario no dia seguinte

input group "--- Parametros da Estrategia PCM ---"
input bool     EnablePCM = false;            // Habilitar operacao PCM apos TP da first_op
input bool     EnablePCMOnNoTradeLimitTarget = false; // Habilitar PCM em NoTrade quando LIMIT cancela por alvo projetado
input bool     BreakEven = false;            // Break even
input bool     TraillingStop = false;        // Trailling stop
input double   PCMTPReductionPercent = 10.0; // Reducao do TP (%) somente para PCM
input double   PCMRiskPercent = 1.0;         // Risco por operacao (%) para entrada PCM
input int      PCMChannelBars = 4;           // Quantidade de velas para recalcular o canal a partir do candle do TP
input int      PCMMaxOperationsPerDay = 1;   // Maximo de operacoes PCM por dia
input bool     PCMIgnoreFirstEntryMaxHour = false; // Permitir entrada PCM apos o horario limite da primeira entrada
input ENUM_TIMEFRAMES PCMReferenceTimeframe = PERIOD_M5; // Timeframe de referencia do PCM (M1/M5/M15)
input bool     PCMEnableSkipLargeCandle = false; // Reiniciar contagem se candle exceder o limite em pontos
input double   PCMMaxCandlePoints = 0.0;     // Limite maximo do range de candle em pontos para contagem PCM (0 desativa)
input bool     EnablePCMHourLimit = false;   // Habilitar horario limite especifico para entrada PCM
input int      PCMEntryMaxHour = 23;         // Hora limite para entrada PCM
input int      PCMEntryMaxMinute = 59;       // Minuto limite para entrada PCM

input group "--- Parametros de Overnight ---"
input bool     AllowTradeWithOvernight = true;  // Permitir novas operacoes com posicao overnight
input bool     KeepPositionsOvernight = true;   // Manter posicoes abertas overnight
input int      CloseMinutesBeforeMarketClose = 30;  // Fechar a mercado X min antes do fechamento

input group "--- Modo de Execucao ---"
input bool     StrictLimitOnly = true;          // Priorizar LIMIT nas entradas; fechamentos e viradas podem usar mercado
input bool     PreferLimitMainEntry = true;     // Priorizar LIMIT na primeira entrada do dia
input bool     PreferLimitReversal = true;      // Priorizar LIMIT na turnof
input bool     PreferLimitOvernightReversal = true; // Priorizar LIMIT na virada de overnight
input bool     PreferLimitNegativeAddOn = true; // Priorizar LIMIT na adicao em flutuacao negativa
input bool     AllowMarketFallbackReversal = false; // Se LIMIT da virada falhar, usar mercado
input bool     AllowMarketFallbackOvernightReversal = false; // Se LIMIT da virada overnight falhar, usar mercado

input group "--- Parametros de Adicao em Flutuacao Negativa ---"
input bool     EnableNegativeAddOn = true;       // Habilitar adicao de posicao quando estiver negativo
input int      NegativeAddMaxEntries = 1;        // Maximo de adicoes por operacao
input double   NegativeAddTriggerPercent = 65.0; // Disparo em X% da distancia da entrada ate o SL
input double   NegativeAddLotMultiplier = 0.6;   // Multiplicador do lote base na adicao
input bool     NegativeAddUseSameSLTP = true;    // Usar mesmo SL/TP da operacao principal
input bool     EnableNegativeAddTPAdjustment = true;  // Ajustar TP de todas as posicoes apos addon
input double   NegativeAddTPDistancePercent = 100.0;  // Novo TP em % da distancia da entrada media ate o SL
input bool     NegativeAddTPAdjustOnReversal = false; // Ajustar TP apos addon tambem em operacoes de virada
input bool     EnableNegativeAddDebugLogs = true; // Gerar logs de diagnostico da adicao negativa
input int      NegativeAddDebugIntervalSeconds = 60; // Intervalo minimo para repetir log igual (seg)

input group "--- P0 Hardening (Live Safety) ---"
input bool     EnableP0InitStateRecovery = true; // Reidratar estado em reinicio para evitar operacoes duplicadas
input bool     EnableP0EmergencyFlattenOnDD = true; // Fechar/cancelar exposicoes ao atingir limite de DD
input int      P0EmergencyRetrySeconds = 5; // Intervalo minimo entre tentativas de flatten por DD
input bool     EnableP0CancelOrphanPreArmedOnInit = true; // Cancelar virada pre-armada sem posicao base ao iniciar
input bool     EnableP0BrokerStopLevelValidation = true; // Validar distancia minima de SL/TP conforme broker
input bool     EnableP0RejectTradeIfMinLotExceedsRisk = true; // Bloquear ordem quando lote minimo excede risco alvo

input group "--- Parametros de Interface e Log ---"
input bool     DrawChannels = true;         // Desenhar canais no grafico
input bool     EnableLogging = true;        // Gerar arquivo de log JSON
input ulong    MagicNumber = 654321;        // Numero magico

//--- Variaveis globais
double g_channelHigh = 0;
double g_channelLow = 0;
double g_channelRange = 0;
datetime g_channelDefinitionTime = 0;  // Fechamento da 4a vela usada para definir o canal
double g_projectedHigh = 0;
double g_projectedLow = 0;
bool g_channelCalculated = false;
bool g_channelValid = false;  // Flag para indicar se canal e valido para operar
bool g_firstTradeExecuted = false;
bool g_reversalTradeExecuted = false;
bool g_usingM15 = false;  // Flag para indicar se esta usando M15
ENUM_TIMEFRAMES g_activeTimeframe = PERIOD_M5;  // Timeframe ativo no dia

// Ciclo 1 (C1)
bool g_cycle1Defined = false;
string g_cycle1Direction = "";  // "UP" ou "DOWN"
double g_cycle1High = 0;
double g_cycle1Low = 0;

// Controle de posicao
ulong g_currentTicket = 0;
ulong g_overnightTicket = 0;  // Ticket da posicao overnight
ENUM_ORDER_TYPE g_currentOrderType;
double g_firstTradeLotSize = 0;
double g_firstTradeStopLoss = 0;  // Armazenar SL da primeira operacao
double g_firstTradeTakeProfit = 0;  // Armazenar TP da primeira operacao
datetime g_lastResetTime = 0;
bool g_pendingOrderPlaced = false;  // Controle de ordem pendente
enum EPendingOrderContext
{
   PENDING_CONTEXT_NONE = 0,
   PENDING_CONTEXT_FIRST_ENTRY = 1,
   PENDING_CONTEXT_REVERSAL = 2,
   PENDING_CONTEXT_OVERNIGHT_REVERSAL = 3
};
EPendingOrderContext g_pendingOrderContext = PENDING_CONTEXT_NONE;
bool g_pendingOrderIsReversal = false;
bool g_pendingOrderIsSliced = false;
datetime g_pendingOrderChannelDefinitionTime = 0;
datetime g_pendingOrderTriggerTime = 0;
bool g_pendingOrderPreserveDailyCycle = false;
double g_pendingOrderChannelRange = 0.0;
double g_pendingOrderLotSnapshot = 0.0;
bool g_pendingOrderIsPCM = false;
datetime g_pendingOrderSubmissionTime = 0;
double g_pendingLimitPrice = 0.0;
double g_pendingStopLossSnapshot = 0.0;
double g_pendingTakeProfitSnapshot = 0.0;
double g_pendingClosestPriceToLimit = 0.0;
double g_pendingMaxRiskRewardObserved = 0.0;
double g_pendingMinDistanceToLimitPoints = -1.0;
bool g_pendingLimitTelemetryReady = false;
int g_negativeAddEntriesExecuted = 0;  // Quantidade de adicoes executadas na operacao atual
double g_negativeAddExecutedLots = 0.0;  // Soma de lotes executados via addon na operacao atual
double g_negativeAddExecutedWeightedEntryPrice = 0.0;  // Soma ponderada de preco de entrada dos addons
ulong g_negativeAddExecutedTickets[];  // Tickets/position IDs rastreados dos addons executados
datetime g_negativeAddEntryTimes[];  // Horario de entrada de cada ticket addon rastreado
double g_negativeAddEntryPrices[];  // Preco de entrada de cada ticket addon rastreado
double g_negativeAddStopLosses[];  // SL observado do ticket addon
double g_negativeAddTakeProfits[];  // TP observado do ticket addon
double g_negativeAddMaxFloatingProfits[];  // MFE do ticket addon desde a entrada
double g_negativeAddMaxFloatingDrawdowns[];  // MAE do ticket addon desde a entrada
double g_negativeAddMaxAdverseToSLPercents[];  // Distancia adversa maxima ate o SL do ticket addon
double g_negativeAddMaxFavorableToTPPercents[];  // Distancia favoravel maxima ate o TP do ticket addon
ulong g_negativeAddPendingOrderTickets[];  // Tickets de ordens LIMIT de addon pendentes
bool g_negativeAddPendingOrderHandled[];  // Controle para evitar processar o mesmo ticket mais de uma vez
bool g_negativeAddPendingOrdersPlaced = false;  // Indica se as ordens LIMIT de addon do trade atual ja foram criadas
bool g_negativeAddRuntimeEnabled = false;  // Flag runtime para proteger cenarios nao suportados
bool g_negativeAddTPAdjustRuntimeEnabled = false;  // Flag runtime para ajuste de TP apos addon
string g_negativeAddRuntimeDisableReason = "";  // Motivo de desativacao em runtime
datetime g_negativeAddLastDebugLogTime = 0;  // Ultimo timestamp de log de diagnostico
int g_negativeAddLastReasonCode = -1;  // Ultimo motivo logado da adicao negativa
double g_initialAccountBalance = 0;  // Saldo inicial capturado no inicio da execucao
double g_dayStartEquity = 0;  // Equity de referencia para DD diario
double g_peakEquity = 0;  // Pico de equity para DD maximo
double g_cachedDailyDrawdownPercent = 0;
double g_cachedMaxDrawdownPercent = 0;
double g_cachedDailyDrawdownAmount = 0;
double g_cachedMaxDrawdownAmount = 0;
datetime g_drawdownLastBlockLogTime = 0;
int g_drawdownLastBlockType = 0;  // 1=daily%, 2=max%, 3=daily$, 4=max$
string g_drawdownLastBlockContext = "";
bool g_drawdownEmergencyLockActive = false;
datetime g_drawdownEmergencyLastAttempt = 0;
int g_drawdownEmergencyLastType = 0;
string g_drawdownEmergencyLastContext = "";
ulong g_currentTradePositionTickets[];  // Tickets observados da operacao atual (suporte a multiplas posicoes)
int g_tickDDCurrentDateKey = 0;
bool g_tickDDCurrentDayInitialized = false;
double g_tickDDCurrentDayStartBalance = 0.0;
double g_tickDDCurrentMaxFloating = 0.0;
datetime g_tickDDCurrentMaxFloatingTime = 0;
double g_tickDDCurrentMaxPendingLimitRisk = 0.0;
datetime g_tickDDCurrentMaxPendingLimitRiskTime = 0;
double g_tickDDCurrentMaxCombined = 0.0;
datetime g_tickDDCurrentMaxCombinedTime = 0;
int g_tickDDCurrentPendingLimitCountAtCombinedPeak = 0;
int g_tickDDCurrentMaxFloatingPositions = 0;
datetime g_tickDDCurrentMaxFloatingPositionsTime = 0;
int g_tickDDDailyDateKeys[];
double g_tickDDDailyDayStartBalances[];
double g_tickDDDailyMaxFloating[];
double g_tickDDDailyMaxFloatingPercentOfDayBalance[];
datetime g_tickDDDailyMaxFloatingTimes[];
double g_tickDDDailyMaxPendingLimitRisk[];
datetime g_tickDDDailyMaxPendingLimitRiskTimes[];
double g_tickDDDailyMaxCombined[];
datetime g_tickDDDailyMaxCombinedTimes[];
int g_tickDDDailyPendingLimitCountAtCombinedPeak[];
int g_tickDDDailyMaxFloatingPositions[];
datetime g_tickDDDailyMaxFloatingPositionsTimes[];

double g_pointValue = 0;
double g_tickValue = 0;
double g_minLot = 0;
double g_maxLot = 0;
double g_lotStep = 0;
double g_contractSize = 0;
double g_tickSize = 0;
long g_accountMarginMode = 0;
bool g_isHedgingAccount = false;
bool g_reversalBlockedByEntryHour = false;
datetime g_reversalBlockedTime = 0;

// Controle da virada pre-armada por STOP (hedging)
ulong g_preArmedReversalOrderTicket = 0;
ENUM_ORDER_TYPE g_preArmedReversalOrderType = ORDER_TYPE_BUY;
double g_preArmedReversalStopLoss = 0.0;
double g_preArmedReversalTakeProfit = 0.0;
double g_preArmedReversalChannelRange = 0.0;
double g_preArmedReversalLotSize = 0.0;
bool g_preArmedReversalIsSliced = false;
datetime g_preArmedReversalChannelDefinitionTime = 0;

// Logging
int g_logFile = INVALID_HANDLE;
string g_tradesLog = "";
string g_noTradesLog = "";
string g_programName = "prime_bot";
datetime g_tradeEntryTime = 0;
double g_tradeEntryPrice = 0;
bool g_tradeSliced = false;
bool g_tradeReversal = false;
bool g_tradePCM = false;
datetime g_tradeChannelDefinitionTime = 0;
string g_tradeEntryExecutionType = "";
datetime g_tradeTriggerTime = 0;
double g_tradeMaxFloatingProfit = 0;
double g_tradeMaxFloatingDrawdown = 0;
double g_tradeMaxAdverseToSLPercent = 0;
double g_tradeMaxFavorableToTPPercent = 0;
bool g_pcmBreakEvenApplied = false;
bool g_pcmTraillingStopApplied = false;
datetime g_backtestStartTime = 0;
bool g_backtestStartCaptured = false;
datetime g_overnightEntryTime = 0;
double g_overnightEntryPrice = 0;
double g_overnightStopLoss = 0;
double g_overnightTakeProfit = 0;
double g_overnightChannelRange = 0;
double g_overnightLotSize = 0;
bool g_overnightSliced = false;
bool g_overnightReversal = false;
bool g_overnightPCM = false;
ENUM_ORDER_TYPE g_overnightOrderType = ORDER_TYPE_BUY;
datetime g_overnightChannelDefinitionTime = 0;
string g_overnightEntryExecutionType = "";
datetime g_overnightTriggerTime = 0;
double g_overnightMaxFloatingProfit = 0;
double g_overnightMaxFloatingDrawdown = 0;
double g_overnightMaxAdverseToSLPercent = 0;
double g_overnightMaxFavorableToTPPercent = 0;
ulong g_overnightLogTickets[];
datetime g_overnightLogEntryTimes[];
double g_overnightLogEntryPrices[];
double g_overnightLogStopLosses[];
double g_overnightLogTakeProfits[];
bool g_overnightLogSliceds[];
bool g_overnightLogReversals[];
bool g_overnightLogPCMs[];
ENUM_ORDER_TYPE g_overnightLogOrderTypes[];
datetime g_overnightLogChannelDefinitionTimes[];
string g_overnightLogEntryExecutionTypes[];
datetime g_overnightLogTriggerTimes[];
double g_overnightLogMaxFloatingProfits[];
double g_overnightLogMaxFloatingDrawdowns[];
double g_overnightLogMaxAdverseToSLPercents[];
double g_overnightLogMaxFavorableToTPPercents[];
double g_overnightLogChannelRanges[];
double g_overnightLogLotSizes[];
int g_overnightLogChainIds[];
int g_operationChainCounter = 0;
int g_currentOperationChainId = 0;
int g_overnightChainId = 0;
int g_lastClosedOvernightChainIdHint = 0;
bool g_pcmPendingActivation = false;
bool g_pcmReady = false;
datetime g_pcmChannelStartTime = 0;
int g_pcmOperationsToday = 0;
ENUM_TIMEFRAMES g_pcmActiveTimeframe = PERIOD_M5;

bool IsSameCalendarDay(datetime a, datetime b);

void ResetPendingLimitTelemetry()
{
   g_pendingLimitPrice = 0.0;
   g_pendingStopLossSnapshot = 0.0;
   g_pendingTakeProfitSnapshot = 0.0;
   g_pendingClosestPriceToLimit = 0.0;
   g_pendingMaxRiskRewardObserved = 0.0;
   g_pendingMinDistanceToLimitPoints = -1.0;
   g_pendingLimitTelemetryReady = false;
}

double CalculatePotentialRiskReward(ENUM_ORDER_TYPE orderType,
                                    double entryPrice,
                                    double stopLoss,
                                    double takeProfit)
{
   double riskDistance = 0.0;
   double rewardDistance = 0.0;

   if(orderType == ORDER_TYPE_BUY)
   {
      riskDistance = entryPrice - stopLoss;
      rewardDistance = takeProfit - entryPrice;
   }
   else if(orderType == ORDER_TYPE_SELL)
   {
      riskDistance = stopLoss - entryPrice;
      rewardDistance = entryPrice - takeProfit;
   }
   else
      return 0.0;

   if(riskDistance <= 0.0 || rewardDistance <= 0.0)
      return 0.0;

   return (rewardDistance / riskDistance);
}

double CalculateMissingToLimitPoints(ENUM_ORDER_TYPE orderType,
                                     double marketPrice,
                                     double limitPrice)
{
   double point = g_pointValue;
   if(point <= 0.0)
      point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(point <= 0.0)
      return 0.0;

   double distance = 0.0;
   if(orderType == ORDER_TYPE_BUY)
      distance = marketPrice - limitPrice;
   else if(orderType == ORDER_TYPE_SELL)
      distance = limitPrice - marketPrice;
   else
      return 0.0;

   if(distance < 0.0)
      distance = 0.0;

   return (distance / point);
}

void InitializePendingLimitTelemetry(double limitPrice,
                                     double stopLoss,
                                     double takeProfit,
                                     ENUM_ORDER_TYPE orderType)
{
   g_pendingLimitPrice = limitPrice;
   g_pendingStopLossSnapshot = stopLoss;
   g_pendingTakeProfitSnapshot = takeProfit;

   double currentPrice = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                                        : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   g_pendingClosestPriceToLimit = currentPrice;
   g_pendingMaxRiskRewardObserved = CalculatePotentialRiskReward(orderType,
                                                                 currentPrice,
                                                                 stopLoss,
                                                                 takeProfit);
   g_pendingMinDistanceToLimitPoints = CalculateMissingToLimitPoints(orderType, currentPrice, limitPrice);
   g_pendingLimitTelemetryReady = true;
}

void UpdatePendingLimitTelemetry(double currentBid, double currentAsk)
{
   if(!g_pendingLimitTelemetryReady)
      return;

   double referencePrice = (g_currentOrderType == ORDER_TYPE_BUY) ? currentAsk : currentBid;

   if(g_currentOrderType == ORDER_TYPE_BUY)
   {
      if(g_pendingClosestPriceToLimit <= 0.0 || referencePrice < g_pendingClosestPriceToLimit)
         g_pendingClosestPriceToLimit = referencePrice;
   }
   else if(g_currentOrderType == ORDER_TYPE_SELL)
   {
      if(g_pendingClosestPriceToLimit <= 0.0 || referencePrice > g_pendingClosestPriceToLimit)
         g_pendingClosestPriceToLimit = referencePrice;
   }

   double rrNow = CalculatePotentialRiskReward(g_currentOrderType,
                                               referencePrice,
                                               g_pendingStopLossSnapshot,
                                               g_pendingTakeProfitSnapshot);
   if(rrNow > g_pendingMaxRiskRewardObserved)
      g_pendingMaxRiskRewardObserved = rrNow;

   double missingPoints = CalculateMissingToLimitPoints(g_currentOrderType, referencePrice, g_pendingLimitPrice);
   if(g_pendingMinDistanceToLimitPoints < 0.0 || missingPoints < g_pendingMinDistanceToLimitPoints)
      g_pendingMinDistanceToLimitPoints = missingPoints;
}

//+------------------------------------------------------------------+
//| Utilitarios de contexto de ordem pendente                         |
//+------------------------------------------------------------------+
void ResetPendingOrderContext()
{
   g_pendingOrderContext = PENDING_CONTEXT_NONE;
   g_pendingOrderIsReversal = false;
   g_pendingOrderIsSliced = false;
   g_pendingOrderIsPCM = false;
   g_pendingOrderChannelDefinitionTime = 0;
   g_pendingOrderTriggerTime = 0;
   g_pendingOrderPreserveDailyCycle = false;
   g_pendingOrderChannelRange = 0.0;
   g_pendingOrderLotSnapshot = 0.0;
   g_pendingOrderSubmissionTime = 0;
   ResetPendingLimitTelemetry();
}

string PendingOrderContextToString(EPendingOrderContext context)
{
   if(context == PENDING_CONTEXT_FIRST_ENTRY)
      return "FIRST_ENTRY";
   if(context == PENDING_CONTEXT_REVERSAL)
      return "REVERSAL";
   if(context == PENDING_CONTEXT_OVERNIGHT_REVERSAL)
      return "OVERNIGHT_REVERSAL";
   return "NONE";
}

int NextOperationChainId()
{
   g_operationChainCounter++;
   if(g_operationChainCounter <= 0)
      g_operationChainCounter = 1;
   return g_operationChainCounter;
}

void StartNewOperationChain()
{
   g_currentOperationChainId = NextOperationChainId();
}

void AdoptOperationChainId(int chainId)
{
   if(chainId > 0)
   {
      g_currentOperationChainId = chainId;
      if(chainId > g_operationChainCounter)
         g_operationChainCounter = chainId;
      return;
   }

   if(g_currentOperationChainId <= 0)
      StartNewOperationChain();
}

int ResolveOperationChainIdForLog(datetime entryTime)
{
   if(g_currentOperationChainId > 0)
      return g_currentOperationChainId;

   if(entryTime > 0)
      return (int)(entryTime % 1000000000);

   return NextOperationChainId();
}

string BuildOperationChainCode(int chainId)
{
   if(chainId <= 0)
      return "";
   return "op" + IntegerToString(chainId);
}

string BuildOperationCode(bool isReversal, bool isPCM, int chainId)
{
   string chainCode = BuildOperationChainCode(chainId);
   if(chainCode == "")
      return "";
   if(isPCM)
      return "pcm_" + chainCode;
   return (isReversal ? "turn_" : "first_") + chainCode;
}

string BuildAddOperationCode(int chainId)
{
   string chainCode = BuildOperationChainCode(chainId);
   if(chainCode == "")
      return "";
   return "add_" + chainCode;
}

void ResetReversalHourBlockState()
{
   g_reversalBlockedByEntryHour = false;
   g_reversalBlockedTime = 0;
}

bool IsAfterMaxEntryHour()
{
   MqlDateTime timeNow;
   TimeToStruct(TimeCurrent(), timeNow);
   return (timeNow.hour >= MaxEntryHour);
}

bool IsReversalAllowedByEntryHourNow()
{
   TryRearmReversalBlockForNewDay();

   if(g_reversalBlockedByEntryHour)
      return false;

   if(AllowReversalAfterMaxEntryHour)
      return true;
   return !IsAfterMaxEntryHour();
}

void MarkReversalBlockedByEntryHour()
{
   g_reversalBlockedByEntryHour = true;
   g_reversalBlockedTime = TimeCurrent();
}

void TryRearmReversalBlockForNewDay()
{
   if(!g_reversalBlockedByEntryHour)
      return;
   if(!RearmCanceledReversalNextDay)
      return;

   datetime nowTime = TimeCurrent();
   if(g_reversalBlockedTime <= 0 || !IsSameCalendarDay(g_reversalBlockedTime, nowTime))
   {
      ResetReversalHourBlockState();
      Print("INFO: bloqueio de virada por horario foi rearmado para novo dia.");
   }
}

double NormalizePriceToTick(double price)
{
   if(price <= 0.0)
      return price;

   double tickSize = g_tickSize;
   if(tickSize <= 0.0)
      tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0.0)
      tickSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(tickSize <= 0.0)
      return price;

   double normalizedByTick = MathRound(price / tickSize) * tickSize;
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   return NormalizeDouble(normalizedByTick, digits);
}

bool ShouldUseLimitForMainEntry()
{
   return (StrictLimitOnly || PreferLimitMainEntry);
}

bool ShouldUseLimitForReversal()
{
   return PreferLimitReversal;
}

bool ShouldUseLimitForOvernightReversal()
{
   return PreferLimitOvernightReversal;
}

bool ShouldUseLimitForNegativeAddOn()
{
   return (StrictLimitOnly || PreferLimitNegativeAddOn);
}

bool IsPCMEnabledRuntime()
{
   if(!EnablePCM)
      return false;
   if(PCMChannelBars < 4)
      return false;
   if(PCMMaxOperationsPerDay <= 0)
      return false;
   if(PCMReferenceTimeframe != PERIOD_M1 &&
      PCMReferenceTimeframe != PERIOD_M5 &&
      PCMReferenceTimeframe != PERIOD_M15)
      return false;
   return true;
}

bool IsPCMMaxCandleFilterEnabled()
{
   if(!PCMEnableSkipLargeCandle)
      return false;
   if(PCMMaxCandlePoints <= 0.0)
      return false;
   return true;
}

ENUM_TIMEFRAMES ResolvePCMActiveTimeframe()
{
   if(PCMReferenceTimeframe == PERIOD_M1 ||
      PCMReferenceTimeframe == PERIOD_M5 ||
      PCMReferenceTimeframe == PERIOD_M15)
      return PCMReferenceTimeframe;
   return PERIOD_M5;
}

bool IsAfterPCMEntryTimeLimit(const MqlDateTime &timeNow)
{
   if(!EnablePCMHourLimit)
      return false;

   int limitHour = PCMEntryMaxHour;
   int limitMinute = PCMEntryMaxMinute;
   if(limitHour < 0)
      limitHour = 0;
   else if(limitHour > 23)
      limitHour = 23;
   if(limitMinute < 0)
      limitMinute = 0;
   else if(limitMinute > 59)
      limitMinute = 59;

   if(timeNow.hour > limitHour)
      return true;
   if(timeNow.hour == limitHour && timeNow.min >= limitMinute)
      return true;
   return false;
}

bool IsAfterPCMEntryCandle()
{
   if(g_tradeEntryTime <= 0)
      return false;

   ENUM_TIMEFRAMES tf = g_pcmActiveTimeframe;
   if(tf != PERIOD_M1 && tf != PERIOD_M5 && tf != PERIOD_M15)
      tf = ResolvePCMActiveTimeframe();

   int entryShift = iBarShift(_Symbol, tf, g_tradeEntryTime, false);
   if(entryShift < 0)
      return false;

   datetime entryBarTime = iTime(_Symbol, tf, entryShift);
   datetime currentBarTime = iTime(_Symbol, tf, 0);
   if(entryBarTime <= 0 || currentBarTime <= 0)
      return false;

   return (currentBarTime > entryBarTime);
}

bool IsPCMHalfTPReached(ENUM_ORDER_TYPE orderType,
                        double entryPrice,
                        double takeProfit,
                        double currentBid,
                        double currentAsk)
{
   if((orderType != ORDER_TYPE_BUY && orderType != ORDER_TYPE_SELL) || entryPrice <= 0.0 || takeProfit <= 0.0)
      return false;

   double totalDistance = MathAbs(takeProfit - entryPrice);
   if(totalDistance <= 0.0)
      return false;

   double triggerPrice = (orderType == ORDER_TYPE_BUY)
                         ? (entryPrice + (totalDistance * 0.5))
                         : (entryPrice - (totalDistance * 0.5));

   if(orderType == ORDER_TYPE_BUY)
      return (currentBid >= triggerPrice);

   return (currentAsk <= triggerPrice);
}

bool IsPCMProgressToTPReached(ENUM_ORDER_TYPE orderType,
                              double entryPrice,
                              double takeProfit,
                              double currentBid,
                              double currentAsk,
                              double progressPercent)
{
   if((orderType != ORDER_TYPE_BUY && orderType != ORDER_TYPE_SELL) || entryPrice <= 0.0 || takeProfit <= 0.0)
      return false;
   if(progressPercent <= 0.0)
      return false;
   if(progressPercent >= 100.0)
      progressPercent = 100.0;

   double totalDistance = MathAbs(takeProfit - entryPrice);
   if(totalDistance <= 0.0)
      return false;

   double progressFactor = progressPercent / 100.0;
   double triggerPrice = (orderType == ORDER_TYPE_BUY)
                         ? (entryPrice + (totalDistance * progressFactor))
                         : (entryPrice - (totalDistance * progressFactor));

   if(orderType == ORDER_TYPE_BUY)
      return (currentBid >= triggerPrice);

   return (currentAsk <= triggerPrice);
}

void TryApplyPCMBreakEven()
{
   if(!g_tradePCM || !BreakEven || g_pcmBreakEvenApplied)
      return;
   if(!IsAfterPCMEntryCandle())
      return;

   if(g_currentOrderType != ORDER_TYPE_BUY && g_currentOrderType != ORDER_TYPE_SELL)
      return;

   ulong activeTickets[];
   double activeVolume = 0.0;
   double weightedEntryPrice = 0.0;
   double activeFloating = 0.0;
   int activeCount = CollectActiveCurrentTradePositions(activeTickets, activeVolume, weightedEntryPrice, activeFloating);
   if(activeCount <= 0)
      return;

   double referenceEntryPrice = weightedEntryPrice;
   if(referenceEntryPrice <= 0.0)
      referenceEntryPrice = g_tradeEntryPrice;
   if(referenceEntryPrice <= 0.0 || g_firstTradeTakeProfit <= 0.0)
      return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   bool halfReachedNow = IsPCMHalfTPReached(g_currentOrderType, referenceEntryPrice, g_firstTradeTakeProfit, bid, ask);
   bool halfReachedHistorically = (g_tradeMaxFavorableToTPPercent >= 50.0);
   if(!halfReachedNow && !halfReachedHistorically)
      return;

   double breakEvenPrice = NormalizePriceToTick(referenceEntryPrice);
   if(breakEvenPrice <= 0.0)
      return;

   double epsilon = g_pointValue * 0.5;
   if(epsilon <= 0.0)
      epsilon = 0.00000001;

   if(g_currentOrderType == ORDER_TYPE_BUY && g_firstTradeStopLoss >= (breakEvenPrice - epsilon))
   {
      g_pcmBreakEvenApplied = true;
      return;
   }
   if(g_currentOrderType == ORDER_TYPE_SELL && g_firstTradeStopLoss <= (breakEvenPrice + epsilon) && g_firstTradeStopLoss > 0.0)
   {
      g_pcmBreakEvenApplied = true;
      return;
   }

   int modifiedCount = 0;
   bool modified = ApplySLTPToCurrentTradePositions(breakEvenPrice,
                                                    g_firstTradeTakeProfit,
                                                    modifiedCount,
                                                    "pcm break even");
   if(modified && modifiedCount > 0)
   {
      int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      g_firstTradeStopLoss = breakEvenPrice;
      g_pcmBreakEvenApplied = true;
      Print("INFO: PCM Break even aplicado. Novo SL=", DoubleToString(g_firstTradeStopLoss, digits),
            " | TP=", DoubleToString(g_firstTradeTakeProfit, digits),
            " | posicoes=", modifiedCount);
   }
}

void TryApplyPCMTraillingStop()
{
   if(!g_tradePCM || !TraillingStop || g_pcmTraillingStopApplied)
      return;
   if(!IsAfterPCMEntryCandle())
      return;

   if(g_currentOrderType != ORDER_TYPE_BUY && g_currentOrderType != ORDER_TYPE_SELL)
      return;

   ulong activeTickets[];
   double activeVolume = 0.0;
   double weightedEntryPrice = 0.0;
   double activeFloating = 0.0;
   int activeCount = CollectActiveCurrentTradePositions(activeTickets, activeVolume, weightedEntryPrice, activeFloating);
   if(activeCount <= 0)
      return;

   double referenceEntryPrice = weightedEntryPrice;
   if(referenceEntryPrice <= 0.0)
      referenceEntryPrice = g_tradeEntryPrice;
   if(referenceEntryPrice <= 0.0 || g_firstTradeTakeProfit <= 0.0)
      return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   bool trailReachedNow = IsPCMProgressToTPReached(g_currentOrderType,
                                                   referenceEntryPrice,
                                                   g_firstTradeTakeProfit,
                                                   bid,
                                                   ask,
                                                   75.0);
   bool trailReachedHistorically = (g_tradeMaxFavorableToTPPercent >= 75.0);
   if(!trailReachedNow && !trailReachedHistorically)
      return;

   double totalDistance = MathAbs(g_firstTradeTakeProfit - referenceEntryPrice);
   if(totalDistance <= 0.0)
      return;

   double newStopLoss = (g_currentOrderType == ORDER_TYPE_BUY)
                        ? (referenceEntryPrice + (totalDistance * 0.5))
                        : (referenceEntryPrice - (totalDistance * 0.5));
   newStopLoss = NormalizePriceToTick(newStopLoss);
   if(newStopLoss <= 0.0)
      return;

   double epsilon = g_pointValue * 0.5;
   if(epsilon <= 0.0)
      epsilon = 0.00000001;

   if(g_currentOrderType == ORDER_TYPE_BUY && g_firstTradeStopLoss >= (newStopLoss - epsilon))
   {
      g_pcmTraillingStopApplied = true;
      return;
   }
   if(g_currentOrderType == ORDER_TYPE_SELL && g_firstTradeStopLoss <= (newStopLoss + epsilon) && g_firstTradeStopLoss > 0.0)
   {
      g_pcmTraillingStopApplied = true;
      return;
   }

   int modifiedCount = 0;
   bool modified = ApplySLTPToCurrentTradePositions(newStopLoss,
                                                    g_firstTradeTakeProfit,
                                                    modifiedCount,
                                                    "pcm trailing stop");
   if(modified && modifiedCount > 0)
   {
      int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      g_firstTradeStopLoss = newStopLoss;
      g_pcmTraillingStopApplied = true;
      Print("INFO: PCM Trailling stop aplicado. Novo SL=", DoubleToString(g_firstTradeStopLoss, digits),
            " | TP=", DoubleToString(g_firstTradeTakeProfit, digits),
            " | posicoes=", modifiedCount);
   }
}

void DeactivatePCMSetup()
{
   g_pcmPendingActivation = false;
   g_pcmReady = false;
   g_pcmChannelStartTime = 0;
}

void ResetPCMStateForNewDay()
{
   DeactivatePCMSetup();
   g_pcmOperationsToday = 0;
   g_pcmActiveTimeframe = ResolvePCMActiveTimeframe();
}

void MarkPCMOperationExecuted()
{
   if(g_pcmOperationsToday < 2147483647)
      g_pcmOperationsToday++;
   DeactivatePCMSetup();
}

bool SchedulePCMActivationFromTP(datetime tpTime)
{
   if(!IsPCMEnabledRuntime())
      return false;
   if(g_tradePCM)
      return false;
   if(g_pcmPendingActivation || g_pcmReady)
      return false;
   if(g_pcmOperationsToday >= PCMMaxOperationsPerDay)
      return false;

   g_pcmActiveTimeframe = ResolvePCMActiveTimeframe();
   int tpBarShift = iBarShift(_Symbol, g_pcmActiveTimeframe, tpTime, false);
   if(tpBarShift < 0)
   {
      Print("WARN: PCM nao armado - candle do TP nao encontrado no timeframe ", EnumToString(g_pcmActiveTimeframe));
      return false;
   }

   datetime startCandleTime = iTime(_Symbol, g_pcmActiveTimeframe, tpBarShift);
   if(startCandleTime <= 0)
   {
      Print("WARN: PCM nao armado - horario inicial invalido.");
      return false;
   }

   g_pcmChannelStartTime = startCandleTime;
   g_pcmPendingActivation = true;
   g_pcmReady = false;

   // Limpa o canal anterior para forcar novo calculo baseado no candle de TP.
   ObjectsDeleteAll(0, "Channel_");
   g_channelCalculated = false;
   g_channelValid = false;
   g_channelHigh = 0;
   g_channelLow = 0;
   g_channelRange = 0;
   g_channelDefinitionTime = 0;
   g_projectedHigh = 0;
   g_projectedLow = 0;
   g_cycle1Defined = false;
   g_cycle1Direction = "";
   g_cycle1High = 0;
   g_cycle1Low = 0;

   Print("INFO: PCM armado. Inicio do novo CA em ",
         TimeToString(g_pcmChannelStartTime, TIME_DATE|TIME_MINUTES),
         " | barras=", PCMChannelBars,
         " | timeframe=", EnumToString(g_pcmActiveTimeframe));
   return true;
}

bool IsReducedRRForNoTradePCM(double rrMaxReached, double rrMinRequired)
{
   if(rrMaxReached < 0.0)
      return false;

   double minRequired = rrMinRequired;
   if(minRequired <= 0.0)
      minRequired = MinRiskReward;
   if(minRequired <= 0.0)
      return false;

   return (rrMaxReached + 0.0000001 < minRequired);
}

bool SchedulePCMActivationFromNoTradeLimitTarget(datetime targetTime,
                                                 double rrMaxReached,
                                                 double rrMinRequired)
{
   if(!EnablePCMOnNoTradeLimitTarget)
      return false;
   if(!IsPCMEnabledRuntime())
      return false;

   bool rrReduced = IsReducedRRForNoTradePCM(rrMaxReached, rrMinRequired);
   if(rrReduced)
   {
      Print("INFO: PCM por NoTrade com RR reduzido permitido. rr_max=",
            DoubleToString(rrMaxReached, 4),
            " | rr_min=", DoubleToString(rrMinRequired, 4));
   }

   // Em no-trade por LIMIT no alvo, sempre atualiza a referencia do candle de TP,
   // mesmo quando ja existe setup PCM pendente/pronto do mesmo dia.
   if(g_pcmPendingActivation || g_pcmReady)
   {
      Print("INFO: PCM por NoTrade substituindo setup PCM anterior. pending=",
            g_pcmPendingActivation ? "true" : "false",
            " | ready=", g_pcmReady ? "true" : "false");
      DeactivatePCMSetup();
   }

   bool scheduled = SchedulePCMActivationFromTP(targetTime);
   if(scheduled)
   {
      Print("INFO: PCM armada por NoTrade (LIMIT cancelada em alvo projetado). rr_max=",
            DoubleToString(rrMaxReached, 4),
            " | rr_min=", DoubleToString(rrMinRequired, 4));
   }
   else
   {
      Print("WARN: Falha ao armar PCM por NoTrade. rr_max=",
            DoubleToString(rrMaxReached, 4),
            " | rr_min=", DoubleToString(rrMinRequired, 4),
            " | pcm_ops_today=", IntegerToString(g_pcmOperationsToday),
            " | pcm_max_ops=", IntegerToString(PCMMaxOperationsPerDay),
            " | trade_pcm=", g_tradePCM ? "true" : "false");
   }
   return scheduled;
}

bool TryActivatePCMChannel()
{
   if(!g_pcmPendingActivation || g_pcmChannelStartTime <= 0)
      return false;

   int requiredBars = PCMChannelBars;
   if(requiredBars < 4)
      requiredBars = 4;

   int totalBars = Bars(_Symbol, g_pcmActiveTimeframe);
   if(totalBars <= 0)
      return false;

   int barsFound = 0;
   double localHigh = 0.0;
   double localLow = 0.0;
   datetime lastBarTime = 0;

   for(int i = totalBars - 1; i >= 0; i--)
   {
      datetime barTime = iTime(_Symbol, g_pcmActiveTimeframe, i);
      if(barTime < g_pcmChannelStartTime)
         continue;

      double barHigh = iHigh(_Symbol, g_pcmActiveTimeframe, i);
      double barLow = iLow(_Symbol, g_pcmActiveTimeframe, i);
      double barRange = MathAbs(barHigh - barLow);

      if(IsPCMMaxCandleFilterEnabled())
      {
         double rangePoints = 0.0;
         if(g_pointValue > 0.0)
            rangePoints = barRange / g_pointValue;
         if(rangePoints > PCMMaxCandlePoints)
         {
            if(barsFound > 0)
            {
               Print("INFO: PCM reiniciado por candle grande em ",
                     TimeToString(barTime, TIME_DATE|TIME_MINUTES),
                     " | range_points=", DoubleToString(rangePoints, 2),
                     " > limite=", DoubleToString(PCMMaxCandlePoints, 2));
            }
            barsFound = 0;
            localHigh = 0.0;
            localLow = 0.0;
            lastBarTime = 0;
            continue;
         }
      }

      if(barsFound == 0)
      {
         localHigh = barHigh;
         localLow = barLow;
      }
      else
      {
         if(barHigh > localHigh)
            localHigh = barHigh;
         if(barLow < localLow)
            localLow = barLow;
      }

      barsFound++;
      lastBarTime = barTime;
      if(barsFound >= requiredBars)
         break;
   }

   if(barsFound < requiredBars)
      return false;

   datetime channelCloseTime = lastBarTime + PeriodSeconds(g_pcmActiveTimeframe);
   if(TimeCurrent() < channelCloseTime)
      return false;

   g_channelDefinitionTime = channelCloseTime;
   g_channelHigh = localHigh;
   g_channelLow = localLow;
   g_channelRange = g_channelHigh - g_channelLow;

   Print(" Canal PCM calculado:");
   Print("  Inicio: ", TimeToString(g_pcmChannelStartTime, TIME_DATE|TIME_MINUTES),
         " | Definicao: ", TimeToString(g_channelDefinitionTime, TIME_DATE|TIME_MINUTES));
   Print("  Timeframe PCM: ", EnumToString(g_pcmActiveTimeframe));
   Print("  High: ", g_channelHigh, " | Low: ", g_channelLow, " | Range: ", g_channelRange);

   if(g_channelRange < MinChannelRange)
   {
      Print(" PCM cancelado - Range pequeno: ", g_channelRange, " < ", MinChannelRange);
      g_channelCalculated = true;
      g_channelValid = false;
      LogNoTrade("PCM: Range pequeno: " + DoubleToString(g_channelRange, 2));
      DeactivatePCMSetup();
      return false;
   }

   if(g_channelRange > SlicedThreshold)
   {
      Print(" PCM em modo SLICED. Range=", g_channelRange, " > ", SlicedThreshold);
      g_projectedHigh = g_channelHigh;
      g_projectedLow = g_channelLow;
      g_cycle1Defined = true;
      g_cycle1Direction = "BOTH";
      g_cycle1High = g_channelHigh;
      g_cycle1Low = g_channelLow;
      g_channelCalculated = true;
      g_channelValid = true;
      if(DrawChannels)
         DrawChannelLines();
      g_pcmPendingActivation = false;
      g_pcmReady = true;
      return true;
   }

   if(g_channelRange > MaxChannelRange)
   {
      Print(" PCM cancelado - Range grande: ", g_channelRange, " > ", MaxChannelRange);
      g_channelCalculated = true;
      g_channelValid = false;
      LogNoTrade("PCM: Range grande: " + DoubleToString(g_channelRange, 2));
      DeactivatePCMSetup();
      return false;
   }

   g_projectedHigh = g_channelHigh + g_channelRange;
   g_projectedLow = g_channelLow - g_channelRange;
   g_cycle1Defined = false;
   g_cycle1Direction = "";
   g_cycle1High = 0;
   g_cycle1Low = 0;
   g_channelCalculated = true;
   g_channelValid = true;
   if(DrawChannels)
      DrawChannelLines();

   g_pcmPendingActivation = false;
   g_pcmReady = true;
   Print(" INFO: Canal PCM pronto para nova entrada.");
   return true;
}

void ConsumeCycleAfterPendingCancel()
{
   if(g_pendingOrderContext == PENDING_CONTEXT_FIRST_ENTRY)
      g_firstTradeExecuted = true;
   else if(g_pendingOrderContext == PENDING_CONTEXT_REVERSAL)
      g_reversalTradeExecuted = true;
   else if(g_pendingOrderContext == PENDING_CONTEXT_OVERNIGHT_REVERSAL && !g_pendingOrderPreserveDailyCycle)
      g_reversalTradeExecuted = true;
}

void ClearPendingOrderState(bool clearTicket)
{
   bool pendingWasPCM = g_pendingOrderIsPCM;
   if(clearTicket)
   {
      g_currentTicket = 0;
      ClearCurrentTradePositionTickets();
   }
   g_pendingOrderPlaced = false;
   ResetPendingOrderContext();
   if(pendingWasPCM)
      DeactivatePCMSetup();
}

void ApplyPendingFillTradeMetadata(double filledEntryPrice)
{
   g_tradeEntryTime = TimeCurrent();
   g_tradeEntryPrice = filledEntryPrice;
   g_tradeSliced = g_pendingOrderIsSliced;
   g_tradeReversal = g_pendingOrderIsReversal;
   g_tradePCM = g_pendingOrderIsPCM;
   g_tradeChannelDefinitionTime = g_pendingOrderChannelDefinitionTime;
   if(g_tradeChannelDefinitionTime <= 0)
      g_tradeChannelDefinitionTime = g_channelDefinitionTime;
   g_tradeEntryExecutionType = "LIMIT";
   g_tradeTriggerTime = g_pendingOrderTriggerTime;
   if(g_tradeTriggerTime <= 0)
      g_tradeTriggerTime = g_tradeEntryTime;

   if(g_tradePCM && g_preArmedReversalOrderTicket > 0)
      CancelPreArmedReversalOrder("entrada PCM LIMIT - turnof desabilitada");
}

void ClearPreArmedReversalState()
{
   g_preArmedReversalOrderTicket = 0;
   g_preArmedReversalOrderType = ORDER_TYPE_BUY;
   g_preArmedReversalStopLoss = 0.0;
   g_preArmedReversalTakeProfit = 0.0;
   g_preArmedReversalChannelRange = 0.0;
   g_preArmedReversalLotSize = 0.0;
   g_preArmedReversalIsSliced = false;
   g_preArmedReversalChannelDefinitionTime = 0;
}

void CancelPreArmedReversalOrder(string reason = "")
{
   if(g_preArmedReversalOrderTicket == 0)
      return;

   if(PositionSelectByTicket(g_preArmedReversalOrderTicket))
   {
      Print("INFO: ordem pre-armada ja virou posicao, cancelamento ignorado. Ticket=", g_preArmedReversalOrderTicket);
      return;
   }

   if(OrderSelect(g_preArmedReversalOrderTicket))
   {
      if(trade.OrderDelete(g_preArmedReversalOrderTicket))
      {
         if(reason == "")
            Print("INFO: ordem pre-armada de virada cancelada. Ticket=", g_preArmedReversalOrderTicket);
         else
            Print("INFO: ordem pre-armada de virada cancelada (", reason, "). Ticket=", g_preArmedReversalOrderTicket);
      }
      else
      {
         Print("WARN: falha ao cancelar ordem pre-armada de virada. Ticket=", g_preArmedReversalOrderTicket,
               " | retcode=", trade.ResultRetcode(), " | ", trade.ResultRetcodeDescription());
      }
   }

   ClearPreArmedReversalState();
}

bool PlacePreArmedReversalStopOrder(ENUM_ORDER_TYPE baseOrderType,
                                    double baseStopLoss,
                                    double channelRange,
                                    bool isSliced,
                                    double lotSize,
                                    datetime channelDefinitionTime)
{
   if(!EnableReversal || !g_isHedgingAccount)
      return false;

   TryRearmReversalBlockForNewDay();

   if(g_reversalBlockedByEntryHour)
      return false;

   if(!IsReversalAllowedByEntryHourNow())
   {
      if(g_preArmedReversalOrderTicket > 0)
         CancelPreArmedReversalOrder("horario limite de entrada atingido");
      if(!g_reversalBlockedByEntryHour)
      {
         MarkReversalBlockedByEntryHour();
         Print("INFO: virada pre-armada bloqueada por horario limite de entrada.");
      }
      return false;
   }

   if(baseOrderType != ORDER_TYPE_BUY && baseOrderType != ORDER_TYPE_SELL)
      return false;
   if(baseStopLoss <= 0.0 || channelRange <= 0.0 || lotSize <= 0.0)
      return false;
   if(g_tradeReversal)
      return false;
   if(g_preArmedReversalOrderTicket > 0 && (OrderSelect(g_preArmedReversalOrderTicket) || PositionSelectByTicket(g_preArmedReversalOrderTicket)))
      return true;

   if(IsDrawdownLimitReached("PlacePreArmedReversalStopOrder"))
      return false;

   ENUM_ORDER_TYPE reversalType = (baseOrderType == ORDER_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   if(!IsTradingAllowedForOrder(reversalType, "PlacePreArmedReversalStopOrder"))
      return false;
   double entryPrice = NormalizePriceToTick(baseStopLoss);
   double baseMultiplier = isSliced ? SlicedMultiplier : ReversalMultiplier;
   double slFactor = (ReversalSLDistanceFactor > 0.0) ? ReversalSLDistanceFactor : 1.0;
   double tpFactor = (ReversalTPDistanceFactor > 0.0) ? ReversalTPDistanceFactor : 1.0;
   double slDistance = baseMultiplier * slFactor * channelRange;
   double tpDistance = baseMultiplier * tpFactor * channelRange;
   if(slDistance <= 0.0 || tpDistance <= 0.0)
      return false;

   double revStopLossBase = (reversalType == ORDER_TYPE_BUY) ? (entryPrice - slDistance) : (entryPrice + slDistance);
   double slIncrement = slDistance * (StopLossIncrement / 100.0);
   double revStopLoss = (reversalType == ORDER_TYPE_BUY) ? (revStopLossBase - slIncrement) : (revStopLossBase + slIncrement);
   double revTakeProfit = (reversalType == ORDER_TYPE_BUY) ? (entryPrice + tpDistance) : (entryPrice - tpDistance);

   if(IsFixedLotAllEntriesEnabled())
      lotSize = ResolveFixedLotAllEntries();
   else
      lotSize = NormalizeLot(lotSize);
   revStopLoss = NormalizePriceToTick(revStopLoss);
   revTakeProfit = NormalizePriceToTick(revTakeProfit);
   if(lotSize <= 0.0)
      return false;
   if(!ValidateOrderProtectionLevels(reversalType, entryPrice, revStopLoss, revTakeProfit, "PlacePreArmedReversalStopOrder"))
      return false;

   bool result = false;
   if(reversalType == ORDER_TYPE_BUY)
      result = trade.BuyStop(lotSize, entryPrice, _Symbol, revStopLoss, revTakeProfit, ORDER_TIME_GTC, 0, "Virada Prearmada");
   else
      result = trade.SellStop(lotSize, entryPrice, _Symbol, revStopLoss, revTakeProfit, ORDER_TIME_GTC, 0, "Virada Prearmada");

   long retcode = trade.ResultRetcode();
   if(result && IsTradeRetcodeAccepted(retcode, true) && trade.ResultOrder() > 0)
   {
      g_preArmedReversalOrderTicket = trade.ResultOrder();
      g_preArmedReversalOrderType = reversalType;
      g_preArmedReversalStopLoss = revStopLoss;
      g_preArmedReversalTakeProfit = revTakeProfit;
      g_preArmedReversalChannelRange = channelRange;
      g_preArmedReversalLotSize = lotSize;
      g_preArmedReversalIsSliced = isSliced;
      g_preArmedReversalChannelDefinitionTime = channelDefinitionTime;

      Print("INFO: virada pre-armada por STOP criada. Ticket=", g_preArmedReversalOrderTicket,
            " | tipo=", EnumToString(reversalType),
            " | entrada=", entryPrice,
            " | SL=", revStopLoss,
            " | TP=", revTakeProfit,
            " | lote=", lotSize);
      return true;
   }

   Print("WARN: falha ao criar virada pre-armada por STOP | retcode=", retcode, " | ", trade.ResultRetcodeDescription());
   return false;
}

bool EnsurePreArmedReversalForCurrentTrade()
{
   if(g_currentTicket == 0 || g_tradeReversal)
      return false;

   // Regra PCM: operacao PCM nao faz turnof em nenhuma situacao.
   if(g_tradePCM)
      return false;

   double channelRange = (g_channelRange > 0.0) ? g_channelRange : g_preArmedReversalChannelRange;
   if(channelRange <= 0.0)
      channelRange = g_preArmedReversalChannelRange;
   if(channelRange <= 0.0)
      return false;

   datetime channelDefinitionTime = g_tradeChannelDefinitionTime;
   if(channelDefinitionTime <= 0)
      channelDefinitionTime = g_channelDefinitionTime;

   return PlacePreArmedReversalStopOrder(g_currentOrderType,
                                         g_firstTradeStopLoss,
                                         channelRange,
                                         g_tradeSliced,
                                         g_firstTradeLotSize,
                                         channelDefinitionTime);
}

bool TryAdoptTriggeredPreArmedReversal(bool fromOvernightFlow)
{
   if(g_preArmedReversalOrderTicket == 0)
      return false;

   if(OrderSelect(g_preArmedReversalOrderTicket))
      return false; // Ainda pendente.

   ulong reversalTicket = g_preArmedReversalOrderTicket;
   if(!PositionSelectByTicket(reversalTicket))
   {
      // Fallback para hedging: localizar por symbol+magic+direcao.
      datetime minEntryTime = g_tradeEntryTime;
      if(minEntryTime <= 0)
         minEntryTime = TimeCurrent() - 24 * 60 * 60;
      datetime bestTime = 0;
      ulong bestTicket = 0;
      int totalPositions = PositionsTotal();
      for(int i = 0; i < totalPositions; i++)
      {
         ulong posTicket = PositionGetTicket(i);
         if(posTicket == 0 || !PositionSelectByTicket(posTicket))
            continue;

         string symbol = PositionGetString(POSITION_SYMBOL);
         ulong magic = (ulong)PositionGetInteger(POSITION_MAGIC);
         if(symbol != _Symbol || magic != MagicNumber)
            continue;

         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         ENUM_ORDER_TYPE posOrderType = (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
         if(posOrderType != g_preArmedReversalOrderType)
            continue;

         datetime posTime = (datetime)PositionGetInteger(POSITION_TIME);
         if(posTime + 1 < minEntryTime)
            continue;

         if(bestTicket == 0 || posTime > bestTime)
         {
            bestTicket = posTicket;
            bestTime = posTime;
         }
      }

      if(bestTicket > 0 && PositionSelectByTicket(bestTicket))
      {
         reversalTicket = bestTicket;
      }
      else if(HistoryOrderSelect(g_preArmedReversalOrderTicket))
      {
         // Se a ordem nao esta pendente nem em posicao, limpa estado para evitar lixo.
         long state = HistoryOrderGetInteger(g_preArmedReversalOrderTicket, ORDER_STATE);
         if(state == ORDER_STATE_CANCELED || state == ORDER_STATE_REJECTED ||
            state == ORDER_STATE_EXPIRED || state == ORDER_STATE_FILLED)
         {
            ClearPreArmedReversalState();
         }
      }
      return false;
   }

   double reversalEntryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double reversalVolume = PositionGetDouble(POSITION_VOLUME);
   datetime reversalEntryTime = (datetime)PositionGetInteger(POSITION_TIME);
   double reversalStopLoss = PositionGetDouble(POSITION_SL);
   double reversalTakeProfit = PositionGetDouble(POSITION_TP);
   if(reversalStopLoss <= 0.0)
      reversalStopLoss = g_preArmedReversalStopLoss;
   if(reversalTakeProfit <= 0.0)
      reversalTakeProfit = g_preArmedReversalTakeProfit;

   if(fromOvernightFlow && AllowTradeWithOvernight)
   {
      int resolvedChainId = g_lastClosedOvernightChainIdHint;
      if(resolvedChainId <= 0)
         resolvedChainId = g_overnightChainId;
      if(resolvedChainId <= 0)
         resolvedChainId = g_currentOperationChainId;
      if(resolvedChainId <= 0)
         resolvedChainId = NextOperationChainId();

      g_overnightTicket = reversalTicket;
      g_overnightEntryTime = reversalEntryTime;
      g_overnightEntryPrice = reversalEntryPrice;
      g_overnightStopLoss = reversalStopLoss;
      g_overnightTakeProfit = reversalTakeProfit;
      g_overnightChannelRange = g_preArmedReversalChannelRange;
      g_overnightLotSize = reversalVolume;
      g_overnightSliced = g_preArmedReversalIsSliced;
      g_overnightReversal = true;
      g_overnightPCM = false;
      g_overnightOrderType = g_preArmedReversalOrderType;
      g_overnightChannelDefinitionTime = g_preArmedReversalChannelDefinitionTime;
      g_overnightEntryExecutionType = "STOP";
      g_overnightTriggerTime = reversalEntryTime;
      g_overnightMaxFloatingProfit = 0;
      g_overnightMaxFloatingDrawdown = 0;
      g_overnightMaxAdverseToSLPercent = 0;
      g_overnightMaxFavorableToTPPercent = 0;
      g_overnightChainId = resolvedChainId;

      AddOvernightLogSnapshot(g_overnightTicket,
                              g_overnightEntryTime,
                              g_overnightEntryPrice,
                              g_overnightStopLoss,
                              g_overnightTakeProfit,
                              g_overnightSliced,
                              g_overnightReversal,
                              g_overnightPCM,
                              g_overnightOrderType,
                              g_overnightChannelDefinitionTime,
                              g_overnightEntryExecutionType,
                              g_overnightTriggerTime,
                              g_overnightMaxFloatingProfit,
                              g_overnightMaxFloatingDrawdown,
                              g_overnightMaxAdverseToSLPercent,
                              g_overnightMaxFavorableToTPPercent,
                              g_overnightChannelRange,
                              g_overnightLotSize,
                              g_overnightChainId);

      g_currentTicket = 0;
      ClearCurrentTradePositionTickets();
      ResetNegativeAddState();
      ResetCurrentTradeFloatingMetrics();
      ClearPreArmedReversalState();
      g_lastClosedOvernightChainIdHint = 0;

      Print("INFO: virada pre-armada (STOP) acionada no fluxo overnight. Ticket: ", g_overnightTicket);
      return true;
   }

   g_currentTicket = reversalTicket;
   ClearCurrentTradePositionTickets();
   TrackCurrentTradePositionTicket(g_currentTicket);
   g_currentOrderType = g_preArmedReversalOrderType;
   g_firstTradeLotSize = reversalVolume;
   g_firstTradeStopLoss = reversalStopLoss;
   g_firstTradeTakeProfit = reversalTakeProfit;
   g_firstTradeExecuted = true;
   g_reversalTradeExecuted = true;
   g_channelRange = g_preArmedReversalChannelRange;
   g_tradeEntryTime = reversalEntryTime;
   g_tradeEntryPrice = reversalEntryPrice;
   g_tradeReversal = true;
   g_tradePCM = false;
   g_tradeSliced = g_preArmedReversalIsSliced;
   g_tradeChannelDefinitionTime = g_preArmedReversalChannelDefinitionTime;
   g_tradeEntryExecutionType = "STOP";
   g_tradeTriggerTime = reversalEntryTime;
   int chainIdForCurrentTrade = g_lastClosedOvernightChainIdHint;
   if(chainIdForCurrentTrade <= 0)
      chainIdForCurrentTrade = g_currentOperationChainId;
   AdoptOperationChainId(chainIdForCurrentTrade);
   ResetNegativeAddState();
   ResetCurrentTradeFloatingMetrics();
   if(ShouldUseLimitForNegativeAddOn() && g_negativeAddRuntimeEnabled)
      PlaceNegativeAddOnLimitOrdersForStrictMode(g_tradeEntryPrice);

   ClearPreArmedReversalState();
   g_lastClosedOvernightChainIdHint = 0;
   Print("INFO: virada pre-armada (STOP) adotada como operacao atual. Ticket: ", g_currentTicket);
   return true;
}

bool IsTradeRetcodeAccepted(long retcode, bool allowPlaced = true)
{
   if(retcode == TRADE_RETCODE_DONE || retcode == TRADE_RETCODE_DONE_PARTIAL)
      return true;
   if(allowPlaced && retcode == TRADE_RETCODE_PLACED)
      return true;
   return false;
}

bool ConfigureTradeFillingMode()
{
   if(trade.SetTypeFillingBySymbol(_Symbol))
   {
      long fillingFlags = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
      Print("INFO: modo de preenchimento configurado pelo simbolo. flags=", fillingFlags);
      return true;
   }

   trade.SetTypeFilling(ORDER_FILLING_IOC);
   Print("WARN: falha ao configurar filling por simbolo. Fallback para IOC.");
   return false;
}

bool IsLikelyNegativeAddComment(string comment)
{
   if(StringFind(comment, "AddOn") >= 0 || StringFind(comment, "addon") >= 0)
      return true;
   if(StringFind(comment, "adicao") >= 0 || StringFind(comment, "Adicao") >= 0)
      return true;
   return false;
}

bool IsLikelyPCMComment(string comment)
{
   return (StringFind(comment, "PCM") >= 0 || StringFind(comment, "pcm") >= 0);
}

bool IsLikelyReversalComment(string comment)
{
   if(StringFind(comment, "Virada") >= 0 || StringFind(comment, "virada") >= 0)
      return true;
   if(StringFind(comment, "turnof") >= 0 || StringFind(comment, "Turnof") >= 0)
      return true;
   return false;
}

bool IsLikelySlicedComment(string comment)
{
   return (StringFind(comment, "Sliced") >= 0 || StringFind(comment, "sliced") >= 0);
}

bool IsLikelyPreArmedReversalComment(string comment)
{
   if(StringFind(comment, "Prearmada") >= 0 || StringFind(comment, "prearmada") >= 0)
      return true;
   if(StringFind(comment, "PreArmed") >= 0 || StringFind(comment, "prearmed") >= 0)
      return true;
   return false;
}

ENUM_ORDER_TYPE ResolveDirectionalOrderType(ENUM_ORDER_TYPE orderType)
{
   if(orderType == ORDER_TYPE_BUY || orderType == ORDER_TYPE_BUY_LIMIT ||
      orderType == ORDER_TYPE_BUY_STOP || orderType == ORDER_TYPE_BUY_STOP_LIMIT)
      return ORDER_TYPE_BUY;
   if(orderType == ORDER_TYPE_SELL || orderType == ORDER_TYPE_SELL_LIMIT ||
      orderType == ORDER_TYPE_SELL_STOP || orderType == ORDER_TYPE_SELL_STOP_LIMIT)
      return ORDER_TYPE_SELL;
   return ORDER_TYPE_BUY;
}

bool IsDirectionalPendingOrderType(ENUM_ORDER_TYPE orderType, ENUM_ORDER_TYPE direction)
{
   if(direction == ORDER_TYPE_BUY)
      return (orderType == ORDER_TYPE_BUY_LIMIT || orderType == ORDER_TYPE_BUY_STOP || orderType == ORDER_TYPE_BUY_STOP_LIMIT);
   if(direction == ORDER_TYPE_SELL)
      return (orderType == ORDER_TYPE_SELL_LIMIT || orderType == ORDER_TYPE_SELL_STOP || orderType == ORDER_TYPE_SELL_STOP_LIMIT);
   return false;
}

bool IsMainPendingOrderType(ENUM_ORDER_TYPE orderType)
{
   return (orderType == ORDER_TYPE_BUY_LIMIT || orderType == ORDER_TYPE_SELL_LIMIT);
}

EPendingOrderContext ResolvePendingContextFromComment(string comment)
{
   bool isOvernight = (StringFind(comment, "Overnight") >= 0 || StringFind(comment, "overnight") >= 0);
   if(isOvernight)
      return PENDING_CONTEXT_OVERNIGHT_REVERSAL;
   if(IsLikelyReversalComment(comment))
      return PENDING_CONTEXT_REVERSAL;
   return PENDING_CONTEXT_FIRST_ENTRY;
}

double GetBrokerMinProtectionDistancePrice()
{
   if(!EnableP0BrokerStopLevelValidation)
      return 0.0;

   long stopsLevelPoints = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freezeLevelPoints = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   long requiredPoints = MathMax(stopsLevelPoints, freezeLevelPoints);
   if(requiredPoints <= 0 || g_pointValue <= 0.0)
      return 0.0;
   return (requiredPoints * g_pointValue);
}

bool ValidateOrderProtectionLevels(ENUM_ORDER_TYPE orderType,
                                   double entryPrice,
                                   double stopLoss,
                                   double takeProfit,
                                   string context)
{
   if(!EnableP0BrokerStopLevelValidation)
      return true;
   if(entryPrice <= 0.0 || stopLoss <= 0.0 || takeProfit <= 0.0)
      return false;

   bool directionalOk = false;
   if(orderType == ORDER_TYPE_BUY)
      directionalOk = (stopLoss < entryPrice && takeProfit > entryPrice);
   else if(orderType == ORDER_TYPE_SELL)
      directionalOk = (stopLoss > entryPrice && takeProfit < entryPrice);
   if(!directionalOk)
   {
      Print("WARN: ", context, " bloqueado por SL/TP invalido para o lado da ordem.",
            " entry=", entryPrice, " sl=", stopLoss, " tp=", takeProfit);
      return false;
   }

   double requiredDistance = GetBrokerMinProtectionDistancePrice();
   if(requiredDistance <= 0.0)
      return true;

   double epsilon = (g_pointValue > 0.0) ? (g_pointValue * 0.1) : 0.0;
   double slDistance = MathAbs(entryPrice - stopLoss);
   double tpDistance = MathAbs(takeProfit - entryPrice);
   if(slDistance + epsilon < requiredDistance || tpDistance + epsilon < requiredDistance)
   {
      Print("WARN: ", context, " bloqueado por distancia minima do broker.",
            " required=", DoubleToString(requiredDistance / g_pointValue, 1), " pontos",
            " | distSL=", DoubleToString(slDistance / g_pointValue, 1),
            " | distTP=", DoubleToString(tpDistance / g_pointValue, 1));
      return false;
   }

   return true;
}

bool IsTradingAllowedForOrder(ENUM_ORDER_TYPE orderType, string context)
{
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
   {
      Print("WARN: ", context, " bloqueado porque trading nao esta permitido no terminal/EA.");
      return false;
   }

   long tradeMode = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);
   if(tradeMode == SYMBOL_TRADE_MODE_DISABLED || tradeMode == SYMBOL_TRADE_MODE_CLOSEONLY)
   {
      Print("WARN: ", context, " bloqueado pelo SYMBOL_TRADE_MODE=", tradeMode);
      return false;
   }

   if(orderType == ORDER_TYPE_BUY && tradeMode == SYMBOL_TRADE_MODE_SHORTONLY)
   {
      Print("WARN: ", context, " bloqueado. simbolo permite apenas SELL no momento.");
      return false;
   }
   if(orderType == ORDER_TYPE_SELL && tradeMode == SYMBOL_TRADE_MODE_LONGONLY)
   {
      Print("WARN: ", context, " bloqueado. simbolo permite apenas BUY no momento.");
      return false;
   }

   return true;
}

ulong FindLatestEAPositionTicketByType(ENUM_ORDER_TYPE direction, datetime minEntryTime = 0)
{
   ulong bestTicket = 0;
   datetime bestTime = 0;

   int totalPositions = PositionsTotal();
   for(int i = 0; i < totalPositions; i++)
   {
      ulong posTicket = PositionGetTicket(i);
      if(posTicket == 0 || !PositionSelectByTicket(posTicket))
         continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      ulong magic = (ulong)PositionGetInteger(POSITION_MAGIC);
      if(symbol != _Symbol || magic != MagicNumber)
         continue;

      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      ENUM_ORDER_TYPE posDirection = (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      if(direction == ORDER_TYPE_BUY || direction == ORDER_TYPE_SELL)
      {
         if(posDirection != direction)
            continue;
      }

      datetime posTime = (datetime)PositionGetInteger(POSITION_TIME);
      if(minEntryTime > 0 && posTime + 2 < minEntryTime)
         continue;

      if(bestTicket == 0 || posTime > bestTime)
      {
         bestTicket = posTicket;
         bestTime = posTime;
      }
   }

   return bestTicket;
}

ulong FindLatestEAPendingOrderTicketByDirection(ENUM_ORDER_TYPE direction,
                                                datetime minSetupTime = 0,
                                                string preferredComment = "",
                                                bool onlyMainLimitOrders = false)
{
   ulong bestTicket = 0;
   datetime bestTime = 0;

   int totalOrders = OrdersTotal();
   for(int i = 0; i < totalOrders; i++)
   {
      ulong orderTicket = OrderGetTicket(i);
      if(orderTicket == 0 || !OrderSelect(orderTicket))
         continue;

      string symbol = OrderGetString(ORDER_SYMBOL);
      ulong magic = (ulong)OrderGetInteger(ORDER_MAGIC);
      if(symbol != _Symbol || magic != MagicNumber)
         continue;

      ENUM_ORDER_TYPE orderType = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(onlyMainLimitOrders && !IsMainPendingOrderType(orderType))
         continue;
      if(!IsDirectionalPendingOrderType(orderType, direction))
         continue;

      string orderComment = OrderGetString(ORDER_COMMENT);
      if(IsLikelyNegativeAddComment(orderComment))
         continue;
      if(IsLikelyPreArmedReversalComment(orderComment))
         continue;

      if(preferredComment != "" &&
         StringFind(orderComment, preferredComment) < 0)
         continue;

      datetime setupTime = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
      if(minSetupTime > 0 && setupTime + 2 < minSetupTime)
         continue;

      if(bestTicket == 0 || setupTime > bestTime)
      {
         bestTicket = orderTicket;
         bestTime = setupTime;
      }
   }

   return bestTicket;
}

bool TryResolvePositionTicketFromTradeResult(ENUM_ORDER_TYPE direction, datetime requestTime, ulong &positionTicketOut)
{
   positionTicketOut = 0;

   ulong resultDeal = trade.ResultDeal();
   if(resultDeal > 0 && HistoryDealSelect(resultDeal))
   {
      long positionId = HistoryDealGetInteger(resultDeal, DEAL_POSITION_ID);
      if(positionId > 0)
      {
         positionTicketOut = (ulong)positionId;
         return true;
      }
   }

   ulong resultOrder = trade.ResultOrder();
   if(resultOrder > 0)
   {
      if(PositionSelectByTicket(resultOrder))
      {
         positionTicketOut = resultOrder;
         return true;
      }

      if(HistoryOrderSelect(resultOrder))
      {
         long orderPositionId = HistoryOrderGetInteger(resultOrder, ORDER_POSITION_ID);
         if(orderPositionId > 0)
         {
            ulong mappedTicket = (ulong)orderPositionId;
            if(PositionSelectByTicket(mappedTicket))
            {
               positionTicketOut = mappedTicket;
               return true;
            }
         }
      }
   }

   datetime minEntryTime = requestTime;
   if(minEntryTime <= 0)
      minEntryTime = TimeCurrent() - 10;
   else
      minEntryTime -= 10;
   ulong latestTicket = FindLatestEAPositionTicketByType(direction, minEntryTime);
   if(latestTicket > 0)
   {
      positionTicketOut = latestTicket;
      return true;
   }

   if(resultOrder > 0)
   {
      positionTicketOut = resultOrder;
      return true;
   }

   return false;
}

bool TryResolvePendingOrderTicketFromTradeResult(ENUM_ORDER_TYPE direction,
                                                 datetime requestTime,
                                                 string preferredComment,
                                                 ulong &orderTicketOut)
{
   orderTicketOut = 0;

   ulong resultOrder = trade.ResultOrder();
   if(resultOrder > 0 && OrderSelect(resultOrder))
   {
      orderTicketOut = resultOrder;
      return true;
   }
   if(resultOrder > 0)
   {
      orderTicketOut = resultOrder;
      return true;
   }

   datetime minSetupTime = requestTime;
   if(minSetupTime <= 0)
      minSetupTime = TimeCurrent() - 10;
   else
      minSetupTime -= 10;

   orderTicketOut = FindLatestEAPendingOrderTicketByDirection(direction, minSetupTime, preferredComment, true);
   if(orderTicketOut > 0)
      return true;

   orderTicketOut = FindLatestEAPendingOrderTicketByDirection(direction, minSetupTime, "", true);
   if(orderTicketOut > 0)
      return true;

   return false;
}

void SyncPreArmedReversalStateFromOrderTicket(ulong orderTicket)
{
   if(orderTicket == 0 || !OrderSelect(orderTicket))
      return;

   ENUM_ORDER_TYPE pendingType = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
   g_preArmedReversalOrderTicket = orderTicket;
   g_preArmedReversalOrderType = ResolveDirectionalOrderType(pendingType);
   g_preArmedReversalStopLoss = OrderGetDouble(ORDER_SL);
   g_preArmedReversalTakeProfit = OrderGetDouble(ORDER_TP);
   g_preArmedReversalLotSize = OrderGetDouble(ORDER_VOLUME_CURRENT);
   if(g_preArmedReversalLotSize <= 0.0)
      g_preArmedReversalLotSize = OrderGetDouble(ORDER_VOLUME_INITIAL);
   g_preArmedReversalIsSliced = g_tradeSliced;
   g_preArmedReversalChannelDefinitionTime = g_tradeChannelDefinitionTime;
}

bool RehydrateRuntimeStateOnInit()
{
   if(!EnableP0InitStateRecovery)
      return false;

   bool rehydrated = false;

   // 1) Recuperar posicao aberta para evitar nova entrada apos restart.
   ulong allPositionTickets[];
   ArrayResize(allPositionTickets, 0);
   ulong latestPositionTicket = 0;
   datetime latestPositionTime = 0;

   int totalPositions = PositionsTotal();
   for(int i = 0; i < totalPositions; i++)
   {
      ulong posTicket = PositionGetTicket(i);
      if(posTicket == 0 || !PositionSelectByTicket(posTicket))
         continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      ulong magic = (ulong)PositionGetInteger(POSITION_MAGIC);
      if(symbol != _Symbol || magic != MagicNumber)
         continue;

      int n = ArraySize(allPositionTickets);
      ArrayResize(allPositionTickets, n + 1);
      allPositionTickets[n] = posTicket;

      datetime posTime = (datetime)PositionGetInteger(POSITION_TIME);
      if(latestPositionTicket == 0 || posTime > latestPositionTime)
      {
         latestPositionTicket = posTicket;
         latestPositionTime = posTime;
      }
   }

   if(latestPositionTicket > 0 && PositionSelectByTicket(latestPositionTicket))
   {
      bool hasOrderType = false;
      ENUM_ORDER_TYPE recoveredOrderType = ResolveOrderTypeFromPositionTicket(latestPositionTicket, hasOrderType);
      if(hasOrderType)
      {
         g_currentTicket = latestPositionTicket;
         g_currentOrderType = recoveredOrderType;
         g_firstTradeLotSize = PositionGetDouble(POSITION_VOLUME);
         g_firstTradeStopLoss = PositionGetDouble(POSITION_SL);
         g_firstTradeTakeProfit = PositionGetDouble(POSITION_TP);
         g_firstTradeExecuted = true;
         g_reversalTradeExecuted = false;
         g_pendingOrderPlaced = false;
         ResetPendingOrderContext();
         ClearCurrentTradePositionTickets();
         TrackCurrentTradePositionTickets(allPositionTickets);

         datetime earliestTime = latestPositionTime;
         for(int i = 0; i < ArraySize(allPositionTickets); i++)
         {
            ulong trackedTicket = allPositionTickets[i];
            if(trackedTicket == 0 || !PositionSelectByTicket(trackedTicket))
               continue;
            datetime trackedTime = (datetime)PositionGetInteger(POSITION_TIME);
            if(earliestTime <= 0 || (trackedTime > 0 && trackedTime < earliestTime))
               earliestTime = trackedTime;
         }
         g_tradeEntryTime = earliestTime;
         if(g_tradeEntryTime <= 0)
            g_tradeEntryTime = latestPositionTime;
         g_tradeEntryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         string posComment = PositionGetString(POSITION_COMMENT);
         g_tradeReversal = IsLikelyReversalComment(posComment);
         g_tradePCM = IsLikelyPCMComment(posComment);
         g_tradeSliced = IsLikelySlicedComment(posComment);
         g_tradeChannelDefinitionTime = 0;
         g_tradeEntryExecutionType = "MARKET";
         g_tradeTriggerTime = g_tradeEntryTime;
         ResetCurrentTradeFloatingMetrics();
         ResetNegativeAddState();
         if(g_currentOperationChainId <= 0)
            StartNewOperationChain();

         rehydrated = true;
         Print("P0: estado reidratado por posicao aberta. ticket=", g_currentTicket,
               " | tipo=", EnumToString(g_currentOrderType),
               " | posicoes=", ArraySize(allPositionTickets));
      }
   }

   // 2) Recuperar ordem pendente principal quando nao ha posicao aberta.
   if(!rehydrated)
   {
      ulong latestPendingTicket = 0;
      datetime latestPendingSetup = 0;
      ENUM_ORDER_TYPE latestPendingType = ORDER_TYPE_BUY_LIMIT;
      string latestPendingComment = "";
      int totalOrders = OrdersTotal();
      for(int i = 0; i < totalOrders; i++)
      {
         ulong orderTicket = OrderGetTicket(i);
         if(orderTicket == 0 || !OrderSelect(orderTicket))
            continue;

         string symbol = OrderGetString(ORDER_SYMBOL);
         ulong magic = (ulong)OrderGetInteger(ORDER_MAGIC);
         if(symbol != _Symbol || magic != MagicNumber)
            continue;

         ENUM_ORDER_TYPE orderType = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
         if(!IsMainPendingOrderType(orderType))
            continue;

         string orderComment = OrderGetString(ORDER_COMMENT);
         if(IsLikelyNegativeAddComment(orderComment))
            continue;
         if(IsLikelyPreArmedReversalComment(orderComment))
            continue;

         datetime setupTime = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
         if(latestPendingTicket == 0 || setupTime > latestPendingSetup)
         {
            latestPendingTicket = orderTicket;
            latestPendingSetup = setupTime;
            latestPendingType = orderType;
            latestPendingComment = orderComment;
         }
      }

      if(latestPendingTicket > 0 && OrderSelect(latestPendingTicket))
      {
         g_currentTicket = latestPendingTicket;
         g_pendingOrderPlaced = true;
         g_currentOrderType = ResolveDirectionalOrderType(latestPendingType);
         g_firstTradeLotSize = OrderGetDouble(ORDER_VOLUME_CURRENT);
         if(g_firstTradeLotSize <= 0.0)
            g_firstTradeLotSize = OrderGetDouble(ORDER_VOLUME_INITIAL);
         g_firstTradeStopLoss = OrderGetDouble(ORDER_SL);
         g_firstTradeTakeProfit = OrderGetDouble(ORDER_TP);
         g_pendingOrderContext = ResolvePendingContextFromComment(latestPendingComment);
         g_pendingOrderIsReversal = (g_pendingOrderContext != PENDING_CONTEXT_FIRST_ENTRY);
         g_pendingOrderIsSliced = IsLikelySlicedComment(latestPendingComment);
         g_pendingOrderIsPCM = IsLikelyPCMComment(latestPendingComment);
         g_pendingOrderChannelDefinitionTime = 0;
         g_pendingOrderTriggerTime = latestPendingSetup;
         g_pendingOrderSubmissionTime = latestPendingSetup;
         g_pendingOrderPreserveDailyCycle = (g_pendingOrderContext == PENDING_CONTEXT_OVERNIGHT_REVERSAL && AllowTradeWithOvernight);
         g_pendingOrderChannelRange = g_channelRange;
         g_pendingOrderLotSnapshot = g_firstTradeLotSize;
         g_firstTradeExecuted = (g_pendingOrderContext != PENDING_CONTEXT_FIRST_ENTRY);
         g_reversalTradeExecuted = false;
         g_tradeEntryTime = 0;
         g_tradeEntryPrice = 0;
         g_tradeReversal = false;
         g_tradePCM = false;
         g_tradeSliced = false;
         g_tradeChannelDefinitionTime = 0;
         g_tradeEntryExecutionType = "";
         g_tradeTriggerTime = 0;

         double pendingPrice = OrderGetDouble(ORDER_PRICE_OPEN);
         InitializePendingLimitTelemetry(pendingPrice,
                                         g_firstTradeStopLoss,
                                         g_firstTradeTakeProfit,
                                         g_currentOrderType);

         rehydrated = true;
         Print("P0: estado reidratado por ordem pendente. ticket=", g_currentTicket,
               " | contexto=", PendingOrderContextToString(g_pendingOrderContext));
      }
   }

   // 3) Reconciliar virada pre-armada pendente.
   ulong latestPreArmedTicket = 0;
   datetime latestPreArmedSetup = 0;
   int totalOrders = OrdersTotal();
   for(int i = 0; i < totalOrders; i++)
   {
      ulong orderTicket = OrderGetTicket(i);
      if(orderTicket == 0 || !OrderSelect(orderTicket))
         continue;

      string symbol = OrderGetString(ORDER_SYMBOL);
      ulong magic = (ulong)OrderGetInteger(ORDER_MAGIC);
      if(symbol != _Symbol || magic != MagicNumber)
         continue;

      string comment = OrderGetString(ORDER_COMMENT);
      if(!IsLikelyPreArmedReversalComment(comment))
         continue;

      datetime setupTime = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
      if(latestPreArmedTicket == 0 || setupTime > latestPreArmedSetup)
      {
         latestPreArmedTicket = orderTicket;
         latestPreArmedSetup = setupTime;
      }
   }

   bool hasBasePosition = (latestPositionTicket > 0);
   if(latestPreArmedTicket > 0)
   {
      if(hasBasePosition || (g_overnightTicket > 0 && PositionSelectByTicket(g_overnightTicket)))
      {
         SyncPreArmedReversalStateFromOrderTicket(latestPreArmedTicket);
         Print("P0: virada pre-armada reidratada. ticket=", g_preArmedReversalOrderTicket);
      }
      else if(EnableP0CancelOrphanPreArmedOnInit)
      {
         if(trade.OrderDelete(latestPreArmedTicket))
            Print("P0: virada pre-armada orfa cancelada no init. ticket=", latestPreArmedTicket);
         else
            Print("WARN: P0 nao conseguiu cancelar virada pre-armada orfa no init. ticket=", latestPreArmedTicket,
                  " | retcode=", trade.ResultRetcode(), " | ", trade.ResultRetcodeDescription());
         ClearPreArmedReversalState();
      }
      else
      {
         SyncPreArmedReversalStateFromOrderTicket(latestPreArmedTicket);
         Print("WARN: virada pre-armada sem base preservada por configuracao. ticket=", g_preArmedReversalOrderTicket);
      }
   }
   else
   {
      ClearPreArmedReversalState();
   }

   if(g_currentTicket > 0 && !g_pendingOrderPlaced && EnableReversal && !g_tradePCM && !g_tradeReversal &&
      g_isHedgingAccount && g_preArmedReversalOrderTicket == 0)
   {
      EnsurePreArmedReversalForCurrentTrade();
   }

   return rehydrated;
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   g_programName = MQLInfoString(MQL_PROGRAM_NAME);
   if(g_programName == "")
      g_programName = "prime_bot";
   int dotIdx = StringFind(g_programName, ".");
   if(dotIdx > 0)
      g_programName = StringSubstr(g_programName, 0, dotIdx);

   // Inicializar variaveis do simbolo
   g_pointValue = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   g_tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   g_tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(g_tickSize <= 0.0)
      g_tickSize = g_pointValue;
   g_accountMarginMode = AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   g_isHedgingAccount = (g_accountMarginMode == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
   g_minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   g_maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   g_lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   g_contractSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(30);
   ConfigureTradeFillingMode();
   trade.SetAsyncMode(false);

   g_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_peakEquity = g_dayStartEquity;
   g_initialAccountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(g_initialAccountBalance <= 0.0)
      g_initialAccountBalance = g_dayStartEquity;
   g_cachedDailyDrawdownPercent = 0.0;
   g_cachedMaxDrawdownPercent = 0.0;
   g_cachedDailyDrawdownAmount = 0.0;
   g_cachedMaxDrawdownAmount = 0.0;
   ClearCurrentTradePositionTickets();
   ResetPendingOrderContext();
   ResetReversalHourBlockState();
   ResetPCMStateForNewDay();
   ClearTickDrawdownHistory();

   g_negativeAddRuntimeDisableReason = "";
   g_negativeAddRuntimeEnabled = EnableNegativeAddOn;
   g_negativeAddTPAdjustRuntimeEnabled = EnableNegativeAddTPAdjustment;
   if(g_negativeAddRuntimeEnabled)
   {
      if(NegativeAddMaxEntries <= 0)
      {
         g_negativeAddRuntimeEnabled = false;
         if(g_negativeAddRuntimeDisableReason == "")
            g_negativeAddRuntimeDisableReason = "NegativeAddMaxEntries <= 0";
         Print("WARN: Adicao em flutuacao negativa desabilitada. NegativeAddMaxEntries <= 0.");
      }
      if(NegativeAddTriggerPercent <= 0.0)
      {
         g_negativeAddRuntimeEnabled = false;
         if(g_negativeAddRuntimeDisableReason == "")
            g_negativeAddRuntimeDisableReason = "NegativeAddTriggerPercent <= 0";
         Print("WARN: Adicao em flutuacao negativa desabilitada. NegativeAddTriggerPercent <= 0.");
      }
      if(NegativeAddLotMultiplier <= 0.0 && !IsFixedLotAllEntriesEnabled())
      {
         g_negativeAddRuntimeEnabled = false;
         if(g_negativeAddRuntimeDisableReason == "")
            g_negativeAddRuntimeDisableReason = "NegativeAddLotMultiplier <= 0";
         Print("WARN: Adicao em flutuacao negativa desabilitada. NegativeAddLotMultiplier <= 0.");
      }
      if(NegativeAddLotMultiplier <= 0.0 && IsFixedLotAllEntriesEnabled())
      {
         Print("INFO: NegativeAddLotMultiplier <= 0 ignorado porque lote fixo para entradas esta ativo.");
      }
   }
   if(g_negativeAddTPAdjustRuntimeEnabled)
   {
      if(!EnableNegativeAddOn)
      {
         g_negativeAddTPAdjustRuntimeEnabled = false;
         Print("WARN: Ajuste de TP apos addon desabilitado. EnableNegativeAddOn = false.");
      }
      if(NegativeAddTPDistancePercent <= 0.0)
      {
         g_negativeAddTPAdjustRuntimeEnabled = false;
         Print("WARN: Ajuste de TP apos addon desabilitado. NegativeAddTPDistancePercent <= 0.");
      }
   }
   if(ReversalSLDistanceFactor <= 0.0)
      Print("WARN: ReversalSLDistanceFactor <= 0. Sera usado 1.0 em runtime.");
   if(ReversalTPDistanceFactor <= 0.0)
      Print("WARN: ReversalTPDistanceFactor <= 0. Sera usado 1.0 em runtime.");
   if(EnablePCM && PCMChannelBars < 4)
      Print("WARN: PCM desabilitada em runtime. PCMChannelBars precisa ser >= 4.");
   if(EnablePCM && PCMMaxOperationsPerDay <= 0)
      Print("WARN: PCM desabilitada em runtime. PCMMaxOperationsPerDay precisa ser > 0.");
   if(EnablePCM && PCMReferenceTimeframe != PERIOD_M1 &&
      PCMReferenceTimeframe != PERIOD_M5 &&
      PCMReferenceTimeframe != PERIOD_M15)
   {
      Print("WARN: PCM desabilitada em runtime. PCMReferenceTimeframe deve ser M1, M5 ou M15.");
   }
   if(EnablePCM && PCMEnableSkipLargeCandle && PCMMaxCandlePoints <= 0.0)
      Print("WARN: filtro de candle grande do PCM ignorado. PCMMaxCandlePoints <= 0.");
   if(EnablePCM && PCMRiskPercent <= 0.0)
      Print("WARN: PCMRiskPercent <= 0. Entradas PCM usarao RiskPercent.");
   if(EnablePCM && PCMTPReductionPercent < 0.0)
      Print("WARN: PCMTPReductionPercent < 0. Sera usado 0 em runtime.");
   if(EnablePCM && PCMTPReductionPercent >= 100.0)
      Print("WARN: PCMTPReductionPercent >= 100. Sera limitado para 99.99 em runtime.");
   if(BreakEven && !EnablePCM)
      Print("WARN: BreakEven ativo, mas EnablePCM esta desabilitado.");
   if(TraillingStop && !EnablePCM)
      Print("WARN: TraillingStop ativo, mas EnablePCM esta desabilitado.");
   if(EnablePCMOnNoTradeLimitTarget && !EnablePCM)
      Print("WARN: EnablePCMOnNoTradeLimitTarget ativo, mas EnablePCM esta desabilitado.");

   // Inicializar log
   if(EnableLogging)
   {
      g_tradesLog = "{\"trades\": [";
      g_noTradesLog = "{\"no_trade_days\": [";
   }

   Print("=== Estrategia ", g_programName, " Iniciado ===");
   Print("Simbolo: ", _Symbol);
   Print("Horario Abertura: ", StringFormat("%02d:%02d", OpeningHour, OpeningMinute), " GMT");
   Print("Horario limite 1a entrada: ", FirstEntryMaxHour, ":00");
   Print("Horario limite entradas adicionais/virada: ", MaxEntryHour, ":00");
   Print("Risco: ", RiskPercent, "%");
   Print("Risco PCM: ", PCMRiskPercent, "%");
   Print("Base fixa de risco no deposito inicial: ", UseInitialDepositForRisk ? "Sim" : "Nao");
   Print("Lote fixo para todas as entradas (0 desativa): ", FixedLotAllEntries);
   Print("Lote fixo em runtime: ", IsFixedLotAllEntriesEnabled() ? "Ativo" : "Inativo");
   if(IsFixedLotAllEntriesEnabled())
      Print("Lote fixo normalizado: ", ResolveFixedLotAllEntries());
   Print("Saldo inicial de referencia (risco): ", g_initialAccountBalance);
   Print("Limite DD diario (%): ", MaxDailyDrawdownPercent);
   Print("Limite DD maximo (%): ", MaxDrawdownPercent);
   Print("Limite DD diario (abs): ", MaxDailyDrawdownAmount);
   Print("Limite DD maximo (abs): ", MaxDrawdownAmount);
   Print("Range: ", MinChannelRange, " - ", MaxChannelRange);
   Print("Tolerancia minima de rompimento (pontos): ", BreakoutMinTolerancePoints);
   Print("Timeframe Canal: ", EnumToString(ChannelTimeframe));
   Print("Fallback M15: ", EnableM15Fallback ? "Habilitado" : "Desabilitado");
   Print("Modo Limit Only Estrito: ", StrictLimitOnly ? "Ativo" : "Inativo");
   Print("Priorizar LIMIT entrada principal: ", PreferLimitMainEntry ? "Sim" : "Nao");
   Print("Priorizar LIMIT turnof: ", PreferLimitReversal ? "Sim" : "Nao");
   Print("Priorizar LIMIT virada overnight: ", PreferLimitOvernightReversal ? "Sim" : "Nao");
   Print("Priorizar LIMIT add-on negativo: ", PreferLimitNegativeAddOn ? "Sim" : "Nao");
   Print("LIMIT efetivo entrada principal: ", ShouldUseLimitForMainEntry() ? "Sim" : "Nao");
   Print("LIMIT efetivo add-on negativo: ", ShouldUseLimitForNegativeAddOn() ? "Sim" : "Nao");
   Print("Fallback mercado virada: ", AllowMarketFallbackReversal ? "Sim" : "Nao");
   Print("Fallback mercado virada overnight: ", AllowMarketFallbackOvernightReversal ? "Sim" : "Nao");
   Print("Adicao em flutuacao negativa: ", EnableNegativeAddOn ? "Habilitada" : "Desabilitada");
   Print("Adicao em flutuacao negativa (runtime): ", g_negativeAddRuntimeEnabled ? "Ativa" : "Inativa");
   if(!g_negativeAddRuntimeEnabled && EnableNegativeAddOn && g_negativeAddRuntimeDisableReason != "")
      Print("Motivo runtime inativa (adicao negativa): ", g_negativeAddRuntimeDisableReason);
   Print("Max adicoes por operacao: ", NegativeAddMaxEntries);
   Print("Trigger adicao (% ate SL): ", NegativeAddTriggerPercent, "%");
   Print("Multiplicador lote adicao: ", NegativeAddLotMultiplier, "x");
   Print("Adicao com mesmo SL/TP: ", NegativeAddUseSameSLTP ? "Sim" : "Nao");
   Print("Ajustar TP apos addon: ", EnableNegativeAddTPAdjustment ? "Habilitado" : "Desabilitado");
   Print("Ajustar TP apos addon (runtime): ", g_negativeAddTPAdjustRuntimeEnabled ? "Ativo" : "Inativo");
   Print("Distancia TP apos addon (% da dist. ate SL): ", NegativeAddTPDistancePercent, "%");
   Print("Ajustar TP apos addon em virada: ", NegativeAddTPAdjustOnReversal ? "Sim" : "Nao");
   Print("Debug adicao negativa: ", EnableNegativeAddDebugLogs ? "Ativo" : "Inativo");
   Print("Intervalo debug adicao (s): ", NegativeAddDebugIntervalSeconds);
   Print("Multiplicador Sliced: ", SlicedMultiplier, "x");
   Print("Reducao TP: ", TPReductionPercent, "%");
   Print("Incremento SL: ", StopLossIncrement, "%");
   Print("turnof: ", EnableReversal ? "Habilitada" : "Desabilitada");
   Print("turnof em Overnight: ", EnableOvernightReversal ? "Habilitada" : "Desabilitada");
   Print("Multiplicador base turnof: ", ReversalMultiplier, "x");
   Print("Fator distancia SL turnof: ", ReversalSLDistanceFactor, "x");
   Print("Fator distancia TP turnof: ", ReversalTPDistanceFactor, "x");
   Print("Permitir virada apos horario limite: ", AllowReversalAfterMaxEntryHour ? "Sim" : "Nao");
   Print("Rearmar virada cancelada no proximo dia: ", RearmCanceledReversalNextDay ? "Sim" : "Nao");
   Print("PCM: ", IsPCMEnabledRuntime() ? "Ativada" : "Desativada");
   Print("PCM - habilitar por NoTrade LIMIT alvo: ", EnablePCMOnNoTradeLimitTarget ? "Sim" : "Nao");
   Print("PCM - Break even: ", BreakEven ? "Ativo" : "Inativo");
   Print("PCM - Trailling stop: ", TraillingStop ? "Ativo" : "Inativo");
   Print("PCM - reducao TP (%): ", PCMTPReductionPercent);
   Print("PCM - timeframe referencia: ", EnumToString(PCMReferenceTimeframe));
   Print("PCM - barras para CA: ", PCMChannelBars);
   Print("PCM - max operacoes por dia: ", PCMMaxOperationsPerDay);
   Print("PCM - ignora FirstEntryMaxHour: ", PCMIgnoreFirstEntryMaxHour ? "Sim" : "Nao");
   Print("PCM - pular candle grande: ", PCMEnableSkipLargeCandle ? "Sim" : "Nao");
   Print("PCM - max pontos por candle: ", PCMMaxCandlePoints);
   Print("PCM - limite horario especifico: ", EnablePCMHourLimit ? "Ativo" : "Inativo");
   Print("PCM - horario limite: ", StringFormat("%02d:%02d", PCMEntryMaxHour, PCMEntryMaxMinute));
   Print("Operar com Overnight: ", AllowTradeWithOvernight ? "Sim" : "Nao");
   Print("Manter posicoes overnight: ", KeepPositionsOvernight ? "Sim" : "Nao");
   Print("Fechar antes do mercado: ", CloseMinutesBeforeMarketClose, " min");
   Print("Logging: ", EnableLogging ? "Habilitado" : "Desabilitado");

   string marginModeText = "UNKNOWN";
   if(g_accountMarginMode == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      marginModeText = "RETAIL_HEDGING";
   else if(g_accountMarginMode == ACCOUNT_MARGIN_MODE_RETAIL_NETTING)
      marginModeText = "RETAIL_NETTING";
   else if(g_accountMarginMode == ACCOUNT_MARGIN_MODE_EXCHANGE)
      marginModeText = "EXCHANGE";
   Print("ACCOUNT_MARGIN_MODE=", g_accountMarginMode, " (", marginModeText, ")");
   Print("Conta em modo hedging: ", g_isHedgingAccount ? "Sim" : "Nao");
   bool initRecoveryApplied = RehydrateRuntimeStateOnInit();
   Print("P0 - recovery init aplicado: ", initRecoveryApplied ? "Sim" : "Nao");
   Print("PENDENCIA P0: revisar retcodes especificos do broker para aceitar/rejeitar ordens (a confirmar depois).");
   g_lastResetTime = TimeCurrent();

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, "Channel_");
   Comment("");

   // Salvar logs
   if(EnableLogging)
   {
      SaveLogs();
   }

   Print("=== Estrategia ", g_programName, " Finalizado ===");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!g_backtestStartCaptured)
   {
      g_backtestStartTime = TimeCurrent();
      g_backtestStartCaptured = true;
      Print("INFO: Inicio do backtest capturado: ", TimeToString(g_backtestStartTime, TIME_DATE|TIME_SECONDS));
   }

   UpdateDrawdownMetrics();
   UpdateTickDrawdownTracking();
   CheckNewDay();
   CheckPositionStatus();
   if(ApplyNoOvernightPolicy())
      return;
   ProcessStrategy();
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.symbol != _Symbol)
      return;

   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;

   ulong dealTicket = trans.deal;
   if(dealTicket == 0 || !HistoryDealSelect(dealTicket))
      return;

   string dealSymbol = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
   ulong dealMagic = (ulong)HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
   if(dealSymbol != _Symbol || dealMagic != MagicNumber)
      return;

   long dealEntry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
   if(dealEntry != DEAL_ENTRY_IN)
      return;

   ulong dealOrder = (ulong)HistoryDealGetInteger(dealTicket, DEAL_ORDER);
   long positionIdRaw = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
   ulong dealPositionTicket = (positionIdRaw > 0) ? (ulong)positionIdRaw : 0;

   if(g_pendingOrderPlaced)
   {
      bool isTrackedPending = (g_currentTicket > 0 && dealOrder == g_currentTicket);
      bool canFallbackBind = (g_currentTicket == 0 && dealPositionTicket > 0);
      if((isTrackedPending || canFallbackBind) && dealPositionTicket > 0)
      {
         ulong oldTicket = g_currentTicket;
         g_currentTicket = dealPositionTicket;
         TrackCurrentTradePositionTicket(dealPositionTicket);
         Print("INFO: OnTradeTransaction vinculou pending order->position. order=", dealOrder,
               " | old_ticket=", oldTicket,
               " | position=", dealPositionTicket);
      }
   }
   else if(g_currentTicket > 0 && dealOrder == g_currentTicket && dealPositionTicket > 0)
   {
      g_currentTicket = dealPositionTicket;
      TrackCurrentTradePositionTicket(dealPositionTicket);
      Print("INFO: OnTradeTransaction atualizou ticket principal por mapeamento order->position. order=",
            dealOrder, " | position=", dealPositionTicket);
   }

   if(g_preArmedReversalOrderTicket > 0 && dealOrder == g_preArmedReversalOrderTicket && dealPositionTicket > 0)
   {
      Print("INFO: OnTradeTransaction detectou fill da virada pre-armada. order=", dealOrder,
            " | position=", dealPositionTicket);
   }
}

//+------------------------------------------------------------------+
//| Verifica novo dia                                                |
//+------------------------------------------------------------------+
void CheckNewDay()
{
   datetime currentTime = TimeCurrent();
   MqlDateTime currStruct, lastStruct;
   TimeToStruct(currentTime, currStruct);
   TimeToStruct(g_lastResetTime, lastStruct);

   if(currStruct.day != lastStruct.day || currStruct.mon != lastStruct.mon || currStruct.year != lastStruct.year)
   {
      ResetDaily();
   }
}

//+------------------------------------------------------------------+
//| Processa estrategia                                              |
//+------------------------------------------------------------------+
void ProcessStrategy()
{
   // Verificar se ordem pendente foi executada (ANTES de bloquear por ticket)
   CheckPendingOrderExecution();

   if(g_preArmedReversalOrderTicket > 0 && g_currentTicket == 0 && g_overnightTicket == 0 && !g_pendingOrderPlaced)
      CancelPreArmedReversalOrder("sem posicao base ativa");

   if(g_reversalTradeExecuted && !g_pendingOrderPlaced) return;

   if(g_pcmPendingActivation)
   {
      TryActivatePCMChannel();
      return;
   }

   // Nao abrir novas exposicoes se DD limite foi atingido.
   if(IsDrawdownLimitReached("ProcessStrategy"))
      return;

   // Bloquear apenas se tem posicao do dia atual (nao overnight)
   if(g_currentTicket > 0 && g_currentTicket != g_overnightTicket) return;

   if(!g_channelCalculated)
   {
      CalculateOpeningChannel();
      return;
   }

   // Se canal foi calculado mas e invalido, nao operar
   if(!g_channelValid) return;

   bool pcmEntryFlow = (g_pcmReady && IsPCMEnabledRuntime());
   if(g_firstTradeExecuted && !pcmEntryFlow) return;

   // Se ja tem ordem pendente, nao criar outra
   if(g_pendingOrderPlaced) return;

   // Verificar horario limite
   MqlDateTime time;
   TimeToStruct(TimeCurrent(), time);
   if(pcmEntryFlow)
   {
      if(g_pcmOperationsToday >= PCMMaxOperationsPerDay)
         return;

      if(IsAfterPCMEntryTimeLimit(time))
         return;

      if(!PCMIgnoreFirstEntryMaxHour && time.hour >= FirstEntryMaxHour)
         return;
   }
   else
   {
      if(time.hour >= FirstEntryMaxHour)
         return;
   }

   // Detectar rompimento
   DetectBreakout();
}

//+------------------------------------------------------------------+
//| Calcula canal de abertura                                        |
//+------------------------------------------------------------------+
void CalculateOpeningChannel()
{
   datetime currentTime = TimeCurrent();
   MqlDateTime currStruct;
   TimeToStruct(currentTime, currStruct);

   // Horario de abertura configuravel
   currStruct.hour = OpeningHour;
   currStruct.min = OpeningMinute;
   currStruct.sec = 0;
   datetime dayStart = StructToTime(currStruct);

   // Buscar velas do dia
   int totalBars = Bars(_Symbol, g_activeTimeframe);
   int barsFound = 0;

   double vela1_high = 0, vela1_low = 0;
   double vela2_high = 0, vela2_low = 0;
   double vela3_high = 0, vela3_low = 0;
   double vela4_high = 0, vela4_low = 0;
   datetime vela4_time = 0;

   // Percorrer velas da mais antiga para mais nova
   for(int i = totalBars - 1; i >= 0; i--)
   {
      datetime barTime = iTime(_Symbol, g_activeTimeframe, i);

      if(barTime >= dayStart)
      {
         barsFound++;

         if(barsFound == 1)
         {
            vela1_high = iHigh(_Symbol, g_activeTimeframe, i);
            vela1_low = iLow(_Symbol, g_activeTimeframe, i);
         }
         else if(barsFound == 2)
         {
            vela2_high = iHigh(_Symbol, g_activeTimeframe, i);
            vela2_low = iLow(_Symbol, g_activeTimeframe, i);
         }
         else if(barsFound == 3)
         {
            vela3_high = iHigh(_Symbol, g_activeTimeframe, i);
            vela3_low = iLow(_Symbol, g_activeTimeframe, i);
         }
         else if(barsFound == 4)
         {
            vela4_high = iHigh(_Symbol, g_activeTimeframe, i);
            vela4_low = iLow(_Symbol, g_activeTimeframe, i);
            vela4_time = barTime;
            break;
         }
      }
   }

   // Verificar se as 4 velas estao fechadas
   if(barsFound < 4)
      return;

   datetime vela4_closeTime = vela4_time + PeriodSeconds(g_activeTimeframe);
   if(currentTime < vela4_closeTime)
   {
      Print(" Aguardando fechamento da 4a vela... Fecha as: ", TimeToString(vela4_closeTime, TIME_MINUTES));
      return;
   }

   // Timestamp efetivo de definicao do canal (fechamento da 4a vela)
   g_channelDefinitionTime = vela4_closeTime;

   // Calcular range
   g_channelHigh = MathMax(MathMax(vela1_high, vela2_high), MathMax(vela3_high, vela4_high));
   g_channelLow = MathMin(MathMin(vela1_low, vela2_low), MathMin(vela3_low, vela4_low));
   g_channelRange = g_channelHigh - g_channelLow;

   Print(" Canal calculado:");
   Print("  High: ", g_channelHigh, " | Low: ", g_channelLow, " | Range: ", g_channelRange);

   // Validar range
   if(g_channelRange < MinChannelRange)
   {
      Print(" Range pequeno: ", g_channelRange, " < ", MinChannelRange);

      // Se flag M15 habilitada E timeframe atual e M5 E ainda nao tentou M15
      if(EnableM15Fallback && ChannelTimeframe == PERIOD_M5 && !g_usingM15)
      {
         Print(" Tentando canal M15...");
         g_usingM15 = true;
         g_activeTimeframe = PERIOD_M15;
         g_channelCalculated = false;
         return;
      }

      g_channelCalculated = true;
      g_channelValid = false;
      LogNoTrade("Range pequeno: " + DoubleToString(g_channelRange, 2));
      return;
   }

   // Verificar se e modo SLICED (range > 20)
   if(g_channelRange > SlicedThreshold)
   {
      Print(" MODO SLICED ativado! Range=", g_channelRange, " > ", SlicedThreshold);
      Print(" CA = C1 (sem projecoes)");

      // CA = C1 (sem projecoes)
      g_projectedHigh = g_channelHigh;
      g_projectedLow = g_channelLow;

      // C1 ja definido automaticamente
      g_cycle1Defined = true;
      g_cycle1Direction = "BOTH";  // Pode romper para cima ou para baixo
      g_cycle1High = g_channelHigh;
      g_cycle1Low = g_channelLow;

      g_channelCalculated = true;
      g_channelValid = true;

      Print(" C1: [", g_cycle1Low, " - ", g_cycle1High, "]");

      if(DrawChannels)
         DrawChannelLines();

      return;
   }

   // Modo NORMAL (range entre MinChannelRange e MaxChannelRange)
   if(g_channelRange > MaxChannelRange)
   {
      Print(" Range grande: ", g_channelRange, " > ", MaxChannelRange);
      g_channelCalculated = true;
      g_channelValid = false;
      LogNoTrade("Range grande: " + DoubleToString(g_channelRange, 2));
      return;
   }

   // Projetar canais (modo normal)
   g_projectedHigh = g_channelHigh + g_channelRange;
   g_projectedLow = g_channelLow - g_channelRange;
   g_channelCalculated = true;
   g_channelValid = true;

   Print(" Projetado: High=", g_projectedHigh, " | Low=", g_projectedLow);

   if(DrawChannels)
      DrawChannelLines();
}

//+------------------------------------------------------------------+
//| Desenha canais                                                    |
//+------------------------------------------------------------------+
void DrawChannelLines()
{
   ObjectsDeleteAll(0, "Channel_");

   // Linha vertical no candle de abertura (Cinza tracejado)
   datetime currentTime = TimeCurrent();
   MqlDateTime currStruct;
   TimeToStruct(currentTime, currStruct);
   currStruct.hour = OpeningHour;
   currStruct.min = OpeningMinute;
   currStruct.sec = 0;
   datetime dayStart = StructToTime(currStruct);

   ObjectCreate(0, "Channel_Opening_VLine", OBJ_VLINE, 0, dayStart, 0);
   ObjectSetInteger(0, "Channel_Opening_VLine", OBJPROP_COLOR, clrGray);
   ObjectSetInteger(0, "Channel_Opening_VLine", OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, "Channel_Opening_VLine", OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, "Channel_Opening_VLine", OBJPROP_BACK, true);

   // Canal de abertura - High (Azul)
   ObjectCreate(0, "Channel_Opening_High", OBJ_HLINE, 0, 0, g_channelHigh);
   ObjectSetInteger(0, "Channel_Opening_High", OBJPROP_COLOR, clrDodgerBlue);
   ObjectSetInteger(0, "Channel_Opening_High", OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, "Channel_Opening_High", OBJPROP_STYLE, STYLE_SOLID);

   // Canal de abertura - Low (Vermelho)
   ObjectCreate(0, "Channel_Opening_Low", OBJ_HLINE, 0, 0, g_channelLow);
   ObjectSetInteger(0, "Channel_Opening_Low", OBJPROP_COLOR, clrRed);
   ObjectSetInteger(0, "Channel_Opening_Low", OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, "Channel_Opening_Low", OBJPROP_STYLE, STYLE_SOLID);

   // Canal projetado acima (Verde)
   ObjectCreate(0, "Channel_Projected_High", OBJ_HLINE, 0, 0, g_projectedHigh);
   ObjectSetInteger(0, "Channel_Projected_High", OBJPROP_COLOR, clrLimeGreen);
   ObjectSetInteger(0, "Channel_Projected_High", OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, "Channel_Projected_High", OBJPROP_STYLE, STYLE_DASH);

   // Canal projetado abaixo (Laranja)
   ObjectCreate(0, "Channel_Projected_Low", OBJ_HLINE, 0, 0, g_projectedLow);
   ObjectSetInteger(0, "Channel_Projected_Low", OBJPROP_COLOR, clrOrange);
   ObjectSetInteger(0, "Channel_Projected_Low", OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, "Channel_Projected_Low", OBJPROP_STYLE, STYLE_DASH);

   // Label
   string info = StringFormat("Range: %.2f | High: %.2f | Low: %.2f",
                              g_channelRange, g_channelHigh, g_channelLow);

   ObjectCreate(0, "Channel_Info", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "Channel_Info", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, "Channel_Info", OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, "Channel_Info", OBJPROP_YDISTANCE, 30);
   ObjectSetString(0, "Channel_Info", OBJPROP_TEXT, info);
   ObjectSetInteger(0, "Channel_Info", OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, "Channel_Info", OBJPROP_FONTSIZE, 10);

   ChartRedraw();
   Print(" Canais desenhados");
}

double GetBreakoutToleranceDistance()
{
   if(BreakoutMinTolerancePoints <= 0.0)
      return 0.0;
   return BreakoutMinTolerancePoints * _Point;
}

bool IsBreakoutAbove(double closePrice, double level)
{
   return (closePrice > (level + GetBreakoutToleranceDistance()));
}

bool IsBreakoutBelow(double closePrice, double level)
{
   return (closePrice < (level - GetBreakoutToleranceDistance()));
}

//+------------------------------------------------------------------+
//| Detecta rompimento com logica de Ciclo 1 (C1)                   |
//+------------------------------------------------------------------+
void DetectBreakout()
{
   ENUM_TIMEFRAMES breakoutTimeframe = PERIOD_M5;
   if(g_pcmReady && IsPCMEnabledRuntime())
      breakoutTimeframe = g_pcmActiveTimeframe;
   double close = iClose(_Symbol, breakoutTimeframe, 1);
   double breakoutTolerance = GetBreakoutToleranceDistance();
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   int tolDigits = digits;
   if(tolDigits < 5)
      tolDigits = 5;

   // Modo SLICED: C1 ja definido como BOTH
   if(g_cycle1Direction == "BOTH")
   {
      // Rompimento para cima
      if(IsBreakoutAbove(close, g_cycle1High))
      {
         Print(" ROMPIMENTO COMPRA (sliced)! Close=", close, " > ", g_cycle1High);
         OpenFirstPosition(ORDER_TYPE_BUY);
         return;
      }

      // Rompimento para baixo
      if(IsBreakoutBelow(close, g_cycle1Low))
      {
         Print(" ROMPIMENTO VENDA (sliced)! Close=", close, " < ", g_cycle1Low);
         OpenFirstPosition(ORDER_TYPE_SELL);
         return;
      }

      return;
   }

   // Se C1 ainda nao foi definido, tentar definir
   if(!g_cycle1Defined)
   {
      // Rompimento para cima
      if(IsBreakoutAbove(close, g_channelHigh))
      {
         g_cycle1Direction = "UP";
         g_cycle1High = g_projectedHigh;
         g_cycle1Low = g_channelLow;
         g_cycle1Defined = true;
         double c1UpTrigger = g_channelHigh + breakoutTolerance;
         Print(" C1 definido (UP): [", g_cycle1Low, " - ", g_cycle1High, "]",
               " | Close=", close,
               " > Trigger=", DoubleToString(c1UpTrigger, tolDigits),
               " | TolPrice=", DoubleToString(breakoutTolerance, tolDigits),
               " | TolPoints=", DoubleToString(BreakoutMinTolerancePoints, 2));
         return;
      }

      // Rompimento para baixo
      if(IsBreakoutBelow(close, g_channelLow))
      {
         g_cycle1Direction = "DOWN";
         g_cycle1High = g_channelHigh;
         g_cycle1Low = g_projectedLow;
         g_cycle1Defined = true;
         double c1DownTrigger = g_channelLow - breakoutTolerance;
         Print(" C1 definido (DOWN): [", g_cycle1Low, " - ", g_cycle1High, "]",
               " | Close=", close,
               " < Trigger=", DoubleToString(c1DownTrigger, tolDigits),
               " | TolPrice=", DoubleToString(breakoutTolerance, tolDigits),
               " | TolPoints=", DoubleToString(BreakoutMinTolerancePoints, 2));
         return;
      }

      return;
   }

   // C1 ja definido - verificar entrada
   if(g_cycle1Direction == "UP")
   {
      // Continuacao: rompe high de C1
      if(IsBreakoutAbove(close, g_cycle1High))
      {
         Print(" ROMPIMENTO COMPRA (continuacao)! Close=", close, " > ", g_cycle1High);
         OpenFirstPosition(ORDER_TYPE_BUY);
         return;
      }

      // Reversao: rompe low do canal de abertura
      if(IsBreakoutBelow(close, g_channelLow))
      {
         Print(" ROMPIMENTO VENDA (reversao)! Close=", close, " < ", g_channelLow);
         OpenFirstPosition(ORDER_TYPE_SELL);
         return;
      }
   }
   else if(g_cycle1Direction == "DOWN")
   {
      // Continuacao: rompe low de C1
      if(IsBreakoutBelow(close, g_cycle1Low))
      {
         Print(" ROMPIMENTO VENDA (continuacao)! Close=", close, " < ", g_cycle1Low);
         OpenFirstPosition(ORDER_TYPE_SELL);
         return;
      }

      // Reversao: rompe high do canal de abertura
      if(IsBreakoutAbove(close, g_channelHigh))
      {
         Print(" ROMPIMENTO COMPRA (reversao)! Close=", close, " > ", g_channelHigh);
         OpenFirstPosition(ORDER_TYPE_BUY);
         return;
      }
   }
}

//+------------------------------------------------------------------+
//| Abre posicao com verificacao de RR                                  |
//+------------------------------------------------------------------+
void OpenFirstPosition(ENUM_ORDER_TYPE orderType)
{
   if(IsDrawdownLimitReached("OpenFirstPosition"))
      return;

   bool isPCMEntry = (g_pcmReady && IsPCMEnabledRuntime());

   // Momento em que o rompimento foi identificado.
   g_tradeTriggerTime = TimeCurrent();

   double price = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double stopLossBase = (orderType == ORDER_TYPE_BUY) ? g_cycle1Low : g_cycle1High;

   // Aplicar incremento ao SL
   double slDistBase = MathAbs(price - stopLossBase);
   double slIncrement = slDistBase * (StopLossIncrement / 100.0);
   double stopLoss = (orderType == ORDER_TYPE_BUY) ? stopLossBase - slIncrement : stopLossBase + slIncrement;

   // Modo SLICED: TP = banda oposta + range
   double tpCalculated;
   if(g_cycle1Direction == "BOTH")
   {
      tpCalculated = (orderType == ORDER_TYPE_BUY) ? g_cycle1High + (SlicedMultiplier * g_channelRange) : g_cycle1Low - (SlicedMultiplier * g_channelRange);
   }
   else
   {
      tpCalculated = (orderType == ORDER_TYPE_BUY) ? g_cycle1High + (TPMultiplier * g_channelRange) : g_cycle1Low - (TPMultiplier * g_channelRange);
   }

   double tpDistance = MathAbs(tpCalculated - price);
   double tpReductionPercent = isPCMEntry ? PCMTPReductionPercent : TPReductionPercent;
   if(tpReductionPercent < 0.0)
      tpReductionPercent = 0.0;
   if(tpReductionPercent >= 100.0)
      tpReductionPercent = 99.99;
   double reductionFactor = 1.0 - (tpReductionPercent / 100.0);
   double takeProfit = (orderType == ORDER_TYPE_BUY) ? price + (tpDistance * reductionFactor) : price - (tpDistance * reductionFactor);

   double slDistance = MathAbs(price - stopLoss);
   double tpDistanceFinal = MathAbs(takeProfit - price);
   double currentRR = (slDistance > 0) ? (tpDistanceFinal / slDistance) : 0;

   Print(" RR Atual: ", DoubleToString(currentRR, 2), " | Minimo: ", MinRiskReward);

   string limitOrderComment = isPCMEntry ? "Ordem Limite RR PCM" : "Ordem Limite RR";

   if(ShouldUseLimitForMainEntry())
   {
      bool useMarketableLimit = (currentRR >= MinRiskReward);
      Print(" Modo LIMIT ativo na entrada principal: forcar ordem LIMIT (marketable=", useMarketableLimit ? "true" : "false",
            " | strict=", StrictLimitOnly ? "true" : "false",
            " | prefer_main=", PreferLimitMainEntry ? "true" : "false", ")");
      PlaceLimitOrder(orderType,
                      stopLoss,
                      takeProfit,
                      limitOrderComment,
                      useMarketableLimit,
                      0.0,
                      PENDING_CONTEXT_FIRST_ENTRY,
                      false,
                      (g_cycle1Direction == "BOTH"),
                      g_channelDefinitionTime,
                      g_tradeTriggerTime,
                      false,
                      g_channelRange,
                      isPCMEntry);
      return;
   }

   if(currentRR >= MinRiskReward)
   {
      ExecuteMarketOrder(orderType, price, stopLoss, takeProfit, isPCMEntry);
   }
   else
   {
      PlaceLimitOrder(orderType,
                      stopLoss,
                      takeProfit,
                      limitOrderComment,
                      false,
                      0.0,
                      PENDING_CONTEXT_FIRST_ENTRY,
                      false,
                      (g_cycle1Direction == "BOTH"),
                      g_channelDefinitionTime,
                      g_tradeTriggerTime,
                      false,
                      g_channelRange,
                      isPCMEntry);
   }
}

//+------------------------------------------------------------------+
//| Executa ordem a mercado                                          |
//+------------------------------------------------------------------+
void ExecuteMarketOrder(ENUM_ORDER_TYPE orderType, double price, double stopLoss, double takeProfit, bool isPCMContext = false)
{
   if(IsDrawdownLimitReached("ExecuteMarketOrder"))
      return;
   if(!IsTradingAllowedForOrder(orderType, "ExecuteMarketOrder"))
      return;

   if(ShouldUseLimitForMainEntry())
   {
      Print("WARN: ExecuteMarketOrder bloqueado por modo LIMIT na entrada principal. Ordem sera enviada como LIMIT marketable.");
      string forcedLimitComment = isPCMContext ? "Ordem Limite RR PCM" : "Ordem Limite RR";
      PlaceLimitOrder(orderType,
                      stopLoss,
                      takeProfit,
                      forcedLimitComment,
                      true,
                      0.0,
                      PENDING_CONTEXT_FIRST_ENTRY,
                      false,
                      (g_cycle1Direction == "BOTH"),
                      g_channelDefinitionTime,
                      g_tradeTriggerTime,
                      false,
                      g_channelRange,
                      isPCMContext);
      return;
   }

   double lotSize = CalculateLotSize(price, stopLoss, isPCMContext);

   stopLoss = NormalizePriceToTick(stopLoss);
   takeProfit = NormalizePriceToTick(takeProfit);
   price = NormalizePriceToTick(price);
   lotSize = NormalizeLot(lotSize);
   if(lotSize <= 0.0)
   {
      Print(" Entrada a mercado cancelada - lote invalido: ", lotSize);
      return;
   }
   if(!ValidateOrderProtectionLevels(orderType, price, stopLoss, takeProfit, "ExecuteMarketOrder"))
      return;

   Print(" Ordem a Mercado: ", EnumToString(orderType));
   Print("  Preco: ", price, " | SL: ", stopLoss, " | TP: ", takeProfit, " | Lotes: ", lotSize);

   bool result = false;
   datetime requestTime = TimeCurrent();
   string marketComment = isPCMContext ? "Operacao PCM" : "Primeira Operacao";
   if(orderType == ORDER_TYPE_BUY)
      result = trade.Buy(lotSize, _Symbol, 0, stopLoss, takeProfit, marketComment);
   else
      result = trade.Sell(lotSize, _Symbol, 0, stopLoss, takeProfit, marketComment);

   long retcode = trade.ResultRetcode();
   if(result && IsTradeRetcodeAccepted(retcode, true))
   {
      StartNewOperationChain();
      g_lastClosedOvernightChainIdHint = 0;
      ResetReversalHourBlockState();
      ulong resolvedTicket = 0;
      if(!TryResolvePositionTicketFromTradeResult(orderType, requestTime, resolvedTicket))
      {
         resolvedTicket = trade.ResultOrder();
         Print("WARN: ticket da posicao nao confirmado imediatamente. fallback=", resolvedTicket);
      }
      g_currentTicket = resolvedTicket;
      ClearCurrentTradePositionTickets();
      if(g_currentTicket > 0)
         TrackCurrentTradePositionTicket(g_currentTicket);
      g_currentOrderType = orderType;
      g_firstTradeLotSize = lotSize;
      g_firstTradeStopLoss = stopLoss;
      g_firstTradeTakeProfit = takeProfit;
      g_firstTradeExecuted = true;
      ResetNegativeAddState();

      // Registrar dados para log
      g_tradeEntryTime = TimeCurrent();
      g_tradeEntryPrice = price;
      g_tradeSliced = (g_cycle1Direction == "BOTH");
      g_tradeReversal = false;
      g_tradePCM = isPCMContext;
      g_tradeChannelDefinitionTime = g_channelDefinitionTime;
      g_tradeEntryExecutionType = "MARKET";
      if(g_tradeTriggerTime <= 0)
         g_tradeTriggerTime = g_tradeEntryTime;
      ResetCurrentTradeFloatingMetrics();
      if(isPCMContext)
      {
         MarkPCMOperationExecuted();
         if(g_preArmedReversalOrderTicket > 0)
            CancelPreArmedReversalOrder("entrada PCM - turnof desabilitada");
      }
      if(PositionSelectByTicket(g_currentTicket))
         EnsurePreArmedReversalForCurrentTrade();
      else
         Print("INFO: entrada aceita; aguardando consolidacao da posicao para armar virada pre-armada.");
      if(ShouldUseLimitForNegativeAddOn() && g_negativeAddRuntimeEnabled)
         PlaceNegativeAddOnLimitOrdersForStrictMode(g_tradeEntryPrice);

      if(isPCMContext)
         Print(" Operacao PCM executada! Ticket: ", g_currentTicket);
      else
         Print(" Primeira operacao executada! Ticket: ", g_currentTicket);
   }
   else
      Print(" Erro: ", retcode, " - ", trade.ResultRetcodeDescription());
}

//+------------------------------------------------------------------+
//| Coloca ordem limite para garantir RR minimo                     |
//+------------------------------------------------------------------+
void PlaceLimitOrder(ENUM_ORDER_TYPE orderType,
                     double stopLoss,
                     double takeProfit,
                     string orderComment = "Ordem Limite RR",
                     bool useMarketableLimit = false,
                     double lotOverride = 0.0,
                     EPendingOrderContext pendingContext = PENDING_CONTEXT_FIRST_ENTRY,
                     bool isReversalContext = false,
                     bool isSlicedContext = false,
                     datetime channelDefinitionTimeContext = 0,
                     datetime triggerTimeContext = 0,
                     bool preserveDailyCycleContext = false,
                     double channelRangeContext = 0.0,
                     bool isPCMContext = false)
{
   if(IsDrawdownLimitReached("PlaceLimitOrder"))
      return;
   if(!IsTradingAllowedForOrder(orderType, "PlaceLimitOrder"))
      return;

   double currentPrice = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double limitPrice = 0.0;
   if(useMarketableLimit)
      limitPrice = currentPrice;
   else
      limitPrice = (takeProfit + MinRiskReward * stopLoss) / (MinRiskReward + 1.0); // Formula RR

   double lotSize = lotOverride;
   if(lotSize <= 0.0)
      lotSize = CalculateLotSize(limitPrice, stopLoss, isPCMContext);

   limitPrice = NormalizePriceToTick(limitPrice);
   stopLoss = NormalizePriceToTick(stopLoss);
   takeProfit = NormalizePriceToTick(takeProfit);
   lotSize = NormalizeLot(lotSize);
   if(lotSize <= 0.0)
   {
      Print(" Ordem limite cancelada - lote invalido: ", lotSize);
      return;
   }

   // Validar ordem antes de enviar
   double epsilon = g_pointValue;
   if(epsilon <= 0.0)
      epsilon = 0.00001;
   bool validOrder = false;

   if(orderType == ORDER_TYPE_BUY)
      validOrder = (limitPrice <= (currentPrice + epsilon) && stopLoss < limitPrice && takeProfit > limitPrice);
   else
      validOrder = (limitPrice >= (currentPrice - epsilon) && stopLoss > limitPrice && takeProfit < limitPrice);

   if(!validOrder)
   {
      Print(" Ordem invalida - Preco atual: ", currentPrice);
      Print("  Limite: ", limitPrice, " | SL: ", stopLoss, " | TP: ", takeProfit);
      return;
   }
   if(!ValidateOrderProtectionLevels(orderType, limitPrice, stopLoss, takeProfit, "PlaceLimitOrder"))
      return;

   // Calcular RR real para log
   double slDist = MathAbs(limitPrice - stopLoss);
   double tpDist = MathAbs(takeProfit - limitPrice);
   double actualRR = (slDist > 0) ? (tpDist / slDist) : 0;

   Print(" Ordem Limite (RR = ", DoubleToString(actualRR, 2), "): ", EnumToString(orderType));
   Print("  Limite: ", limitPrice, " | SL: ", stopLoss, " | TP: ", takeProfit, " | Lotes: ", lotSize);

   bool result = false;
   datetime requestTime = TimeCurrent();
   if(orderType == ORDER_TYPE_BUY)
      result = trade.BuyLimit(lotSize, limitPrice, _Symbol, stopLoss, takeProfit, ORDER_TIME_DAY, 0, orderComment);
   else
      result = trade.SellLimit(lotSize, limitPrice, _Symbol, stopLoss, takeProfit, ORDER_TIME_DAY, 0, orderComment);

   long retcode = trade.ResultRetcode();
   if(result && IsTradeRetcodeAccepted(retcode, true))
   {
      ulong trackedTicket = 0;
      bool hasPendingTicket = TryResolvePendingOrderTicketFromTradeResult(orderType,
                                                                          requestTime,
                                                                          orderComment,
                                                                          trackedTicket);
      if(!hasPendingTicket)
      {
         ulong resolvedPositionTicket = 0;
         if(TryResolvePositionTicketFromTradeResult(orderType, requestTime, resolvedPositionTicket))
         {
            trackedTicket = resolvedPositionTicket;
            Print("INFO: LIMIT aceita com preenchimento imediato. ticket_posicao=", trackedTicket);
         }
      }
      if(trackedTicket == 0)
      {
         Print("WARN: LIMIT aceita, mas ticket rastreavel nao foi encontrado. retcode=", retcode,
               " | ", trade.ResultRetcodeDescription());
         return;
      }

      g_currentTicket = trackedTicket;
      ClearCurrentTradePositionTickets();
      if(!hasPendingTicket)
         TrackCurrentTradePositionTicket(g_currentTicket);
      g_currentOrderType = orderType;
      g_firstTradeLotSize = lotSize;
      g_firstTradeStopLoss = stopLoss;
      g_firstTradeTakeProfit = takeProfit;
      g_pendingOrderPlaced = true;
      g_pendingOrderContext = pendingContext;
      g_pendingOrderIsReversal = isReversalContext;
      g_pendingOrderIsSliced = isSlicedContext;
      g_pendingOrderIsPCM = isPCMContext;
      g_pendingOrderChannelDefinitionTime = channelDefinitionTimeContext;
      if(g_pendingOrderChannelDefinitionTime <= 0)
         g_pendingOrderChannelDefinitionTime = g_channelDefinitionTime;
      g_pendingOrderTriggerTime = triggerTimeContext;
      g_pendingOrderPreserveDailyCycle = preserveDailyCycleContext;
      g_pendingOrderChannelRange = channelRangeContext;
      if(g_pendingOrderChannelRange <= 0.0)
         g_pendingOrderChannelRange = g_channelRange;
      g_pendingOrderLotSnapshot = lotSize;
      g_pendingOrderSubmissionTime = requestTime;
      InitializePendingLimitTelemetry(limitPrice, stopLoss, takeProfit, orderType);
      Print(" Ordem limite colocada! Ticket: ", g_currentTicket);
      Print("  Contexto pending: ", PendingOrderContextToString(g_pendingOrderContext),
            " | reversal=", g_pendingOrderIsReversal ? "true" : "false",
            " | pcm=", g_pendingOrderIsPCM ? "true" : "false",
            " | preserve_daily_cycle=", g_pendingOrderPreserveDailyCycle ? "true" : "false");
   }
   else
      Print(" Erro: ", retcode, " - ", trade.ResultRetcodeDescription());
}

//+------------------------------------------------------------------+
//| Verifica se ordem pendente foi executada                         |
//+------------------------------------------------------------------+
void CheckPendingOrderExecution()
{
   if(!g_pendingOrderPlaced)
      return;

   EPendingOrderContext pendingContext = g_pendingOrderContext;
   bool isOvernightContext = (pendingContext == PENDING_CONTEXT_OVERNIGHT_REVERSAL);
   bool preserveDailyCycle = g_pendingOrderPreserveDailyCycle;
   bool isReversalPending = (pendingContext == PENDING_CONTEXT_REVERSAL || pendingContext == PENDING_CONTEXT_OVERNIGHT_REVERSAL);

   if(isReversalPending)
   {
      TryRearmReversalBlockForNewDay();

      if(!IsReversalAllowedByEntryHourNow())
      {
         if(OrderSelect(g_currentTicket))
         {
            if(trade.OrderDelete(g_currentTicket))
               Print("INFO: Ordem de virada cancelada por horario limite. Ticket: ", g_currentTicket);
            else
               Print("WARN: falha ao cancelar ordem de virada por horario limite. Ticket: ", g_currentTicket,
                     " | retcode=", trade.ResultRetcode(), " | ", trade.ResultRetcodeDescription());
         }

         if(!g_reversalBlockedByEntryHour)
            Print("INFO: Virada bloqueada por horario limite para este ciclo.");
         MarkReversalBlockedByEntryHour();

         ConsumeCycleAfterPendingCancel();
         ClearPendingOrderState(true);
         g_tradeEntryTime = 0;
         g_tradeReversal = false;
         g_tradePCM = false;
         g_tradeChannelDefinitionTime = 0;
         g_tradeEntryExecutionType = "";
         g_tradeTriggerTime = 0;
         ResetNegativeAddState();
         ResetCurrentTradeFloatingMetrics();
         g_currentOperationChainId = 0;
         return;
      }
   }

   if(IsDrawdownLimitReached("CheckPendingOrderExecution") && OrderSelect(g_currentTicket))
   {
      if(trade.OrderDelete(g_currentTicket))
         Print(" Ordem limite cancelada por limite de DD. Ticket: ", g_currentTicket);
      else
         Print(" WARN: falha ao cancelar ordem limite por DD. Ticket: ", g_currentTicket,
               " | retcode=", trade.ResultRetcode(), " | ", trade.ResultRetcodeDescription());

      ClearPendingOrderState(true);
      g_tradeEntryTime = 0;
      g_tradeReversal = false;
      g_tradePCM = false;
      g_tradeChannelDefinitionTime = 0;
      g_tradeEntryExecutionType = "";
      g_tradeTriggerTime = 0;
      ResetNegativeAddState();
      ResetCurrentTradeFloatingMetrics();
      g_currentOperationChainId = 0;
      ResetReversalHourBlockState();
      return;
   }

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(!g_pendingLimitTelemetryReady && OrderSelect(g_currentTicket))
   {
      double orderLimitPrice = OrderGetDouble(ORDER_PRICE_OPEN);
      if(orderLimitPrice > 0.0)
         InitializePendingLimitTelemetry(orderLimitPrice, g_firstTradeStopLoss, g_firstTradeTakeProfit, g_currentOrderType);
   }
   UpdatePendingLimitTelemetry(currentBid, currentAsk);

   double limitPriceSnapshot = g_pendingLimitPrice;
   if(limitPriceSnapshot <= 0.0 && OrderSelect(g_currentTicket))
      limitPriceSnapshot = OrderGetDouble(ORDER_PRICE_OPEN);
   double closestPriceSnapshot = g_pendingClosestPriceToLimit;
   if(closestPriceSnapshot <= 0.0)
      closestPriceSnapshot = (g_currentOrderType == ORDER_TYPE_BUY) ? currentAsk : currentBid;
   double missingToLimitPoints = g_pendingMinDistanceToLimitPoints;
   if(missingToLimitPoints < 0.0 && limitPriceSnapshot > 0.0)
      missingToLimitPoints = CalculateMissingToLimitPoints(g_currentOrderType, closestPriceSnapshot, limitPriceSnapshot);
   double rrMaxReached = g_pendingMaxRiskRewardObserved;
   if(rrMaxReached <= 0.0)
      rrMaxReached = CalculatePotentialRiskReward(g_currentOrderType,
                                                  closestPriceSnapshot,
                                                  g_firstTradeStopLoss,
                                                  g_firstTradeTakeProfit);

   bool targetReachedBeforeFill = false;
   if(g_currentOrderType == ORDER_TYPE_BUY)
      targetReachedBeforeFill = (currentAsk >= g_firstTradeTakeProfit);
   else if(g_currentOrderType == ORDER_TYPE_SELL)
      targetReachedBeforeFill = (currentBid <= g_firstTradeTakeProfit);

   if(targetReachedBeforeFill)
   {
      bool pcmArmedFromNoTrade = false;
      if(pendingContext == PENDING_CONTEXT_FIRST_ENTRY)
      {
         pcmArmedFromNoTrade = SchedulePCMActivationFromNoTradeLimitTarget(TimeCurrent(),
                                                                           rrMaxReached,
                                                                           MinRiskReward);
      }

      if(g_currentOrderType == ORDER_TYPE_BUY)
      {
         Print(" Ordem limite cancelada - Preco atingiu TP (Ask=", currentAsk, " >= TP=", g_firstTradeTakeProfit, ")");
         if(pendingContext == PENDING_CONTEXT_FIRST_ENTRY)
         {
            LogNoTrade("Limit cancelada: preco atingiu alvo projetado antes da execucao (tipo=BUY ask=" +
                       DoubleToString(currentAsk, digits) + " tp=" + DoubleToString(g_firstTradeTakeProfit, digits) + ")",
                       "LIMIT_CANCELED_TARGET_REACHED",
                       "BUY",
                       limitPriceSnapshot,
                       closestPriceSnapshot,
                       g_firstTradeStopLoss,
                       g_firstTradeTakeProfit,
                       missingToLimitPoints,
                       rrMaxReached,
                       MinRiskReward,
                       pcmArmedFromNoTrade);
         }
      }
      else
      {
         Print(" Ordem limite cancelada - Preco atingiu TP (Bid=", currentBid, " <= TP=", g_firstTradeTakeProfit, ")");
         if(pendingContext == PENDING_CONTEXT_FIRST_ENTRY)
         {
            LogNoTrade("Limit cancelada: preco atingiu alvo projetado antes da execucao (tipo=SELL bid=" +
                       DoubleToString(currentBid, digits) + " tp=" + DoubleToString(g_firstTradeTakeProfit, digits) + ")",
                       "LIMIT_CANCELED_TARGET_REACHED",
                       "SELL",
                       limitPriceSnapshot,
                       closestPriceSnapshot,
                       g_firstTradeStopLoss,
                       g_firstTradeTakeProfit,
                       missingToLimitPoints,
                       rrMaxReached,
                       MinRiskReward,
                       pcmArmedFromNoTrade);
         }
      }

      if(trade.OrderDelete(g_currentTicket))
         Print(" Ordem #", g_currentTicket, " cancelada com sucesso");

      ConsumeCycleAfterPendingCancel();
      ClearPendingOrderState(true);
      g_tradeEntryTime = 0;
      g_tradeReversal = false;
      g_tradePCM = false;
      g_tradeChannelDefinitionTime = 0;
      g_tradeEntryExecutionType = "";
      g_tradeTriggerTime = 0;
      ResetNegativeAddState();
      ResetCurrentTradeFloatingMetrics();
      g_currentOperationChainId = 0;
      return;
   }

   if(OrderSelect(g_currentTicket))
      return;

   ulong filledTicketCandidate = g_currentTicket;
   if(!PositionSelectByTicket(filledTicketCandidate))
   {
      datetime minEntryTime = g_pendingOrderTriggerTime;
      if(minEntryTime <= 0)
         minEntryTime = TimeCurrent() - 12 * 60 * 60;
      else
         minEntryTime -= 5;

      ulong scannedTicket = FindLatestEAPositionTicketByType(g_currentOrderType, minEntryTime);
      if(scannedTicket > 0 && PositionSelectByTicket(scannedTicket))
      {
         filledTicketCandidate = scannedTicket;
         g_currentTicket = scannedTicket;
         TrackCurrentTradePositionTicket(scannedTicket);
         Print("INFO: fill de LIMIT recuperado por varredura. ticket=", scannedTicket);
      }
   }

   if(PositionSelectByTicket(filledTicketCandidate))
   {
      ulong filledTicket = filledTicketCandidate;
      g_currentTicket = filledTicket;
      double filledEntryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double filledVolume = PositionGetDouble(POSITION_VOLUME);
      datetime fillTime = TimeCurrent();

      Print(" Ordem limite executada! Ticket: ", filledTicket,
            " | contexto=", PendingOrderContextToString(pendingContext));

      // Virada overnight com ciclo diario preservado: rastrear como overnight e liberar entrada diaria.
      if(isOvernightContext && preserveDailyCycle)
      {
         int overnightChainId = g_lastClosedOvernightChainIdHint;
         if(overnightChainId <= 0)
            overnightChainId = g_overnightChainId;
         if(overnightChainId <= 0)
            overnightChainId = g_currentOperationChainId;
         if(overnightChainId <= 0)
            overnightChainId = NextOperationChainId();

         g_overnightTicket = filledTicket;
         g_overnightEntryTime = fillTime;
         g_overnightEntryPrice = filledEntryPrice;
         g_overnightStopLoss = g_firstTradeStopLoss;
         g_overnightTakeProfit = g_firstTradeTakeProfit;
         g_overnightChannelRange = (g_pendingOrderChannelRange > 0.0) ? g_pendingOrderChannelRange : g_channelRange;
         g_overnightLotSize = (filledVolume > 0.0) ? filledVolume : g_pendingOrderLotSnapshot;
         g_overnightSliced = g_pendingOrderIsSliced;
         g_overnightReversal = true;
         g_overnightPCM = false;
         g_overnightOrderType = g_currentOrderType;
         g_overnightChannelDefinitionTime = g_pendingOrderChannelDefinitionTime;
         g_overnightEntryExecutionType = "LIMIT";
         g_overnightTriggerTime = g_pendingOrderTriggerTime;
         if(g_overnightTriggerTime <= 0)
            g_overnightTriggerTime = fillTime;
         g_overnightMaxFloatingProfit = 0;
         g_overnightMaxFloatingDrawdown = 0;
         g_overnightMaxAdverseToSLPercent = 0;
         g_overnightMaxFavorableToTPPercent = 0;
         g_overnightChainId = overnightChainId;

         AddOvernightLogSnapshot(g_overnightTicket,
                                 g_overnightEntryTime,
                                 g_overnightEntryPrice,
                                 g_overnightStopLoss,
                                 g_overnightTakeProfit,
                                 g_overnightSliced,
                                 g_overnightReversal,
                                 g_overnightPCM,
                                 g_overnightOrderType,
                                 g_overnightChannelDefinitionTime,
                                 g_overnightEntryExecutionType,
                                 g_overnightTriggerTime,
                                 g_overnightMaxFloatingProfit,
                                 g_overnightMaxFloatingDrawdown,
                                 g_overnightMaxAdverseToSLPercent,
                                 g_overnightMaxFavorableToTPPercent,
                                 g_overnightChannelRange,
                                 g_overnightLotSize,
                                 g_overnightChainId);

         g_currentTicket = 0;
         ClearCurrentTradePositionTickets();
         g_tradeEntryTime = 0;
         g_tradeEntryPrice = 0;
         g_tradeReversal = false;
         g_tradePCM = false;
         g_tradeSliced = false;
         g_tradeChannelDefinitionTime = 0;
         g_tradeEntryExecutionType = "";
         g_tradeTriggerTime = 0;
         ClearPendingOrderState(false);
         ResetNegativeAddState();
         ResetCurrentTradeFloatingMetrics();
         g_currentOperationChainId = 0;
         ResetReversalHourBlockState();
         g_lastClosedOvernightChainIdHint = 0;

         Print(" Virada overnight LIMIT executada sem consumir entrada diaria! Ticket: ", g_overnightTicket);
         return;
      }

      ClearCurrentTradePositionTickets();
      TrackCurrentTradePositionTicket(filledTicket);
      ApplyPendingFillTradeMetadata(filledEntryPrice);
      ResetCurrentTradeFloatingMetrics();
      ResetNegativeAddState();

      if(pendingContext == PENDING_CONTEXT_FIRST_ENTRY)
      {
         StartNewOperationChain();
         ResetReversalHourBlockState();
      }
      else
      {
         int reversalChainId = g_lastClosedOvernightChainIdHint;
         if(reversalChainId <= 0)
            reversalChainId = g_currentOperationChainId;
         AdoptOperationChainId(reversalChainId);
      }
      g_lastClosedOvernightChainIdHint = 0;

      g_firstTradeExecuted = true;
      if(pendingContext == PENDING_CONTEXT_REVERSAL || pendingContext == PENDING_CONTEXT_OVERNIGHT_REVERSAL)
         g_reversalTradeExecuted = true;
      if(g_tradePCM)
         MarkPCMOperationExecuted();

      ClearPendingOrderState(false);
      if(!g_tradeReversal)
         EnsurePreArmedReversalForCurrentTrade();
      if(ShouldUseLimitForNegativeAddOn() && g_negativeAddRuntimeEnabled)
         PlaceNegativeAddOnLimitOrdersForStrictMode(g_tradeEntryPrice);

      if(IsDrawdownLimitReached("PendingOrderExecuted"))
      {
         if(g_preArmedReversalOrderTicket > 0)
            CancelPreArmedReversalOrder("fechamento por DD apos fill LIMIT");
         if(ClosePositionByTicketMarket(g_currentTicket))
            Print(" Posicao de ordem limite fechada por limite de DD. Ticket: ", g_currentTicket);
         else
            Print(" WARN: nao foi possivel fechar posicao de ordem limite sob DD. Ticket: ", g_currentTicket);
      }
      return;
   }

   if(g_pendingOrderSubmissionTime > 0 && (TimeCurrent() - g_pendingOrderSubmissionTime) < 5)
   {
      Print("INFO: aguardando sincronizacao da ordem pendente (grace period). ticket=", g_currentTicket);
      return;
   }

   Print(" Ordem limite nao encontrada - pode ter sido cancelada");
   ConsumeCycleAfterPendingCancel();
   ClearPendingOrderState(true);
   g_tradeEntryTime = 0;
   g_tradeReversal = false;
   g_tradePCM = false;
   g_tradeChannelDefinitionTime = 0;
   g_tradeEntryExecutionType = "";
   g_tradeTriggerTime = 0;
   ResetNegativeAddState();
   ResetCurrentTradeFloatingMetrics();
   g_currentOperationChainId = 0;
   ResetReversalHourBlockState();
}

//+------------------------------------------------------------------+
//| Calcula lotes                                                     |
//+------------------------------------------------------------------+
bool IsFixedLotAllEntriesEnabled()
{
   return (FixedLotAllEntries > 0.0);
}

double ResolveFixedLotAllEntries()
{
   if(!IsFixedLotAllEntriesEnabled())
      return 0.0;
   return NormalizeLot(FixedLotAllEntries);
}

double ResolveRiskPercentForEntry(bool isPCMContext = false)
{
   if(isPCMContext)
   {
      if(PCMRiskPercent > 0.0)
         return PCMRiskPercent;
      return RiskPercent;
   }

   return RiskPercent;
}

double CalculateLotSize(double entryPrice, double stopLoss, bool isPCMContext = false)
{
   double fixedLot = ResolveFixedLotAllEntries();
   if(fixedLot > 0.0)
      return fixedLot;

   if(entryPrice <= 0.0 || stopLoss <= 0.0)
      return 0.0;

   ENUM_ORDER_TYPE calcType = (entryPrice > stopLoss) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

   double riskReferenceBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(UseInitialDepositForRisk && g_initialAccountBalance > 0.0)
      riskReferenceBalance = g_initialAccountBalance;
   double riskPercentToUse = ResolveRiskPercentForEntry(isPCMContext);
   double riskAmount = riskReferenceBalance * (riskPercentToUse / 100.0);
   if(riskAmount <= 0.0)
      return 0.0;

   double minLot = NormalizeLot(g_minLot);
   if(minLot <= 0.0)
      return 0.0;

   double lossAtMinLotRaw = 0.0;
   if(!OrderCalcProfit(calcType, _Symbol, minLot, entryPrice, stopLoss, lossAtMinLotRaw))
   {
      Print("WARN: OrderCalcProfit falhou no calculo de lote. fallback para min lot.");
      return minLot;
   }

   double lossAtMinLot = (lossAtMinLotRaw < 0.0) ? (-lossAtMinLotRaw) : 0.0;
   if(lossAtMinLot <= 0.0)
   {
      Print("WARN: perda estimada no SL <= 0 para lote minimo. lote bloqueado.");
      return 0.0;
   }

   if(EnableP0RejectTradeIfMinLotExceedsRisk && lossAtMinLot > (riskAmount * 1.01))
   {
      Print("WARN: lote minimo excede risco alvo. risco_alvo=", DoubleToString(riskAmount, 2),
            " | risco_lote_min=", DoubleToString(lossAtMinLot, 2));
      return 0.0;
   }

   double rawLot = (riskAmount / lossAtMinLot) * minLot;
   double lot = NormalizeLot(rawLot);
   if(lot < minLot)
      lot = minLot;

   double projectedLossRaw = 0.0;
   if(OrderCalcProfit(calcType, _Symbol, lot, entryPrice, stopLoss, projectedLossRaw))
   {
      double projectedLoss = (projectedLossRaw < 0.0) ? (-projectedLossRaw) : 0.0;
      int adjustCount = 0;
      while(projectedLoss > (riskAmount * 1.01) && lot > minLot && adjustCount < 200)
      {
         lot = NormalizeLot(lot - g_lotStep);
         if(lot < minLot)
            lot = minLot;
         if(!OrderCalcProfit(calcType, _Symbol, lot, entryPrice, stopLoss, projectedLossRaw))
            break;
         projectedLoss = (projectedLossRaw < 0.0) ? (-projectedLossRaw) : 0.0;
         adjustCount++;
      }
   }

   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double marginRequired = 0.0;
   if(freeMargin > 0.0 && OrderCalcMargin(calcType, _Symbol, lot, entryPrice, marginRequired))
   {
      int marginAdjustCount = 0;
      while(marginRequired > (freeMargin * 0.8) && lot > minLot && marginAdjustCount < 200)
      {
         lot = NormalizeLot(lot - g_lotStep);
         if(lot < minLot)
            lot = minLot;
         if(!OrderCalcMargin(calcType, _Symbol, lot, entryPrice, marginRequired))
            break;
         marginAdjustCount++;
      }

      if(EnableP0RejectTradeIfMinLotExceedsRisk && marginRequired > (freeMargin * 0.8) && lot <= minLot)
      {
         Print("WARN: lote minimo nao cabe na margem livre (80%). margem_requerida=",
               DoubleToString(marginRequired, 2), " | margem_livre=", DoubleToString(freeMargin, 2));
         return 0.0;
      }
   }

   return NormalizeLot(lot);
}

//+------------------------------------------------------------------+
//| Normaliza lotes                                                   |
//+------------------------------------------------------------------+
double NormalizeLot(double lot)
{
   if(lot < g_minLot) lot = g_minLot;
   if(lot > g_maxLot) lot = g_maxLot;

   double step = g_lotStep;
   if(step <= 0.0)
      step = g_minLot;
   if(step <= 0.0)
      step = 0.01;
   lot = MathFloor(lot / step) * step;

   int lotDigits = 0;
   double scaledStep = step;
   while(lotDigits < 8 && MathAbs(scaledStep - MathRound(scaledStep)) > 1e-9)
   {
      scaledStep *= 10.0;
      lotDigits++;
   }

   return NormalizeDouble(lot, lotDigits);
}

//+------------------------------------------------------------------+
//| Reseta metricas de flutuacao da operacao atual                  |
//+------------------------------------------------------------------+
void ResetCurrentTradeFloatingMetrics()
{
   g_tradeMaxFloatingProfit = 0;
   g_tradeMaxFloatingDrawdown = 0;
   g_tradeMaxAdverseToSLPercent = 0;
   g_tradeMaxFavorableToTPPercent = 0;
   g_pcmBreakEvenApplied = false;
   g_pcmTraillingStopApplied = false;
}

//+------------------------------------------------------------------+
//| Reseta estado da logica de adicao negativa                      |
//+------------------------------------------------------------------+
void ClearNegativeAddExecutedTickets()
{
   ArrayResize(g_negativeAddExecutedTickets, 0);
   ArrayResize(g_negativeAddEntryTimes, 0);
   ArrayResize(g_negativeAddEntryPrices, 0);
   ArrayResize(g_negativeAddStopLosses, 0);
   ArrayResize(g_negativeAddTakeProfits, 0);
   ArrayResize(g_negativeAddMaxFloatingProfits, 0);
   ArrayResize(g_negativeAddMaxFloatingDrawdowns, 0);
   ArrayResize(g_negativeAddMaxAdverseToSLPercents, 0);
   ArrayResize(g_negativeAddMaxFavorableToTPPercents, 0);
}

void ClearNegativeAddPendingOrdersTracking()
{
   ArrayResize(g_negativeAddPendingOrderTickets, 0);
   ArrayResize(g_negativeAddPendingOrderHandled, 0);
   g_negativeAddPendingOrdersPlaced = false;
}

void TrackNegativeAddPendingOrderTicket(ulong ticket)
{
   if(ticket == 0)
      return;

   int n = ArraySize(g_negativeAddPendingOrderTickets);
   ArrayResize(g_negativeAddPendingOrderTickets, n + 1);
   ArrayResize(g_negativeAddPendingOrderHandled, n + 1);
   g_negativeAddPendingOrderTickets[n] = ticket;
   g_negativeAddPendingOrderHandled[n] = false;
}

void CancelNegativeAddPendingOrders(string reason = "")
{
   int total = ArraySize(g_negativeAddPendingOrderTickets);
   for(int i = 0; i < total; i++)
   {
      ulong ticket = g_negativeAddPendingOrderTickets[i];
      if(ticket == 0)
         continue;

      if(OrderSelect(ticket))
      {
         if(trade.OrderDelete(ticket))
         {
            if(reason == "")
               Print("INFO: ordem LIMIT de addon cancelada. Ticket=", ticket);
            else
               Print("INFO: ordem LIMIT de addon cancelada (", reason, "). Ticket=", ticket);
         }
      }
   }

   ClearNegativeAddPendingOrdersTracking();
}

int FindNegativeAddExecutedTicket(ulong ticket)
{
   int total = ArraySize(g_negativeAddExecutedTickets);
   for(int i = 0; i < total; i++)
   {
      if(g_negativeAddExecutedTickets[i] == ticket)
         return i;
   }
   return -1;
}

ENUM_ORDER_TYPE ResolveOrderTypeFromPositionTicket(ulong ticket, bool &ok)
{
   ok = false;
   if(ticket == 0)
      return ORDER_TYPE_BUY;
   if(!PositionSelectByTicket(ticket))
      return ORDER_TYPE_BUY;

   ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   ok = true;
   return (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
}

void UpdateNegativeAddSnapshotByIndex(int index)
{
   if(index < 0 || index >= ArraySize(g_negativeAddExecutedTickets))
      return;

   ulong ticket = g_negativeAddExecutedTickets[index];
   if(ticket == 0 || !PositionSelectByTicket(ticket))
      return;

   datetime posTime = (datetime)PositionGetInteger(POSITION_TIME);
   double posEntryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double posSL = PositionGetDouble(POSITION_SL);
   double posTP = PositionGetDouble(POSITION_TP);
   double posFloating = PositionGetDouble(POSITION_PROFIT);

   if(g_negativeAddEntryTimes[index] <= 0 && posTime > 0)
      g_negativeAddEntryTimes[index] = posTime;
   if(g_negativeAddEntryPrices[index] <= 0.0 && posEntryPrice > 0.0)
      g_negativeAddEntryPrices[index] = posEntryPrice;
   if(posSL > 0.0)
      g_negativeAddStopLosses[index] = posSL;
   if(posTP > 0.0)
      g_negativeAddTakeProfits[index] = posTP;

   if(posFloating > g_negativeAddMaxFloatingProfits[index])
      g_negativeAddMaxFloatingProfits[index] = posFloating;
   if(posFloating < g_negativeAddMaxFloatingDrawdowns[index])
      g_negativeAddMaxFloatingDrawdowns[index] = posFloating;

   bool hasOrderType = false;
   ENUM_ORDER_TYPE orderType = ResolveOrderTypeFromPositionTicket(ticket, hasOrderType);
   if(!hasOrderType)
      return;

   double referenceEntry = g_negativeAddEntryPrices[index];
   if(referenceEntry <= 0.0)
      referenceEntry = posEntryPrice;

   if(referenceEntry > 0.0 && g_negativeAddStopLosses[index] > 0.0)
   {
      double adverseToSLPercent = CalculateAdverseToSLPercent(orderType, referenceEntry, g_negativeAddStopLosses[index]);
      if(adverseToSLPercent > g_negativeAddMaxAdverseToSLPercents[index])
         g_negativeAddMaxAdverseToSLPercents[index] = adverseToSLPercent;
   }

   if(referenceEntry > 0.0 && g_negativeAddTakeProfits[index] > 0.0)
   {
      double favorableToTPPercent = CalculateFavorableToTPPercent(orderType, referenceEntry, g_negativeAddTakeProfits[index]);
      if(favorableToTPPercent > g_negativeAddMaxFavorableToTPPercents[index])
         g_negativeAddMaxFavorableToTPPercents[index] = favorableToTPPercent;
   }
}

void UpdateNegativeAddSnapshotsFromOpenPositions()
{
   int total = ArraySize(g_negativeAddExecutedTickets);
   for(int i = 0; i < total; i++)
      UpdateNegativeAddSnapshotByIndex(i);
}

bool GetNegativeAddSnapshotByTicket(ulong ticket,
                                    datetime &entryTime,
                                    double &entryPrice,
                                    double &stopLoss,
                                    double &takeProfit,
                                    double &maxFloatingProfit,
                                    double &maxFloatingDrawdown,
                                    double &maxAdverseToSLPercent,
                                    double &maxFavorableToTPPercent)
{
   int index = FindNegativeAddExecutedTicket(ticket);
   if(index < 0)
      return false;

   entryTime = g_negativeAddEntryTimes[index];
   entryPrice = g_negativeAddEntryPrices[index];
   stopLoss = g_negativeAddStopLosses[index];
   takeProfit = g_negativeAddTakeProfits[index];
   maxFloatingProfit = g_negativeAddMaxFloatingProfits[index];
   maxFloatingDrawdown = g_negativeAddMaxFloatingDrawdowns[index];
   maxAdverseToSLPercent = g_negativeAddMaxAdverseToSLPercents[index];
   maxFavorableToTPPercent = g_negativeAddMaxFavorableToTPPercents[index];
   return true;
}

void TrackNegativeAddExecutedTicket(ulong ticket)
{
   if(ticket == 0)
      return;
   if(FindNegativeAddExecutedTicket(ticket) >= 0)
      return;

   int n = ArraySize(g_negativeAddExecutedTickets);
   ArrayResize(g_negativeAddExecutedTickets, n + 1);
   g_negativeAddExecutedTickets[n] = ticket;
   ArrayResize(g_negativeAddEntryTimes, n + 1);
   ArrayResize(g_negativeAddEntryPrices, n + 1);
   ArrayResize(g_negativeAddStopLosses, n + 1);
   ArrayResize(g_negativeAddTakeProfits, n + 1);
   ArrayResize(g_negativeAddMaxFloatingProfits, n + 1);
   ArrayResize(g_negativeAddMaxFloatingDrawdowns, n + 1);
   ArrayResize(g_negativeAddMaxAdverseToSLPercents, n + 1);
   ArrayResize(g_negativeAddMaxFavorableToTPPercents, n + 1);

   g_negativeAddEntryTimes[n] = 0;
   g_negativeAddEntryPrices[n] = 0.0;
   g_negativeAddStopLosses[n] = 0.0;
   g_negativeAddTakeProfits[n] = 0.0;
   g_negativeAddMaxFloatingProfits[n] = 0.0;
   g_negativeAddMaxFloatingDrawdowns[n] = 0.0;
   g_negativeAddMaxAdverseToSLPercents[n] = 0.0;
   g_negativeAddMaxFavorableToTPPercents[n] = 0.0;

   UpdateNegativeAddSnapshotByIndex(n);
}

double CollectProfitFromTicketsHistory(const ulong &tickets[])
{
   double totalProfit = 0.0;
   int totalTickets = ArraySize(tickets);
   for(int t = 0; t < totalTickets; t++)
   {
      ulong ticket = tickets[t];
      if(ticket == 0)
         continue;

      if(!HistorySelectByPosition(ticket))
         continue;

      int dealsTotal = HistoryDealsTotal();
      for(int i = 0; i < dealsTotal; i++)
      {
         ulong dealTicket = HistoryDealGetTicket(i);
         if(dealTicket == 0)
            continue;

         long dealEntry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
         if(dealEntry == DEAL_ENTRY_OUT)
         {
            double dealProfit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
            double dealSwap = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
            double dealCommission = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
            double dealFee = HistoryDealGetDouble(dealTicket, DEAL_FEE);
            totalProfit += (dealProfit + dealSwap + dealCommission + dealFee);
         }
      }
   }

   return totalProfit;
}

void GetNegativeAddRuntimeMetrics(int &addOnCount, double &addOnLots, double &addOnAvgEntryPrice)
{
   addOnCount = g_negativeAddEntriesExecuted;
   addOnLots = g_negativeAddExecutedLots;
   addOnAvgEntryPrice = 0.0;
   if(addOnLots > 0.0)
      addOnAvgEntryPrice = g_negativeAddExecutedWeightedEntryPrice / addOnLots;
}

void ResetNegativeAddState()
{
   CancelNegativeAddPendingOrders("reset estado addon");
   g_negativeAddEntriesExecuted = 0;
   g_negativeAddExecutedLots = 0.0;
   g_negativeAddExecutedWeightedEntryPrice = 0.0;
   ClearNegativeAddExecutedTickets();
   g_negativeAddLastDebugLogTime = 0;
   g_negativeAddLastReasonCode = -1;
}

//+------------------------------------------------------------------+
//| Limpa lista de tickets rastreados na operacao atual              |
//+------------------------------------------------------------------+
void ClearCurrentTradePositionTickets()
{
   ArrayResize(g_currentTradePositionTickets, 0);
}

//+------------------------------------------------------------------+
//| Localiza ticket na lista rastreada                               |
//+------------------------------------------------------------------+
int FindCurrentTradePositionTicket(ulong ticket)
{
   int total = ArraySize(g_currentTradePositionTickets);
   for(int i = 0; i < total; i++)
   {
      if(g_currentTradePositionTickets[i] == ticket)
         return i;
   }
   return -1;
}

//+------------------------------------------------------------------+
//| Rastreia ticket de posicao da operacao atual                     |
//+------------------------------------------------------------------+
void TrackCurrentTradePositionTicket(ulong ticket)
{
   if(ticket == 0)
      return;
   if(FindCurrentTradePositionTicket(ticket) >= 0)
      return;

   int n = ArraySize(g_currentTradePositionTickets);
   ArrayResize(g_currentTradePositionTickets, n + 1);
   g_currentTradePositionTickets[n] = ticket;
}

//+------------------------------------------------------------------+
//| Rastreia lista de tickets ativos da operacao atual               |
//+------------------------------------------------------------------+
void TrackCurrentTradePositionTickets(const ulong &tickets[])
{
   int total = ArraySize(tickets);
   for(int i = 0; i < total; i++)
      TrackCurrentTradePositionTicket(tickets[i]);
}

//+------------------------------------------------------------------+
//| Atualiza metricas de drawdown (diario e maximo)                 |
//+------------------------------------------------------------------+
void UpdateDrawdownMetrics()
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(g_dayStartEquity <= 0.0)
      g_dayStartEquity = equity;
   if(g_peakEquity <= 0.0 || equity > g_peakEquity)
      g_peakEquity = equity;

   g_cachedDailyDrawdownAmount = 0.0;
   if(equity < g_dayStartEquity)
      g_cachedDailyDrawdownAmount = (g_dayStartEquity - equity);

   g_cachedDailyDrawdownPercent = 0.0;
   if(g_dayStartEquity > 0.0 && g_cachedDailyDrawdownAmount > 0.0)
      g_cachedDailyDrawdownPercent = (g_cachedDailyDrawdownAmount / g_dayStartEquity) * 100.0;

   g_cachedMaxDrawdownAmount = 0.0;
   if(equity < g_peakEquity)
      g_cachedMaxDrawdownAmount = (g_peakEquity - equity);

   g_cachedMaxDrawdownPercent = 0.0;
   if(g_peakEquity > 0.0 && g_cachedMaxDrawdownAmount > 0.0)
      g_cachedMaxDrawdownPercent = (g_cachedMaxDrawdownAmount / g_peakEquity) * 100.0;
}

int DateKeyFromTime(datetime ts)
{
   if(ts <= 0)
      return 0;

   MqlDateTime dt;
   TimeToStruct(ts, dt);
   return (dt.year * 10000) + (dt.mon * 100) + dt.day;
}

string DateKeyToString(int dateKey)
{
   if(dateKey <= 0)
      return "";

   int year = dateKey / 10000;
   int month = (dateKey / 100) % 100;
   int day = dateKey % 100;
   return StringFormat("%04d.%02d.%02d", year, month, day);
}

double CalculateTickDDPercentByBalance(double amount, double balance)
{
   if(amount <= 0.0 || balance <= 0.0)
      return 0.0;
   return (amount / balance) * 100.0;
}

void ResetTickDrawdownCurrentDay(int dateKey)
{
   g_tickDDCurrentDateKey = dateKey;
   g_tickDDCurrentDayInitialized = true;
   g_tickDDCurrentDayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(g_tickDDCurrentDayStartBalance <= 0.0)
      g_tickDDCurrentDayStartBalance = AccountInfoDouble(ACCOUNT_EQUITY);
   g_tickDDCurrentMaxFloating = 0.0;
   g_tickDDCurrentMaxFloatingTime = 0;
   g_tickDDCurrentMaxPendingLimitRisk = 0.0;
   g_tickDDCurrentMaxPendingLimitRiskTime = 0;
   g_tickDDCurrentMaxCombined = 0.0;
   g_tickDDCurrentMaxCombinedTime = 0;
   g_tickDDCurrentPendingLimitCountAtCombinedPeak = 0;
   g_tickDDCurrentMaxFloatingPositions = 0;
   g_tickDDCurrentMaxFloatingPositionsTime = 0;
}

void ClearTickDrawdownHistory()
{
   g_tickDDCurrentDateKey = 0;
   g_tickDDCurrentDayInitialized = false;
   g_tickDDCurrentDayStartBalance = 0.0;
   g_tickDDCurrentMaxFloating = 0.0;
   g_tickDDCurrentMaxFloatingTime = 0;
   g_tickDDCurrentMaxPendingLimitRisk = 0.0;
   g_tickDDCurrentMaxPendingLimitRiskTime = 0;
   g_tickDDCurrentMaxCombined = 0.0;
   g_tickDDCurrentMaxCombinedTime = 0;
   g_tickDDCurrentPendingLimitCountAtCombinedPeak = 0;
   g_tickDDCurrentMaxFloatingPositions = 0;
   g_tickDDCurrentMaxFloatingPositionsTime = 0;

   ArrayResize(g_tickDDDailyDateKeys, 0);
   ArrayResize(g_tickDDDailyDayStartBalances, 0);
   ArrayResize(g_tickDDDailyMaxFloating, 0);
   ArrayResize(g_tickDDDailyMaxFloatingPercentOfDayBalance, 0);
   ArrayResize(g_tickDDDailyMaxFloatingTimes, 0);
   ArrayResize(g_tickDDDailyMaxPendingLimitRisk, 0);
   ArrayResize(g_tickDDDailyMaxPendingLimitRiskTimes, 0);
   ArrayResize(g_tickDDDailyMaxCombined, 0);
   ArrayResize(g_tickDDDailyMaxCombinedTimes, 0);
   ArrayResize(g_tickDDDailyPendingLimitCountAtCombinedPeak, 0);
   ArrayResize(g_tickDDDailyMaxFloatingPositions, 0);
   ArrayResize(g_tickDDDailyMaxFloatingPositionsTimes, 0);
}

double CalculateCurrentFloatingExposure(int &openPositionsCount)
{
   openPositionsCount = 0;
   double totalFloating = 0.0;
   int totalPositions = PositionsTotal();
   for(int i = 0; i < totalPositions; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      ulong magic = (ulong)PositionGetInteger(POSITION_MAGIC);
      if(symbol != _Symbol || magic != MagicNumber)
         continue;

      openPositionsCount++;
      totalFloating += PositionGetDouble(POSITION_PROFIT);
   }

   if(totalFloating < 0.0)
      return -totalFloating;
   return 0.0;
}

double CalculateOpenPositionsStopRisk()
{
   double totalRisk = 0.0;
   int totalPositions = PositionsTotal();
   for(int i = 0; i < totalPositions; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      ulong magic = (ulong)PositionGetInteger(POSITION_MAGIC);
      if(symbol != _Symbol || magic != MagicNumber)
         continue;

      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      ENUM_ORDER_TYPE calcType = (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

      double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double volume = PositionGetDouble(POSITION_VOLUME);
      if(volume <= 0.0 || entryPrice <= 0.0 || sl <= 0.0)
         continue;

      double projectedProfitAtSL = 0.0;
      if(OrderCalcProfit(calcType, _Symbol, volume, entryPrice, sl, projectedProfitAtSL))
      {
         if(projectedProfitAtSL < 0.0)
            totalRisk += (-projectedProfitAtSL);
      }
   }

   return totalRisk;
}

void CalculatePendingLimitRisk(double &riskAmount, int &pendingLimitCount)
{
   riskAmount = 0.0;
   pendingLimitCount = 0;

   int totalOrders = OrdersTotal();
   for(int i = 0; i < totalOrders; i++)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;

      string symbol = OrderGetString(ORDER_SYMBOL);
      ulong magic = (ulong)OrderGetInteger(ORDER_MAGIC);
      if(symbol != _Symbol || magic != MagicNumber)
         continue;

      ENUM_ORDER_TYPE orderType = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(orderType != ORDER_TYPE_BUY_LIMIT && orderType != ORDER_TYPE_SELL_LIMIT)
         continue;

      pendingLimitCount++;

      double sl = OrderGetDouble(ORDER_SL);
      double entryPrice = OrderGetDouble(ORDER_PRICE_OPEN);
      double volume = OrderGetDouble(ORDER_VOLUME_CURRENT);
      if(volume <= 0.0)
         volume = OrderGetDouble(ORDER_VOLUME_INITIAL);

      if(sl <= 0.0 || entryPrice <= 0.0 || volume <= 0.0)
         continue;

      double projectedProfitAtSL = 0.0;
      ENUM_ORDER_TYPE calcType = (orderType == ORDER_TYPE_BUY_LIMIT) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      if(OrderCalcProfit(calcType, _Symbol, volume, entryPrice, sl, projectedProfitAtSL))
      {
         if(projectedProfitAtSL < 0.0)
            riskAmount += (-projectedProfitAtSL);
      }
   }
}

void FinalizeTickDrawdownCurrentDay()
{
   if(!g_tickDDCurrentDayInitialized || g_tickDDCurrentDateKey <= 0)
      return;

   double dayStartBalance = g_tickDDCurrentDayStartBalance;
   if(dayStartBalance <= 0.0)
      dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(dayStartBalance <= 0.0)
      dayStartBalance = AccountInfoDouble(ACCOUNT_EQUITY);
   double dayMaxFloatingPercent = CalculateTickDDPercentByBalance(g_tickDDCurrentMaxFloating, dayStartBalance);

   int total = ArraySize(g_tickDDDailyDateKeys);
   if(total > 0 && g_tickDDDailyDateKeys[total - 1] == g_tickDDCurrentDateKey)
   {
      int idx = total - 1;
      if(g_tickDDDailyDayStartBalances[idx] <= 0.0 && dayStartBalance > 0.0)
         g_tickDDDailyDayStartBalances[idx] = dayStartBalance;
      if(g_tickDDCurrentMaxFloating > g_tickDDDailyMaxFloating[idx])
      {
         g_tickDDDailyMaxFloating[idx] = g_tickDDCurrentMaxFloating;
         g_tickDDDailyMaxFloatingTimes[idx] = g_tickDDCurrentMaxFloatingTime;
         double baseBalance = g_tickDDDailyDayStartBalances[idx];
         if(baseBalance <= 0.0)
            baseBalance = dayStartBalance;
         g_tickDDDailyMaxFloatingPercentOfDayBalance[idx] = CalculateTickDDPercentByBalance(g_tickDDCurrentMaxFloating, baseBalance);
      }
      if(g_tickDDCurrentMaxPendingLimitRisk > g_tickDDDailyMaxPendingLimitRisk[idx])
      {
         g_tickDDDailyMaxPendingLimitRisk[idx] = g_tickDDCurrentMaxPendingLimitRisk;
         g_tickDDDailyMaxPendingLimitRiskTimes[idx] = g_tickDDCurrentMaxPendingLimitRiskTime;
      }
      if(g_tickDDCurrentMaxCombined > g_tickDDDailyMaxCombined[idx] ||
         (g_tickDDCurrentMaxCombined == g_tickDDDailyMaxCombined[idx] &&
          g_tickDDCurrentPendingLimitCountAtCombinedPeak > g_tickDDDailyPendingLimitCountAtCombinedPeak[idx]))
      {
         g_tickDDDailyMaxCombined[idx] = g_tickDDCurrentMaxCombined;
         g_tickDDDailyMaxCombinedTimes[idx] = g_tickDDCurrentMaxCombinedTime;
         g_tickDDDailyPendingLimitCountAtCombinedPeak[idx] = g_tickDDCurrentPendingLimitCountAtCombinedPeak;
      }
      if(g_tickDDCurrentMaxFloatingPositions > g_tickDDDailyMaxFloatingPositions[idx])
      {
         g_tickDDDailyMaxFloatingPositions[idx] = g_tickDDCurrentMaxFloatingPositions;
         g_tickDDDailyMaxFloatingPositionsTimes[idx] = g_tickDDCurrentMaxFloatingPositionsTime;
      }
      return;
   }

   int newSize = total + 1;
   ArrayResize(g_tickDDDailyDateKeys, newSize);
   ArrayResize(g_tickDDDailyDayStartBalances, newSize);
   ArrayResize(g_tickDDDailyMaxFloating, newSize);
   ArrayResize(g_tickDDDailyMaxFloatingPercentOfDayBalance, newSize);
   ArrayResize(g_tickDDDailyMaxFloatingTimes, newSize);
   ArrayResize(g_tickDDDailyMaxPendingLimitRisk, newSize);
   ArrayResize(g_tickDDDailyMaxPendingLimitRiskTimes, newSize);
   ArrayResize(g_tickDDDailyMaxCombined, newSize);
   ArrayResize(g_tickDDDailyMaxCombinedTimes, newSize);
   ArrayResize(g_tickDDDailyPendingLimitCountAtCombinedPeak, newSize);
   ArrayResize(g_tickDDDailyMaxFloatingPositions, newSize);
   ArrayResize(g_tickDDDailyMaxFloatingPositionsTimes, newSize);

   int i = newSize - 1;
   g_tickDDDailyDateKeys[i] = g_tickDDCurrentDateKey;
   g_tickDDDailyDayStartBalances[i] = dayStartBalance;
   g_tickDDDailyMaxFloating[i] = g_tickDDCurrentMaxFloating;
   g_tickDDDailyMaxFloatingPercentOfDayBalance[i] = dayMaxFloatingPercent;
   g_tickDDDailyMaxFloatingTimes[i] = g_tickDDCurrentMaxFloatingTime;
   g_tickDDDailyMaxPendingLimitRisk[i] = g_tickDDCurrentMaxPendingLimitRisk;
   g_tickDDDailyMaxPendingLimitRiskTimes[i] = g_tickDDCurrentMaxPendingLimitRiskTime;
   g_tickDDDailyMaxCombined[i] = g_tickDDCurrentMaxCombined;
   g_tickDDDailyMaxCombinedTimes[i] = g_tickDDCurrentMaxCombinedTime;
   g_tickDDDailyPendingLimitCountAtCombinedPeak[i] = g_tickDDCurrentPendingLimitCountAtCombinedPeak;
   g_tickDDDailyMaxFloatingPositions[i] = g_tickDDCurrentMaxFloatingPositions;
   g_tickDDDailyMaxFloatingPositionsTimes[i] = g_tickDDCurrentMaxFloatingPositionsTime;
}

void UpdateTickDrawdownTracking()
{
   datetime nowTime = TimeCurrent();
   int dateKey = DateKeyFromTime(nowTime);

   if(!g_tickDDCurrentDayInitialized)
   {
      ResetTickDrawdownCurrentDay(dateKey);
   }
   else if(dateKey != g_tickDDCurrentDateKey)
   {
      FinalizeTickDrawdownCurrentDay();
      ResetTickDrawdownCurrentDay(dateKey);
   }

   int floatingPositionsCount = 0;
   double floatingExposure = CalculateCurrentFloatingExposure(floatingPositionsCount);
   double openStopRisk = CalculateOpenPositionsStopRisk();
   double pendingLimitRisk = 0.0;
   int pendingLimitCount = 0;
   CalculatePendingLimitRisk(pendingLimitRisk, pendingLimitCount);
   // DD+Limit (pior caso): risco no SL das posicoes abertas + risco no SL das LIMIT pendentes.
   double combinedExposure = openStopRisk + pendingLimitRisk;

   if(floatingExposure > g_tickDDCurrentMaxFloating)
   {
      g_tickDDCurrentMaxFloating = floatingExposure;
      g_tickDDCurrentMaxFloatingTime = nowTime;
   }

   if(pendingLimitRisk > g_tickDDCurrentMaxPendingLimitRisk)
   {
      g_tickDDCurrentMaxPendingLimitRisk = pendingLimitRisk;
      g_tickDDCurrentMaxPendingLimitRiskTime = nowTime;
   }

   if(floatingPositionsCount > g_tickDDCurrentMaxFloatingPositions)
   {
      g_tickDDCurrentMaxFloatingPositions = floatingPositionsCount;
      g_tickDDCurrentMaxFloatingPositionsTime = nowTime;
   }

   if(combinedExposure > g_tickDDCurrentMaxCombined ||
      (combinedExposure == g_tickDDCurrentMaxCombined &&
       pendingLimitCount > g_tickDDCurrentPendingLimitCountAtCombinedPeak))
   {
      g_tickDDCurrentMaxCombined = combinedExposure;
      g_tickDDCurrentMaxCombinedTime = nowTime;
      g_tickDDCurrentPendingLimitCountAtCombinedPeak = pendingLimitCount;
   }
}

double SumTickDrawdownArray(const double &values[])
{
   double sum = 0.0;
   int total = ArraySize(values);
   for(int i = 0; i < total; i++)
      sum += values[i];
   return sum;
}

double MaxTickDrawdownArray(const double &values[])
{
   double maxValue = 0.0;
   int total = ArraySize(values);
   for(int i = 0; i < total; i++)
   {
      if(values[i] > maxValue)
         maxValue = values[i];
   }
   return maxValue;
}

void ExecuteDrawdownEmergencyProtection(string context, int breachType)
{
   if(!EnableP0EmergencyFlattenOnDD)
      return;

   datetime now = TimeCurrent();
   int retrySeconds = (P0EmergencyRetrySeconds <= 0) ? 1 : P0EmergencyRetrySeconds;
   if(g_drawdownEmergencyLockActive &&
      g_drawdownEmergencyLastType == breachType &&
      (now - g_drawdownEmergencyLastAttempt) < retrySeconds)
      return;

   g_drawdownEmergencyLockActive = true;
   g_drawdownEmergencyLastType = breachType;
   g_drawdownEmergencyLastContext = context;
   g_drawdownEmergencyLastAttempt = now;

   if(g_preArmedReversalOrderTicket > 0)
      CancelPreArmedReversalOrder("lock DD emergencia");
   CancelNegativeAddPendingOrders("lock DD emergencia");

   int canceledPending = CancelAllPendingOrdersForNoOvernight("lock DD emergencia");
   int closedPositions = CloseAllOpenPositionsForNoOvernight();

   ulong remainingOpenTickets[];
   int remainingOpen = CollectEAOpenPositionTickets(remainingOpenTickets);
   ulong remainingPendingTickets[];
   int remainingPending = CollectEAPendingOrderTickets(remainingPendingTickets);

   if(remainingOpen == 0 && remainingPending == 0)
   {
      if(g_pendingOrderPlaced)
         ClearPendingOrderState(true);
      if(g_currentTicket > 0 && !PositionSelectByTicket(g_currentTicket))
      {
         g_currentTicket = 0;
         ClearCurrentTradePositionTickets();
      }
   }

   Print("ALERTA: lock DD emergencia ativo",
         (context == "" ? "" : " [" + context + "]"),
         " | tipo=", breachType,
         " | canceladas=", canceledPending,
         " | fechadas=", closedPositions,
         " | abertas_restantes=", remainingOpen,
         " | pendentes_restantes=", remainingPending);
}

//+------------------------------------------------------------------+
//| Verifica se algum limite de drawdown foi atingido                |
//+------------------------------------------------------------------+
bool IsDrawdownLimitReached(string context = "")
{
   UpdateDrawdownMetrics();

   if(MaxDailyDrawdownPercent > 0.0 && g_cachedDailyDrawdownPercent >= MaxDailyDrawdownPercent)
   {
      datetime now = TimeCurrent();
      bool shouldLog = (g_drawdownLastBlockType != 1) ||
                       (g_drawdownLastBlockContext != context) ||
                       ((now - g_drawdownLastBlockLogTime) >= 60);
      if(shouldLog)
      {
         Print("BLOQUEIO DD diario", (context == "" ? "" : " [" + context + "]"),
               " | atual=", DoubleToString(g_cachedDailyDrawdownPercent, 2),
               "% | limite=", DoubleToString(MaxDailyDrawdownPercent, 2), "%",
               " | valor=", DoubleToString(g_cachedDailyDrawdownAmount, 2));
         g_drawdownLastBlockLogTime = now;
         g_drawdownLastBlockType = 1;
         g_drawdownLastBlockContext = context;
      }
      ExecuteDrawdownEmergencyProtection(context, 1);
      return true;
   }

   if(MaxDailyDrawdownAmount > 0.0 && g_cachedDailyDrawdownAmount >= MaxDailyDrawdownAmount)
   {
      datetime now = TimeCurrent();
      bool shouldLog = (g_drawdownLastBlockType != 3) ||
                       (g_drawdownLastBlockContext != context) ||
                       ((now - g_drawdownLastBlockLogTime) >= 60);
      if(shouldLog)
      {
         Print("BLOQUEIO DD diario abs", (context == "" ? "" : " [" + context + "]"),
               " | atual=", DoubleToString(g_cachedDailyDrawdownAmount, 2),
               " | limite=", DoubleToString(MaxDailyDrawdownAmount, 2),
               " | pct=", DoubleToString(g_cachedDailyDrawdownPercent, 2), "%");
         g_drawdownLastBlockLogTime = now;
         g_drawdownLastBlockType = 3;
         g_drawdownLastBlockContext = context;
      }
      ExecuteDrawdownEmergencyProtection(context, 3);
      return true;
   }

   if(MaxDrawdownPercent > 0.0 && g_cachedMaxDrawdownPercent >= MaxDrawdownPercent)
   {
      datetime now = TimeCurrent();
      bool shouldLog = (g_drawdownLastBlockType != 2) ||
                       (g_drawdownLastBlockContext != context) ||
                       ((now - g_drawdownLastBlockLogTime) >= 60);
      if(shouldLog)
      {
         Print("BLOQUEIO DD maximo", (context == "" ? "" : " [" + context + "]"),
               " | atual=", DoubleToString(g_cachedMaxDrawdownPercent, 2),
               "% | limite=", DoubleToString(MaxDrawdownPercent, 2), "%",
               " | valor=", DoubleToString(g_cachedMaxDrawdownAmount, 2));
         g_drawdownLastBlockLogTime = now;
         g_drawdownLastBlockType = 2;
         g_drawdownLastBlockContext = context;
      }
      ExecuteDrawdownEmergencyProtection(context, 2);
      return true;
   }

   if(MaxDrawdownAmount > 0.0 && g_cachedMaxDrawdownAmount >= MaxDrawdownAmount)
   {
      datetime now = TimeCurrent();
      bool shouldLog = (g_drawdownLastBlockType != 4) ||
                       (g_drawdownLastBlockContext != context) ||
                       ((now - g_drawdownLastBlockLogTime) >= 60);
      if(shouldLog)
      {
         Print("BLOQUEIO DD maximo abs", (context == "" ? "" : " [" + context + "]"),
               " | atual=", DoubleToString(g_cachedMaxDrawdownAmount, 2),
               " | limite=", DoubleToString(MaxDrawdownAmount, 2),
               " | pct=", DoubleToString(g_cachedMaxDrawdownPercent, 2), "%");
         g_drawdownLastBlockLogTime = now;
         g_drawdownLastBlockType = 4;
         g_drawdownLastBlockContext = context;
      }
      ExecuteDrawdownEmergencyProtection(context, 4);
      return true;
   }

   if(g_drawdownEmergencyLockActive)
   {
      g_drawdownEmergencyLockActive = false;
      g_drawdownEmergencyLastType = 0;
      g_drawdownEmergencyLastContext = "";
   }

   g_drawdownLastBlockType = 0;
   g_drawdownLastBlockContext = "";
   return false;
}

//+------------------------------------------------------------------+
//| Coleta posicoes ativas da operacao atual (symbol+magic+sentido) |
//+------------------------------------------------------------------+
int CollectActiveCurrentTradePositions(ulong &tickets[], double &totalVolume, double &weightedEntryPrice, double &totalFloatingProfit)
{
   ArrayResize(tickets, 0);
   totalVolume = 0.0;
   weightedEntryPrice = 0.0;
   totalFloatingProfit = 0.0;

   if(g_currentOrderType != ORDER_TYPE_BUY && g_currentOrderType != ORDER_TYPE_SELL)
      return 0;

   datetime minEntryTime = g_tradeEntryTime;
   int totalPositions = PositionsTotal();
   for(int i = 0; i < totalPositions; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      ulong magic = (ulong)PositionGetInteger(POSITION_MAGIC);
      if(symbol != _Symbol || magic != MagicNumber)
         continue;

      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      ENUM_ORDER_TYPE posOrderType = (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      if(posOrderType != g_currentOrderType)
         continue;

      datetime posTime = (datetime)PositionGetInteger(POSITION_TIME);
      if(minEntryTime > 0 && posTime + 1 < minEntryTime)
         continue;

      int n = ArraySize(tickets);
      ArrayResize(tickets, n + 1);
      tickets[n] = ticket;

      double vol = PositionGetDouble(POSITION_VOLUME);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double floatingProfit = PositionGetDouble(POSITION_PROFIT);

      totalVolume += vol;
      weightedEntryPrice += (openPrice * vol);
      totalFloatingProfit += floatingProfit;
   }

   if(totalVolume > 0.0)
      weightedEntryPrice /= totalVolume;
   else
      weightedEntryPrice = 0.0;

   return ArraySize(tickets);
}

//+------------------------------------------------------------------+
//| Agrega resumo de fechamento da operacao atual (multiplas pos.)  |
//+------------------------------------------------------------------+
bool GetClosedCurrentTradeSummary(double &totalProfit,
                                  double &totalGrossProfit,
                                  double &totalSwap,
                                  double &totalCommission,
                                  double &totalFee,
                                  double &lastExitPrice,
                                  datetime &lastExitTime,
                                  int &slCloseCount,
                                  int &tpCloseCount)
{
   totalProfit = 0.0;
   totalGrossProfit = 0.0;
   totalSwap = 0.0;
   totalCommission = 0.0;
   totalFee = 0.0;
   lastExitPrice = 0.0;
   lastExitTime = 0;
   slCloseCount = 0;
   tpCloseCount = 0;

   bool foundExit = false;
   int trackedTotal = ArraySize(g_currentTradePositionTickets);
   for(int t = 0; t < trackedTotal; t++)
   {
      ulong ticket = g_currentTradePositionTickets[t];
      if(ticket == 0)
         continue;

      if(!HistorySelectByPosition(ticket))
         continue;

      int dealsTotal = HistoryDealsTotal();
      for(int i = 0; i < dealsTotal; i++)
      {
         ulong dealTicket = HistoryDealGetTicket(i);
         if(dealTicket == 0)
            continue;

         long dealEntry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
         if(dealEntry != DEAL_ENTRY_OUT)
            continue;

         double dealProfit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
         double dealSwap = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
         double dealCommission = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
         double dealFee = HistoryDealGetDouble(dealTicket, DEAL_FEE);
         totalGrossProfit += dealProfit;
         totalSwap += dealSwap;
         totalCommission += dealCommission;
         totalFee += dealFee;
         totalProfit += (dealProfit + dealSwap + dealCommission + dealFee);
         datetime dealTime = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
         if(!foundExit || dealTime >= lastExitTime)
         {
            lastExitTime = dealTime;
            lastExitPrice = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
         }

         long dealReason = HistoryDealGetInteger(dealTicket, DEAL_REASON);
         if(dealReason == DEAL_REASON_SL)
            slCloseCount++;
         else if(dealReason == DEAL_REASON_TP)
            tpCloseCount++;

         foundExit = true;
      }
   }

   return foundExit;
}

//+------------------------------------------------------------------+
//| Verifica se comentario pertence a adicao negativa                |
//+------------------------------------------------------------------+
bool IsNegativeAddComment(string text)
{
   if(text == "")
      return false;

   string lowerText = text;
   StringToLower(lowerText);
   if(StringFind(lowerText, "addon negativo") >= 0)
      return true;
   if(StringFind(lowerText, "add on negativo") >= 0)
      return true;
   if(StringFind(lowerText, "addon") >= 0 && StringFind(lowerText, "negativo") >= 0)
      return true;

   return false;
}

//+------------------------------------------------------------------+
//| Verifica se o ticket possui entrada de addon negativa            |
//+------------------------------------------------------------------+
bool IsNegativeAddTicket(ulong ticket)
{
   if(ticket == 0)
      return false;

   // Prioriza rastreamento runtime dos tickets executados como addon.
   // Isso evita depender apenas de comentario de deal/order (que pode variar em live).
   if(FindNegativeAddExecutedTicket(ticket) >= 0)
      return true;

   if(!HistorySelectByPosition(ticket))
      return false;

   int dealsTotal = HistoryDealsTotal();
   for(int i = 0; i < dealsTotal; i++)
   {
      ulong dealTicket = HistoryDealGetTicket(i);
      if(dealTicket == 0)
         continue;

      long dealEntry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
      if(dealEntry != DEAL_ENTRY_IN)
         continue;

      string dealComment = HistoryDealGetString(dealTicket, DEAL_COMMENT);
      if(IsNegativeAddComment(dealComment))
         return true;

      ulong orderTicket = (ulong)HistoryDealGetInteger(dealTicket, DEAL_ORDER);
      if(orderTicket > 0)
      {
         string orderComment = HistoryOrderGetString(orderTicket, ORDER_COMMENT);
         if(IsNegativeAddComment(orderComment))
            return true;
      }
   }

   return false;
}

//+------------------------------------------------------------------+
//| Coleta metricas de addon pelos tickets informados                |
//+------------------------------------------------------------------+
void CollectNegativeAddMetricsFromTickets(const ulong &tickets[],
                                          int &addOnCount,
                                          double &addOnLots,
                                          double &addOnAvgEntryPrice,
                                          double &addOnProfit)
{
   addOnCount = 0;
   addOnLots = 0.0;
   addOnAvgEntryPrice = 0.0;
   addOnProfit = 0.0;

   double weightedAddOnEntryPrice = 0.0;
   int ticketCount = ArraySize(tickets);
   for(int t = 0; t < ticketCount; t++)
   {
      ulong ticket = tickets[t];
      if(ticket == 0)
         continue;

      if(!HistorySelectByPosition(ticket))
         continue;

      bool ticketHasAddOnEntry = false;
      double ticketExitProfit = 0.0;
      int dealsTotal = HistoryDealsTotal();
      for(int i = 0; i < dealsTotal; i++)
      {
         ulong dealTicket = HistoryDealGetTicket(i);
         if(dealTicket == 0)
            continue;

         long dealEntry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
         if(dealEntry == DEAL_ENTRY_IN)
         {
            string dealComment = HistoryDealGetString(dealTicket, DEAL_COMMENT);
            ulong orderTicket = (ulong)HistoryDealGetInteger(dealTicket, DEAL_ORDER);
            string orderComment = "";
            if(orderTicket > 0)
               orderComment = HistoryOrderGetString(orderTicket, ORDER_COMMENT);

            bool isAddOnEntry = IsNegativeAddComment(dealComment) || IsNegativeAddComment(orderComment);
            if(isAddOnEntry)
            {
               ticketHasAddOnEntry = true;
               addOnCount++;

               double entryVolume = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);
               double entryPrice = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
               addOnLots += entryVolume;
               weightedAddOnEntryPrice += (entryPrice * entryVolume);
            }
         }
         else if(dealEntry == DEAL_ENTRY_OUT)
         {
            double dealProfit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
            double dealSwap = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
            double dealCommission = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
            double dealFee = HistoryDealGetDouble(dealTicket, DEAL_FEE);
            ticketExitProfit += (dealProfit + dealSwap + dealCommission + dealFee);
         }
      }

      // Em conta hedging, cada addon costuma virar um ticket proprio.
      if(ticketHasAddOnEntry)
         addOnProfit += ticketExitProfit;
   }

   if(addOnLots > 0.0)
      addOnAvgEntryPrice = weightedAddOnEntryPrice / addOnLots;
}

//+------------------------------------------------------------------+
//| Coleta metricas de addon da operacao atual                       |
//+------------------------------------------------------------------+
void CollectNegativeAddMetricsCurrentTrade(int &addOnCount,
                                           double &addOnLots,
                                           double &addOnAvgEntryPrice,
                                           double &addOnProfit)
{
   ulong tickets[];
   int trackedCount = ArraySize(g_currentTradePositionTickets);
   if(trackedCount > 0)
   {
      ArrayResize(tickets, trackedCount);
      for(int i = 0; i < trackedCount; i++)
         tickets[i] = g_currentTradePositionTickets[i];
   }
   else if(g_currentTicket > 0)
   {
      ArrayResize(tickets, 1);
      tickets[0] = g_currentTicket;
   }
   else
   {
      ArrayResize(tickets, 0);
   }

   // Primeiro tenta via historico/comentarios.
   int historyAddOnCount = 0;
   double historyAddOnLots = 0.0;
   double historyAddOnAvgEntryPrice = 0.0;
   double historyAddOnProfit = 0.0;
   CollectNegativeAddMetricsFromTickets(tickets,
                                        historyAddOnCount,
                                        historyAddOnLots,
                                        historyAddOnAvgEntryPrice,
                                        historyAddOnProfit);

   // Depois combina com dados de runtime (mais robusto para contagem/lotes).
   int runtimeAddOnCount = 0;
   double runtimeAddOnLots = 0.0;
   double runtimeAddOnAvgEntryPrice = 0.0;
   GetNegativeAddRuntimeMetrics(runtimeAddOnCount, runtimeAddOnLots, runtimeAddOnAvgEntryPrice);

   addOnCount = historyAddOnCount;
   if(runtimeAddOnCount > addOnCount)
      addOnCount = runtimeAddOnCount;

   addOnLots = historyAddOnLots;
   if(runtimeAddOnLots > addOnLots)
      addOnLots = runtimeAddOnLots;

   addOnAvgEntryPrice = historyAddOnAvgEntryPrice;
   if(runtimeAddOnLots > 0.0)
      addOnAvgEntryPrice = runtimeAddOnAvgEntryPrice;

   addOnProfit = historyAddOnProfit;
   double runtimeAddOnProfit = CollectProfitFromTicketsHistory(g_negativeAddExecutedTickets);
   if(runtimeAddOnProfit != 0.0 || ArraySize(g_negativeAddExecutedTickets) > 0)
      addOnProfit = runtimeAddOnProfit;
}

//+------------------------------------------------------------------+
//| Log de diagnostico da adicao negativa com controle de frequencia|
//+------------------------------------------------------------------+
void LogNegativeAddDebug(int reasonCode, string details, bool force=false)
{
   if(!EnableNegativeAddDebugLogs || !EnableNegativeAddOn)
      return;

   datetime now = TimeCurrent();
   int intervalSec = (NegativeAddDebugIntervalSeconds < 0) ? 0 : NegativeAddDebugIntervalSeconds;
   bool shouldLog = force;

   if(!shouldLog)
   {
      if(reasonCode != g_negativeAddLastReasonCode)
         shouldLog = true;
      else if(intervalSec == 0 || (now - g_negativeAddLastDebugLogTime) >= intervalSec)
         shouldLog = true;
   }

   if(!shouldLog)
      return;

   g_negativeAddLastReasonCode = reasonCode;
   g_negativeAddLastDebugLogTime = now;
   Print("NEG_ADD DEBUG | reason=", reasonCode, " | ", details);
}

//+------------------------------------------------------------------+
//| Calcula profit flutuante estimado para uma entrada/ordem        |
//+------------------------------------------------------------------+
bool CalculateFloatingProfit(ENUM_ORDER_TYPE orderType, double entryPrice, double volume, double &floatingProfit)
{
   if(volume <= 0 || entryPrice <= 0)
      return false;

   double currentPrice = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double calcProfit = 0;
   if(!OrderCalcProfit(orderType, _Symbol, volume, entryPrice, currentPrice, calcProfit))
      return false;

   floatingProfit = calcProfit;
   return true;
}

//+------------------------------------------------------------------+
//| Calcula percentual adverso percorrido da entrada ate o SL        |
//+------------------------------------------------------------------+
double CalculateAdverseToSLPercent(ENUM_ORDER_TYPE orderType, double entryPrice, double stopLoss)
{
   if((orderType != ORDER_TYPE_BUY && orderType != ORDER_TYPE_SELL) || entryPrice <= 0.0 || stopLoss <= 0.0)
      return 0.0;

   double riskDistance = MathAbs(entryPrice - stopLoss);
   if(riskDistance <= 0.0)
      return 0.0;

   double currentPrice = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double adverseDistance = (orderType == ORDER_TYPE_BUY) ? (entryPrice - currentPrice) : (currentPrice - entryPrice);
   if(adverseDistance <= 0.0)
      return 0.0;

   return (adverseDistance / riskDistance) * 100.0;
}

double CalculateFavorableToTPPercent(ENUM_ORDER_TYPE orderType, double entryPrice, double takeProfit)
{
   if((orderType != ORDER_TYPE_BUY && orderType != ORDER_TYPE_SELL) || entryPrice <= 0.0 || takeProfit <= 0.0)
      return 0.0;

   double tpDistance = MathAbs(takeProfit - entryPrice);
   if(tpDistance <= 0.0)
      return 0.0;

   double currentPrice = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double favorableDistance = (orderType == ORDER_TYPE_BUY) ? (currentPrice - entryPrice) : (entryPrice - currentPrice);
   if(favorableDistance <= 0.0)
      return 0.0;

   double pct = (favorableDistance / tpDistance) * 100.0;
   if(pct < 0.0)
      return 0.0;
   if(pct > 100.0)
      return 100.0;
   return pct;
}

//+------------------------------------------------------------------+
//| Atualiza metricas de flutuacao da operacao atual                |
//+------------------------------------------------------------------+
void UpdateCurrentTradeFloatingMetricsFromPosition()
{
   if(g_currentTicket == 0 || g_pendingOrderPlaced)
      return;
   ulong activeTickets[];
   double totalVolume = 0.0;
   double weightedEntryPrice = 0.0;
   double floatingProfit = 0.0;
   int activeCount = CollectActiveCurrentTradePositions(activeTickets, totalVolume, weightedEntryPrice, floatingProfit);
   if(activeCount <= 0)
      return;

   if(floatingProfit > g_tradeMaxFloatingProfit)
      g_tradeMaxFloatingProfit = floatingProfit;
   if(floatingProfit < g_tradeMaxFloatingDrawdown)
      g_tradeMaxFloatingDrawdown = floatingProfit;

   if(g_tradeEntryPrice <= 0.0 && weightedEntryPrice > 0.0)
      g_tradeEntryPrice = weightedEntryPrice;

   double referenceEntryPrice = (g_tradeEntryPrice > 0.0) ? g_tradeEntryPrice : weightedEntryPrice;
   if(referenceEntryPrice > 0.0 && g_firstTradeStopLoss > 0.0)
   {
      double adverseToSLPercent = CalculateAdverseToSLPercent(g_currentOrderType, referenceEntryPrice, g_firstTradeStopLoss);
      if(adverseToSLPercent > g_tradeMaxAdverseToSLPercent)
         g_tradeMaxAdverseToSLPercent = adverseToSLPercent;
   }

   if(referenceEntryPrice > 0.0 && g_firstTradeTakeProfit > 0.0)
   {
      double favorableToTPPercent = CalculateFavorableToTPPercent(g_currentOrderType, referenceEntryPrice, g_firstTradeTakeProfit);
      if(favorableToTPPercent > g_tradeMaxFavorableToTPPercent)
         g_tradeMaxFavorableToTPPercent = favorableToTPPercent;
   }

   // Atualiza snapshots tick-a-tick dos tickets de addon para log detalhado.
   UpdateNegativeAddSnapshotsFromOpenPositions();
}

//+------------------------------------------------------------------+
//| Calcula novo TP baseado em % da distancia da entrada ate o SL    |
//+------------------------------------------------------------------+
double CalculateTakeProfitByStopDistancePercent(ENUM_ORDER_TYPE orderType,
                                                double referenceEntryPrice,
                                                double stopLoss,
                                                double distancePercent)
{
   if((orderType != ORDER_TYPE_BUY && orderType != ORDER_TYPE_SELL) || referenceEntryPrice <= 0.0 || stopLoss <= 0.0)
      return 0.0;

   double distanceMultiplier = distancePercent / 100.0;
   if(distanceMultiplier <= 0.0)
      return 0.0;

   double stopDistance = MathAbs(referenceEntryPrice - stopLoss);
   if(stopDistance <= 0.0)
      return 0.0;

   if(orderType == ORDER_TYPE_BUY)
      return referenceEntryPrice + (stopDistance * distanceMultiplier);

   return referenceEntryPrice - (stopDistance * distanceMultiplier);
}

//+------------------------------------------------------------------+
//| Aplica SL/TP para todas as posicoes ativas da operacao atual     |
//+------------------------------------------------------------------+
bool ApplySLTPToCurrentTradePositions(double stopLoss,
                                      double takeProfit,
                                      int &modifiedCount,
                                      string context)
{
   modifiedCount = 0;

   if(g_currentOrderType != ORDER_TYPE_BUY && g_currentOrderType != ORDER_TYPE_SELL)
      return false;

   ulong activeTickets[];
   double activeVolume = 0.0;
   double weightedEntryPrice = 0.0;
   double activeFloating = 0.0;
   int activeCount = CollectActiveCurrentTradePositions(activeTickets, activeVolume, weightedEntryPrice, activeFloating);
   if(activeCount <= 0)
   {
      LogNegativeAddDebug(42, context + " | no active positions");
      return false;
   }

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   stopLoss = NormalizeDouble(stopLoss, digits);
   takeProfit = NormalizeDouble(takeProfit, digits);

   bool allModified = true;
   double epsilon = g_pointValue * 0.5;
   if(epsilon <= 0.0)
      epsilon = 0.00000001;

   for(int i = 0; i < activeCount; i++)
   {
      ulong ticket = activeTickets[i];
      if(ticket == 0 || !PositionSelectByTicket(ticket))
      {
         allModified = false;
         continue;
      }

      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      if(MathAbs(currentSL - stopLoss) <= epsilon && MathAbs(currentTP - takeProfit) <= epsilon)
      {
         modifiedCount++;
         continue;
      }

      bool modified = trade.PositionModify(ticket, stopLoss, takeProfit);
      if(!modified)
      {
         allModified = false;
         LogNegativeAddDebug(43,
                             context + " | modify failed ticket=" + StringFormat("%I64u", ticket) +
                             " | retcode=" + IntegerToString((int)trade.ResultRetcode()) +
                             " | " + trade.ResultRetcodeDescription(),
                             true);
      }
      else
         modifiedCount++;
   }

   // Fallback para conta netting quando nao houver ticket alterado.
   if(modifiedCount == 0)
   {
      bool modified = trade.PositionModify(_Symbol, stopLoss, takeProfit);
      if(modified)
         modifiedCount = 1;
      else
      {
         allModified = false;
         LogNegativeAddDebug(44,
                             context + " | symbol modify failed retcode=" + IntegerToString((int)trade.ResultRetcode()) +
                             " | " + trade.ResultRetcodeDescription(),
                             true);
      }
   }

   return (allModified && modifiedCount > 0);
}

bool PlaceNegativeAddOnLimitOrdersForStrictMode(double referenceEntryPrice)
{
   if(g_negativeAddPendingOrdersPlaced)
      return (ArraySize(g_negativeAddPendingOrderTickets) > 0);

   if(IsDrawdownLimitReached("PlaceNegativeAddOnLimitOrdersForStrictMode"))
      return false;

   if(g_currentOrderType != ORDER_TYPE_BUY && g_currentOrderType != ORDER_TYPE_SELL)
      return false;
   double baseLot = IsFixedLotAllEntriesEnabled() ? ResolveFixedLotAllEntries() : g_firstTradeLotSize;
   if(referenceEntryPrice <= 0.0 || g_firstTradeStopLoss <= 0.0 || baseLot <= 0.0)
      return false;
   if(NegativeAddMaxEntries <= 0 || NegativeAddTriggerPercent <= 0.0)
      return false;
   if(!IsFixedLotAllEntriesEnabled() && NegativeAddLotMultiplier <= 0.0)
      return false;

   double triggerStepFraction = NegativeAddTriggerPercent / 100.0;
   if(triggerStepFraction <= 0.0)
      return false;

   double addLot = 0.0;
   if(IsFixedLotAllEntriesEnabled())
      addLot = ResolveFixedLotAllEntries();
   else
      addLot = NormalizeLot(baseLot * NegativeAddLotMultiplier);
   if(addLot <= 0.0)
      return false;

   double riskDistance = MathAbs(referenceEntryPrice - g_firstTradeStopLoss);
   if(riskDistance <= 0.0)
      return false;

   double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double epsilon = g_pointValue;
   if(epsilon <= 0.0)
      epsilon = 0.00001;

   bool placedAny = false;
   for(int step = 1; step <= NegativeAddMaxEntries; step++)
   {
      double requiredFraction = triggerStepFraction * step;
      double limitPrice = 0.0;
      if(g_currentOrderType == ORDER_TYPE_BUY)
         limitPrice = referenceEntryPrice - (riskDistance * requiredFraction);
      else
         limitPrice = referenceEntryPrice + (riskDistance * requiredFraction);

      limitPrice = NormalizePriceToTick(limitPrice);

      // Evita colocar addon no proprio SL ou alem dele.
      if(g_currentOrderType == ORDER_TYPE_BUY && limitPrice <= (g_firstTradeStopLoss + epsilon))
      {
         LogNegativeAddDebug(55,
                             "strict addon skip step=" + IntegerToString(step) +
                             " | limit reached SL (buy)");
         continue;
      }
      if(g_currentOrderType == ORDER_TYPE_SELL && limitPrice >= (g_firstTradeStopLoss - epsilon))
      {
         LogNegativeAddDebug(55,
                             "strict addon skip step=" + IntegerToString(step) +
                             " | limit reached SL (sell)");
         continue;
      }

      double stopLoss = 0.0;
      double takeProfit = 0.0;
      if(NegativeAddUseSameSLTP)
      {
         stopLoss = NormalizePriceToTick(g_firstTradeStopLoss);
         takeProfit = NormalizePriceToTick(g_firstTradeTakeProfit);
      }

      bool validOrder = false;
      if(g_currentOrderType == ORDER_TYPE_BUY)
         validOrder = (limitPrice <= (currentAsk + epsilon));
      else
         validOrder = (limitPrice >= (currentBid - epsilon));

      if(!validOrder)
      {
         LogNegativeAddDebug(56,
                             "strict addon invalid step=" + IntegerToString(step) +
                             " | limit=" + DoubleToString(limitPrice, 2));
         continue;
      }

      string comment = "AddOn Negativo #" + IntegerToString(step);
      bool result = false;
      if(g_currentOrderType == ORDER_TYPE_BUY)
         result = trade.BuyLimit(addLot, limitPrice, _Symbol, stopLoss, takeProfit, ORDER_TIME_DAY, 0, comment);
      else
         result = trade.SellLimit(addLot, limitPrice, _Symbol, stopLoss, takeProfit, ORDER_TIME_DAY, 0, comment);

      long retcode = trade.ResultRetcode();
      if(result && IsTradeRetcodeAccepted(retcode, true) && trade.ResultOrder() > 0)
      {
         ulong orderTicket = trade.ResultOrder();
         TrackNegativeAddPendingOrderTicket(orderTicket);
         placedAny = true;
         LogNegativeAddDebug(57,
                             "strict addon limit placed step=" + IntegerToString(step) +
                             " | ticket=" + StringFormat("%I64u", orderTicket) +
                             " | price=" + DoubleToString(limitPrice, 2),
                             true);
      }
      else
      {
         LogNegativeAddDebug(58,
                             "strict addon limit failed step=" + IntegerToString(step) +
                             " | retcode=" + IntegerToString((int)retcode) +
                             " | " + trade.ResultRetcodeDescription(),
                             true);
      }
   }

   g_negativeAddPendingOrdersPlaced = true;
   return placedAny;
}

bool ProcessStrictNegativeAddOnLimitOrders()
{
   int total = ArraySize(g_negativeAddPendingOrderTickets);
   if(total <= 0)
      return false;

   bool hadNewExecution = false;
   datetime nowTime = TimeCurrent();
   datetime historyFrom = (g_tradeEntryTime > 0) ? (g_tradeEntryTime - 24 * 60 * 60) : 0;
   if(!HistorySelect(historyFrom, nowTime))
      return false;

   for(int i = 0; i < total; i++)
   {
      if(g_negativeAddPendingOrderHandled[i])
         continue;

      ulong orderTicket = g_negativeAddPendingOrderTickets[i];
      if(orderTicket == 0)
      {
         g_negativeAddPendingOrderHandled[i] = true;
         continue;
      }

      if(OrderSelect(orderTicket))
         continue;

      bool processed = false;
      bool wasExecuted = false;
      double executedVolume = 0.0;
      double weightedExecutedPrice = 0.0;
      ulong positionId = 0;

      if(HistoryOrderSelect(orderTicket))
      {
         processed = true;
         long state = HistoryOrderGetInteger(orderTicket, ORDER_STATE);
         if(state == ORDER_STATE_FILLED || state == ORDER_STATE_PARTIAL)
         {
            int dealsTotal = HistoryDealsTotal();
            for(int d = 0; d < dealsTotal; d++)
            {
               ulong dealTicket = HistoryDealGetTicket(d);
               if(dealTicket == 0)
                  continue;

               ulong dealOrder = (ulong)HistoryDealGetInteger(dealTicket, DEAL_ORDER);
               long dealEntry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
               if(dealOrder != orderTicket || dealEntry != DEAL_ENTRY_IN)
                  continue;

               double dealVolume = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);
               double dealPrice = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
               executedVolume += dealVolume;
               weightedExecutedPrice += (dealPrice * dealVolume);
               if(positionId == 0)
               {
                  long dealPos = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
                  if(dealPos > 0)
                     positionId = (ulong)dealPos;
               }
            }

            if(executedVolume <= 0.0)
            {
               executedVolume = HistoryOrderGetDouble(orderTicket, ORDER_VOLUME_INITIAL);
               double fallbackPrice = HistoryOrderGetDouble(orderTicket, ORDER_PRICE_OPEN);
               if(fallbackPrice > 0.0 && executedVolume > 0.0)
                  weightedExecutedPrice = fallbackPrice * executedVolume;
            }

            if(executedVolume > 0.0)
               wasExecuted = true;
         }
      }

      if(processed)
      {
         g_negativeAddPendingOrderHandled[i] = true;

         if(wasExecuted)
         {
            g_negativeAddEntriesExecuted++;
            g_negativeAddExecutedLots += executedVolume;
            g_negativeAddExecutedWeightedEntryPrice += weightedExecutedPrice;
            if(positionId > 0)
            {
               TrackNegativeAddExecutedTicket(positionId);
               if(positionId != g_currentTicket)
                  TrackCurrentTradePositionTicket(positionId);
            }

            hadNewExecution = true;
            LogNegativeAddDebug(59,
                                "strict addon executed | order=" + StringFormat("%I64u", orderTicket) +
                                " | volume=" + DoubleToString(executedVolume, 2),
                                true);
         }
         else
         {
            LogNegativeAddDebug(60,
                                "strict addon not executed | order=" + StringFormat("%I64u", orderTicket),
                                true);
         }
      }
   }

   return hadNewExecution;
}

bool TryAdjustTakeProfitAfterAddonExecution(double fallbackEntryPrice)
{
   if(!g_negativeAddTPAdjustRuntimeEnabled)
      return false;

   if(g_tradeReversal && !NegativeAddTPAdjustOnReversal)
   {
      LogNegativeAddDebug(47, "tp adjust skipped: reversal trade and flag disabled");
      return false;
   }

   ulong refreshedTickets[];
   double refreshedVolume = 0.0;
   double refreshedWeightedEntry = 0.0;
   double refreshedFloating = 0.0;
   int refreshedCount = CollectActiveCurrentTradePositions(refreshedTickets,
                                                           refreshedVolume,
                                                           refreshedWeightedEntry,
                                                           refreshedFloating);
   if(refreshedCount > 0)
      TrackCurrentTradePositionTickets(refreshedTickets);

   double tpReferenceEntry = refreshedWeightedEntry;
   if(tpReferenceEntry <= 0.0)
      tpReferenceEntry = fallbackEntryPrice;
   if(tpReferenceEntry <= 0.0)
      tpReferenceEntry = g_tradeEntryPrice;

   double adjustedTakeProfit = CalculateTakeProfitByStopDistancePercent(g_currentOrderType,
                                                                        tpReferenceEntry,
                                                                        g_firstTradeStopLoss,
                                                                        NegativeAddTPDistancePercent);
   if(adjustedTakeProfit <= 0.0)
   {
      LogNegativeAddDebug(46,
                          "tp adjust skipped: invalid adjusted TP | entry_avg=" + DoubleToString(tpReferenceEntry, 2) +
                          " sl=" + DoubleToString(g_firstTradeStopLoss, 2) +
                          " distance=" + DoubleToString(NegativeAddTPDistancePercent, 2) + "%",
                          true);
      return false;
   }

   int modifiedPositions = 0;
   bool modified = ApplySLTPToCurrentTradePositions(g_firstTradeStopLoss,
                                                    adjustedTakeProfit,
                                                    modifiedPositions,
                                                    "adjust tp after addon");
   if(modified)
   {
      int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      double oldTakeProfit = g_firstTradeTakeProfit;
      g_firstTradeTakeProfit = adjustedTakeProfit;
      if(g_tradePCM && tpReferenceEntry > 0.0)
      {
         double oldTpDistance = MathAbs(oldTakeProfit - tpReferenceEntry);
         double newTpDistance = MathAbs(g_firstTradeTakeProfit - tpReferenceEntry);
         if(oldTpDistance > 0.0 && newTpDistance > 0.0)
         {
            double favorableDistanceAbs = (g_tradeMaxFavorableToTPPercent / 100.0) * oldTpDistance;
            double remappedFavorablePercent = (favorableDistanceAbs / newTpDistance) * 100.0;
            if(remappedFavorablePercent < 0.0)
               remappedFavorablePercent = 0.0;
            g_tradeMaxFavorableToTPPercent = remappedFavorablePercent;
         }
      }

      Print("INFO: TP ajustado apos addon | TP antigo=", DoubleToString(oldTakeProfit, digits),
            " | TP novo=", DoubleToString(g_firstTradeTakeProfit, digits),
            " | entrada media=", DoubleToString(tpReferenceEntry, digits),
            " | distancia=", DoubleToString(NegativeAddTPDistancePercent, 2), "%",
            " | posicoes=", IntegerToString(modifiedPositions));
      LogNegativeAddDebug(31,
                          "tp adjusted after addon | old_tp=" + DoubleToString(oldTakeProfit, digits) +
                          " new_tp=" + DoubleToString(g_firstTradeTakeProfit, digits) +
                          " entry_avg=" + DoubleToString(tpReferenceEntry, digits) +
                          " distance=" + DoubleToString(NegativeAddTPDistancePercent, 2) +
                          "% positions=" + IntegerToString(modifiedPositions),
                          true);
      return true;
   }
   else
   {
      LogNegativeAddDebug(45,
                          "tp adjust after addon failed | entry_avg=" + DoubleToString(tpReferenceEntry, 2) +
                          " sl=" + DoubleToString(g_firstTradeStopLoss, 2) +
                          " distance=" + DoubleToString(NegativeAddTPDistancePercent, 2) + "%",
                          true);
      return false;
   }
}

bool TryExecuteNegativeAddOnStrictLimit()
{
   if(!g_negativeAddRuntimeEnabled)
   {
      string details = "runtime disabled";
      if(g_negativeAddRuntimeDisableReason != "")
         details += " | reason=" + g_negativeAddRuntimeDisableReason;
      LogNegativeAddDebug(1, details);
      return false;
   }

   if(g_currentTicket == 0 || g_pendingOrderPlaced)
   {
      LogNegativeAddDebug(2,
                          "ticket=" + StringFormat("%I64u", g_currentTicket) +
                          " pending=" + (g_pendingOrderPlaced ? "true" : "false"));
      return false;
   }

   if(g_currentOrderType != ORDER_TYPE_BUY && g_currentOrderType != ORDER_TYPE_SELL)
   {
      LogNegativeAddDebug(4, "order type not supported: " + EnumToString(g_currentOrderType));
      return false;
   }

   if(g_negativeAddEntriesExecuted >= NegativeAddMaxEntries)
   {
      LogNegativeAddDebug(3,
                          "max entries reached: executed=" + IntegerToString(g_negativeAddEntriesExecuted) +
                          " max=" + IntegerToString(NegativeAddMaxEntries));
      return false;
   }

   ulong activeTickets[];
   double totalVolume = 0.0;
   double weightedEntryPrice = 0.0;
   double totalFloatingProfit = 0.0;
   int activeCount = CollectActiveCurrentTradePositions(activeTickets, totalVolume, weightedEntryPrice, totalFloatingProfit);
   if(activeCount <= 0)
   {
      LogNegativeAddDebug(7,
                          "no active positions for current trade | ticket=" + StringFormat("%I64u", g_currentTicket));
      return false;
   }
   TrackCurrentTradePositionTickets(activeTickets);
   if(g_currentTicket != activeTickets[0])
      g_currentTicket = activeTickets[0];

   double referenceEntryPrice = g_tradeEntryPrice;
   if(referenceEntryPrice <= 0.0)
      referenceEntryPrice = weightedEntryPrice;
   if(referenceEntryPrice <= 0.0)
      return false;

   if(!g_negativeAddPendingOrdersPlaced)
      PlaceNegativeAddOnLimitOrdersForStrictMode(referenceEntryPrice);

   bool hadNewExecution = ProcessStrictNegativeAddOnLimitOrders();
   if(hadNewExecution)
   {
      bool tpAdjusted = TryAdjustTakeProfitAfterAddonExecution(weightedEntryPrice);
      if(!tpAdjusted && !NegativeAddUseSameSLTP && (g_firstTradeStopLoss > 0.0 || g_firstTradeTakeProfit > 0.0))
      {
         int modifiedCount = 0;
         bool modified = ApplySLTPToCurrentTradePositions(g_firstTradeStopLoss,
                                                          g_firstTradeTakeProfit,
                                                          modifiedCount,
                                                          "sync sltp after strict addon");
         if(!modified)
         {
            LogNegativeAddDebug(41,
                                "position modify after strict addon failed",
                                true);
         }
      }
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Tenta executar adicao de posicao em flutuacao negativa          |
//+------------------------------------------------------------------+
bool TryExecuteNegativeAddOn()
{
   if(ShouldUseLimitForNegativeAddOn())
      return TryExecuteNegativeAddOnStrictLimit();

   if(!g_negativeAddRuntimeEnabled)
   {
      string details = "runtime disabled";
      if(g_negativeAddRuntimeDisableReason != "")
         details += " | reason=" + g_negativeAddRuntimeDisableReason;
      LogNegativeAddDebug(1, details);
      return false;
   }
   if(g_currentTicket == 0 || g_pendingOrderPlaced)
   {
      LogNegativeAddDebug(2,
                          "ticket=" + StringFormat("%I64u", g_currentTicket) +
                          " pending=" + (g_pendingOrderPlaced ? "true" : "false"));
      return false;
   }
   if(g_negativeAddEntriesExecuted >= NegativeAddMaxEntries)
   {
      LogNegativeAddDebug(3,
                          "max entries reached: executed=" + IntegerToString(g_negativeAddEntriesExecuted) +
                          " max=" + IntegerToString(NegativeAddMaxEntries));
      return false;
   }
   if(g_currentOrderType != ORDER_TYPE_BUY && g_currentOrderType != ORDER_TYPE_SELL)
   {
      LogNegativeAddDebug(4, "order type not supported: " + EnumToString(g_currentOrderType));
      return false;
   }

   ulong activeTickets[];
   double totalVolume = 0.0;
   double weightedEntryPrice = 0.0;
   double totalFloatingProfit = 0.0;
   int activeCount = CollectActiveCurrentTradePositions(activeTickets, totalVolume, weightedEntryPrice, totalFloatingProfit);
   if(activeCount <= 0)
   {
      LogNegativeAddDebug(7,
                          "no active positions for current trade | ticket=" + StringFormat("%I64u", g_currentTicket));
      return false;
   }
   TrackCurrentTradePositionTickets(activeTickets);
   if(g_currentTicket != activeTickets[0])
      g_currentTicket = activeTickets[0];

   MqlDateTime nowStruct;
   TimeToStruct(TimeCurrent(), nowStruct);
   if(nowStruct.hour >= MaxEntryHour)
   {
      LogNegativeAddDebug(5,
                          "blocked by hour limit: hour=" + IntegerToString(nowStruct.hour) +
                          " max=" + IntegerToString(MaxEntryHour));
      return false;
   }
   double baseLot = IsFixedLotAllEntriesEnabled() ? ResolveFixedLotAllEntries() : g_firstTradeLotSize;
   if(g_firstTradeStopLoss <= 0 || baseLot <= 0)
   {
      LogNegativeAddDebug(6,
                          "invalid base data: entry=" + DoubleToString(g_tradeEntryPrice, 2) +
                          " weighted=" + DoubleToString(weightedEntryPrice, 2) +
                          " sl=" + DoubleToString(g_firstTradeStopLoss, 2) +
                          " lot=" + DoubleToString(baseLot, 2));
      return false;
   }

   double triggerStepFraction = NegativeAddTriggerPercent / 100.0;
   if(triggerStepFraction <= 0.0)
   {
      LogNegativeAddDebug(8,
                          "invalid trigger percent: " + DoubleToString(NegativeAddTriggerPercent, 2));
      return false;
   }

   double referenceEntryPrice = g_tradeEntryPrice;
   if(referenceEntryPrice <= 0.0)
      referenceEntryPrice = weightedEntryPrice;
   if(referenceEntryPrice <= 0.0)
   {
      LogNegativeAddDebug(6,
                          "invalid reference entry: trade_entry=" + DoubleToString(g_tradeEntryPrice, 2) +
                          " weighted=" + DoubleToString(weightedEntryPrice, 2));
      return false;
   }

   double riskDistance = MathAbs(referenceEntryPrice - g_firstTradeStopLoss);
   if(riskDistance <= 0.0)
   {
      LogNegativeAddDebug(9,
                          "risk distance <= 0: entry=" + DoubleToString(referenceEntryPrice, 2) +
                          " sl=" + DoubleToString(g_firstTradeStopLoss, 2));
      return false;
   }

   double currentPrice = (g_currentOrderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double adverseDistance = (g_currentOrderType == ORDER_TYPE_BUY) ? (referenceEntryPrice - currentPrice) : (currentPrice - referenceEntryPrice);
   if(adverseDistance <= 0.0)
   {
      LogNegativeAddDebug(10,
                          "position not adverse yet: entry=" + DoubleToString(referenceEntryPrice, 2) +
                          " current=" + DoubleToString(currentPrice, 2));
      return false;
   }

   UpdateDrawdownMetrics();
   if(MaxDailyDrawdownPercent > 0.0 && g_cachedDailyDrawdownPercent >= MaxDailyDrawdownPercent)
   {
      LogNegativeAddDebug(13,
                          "blocked by daily DD limit: current=" + DoubleToString(g_cachedDailyDrawdownPercent, 2) +
                          "% limit=" + DoubleToString(MaxDailyDrawdownPercent, 2) + "%");
      return false;
   }
   if(MaxDrawdownPercent > 0.0 && g_cachedMaxDrawdownPercent >= MaxDrawdownPercent)
   {
      LogNegativeAddDebug(14,
                          "blocked by max DD limit: current=" + DoubleToString(g_cachedMaxDrawdownPercent, 2) +
                          "% limit=" + DoubleToString(MaxDrawdownPercent, 2) + "%");
      return false;
   }
   if(MaxDailyDrawdownAmount > 0.0 && g_cachedDailyDrawdownAmount >= MaxDailyDrawdownAmount)
   {
      LogNegativeAddDebug(48,
                          "blocked by daily DD abs limit: current=" + DoubleToString(g_cachedDailyDrawdownAmount, 2) +
                          " limit=" + DoubleToString(MaxDailyDrawdownAmount, 2));
      return false;
   }
   if(MaxDrawdownAmount > 0.0 && g_cachedMaxDrawdownAmount >= MaxDrawdownAmount)
   {
      LogNegativeAddDebug(49,
                          "blocked by max DD abs limit: current=" + DoubleToString(g_cachedMaxDrawdownAmount, 2) +
                          " limit=" + DoubleToString(MaxDrawdownAmount, 2));
      return false;
   }

   double requiredFraction = triggerStepFraction * (g_negativeAddEntriesExecuted + 1);
   double adverseFraction = adverseDistance / riskDistance;
   if(adverseFraction < requiredFraction)
   {
      LogNegativeAddDebug(11,
                          "waiting trigger: adverse=" + DoubleToString(adverseFraction * 100.0, 2) +
                          "% required=" + DoubleToString(requiredFraction * 100.0, 2) +
                          "% step=" + DoubleToString(triggerStepFraction * 100.0, 2) + "%" +
                          " positions=" + IntegerToString(activeCount) +
                          " volume=" + DoubleToString(totalVolume, 2));
      return false;
   }

   double addLot = 0.0;
   if(IsFixedLotAllEntriesEnabled())
      addLot = ResolveFixedLotAllEntries();
   else
      addLot = NormalizeLot(baseLot * NegativeAddLotMultiplier);
   if(addLot <= 0.0)
   {
      string lotDebug = "invalid add lot: base=" + DoubleToString(baseLot, 2);
      if(IsFixedLotAllEntriesEnabled())
         lotDebug += " fixed=" + DoubleToString(FixedLotAllEntries, 2);
      else
         lotDebug += " mult=" + DoubleToString(NegativeAddLotMultiplier, 2);
      lotDebug += " norm=" + DoubleToString(addLot, 2);
      LogNegativeAddDebug(12, lotDebug);
      return false;
   }

   double stopLoss = 0.0;
   double takeProfit = 0.0;
   if(NegativeAddUseSameSLTP)
   {
      stopLoss = g_firstTradeStopLoss;
      takeProfit = g_firstTradeTakeProfit;
   }

   string comment = "AddOn Negativo #" + IntegerToString(g_negativeAddEntriesExecuted + 1);
   LogNegativeAddDebug(20,
                       "trigger reached: sending add order type=" + EnumToString(g_currentOrderType) +
                       " lot=" + DoubleToString(addLot, 2) +
                       " adverse=" + DoubleToString(adverseFraction * 100.0, 2) +
                       "% required=" + DoubleToString(requiredFraction * 100.0, 2) + "%" +
                       " positions=" + IntegerToString(activeCount),
                       true);
   bool result = false;
   if(g_currentOrderType == ORDER_TYPE_BUY)
      result = trade.Buy(addLot, _Symbol, 0, stopLoss, takeProfit, comment);
   else
      result = trade.Sell(addLot, _Symbol, 0, stopLoss, takeProfit, comment);

   long retcode = trade.ResultRetcode();
   if(result && (retcode == TRADE_RETCODE_DONE || retcode == TRADE_RETCODE_DONE_PARTIAL))
   {
      g_negativeAddEntriesExecuted++;
      g_negativeAddExecutedLots += addLot;

      double executedPrice = trade.ResultPrice();
      if(executedPrice <= 0.0)
         executedPrice = currentPrice;
      g_negativeAddExecutedWeightedEntryPrice += (executedPrice * addLot);

      // Em hedging, tenta rastrear o position ID do addon executado.
      ulong addOnPositionId = 0;
      ulong addOnDeal = trade.ResultDeal();
      if(addOnDeal > 0 && HistoryDealSelect(addOnDeal))
      {
         long dealPositionId = HistoryDealGetInteger(addOnDeal, DEAL_POSITION_ID);
         if(dealPositionId > 0)
            addOnPositionId = (ulong)dealPositionId;
      }
      if(addOnPositionId == 0)
      {
         ulong addOnOrder = trade.ResultOrder();
         if(addOnOrder > 0)
            addOnPositionId = addOnOrder;
      }
      if(addOnPositionId > 0)
      {
         TrackNegativeAddExecutedTicket(addOnPositionId);
         if(addOnPositionId != g_currentTicket)
            TrackCurrentTradePositionTicket(addOnPositionId);
      }

      // Tenta rastrear imediatamente o novo ticket addon em contas hedging.
      ulong refreshedTickets[];
      double refreshedVolume = 0.0;
      double refreshedWeightedEntry = 0.0;
      double refreshedFloating = 0.0;
      int refreshedCount = CollectActiveCurrentTradePositions(refreshedTickets, refreshedVolume, refreshedWeightedEntry, refreshedFloating);
      if(refreshedCount > 0)
         TrackCurrentTradePositionTickets(refreshedTickets);

      bool tpAdjustedAfterAdd = false;
      if(g_negativeAddTPAdjustRuntimeEnabled)
      {
         if(g_tradeReversal && !NegativeAddTPAdjustOnReversal)
         {
            LogNegativeAddDebug(47,
                                "tp adjust skipped: reversal trade and flag disabled");
         }
         else
         {
            double tpReferenceEntry = refreshedWeightedEntry;
            if(tpReferenceEntry <= 0.0)
               tpReferenceEntry = weightedEntryPrice;
            if(tpReferenceEntry <= 0.0)
               tpReferenceEntry = executedPrice;

            double adjustedTakeProfit = CalculateTakeProfitByStopDistancePercent(g_currentOrderType,
                                                                                 tpReferenceEntry,
                                                                                 g_firstTradeStopLoss,
                                                                                 NegativeAddTPDistancePercent);
            if(adjustedTakeProfit > 0.0)
            {
               int modifiedPositions = 0;
               bool modified = ApplySLTPToCurrentTradePositions(g_firstTradeStopLoss,
                                                                adjustedTakeProfit,
                                                                modifiedPositions,
                                                                "adjust tp after addon");
               if(modified)
               {
                  int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
                  double oldTakeProfit = g_firstTradeTakeProfit;
                  g_firstTradeTakeProfit = adjustedTakeProfit;
                  if(g_tradePCM && tpReferenceEntry > 0.0)
                  {
                     double oldTpDistance = MathAbs(oldTakeProfit - tpReferenceEntry);
                     double newTpDistance = MathAbs(g_firstTradeTakeProfit - tpReferenceEntry);
                     if(oldTpDistance > 0.0 && newTpDistance > 0.0)
                     {
                        double favorableDistanceAbs = (g_tradeMaxFavorableToTPPercent / 100.0) * oldTpDistance;
                        double remappedFavorablePercent = (favorableDistanceAbs / newTpDistance) * 100.0;
                        if(remappedFavorablePercent < 0.0)
                           remappedFavorablePercent = 0.0;
                        g_tradeMaxFavorableToTPPercent = remappedFavorablePercent;
                     }
                  }
                  tpAdjustedAfterAdd = true;

                  Print("INFO: TP ajustado apos addon | TP antigo=", DoubleToString(oldTakeProfit, digits),
                        " | TP novo=", DoubleToString(g_firstTradeTakeProfit, digits),
                        " | entrada media=", DoubleToString(tpReferenceEntry, digits),
                        " | distancia=", DoubleToString(NegativeAddTPDistancePercent, 2), "%",
                        " | posicoes=", IntegerToString(modifiedPositions));
                  LogNegativeAddDebug(31,
                                      "tp adjusted after addon | old_tp=" + DoubleToString(oldTakeProfit, digits) +
                                      " new_tp=" + DoubleToString(g_firstTradeTakeProfit, digits) +
                                      " entry_avg=" + DoubleToString(tpReferenceEntry, digits) +
                                      " distance=" + DoubleToString(NegativeAddTPDistancePercent, 2) +
                                      "% positions=" + IntegerToString(modifiedPositions),
                                      true);
               }
               else
               {
                  LogNegativeAddDebug(45,
                                      "tp adjust after addon failed | entry_avg=" + DoubleToString(tpReferenceEntry, 2) +
                                      " sl=" + DoubleToString(g_firstTradeStopLoss, 2) +
                                      " distance=" + DoubleToString(NegativeAddTPDistancePercent, 2) + "%",
                                      true);
               }
            }
            else
            {
               LogNegativeAddDebug(46,
                                   "tp adjust skipped: invalid adjusted TP | entry_avg=" + DoubleToString(tpReferenceEntry, 2) +
                                   " sl=" + DoubleToString(g_firstTradeStopLoss, 2) +
                                   " distance=" + DoubleToString(NegativeAddTPDistancePercent, 2) + "%",
                                   true);
            }
         }
      }

      // Quando nao houver ajuste de TP, mantem o comportamento anterior de preservar SL/TP base.
      if(!tpAdjustedAfterAdd && !NegativeAddUseSameSLTP && (g_firstTradeStopLoss > 0 || g_firstTradeTakeProfit > 0))
      {
         bool modified = trade.PositionModify(_Symbol, g_firstTradeStopLoss, g_firstTradeTakeProfit);
         if(!modified)
         {
            LogNegativeAddDebug(41,
                                "position modify after add failed | retcode=" + IntegerToString((int)trade.ResultRetcode()) +
                                " | " + trade.ResultRetcodeDescription(),
                                true);
         }
      }

      Print("INFO: Adicao negativa executada. #", g_negativeAddEntriesExecuted,
            " | lote=", DoubleToString(addLot, 2),
            " | adverse=", DoubleToString(adverseFraction * 100.0, 2), "%");
      LogNegativeAddDebug(30,
                          "add executed with success: count=" + IntegerToString(g_negativeAddEntriesExecuted),
                          true);
      return true;
   }

   LogNegativeAddDebug(40,
                       "send failed | retcode=" + IntegerToString((int)retcode) +
                       " | " + trade.ResultRetcodeDescription(),
                       true);
   Print("WARN: Falha ao executar adicao negativa | retcode=", retcode, " | ", trade.ResultRetcodeDescription());
   return false;
}

//+------------------------------------------------------------------+
//| Atualiza metricas de flutuacao de snapshot overnight            |
//+------------------------------------------------------------------+
void UpdateOvernightFloatingMetricsByIndex(int index, ulong ticket)
{
   int total = ArraySize(g_overnightLogTickets);
   if(index < 0 || index >= total || ticket == 0)
      return;

   if(!PositionSelectByTicket(ticket))
      return;

   double volume = PositionGetDouble(POSITION_VOLUME);
   double floatingProfit = 0;
   if(!CalculateFloatingProfit(g_overnightLogOrderTypes[index], g_overnightLogEntryPrices[index], volume, floatingProfit))
      return;

   if(floatingProfit > g_overnightLogMaxFloatingProfits[index])
      g_overnightLogMaxFloatingProfits[index] = floatingProfit;
   if(floatingProfit < g_overnightLogMaxFloatingDrawdowns[index])
      g_overnightLogMaxFloatingDrawdowns[index] = floatingProfit;

   double adverseToSLPercent = CalculateAdverseToSLPercent(g_overnightLogOrderTypes[index],
                                                           g_overnightLogEntryPrices[index],
                                                           g_overnightLogStopLosses[index]);
   if(adverseToSLPercent > g_overnightLogMaxAdverseToSLPercents[index])
      g_overnightLogMaxAdverseToSLPercents[index] = adverseToSLPercent;

   double favorableToTPPercent = CalculateFavorableToTPPercent(g_overnightLogOrderTypes[index],
                                                               g_overnightLogEntryPrices[index],
                                                               g_overnightLogTakeProfits[index]);
   if(favorableToTPPercent > g_overnightLogMaxFavorableToTPPercents[index])
      g_overnightLogMaxFavorableToTPPercents[index] = favorableToTPPercent;

   if(g_overnightTicket == ticket)
   {
      g_overnightMaxFloatingProfit = g_overnightLogMaxFloatingProfits[index];
      g_overnightMaxFloatingDrawdown = g_overnightLogMaxFloatingDrawdowns[index];
      g_overnightMaxAdverseToSLPercent = g_overnightLogMaxAdverseToSLPercents[index];
      g_overnightMaxFavorableToTPPercent = g_overnightLogMaxFavorableToTPPercents[index];
   }
}

//+------------------------------------------------------------------+
//| Adiciona/atualiza snapshot overnight para logging                 |
//+------------------------------------------------------------------+
void AddOvernightLogSnapshot(ulong ticket,
                             datetime entryTime,
                             double entryPrice,
                             double stopLoss,
                             double takeProfit,
                             bool isSliced,
                             bool isReversal,
                             bool isPCM,
                             ENUM_ORDER_TYPE orderType,
                             datetime channelDefinitionTime,
                             string entryExecutionType,
                             datetime triggerTime,
                             double maxFloatingProfit,
                             double maxFloatingDrawdown,
                             double maxAdverseToSLPercent,
                             double maxFavorableToTPPercent,
                             double channelRange,
                             double lotSize,
                             int operationChainId)
{
   if(ticket == 0)
      return;

   int total = ArraySize(g_overnightLogTickets);
   for(int i = 0; i < total; i++)
   {
      if(g_overnightLogTickets[i] == ticket)
      {
         g_overnightLogEntryTimes[i] = entryTime;
         g_overnightLogEntryPrices[i] = entryPrice;
         g_overnightLogStopLosses[i] = stopLoss;
         g_overnightLogTakeProfits[i] = takeProfit;
         g_overnightLogSliceds[i] = isSliced;
         g_overnightLogReversals[i] = isReversal;
         g_overnightLogPCMs[i] = isPCM;
         g_overnightLogOrderTypes[i] = orderType;
         g_overnightLogChannelDefinitionTimes[i] = channelDefinitionTime;
         g_overnightLogEntryExecutionTypes[i] = entryExecutionType;
         g_overnightLogTriggerTimes[i] = triggerTime;
         g_overnightLogMaxFloatingProfits[i] = MathMax(g_overnightLogMaxFloatingProfits[i], maxFloatingProfit);
         g_overnightLogMaxFloatingDrawdowns[i] = MathMin(g_overnightLogMaxFloatingDrawdowns[i], maxFloatingDrawdown);
         g_overnightLogMaxAdverseToSLPercents[i] = MathMax(g_overnightLogMaxAdverseToSLPercents[i], maxAdverseToSLPercent);
         g_overnightLogMaxFavorableToTPPercents[i] = MathMax(g_overnightLogMaxFavorableToTPPercents[i], maxFavorableToTPPercent);
         g_overnightLogChannelRanges[i] = channelRange;
         g_overnightLogLotSizes[i] = lotSize;
         g_overnightLogChainIds[i] = operationChainId;
         return;
      }
   }

   int newSize = total + 1;
   ArrayResize(g_overnightLogTickets, newSize);
   ArrayResize(g_overnightLogEntryTimes, newSize);
   ArrayResize(g_overnightLogEntryPrices, newSize);
   ArrayResize(g_overnightLogStopLosses, newSize);
   ArrayResize(g_overnightLogTakeProfits, newSize);
   ArrayResize(g_overnightLogSliceds, newSize);
   ArrayResize(g_overnightLogReversals, newSize);
   ArrayResize(g_overnightLogPCMs, newSize);
   ArrayResize(g_overnightLogOrderTypes, newSize);
   ArrayResize(g_overnightLogChannelDefinitionTimes, newSize);
   ArrayResize(g_overnightLogEntryExecutionTypes, newSize);
   ArrayResize(g_overnightLogTriggerTimes, newSize);
   ArrayResize(g_overnightLogMaxFloatingProfits, newSize);
   ArrayResize(g_overnightLogMaxFloatingDrawdowns, newSize);
   ArrayResize(g_overnightLogMaxAdverseToSLPercents, newSize);
   ArrayResize(g_overnightLogMaxFavorableToTPPercents, newSize);
   ArrayResize(g_overnightLogChannelRanges, newSize);
   ArrayResize(g_overnightLogLotSizes, newSize);
   ArrayResize(g_overnightLogChainIds, newSize);

   g_overnightLogTickets[total] = ticket;
   g_overnightLogEntryTimes[total] = entryTime;
   g_overnightLogEntryPrices[total] = entryPrice;
   g_overnightLogStopLosses[total] = stopLoss;
   g_overnightLogTakeProfits[total] = takeProfit;
   g_overnightLogSliceds[total] = isSliced;
   g_overnightLogReversals[total] = isReversal;
   g_overnightLogPCMs[total] = isPCM;
   g_overnightLogOrderTypes[total] = orderType;
   g_overnightLogChannelDefinitionTimes[total] = channelDefinitionTime;
   g_overnightLogEntryExecutionTypes[total] = entryExecutionType;
   g_overnightLogTriggerTimes[total] = triggerTime;
   g_overnightLogMaxFloatingProfits[total] = maxFloatingProfit;
   g_overnightLogMaxFloatingDrawdowns[total] = maxFloatingDrawdown;
   g_overnightLogMaxAdverseToSLPercents[total] = maxAdverseToSLPercent;
   g_overnightLogMaxFavorableToTPPercents[total] = maxFavorableToTPPercent;
   g_overnightLogChannelRanges[total] = channelRange;
   g_overnightLogLotSizes[total] = lotSize;
   g_overnightLogChainIds[total] = operationChainId;
}

//+------------------------------------------------------------------+
//| Remove snapshot overnight por indice                              |
//+------------------------------------------------------------------+
void RemoveOvernightLogSnapshotByIndex(int index)
{
   int total = ArraySize(g_overnightLogTickets);
   if(index < 0 || index >= total)
      return;

   for(int i = index; i < total - 1; i++)
   {
      g_overnightLogTickets[i] = g_overnightLogTickets[i + 1];
      g_overnightLogEntryTimes[i] = g_overnightLogEntryTimes[i + 1];
      g_overnightLogEntryPrices[i] = g_overnightLogEntryPrices[i + 1];
      g_overnightLogStopLosses[i] = g_overnightLogStopLosses[i + 1];
      g_overnightLogTakeProfits[i] = g_overnightLogTakeProfits[i + 1];
      g_overnightLogSliceds[i] = g_overnightLogSliceds[i + 1];
      g_overnightLogReversals[i] = g_overnightLogReversals[i + 1];
      g_overnightLogPCMs[i] = g_overnightLogPCMs[i + 1];
      g_overnightLogOrderTypes[i] = g_overnightLogOrderTypes[i + 1];
      g_overnightLogChannelDefinitionTimes[i] = g_overnightLogChannelDefinitionTimes[i + 1];
      g_overnightLogEntryExecutionTypes[i] = g_overnightLogEntryExecutionTypes[i + 1];
      g_overnightLogTriggerTimes[i] = g_overnightLogTriggerTimes[i + 1];
      g_overnightLogMaxFloatingProfits[i] = g_overnightLogMaxFloatingProfits[i + 1];
      g_overnightLogMaxFloatingDrawdowns[i] = g_overnightLogMaxFloatingDrawdowns[i + 1];
      g_overnightLogMaxAdverseToSLPercents[i] = g_overnightLogMaxAdverseToSLPercents[i + 1];
      g_overnightLogMaxFavorableToTPPercents[i] = g_overnightLogMaxFavorableToTPPercents[i + 1];
      g_overnightLogChannelRanges[i] = g_overnightLogChannelRanges[i + 1];
      g_overnightLogLotSizes[i] = g_overnightLogLotSizes[i + 1];
      g_overnightLogChainIds[i] = g_overnightLogChainIds[i + 1];
   }

   int newSize = total - 1;
   ArrayResize(g_overnightLogTickets, newSize);
   ArrayResize(g_overnightLogEntryTimes, newSize);
   ArrayResize(g_overnightLogEntryPrices, newSize);
   ArrayResize(g_overnightLogStopLosses, newSize);
   ArrayResize(g_overnightLogTakeProfits, newSize);
   ArrayResize(g_overnightLogSliceds, newSize);
   ArrayResize(g_overnightLogReversals, newSize);
   ArrayResize(g_overnightLogPCMs, newSize);
   ArrayResize(g_overnightLogOrderTypes, newSize);
   ArrayResize(g_overnightLogChannelDefinitionTimes, newSize);
   ArrayResize(g_overnightLogEntryExecutionTypes, newSize);
   ArrayResize(g_overnightLogTriggerTimes, newSize);
   ArrayResize(g_overnightLogMaxFloatingProfits, newSize);
   ArrayResize(g_overnightLogMaxFloatingDrawdowns, newSize);
   ArrayResize(g_overnightLogMaxAdverseToSLPercents, newSize);
   ArrayResize(g_overnightLogMaxFavorableToTPPercents, newSize);
   ArrayResize(g_overnightLogChannelRanges, newSize);
   ArrayResize(g_overnightLogLotSizes, newSize);
   ArrayResize(g_overnightLogChainIds, newSize);
}

//+------------------------------------------------------------------+
//| Limpa snapshots overnight                                         |
//+------------------------------------------------------------------+
void ClearOvernightLogSnapshots()
{
   ArrayResize(g_overnightLogTickets, 0);
   ArrayResize(g_overnightLogEntryTimes, 0);
   ArrayResize(g_overnightLogEntryPrices, 0);
   ArrayResize(g_overnightLogStopLosses, 0);
   ArrayResize(g_overnightLogTakeProfits, 0);
   ArrayResize(g_overnightLogSliceds, 0);
   ArrayResize(g_overnightLogReversals, 0);
   ArrayResize(g_overnightLogPCMs, 0);
   ArrayResize(g_overnightLogOrderTypes, 0);
   ArrayResize(g_overnightLogChannelDefinitionTimes, 0);
   ArrayResize(g_overnightLogEntryExecutionTypes, 0);
   ArrayResize(g_overnightLogTriggerTimes, 0);
   ArrayResize(g_overnightLogMaxFloatingProfits, 0);
   ArrayResize(g_overnightLogMaxFloatingDrawdowns, 0);
   ArrayResize(g_overnightLogMaxAdverseToSLPercents, 0);
   ArrayResize(g_overnightLogMaxFavorableToTPPercents, 0);
   ArrayResize(g_overnightLogChannelRanges, 0);
   ArrayResize(g_overnightLogLotSizes, 0);
   ArrayResize(g_overnightLogChainIds, 0);
}

//+------------------------------------------------------------------+
//| Obtem horario de fechamento da ultima sessao de hoje             |
//+------------------------------------------------------------------+
bool GetTodayLastSessionClose(datetime &sessionClose)
{
   MqlDateTime nowStruct;
   TimeToStruct(TimeCurrent(), nowStruct);
   ENUM_DAY_OF_WEEK dayOfWeek = (ENUM_DAY_OF_WEEK)nowStruct.day_of_week;

   bool foundSession = false;
   datetime latestClose = 0;
   datetime sessionFrom, sessionTo;

   for(uint i = 0; i < 12; i++)
   {
      if(!SymbolInfoSessionTrade(_Symbol, dayOfWeek, i, sessionFrom, sessionTo))
         break;

      MqlDateTime fromStruct, toStruct;
      TimeToStruct(sessionFrom, fromStruct);
      TimeToStruct(sessionTo, toStruct);

      MqlDateTime openStruct = nowStruct;
      openStruct.hour = fromStruct.hour;
      openStruct.min = fromStruct.min;
      openStruct.sec = fromStruct.sec;

      MqlDateTime closeStruct = nowStruct;
      closeStruct.hour = toStruct.hour;
      closeStruct.min = toStruct.min;
      closeStruct.sec = toStruct.sec;

      datetime openTime = StructToTime(openStruct);
      datetime closeTime = StructToTime(closeStruct);
      if(closeTime <= openTime)
         closeTime += 24 * 60 * 60;

      if(!foundSession || closeTime > latestClose)
      {
         latestClose = closeTime;
         foundSession = true;
      }
   }

   if(!foundSession)
      return false;

   sessionClose = latestClose;
   return true;
}

//+------------------------------------------------------------------+
//| Compara se dois datetimes estao no mesmo dia calendario          |
//+------------------------------------------------------------------+
bool IsSameCalendarDay(datetime a, datetime b)
{
   MqlDateTime sa, sb;
   TimeToStruct(a, sa);
   TimeToStruct(b, sb);
   return (sa.year == sb.year && sa.mon == sb.mon && sa.day == sb.day);
}

//+------------------------------------------------------------------+
//| Fecha posicao por ticket a mercado                               |
//+------------------------------------------------------------------+
bool ClosePositionByTicketMarket(ulong ticket)
{
   if(ticket == 0)
      return false;

   if(!PositionSelectByTicket(ticket))
      return false;

   bool result = trade.PositionClose(ticket);
   long retcode = trade.ResultRetcode();
   if(result && (retcode == TRADE_RETCODE_DONE || retcode == TRADE_RETCODE_DONE_PARTIAL))
   {
      Print("INFO: Posicao fechada por politica sem overnight. Ticket=", ticket);
      return true;
   }

   Print("WARN: Falha ao fechar ticket ", ticket, " | retcode=", retcode, " | ", trade.ResultRetcodeDescription());
   return false;
}

//+------------------------------------------------------------------+
//| Coleta tickets de ordens pendentes do EA (symbol+magic)         |
//+------------------------------------------------------------------+
int CollectEAPendingOrderTickets(ulong &tickets[])
{
   ArrayResize(tickets, 0);

   int totalOrders = OrdersTotal();
   for(int i = 0; i < totalOrders; i++)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;

      string symbol = OrderGetString(ORDER_SYMBOL);
      ulong magic = (ulong)OrderGetInteger(ORDER_MAGIC);
      if(symbol != _Symbol || magic != MagicNumber)
         continue;

      ENUM_ORDER_TYPE orderType = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(orderType == ORDER_TYPE_BUY || orderType == ORDER_TYPE_SELL)
         continue;

      int n = ArraySize(tickets);
      ArrayResize(tickets, n + 1);
      tickets[n] = ticket;
   }

   return ArraySize(tickets);
}

//+------------------------------------------------------------------+
//| Cancela todas as ordens pendentes do EA (symbol+magic)          |
//+------------------------------------------------------------------+
int CancelAllPendingOrdersForNoOvernight(string reason = "")
{
   ulong pendingTickets[];
   int totalPending = CollectEAPendingOrderTickets(pendingTickets);
   int canceled = 0;

   for(int i = 0; i < totalPending; i++)
   {
      ulong ticket = pendingTickets[i];
      if(ticket == 0 || !OrderSelect(ticket))
         continue;

      bool deleted = trade.OrderDelete(ticket);
      if(deleted)
      {
         canceled++;
         if(reason == "")
            Print("INFO: Ordem pendente cancelada por politica sem overnight. Ticket=", ticket);
         else
            Print("INFO: Ordem pendente cancelada por politica sem overnight (", reason, "). Ticket=", ticket);
      }
      else
      {
         Print("WARN: Falha ao cancelar ordem pendente por politica sem overnight. Ticket=", ticket,
               " | retcode=", trade.ResultRetcode(), " | ", trade.ResultRetcodeDescription());
      }
   }

   return canceled;
}

//+------------------------------------------------------------------+
//| Coleta tickets de posicoes abertas do EA (symbol+magic)         |
//+------------------------------------------------------------------+
int CollectEAOpenPositionTickets(ulong &tickets[])
{
   ArrayResize(tickets, 0);

   int totalPositions = PositionsTotal();
   for(int i = 0; i < totalPositions; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      ulong magic = (ulong)PositionGetInteger(POSITION_MAGIC);
      if(symbol != _Symbol || magic != MagicNumber)
         continue;

      int n = ArraySize(tickets);
      ArrayResize(tickets, n + 1);
      tickets[n] = ticket;
   }

   return ArraySize(tickets);
}

//+------------------------------------------------------------------+
//| Fecha todas as posicoes abertas do EA (symbol+magic)            |
//+------------------------------------------------------------------+
int CloseAllOpenPositionsForNoOvernight()
{
   ulong openTickets[];
   int totalOpen = CollectEAOpenPositionTickets(openTickets);
   int closed = 0;

   for(int i = 0; i < totalOpen; i++)
   {
      if(ClosePositionByTicketMarket(openTickets[i]))
         closed++;
   }

   return closed;
}

//+------------------------------------------------------------------+
//| Politica de fechamento quando overnight estiver desabilitado     |
//+------------------------------------------------------------------+
bool ApplyNoOvernightPolicy()
{
   if(KeepPositionsOvernight)
      return false;

   datetime marketClose = 0;
   bool hasSession = GetTodayLastSessionClose(marketClose);
   int closeMinutes = (CloseMinutesBeforeMarketClose < 0) ? 0 : CloseMinutesBeforeMarketClose;
   datetime triggerTime = marketClose - (closeMinutes * 60);
   datetime nowTime = TimeCurrent();
   bool cutoffReached = hasSession && nowTime >= triggerTime;

   bool hasCurrentOvernight = false;
   if(g_currentTicket > 0 && PositionSelectByTicket(g_currentTicket) && g_tradeEntryTime > 0)
      hasCurrentOvernight = !IsSameCalendarDay(g_tradeEntryTime, nowTime);

   bool hasSnapshotOvernight = false;
   for(int i = 0; i < ArraySize(g_overnightLogTickets); i++)
   {
      ulong ticket = g_overnightLogTickets[i];
      if(ticket > 0 && PositionSelectByTicket(ticket))
      {
         hasSnapshotOvernight = true;
         break;
      }
   }

   bool hasForcedOvernight = hasCurrentOvernight || hasSnapshotOvernight || (g_overnightTicket > 0 && PositionSelectByTicket(g_overnightTicket));
   if(!cutoffReached && !hasForcedOvernight)
      return false;

   if(g_preArmedReversalOrderTicket > 0)
      CancelPreArmedReversalOrder("politica sem overnight");
   CancelNegativeAddPendingOrders("politica sem overnight");

   int canceledPending = CancelAllPendingOrdersForNoOvernight("cutoff sem overnight");
   bool attemptedClose = (canceledPending > 0);

   if(g_pendingOrderPlaced || g_currentTicket > 0)
      ConsumeCycleAfterPendingCancel();
   ClearPendingOrderState(true);
   g_tradeEntryTime = 0;
   g_tradeReversal = false;
   g_tradePCM = false;
   g_tradeChannelDefinitionTime = 0;
   g_tradeEntryExecutionType = "";
   g_tradeTriggerTime = 0;
   g_currentOperationChainId = 0;
   ResetReversalHourBlockState();
   ResetNegativeAddState();
   ResetCurrentTradeFloatingMetrics();

   int closedPositions = CloseAllOpenPositionsForNoOvernight();
   if(closedPositions > 0)
      attemptedClose = true;

   if(cutoffReached || hasForcedOvernight)
      return true;

   return attemptedClose;
}

//+------------------------------------------------------------------+
//| Registra fechamento de posicao overnight                         |
//+------------------------------------------------------------------+
bool LogClosedOvernightTrade(ulong ticket,
                             datetime snapshotEntryTime,
                             double snapshotEntryPrice,
                             double snapshotStopLoss,
                             double snapshotTakeProfit,
                             bool snapshotSliced,
                             bool snapshotReversal,
                             bool snapshotPCM,
                             ENUM_ORDER_TYPE snapshotOrderType,
                             datetime snapshotChannelDefinitionTime,
                             string snapshotEntryExecutionType,
                             datetime snapshotTriggerTime,
                             double snapshotMaxFloatingProfit,
                             double snapshotMaxFloatingDrawdown,
                             double snapshotMaxAdverseToSLPercent,
                             double snapshotMaxFavorableToTPPercent,
                             int snapshotOperationChainId,
                             bool &wasStopLossOut)
{
   wasStopLossOut = false;
   bool shouldLog = EnableLogging;

   datetime entryTime = snapshotEntryTime;
   double entryPrice = snapshotEntryPrice;
   double stopLoss = snapshotStopLoss;
   double takeProfit = snapshotTakeProfit;
   bool isSliced = snapshotSliced;
   bool isReversal = snapshotReversal;
   bool isPCM = snapshotPCM;
   ENUM_ORDER_TYPE orderType = snapshotOrderType;
   datetime channelDefinitionTime = snapshotChannelDefinitionTime;
   string entryExecutionType = snapshotEntryExecutionType;
   datetime triggerTime = snapshotTriggerTime;
   double maxFloatingProfit = snapshotMaxFloatingProfit;
   double maxFloatingDrawdown = snapshotMaxFloatingDrawdown;
   double maxAdverseToSLPercent = snapshotMaxAdverseToSLPercent;
   double maxFavorableToTPPercent = snapshotMaxFavorableToTPPercent;

   datetime exitTime = TimeCurrent();
   double exitPrice = 0;
   double profit = 0;
   double grossProfit = 0.0;
   double swapValue = 0.0;
   double commissionValue = 0.0;
   double feeValue = 0.0;
   bool hasExit = false;
   bool hasReason = false;
   bool wasStopLoss = true;

   if(HistorySelectByPosition(ticket))
   {
      int total = HistoryDealsTotal();
      for(int i = 0; i < total; i++)
      {
         ulong dealTicket = HistoryDealGetTicket(i);
         if(dealTicket == 0)
            continue;

         long dealEntry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
         if(dealEntry == DEAL_ENTRY_IN)
         {
            if(entryTime == 0)
            {
               entryTime = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
               entryPrice = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
            }

            string comment = HistoryDealGetString(dealTicket, DEAL_COMMENT);
            ulong orderTicket = (ulong)HistoryDealGetInteger(dealTicket, DEAL_ORDER);
            string orderComment = "";
            if(orderTicket > 0)
               orderComment = HistoryOrderGetString(orderTicket, ORDER_COMMENT);

            if(orderTicket > 0)
            {
               double orderSL = HistoryOrderGetDouble(orderTicket, ORDER_SL);
               double orderTP = HistoryOrderGetDouble(orderTicket, ORDER_TP);
               if(orderSL > 0.0)
                  stopLoss = orderSL;
               if(orderTP > 0.0)
                  takeProfit = orderTP;

               ENUM_ORDER_TYPE histOrderTypeRaw = (ENUM_ORDER_TYPE)HistoryOrderGetInteger(orderTicket, ORDER_TYPE);
               if(histOrderTypeRaw == ORDER_TYPE_BUY || histOrderTypeRaw == ORDER_TYPE_BUY_LIMIT || histOrderTypeRaw == ORDER_TYPE_BUY_STOP)
                  orderType = ORDER_TYPE_BUY;
               else if(histOrderTypeRaw == ORDER_TYPE_SELL || histOrderTypeRaw == ORDER_TYPE_SELL_LIMIT || histOrderTypeRaw == ORDER_TYPE_SELL_STOP)
                  orderType = ORDER_TYPE_SELL;
            }

            if(StringFind(comment, "Virada") >= 0 || StringFind(comment, "virada") >= 0)
               isReversal = true;
            if(StringFind(comment, "PCM") >= 0 || StringFind(orderComment, "PCM") >= 0)
               isPCM = true;

            if(entryExecutionType == "")
            {
               if(StringFind(comment, "Limite") >= 0 || StringFind(comment, "LIMIT") >= 0 ||
                  StringFind(orderComment, "Limite") >= 0 || StringFind(orderComment, "LIMIT") >= 0)
               {
                  entryExecutionType = "LIMIT";
               }
               else if(orderTicket > 0)
               {
                  ENUM_ORDER_TYPE histOrderType = (ENUM_ORDER_TYPE)HistoryOrderGetInteger(orderTicket, ORDER_TYPE);
                  if(histOrderType == ORDER_TYPE_BUY_LIMIT || histOrderType == ORDER_TYPE_SELL_LIMIT)
                     entryExecutionType = "LIMIT";
                  else if(histOrderType == ORDER_TYPE_BUY || histOrderType == ORDER_TYPE_SELL)
                     entryExecutionType = "MARKET";
               }
            }

            if(!isReversal)
            {
               if(orderTicket > 0)
               {
                  if(StringFind(orderComment, "Virada") >= 0 || StringFind(orderComment, "virada") >= 0)
                     isReversal = true;
               }
            }
         }
         else if(dealEntry == DEAL_ENTRY_OUT)
         {
            exitTime = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
            exitPrice = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
            double dealProfit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
            double dealSwap = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
            double dealCommission = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
            double dealFee = HistoryDealGetDouble(dealTicket, DEAL_FEE);
            grossProfit += dealProfit;
            swapValue += dealSwap;
            commissionValue += dealCommission;
            feeValue += dealFee;
            profit += (dealProfit + dealSwap + dealCommission + dealFee);
            hasExit = true;

            long dealReason = HistoryDealGetInteger(dealTicket, DEAL_REASON);
            if(dealReason == DEAL_REASON_SL)
            {
               wasStopLoss = true;
               hasReason = true;
            }
            else if(dealReason == DEAL_REASON_TP)
            {
               wasStopLoss = false;
               hasReason = true;
            }
         }
      }
   }

   if(!hasReason && hasExit && stopLoss != 0 && takeProfit != 0)
   {
      double distanceToSL = MathAbs(exitPrice - stopLoss);
      double distanceToTP = MathAbs(exitPrice - takeProfit);
      wasStopLoss = (distanceToSL < distanceToTP);
   }

   if(!shouldLog)
   {
      if(!hasExit)
      {
         Print("WARN: nao foi possivel resolver fechamento overnight do ticket ", ticket);
         return false;
      }

      wasStopLossOut = wasStopLoss;
      return true;
   }

   if(entryTime <= 0 || !hasExit)
   {
      Print("WARN: nao foi possivel logar fechamento overnight do ticket ", ticket);
      return false;
   }

   if(entryExecutionType == "")
      entryExecutionType = "MARKET";
   if(triggerTime <= 0)
      triggerTime = entryTime;
   if(profit > maxFloatingProfit)
      maxFloatingProfit = profit;
   if(profit < maxFloatingDrawdown)
      maxFloatingDrawdown = profit;

   datetime tempEntryTime = g_tradeEntryTime;
   double tempEntryPrice = g_tradeEntryPrice;
   bool tempReversal = g_tradeReversal;
   bool tempPCM = g_tradePCM;
   bool tempSliced = g_tradeSliced;
   ENUM_ORDER_TYPE tempOrderType = g_currentOrderType;
   double tempStopLoss = g_firstTradeStopLoss;
   double tempTakeProfit = g_firstTradeTakeProfit;
   datetime tempChannelDefinitionTime = g_tradeChannelDefinitionTime;
   string tempEntryExecutionType = g_tradeEntryExecutionType;
   datetime tempTriggerTime = g_tradeTriggerTime;
   double tempMaxFloatingProfit = g_tradeMaxFloatingProfit;
   double tempMaxFloatingDrawdown = g_tradeMaxFloatingDrawdown;
   double tempMaxAdverseToSLPercent = g_tradeMaxAdverseToSLPercent;
   double tempMaxFavorableToTPPercent = g_tradeMaxFavorableToTPPercent;
   int tempOperationChainId = g_currentOperationChainId;

   int resolvedOperationChainId = snapshotOperationChainId;
   if(resolvedOperationChainId <= 0)
      resolvedOperationChainId = g_overnightChainId;
   if(resolvedOperationChainId <= 0)
      resolvedOperationChainId = g_currentOperationChainId;
   if(resolvedOperationChainId <= 0)
      resolvedOperationChainId = ResolveOperationChainIdForLog(entryTime);
   AdoptOperationChainId(resolvedOperationChainId);

   g_tradeEntryTime = entryTime;
   g_tradeEntryPrice = entryPrice;
   g_tradeReversal = isReversal;
   g_tradePCM = isPCM;
   g_tradeSliced = isSliced;
   g_currentOrderType = orderType;
   g_firstTradeStopLoss = stopLoss;
   g_firstTradeTakeProfit = takeProfit;
   g_tradeChannelDefinitionTime = channelDefinitionTime;
   g_tradeEntryExecutionType = entryExecutionType;
   g_tradeTriggerTime = triggerTime;
   g_tradeMaxFloatingProfit = maxFloatingProfit;
   g_tradeMaxFloatingDrawdown = maxFloatingDrawdown;
   g_tradeMaxAdverseToSLPercent = maxAdverseToSLPercent;
   g_tradeMaxFavorableToTPPercent = maxFavorableToTPPercent;

   ulong overnightTicketList[];
   ArrayResize(overnightTicketList, 1);
   overnightTicketList[0] = ticket;
   int addOnCount = 0;
   double addOnLots = 0.0;
   double addOnAvgEntryPrice = 0.0;
   double addOnProfit = 0.0;
   CollectNegativeAddMetricsFromTickets(overnightTicketList, addOnCount, addOnLots, addOnAvgEntryPrice, addOnProfit);

   int isAddOperationOverride = IsNegativeAddTicket(ticket) ? 1 : 0;
   LogTrade(exitTime,
            exitPrice,
            profit,
            !wasStopLoss,
            addOnCount,
            addOnLots,
            addOnAvgEntryPrice,
            addOnProfit,
            isAddOperationOverride,
            grossProfit,
            swapValue,
            commissionValue,
            feeValue,
            true);
   wasStopLossOut = wasStopLoss;

   g_tradeEntryTime = tempEntryTime;
   g_tradeEntryPrice = tempEntryPrice;
   g_tradeReversal = tempReversal;
   g_tradePCM = tempPCM;
   g_tradeSliced = tempSliced;
   g_currentOrderType = tempOrderType;
   g_firstTradeStopLoss = tempStopLoss;
   g_firstTradeTakeProfit = tempTakeProfit;
   g_tradeChannelDefinitionTime = tempChannelDefinitionTime;
   g_tradeEntryExecutionType = tempEntryExecutionType;
   g_tradeTriggerTime = tempTriggerTime;
   g_tradeMaxFloatingProfit = tempMaxFloatingProfit;
   g_tradeMaxFloatingDrawdown = tempMaxFloatingDrawdown;
   g_tradeMaxAdverseToSLPercent = tempMaxAdverseToSLPercent;
   g_tradeMaxFavorableToTPPercent = tempMaxFavorableToTPPercent;
   g_currentOperationChainId = tempOperationChainId;

   Print("INFO: fechamento overnight logado para ticket ", ticket, " | is_reversal=", isReversal);
   return true;
}

//+------------------------------------------------------------------+
//| Loga tickets ADD-on fechados da operacao atual (nao overnight)   |
//+------------------------------------------------------------------+
int LogClosedAddOnTicketsCurrentTrade(bool snapshotSliced,
                                      bool snapshotReversal,
                                      bool snapshotPCM,
                                      datetime snapshotChannelDefinitionTime,
                                      int snapshotOperationChainId)
{
   if(!EnableLogging)
      return 0;

   ulong addOnTicketsToLog[];
   ArrayResize(addOnTicketsToLog, 0);

   int addTrackedTotal = ArraySize(g_negativeAddExecutedTickets);
   for(int i = 0; i < addTrackedTotal; i++)
   {
      ulong ticket = g_negativeAddExecutedTickets[i];
      if(ticket == 0)
         continue;

      bool exists = false;
      int existingTotal = ArraySize(addOnTicketsToLog);
      for(int j = 0; j < existingTotal; j++)
      {
         if(addOnTicketsToLog[j] == ticket)
         {
            exists = true;
            break;
         }
      }

      if(!exists)
      {
         int n = ArraySize(addOnTicketsToLog);
         ArrayResize(addOnTicketsToLog, n + 1);
         addOnTicketsToLog[n] = ticket;
      }
   }

   int trackedCurrentTotal = ArraySize(g_currentTradePositionTickets);
   for(int i = 0; i < trackedCurrentTotal; i++)
   {
      ulong ticket = g_currentTradePositionTickets[i];
      if(ticket == 0)
         continue;
      if(!IsNegativeAddTicket(ticket))
         continue;

      bool exists = false;
      int existingTotal = ArraySize(addOnTicketsToLog);
      for(int j = 0; j < existingTotal; j++)
      {
         if(addOnTicketsToLog[j] == ticket)
         {
            exists = true;
            break;
         }
      }

      if(!exists)
      {
         int n = ArraySize(addOnTicketsToLog);
         ArrayResize(addOnTicketsToLog, n + 1);
         addOnTicketsToLog[n] = ticket;
      }
   }

   int loggedCount = 0;
   int total = ArraySize(addOnTicketsToLog);
   for(int i = 0; i < total; i++)
   {
      ulong ticket = addOnTicketsToLog[i];
      if(ticket == 0)
         continue;
      if(!IsNegativeAddTicket(ticket))
         continue;

      datetime addEntryTime = 0;
      double addEntryPrice = 0.0;
      double addStopLoss = g_firstTradeStopLoss;
      double addTakeProfit = g_firstTradeTakeProfit;
      double addMaxFloatingProfit = 0.0;
      double addMaxFloatingDrawdown = 0.0;
      double addMaxAdverseToSLPercent = 0.0;
      double addMaxFavorableToTPPercent = 0.0;
      GetNegativeAddSnapshotByTicket(ticket,
                                     addEntryTime,
                                     addEntryPrice,
                                     addStopLoss,
                                     addTakeProfit,
                                     addMaxFloatingProfit,
                                     addMaxFloatingDrawdown,
                                     addMaxAdverseToSLPercent,
                                     addMaxFavorableToTPPercent);

      bool wasStopLoss = false;
      bool logged = LogClosedOvernightTrade(ticket,
                                            addEntryTime,
                                            addEntryPrice,
                                            addStopLoss,
                                            addTakeProfit,
                                            snapshotSliced,
                                            snapshotReversal,
                                            snapshotPCM,
                                            g_currentOrderType,
                                            snapshotChannelDefinitionTime,
                                            "",
                                            addEntryTime,
                                            addMaxFloatingProfit,
                                            addMaxFloatingDrawdown,
                                            addMaxAdverseToSLPercent,
                                            addMaxFavorableToTPPercent,
                                            snapshotOperationChainId,
                                            wasStopLoss);
      if(logged)
         loggedCount++;
   }

   return loggedCount;
}

//+------------------------------------------------------------------+
//| Verifica status da posicao                                       |
//+------------------------------------------------------------------+
void CheckPositionStatus()
{
   // Verificar posicao overnight separadamente
   for(int i = ArraySize(g_overnightLogTickets) - 1; i >= 0; i--)
   {
      ulong overnightTicket = g_overnightLogTickets[i];
      if(overnightTicket == 0)
         continue;

      if(!PositionSelectByTicket(overnightTicket))
      {
         Print("INFO: Posicao overnight fechada. Ticket: ", overnightTicket);
         bool overnightWasStopLoss = false;
         bool overnightWasMainTicket = (g_overnightTicket == overnightTicket);
         bool overnightSnapshotWasReversal = g_overnightLogReversals[i];
         bool overnightSnapshotWasPCM = g_overnightLogPCMs[i];
         bool overnightSnapshotSliced = g_overnightLogSliceds[i];
         ENUM_ORDER_TYPE overnightSnapshotOrderType = g_overnightLogOrderTypes[i];
         double overnightSnapshotChannelRange = g_overnightLogChannelRanges[i];
         double overnightSnapshotLotSize = g_overnightLogLotSizes[i];
         datetime overnightSnapshotChannelDefinitionTime = g_overnightLogChannelDefinitionTimes[i];
         int overnightSnapshotChainId = g_overnightLogChainIds[i];
         bool overnightLoggedFromList = LogClosedOvernightTrade(overnightTicket,
                                                                g_overnightLogEntryTimes[i],
                                                                g_overnightLogEntryPrices[i],
                                                                g_overnightLogStopLosses[i],
                                                                g_overnightLogTakeProfits[i],
                                                                g_overnightLogSliceds[i],
                                                                g_overnightLogReversals[i],
                                                                g_overnightLogPCMs[i],
                                                                g_overnightLogOrderTypes[i],
                                                                g_overnightLogChannelDefinitionTimes[i],
                                                                g_overnightLogEntryExecutionTypes[i],
                                                                g_overnightLogTriggerTimes[i],
                                                                g_overnightLogMaxFloatingProfits[i],
                                                                g_overnightLogMaxFloatingDrawdowns[i],
                                                                g_overnightLogMaxAdverseToSLPercents[i],
                                                                g_overnightLogMaxFavorableToTPPercents[i],
                                                                overnightSnapshotChainId,
                                                                overnightWasStopLoss);
         if(overnightLoggedFromList)
         {
            RemoveOvernightLogSnapshotByIndex(i);
            if(overnightWasMainTicket)
            {
               g_overnightTicket = 0;
               g_overnightEntryTime = 0;
               g_overnightEntryPrice = 0;
               g_overnightStopLoss = 0;
               g_overnightTakeProfit = 0;
               g_overnightChannelRange = 0;
               g_overnightLotSize = 0;
               g_overnightSliced = false;
               g_overnightReversal = false;
               g_overnightPCM = false;
               g_overnightOrderType = ORDER_TYPE_BUY;
               g_overnightChannelDefinitionTime = 0;
               g_overnightEntryExecutionType = "";
               g_overnightTriggerTime = 0;
               g_overnightMaxFloatingProfit = 0;
               g_overnightMaxFloatingDrawdown = 0;
               g_overnightMaxAdverseToSLPercent = 0;
               g_overnightMaxFavorableToTPPercent = 0;
               g_overnightChainId = 0;
            }

            if(overnightWasMainTicket && overnightWasStopLoss && !overnightSnapshotWasPCM)
            {
               g_lastClosedOvernightChainIdHint = overnightSnapshotChainId;
               bool overnightReversalAdopted = TryAdoptTriggeredPreArmedReversal(true);
               if(!overnightReversalAdopted)
               {
                  if(g_preArmedReversalOrderTicket > 0)
                     CancelPreArmedReversalOrder("fallback para virada overnight a mercado");
                  TryExecuteOvernightReversal(overnightSnapshotOrderType,
                                              overnightSnapshotWasReversal,
                                              overnightSnapshotWasPCM,
                                              overnightSnapshotSliced,
                                              overnightSnapshotChannelRange,
                                              overnightSnapshotLotSize,
                                              overnightSnapshotChannelDefinitionTime,
                                              overnightSnapshotChainId);
               }
               g_lastClosedOvernightChainIdHint = 0;
            }
            else if(overnightWasMainTicket && overnightWasStopLoss && overnightSnapshotWasPCM)
            {
               Print("INFO: overnight em SL era PCM. Turnof ignorada por regra.");
               CancelPreArmedReversalOrder("SL de overnight PCM - turnof desabilitada");
            }
            else if(overnightWasMainTicket)
            {
               CancelPreArmedReversalOrder("overnight encerrada sem SL");
            }
         }
         else
         {
            Print("WARN: mantendo ticket overnight para nova tentativa de log");
         }
      }
      else
      {
         UpdateOvernightFloatingMetricsByIndex(i, overnightTicket);
      }
   }

   if(g_overnightTicket > 0 && ArraySize(g_overnightLogTickets) == 0)
   {
      if(!PositionSelectByTicket(g_overnightTicket))
      {
         Print(" Posicao overnight ", g_overnightTicket, " foi fechada");
         bool overnightWasStopLoss = false;
         ENUM_ORDER_TYPE overnightSnapshotOrderType = g_overnightOrderType;
         bool overnightSnapshotWasReversal = g_overnightReversal;
         bool overnightSnapshotWasPCM = g_overnightPCM;
         bool overnightSnapshotSliced = g_overnightSliced;
         double overnightSnapshotChannelRange = g_overnightChannelRange;
         double overnightSnapshotLotSize = g_overnightLotSize;
         datetime overnightSnapshotChannelDefinitionTime = g_overnightChannelDefinitionTime;
         int overnightSnapshotChainId = g_overnightChainId;
         bool overnightLogged = LogClosedOvernightTrade(g_overnightTicket,
                                                        g_overnightEntryTime,
                                                        g_overnightEntryPrice,
                                                        g_overnightStopLoss,
                                                        g_overnightTakeProfit,
                                                        g_overnightSliced,
                                                        g_overnightReversal,
                                                        g_overnightPCM,
                                                        g_overnightOrderType,
                                                        g_overnightChannelDefinitionTime,
                                                        g_overnightEntryExecutionType,
                                                        g_overnightTriggerTime,
                                                        g_overnightMaxFloatingProfit,
                                                        g_overnightMaxFloatingDrawdown,
                                                        g_overnightMaxAdverseToSLPercent,
                                                        g_overnightMaxFavorableToTPPercent,
                                                        overnightSnapshotChainId,
                                                        overnightWasStopLoss);
         if(overnightLogged)
         {
            g_overnightTicket = 0;
            g_overnightEntryTime = 0;
            g_overnightEntryPrice = 0;
            g_overnightStopLoss = 0;
            g_overnightTakeProfit = 0;
            g_overnightChannelRange = 0;
            g_overnightLotSize = 0;
            g_overnightSliced = false;
            g_overnightReversal = false;
            g_overnightPCM = false;
            g_overnightOrderType = ORDER_TYPE_BUY;
            g_overnightChannelDefinitionTime = 0;
            g_overnightEntryExecutionType = "";
            g_overnightTriggerTime = 0;
            g_overnightMaxFloatingProfit = 0;
            g_overnightMaxFloatingDrawdown = 0;
            g_overnightMaxAdverseToSLPercent = 0;
            g_overnightMaxFavorableToTPPercent = 0;
            g_overnightChainId = 0;

            if(overnightWasStopLoss && !overnightSnapshotWasPCM)
            {
               g_lastClosedOvernightChainIdHint = overnightSnapshotChainId;
               bool overnightReversalAdopted = TryAdoptTriggeredPreArmedReversal(true);
               if(!overnightReversalAdopted)
               {
                  if(g_preArmedReversalOrderTicket > 0)
                     CancelPreArmedReversalOrder("fallback para virada overnight a mercado");
                  TryExecuteOvernightReversal(overnightSnapshotOrderType,
                                              overnightSnapshotWasReversal,
                                              overnightSnapshotWasPCM,
                                              overnightSnapshotSliced,
                                              overnightSnapshotChannelRange,
                                              overnightSnapshotLotSize,
                                              overnightSnapshotChannelDefinitionTime,
                                              overnightSnapshotChainId);
               }
               g_lastClosedOvernightChainIdHint = 0;
            }
            else if(overnightWasStopLoss && overnightSnapshotWasPCM)
            {
               Print("INFO: overnight em SL era PCM. Turnof ignorada por regra.");
               CancelPreArmedReversalOrder("SL de overnight PCM - turnof desabilitada");
            }
            else
            {
               CancelPreArmedReversalOrder("overnight encerrada sem SL");
            }
         }
         else
         {
            Print("WARN: mantendo ticket overnight para nova tentativa de log");
         }
      }
      else
      {
         double volume = PositionGetDouble(POSITION_VOLUME);
         double floatingProfit = 0;
         if(CalculateFloatingProfit(g_overnightOrderType, g_overnightEntryPrice, volume, floatingProfit))
         {
            if(floatingProfit > g_overnightMaxFloatingProfit)
               g_overnightMaxFloatingProfit = floatingProfit;
            if(floatingProfit < g_overnightMaxFloatingDrawdown)
               g_overnightMaxFloatingDrawdown = floatingProfit;

            double overnightAdverseToSLPercent = CalculateAdverseToSLPercent(g_overnightOrderType,
                                                                             g_overnightEntryPrice,
                                                                             g_overnightStopLoss);
            if(overnightAdverseToSLPercent > g_overnightMaxAdverseToSLPercent)
               g_overnightMaxAdverseToSLPercent = overnightAdverseToSLPercent;
         }
      }
   }

   if(g_currentTicket == 0 && !g_pendingOrderPlaced &&
      (g_currentOrderType == ORDER_TYPE_BUY || g_currentOrderType == ORDER_TYPE_SELL) &&
      (g_firstTradeExecuted || g_reversalTradeExecuted))
   {
      datetime recoveryMinTime = g_tradeEntryTime;
      if(recoveryMinTime <= 0)
         recoveryMinTime = TimeCurrent() - 24 * 60 * 60;
      else
         recoveryMinTime -= 60;
      ulong recoveredTicket = FindLatestEAPositionTicketByType(g_currentOrderType, recoveryMinTime);
      if(recoveredTicket > 0)
      {
         g_currentTicket = recoveredTicket;
         TrackCurrentTradePositionTicket(recoveredTicket);
         Print("INFO: ticket principal recuperado por varredura de posicoes. ticket=", recoveredTicket);
      }
   }

   if(g_currentTicket == 0)
      return;

   // Se tem ordem pendente, nao verificar como posicao
   if(g_pendingOrderPlaced)
      return;

   ulong activeTickets[];
   double activeVolume = 0.0;
   double weightedEntryPrice = 0.0;
   double activeFloating = 0.0;
   int activeCount = CollectActiveCurrentTradePositions(activeTickets, activeVolume, weightedEntryPrice, activeFloating);
   if(activeCount > 0)
   {
      TrackCurrentTradePositionTickets(activeTickets);
      if(g_currentTicket != activeTickets[0])
      {
         Print("INFO: Ticket principal atualizado para posicao ativa ", activeTickets[0],
               " | total_posicoes=", activeCount);
         g_currentTicket = activeTickets[0];
      }
      UpdateCurrentTradeFloatingMetricsFromPosition();
      TryApplyPCMBreakEven();
      TryApplyPCMTraillingStop();
      if(!g_tradePCM && !g_tradeReversal && !AllowReversalAfterMaxEntryHour && IsAfterMaxEntryHour())
      {
         if(g_preArmedReversalOrderTicket > 0)
            CancelPreArmedReversalOrder("horario limite de entrada atingido");
         if(!g_reversalBlockedByEntryHour)
         {
            MarkReversalBlockedByEntryHour();
            Print("INFO: virada bloqueada por horario limite enquanto posicao permanecia aberta.");
         }
      }
      if(g_tradePCM)
      {
         if(g_preArmedReversalOrderTicket > 0)
            CancelPreArmedReversalOrder("turnof desabilitada para estrategia PCM");
      }
      else if(!g_tradeReversal && g_preArmedReversalOrderTicket == 0)
         EnsurePreArmedReversalForCurrentTrade();
      TryExecuteNegativeAddOn();
      return;
   }

   // A partir daqui a posicao ja foi fechada.
   {
      Print(" Posicao ", g_currentTicket, " foi fechada");
      Print(" Debug: g_firstTradeExecuted=", g_firstTradeExecuted, " | g_reversalTradeExecuted=", g_reversalTradeExecuted);

      // Calcular profit real do historico
      double profit = 0;
      double grossProfit = 0.0;
      double swapValue = 0.0;
      double commissionValue = 0.0;
      double feeValue = 0.0;
      double exitPrice = 0;
      datetime exitTime = TimeCurrent();
      int slCloseCount = 0;
      int tpCloseCount = 0;
      bool closeSummaryFound = GetClosedCurrentTradeSummary(profit,
                                                            grossProfit,
                                                            swapValue,
                                                            commissionValue,
                                                            feeValue,
                                                            exitPrice,
                                                            exitTime,
                                                            slCloseCount,
                                                            tpCloseCount);
      if(!closeSummaryFound && HistorySelectByPosition(g_currentTicket))
      {
         int total = HistoryDealsTotal();
         for(int i = total - 1; i >= 0; i--)
         {
            ulong dealTicket = HistoryDealGetTicket(i);
            if(dealTicket > 0)
            {
               long dealEntry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
               if(dealEntry == DEAL_ENTRY_OUT)
               {
                  double dealProfit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
                  double dealSwap = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
                  double dealCommission = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
                  double dealFee = HistoryDealGetDouble(dealTicket, DEAL_FEE);
                  grossProfit = dealProfit;
                  swapValue = dealSwap;
                  commissionValue = dealCommission;
                  feeValue = dealFee;
                  profit = (dealProfit + dealSwap + dealCommission + dealFee);
                  exitPrice = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
                  exitTime = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
                  long dealReason = HistoryDealGetInteger(dealTicket, DEAL_REASON);
                  if(dealReason == DEAL_REASON_SL)
                     slCloseCount++;
                  else if(dealReason == DEAL_REASON_TP)
                     tpCloseCount++;
                  break;
               }
            }
         }
      }

      // Metodo robusto: verificar preco de fechamento
      bool wasStopLoss = CheckIfStopLossHitRobust();
      if(slCloseCount > 0 && tpCloseCount == 0)
         wasStopLoss = true;
      else if(tpCloseCount > 0 && slCloseCount == 0)
         wasStopLoss = false;

      Print(" DEBUG ANTES DE LOGAR:");
      Print("  g_tradeReversal=", g_tradeReversal);
      Print("  g_tradePCM=", g_tradePCM);
      Print("  g_tradeSliced=", g_tradeSliced);
      Print("  g_tradeEntryTime=", TimeToString(g_tradeEntryTime, TIME_DATE|TIME_MINUTES));
      Print("  g_tradeEntryPrice=", g_tradeEntryPrice);

      // Registrar operacao no log
      if(EnableLogging)
      {
         // SEMPRE buscar dados do historico para garantir que viradas de mao sejam logadas
         datetime entryTime = g_tradeEntryTime;
         double entryPrice = g_tradeEntryPrice;
         bool isReversal = g_tradeReversal;
         bool isPCM = g_tradePCM;
         bool isSliced = g_tradeSliced;
         datetime channelDefinitionTime = g_tradeChannelDefinitionTime;
         string entryExecutionType = g_tradeEntryExecutionType;
         datetime triggerTime = g_tradeTriggerTime;
         double maxFloatingProfit = g_tradeMaxFloatingProfit;
         double maxFloatingDrawdown = g_tradeMaxFloatingDrawdown;
         double maxAdverseToSLPercent = g_tradeMaxAdverseToSLPercent;
         double maxFavorableToTPPercent = g_tradeMaxFavorableToTPPercent;
         if(channelDefinitionTime <= 0)
            channelDefinitionTime = g_channelDefinitionTime;

         // Se nao temos dados em memoria, buscar do historico
         if(HistorySelectByPosition(g_currentTicket))
         {
            int total = HistoryDealsTotal();
            bool entryRecovered = false;
            for(int i = 0; i < total; i++)
            {
               ulong dealTicket = HistoryDealGetTicket(i);
               if(dealTicket > 0)
               {
                  long dealEntry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
                  if(dealEntry == DEAL_ENTRY_IN)
                  {
                     if(entryTime == 0 || !entryRecovered)
                     {
                        entryTime = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
                        entryPrice = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
                        entryRecovered = true;
                     }

                     // Verificar se e turnof pelo comentario
                     string comment = HistoryDealGetString(dealTicket, DEAL_COMMENT);
                     ulong orderTicket = (ulong)HistoryDealGetInteger(dealTicket, DEAL_ORDER);
                     string orderComment = "";
                     if(orderTicket > 0)
                        orderComment = HistoryOrderGetString(orderTicket, ORDER_COMMENT);

                     if(StringFind(comment, "Virada") >= 0 || StringFind(comment, "virada") >= 0)
                     {
                        isReversal = true;
                        Print(" turnof detectada no historico");
                     }
                     if(StringFind(comment, "PCM") >= 0 || StringFind(orderComment, "PCM") >= 0)
                     {
                        isPCM = true;
                        Print(" PCM detectada no historico");
                     }

                     if(entryExecutionType == "")
                     {
                        if(StringFind(comment, "Limite") >= 0 || StringFind(comment, "LIMIT") >= 0 ||
                           StringFind(orderComment, "Limite") >= 0 || StringFind(orderComment, "LIMIT") >= 0)
                        {
                           entryExecutionType = "LIMIT";
                        }
                        else if(orderTicket > 0)
                        {
                           ENUM_ORDER_TYPE histOrderType = (ENUM_ORDER_TYPE)HistoryOrderGetInteger(orderTicket, ORDER_TYPE);
                           if(histOrderType == ORDER_TYPE_BUY_LIMIT || histOrderType == ORDER_TYPE_SELL_LIMIT)
                              entryExecutionType = "LIMIT";
                           else if(histOrderType == ORDER_TYPE_BUY || histOrderType == ORDER_TYPE_SELL)
                              entryExecutionType = "MARKET";
                        }
                     }

                     Print(" Entry recuperado do historico: ", TimeToString(entryTime, TIME_DATE|TIME_MINUTES));
                     if(!isReversal)
                     {
                        if(orderTicket > 0)
                        {
                           if(StringFind(orderComment, "Virada") >= 0 || StringFind(orderComment, "virada") >= 0)
                           {
                              isReversal = true;
                              Print("INFO: turnof detectada no comentario da ordem");
                           }
                        }
                     }
                  }
               }
            }
         }

         // Logar se temos dados validos
         if(entryTime > 0)
         {
            if(entryExecutionType == "")
               entryExecutionType = "MARKET";
            if(triggerTime <= 0)
               triggerTime = entryTime;
            if(profit > maxFloatingProfit)
               maxFloatingProfit = profit;
            if(profit < maxFloatingDrawdown)
               maxFloatingDrawdown = profit;

            // Temporariamente restaurar valores para LogTrade
            datetime tempEntryTime = g_tradeEntryTime;
            double tempEntryPrice = g_tradeEntryPrice;
            bool tempReversal = g_tradeReversal;
            bool tempPCM = g_tradePCM;
            bool tempSliced = g_tradeSliced;
            datetime tempChannelDefinitionTime = g_tradeChannelDefinitionTime;
            string tempEntryExecutionType = g_tradeEntryExecutionType;
            datetime tempTriggerTime = g_tradeTriggerTime;
            double tempMaxFloatingProfit = g_tradeMaxFloatingProfit;
            double tempMaxFloatingDrawdown = g_tradeMaxFloatingDrawdown;
            double tempMaxAdverseToSLPercent = g_tradeMaxAdverseToSLPercent;
            double tempMaxFavorableToTPPercent = g_tradeMaxFavorableToTPPercent;

            g_tradeEntryTime = entryTime;
            g_tradeEntryPrice = entryPrice;
            g_tradeReversal = isReversal;
            g_tradePCM = isPCM;
            g_tradeSliced = isSliced;
            g_tradeChannelDefinitionTime = channelDefinitionTime;
            g_tradeEntryExecutionType = entryExecutionType;
            g_tradeTriggerTime = triggerTime;
            g_tradeMaxFloatingProfit = maxFloatingProfit;
            g_tradeMaxFloatingDrawdown = maxFloatingDrawdown;
            g_tradeMaxAdverseToSLPercent = maxAdverseToSLPercent;
            g_tradeMaxFavorableToTPPercent = maxFavorableToTPPercent;

            int addOnTicketsLogged = LogClosedAddOnTicketsCurrentTrade(isSliced,
                                                                       isReversal,
                                                                       isPCM,
                                                                       channelDefinitionTime,
                                                                       g_currentOperationChainId);
            if(addOnTicketsLogged > 0)
               Print("INFO: tickets de addon logados separadamente: ", addOnTicketsLogged);

            int addOnCount = 0;
            double addOnLots = 0.0;
            double addOnAvgEntryPrice = 0.0;
            double addOnProfit = 0.0;
            CollectNegativeAddMetricsCurrentTrade(addOnCount, addOnLots, addOnAvgEntryPrice, addOnProfit);

            // Este log resume o fechamento do ciclo atual (nao representa ticket addon individual).
            LogTrade(exitTime,
                     exitPrice,
                     profit,
                     !wasStopLoss,
                     addOnCount,
                     addOnLots,
                     addOnAvgEntryPrice,
                     addOnProfit,
                     0,
                     grossProfit,
                     swapValue,
                     commissionValue,
                     feeValue,
                     true);

            // Restaurar
            g_tradeEntryTime = tempEntryTime;
            g_tradeEntryPrice = tempEntryPrice;
            g_tradeReversal = tempReversal;
            g_tradePCM = tempPCM;
            g_tradeSliced = tempSliced;
            g_tradeChannelDefinitionTime = tempChannelDefinitionTime;
            g_tradeEntryExecutionType = tempEntryExecutionType;
            g_tradeTriggerTime = tempTriggerTime;
            g_tradeMaxFloatingProfit = tempMaxFloatingProfit;
            g_tradeMaxFloatingDrawdown = tempMaxFloatingDrawdown;
            g_tradeMaxAdverseToSLPercent = tempMaxAdverseToSLPercent;
            g_tradeMaxFavorableToTPPercent = tempMaxFavorableToTPPercent;
         }
         else
         {
            Print(" Nao foi possivel logar operacao - dados de entrada nao encontrados");
         }
      }

      bool reversalOpenedNow = false;
      if(g_firstTradeExecuted && !g_reversalTradeExecuted)
      {
         if(wasStopLoss)
         {
            if(g_tradePCM)
            {
               Print(" STOP LOSS ATINGIDO - Operacao PCM nao permite turnof. Encerrando ciclo.");
               CancelPreArmedReversalOrder("SL de operacao PCM - turnof desabilitada");
            }
            else if(EnableReversal)
            {
               Print(" STOP LOSS ATINGIDO - Virando a mao!");
               reversalOpenedNow = TryAdoptTriggeredPreArmedReversal(false);
               if(!reversalOpenedNow)
               {
                  if(g_preArmedReversalOrderTicket > 0)
                     CancelPreArmedReversalOrder("fallback para virada a mercado");
                  ExecuteReversal();
                  if((g_reversalTradeExecuted && g_currentTicket > 0) ||
                     (g_pendingOrderPlaced && g_currentTicket > 0 &&
                      (g_pendingOrderContext == PENDING_CONTEXT_REVERSAL ||
                       g_pendingOrderContext == PENDING_CONTEXT_OVERNIGHT_REVERSAL)))
                     reversalOpenedNow = true;
               }
            }
            else
            {
               Print(" STOP LOSS ATINGIDO - turnof desabilitada");
               CancelPreArmedReversalOrder("SL com virada desabilitada");
            }
         }
         else
         {
            bool pcmScheduled = false;
            if(!g_tradePCM)
               pcmScheduled = SchedulePCMActivationFromTP(exitTime);
            if(pcmScheduled)
               Print(" Take Profit atingido - PCM armado para nova operacao.");
            else
               Print(" Take Profit atingido - Fim do dia");
            CancelPreArmedReversalOrder("TP da operacao principal");
         }
      }
      else if(g_reversalTradeExecuted)
      {
         Print(wasStopLoss ? " turnof: SL atingido" : " turnof: TP atingido");
         if(g_preArmedReversalOrderTicket > 0)
            CancelPreArmedReversalOrder("encerramento de trade de virada");
      }

      if(!reversalOpenedNow)
      {
         g_currentTicket = 0;
         ClearCurrentTradePositionTickets();
         g_currentOperationChainId = 0;
         ResetReversalHourBlockState();
         ResetNegativeAddState();
      }
      else
      {
         Print("INFO: Ticket de virada preservado para monitorar fechamento: ", g_currentTicket);
      }
   }
}

//+------------------------------------------------------------------+
//| Verifica se foi stop loss (Metodo Robusto)                        |
//+------------------------------------------------------------------+
bool CheckIfStopLossHitRobust()
{
   // Primeiro tenta pelo historico (metodo original)
   if(HistorySelectByPosition(g_currentTicket))
   {
      int total = HistoryDealsTotal();
      for(int i = total - 1; i >= 0; i--)
      {
         ulong dealTicket = HistoryDealGetTicket(i);
         if(dealTicket > 0)
         {
            long dealEntry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
            if(dealEntry == DEAL_ENTRY_OUT)
            {
               long dealReason = HistoryDealGetInteger(dealTicket, DEAL_REASON);
               if(dealReason == DEAL_REASON_SL)
               {
                  Print(" Metodo 1: SL detectado via historico");
                  return true;
               }
               if(dealReason == DEAL_REASON_TP)
               {
                  Print(" Metodo 1: TP detectado via historico");
                  return false;
               }

               // Se nao tem razao clara, usar metodo 2
               break;
            }
         }
      }
   }

   // Metodo 2: Verificar preco de fechamento vs SL/TP
   if(HistoryOrderSelect(g_currentTicket))
   {
      double closePrice = HistoryOrderGetDouble(g_currentTicket, ORDER_PRICE_CURRENT);

      if(g_currentOrderType == ORDER_TYPE_BUY)
      {
         // BUY: SL esta abaixo, TP esta acima
         double distanceToSL = MathAbs(closePrice - g_firstTradeStopLoss);
         double distanceToTP = MathAbs(closePrice - g_firstTradeTakeProfit);

         bool hitSL = (distanceToSL < distanceToTP);
         Print(" Metodo 2 (BUY): Close=", closePrice, " | SL=", g_firstTradeStopLoss, " | TP=", g_firstTradeTakeProfit, " | Hit SL=", hitSL);
         return hitSL;
      }
      else  // SELL
      {
         // SELL: SL esta acima, TP esta abaixo
         double distanceToSL = MathAbs(closePrice - g_firstTradeStopLoss);
         double distanceToTP = MathAbs(closePrice - g_firstTradeTakeProfit);

         bool hitSL = (distanceToSL < distanceToTP);
         Print(" Metodo 2 (SELL): Close=", closePrice, " | SL=", g_firstTradeStopLoss, " | TP=", g_firstTradeTakeProfit, " | Hit SL=", hitSL);
         return hitSL;
      }
   }

   // Fallback seguro: nao inferir SL sem evidencia para evitar turnof indevida.
   Print(" Metodo 3: saida sem classificacao confiavel - tratando como NAO_SL por seguranca");
   return false;
}

//+------------------------------------------------------------------+
//| Executa turnof                                            |
//+------------------------------------------------------------------+
void ExecuteReversal()
{
   Print(" === ExecuteReversal CHAMADA ===");
   Print("  g_channelRange: ", g_channelRange);
   Print("  g_cycle1Direction: ", g_cycle1Direction);
   Print("  g_currentOrderType: ", EnumToString(g_currentOrderType));

   if(g_tradePCM)
   {
      Print(" turnof cancelada - Estrategia PCM nao permite virada.");
      return;
   }

   if(IsDrawdownLimitReached("ExecuteReversal"))
   {
      Print(" turnof cancelada por limite de drawdown.");
      return;
   }

   TryRearmReversalBlockForNewDay();
   if(!IsReversalAllowedByEntryHourNow())
   {
      MarkReversalBlockedByEntryHour();
      Print(" turnof cancelada - Horario limite atingido e virada apos limite desabilitada.");
      return;
   }

   if(g_preArmedReversalOrderTicket > 0)
      CancelPreArmedReversalOrder("execucao direta da virada");

   ENUM_ORDER_TYPE reversalType = (g_currentOrderType == ORDER_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   if(!IsTradingAllowedForOrder(reversalType, "ExecuteReversal"))
      return;
   double price = (reversalType == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // Base da distancia da turnof: SlicedMultiplier no modo sliced, senao ReversalMultiplier.
   double baseMultiplier = (g_cycle1Direction == "BOTH") ? SlicedMultiplier : ReversalMultiplier;
   double slFactor = (ReversalSLDistanceFactor > 0.0) ? ReversalSLDistanceFactor : 1.0;
   double tpFactor = (ReversalTPDistanceFactor > 0.0) ? ReversalTPDistanceFactor : 1.0;
   double slDistance = baseMultiplier * slFactor * g_channelRange;
   double tpDistance = baseMultiplier * tpFactor * g_channelRange;

   Print("  BaseMult: ", baseMultiplier,
         " | SL Factor: ", slFactor, " | TP Factor: ", tpFactor,
         " | SL Dist: ", slDistance, " | TP Dist: ", tpDistance);

   // Calcular SL base
   double stopLossBase = (reversalType == ORDER_TYPE_BUY) ? price - slDistance : price + slDistance;

   // Aplicar incremento ao SL
   double slIncrement = slDistance * (StopLossIncrement / 100.0);
   double stopLoss = (reversalType == ORDER_TYPE_BUY) ? stopLossBase - slIncrement : stopLossBase + slIncrement;

   // TP permanece sem incremento
   double takeProfit = (reversalType == ORDER_TYPE_BUY) ? price + tpDistance : price - tpDistance;

   stopLoss = NormalizePriceToTick(stopLoss);
   takeProfit = NormalizePriceToTick(takeProfit);
   double lotSize = IsFixedLotAllEntriesEnabled() ? ResolveFixedLotAllEntries() : NormalizeLot(g_firstTradeLotSize);
   if(lotSize <= 0.0)
   {
      Print(" turnof cancelada - Lote invalido: ", lotSize);
      return;
   }
   if(!ValidateOrderProtectionLevels(reversalType, price, stopLoss, takeProfit, "ExecuteReversal"))
      return;
   datetime triggerTime = TimeCurrent();
   datetime reversalChannelDefinitionTime = (g_tradeChannelDefinitionTime > 0) ? g_tradeChannelDefinitionTime : g_channelDefinitionTime;
   bool reversalIsSliced = (g_cycle1Direction == "BOTH");

   Print(" turnof:");
   Print("  Tipo: ", EnumToString(reversalType));
   Print("  Preco: ", price, " | SL: ", stopLoss, " | TP: ", takeProfit, " | Lotes: ", lotSize);

   if(ShouldUseLimitForReversal())
   {
      Print(" turnof configurada para LIMIT marketable.");
      PlaceLimitOrder(reversalType,
                      stopLoss,
                      takeProfit,
                      "turnof LIMIT",
                      true,
                      lotSize,
                      PENDING_CONTEXT_REVERSAL,
                      true,
                      reversalIsSliced,
                      reversalChannelDefinitionTime,
                      triggerTime,
                      false,
                      g_channelRange);
      if(g_pendingOrderPlaced && g_currentTicket > 0)
      {
         Print(" turnof enviada como LIMIT. Ticket: ", g_currentTicket);
         return;
      }

      if(!AllowMarketFallbackReversal)
      {
         Print(" turnof LIMIT falhou e fallback a mercado esta desabilitado.");
         return;
      }

      Print(" WARN: virada LIMIT falhou; aplicando fallback a mercado.");
   }

   bool result = false;
   datetime requestTime = TimeCurrent();
   if(reversalType == ORDER_TYPE_BUY)
      result = trade.Buy(lotSize, _Symbol, 0, stopLoss, takeProfit, "turnof");
   else
      result = trade.Sell(lotSize, _Symbol, 0, stopLoss, takeProfit, "turnof");

   long retcode = trade.ResultRetcode();
   Print("  Result: ", result, " | ResultRetcode: ", retcode);

   if(result && IsTradeRetcodeAccepted(retcode, true))
   {
      ulong resolvedTicket = 0;
      if(!TryResolvePositionTicketFromTradeResult(reversalType, requestTime, resolvedTicket))
      {
         resolvedTicket = trade.ResultOrder();
         Print("WARN: turnof aceita, mas ticket da posicao nao confirmado imediatamente. fallback=", resolvedTicket);
      }
      g_currentTicket = resolvedTicket;
      ClearCurrentTradePositionTickets();
      if(g_currentTicket > 0)
         TrackCurrentTradePositionTicket(g_currentTicket);
      g_currentOrderType = reversalType;
      g_reversalTradeExecuted = true;

      // CRITICO: Definir dados para log IMEDIATAMENTE
      g_tradeEntryTime = triggerTime;
      g_tradeEntryPrice = price;
      g_tradeReversal = true;  // MARCAR COMO VIRADA
      g_tradePCM = false;
      g_tradeSliced = reversalIsSliced;  // Preservar se e sliced
      g_tradeChannelDefinitionTime = reversalChannelDefinitionTime;
      g_tradeEntryExecutionType = "MARKET";
      g_tradeTriggerTime = triggerTime;
      int reversalChainId = g_lastClosedOvernightChainIdHint;
      if(reversalChainId <= 0)
         reversalChainId = g_currentOperationChainId;
      AdoptOperationChainId(reversalChainId);
      ResetNegativeAddState();
      ResetCurrentTradeFloatingMetrics();
      g_firstTradeStopLoss = stopLoss;
      g_firstTradeTakeProfit = takeProfit;
      if(ShouldUseLimitForNegativeAddOn() && g_negativeAddRuntimeEnabled)
         PlaceNegativeAddOnLimitOrdersForStrictMode(g_tradeEntryPrice);
      g_lastClosedOvernightChainIdHint = 0;

      Print(" turnof executada! Ticket: ", g_currentTicket);
      Print(" FLAGS DEFINIDAS: g_tradeReversal=", g_tradeReversal, " | g_tradeSliced=", g_tradeSliced);
   }
   else
   {
      Print(" Erro na virada: ", retcode, " - ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Executa turnof para fechamento de operacao overnight em SL|
//+------------------------------------------------------------------+
bool TryExecuteOvernightReversal(ENUM_ORDER_TYPE closedOrderType,
                                 bool closedWasReversal,
                                 bool closedWasPCM,
                                 bool isSliced,
                                 double channelRange,
                                 double lotSizeSnapshot,
                                 datetime channelDefinitionTime,
                                 int sourceOperationChainId = 0)
{
   if(!EnableReversal || !EnableOvernightReversal)
      return false;

   if(IsDrawdownLimitReached("TryExecuteOvernightReversal"))
   {
      Print(" Virada overnight cancelada por limite de drawdown.");
      return false;
   }

   if(closedWasReversal)
   {
      Print(" Virada overnight ignorada: operacao fechada ja era turnof");
      return false;
   }

   if(closedWasPCM)
   {
      Print(" Virada overnight ignorada: operacao fechada era PCM (PCM nao permite turnof).");
      return false;
   }

   if(g_currentTicket != 0 || g_pendingOrderPlaced)
   {
      Print(" Virada overnight ignorada: ja existe operacao ativa/pendente no ciclo atual");
      return false;
   }

   TryRearmReversalBlockForNewDay();
   if(!IsReversalAllowedByEntryHourNow())
   {
      MarkReversalBlockedByEntryHour();
      Print(" Virada overnight cancelada - Horario limite atingido e virada apos limite desabilitada.");
      return false;
   }

   if(g_preArmedReversalOrderTicket > 0)
      CancelPreArmedReversalOrder("execucao direta da virada overnight");

   if(channelRange <= 0.0)
   {
      Print(" Virada overnight cancelada - Channel range invalido: ", channelRange);
      return false;
   }

   ENUM_ORDER_TYPE reversalType = (closedOrderType == ORDER_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   if(!IsTradingAllowedForOrder(reversalType, "TryExecuteOvernightReversal"))
      return false;
   double price = (reversalType == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double baseMultiplier = isSliced ? SlicedMultiplier : ReversalMultiplier;
   double slFactor = (ReversalSLDistanceFactor > 0.0) ? ReversalSLDistanceFactor : 1.0;
   double tpFactor = (ReversalTPDistanceFactor > 0.0) ? ReversalTPDistanceFactor : 1.0;
   double slDistance = baseMultiplier * slFactor * channelRange;
   double tpDistance = baseMultiplier * tpFactor * channelRange;
   if(slDistance <= 0.0 || tpDistance <= 0.0)
   {
      Print(" Virada overnight cancelada - Distancia invalida: sl=", slDistance, " tp=", tpDistance);
      return false;
   }

   double stopLossBase = (reversalType == ORDER_TYPE_BUY) ? price - slDistance : price + slDistance;
   double slIncrement = slDistance * (StopLossIncrement / 100.0);
   double stopLoss = (reversalType == ORDER_TYPE_BUY) ? stopLossBase - slIncrement : stopLossBase + slIncrement;
   double takeProfit = (reversalType == ORDER_TYPE_BUY) ? price + tpDistance : price - tpDistance;

   double lotSize = 0.0;
   if(IsFixedLotAllEntriesEnabled())
      lotSize = ResolveFixedLotAllEntries();
   else
   {
      lotSize = (lotSizeSnapshot > 0.0) ? lotSizeSnapshot : g_firstTradeLotSize;
      lotSize = NormalizeLot(lotSize);
   }
   if(lotSize <= 0.0)
   {
      Print(" Virada overnight cancelada - Lote invalido: ", lotSize);
      return false;
   }

   stopLoss = NormalizePriceToTick(stopLoss);
   takeProfit = NormalizePriceToTick(takeProfit);
   if(!ValidateOrderProtectionLevels(reversalType, price, stopLoss, takeProfit, "TryExecuteOvernightReversal"))
      return false;
   datetime reversalEntryTime = TimeCurrent();
   int resolvedChainId = sourceOperationChainId;
   if(resolvedChainId <= 0)
      resolvedChainId = g_lastClosedOvernightChainIdHint;
   if(resolvedChainId <= 0)
      resolvedChainId = g_overnightChainId;
   if(resolvedChainId <= 0)
      resolvedChainId = g_currentOperationChainId;
   if(resolvedChainId <= 0)
      resolvedChainId = NextOperationChainId();

   if(ShouldUseLimitForOvernightReversal())
   {
      if(AllowTradeWithOvernight)
         g_overnightChainId = resolvedChainId;
      else
         AdoptOperationChainId(resolvedChainId);

      PlaceLimitOrder(reversalType,
                      stopLoss,
                      takeProfit,
                      "Virada Overnight LIMIT",
                      true,
                      lotSize,
                      PENDING_CONTEXT_OVERNIGHT_REVERSAL,
                      true,
                      isSliced,
                      channelDefinitionTime,
                      reversalEntryTime,
                      AllowTradeWithOvernight,
                      channelRange);
      if(g_pendingOrderPlaced && g_currentTicket > 0)
      {
         if(AllowTradeWithOvernight)
            Print(" Virada overnight enviada como LIMIT sem consumir entrada diaria. Ticket: ", g_currentTicket);
         else
            Print(" Virada overnight enviada como LIMIT. Ticket: ", g_currentTicket);
         return true;
      }

      if(!AllowMarketFallbackOvernightReversal)
      {
         Print(" Virada overnight LIMIT falhou e fallback a mercado esta desabilitado.");
         return false;
      }

      Print(" WARN: virada overnight LIMIT falhou; aplicando fallback a mercado.");
   }

   bool result = false;
   datetime requestTime = TimeCurrent();
   if(reversalType == ORDER_TYPE_BUY)
      result = trade.Buy(lotSize, _Symbol, 0, stopLoss, takeProfit, "Virada Overnight");
   else
      result = trade.Sell(lotSize, _Symbol, 0, stopLoss, takeProfit, "Virada Overnight");

   long retcode = trade.ResultRetcode();
   if(result && IsTradeRetcodeAccepted(retcode, true))
   {
      ulong reversalTicket = 0;
      if(!TryResolvePositionTicketFromTradeResult(reversalType, requestTime, reversalTicket))
      {
         reversalTicket = trade.ResultOrder();
         Print("WARN: virada overnight aceita, mas ticket da posicao nao confirmado imediatamente. fallback=", reversalTicket);
      }

      // Quando permitido operar com overnight, a virada overnight nao deve consumir
      // o ciclo diario (primeira entrada/virada do dia).
      if(AllowTradeWithOvernight)
      {
         g_overnightTicket = reversalTicket;
         g_overnightEntryTime = reversalEntryTime;
         g_overnightEntryPrice = price;
         g_overnightStopLoss = stopLoss;
         g_overnightTakeProfit = takeProfit;
         g_overnightChannelRange = channelRange;
         g_overnightLotSize = lotSize;
         g_overnightSliced = isSliced;
         g_overnightReversal = true;
         g_overnightPCM = false;
         g_overnightOrderType = reversalType;
         g_overnightChannelDefinitionTime = channelDefinitionTime;
         g_overnightEntryExecutionType = "MARKET";
         g_overnightTriggerTime = reversalEntryTime;
         g_overnightMaxFloatingProfit = 0;
         g_overnightMaxFloatingDrawdown = 0;
         g_overnightMaxAdverseToSLPercent = 0;
         g_overnightMaxFavorableToTPPercent = 0;
         g_overnightChainId = resolvedChainId;

         AddOvernightLogSnapshot(g_overnightTicket,
                                 g_overnightEntryTime,
                                 g_overnightEntryPrice,
                                 g_overnightStopLoss,
                                 g_overnightTakeProfit,
                                 g_overnightSliced,
                                 g_overnightReversal,
                                 g_overnightPCM,
                                 g_overnightOrderType,
                                 g_overnightChannelDefinitionTime,
                                 g_overnightEntryExecutionType,
                                 g_overnightTriggerTime,
                                 g_overnightMaxFloatingProfit,
                                 g_overnightMaxFloatingDrawdown,
                                 g_overnightMaxAdverseToSLPercent,
                                 g_overnightMaxFavorableToTPPercent,
                                 g_overnightChannelRange,
                                 g_overnightLotSize,
                                 g_overnightChainId);

         // Garante ciclo diario limpo para permitir a entrada normal do dia.
         ClearCurrentTradePositionTickets();
         ResetNegativeAddState();
         ResetCurrentTradeFloatingMetrics();
         g_lastClosedOvernightChainIdHint = 0;

         Print(" Virada overnight executada sem consumir entrada diaria! Ticket: ", g_overnightTicket);
         return true;
      }

      // Com AllowTradeWithOvernight = false, mantem comportamento original.
      g_currentTicket = reversalTicket;
      ClearCurrentTradePositionTickets();
      TrackCurrentTradePositionTicket(g_currentTicket);
      g_currentOrderType = reversalType;
      g_firstTradeLotSize = lotSize;
      g_firstTradeStopLoss = stopLoss;
      g_firstTradeTakeProfit = takeProfit;
      g_firstTradeExecuted = true;
      g_reversalTradeExecuted = true;
      g_channelRange = channelRange;
      g_tradeEntryTime = reversalEntryTime;
      g_tradeEntryPrice = price;
      g_tradeReversal = true;
      g_tradePCM = false;
      g_tradeSliced = isSliced;
      g_tradeChannelDefinitionTime = channelDefinitionTime;
      g_tradeEntryExecutionType = "MARKET";
      g_tradeTriggerTime = reversalEntryTime;
      AdoptOperationChainId(resolvedChainId);
      ResetNegativeAddState();
      ResetCurrentTradeFloatingMetrics();
      if(ShouldUseLimitForNegativeAddOn() && g_negativeAddRuntimeEnabled)
         PlaceNegativeAddOnLimitOrdersForStrictMode(g_tradeEntryPrice);
      g_lastClosedOvernightChainIdHint = 0;

      Print(" Virada overnight executada! Ticket: ", g_currentTicket);
      return true;
   }

   Print(" Erro na virada overnight: ", retcode, " - ", trade.ResultRetcodeDescription());
   return false;
}

//+------------------------------------------------------------------+
//| Reset diario                                                      |
//+------------------------------------------------------------------+
void ResetDaily()
{
   Print(" === Novo dia - Reset ===");
   UpdateDrawdownMetrics();
   g_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_cachedDailyDrawdownPercent = 0.0;
   g_cachedDailyDrawdownAmount = 0.0;
   ResetPCMStateForNewDay();

   // PRIMEIRO: Verificar se ha posicao overnight ANTES de mover tickets
   bool hasAnyOvernight = false;

   // Se tem posicao aberta overnight
   if(g_currentTicket > 0 && PositionSelectByTicket(g_currentTicket))
   {
      hasAnyOvernight = true;
      Print(" Posicao overnight detectada - Ticket: ", g_currentTicket);
      Print("  Tipo: ", EnumToString(g_currentOrderType), " | SL: ", g_firstTradeStopLoss, " | TP: ", g_firstTradeTakeProfit);
      Print(" Preservando flags: is_reversal=", g_tradeReversal, " | is_sliced=", g_tradeSliced);

      if(!AllowTradeWithOvernight && KeepPositionsOvernight)
      {
         Print(" Novas operacoes bloqueadas (AllowTradeWithOvernight = false)");

         // Resetar apenas canais, manter controles de operacao bloqueados
         ObjectsDeleteAll(0, "Channel_");
         g_channelCalculated = false;
         g_channelValid = false;
         g_channelHigh = 0;
         g_channelLow = 0;
         g_channelDefinitionTime = 0;
         g_projectedHigh = 0;
         g_projectedLow = 0;
         g_cycle1Defined = false;
         g_cycle1Direction = "";
         g_cycle1High = 0;
         g_cycle1Low = 0;
         g_lastResetTime = TimeCurrent();
         return;
      }

      Print(" Fluxo de overnight ativo para controle de posicoes");

      if(EnableOvernightReversal && !g_tradeReversal && !g_tradePCM && g_preArmedReversalOrderTicket == 0)
      {
         EnsurePreArmedReversalForCurrentTrade();
      }

      // Mover ticket atual para overnight e liberar para novas operacoes
      g_overnightTicket = g_currentTicket;
      g_overnightEntryTime = g_tradeEntryTime;
      g_overnightEntryPrice = g_tradeEntryPrice;
      g_overnightStopLoss = g_firstTradeStopLoss;
      g_overnightTakeProfit = g_firstTradeTakeProfit;
      g_overnightChannelRange = g_channelRange;
      g_overnightLotSize = g_firstTradeLotSize;
      g_overnightSliced = g_tradeSliced;
      g_overnightReversal = g_tradeReversal;
      g_overnightPCM = g_tradePCM;
      g_overnightOrderType = g_currentOrderType;
      g_overnightChannelDefinitionTime = g_tradeChannelDefinitionTime;
      g_overnightEntryExecutionType = g_tradeEntryExecutionType;
      g_overnightTriggerTime = g_tradeTriggerTime;
      g_overnightMaxFloatingProfit = g_tradeMaxFloatingProfit;
      g_overnightMaxFloatingDrawdown = g_tradeMaxFloatingDrawdown;
      g_overnightMaxAdverseToSLPercent = g_tradeMaxAdverseToSLPercent;
      g_overnightMaxFavorableToTPPercent = g_tradeMaxFavorableToTPPercent;
      g_overnightChainId = g_currentOperationChainId;
      if(g_overnightChainId <= 0)
         g_overnightChainId = ResolveOperationChainIdForLog(g_tradeEntryTime);

      // Snapshot do ticket principal.
      AddOvernightLogSnapshot(g_overnightTicket,
                              g_overnightEntryTime,
                              g_overnightEntryPrice,
                              g_overnightStopLoss,
                              g_overnightTakeProfit,
                              g_overnightSliced,
                              g_overnightReversal,
                              g_overnightPCM,
                              g_overnightOrderType,
                              g_overnightChannelDefinitionTime,
                              g_overnightEntryExecutionType,
                              g_overnightTriggerTime,
                              g_overnightMaxFloatingProfit,
                              g_overnightMaxFloatingDrawdown,
                              g_overnightMaxAdverseToSLPercent,
                              g_overnightMaxFavorableToTPPercent,
                              g_overnightChannelRange,
                              g_overnightLotSize,
                              g_overnightChainId);

      // Snapshot adicional para todos os tickets ativos da operacao (hedging/addon).
      ulong overnightActiveTickets[];
      double overnightVolume = 0.0;
      double overnightWeightedEntry = 0.0;
      double overnightFloating = 0.0;
      int overnightActiveCount = CollectActiveCurrentTradePositions(overnightActiveTickets, overnightVolume, overnightWeightedEntry, overnightFloating);
      for(int i = 0; i < overnightActiveCount; i++)
      {
         ulong t = overnightActiveTickets[i];
         if(t == 0)
            continue;

         datetime snapshotEntryTime = g_overnightEntryTime;
         double snapshotEntryPrice = g_overnightEntryPrice;
         if(PositionSelectByTicket(t))
         {
            snapshotEntryTime = (datetime)PositionGetInteger(POSITION_TIME);
            snapshotEntryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         }

         AddOvernightLogSnapshot(t,
                                 snapshotEntryTime,
                                 snapshotEntryPrice,
                                 g_overnightStopLoss,
                                 g_overnightTakeProfit,
                                 g_overnightSliced,
                                 g_overnightReversal,
                                 g_overnightPCM,
                                 g_overnightOrderType,
                                 g_overnightChannelDefinitionTime,
                                 g_overnightEntryExecutionType,
                                 g_overnightTriggerTime,
                                 g_overnightMaxFloatingProfit,
                                 g_overnightMaxFloatingDrawdown,
                                 g_overnightMaxAdverseToSLPercent,
                                 g_overnightMaxFavorableToTPPercent,
                                 g_overnightChannelRange,
                                 g_overnightLotSize,
                                 g_overnightChainId);
      }
      g_currentTicket = 0;
      ClearCurrentTradePositionTickets();
      g_currentOperationChainId = 0;
   }

   // Verificar se ja tinha overnight anterior
   if(g_overnightTicket > 0 && PositionSelectByTicket(g_overnightTicket))
   {
      hasAnyOvernight = true;
   }

   // Reset completo para permitir novas operacoes no novo dia
   ObjectsDeleteAll(0, "Channel_");
   g_channelCalculated = false;
   g_channelValid = false;
   g_firstTradeExecuted = false;
   g_reversalTradeExecuted = false;
   g_channelHigh = 0;
   g_channelLow = 0;
   g_channelRange = 0;
   g_channelDefinitionTime = 0;
   g_projectedHigh = 0;
   g_projectedLow = 0;
   g_cycle1Defined = false;
   g_cycle1Direction = "";
   g_cycle1High = 0;
   g_cycle1Low = 0;
   g_pendingOrderPlaced = false;
   g_usingM15 = false;
   g_activeTimeframe = ChannelTimeframe;
   g_lastResetTime = TimeCurrent();

   // Resetar flags de logging APENAS se nao houver posicao overnight
   if(!hasAnyOvernight)
   {
      CancelPreArmedReversalOrder("reset diario sem overnight");
      ClearCurrentTradePositionTickets();
      g_tradeEntryTime = 0;
      g_tradeEntryPrice = 0;
      g_tradeSliced = false;
      g_tradeReversal = false;
      g_tradePCM = false;
      g_tradeChannelDefinitionTime = 0;
      g_tradeEntryExecutionType = "";
      g_tradeTriggerTime = 0;
      g_currentOperationChainId = 0;
      ResetReversalHourBlockState();
      ResetNegativeAddState();
      ResetCurrentTradeFloatingMetrics();
      g_overnightEntryTime = 0;
      g_overnightEntryPrice = 0;
      g_overnightStopLoss = 0;
      g_overnightTakeProfit = 0;
      g_overnightChannelRange = 0;
      g_overnightLotSize = 0;
      g_overnightSliced = false;
      g_overnightReversal = false;
      g_overnightPCM = false;
      g_overnightOrderType = ORDER_TYPE_BUY;
      g_overnightChannelDefinitionTime = 0;
      g_overnightEntryExecutionType = "";
      g_overnightTriggerTime = 0;
      g_overnightMaxFloatingProfit = 0;
      g_overnightMaxFloatingDrawdown = 0;
      g_overnightMaxAdverseToSLPercent = 0;
      g_overnightMaxFavorableToTPPercent = 0;
      g_overnightChainId = 0;
      ClearOvernightLogSnapshots();
      Print(" Flags de logging resetadas (sem overnight)");
   }
   else
   {
      Print(" Flags de logging PRESERVADAS para overnight (is_reversal=", g_tradeReversal, ")");
   }
}



//+------------------------------------------------------------------+
//| Salva logs em arquivo JSON                                       |
//+------------------------------------------------------------------+
string FormatTimestamp(datetime ts)
{
   if(ts <= 0)
      return "00000000_000000";

   MqlDateTime dt;
   TimeToStruct(ts, dt);
   return StringFormat("%04d%02d%02d_%02d%02d%02d", dt.year, dt.mon, dt.day, dt.hour, dt.min, dt.sec);
}

string BoolToJson(bool value)
{
   return (value ? "true" : "false");
}

string BuildUniqueFileName(string baseName, string extension)
{
   string candidate = baseName + extension;
   int suffix = 1;

   while(FileIsExist(candidate))
   {
      candidate = baseName + "_run_" + IntegerToString(suffix) + extension;
      suffix++;
      if(suffix > 100000)
         break;
   }

   return candidate;
}

string BuildTickDrawdownJson()
{
   double maxFloating = MaxTickDrawdownArray(g_tickDDDailyMaxFloating);
   double maxFloatingPercentOfDayBalance = MaxTickDrawdownArray(g_tickDDDailyMaxFloatingPercentOfDayBalance);
   double maxCombined = MaxTickDrawdownArray(g_tickDDDailyMaxCombined);
   double sumDailyFloating = SumTickDrawdownArray(g_tickDDDailyMaxFloating);
   double sumDailyCombined = SumTickDrawdownArray(g_tickDDDailyMaxCombined);
   int daysCount = ArraySize(g_tickDDDailyDateKeys);
   int maxFloatingPositionsInDay = 0;
   int maxFloatingPositionsDayKey = 0;
   datetime maxFloatingPositionsTime = 0;

   for(int i = 0; i < daysCount; i++)
   {
      if(g_tickDDDailyMaxFloatingPositions[i] > maxFloatingPositionsInDay)
      {
         maxFloatingPositionsInDay = g_tickDDDailyMaxFloatingPositions[i];
         maxFloatingPositionsDayKey = g_tickDDDailyDateKeys[i];
         maxFloatingPositionsTime = g_tickDDDailyMaxFloatingPositionsTimes[i];
      }
   }

   string maxFloatingPositionsDayText = DateKeyToString(maxFloatingPositionsDayKey);
   string maxFloatingPositionsTimeText = "";
   if(maxFloatingPositionsTime > 0)
      maxFloatingPositionsTimeText = TimeToString(maxFloatingPositionsTime, TIME_DATE|TIME_SECONDS);

   string json = "  \"tick_drawdown\": {\n";
   json += "    \"summary\": {\n";
   json += "      \"days_count\": " + IntegerToString(daysCount) + ",\n";
   json += "      \"max_intraday_floating_dd\": " + DoubleToString(maxFloating, 2) + ",\n";
   json += "      \"max_intraday_floating_dd_percent_of_day_balance\": " + DoubleToString(maxFloatingPercentOfDayBalance, 2) + ",\n";
   json += "      \"max_intraday_floating_dd_with_limit_risk\": " + DoubleToString(maxCombined, 2) + ",\n";
   json += "      \"max_intraday_dd_plus_limit\": " + DoubleToString(maxCombined, 2) + ",\n";
   json += "      \"sum_daily_max_floating_dd\": " + DoubleToString(sumDailyFloating, 2) + ",\n";
   json += "      \"sum_daily_max_floating_dd_with_limit_risk\": " + DoubleToString(sumDailyCombined, 2) + ",\n";
   json += "      \"sum_daily_max_dd_plus_limit\": " + DoubleToString(sumDailyCombined, 2) + ",\n";
   json += "      \"max_floating_positions_in_day\": " + IntegerToString(maxFloatingPositionsInDay) + ",\n";
   json += "      \"max_floating_positions_day\": \"" + maxFloatingPositionsDayText + "\",\n";
   json += "      \"max_floating_positions_time\": \"" + maxFloatingPositionsTimeText + "\"\n";
   json += "    },\n";
   json += "    \"daily\": [";

   if(daysCount > 0)
      json += "\n";

   for(int i = 0; i < daysCount; i++)
   {
      string dateText = DateKeyToString(g_tickDDDailyDateKeys[i]);
      string floatingTimeText = "";
      string pendingTimeText = "";
      string combinedTimeText = "";
      string floatingPositionsTimeText = "";

      if(g_tickDDDailyMaxFloatingTimes[i] > 0)
         floatingTimeText = TimeToString(g_tickDDDailyMaxFloatingTimes[i], TIME_DATE|TIME_SECONDS);
      if(g_tickDDDailyMaxPendingLimitRiskTimes[i] > 0)
         pendingTimeText = TimeToString(g_tickDDDailyMaxPendingLimitRiskTimes[i], TIME_DATE|TIME_SECONDS);
      if(g_tickDDDailyMaxCombinedTimes[i] > 0)
         combinedTimeText = TimeToString(g_tickDDDailyMaxCombinedTimes[i], TIME_DATE|TIME_SECONDS);
      if(g_tickDDDailyMaxFloatingPositionsTimes[i] > 0)
         floatingPositionsTimeText = TimeToString(g_tickDDDailyMaxFloatingPositionsTimes[i], TIME_DATE|TIME_SECONDS);

      json += "      {\n";
      json += "        \"date\": \"" + dateText + "\",\n";
      json += "        \"day_start_balance\": " + DoubleToString(g_tickDDDailyDayStartBalances[i], 2) + ",\n";
      json += "        \"max_floating_dd\": " + DoubleToString(g_tickDDDailyMaxFloating[i], 2) + ",\n";
      json += "        \"max_floating_dd_percent_of_day_balance\": " + DoubleToString(g_tickDDDailyMaxFloatingPercentOfDayBalance[i], 2) + ",\n";
      json += "        \"max_floating_dd_time\": \"" + floatingTimeText + "\",\n";
      json += "        \"max_pending_limit_risk\": " + DoubleToString(g_tickDDDailyMaxPendingLimitRisk[i], 2) + ",\n";
      json += "        \"max_pending_limit_risk_time\": \"" + pendingTimeText + "\",\n";
      json += "        \"max_combined_dd\": " + DoubleToString(g_tickDDDailyMaxCombined[i], 2) + ",\n";
      json += "        \"max_dd_plus_limit\": " + DoubleToString(g_tickDDDailyMaxCombined[i], 2) + ",\n";
      json += "        \"max_combined_dd_time\": \"" + combinedTimeText + "\",\n";
      json += "        \"max_dd_plus_limit_time\": \"" + combinedTimeText + "\",\n";
      json += "        \"pending_limit_count_at_combined_peak\": " + IntegerToString(g_tickDDDailyPendingLimitCountAtCombinedPeak[i]) + ",\n";
      json += "        \"max_floating_positions\": " + IntegerToString(g_tickDDDailyMaxFloatingPositions[i]) + ",\n";
      json += "        \"max_floating_positions_time\": \"" + floatingPositionsTimeText + "\"\n";
      json += "      }";

      if(i < daysCount - 1)
         json += ",\n";
      else
         json += "\n";
   }

   json += "    ]\n";
   json += "  }";
   return json;
}

string BuildRunConfigJson(datetime startTime, datetime endTime)
{
   string cfg = "  \"run_config\": {\n";
   cfg += "    \"symbol\": \"" + _Symbol + "\",\n";
   cfg += "    \"start_time\": \"" + TimeToString(startTime, TIME_DATE|TIME_MINUTES) + "\",\n";
   cfg += "    \"end_time\": \"" + TimeToString(endTime, TIME_DATE|TIME_MINUTES) + "\",\n";
   cfg += "    \"selected_parameters\": {\n";
   cfg += "      \"OpeningHour\": " + IntegerToString(OpeningHour) + ",\n";
   cfg += "      \"OpeningMinute\": " + IntegerToString(OpeningMinute) + ",\n";
   cfg += "      \"FirstEntryMaxHour\": " + IntegerToString(FirstEntryMaxHour) + ",\n";
   cfg += "      \"RiskPercent\": " + DoubleToString(RiskPercent, 2) + ",\n";
   cfg += "      \"UseInitialDepositForRisk\": " + BoolToJson(UseInitialDepositForRisk) + ",\n";
   cfg += "      \"FixedLotAllEntries\": " + DoubleToString(FixedLotAllEntries, 2) + ",\n";
   cfg += "      \"MinChannelRange\": " + DoubleToString(MinChannelRange, 2) + ",\n";
   cfg += "      \"MaxChannelRange\": " + DoubleToString(MaxChannelRange, 2) + ",\n";
   cfg += "      \"SlicedThreshold\": " + DoubleToString(SlicedThreshold, 2) + ",\n";
   cfg += "      \"BreakoutMinTolerancePoints\": " + DoubleToString(BreakoutMinTolerancePoints, 2) + ",\n";
   cfg += "      \"SlicedMultiplier\": " + DoubleToString(SlicedMultiplier, 2) + ",\n";
   cfg += "      \"EnableM15Fallback\": " + BoolToJson(EnableM15Fallback) + ",\n";
   cfg += "      \"MaxEntryHour\": " + IntegerToString(MaxEntryHour) + ",\n";
   cfg += "      \"TPMultiplier\": " + DoubleToString(TPMultiplier, 2) + ",\n";
   cfg += "      \"TPReductionPercent\": " + DoubleToString(TPReductionPercent, 2) + ",\n";
   cfg += "      \"StopLossIncrement\": " + DoubleToString(StopLossIncrement, 2) + ",\n";
   cfg += "      \"MinRiskReward\": " + DoubleToString(MinRiskReward, 2) + ",\n";
   cfg += "      \"MaxDailyDrawdownPercent\": " + DoubleToString(MaxDailyDrawdownPercent, 2) + ",\n";
   cfg += "      \"MaxDrawdownPercent\": " + DoubleToString(MaxDrawdownPercent, 2) + ",\n";
   cfg += "      \"MaxDailyDrawdownAmount\": " + DoubleToString(MaxDailyDrawdownAmount, 2) + ",\n";
   cfg += "      \"MaxDrawdownAmount\": " + DoubleToString(MaxDrawdownAmount, 2) + ",\n";
   cfg += "      \"EnableNegativeAddOn\": " + BoolToJson(EnableNegativeAddOn) + ",\n";
   cfg += "      \"NegativeAddMaxEntries\": " + IntegerToString(NegativeAddMaxEntries) + ",\n";
   cfg += "      \"NegativeAddTriggerPercent\": " + DoubleToString(NegativeAddTriggerPercent, 2) + ",\n";
   cfg += "      \"NegativeAddLotMultiplier\": " + DoubleToString(NegativeAddLotMultiplier, 2) + ",\n";
   cfg += "      \"NegativeAddUseSameSLTP\": " + BoolToJson(NegativeAddUseSameSLTP) + ",\n";
   cfg += "      \"EnableNegativeAddTPAdjustment\": " + BoolToJson(EnableNegativeAddTPAdjustment) + ",\n";
   cfg += "      \"NegativeAddTPDistancePercent\": " + DoubleToString(NegativeAddTPDistancePercent, 2) + ",\n";
   cfg += "      \"NegativeAddTPAdjustOnReversal\": " + BoolToJson(NegativeAddTPAdjustOnReversal) + ",\n";
   cfg += "      \"EnableNegativeAddDebugLogs\": " + BoolToJson(EnableNegativeAddDebugLogs) + ",\n";
   cfg += "      \"NegativeAddDebugIntervalSeconds\": " + IntegerToString(NegativeAddDebugIntervalSeconds) + ",\n";
   cfg += "      \"EnableReversal\": " + BoolToJson(EnableReversal) + ",\n";
   cfg += "      \"EnableOvernightReversal\": " + BoolToJson(EnableOvernightReversal) + ",\n";
   cfg += "      \"ReversalMultiplier\": " + DoubleToString(ReversalMultiplier, 2) + ",\n";
   cfg += "      \"ReversalSLDistanceFactor\": " + DoubleToString(ReversalSLDistanceFactor, 2) + ",\n";
   cfg += "      \"ReversalTPDistanceFactor\": " + DoubleToString(ReversalTPDistanceFactor, 2) + ",\n";
   cfg += "      \"AllowReversalAfterMaxEntryHour\": " + BoolToJson(AllowReversalAfterMaxEntryHour) + ",\n";
   cfg += "      \"RearmCanceledReversalNextDay\": " + BoolToJson(RearmCanceledReversalNextDay) + ",\n";
   cfg += "      \"EnablePCM\": " + BoolToJson(EnablePCM) + ",\n";
   cfg += "      \"EnablePCMOnNoTradeLimitTarget\": " + BoolToJson(EnablePCMOnNoTradeLimitTarget) + ",\n";
   cfg += "      \"BreakEven\": " + BoolToJson(BreakEven) + ",\n";
   cfg += "      \"TraillingStop\": " + BoolToJson(TraillingStop) + ",\n";
   cfg += "      \"PCMTPReductionPercent\": " + DoubleToString(PCMTPReductionPercent, 2) + ",\n";
   cfg += "      \"PCMRiskPercent\": " + DoubleToString(PCMRiskPercent, 2) + ",\n";
   cfg += "      \"PCMChannelBars\": " + IntegerToString(PCMChannelBars) + ",\n";
   cfg += "      \"PCMMaxOperationsPerDay\": " + IntegerToString(PCMMaxOperationsPerDay) + ",\n";
   cfg += "      \"PCMIgnoreFirstEntryMaxHour\": " + BoolToJson(PCMIgnoreFirstEntryMaxHour) + ",\n";
   cfg += "      \"PCMReferenceTimeframe\": \"" + EnumToString(PCMReferenceTimeframe) + "\",\n";
   cfg += "      \"PCMEnableSkipLargeCandle\": " + BoolToJson(PCMEnableSkipLargeCandle) + ",\n";
   cfg += "      \"PCMMaxCandlePoints\": " + DoubleToString(PCMMaxCandlePoints, 2) + ",\n";
   cfg += "      \"EnablePCMHourLimit\": " + BoolToJson(EnablePCMHourLimit) + ",\n";
   cfg += "      \"PCMEntryMaxHour\": " + IntegerToString(PCMEntryMaxHour) + ",\n";
   cfg += "      \"PCMEntryMaxMinute\": " + IntegerToString(PCMEntryMaxMinute) + ",\n";
   cfg += "      \"AllowTradeWithOvernight\": " + BoolToJson(AllowTradeWithOvernight) + ",\n";
   cfg += "      \"KeepPositionsOvernight\": " + BoolToJson(KeepPositionsOvernight) + ",\n";
   cfg += "      \"CloseMinutesBeforeMarketClose\": " + IntegerToString(CloseMinutesBeforeMarketClose) + ",\n";
   cfg += "      \"StrictLimitOnly\": " + BoolToJson(StrictLimitOnly) + ",\n";
   cfg += "      \"PreferLimitMainEntry\": " + BoolToJson(PreferLimitMainEntry) + ",\n";
   cfg += "      \"PreferLimitReversal\": " + BoolToJson(PreferLimitReversal) + ",\n";
   cfg += "      \"PreferLimitOvernightReversal\": " + BoolToJson(PreferLimitOvernightReversal) + ",\n";
   cfg += "      \"PreferLimitNegativeAddOn\": " + BoolToJson(PreferLimitNegativeAddOn) + ",\n";
   cfg += "      \"AllowMarketFallbackReversal\": " + BoolToJson(AllowMarketFallbackReversal) + ",\n";
   cfg += "      \"AllowMarketFallbackOvernightReversal\": " + BoolToJson(AllowMarketFallbackOvernightReversal) + ",\n";
   cfg += "      \"ChannelTimeframe\": \"" + EnumToString(ChannelTimeframe) + "\",\n";
   cfg += "      \"DrawChannels\": " + BoolToJson(DrawChannels) + ",\n";
   cfg += "      \"EnableLogging\": " + BoolToJson(EnableLogging) + ",\n";
   cfg += "      \"MagicNumber\": " + StringFormat("%I64u", MagicNumber) + "\n";
   cfg += "    }\n";
   cfg += "  }";
   return cfg;
}

void SaveLogs()
{
   if(!EnableLogging) return;

   datetime endTime = TimeCurrent();
   datetime startTime = g_backtestStartTime;
   if(startTime <= 0)
      startTime = endTime;

   FinalizeTickDrawdownCurrentDay();

   string runTimestamp = "start_" + FormatTimestamp(startTime) + "_end_" + FormatTimestamp(endTime);
   string saveTimestamp = "saved_" + FormatTimestamp(TimeLocal());

   // Obter caminho completo
   string terminalPath = TerminalInfoString(TERMINAL_DATA_PATH);
   string filesPath = terminalPath + "\\MQL5\\Files\\";

   Print("=== SALVANDO LOGS ===");
   Print("Caminho completo: ", filesPath);

   // Salvar arquivo de trades
   if(StringLen(g_tradesLog) > 15)
   {
      int tradesLen = StringLen(g_tradesLog);
      if(tradesLen >= 2)
      {
         StringSetCharacter(g_tradesLog, tradesLen-2, ' '); // remove trailing comma
         StringSetCharacter(g_tradesLog, tradesLen-1, ' '); // remove trailing newline
      }
      g_tradesLog += "],\n";
      g_tradesLog += BuildTickDrawdownJson();
      g_tradesLog += ",\n";
      g_tradesLog += BuildRunConfigJson(startTime, endTime);
      g_tradesLog += "\n}";

      string tradesBase = g_programName + "_Trades_" + _Symbol + "_" + runTimestamp + "_" + saveTimestamp;
      string tradesFile = BuildUniqueFileName(tradesBase, ".json");
      int handle = FileOpen(tradesFile, FILE_WRITE|FILE_TXT|FILE_ANSI);
      if(handle != INVALID_HANDLE)
      {
         FileWriteString(handle, g_tradesLog);
         FileClose(handle);
         Print(" Trades salvo: ", filesPath + tradesFile);
      }
      else
         Print(" Erro ao salvar trades: ", GetLastError());
   }
   else
   {
      Print(" Nenhum trade para salvar");
   }

   // Salvar arquivo de dias sem trade
   if(StringLen(g_noTradesLog) > 22)
   {
      int noTradesLen = StringLen(g_noTradesLog);
      if(noTradesLen >= 2)
      {
         StringSetCharacter(g_noTradesLog, noTradesLen-2, ' '); // remove trailing comma
         StringSetCharacter(g_noTradesLog, noTradesLen-1, ' '); // remove trailing newline
      }
      g_noTradesLog += "],\n";
      g_noTradesLog += BuildTickDrawdownJson();
      g_noTradesLog += ",\n";
      g_noTradesLog += BuildRunConfigJson(startTime, endTime);
      g_noTradesLog += "\n}";

      string noTradesBase = g_programName + "_NoTrades_" + _Symbol + "_" + runTimestamp + "_" + saveTimestamp;
      string noTradesFile = BuildUniqueFileName(noTradesBase, ".json");
      int handle = FileOpen(noTradesFile, FILE_WRITE|FILE_TXT|FILE_ANSI);
      if(handle != INVALID_HANDLE)
      {
         FileWriteString(handle, g_noTradesLog);
         FileClose(handle);
         Print(" NoTrades salvo: ", filesPath + noTradesFile);
      }
      else
         Print(" Erro ao salvar no-trades: ", GetLastError());
   }
   else
   {
      Print(" Nenhum dia sem trade para salvar");
   }
}

//+------------------------------------------------------------------+
//| Registra operacao no log                                         |
//+------------------------------------------------------------------+
void LogTrade(datetime exitTime,
              double exitPrice,
              double profit,
              bool hitTP,
              int addOnCountOverride = -1,
              double addOnLotsOverride = -1.0,
              double addOnAvgEntryPriceOverride = 0.0,
              double addOnProfitOverride = 0.0,
              int isAddOperationOverride = -1,
              double grossProfitOverride = 0.0,
              double swapOverride = 0.0,
              double commissionOverride = 0.0,
              double feeOverride = 0.0,
              bool hasFinancialBreakdownOverride = false)
{
   if(!EnableLogging) return;

   double riskReward = 0;
   if(g_firstTradeStopLoss != 0)
   {
      double slDist = MathAbs(g_tradeEntryPrice - g_firstTradeStopLoss);
      double tpDist = MathAbs(g_firstTradeTakeProfit - g_tradeEntryPrice);
      if(slDist > 0) riskReward = tpDist / slDist;
   }

   string channelDefinitionTimeText = "";
   if(g_tradeChannelDefinitionTime > 0)
      channelDefinitionTimeText = TimeToString(g_tradeChannelDefinitionTime, TIME_DATE|TIME_MINUTES);
   ENUM_TIMEFRAMES tradeLogTimeframe = g_tradePCM ? g_pcmActiveTimeframe : g_activeTimeframe;

   string entryExecutionType = g_tradeEntryExecutionType;
   if(entryExecutionType == "")
      entryExecutionType = "MARKET";

   string triggerTimeText = "";
   if(g_tradeTriggerTime > 0)
      triggerTimeText = TimeToString(g_tradeTriggerTime, TIME_DATE|TIME_MINUTES);

   double maxFloatingProfit = g_tradeMaxFloatingProfit;
   double maxFloatingDrawdown = g_tradeMaxFloatingDrawdown;
   double maxAdverseToSLPercent = g_tradeMaxAdverseToSLPercent;
   double maxFavorableToTPPercent = g_tradeMaxFavorableToTPPercent;
   if(profit > maxFloatingProfit)
      maxFloatingProfit = profit;
   if(profit < maxFloatingDrawdown)
      maxFloatingDrawdown = profit;
   if(maxAdverseToSLPercent <= 0.0 && g_tradeEntryPrice > 0.0 && g_firstTradeStopLoss > 0.0)
   {
      double riskDistance = MathAbs(g_tradeEntryPrice - g_firstTradeStopLoss);
      if(riskDistance > 0.0)
      {
         double adverseAtExitDistance = (g_currentOrderType == ORDER_TYPE_BUY) ? (g_tradeEntryPrice - exitPrice) : (exitPrice - g_tradeEntryPrice);
         if(adverseAtExitDistance > 0.0)
            maxAdverseToSLPercent = (adverseAtExitDistance / riskDistance) * 100.0;
      }
   }
   if(maxFavorableToTPPercent <= 0.0 && g_tradeEntryPrice > 0.0 && g_firstTradeTakeProfit > 0.0)
   {
      double tpDistance = MathAbs(g_firstTradeTakeProfit - g_tradeEntryPrice);
      if(tpDistance > 0.0)
      {
         double favorableAtExitDistance = (g_currentOrderType == ORDER_TYPE_BUY) ? (exitPrice - g_tradeEntryPrice) : (g_tradeEntryPrice - exitPrice);
         if(favorableAtExitDistance > 0.0)
            maxFavorableToTPPercent = (favorableAtExitDistance / tpDistance) * 100.0;
      }
   }
   if(maxFavorableToTPPercent < 0.0)
      maxFavorableToTPPercent = 0.0;
   else if(maxFavorableToTPPercent > 100.0)
      maxFavorableToTPPercent = 100.0;

   double grossProfit = hasFinancialBreakdownOverride ? grossProfitOverride : profit;
   double swapValue = hasFinancialBreakdownOverride ? swapOverride : 0.0;
   double commissionValue = hasFinancialBreakdownOverride ? commissionOverride : 0.0;
   double feeValue = hasFinancialBreakdownOverride ? feeOverride : 0.0;
   double costsTotal = swapValue + commissionValue + feeValue;
   double netProfit = profit;

   int addOnCount = 0;
   double addOnLots = 0.0;
   double addOnAvgEntryPrice = 0.0;
   double addOnProfit = 0.0;
   if(addOnCountOverride >= 0 && addOnLotsOverride >= 0.0)
   {
      addOnCount = addOnCountOverride;
      addOnLots = addOnLotsOverride;
      addOnAvgEntryPrice = addOnAvgEntryPriceOverride;
      addOnProfit = addOnProfitOverride;
   }
   else
   {
      CollectNegativeAddMetricsCurrentTrade(addOnCount, addOnLots, addOnAvgEntryPrice, addOnProfit);
   }

   int operationChainId = ResolveOperationChainIdForLog(g_tradeEntryTime);
   if(operationChainId > g_operationChainCounter)
      g_operationChainCounter = operationChainId;

   bool isTurnOperation = g_tradeReversal;
   bool isPcmOperation = g_tradePCM;
   bool isAddOperation = (isAddOperationOverride >= 0) ? (isAddOperationOverride == 1) : (addOnCount > 0);
   bool isFirstOperation = (!isTurnOperation && !isAddOperation && !isPcmOperation);
   string operationChainCode = BuildOperationChainCode(operationChainId);
   string operationCode = BuildOperationCode(isTurnOperation, isPcmOperation, operationChainId);
   string addOperationCode = "";
   if(isAddOperation)
   {
      addOperationCode = BuildAddOperationCode(operationChainId);
      operationCode = addOperationCode;
   }

   // Determinar se disparou turnof
   bool triggeredReversal = false;
   if(!hitTP && EnableReversal && !isPcmOperation)
   {
      TryRearmReversalBlockForNewDay();
      if(IsReversalAllowedByEntryHourNow() && !g_reversalBlockedByEntryHour)
      {
         if(isFirstOperation)
            triggeredReversal = true;  // Primeira operacao bateu SL
         else if(isTurnOperation && g_reversalTradeExecuted)
            triggeredReversal = true;  // turnof bateu SL
      }
   }

   bool classifyAsTPByTrailing = (isPcmOperation && !hitTP && g_pcmTraillingStopApplied);
   bool classifyAsBE = (isPcmOperation && !hitTP && !classifyAsTPByTrailing && g_pcmBreakEvenApplied);
   string resultCode = classifyAsTPByTrailing ? "TP" : (classifyAsBE ? "BE" : (hitTP ? "TP" : "SL"));

   string tradeJson = "{\n";
   tradeJson += "  \"date\": \"" + TimeToString(g_tradeEntryTime, TIME_DATE) + "\",\n";
   tradeJson += "  \"entry_time\": \"" + TimeToString(g_tradeEntryTime, TIME_DATE|TIME_MINUTES) + "\",\n";
   tradeJson += "  \"trigger_time\": \"" + triggerTimeText + "\",\n";
   tradeJson += "  \"exit_time\": \"" + TimeToString(exitTime, TIME_DATE|TIME_MINUTES) + "\",\n";
   tradeJson += "  \"direction\": \"" + EnumToString(g_currentOrderType) + "\",\n";
   tradeJson += "  \"entry_price\": " + DoubleToString(g_tradeEntryPrice, 2) + ",\n";
   tradeJson += "  \"exit_price\": " + DoubleToString(exitPrice, 2) + ",\n";
   tradeJson += "  \"stop_loss\": " + DoubleToString(g_firstTradeStopLoss, 2) + ",\n";
   tradeJson += "  \"take_profit\": " + DoubleToString(g_firstTradeTakeProfit, 2) + ",\n";
   tradeJson += "  \"entry_execution_type\": \"" + entryExecutionType + "\",\n";
   tradeJson += "  \"channel_definition_time\": \"" + channelDefinitionTimeText + "\",\n";
   tradeJson += "  \"channel_range\": " + DoubleToString(g_channelRange, 2) + ",\n";
   tradeJson += "  \"is_sliced\": " + (g_tradeSliced ? "true" : "false") + ",\n";
   tradeJson += "  \"is_reversal\": " + (g_tradeReversal ? "true" : "false") + ",\n";
   tradeJson += "  \"triggered_reversal\": " + (triggeredReversal ? "true" : "false") + ",\n";
   tradeJson += "  \"operation_chain_id\": " + IntegerToString(operationChainId) + ",\n";
   tradeJson += "  \"operation_chain_code\": \"" + operationChainCode + "\",\n";
   tradeJson += "  \"operation_code\": \"" + operationCode + "\",\n";
   tradeJson += "  \"is_first_operation\": " + (isFirstOperation ? "true" : "false") + ",\n";
   tradeJson += "  \"is_turn_operation\": " + (isTurnOperation ? "true" : "false") + ",\n";
   tradeJson += "  \"is_pcm_operation\": " + (isPcmOperation ? "true" : "false") + ",\n";
   tradeJson += "  \"is_add_operation\": " + (isAddOperation ? "true" : "false") + ",\n";
   tradeJson += "  \"add_operation_code\": \"" + addOperationCode + "\",\n";
   tradeJson += "  \"timeframe\": \"" + EnumToString(tradeLogTimeframe) + "\",\n";
   tradeJson += "  \"risk_reward\": " + DoubleToString(riskReward, 2) + ",\n";
   tradeJson += "  \"max_adverse_to_sl_percent\": " + DoubleToString(maxAdverseToSLPercent, 2) + ",\n";
   tradeJson += "  \"max_favorable_to_tp_percent\": " + DoubleToString(maxFavorableToTPPercent, 2) + ",\n";
   tradeJson += "  \"addon_count\": " + IntegerToString(addOnCount) + ",\n";
   tradeJson += "  \"addon_total_lots\": " + DoubleToString(addOnLots, 2) + ",\n";
   tradeJson += "  \"addon_avg_entry_price\": " + DoubleToString(addOnAvgEntryPrice, 2) + ",\n";
   tradeJson += "  \"addon_profit\": " + DoubleToString(addOnProfit, 2) + ",\n";
   tradeJson += "  \"has_addon\": " + (addOnCount > 0 ? "true" : "false") + ",\n";
   tradeJson += "  \"pcm_break_even_applied\": " + (g_pcmBreakEvenApplied ? "true" : "false") + ",\n";
   tradeJson += "  \"pcm_trailling_stop_applied\": " + (g_pcmTraillingStopApplied ? "true" : "false") + ",\n";
   tradeJson += "  \"result\": \"" + resultCode + "\",\n";
   tradeJson += "  \"max_floating_profit\": " + DoubleToString(maxFloatingProfit, 2) + ",\n";
   tradeJson += "  \"max_floating_drawdown\": " + DoubleToString(maxFloatingDrawdown, 2) + ",\n";
   tradeJson += "  \"profit_gross\": " + DoubleToString(grossProfit, 2) + ",\n";
   tradeJson += "  \"swap\": " + DoubleToString(swapValue, 2) + ",\n";
   tradeJson += "  \"commission\": " + DoubleToString(commissionValue, 2) + ",\n";
   tradeJson += "  \"fee\": " + DoubleToString(feeValue, 2) + ",\n";
   tradeJson += "  \"costs_total\": " + DoubleToString(costsTotal, 2) + ",\n";
   tradeJson += "  \"profit_net\": " + DoubleToString(netProfit, 2) + ",\n";
   tradeJson += "  \"profit\": " + DoubleToString(netProfit, 2) + "\n";
   tradeJson += "},\n";

   g_tradesLog += tradeJson;
}

//+------------------------------------------------------------------+
//| Registra dia sem operacao                                        |
//+------------------------------------------------------------------+
void LogNoTrade(string reason,
                string eventType = "",
                string entryDirection = "",
                double limitPrice = 0.0,
                double closestPrice = 0.0,
                double stopLoss = 0.0,
                double takeProfit = 0.0,
                double missingToLimitPoints = -1.0,
                double rrMaxReached = -1.0,
                double rrMinRequired = -1.0,
                bool pcmArmedFromNoTrade = false)
{
   if(!EnableLogging) return;

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   if(digits <= 0)
      digits = 2;

   string limitPriceText = (limitPrice > 0.0) ? DoubleToString(limitPrice, digits) : "null";
   string closestPriceText = (closestPrice > 0.0) ? DoubleToString(closestPrice, digits) : "null";
   string stopLossText = (stopLoss > 0.0) ? DoubleToString(stopLoss, digits) : "null";
   string takeProfitText = (takeProfit > 0.0) ? DoubleToString(takeProfit, digits) : "null";
   string missingPointsText = (missingToLimitPoints >= 0.0) ? DoubleToString(missingToLimitPoints, 2) : "null";
   string rrMaxText = (rrMaxReached >= 0.0) ? DoubleToString(rrMaxReached, 4) : "null";
   string rrMinText = (rrMinRequired >= 0.0) ? DoubleToString(rrMinRequired, 4) : "null";
   string pcmArmedText = pcmArmedFromNoTrade ? "true" : "false";

   string noTradeJson = "{\n";
   noTradeJson += "  \"date\": \"" + TimeToString(TimeCurrent(), TIME_DATE) + "\",\n";
   noTradeJson += "  \"reason\": \"" + reason + "\",\n";
   noTradeJson += "  \"channel_range\": " + DoubleToString(g_channelRange, 2) + ",\n";
   noTradeJson += "  \"timeframe\": \"" + EnumToString(g_activeTimeframe) + "\",\n";
   noTradeJson += "  \"event_type\": \"" + eventType + "\",\n";
   noTradeJson += "  \"entry_direction\": \"" + entryDirection + "\",\n";
   noTradeJson += "  \"limit_price\": " + limitPriceText + ",\n";
   noTradeJson += "  \"closest_price\": " + closestPriceText + ",\n";
   noTradeJson += "  \"stop_loss\": " + stopLossText + ",\n";
   noTradeJson += "  \"take_profit\": " + takeProfitText + ",\n";
   noTradeJson += "  \"missing_to_limit_points\": " + missingPointsText + ",\n";
   noTradeJson += "  \"rr_max_reached\": " + rrMaxText + ",\n";
   noTradeJson += "  \"rr_min_required\": " + rrMinText + ",\n";
   noTradeJson += "  \"pcm_armed_from_notrade\": " + pcmArmedText + "\n";
   noTradeJson += "},\n";

   g_noTradesLog += noTradeJson;
}
