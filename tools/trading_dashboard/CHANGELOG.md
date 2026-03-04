# Trading Dashboard - Changelog

## Versão 2.0 - Cards Expandidos com Métricas Completas

### Mudanças Principais

#### 1. Cards Redesenhados
- **Antes**: 6 cards simples com apenas contadores básicos
- **Agora**: 6 cards expandidos com todas as métricas do relatório

#### 2. Novos Cards

##### Card 1: OPERAÇÕES
- Total de operações
- TP / SL
- BUY / SELL
- Sliced
- turnof

##### Card 2: PERFORMANCE
- Lucro Líquido (valor principal)
- Win Rate
- Profit Factor
- Payoff Ratio
- Gross Profit
- Gross Loss
- Média por Trade
- Mediana
- Recovery Factor

##### Card 3: DRAWDOWN
- Max Drawdown (valor principal)
- Max DD %
- DD Tick Flutuante
- DD + LIMIT
- Soma DD Diário
- Dias Monitorados

##### Card 4: EXTREMOS
- Melhor Trade (valor principal)
- Pior Trade
- MFE Médio
- MAE Médio
- MFE Max
- MAE Min
- Distância Média SL

##### Card 5: ADD-ON
- Operações com AddOn (valor principal)
- Total AddOns
- Lotes AddOn
- PnL AddOn

##### Card 6: SEQUÊNCIAS
- Max Sequência Ganhos (valor principal)
- Valor Ganhos
- Max Sequência Perdas
- Valor Perdas
- Dias NoTrade

### Melhorias Técnicas

#### Backend (trading_dashboard_server.py)
- Parser expandido para extrair todas as métricas do relatório markdown
- Novos campos extraídos:
  - `buy_count`, `sell_count`
  - `is_reversal_count`, `triggered_reversal_count`
  - `first_ops`, `turn_ops`, `add_ops`
  - `sliced_count`, `no_trade_days`
  - `ops_with_addon`, `total_addons`, `addon_total_lots`, `addon_total_pnl`
  - `media_profit`, `gross_profit`, `gross_loss`
  - `payoff_ratio`, `median_profit`
  - `best_trade`, `worst_trade`
  - `avg_mfe`, `avg_mae`, `avg_adverse_to_sl`
  - `max_mfe`, `min_mae`
  - `max_drawdown_pct`, `recovery_factor`
  - `max_win_streak`, `max_win_streak_value`
  - `max_loss_streak`, `max_loss_streak_value`

#### Frontend (index.html + app.js)
- Cards redesenhados com estrutura hierárquica
- Valor principal em destaque (32px, bold)
- Métricas secundárias organizadas em linhas
- Ícones SVG para cada categoria
- Cores dinâmicas para valores positivos/negativos

#### Estilo (styles.css)
- Nova classe `.card-large` para cards expandidos
- `.card-header` com ícone e label
- `.card-metrics` para lista de métricas
- `.metric-row` para cada linha de métrica
- Grid responsivo ajustado para `minmax(280px, 1fr)`

### Compatibilidade
- Mantém compatibilidade com relatórios antigos
- Valores ausentes exibem "-"
- Formatação automática de moeda
- Cores condicionais (verde/vermelho) para PnL

### Como Usar
```powershell
# Iniciar dashboard
powershell -ExecutionPolicy Bypass -File .\tools\iniciar_trading_dashboard.ps1

# Ou com parâmetros customizados
powershell -ExecutionPolicy Bypass -File .\tools\iniciar_trading_dashboard.ps1 -ServerHost 127.0.0.1 -Port 8788
```

Acesse: http://127.0.0.1:8788
