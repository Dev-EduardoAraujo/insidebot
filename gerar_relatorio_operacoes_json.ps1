param(
   [string]$JsonPath = "",
   [string]$NoTradesJsonPath = "",
   [string]$OutputPath = "docs/relatorios/operacoes/RELATORIO_OPERACOES_JSON.md",
   [int]$OpeningHour = 0,
   [int]$OpeningMinute = 0
)

$ErrorActionPreference = "Stop"
$invariant = [System.Globalization.CultureInfo]::InvariantCulture
$emojiTrue = [string][char]0x2705
$emojiFalse = [string][char]0x274C
$script:IsHiran1Mode = $false
$script:SecondaryOpLabel = "PCM"
$script:SecondaryOpPrefix = "pcm_"

function Is-True {
   param([object]$Value)
   if ($null -eq $Value) { return $false }
   if ($Value -is [bool]) { return $Value }
   return ([string]$Value).Trim().ToLowerInvariant() -eq "true"
}

function To-Double {
   param([object]$Value, [double]$Default = 0.0)
   if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $Default }
   try { return [double]$Value } catch { return $Default }
}

function To-NullableDouble {
   param([object]$Value)
   if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $null }
   try { return [double]$Value } catch { return $null }
}

function Resolve-NoTradePCMArmedFlag {
   param(
      [object]$Row,
      [bool]$EnablePCMOnNoTrade,
      [bool]$PCMRuntimeLikelyEnabled
   )

   if ($null -eq $Row) { return $false }

   $rawArmed = Is-True $Row.pcm_armed_from_notrade
   if (-not $rawArmed) { $rawArmed = Is-True $Row.recontagem_armed_from_notrade }
   if (-not $rawArmed) { $rawArmed = Is-True $Row.Recontagem_armed_from_notrade }
   if (-not $rawArmed) { $rawArmed = Is-True $Row.second_op_armed_from_notrade }
   if (-not $rawArmed) { $rawArmed = Is-True $Row.Second_op_armed_from_notrade }
   if ($rawArmed) { return $true }

   $eventType = [string]$Row.event_type
   $reasonText = [string]$Row.reason
   $isLimitCanceledTarget = ($eventType -eq "LIMIT_CANCELED_TARGET_REACHED") -or ($reasonText -like "Limit cancelada*")
   if (-not $isLimitCanceledTarget) { return $false }
   if (-not $EnablePCMOnNoTrade) { return $false }
   if (-not $PCMRuntimeLikelyEnabled) { return $false }
   return $true
}

function Normalize-Direction {
   param([object]$Direction)
   $text = [string]$Direction
   if ([string]::IsNullOrWhiteSpace($text)) { return "-" }
   if ($text -like "*BUY*") { return "BUY" }
   if ($text -like "*SELL*") { return "SELL" }
   return $text
}

function Format-Number {
   param([object]$Value, [int]$Decimals = 2, [string]$IfEmpty = "-")
   if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $IfEmpty }
   try {
      $pattern = "{0:0." + ("0" * $Decimals) + "}"
      return [string]::Format($invariant, $pattern, [double]$Value)
   } catch {
      return [string]$Value
   }
}

function Format-Percent {
   param([double]$Value)
   return [string]::Format($invariant, "{0:0.00}%", $Value)
}

function Format-ProfitFactor {
   param([double]$GrossProfit, [double]$GrossLossAbs)
   if ($GrossLossAbs -le 0) {
      if ($GrossProfit -gt 0) { return "INF" }
      return "0.00"
   }
   return Format-Number ($GrossProfit / $GrossLossAbs)
}

function Resolve-TesterResultFromLogs {
   param([string]$TradesJsonPath)

   if ([string]::IsNullOrWhiteSpace($TradesJsonPath)) {
      return $null
   }

   $normalizedTarget = ([string]$TradesJsonPath).Trim()
   $normalizedTarget = $normalizedTarget -replace '/', '\'
   $normalizedTargetLower = $normalizedTarget.ToLowerInvariant()

   $filesDir = Split-Path -Path $normalizedTarget -Parent
   $mql5Dir = if (-not [string]::IsNullOrWhiteSpace($filesDir)) { Split-Path -Path $filesDir -Parent } else { "" }
   $agentDir = if (-not [string]::IsNullOrWhiteSpace($mql5Dir)) { Split-Path -Path $mql5Dir -Parent } else { "" }
   $logsDir = if (-not [string]::IsNullOrWhiteSpace($agentDir)) { Join-Path -Path $agentDir -ChildPath "logs" } else { "" }

   if ([string]::IsNullOrWhiteSpace($logsDir) -or -not (Test-Path -LiteralPath $logsDir)) {
      return $null
   }

   $logFiles = @(
      Get-ChildItem -LiteralPath $logsDir -File -Filter "*.log" -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTime -Descending
   )
   if ($logFiles.Count -eq 0) {
      return $null
   }

   $initialPattern = [regex]'Tester\s+initial deposit\s+([0-9\.\-]+)\s+USD'
   $finalPattern = [regex]'Tester\s+final balance\s+([0-9\.\-]+)\s+USD'

   foreach ($file in $logFiles) {
      $currentInitial = $null
      $currentFinal = $null
      $lineNumber = 0
      $lastMatch = $null
      $stream = $null
      $reader = $null

      try {
         $stream = [System.IO.File]::Open($file.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
         $reader = [System.IO.StreamReader]::new($stream)

         while (($line = $reader.ReadLine()) -ne $null) {
            $lineNumber++

            $mInit = $initialPattern.Match($line)
            if ($mInit.Success) {
               try {
                  $currentInitial = [double]::Parse($mInit.Groups[1].Value, [System.Globalization.CultureInfo]::InvariantCulture)
               } catch {
                  $currentInitial = $null
               }
            }

            $mFinal = $finalPattern.Match($line)
            if ($mFinal.Success) {
               try {
                  $currentFinal = [double]::Parse($mFinal.Groups[1].Value, [System.Globalization.CultureInfo]::InvariantCulture)
               } catch {
                  $currentFinal = $null
               }
            }

            $tag = "Trades salvo:"
            $idx = $line.IndexOf($tag, [System.StringComparison]::OrdinalIgnoreCase)
            if ($idx -ge 0) {
               $savedPath = $line.Substring($idx + $tag.Length).Trim()
               $savedPath = $savedPath -replace '/', '\'
               $savedPathLower = $savedPath.ToLowerInvariant()

               if ($savedPathLower -eq $normalizedTargetLower -and $null -ne $currentFinal) {
                  $lastMatch = [pscustomobject]@{
                     initial_balance = $currentInitial
                     final_balance = $currentFinal
                     log_file = $file.FullName
                     line_number = $lineNumber
                  }
               }
            }
         }
      } catch {
         continue
      } finally {
         if ($null -ne $reader) { $reader.Close() }
         if ($null -ne $stream) { $stream.Close() }
      }

      if ($null -ne $lastMatch) {
         return $lastMatch
      }
   }

   return $null
}

function Get-UniqueOutputPath {
   param([string]$PreferredPath)

   if (-not (Test-Path -LiteralPath $PreferredPath)) {
      return $PreferredPath
   }

   $directory = Split-Path -Path $PreferredPath -Parent
   if ([string]::IsNullOrWhiteSpace($directory)) {
      $directory = "."
   }

   $fileName = [System.IO.Path]::GetFileNameWithoutExtension($PreferredPath)
   $extension = [System.IO.Path]::GetExtension($PreferredPath)
   $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

   $candidate = Join-Path -Path $directory -ChildPath ($fileName + "_" + $timestamp + $extension)
   if (-not (Test-Path -LiteralPath $candidate)) {
      return $candidate
   }

   $suffix = 1
   while ($true) {
      $candidate = Join-Path -Path $directory -ChildPath ("{0}_{1}_{2}{3}" -f $fileName, $timestamp, $suffix, $extension)
      if (-not (Test-Path -LiteralPath $candidate)) {
         return $candidate
      }
      $suffix++
   }
}

function Resolve-NoTradesJsonPath {
   param(
      [string]$TradesPath,
      [string]$ExplicitNoTradesPath
   )

   if (-not [string]::IsNullOrWhiteSpace($ExplicitNoTradesPath)) {
      return $ExplicitNoTradesPath
   }

   if ([string]::IsNullOrWhiteSpace($TradesPath)) {
      return ""
   }

   $candidate = $TradesPath
   if ($candidate -match "_[Tt]rades_") {
      $candidate = $candidate -replace "_[Tt]rades_", "_NoTrades_"
   }
   return $candidate
}

function Normalize-LogPath {
   param([string]$PathText)

   if ([string]::IsNullOrWhiteSpace($PathText)) { return "" }

   $text = [string]$PathText
   $tradesTag = "Trades salvo:"
   $noTradesTag = "NoTrades salvo:"

   $idxTrades = $text.IndexOf($tradesTag, [System.StringComparison]::OrdinalIgnoreCase)
   if ($idxTrades -ge 0) {
      $text = $text.Substring($idxTrades + $tradesTag.Length).Trim()
   }

   $idxNoTrades = $text.IndexOf($noTradesTag, [System.StringComparison]::OrdinalIgnoreCase)
   if ($idxNoTrades -ge 0) {
      $text = $text.Substring($idxNoTrades + $noTradesTag.Length).Trim()
   }

   $text = $text.Trim('"').Trim("'")
   return $text.Trim()
}

function Parse-TradeDateTime {
   param([string]$Text)
   if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
   $patterns = @(
      "yyyy.MM.dd HH:mm:ss",
      "yyyy.MM.dd HH:mm",
      "yyyy-MM-dd HH:mm:ss",
      "yyyy-MM-dd HH:mm"
   )
   foreach ($p in $patterns) {
      try { return [datetime]::ParseExact($Text, $p, $invariant) } catch {}
   }
   try { return [datetime]::Parse($Text, $invariant) } catch { return $null }
}

function Format-CapitalTag {
   param([double]$BalanceValue)

   $absValue = [math]::Abs($BalanceValue)
   if ($absValue -ge 1000.0) {
      $kValue = $absValue / 1000.0
      $roundedK = [math]::Round($kValue)
      if ([math]::Abs($kValue - $roundedK) -le 0.0001) {
         return ("{0}k" -f [int]$roundedK)
      }
      return ([string]::Format($invariant, "{0:0.##}k", $kValue))
   }

   if ([math]::Abs($absValue - [math]::Round($absValue)) -le 0.0001) {
      return [string]([int][math]::Round($absValue))
   }
   return [string]::Format($invariant, "{0:0.##}", $absValue)
}

function Resolve-PeriodTagForOutput {
   param(
      [object]$RunConfig,
      [array]$RawTrades
   )

   $startDt = $null
   $endDt = $null

   if ($null -ne $RunConfig) {
      if ($null -ne $RunConfig.PSObject.Properties["start_time"]) {
         $startDt = Parse-TradeDateTime ([string]$RunConfig.start_time)
      }
      if ($null -ne $RunConfig.PSObject.Properties["end_time"]) {
         $endDt = Parse-TradeDateTime ([string]$RunConfig.end_time)
      }
   }

   if ($null -eq $startDt -or $null -eq $endDt) {
      $entries = @()
      $exits = @()
      foreach ($t in @($RawTrades)) {
         $entryDt = Parse-TradeDateTime ([string]$t.entry_time)
         $exitDt = Parse-TradeDateTime ([string]$t.exit_time)
         if ($entryDt -ne $null) { $entries += $entryDt }
         if ($exitDt -ne $null) { $exits += $exitDt }
      }
      if ($null -eq $startDt -and $entries.Count -gt 0) {
         $startDt = @($entries | Sort-Object)[0]
      }
      if ($null -eq $endDt -and $exits.Count -gt 0) {
         $endDt = @($exits | Sort-Object)[-1]
      }
   }

   if ($null -eq $startDt -or $null -eq $endDt) {
      return "0000_0000"
   }

   return ("{0}{1}_{2}{3}" -f $startDt.ToString("dd", $invariant), $startDt.ToString("MM", $invariant), $endDt.ToString("dd", $invariant), $endDt.ToString("MM", $invariant))
}

function Resolve-InitialBalanceForOutput {
   param(
      [object]$RunConfig,
      [object]$TickDrawdown
   )

   if ($null -ne $RunConfig) {
      if ($null -ne $RunConfig.PSObject.Properties["InitialDeposit"]) {
         $v = To-Double $RunConfig.InitialDeposit
         if ($v -gt 0.0) { return $v }
      }
      if ($null -ne $RunConfig.PSObject.Properties["initial_deposit"]) {
         $v = To-Double $RunConfig.initial_deposit
         if ($v -gt 0.0) { return $v }
      }
   }

   if ($null -ne $TickDrawdown -and $null -ne $TickDrawdown.daily) {
      $dailyRows = @($TickDrawdown.daily)
      if ($dailyRows.Count -gt 0) {
         $v = To-Double $dailyRows[0].day_start_balance
         if ($v -gt 0.0) { return $v }
      }
   }

   return 0.0
}

function Resolve-StandardOutputPath {
   param(
      [object]$RunConfig,
      [object]$TickDrawdown,
      [array]$RawTrades
   )

   $useInitialDeposit = $false
   if ($null -ne $RunConfig -and $null -ne $RunConfig.selected_parameters) {
      $useInitialProp = $RunConfig.selected_parameters.PSObject.Properties["UseInitialDepositForRisk"]
      if ($null -ne $useInitialProp) {
         $useInitialDeposit = Is-True $useInitialProp.Value
      }
   }
   $modeTag = if ($useInitialDeposit) { "LimitOfDeposit" } else { "BalanceBased" }
   $initialBalance = Resolve-InitialBalanceForOutput -RunConfig $RunConfig -TickDrawdown $TickDrawdown
   if ($initialBalance -le 0.0) { $initialBalance = 100000.0 }
   $capitalTag = Format-CapitalTag -BalanceValue $initialBalance
   $periodTag = Resolve-PeriodTagForOutput -RunConfig $RunConfig -RawTrades $RawTrades

   return ("docs/relatorios/operacoes/{0}-{1}{2}.md" -f $periodTag, $modeTag, $capitalTag)
}

function Get-Median {
   param([array]$Values)
   $arr = @($Values | Where-Object { $_ -ne $null } | ForEach-Object { [double]$_ } | Sort-Object)
   if ($arr.Count -eq 0) { return 0.0 }
   $mid = [math]::Floor($arr.Count / 2)
   if (($arr.Count % 2) -eq 1) { return [double]$arr[$mid] }
   return ([double]$arr[$mid - 1] + [double]$arr[$mid]) / 2.0
}

function Month-Key {
   param([string]$DateText)
   if ($DateText -match "^(\d{4})\.(\d{2})") {
      return "$($Matches[1])-$($Matches[2])"
   }
   return "N/A"
}

function Get-Timeframe-Minutes {
   param([object]$Timeframe)
   switch ([string]$Timeframe) {
      "PERIOD_M1"  { return 1 }
      "PERIOD_M2"  { return 2 }
      "PERIOD_M3"  { return 3 }
      "PERIOD_M4"  { return 4 }
      "PERIOD_M5"  { return 5 }
      "PERIOD_M6"  { return 6 }
      "PERIOD_M10" { return 10 }
      "PERIOD_M12" { return 12 }
      "PERIOD_M15" { return 15 }
      "PERIOD_M20" { return 20 }
      "PERIOD_M30" { return 30 }
      "PERIOD_H1"  { return 60 }
      "PERIOD_H2"  { return 120 }
      "PERIOD_H3"  { return 180 }
      "PERIOD_H4"  { return 240 }
      "PERIOD_H6"  { return 360 }
      "PERIOD_H8"  { return 480 }
      "PERIOD_H12" { return 720 }
      "PERIOD_D1"  { return 1440 }
      default { return 0 }
   }
}

function Resolve-Channel-Definition-Time {
   param([object]$Trade, [int]$OpenHour, [int]$OpenMinute)

   $explicit = [string]$Trade.channel_definition_time
   if (-not [string]::IsNullOrWhiteSpace($explicit)) {
      return $explicit
   }

   $dateText = [string]$Trade.date
   if ([string]::IsNullOrWhiteSpace($dateText)) {
      return "-"
   }

   $tfMinutes = Get-Timeframe-Minutes $Trade.timeframe
   if ($tfMinutes -le 0) {
      return "-"
   }

   try {
      $day = [datetime]::ParseExact($dateText, "yyyy.MM.dd", $invariant)
      $open = $day.Date.AddHours($OpenHour).AddMinutes($OpenMinute)
      $channelDef = $open.AddMinutes(4 * $tfMinutes)
      return $channelDef.ToString("yyyy.MM.dd HH:mm", $invariant)
   } catch {
      return "-"
   }
}

function Resolve-Entry-Execution-Type {
   param([object]$Trade)

   $raw = [string]$Trade.entry_execution_type
   if ([string]::IsNullOrWhiteSpace($raw)) {
      if (Is-True $Trade.is_reversal) { return "MARKET" }
      return "-"
   }

   $text = $raw.Trim().ToUpperInvariant()
   if ($text -like "*LIMIT*") { return "LIMIT" }
   if ($text -like "*MARKET*") { return "MARKET" }
   return $text
}

function Resolve-Operation-ChainCode {
   param(
      [object]$Trade,
      [int]$FallbackIndex = 0
   )

   $chain = [string]$Trade.operation_chain_code
   if (-not [string]::IsNullOrWhiteSpace($chain)) {
      return $chain.Trim()
   }

   $opCode = [string]$Trade.operation_code
   if ($opCode -match "(op\d+)") {
      return [string]$Matches[1]
   }

   $idRaw = [string]$Trade.operation_chain_id
   if ($idRaw -match "^\d+$") {
      return ("op" + $idRaw)
   }

   if ($FallbackIndex -lt 1) { $FallbackIndex = 1 }
   return ("op" + [string]$FallbackIndex)
}

function Resolve-Operation-Code {
   param(
      [object]$Trade,
      [string]$ChainCode,
      [bool]$IsTurn
   )

   $opCode = [string]$Trade.operation_code
   if (-not [string]::IsNullOrWhiteSpace($opCode)) {
      return $opCode.Trim()
   }

   if ([string]::IsNullOrWhiteSpace($ChainCode)) {
      return "-"
   }

   if ($IsTurn) {
      return ("turn_" + $ChainCode)
   }
   return ("first_" + $ChainCode)
}

function Resolve-Add-Operation-Code {
   param(
      [object]$Trade,
      [string]$ChainCode,
      [bool]$HasAdd
   )

   $addCode = [string]$Trade.add_operation_code
   if (-not [string]::IsNullOrWhiteSpace($addCode)) {
      return $addCode.Trim()
   }

   if (-not $HasAdd) {
      return "-"
   }

   if ([string]::IsNullOrWhiteSpace($ChainCode)) {
      return "-"
   }

   return ("add_" + $ChainCode)
}

function Get-WeekdayName {
   param([datetime]$DateValue)
   if ($null -eq $DateValue) { return "N/A" }
   switch ([int]$DateValue.DayOfWeek) {
      1 { return "Seg" }
      2 { return "Ter" }
      3 { return "Qua" }
      4 { return "Qui" }
      5 { return "Sex" }
      6 { return "Sab" }
      0 { return "Dom" }
      default { return "N/A" }
   }
}

function New-Stats {
   param([array]$Rows)

   $rows = @($Rows)
   $trades = $rows.Count
   $wins = @($rows | Where-Object { $_.profit -gt 0 })
   $losses = @($rows | Where-Object { $_.profit -lt 0 })
   $tp = @($rows | Where-Object { $_.result -eq "TP" }).Count
   $sl = @($rows | Where-Object { $_.result -eq "SL" }).Count
   $be = @($rows | Where-Object { $_.result -eq "BE" }).Count

   $grossProfit = To-Double (($wins | Measure-Object -Property profit -Sum).Sum)
   $grossLoss = To-Double (($losses | Measure-Object -Property profit -Sum).Sum)
   $grossLossAbs = [math]::Abs($grossLoss)
   $netProfit = To-Double (($rows | Measure-Object -Property profit -Sum).Sum)

   $winRate = if ($trades -gt 0) { ([double]$wins.Count / [double]$trades) * 100.0 } else { 0.0 }
   $avgProfit = if ($trades -gt 0) { $netProfit / [double]$trades } else { 0.0 }
   $avgWin = if ($wins.Count -gt 0) { $grossProfit / [double]$wins.Count } else { 0.0 }
   $avgLossAbs = if ($losses.Count -gt 0) { $grossLossAbs / [double]$losses.Count } else { 0.0 }
   $payoff = if ($avgLossAbs -gt 0) { $avgWin / $avgLossAbs } else { 0.0 }
   $profitFactorText = Format-ProfitFactor $grossProfit $grossLossAbs
   $avgRange = if ($trades -gt 0) { To-Double (($rows | Measure-Object -Property channel_range -Average).Average) } else { 0.0 }
   $avgRR = if ($trades -gt 0) { To-Double (($rows | Measure-Object -Property risk_reward -Average).Average) } else { 0.0 }
   $avgMaxFloatingProfit = if ($trades -gt 0) { To-Double (($rows | Measure-Object -Property max_floating_profit -Average).Average) } else { 0.0 }
   $avgMaxFloatingDrawdown = if ($trades -gt 0) { To-Double (($rows | Measure-Object -Property max_floating_drawdown -Average).Average) } else { 0.0 }
   $medianProfit = Get-Median ($rows | ForEach-Object { $_.profit })
   $bestTrade = if ($trades -gt 0) { To-Double (($rows | Measure-Object -Property profit -Maximum).Maximum) } else { 0.0 }
   $worstTrade = if ($trades -gt 0) { To-Double (($rows | Measure-Object -Property profit -Minimum).Minimum) } else { 0.0 }
   $bestFloatingProfit = if ($trades -gt 0) { To-Double (($rows | Measure-Object -Property max_floating_profit -Maximum).Maximum) } else { 0.0 }
   $worstFloatingDrawdown = if ($trades -gt 0) { To-Double (($rows | Measure-Object -Property max_floating_drawdown -Minimum).Minimum) } else { 0.0 }

   return [pscustomobject]@{
      trades = $trades
      tp = $tp
      sl = $sl
      be = $be
      wins = $wins.Count
      losses = $losses.Count
      win_rate = $winRate
      gross_profit = $grossProfit
      gross_loss = $grossLoss
      gross_loss_abs = $grossLossAbs
      net_profit = $netProfit
      avg_profit = $avgProfit
      avg_win = $avgWin
      avg_loss_abs = $avgLossAbs
      payoff_ratio = $payoff
      profit_factor_text = $profitFactorText
      avg_range = $avgRange
      avg_rr = $avgRR
      avg_max_floating_profit = $avgMaxFloatingProfit
      avg_max_floating_drawdown = $avgMaxFloatingDrawdown
      median_profit = $medianProfit
      best_trade = $bestTrade
      worst_trade = $worstTrade
      best_floating_profit = $bestFloatingProfit
      worst_floating_drawdown = $worstFloatingDrawdown
   }
}

function Get-Drawdown-And-Streaks {
   param(
      [array]$Rows,
      [double]$InitialBalance = 0.0
   )

   $rows = @($Rows)
   $equity = 0.0
   $peak = 0.0
   $accountEquity = if ($InitialBalance -gt 0.0) { $InitialBalance } else { 0.0 }
   $accountPeak = $accountEquity
   $maxDrawdown = 0.0
   $maxDrawdownPct = 0.0

   $currWinCount = 0
   $currLossCount = 0
   $currWinSum = 0.0
   $currLossSum = 0.0
   $maxWinCount = 0
   $maxLossCount = 0
   $maxWinSum = 0.0
   $maxLossSum = 0.0

   foreach ($r in $rows) {
      $p = To-Double $r.profit
      $equity += $p
      $accountEquity += $p

      if ($equity -gt $peak) { $peak = $equity }
      if ($accountEquity -gt $accountPeak) { $accountPeak = $accountEquity }
      $dd = $peak - $equity
      if ($dd -gt $maxDrawdown) { $maxDrawdown = $dd }
      if ($accountPeak -gt 0.0) {
         $ddPct = ($dd / $accountPeak) * 100.0
         if ($ddPct -gt $maxDrawdownPct) { $maxDrawdownPct = $ddPct }
      }

      if ($p -gt 0) {
         $currWinCount++
         $currWinSum += $p
         $currLossCount = 0
         $currLossSum = 0.0

         if ($currWinCount -gt $maxWinCount) {
            $maxWinCount = $currWinCount
            $maxWinSum = $currWinSum
         } elseif ($currWinCount -eq $maxWinCount -and $currWinSum -gt $maxWinSum) {
            $maxWinSum = $currWinSum
         }
      } elseif ($p -lt 0) {
         $currLossCount++
         $currLossSum += $p
         $currWinCount = 0
         $currWinSum = 0.0

         if ($currLossCount -gt $maxLossCount) {
            $maxLossCount = $currLossCount
            $maxLossSum = $currLossSum
         } elseif ($currLossCount -eq $maxLossCount -and $currLossSum -lt $maxLossSum) {
            $maxLossSum = $currLossSum
         }
      } else {
         $currWinCount = 0
         $currLossCount = 0
         $currWinSum = 0.0
         $currLossSum = 0.0
      }
   }

   return [pscustomobject]@{
      max_drawdown = $maxDrawdown
      max_drawdown_pct = $maxDrawdownPct
      max_win_streak = $maxWinCount
      max_win_streak_profit = $maxWinSum
      max_loss_streak = $maxLossCount
      max_loss_streak_profit = $maxLossSum
      final_equity = $equity
   }
}

function Get-MaxDailyDrawdown {
   param([array]$Rows)

   $rows = @($Rows)
   if ($rows.Count -eq 0) { return 0.0 }

   $groups = @($rows | Group-Object date)
   $maxDailyDrawdown = 0.0

   foreach ($g in $groups) {
      $dayRows = @(
         $g.Group |
         Sort-Object `
            @{ Expression = { if ($_.exit_dt -ne $null) { $_.exit_dt } else { [datetime]::MaxValue } }; Descending = $false }, `
            @{ Expression = { if ($_.entry_dt -ne $null) { $_.entry_dt } else { [datetime]::MaxValue } }; Descending = $false }
      )

      $equity = 0.0
      $peak = 0.0
      $dayMaxDrawdown = 0.0

      foreach ($r in $dayRows) {
         $equity += To-Double $r.profit
         if ($equity -gt $peak) { $peak = $equity }
         $dd = $peak - $equity
         if ($dd -gt $dayMaxDrawdown) { $dayMaxDrawdown = $dd }
      }

      if ($dayMaxDrawdown -gt $maxDailyDrawdown) { $maxDailyDrawdown = $dayMaxDrawdown }
   }

   return $maxDailyDrawdown
}

function Get-RunParamValue {
   param(
      [object]$RunConfig,
      [string]$Name,
      [double]$DefaultValue
   )

   if ($null -eq $RunConfig -or $null -eq $RunConfig.selected_parameters) { return $DefaultValue }
   $prop = $RunConfig.selected_parameters.PSObject.Properties[$Name]
   if ($null -eq $prop) { return $DefaultValue }
   return To-Double $prop.Value $DefaultValue
}

function Get-RunParamRawValue {
   param(
      [object]$RunConfig,
      [string]$Name,
      [object]$DefaultValue = $null
   )

   if ($null -eq $RunConfig -or $null -eq $RunConfig.selected_parameters) { return $DefaultValue }
   $prop = $RunConfig.selected_parameters.PSObject.Properties[$Name]
   if ($null -eq $prop) { return $DefaultValue }
   return $prop.Value
}

function Get-RunParamDisplayValue {
   param(
      [object]$SelectedParams,
      [string]$Name
   )

   if ($null -eq $SelectedParams) { return "-" }
   $prop = $SelectedParams.PSObject.Properties[$Name]
   if ($null -eq $prop) { return "-" }

   $value = $prop.Value
   if ($null -eq $value) { return "-" }
   if ($value -is [bool]) {
      return $(if ($value) { $script:emojiTrue } else { $script:emojiFalse })
   }

   $text = [string]$value
   if ([string]::IsNullOrWhiteSpace($text)) { return "-" }
   $lower = $text.Trim().ToLowerInvariant()
   if ($lower -eq "true") { return $script:emojiTrue }
   if ($lower -eq "false") { return $script:emojiFalse }

   if ($value -is [double] -or $value -is [single] -or $value -is [decimal]) {
      return Format-Number $value
   }

   return $text
}

function Get-RunParamBoolValue {
   param(
      [object]$SelectedParams,
      [string]$Name,
      [bool]$DefaultValue = $false
   )

   if ($null -eq $SelectedParams) { return $DefaultValue }
   $prop = $SelectedParams.PSObject.Properties[$Name]
   if ($null -eq $prop) { return $DefaultValue }
   return Is-True $prop.Value
}

function Get-RunParamDisplayName {
   param([string]$Name)

   switch ([string]$Name) {
      "StrictLimitOnly" { return "Priorizar LIMIT nas entradas; fechamentos e TurnOfs podem usar mercado" }
      "PreferLimitMainEntry" { return "Priorizar LIMIT na primeira entrada do dia" }
      "PreferLimitReversal" { return "Priorizar LIMIT na TurnOf" }
      "PreferLimitOvernightReversal" { return "Priorizar LIMIT na TurnOf de overnight" }
      "PreferLimitNegativeAddOn" { return "Priorizar LIMIT na adicao em flutuacao negativa" }
      "EnableReversal" { return "EnableTurnOf" }
      "EnableOvernightReversal" { return "EnableOvernightTurnOf" }
      "AllowMarketFallbackReversal" { return "Se LIMIT da TurnOf falhar, usar mercado" }
      "AllowMarketFallbackOvernightReversal" { return "Se LIMIT da TurnOf overnight falhar, usar mercado" }
      "ReversalMultiplier" { return "Multiplicador base do range na TurnOf" }
      "ReversalSLDistanceFactor" { return "Fator de distancia do SL na TurnOf" }
      "ReversalTPDistanceFactor" { return "Fator de distancia do TP na TurnOf" }
      "AllowReversalAfterMaxEntryHour" { return "AllowTurnOfAfterMaxEntryHour" }
      "RearmCanceledReversalNextDay" { return "RearmCanceledTurnOfNextDay" }
      "EnableNegativeAddOn" { return "EnableNegativeADON" }
      "NegativeAddTPAdjustOnReversal" { return "NegativeAddTPAdjustOnTurnOf" }
      "SlicedThreshold" { return "SLDThreshold" }
      "SlicedMultiplier" { return "SLDMultiplier" }
      "BreakoutMinTolerancePoints" { return "Tolerancia minima de rompimento (pontos)" }
      "PCMRiskPercent" { return "Risco por operacao PCM (%)" }
      "RecontagemRiskPercent" { return "Risco por operacao Recontagem (%)" }
      "EnablePCMOnNoTradeLimitTarget" { return "Habilitar PCM em NoTrade por LIMIT no alvo" }
      "EnableRecontagemOnNoTradeLimitTarget" { return "Habilitar Recontagem em NoTrade por LIMIT no alvo" }
      "EnableSecond_op" { return "Habilitar Recontagem pos TP da first_op" }
      "EnableSecondOp" { return "Habilitar Recontagem pos TP da first_op" }
      "EnableRecontagem" { return "Habilitar Recontagem pos TP da first_op" }
      "EnableSecond_opOnNoTradeLimitTarget" { return "Habilitar Recontagem em NoTrade por LIMIT no alvo" }
      "EnableSecondOpOnNoTradeLimitTarget" { return "Habilitar Recontagem em NoTrade por LIMIT no alvo" }
      "EnableSecondOpOnFirstOpStopLoss" { return "Habilitar Recontagem por SL da first_op" }
      "EnableSecond_opOnFirstOpStopLoss" { return "Habilitar Recontagem por SL da first_op" }
      "EnableRecontagemOnFirstOpStopLoss" { return "Habilitar Recontagem por SL da first_op" }
      "BreakEven" { return "Break even" }
      "PCMBreakEven" { return "Break even" }
      "PCMBreakEvenTriggerPercent" { return "Gatilho Break even PCM (% da distancia ate TP)" }
      "RecontagemBreakEvenTriggerPercent" { return "Gatilho Break even Recontagem (% da distancia ate TP)" }
      "TraillingStop" { return "Trailling stop" }
      "TrailingStop" { return "Trailling stop" }
      "PCMTPReductionPercent" { return "Reducao TP PCM (%)" }
      "RecontagemTPReductionPercent" { return "Reducao TP Recontagem (%)" }
      "PCMNegativeAddTPDistancePercent" { return "Distancia TP apos ADON em PCM (% da dist. ate SL)" }
      "RecontagemNegativeAddTPDistancePercent" { return "Distancia TP apos ADON em Recontagem (% da dist. ate SL)" }
      "RecontagemChannelBars" { return "RecontagemChannelBars" }
      "RecontagemMaxNoTradeRecounts" { return "Maximo de recontagens por NoTrade" }
      "RecontagemMaxOperationsPerDay" { return "RecontagemMaxOperationsPerDay" }
      "RecontagemIgnoreFirstEntryMaxHour" { return "RecontagemIgnoreFirstEntryMaxHour" }
      "RecontagemReferenceTimeframe" { return "RecontagemReferenceTimeframe" }
      "RecontagemEnableSkipLargeCandle" { return "RecontagemEnableSkipLargeCandle" }
      "RecontagemMaxCandlePoints" { return "RecontagemMaxCandlePoints" }
      "EnableRecontagemHourLimit" { return "EnableRecontagemHourLimit" }
      "RecontagemEntryMaxHour" { return "RecontagemEntryMaxHour" }
      "RecontagemEntryMaxMinute" { return "RecontagemEntryMaxMinute" }
      "UseInitialDepositForRisk" { return "Usar deposito inicial da conta como base fixa do risco" }
      "FixedLotAllEntries" { return "Lote fixo para todas as entradas (0 desativa)" }
      "DrawdownPercentReference" { return "Referencia DD percentual" }
      "EnableVerboseDDLogs" { return "Verbose DD logs" }
      "DDVerboseLogIntervalSeconds" { return "Intervalo verbose DD (s)" }
      default { return [string]$Name }
   }
}

function Append-RunConfigSection {
   param(
      [System.Text.StringBuilder]$Builder,
      [object]$RunConfig,
      [bool]$IsHiran1Mode = $false
   )

   [void]$Builder.AppendLine("## Parametros do Bot")
   [void]$Builder.AppendLine("")

   if ($null -eq $RunConfig) {
      [void]$Builder.AppendLine("Bloco `run_config` nao encontrado no JSON.")
      [void]$Builder.AppendLine("")
      return
   }

   [void]$Builder.AppendLine("- Simbolo: $([string]$RunConfig.symbol)")
   [void]$Builder.AppendLine("- Inicio da execucao: $([string]$RunConfig.start_time)")
   [void]$Builder.AppendLine("- Fim da execucao: $([string]$RunConfig.end_time)")
   [void]$Builder.AppendLine("")

   $selected = $RunConfig.selected_parameters
   $secondaryTitle = if ($IsHiran1Mode) { "Parametros de Recontagem" } else { "Parametros de PCM" }
   $groupDefinitions = @(
      [pscustomobject]@{
         title = "Parametros de Gatilho e Canal"
         names = @("OpeningHour", "OpeningMinute", "FirstEntryMaxHour", "MaxEntryHour", "ChannelTimeframe", "EnableM15Fallback", "MinChannelRange", "MaxChannelRange", "SlicedThreshold", "BreakoutMinTolerancePoints")
      },
      [pscustomobject]@{
         title = "Parametros de Stop"
         names = @("StopLossIncrement")
      },
      [pscustomobject]@{
         title = "Parametros de TP"
         names = @("TPMultiplier", "TPReductionPercent")
      },
      [pscustomobject]@{
         title = "Parametros de TP (Complementar)"
         names = @("SlicedMultiplier")
      },
      [pscustomobject]@{
         title = "Parametros de Risco e Retorno"
         names = @("RiskPercent", "UseInitialDepositForRisk", "FixedLotAllEntries", "MinRiskReward", "DrawdownPercentReference", "MaxDailyDrawdownPercent", "MaxDrawdownPercent", "MaxDailyDrawdownAmount", "MaxDrawdownAmount", "EnableVerboseDDLogs", "DDVerboseLogIntervalSeconds")
      },
      [pscustomobject]@{
         title = "Parametros de TurnOf"
         names = @("EnableReversal", "EnableOvernightReversal", "ReversalMultiplier", "ReversalSLDistanceFactor", "ReversalTPDistanceFactor", "AllowReversalAfterMaxEntryHour", "RearmCanceledReversalNextDay")
      },
      [pscustomobject]@{
         title = "Parametros de Overnight"
         names = @("AllowTradeWithOvernight", "KeepPositionsOvernight", "CloseMinutesBeforeMarketClose")
      },
      [pscustomobject]@{
         title = "Modo de Execucao"
         names = @("StrictLimitOnly", "PreferLimitMainEntry", "PreferLimitReversal", "PreferLimitOvernightReversal", "PreferLimitNegativeAddOn", "AllowMarketFallbackReversal", "AllowMarketFallbackOvernightReversal")
      },
      [pscustomobject]@{
         title = "Parametros de Adicao em Flutuacao Negativa"
         names = @("EnableNegativeAddOn", "NegativeAddMaxEntries", "NegativeAddTriggerPercent", "NegativeAddLotMultiplier", "NegativeAddUseSameSLTP", "EnableNegativeAddTPAdjustment", "NegativeAddTPDistancePercent", "NegativeAddTPAdjustOnReversal", "EnableNegativeAddDebugLogs", "NegativeAddDebugIntervalSeconds")
      },
      [pscustomobject]@{
         title = $secondaryTitle
         names = @(
            "EnablePCM", "EnableSecondOp", "EnableSecond_op", "EnableRecontagem",
            "EnablePCMOnNoTradeLimitTarget", "EnableSecondOpOnNoTradeLimitTarget", "EnableSecond_opOnNoTradeLimitTarget", "EnableRecontagemOnNoTradeLimitTarget",
            "EnableSecondOpOnFirstOpStopLoss", "EnableSecond_opOnFirstOpStopLoss", "EnableRecontagemOnFirstOpStopLoss",
            "BreakEven", "PCMBreakEven",
            "PCMBreakEvenTriggerPercent", "RecontagemBreakEvenTriggerPercent",
            "TraillingStop", "TrailingStop",
            "PCMTPReductionPercent", "RecontagemTPReductionPercent",
            "PCMRiskPercent", "RecontagemRiskPercent",
            "PCMNegativeAddTPDistancePercent", "RecontagemNegativeAddTPDistancePercent",
            "PCMChannelBars", "RecontagemChannelBars",
            "PCMMaxNoTradeRecounts", "RecontagemMaxNoTradeRecounts",
            "PCMMaxOperationsPerDay", "RecontagemMaxOperationsPerDay",
            "PCMIgnoreFirstEntryMaxHour", "RecontagemIgnoreFirstEntryMaxHour",
            "PCMReferenceTimeframe", "RecontagemReferenceTimeframe",
            "PCMEnableSkipLargeCandle", "RecontagemEnableSkipLargeCandle",
            "PCMMaxCandlePoints", "RecontagemMaxCandlePoints",
            "EnablePCMHourLimit", "EnableRecontagemHourLimit",
            "PCMEntryMaxHour", "RecontagemEntryMaxHour",
            "PCMEntryMaxMinute", "RecontagemEntryMaxMinute"
         )
      },
      [pscustomobject]@{
         title = "Parametros de Interface e Log"
         names = @("DrawChannels", "EnableLogging", "MagicNumber")
      }
   )

   $renderedNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

   foreach ($group in $groupDefinitions) {
      [void]$Builder.AppendLine("### $([string]$group.title)")
      [void]$Builder.AppendLine("")
      [void]$Builder.AppendLine("| Parametro (painel MQL) | Valor utilizado |")
      [void]$Builder.AppendLine("|---|---|")

      foreach ($name in @($group.names)) {
         [void]$renderedNames.Add([string]$name)
         $displayName = Get-RunParamDisplayName -Name ([string]$name)
         $valueText = Get-RunParamDisplayValue -SelectedParams $selected -Name ([string]$name)
         [void]$Builder.AppendLine("| $displayName | $valueText |")
      }

      [void]$Builder.AppendLine("")
   }

   if ($null -ne $selected) {
      $extraParams = @()
      foreach ($prop in $selected.PSObject.Properties) {
         if ($null -eq $prop) { continue }
         $propName = [string]$prop.Name
         if ([string]::IsNullOrWhiteSpace($propName)) { continue }
         if (-not $renderedNames.Contains($propName)) {
            $extraParams += $propName
         }
      }

      if ($extraParams.Count -gt 0) {
         [void]$Builder.AppendLine("### Parametros Adicionais do JSON")
         [void]$Builder.AppendLine("")
         [void]$Builder.AppendLine("| Parametro (painel MQL) | Valor utilizado |")
         [void]$Builder.AppendLine("|---|---|")
         foreach ($extraName in $extraParams) {
            $displayName = Get-RunParamDisplayName -Name ([string]$extraName)
            $valueText = Get-RunParamDisplayValue -SelectedParams $selected -Name ([string]$extraName)
            [void]$Builder.AppendLine("| $displayName | $valueText |")
         }
         [void]$Builder.AppendLine("")
      }
   }
}

function Append-TickDrawdownSection {
   param(
      [System.Text.StringBuilder]$Builder,
      [object]$TickDrawdown
   )

   [void]$Builder.AppendLine("## DD Tick a Tick")
   [void]$Builder.AppendLine("")

   if ($null -eq $TickDrawdown) {
      [void]$Builder.AppendLine("Dados de DD tick a tick nao disponiveis neste JSON.")
      [void]$Builder.AppendLine("")
      return
   }

   $summary = $TickDrawdown.summary
   $daysCount = [int](To-Double $summary.days_count)
   $maxFloating = To-Double $summary.max_intraday_floating_dd
   $hasMaxFloatingPctOfDayBalance = ($null -ne $summary.PSObject.Properties["max_intraday_floating_dd_percent_of_day_balance"])
   $maxFloatingPctOfDayBalance = if ($hasMaxFloatingPctOfDayBalance) { To-Double $summary.max_intraday_floating_dd_percent_of_day_balance } else { 0.0 }
   $maxCombined = if ($null -ne $summary.PSObject.Properties["max_intraday_dd_plus_limit"]) { To-Double $summary.max_intraday_dd_plus_limit } else { To-Double $summary.max_intraday_floating_dd_with_limit_risk }
   $maxFloatingPositionsInDay = [int](To-Double $summary.max_floating_positions_in_day)
   $maxFloatingPositionsDay = [string]$summary.max_floating_positions_day
   $maxFloatingPositionsTime = [string]$summary.max_floating_positions_time

   $dailyRows = @(
      foreach ($d in @($TickDrawdown.daily)) {
         [pscustomobject]@{
            date = [string]$d.date
            day_start_balance = $(if ($null -ne $d.PSObject.Properties["day_start_balance"]) { To-Double $d.day_start_balance } else { 0.0 })
            max_floating_dd = To-Double $d.max_floating_dd
            max_floating_dd_percent_of_day_balance = $(if ($null -ne $d.PSObject.Properties["max_floating_dd_percent_of_day_balance"]) { To-Double $d.max_floating_dd_percent_of_day_balance } else { 0.0 })
            max_floating_dd_time = [string]$d.max_floating_dd_time
            max_pending_limit_risk = To-Double $d.max_pending_limit_risk
            max_pending_limit_risk_time = [string]$d.max_pending_limit_risk_time
            max_combined_dd = $(if ($null -ne $d.PSObject.Properties["max_dd_plus_limit"]) { To-Double $d.max_dd_plus_limit } else { To-Double $d.max_combined_dd })
            max_combined_dd_time = $(if ($null -ne $d.PSObject.Properties["max_dd_plus_limit_time"]) { [string]$d.max_dd_plus_limit_time } else { [string]$d.max_combined_dd_time })
            pending_limit_count_at_combined_peak = [int](To-Double $d.pending_limit_count_at_combined_peak)
            max_floating_positions = [int](To-Double $d.max_floating_positions)
            max_floating_positions_time = [string]$d.max_floating_positions_time
         }
      }
   )
   $dailyRows = @($dailyRows | Sort-Object date)

   if (-not $hasMaxFloatingPctOfDayBalance -and $dailyRows.Count -gt 0) {
      $bestPct = 0.0
      $foundPct = $false
      foreach ($row in $dailyRows) {
         $pct = To-Double $row.max_floating_dd_percent_of_day_balance
         if ($pct -gt 0) {
            if (-not $foundPct -or $pct -gt $bestPct) {
               $bestPct = $pct
               $foundPct = $true
            }
            continue
         }
         $base = To-Double $row.day_start_balance
         if ($base -gt 0 -and (To-Double $row.max_floating_dd) -gt 0) {
            $calcPct = ((To-Double $row.max_floating_dd) / $base) * 100.0
            if (-not $foundPct -or $calcPct -gt $bestPct) {
               $bestPct = $calcPct
               $foundPct = $true
            }
         }
      }
      if ($foundPct) {
         $maxFloatingPctOfDayBalance = $bestPct
         $hasMaxFloatingPctOfDayBalance = $true
      }
   }

   if ($dailyRows.Count -gt 0 -and ($maxFloatingPositionsInDay -le 0 -or [string]::IsNullOrWhiteSpace($maxFloatingPositionsDay))) {
      $bestFloatingDay = $null
      foreach ($row in $dailyRows) {
         if ($row.max_floating_positions -gt 0 -and ($null -eq $bestFloatingDay -or $row.max_floating_positions -gt $bestFloatingDay.max_floating_positions)) {
            $bestFloatingDay = $row
         }
      }
      if ($null -ne $bestFloatingDay) {
         $maxFloatingPositionsInDay = [int]$bestFloatingDay.max_floating_positions
         $maxFloatingPositionsDay = [string]$bestFloatingDay.date
         $maxFloatingPositionsTime = [string]$bestFloatingDay.max_floating_positions_time
      }
   }

   if ($maxFloatingPositionsInDay -le 0) {
      $maxFloatingPositionsDay = ""
      $maxFloatingPositionsTime = ""
   }
   $maxFloatingDayText = if ([string]::IsNullOrWhiteSpace($maxFloatingPositionsDay)) { "-" } else { $maxFloatingPositionsDay }
   $maxFloatingTimeText = if ([string]::IsNullOrWhiteSpace($maxFloatingPositionsTime)) { "-" } else { $maxFloatingPositionsTime }

   [void]$Builder.AppendLine("- Dias monitorados: **$daysCount**")
   [void]$Builder.AppendLine("- Max DD intraday flutuante (posicoes abertas): **" + (Format-Number $maxFloating) + "**")
   [void]$Builder.AppendLine("- Max DD intraday flutuante (posicoes abertas) em % do saldo do dia: **" + ($(if ($hasMaxFloatingPctOfDayBalance) { Format-Percent $maxFloatingPctOfDayBalance } else { "-" })) + "**")
   [void]$Builder.AppendLine("- Max DD+Limit (posicoes abertas no SL + LIMIT pendentes no SL): **" + (Format-Number $maxCombined) + "**")
   [void]$Builder.AppendLine("- Dia com mais operacoes flutuantes: **$maxFloatingDayText** (**$maxFloatingPositionsInDay** posicoes) | Hora do pico: **$maxFloatingTimeText**")
   [void]$Builder.AppendLine("")

   if ($dailyRows.Count -eq 0) {
      [void]$Builder.AppendLine("Nenhum registro diario em `tick_drawdown.daily`.")
      [void]$Builder.AppendLine("")
      return
   }

   [void]$Builder.AppendLine("### Detalhe Diario")
   [void]$Builder.AppendLine("")
   [void]$Builder.AppendLine("| Date | Max Floating DD | Hora Max Floating | Max LIMIT Risk | Hora Max LIMIT Risk | Max DD+Limit | Hora Max DD+Limit | Limits no Pico | Max Ops Flutuantes | Hora Max Ops |")
   [void]$Builder.AppendLine("|---|---:|---|---:|---|---:|---|---:|---:|---|")
   foreach ($row in $dailyRows) {
      $maxFloatingTimeText = if ([string]::IsNullOrWhiteSpace([string]$row.max_floating_dd_time)) { "-" } else { [string]$row.max_floating_dd_time }
      $maxPendingTimeText = if ([string]::IsNullOrWhiteSpace([string]$row.max_pending_limit_risk_time)) { "-" } else { [string]$row.max_pending_limit_risk_time }
      $maxCombinedTimeText = if ([string]::IsNullOrWhiteSpace([string]$row.max_combined_dd_time)) { "-" } else { [string]$row.max_combined_dd_time }
      $maxFloatingPositionsTimeText = if ([string]::IsNullOrWhiteSpace([string]$row.max_floating_positions_time)) { "-" } else { [string]$row.max_floating_positions_time }
      $line = "| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} | {8} | {9} |" -f `
         [string]$row.date, `
         (Format-Number $row.max_floating_dd), `
         $maxFloatingTimeText, `
         (Format-Number $row.max_pending_limit_risk), `
         $maxPendingTimeText, `
         (Format-Number $row.max_combined_dd), `
         $maxCombinedTimeText, `
         [int]$row.pending_limit_count_at_combined_peak, `
         [int]$row.max_floating_positions, `
         $maxFloatingPositionsTimeText
      [void]$Builder.AppendLine($line)
   }
   [void]$Builder.AppendLine("")
}

function Append-NoTrades-Section {
   param(
      [System.Text.StringBuilder]$Builder,
      [string]$SourcePath,
      [array]$NoTradeRows,
      [string]$SecondaryOpLabel = "PCM"
   )

   $rows = @($NoTradeRows)
   [void]$Builder.AppendLine("## Dias sem Operacao (NoTrade)")
   [void]$Builder.AppendLine("")
   [void]$Builder.AppendLine("- Arquivo fonte no-trades: $SourcePath")
   [void]$Builder.AppendLine("- Total de dias sem operacao: **$($rows.Count)**")
   $limitCanceledRows = @(
      $rows | Where-Object {
         $eventType = [string]$_.event_type
         $reasonText = [string]$_.reason
         ($eventType -eq "LIMIT_CANCELED_TARGET_REACHED") -or ($reasonText -like "Limit cancelada*")
      }
   )
   [void]$Builder.AppendLine("- Dias com LIMIT cancelada antes do fill: **$($limitCanceledRows.Count)**")
   $secondaryArmedRows = @(
      $limitCanceledRows | Where-Object {
         Resolve-NoTradePCMArmedFlag -Row $_ -EnablePCMOnNoTrade $false -PCMRuntimeLikelyEnabled $false
      }
   )
   [void]$Builder.AppendLine("- LIMIT cancelada com $SecondaryOpLabel armada por NoTrade: **$($secondaryArmedRows.Count)**")

   $limitCanceledWithMetrics = @(
      $limitCanceledRows | Where-Object {
         ($null -ne $_.missing_to_limit_points) -or ($null -ne $_.rr_max_reached)
      }
   )
   if ($limitCanceledWithMetrics.Count -gt 0) {
      $avgMissingToLimit = (
         $limitCanceledWithMetrics |
         Where-Object { $null -ne $_.missing_to_limit_points } |
         Measure-Object -Property missing_to_limit_points -Average
      ).Average
      $avgRRMaxReached = (
         $limitCanceledWithMetrics |
         Where-Object { $null -ne $_.rr_max_reached } |
         Measure-Object -Property rr_max_reached -Average
      ).Average
      [void]$Builder.AppendLine("- LIMIT cancelada (media) faltou: **$(Format-Number $avgMissingToLimit)** pts | RR max atingido: **$(Format-Number $avgRRMaxReached 3)**")
   }
   [void]$Builder.AppendLine("")

   if ($rows.Count -eq 0) {
      [void]$Builder.AppendLine("Nenhum registro em `no_trade_days`.")
      [void]$Builder.AppendLine("")
      return
   }

   $reasonGroups = @(
      $rows |
      Group-Object {
         $eventType = [string]$_.event_type
         if ([string]::IsNullOrWhiteSpace($eventType)) {
            $reasonText = [string]$_.reason
            if ($reasonText -like "Limit cancelada*") {
               return "LIMIT cancelada: alvo atingido antes da execucao"
            }
            return [string]$_.reason
         }
         if ($eventType -eq "LIMIT_CANCELED_TARGET_REACHED") {
            return "LIMIT cancelada: alvo atingido antes da execucao"
         }
         return $eventType
      } |
      Sort-Object @{ Expression = { $_.Count }; Descending = $true }, @{ Expression = { $_.Name }; Descending = $false }
   )

   [void]$Builder.AppendLine("### Resumo por Motivo")
   [void]$Builder.AppendLine("")
   [void]$Builder.AppendLine("| Motivo | Dias |")
   [void]$Builder.AppendLine("|---|---:|")
   foreach ($g in $reasonGroups) {
      [void]$Builder.AppendLine("| $([string]$g.Name) | $($g.Count) |")
   }
   [void]$Builder.AppendLine("")

   [void]$Builder.AppendLine("### Detalhes de Dias sem Operacao")
   [void]$Builder.AppendLine("")
   [void]$Builder.AppendLine("| # | Date | Reason | Channel Range | Timeframe | Faltou LIMIT (pts) | RR Max | RR Min | $SecondaryOpLabel armada por NoTrade |")
   [void]$Builder.AppendLine("|---:|---|---|---:|---|---:|---:|---:|---|")
   for ($i = 0; $i -lt $rows.Count; $i++) {
      $r = $rows[$i]
      $eventType = [string]$r.event_type
      $reasonText = [string]$r.reason
      $isLimitCanceledTarget = ($eventType -eq "LIMIT_CANCELED_TARGET_REACHED") -or ($reasonText -like "Limit cancelada*")
      $secondaryArmed = Resolve-NoTradePCMArmedFlag -Row $r -EnablePCMOnNoTrade $false -PCMRuntimeLikelyEnabled $false
      $pcmArmedLabel = if (-not $isLimitCanceledTarget) { "-" } elseif ($secondaryArmed) { $emojiTrue } else { $emojiFalse }
      $line = "| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} | {8} |" -f `
         ($i + 1), `
         [string]$r.date, `
         [string]$r.reason, `
         (Format-Number $r.channel_range), `
         [string]$r.timeframe, `
         (Format-Number $r.missing_to_limit_points), `
         (Format-Number $r.rr_max_reached 3), `
         (Format-Number $r.rr_min_required 3), `
         $pcmArmedLabel
      [void]$Builder.AppendLine($line)
   }
   [void]$Builder.AppendLine("")
}

function Append-Stats-Table {
   param(
      [System.Text.StringBuilder]$Builder,
      [string]$Title,
      [string]$GroupHeader,
      [array]$Groups
   )

   [void]$Builder.AppendLine("## $Title")
   [void]$Builder.AppendLine("")
   [void]$Builder.AppendLine("| $GroupHeader | Trades | TP | SL | Win Rate | Net Profit | Avg Profit | Profit Factor | Avg RR | Avg Range |")
   [void]$Builder.AppendLine("|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|")

   foreach ($g in $Groups) {
      $stats = New-Stats $g.rows
      $line = "| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} | {8} | {9} |" -f `
         [string]$g.name, `
         $stats.trades, `
         $stats.tp, `
         $stats.sl, `
         (Format-Percent $stats.win_rate), `
         (Format-Number $stats.net_profit), `
         (Format-Number $stats.avg_profit), `
         $stats.profit_factor_text, `
         (Format-Number $stats.avg_rr), `
         (Format-Number $stats.avg_range)
      [void]$Builder.AppendLine($line)
   }

   [void]$Builder.AppendLine("")
}

function Append-TopBottom-Table {
   param(
      [System.Text.StringBuilder]$Builder,
      [string]$Title,
      [array]$Rows,
      [int]$TakeCount,
      [bool]$Descending
   )

   $rows = @($Rows)
   $sorted = @()
   if ($Descending) {
      $sorted = @($rows | Sort-Object -Property profit -Descending | Select-Object -First $TakeCount)
   } else {
      $sorted = @($rows | Sort-Object -Property profit | Select-Object -First $TakeCount)
   }

   [void]$Builder.AppendLine("## $Title")
   [void]$Builder.AppendLine("")
   [void]$Builder.AppendLine("| # | Date | Entry Time | Exit Time | Direction | Entry Type | Result | Channel Range | RR | Profit |")
   [void]$Builder.AppendLine("|---:|---|---|---|---|---|---|---:|---:|---:|")

   for ($i = 0; $i -lt $sorted.Count; $i++) {
      $t = $sorted[$i]
      $line = "| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} | {8} | {9} |" -f `
         ($i + 1), `
         [string]$t.date, `
         [string]$t.entry_time, `
         [string]$t.exit_time, `
         [string]$t.direction, `
         [string]$t.entry_type, `
         [string]$t.result, `
         (Format-Number $t.channel_range), `
         (Format-Number $t.risk_reward), `
         (Format-Number $t.profit)
      [void]$Builder.AppendLine($line)
   }

   [void]$Builder.AppendLine("")
}

function Append-Trade-Table {
   param(
      [System.Text.StringBuilder]$Builder,
      [string]$Title,
      [array]$Rows,
      [string]$DistanceColumnHeader = "Dist. ate SL (%)",
      [string]$DistanceMetric = "max_adverse_to_sl_percent",
      [bool]$IncludeBothDistanceColumns = $false
   )

   [void]$Builder.AppendLine("## $Title")
   [void]$Builder.AppendLine("")
   [void]$Builder.AppendLine("- Total: **$($Rows.Count)**")
   [void]$Builder.AppendLine("")
   $headerSpecs = @(
      [pscustomobject]@{ Name = "Result"; Numeric = $false },
      [pscustomobject]@{ Name = "Flag Op"; Numeric = $false },
      [pscustomobject]@{ Name = "Date"; Numeric = $false },
      [pscustomobject]@{ Name = "Trigger Time"; Numeric = $false },
      [pscustomobject]@{ Name = "Entry Time"; Numeric = $false },
      [pscustomobject]@{ Name = "Exit Time"; Numeric = $false },
      [pscustomobject]@{ Name = "Direction"; Numeric = $false },
      [pscustomobject]@{ Name = "Entry Type"; Numeric = $false },
      [pscustomobject]@{ Name = "SL"; Numeric = $true },
      [pscustomobject]@{ Name = "TP"; Numeric = $true },
      [pscustomobject]@{ Name = "Channel Range"; Numeric = $true },
      [pscustomobject]@{ Name = "RR"; Numeric = $true }
   )
   if ($IncludeBothDistanceColumns) {
      $headerSpecs += @(
         [pscustomobject]@{ Name = "Dist. ate SL (%)"; Numeric = $true },
         [pscustomobject]@{ Name = "Dist. ate TP (%)"; Numeric = $true }
      )
   } else {
      $headerSpecs += @(
         [pscustomobject]@{ Name = $DistanceColumnHeader; Numeric = $true }
      )
   }
   $headerSpecs += @(
      [pscustomobject]@{ Name = "ADON Cnt"; Numeric = $true },
      [pscustomobject]@{ Name = "ADON Lots"; Numeric = $true },
      [pscustomobject]@{ Name = "ADON Avg Entry"; Numeric = $true },
      [pscustomobject]@{ Name = "ADON Profit"; Numeric = $true },
      [pscustomobject]@{ Name = "ADON"; Numeric = $true },
      [pscustomobject]@{ Name = "Max Floating Profit"; Numeric = $true },
      [pscustomobject]@{ Name = "Max Floating Drawdown"; Numeric = $true },
      [pscustomobject]@{ Name = "SLD"; Numeric = $true },
      [pscustomobject]@{ Name = "TurnOf"; Numeric = $true },
      [pscustomobject]@{ Name = "Triggered TurnOf"; Numeric = $true },
      [pscustomobject]@{ Name = ($script:SecondaryOpLabel + " BE"); Numeric = $true },
      [pscustomobject]@{ Name = ($script:SecondaryOpLabel + " Trail"); Numeric = $true },
      [pscustomobject]@{ Name = "Op Chain"; Numeric = $false },
      [pscustomobject]@{ Name = "Op Code"; Numeric = $false },
      [pscustomobject]@{ Name = "First Op"; Numeric = $true },
      [pscustomobject]@{ Name = "TurnOf Op"; Numeric = $true },
      [pscustomobject]@{ Name = "ADON Op"; Numeric = $true },
      [pscustomobject]@{ Name = "ADON Code"; Numeric = $false },
      [pscustomobject]@{ Name = "Profit"; Numeric = $true }
   )
   [void]$Builder.AppendLine("| " + (($headerSpecs | ForEach-Object { $_.Name }) -join " | ") + " |")
   [void]$Builder.AppendLine("|" + (($headerSpecs | ForEach-Object { if ($_.Numeric) { "---:" } else { "---" } }) -join "|") + "|")

   for ($i = 0; $i -lt $Rows.Count; $i++) {
      $trade = $Rows[$i]
      $distanceValue = 0.0
      $distanceSLValue = To-Double $trade.max_adverse_to_sl_percent
      $distanceTPValue = To-Double $trade.max_favorable_to_tp_percent
      if ($DistanceMetric -eq "entry_to_stop_percent") {
         $distanceValue = To-Double $trade.entry_to_stop_percent
      } elseif ($DistanceMetric -eq "entry_to_tp_percent") {
         $distanceValue = To-Double $trade.entry_to_tp_percent
      } elseif ($DistanceMetric -eq "max_favorable_to_tp_percent") {
         $distanceValue = To-Double $trade.max_favorable_to_tp_percent
      } else {
         $distanceValue = To-Double $trade.max_adverse_to_sl_percent
      }
      $flagOpCode = [string]$trade.operation_code
      if ([string]::IsNullOrWhiteSpace($flagOpCode) -or $flagOpCode -eq "-") {
         $fallbackChain = [string]$trade.operation_chain_code
         if ([string]::IsNullOrWhiteSpace($fallbackChain) -or $fallbackChain -eq "-") {
            $fallbackChain = "op$($i + 1)"
         }
         $flagOpCode = $fallbackChain
      }
      $lineCells = @(
         [string]$trade.result,
         $flagOpCode,
         [string]$trade.date,
         [string]$trade.trigger_time,
         [string]$trade.entry_time,
         [string]$trade.exit_time,
         [string]$trade.direction,
         [string]$trade.entry_type,
         (Format-Number $trade.stop_loss),
         (Format-Number $trade.take_profit),
         (Format-Number $trade.channel_range),
         (Format-Number $trade.risk_reward)
      )
      if ($IncludeBothDistanceColumns) {
         $lineCells += @(
            (Format-Percent $distanceSLValue),
            (Format-Percent $distanceTPValue)
         )
      } else {
         $lineCells += @(
            (Format-Percent $distanceValue)
         )
      }
      $lineCells += @(
         [int]$trade.addon_count,
         (Format-Number $trade.addon_total_lots),
         ($(if ([double]$trade.addon_total_lots -gt 0) { Format-Number $trade.addon_avg_entry_price } else { "-" })),
         (Format-Number $trade.addon_profit),
         ($(if ($trade.has_addon) { $script:emojiTrue } else { $script:emojiFalse })),
         (Format-Number $trade.max_floating_profit),
         (Format-Number $trade.max_floating_drawdown),
         ($(if ($trade.is_sliced) { $script:emojiTrue } else { $script:emojiFalse })),
         ($(if ($trade.is_reversal) { $script:emojiTrue } else { $script:emojiFalse })),
         ($(if ($trade.triggered_reversal) { $script:emojiTrue } else { $script:emojiFalse })),
         ($(if ($trade.pcm_break_even_applied) { $script:emojiTrue } else { $script:emojiFalse })),
         ($(if ($trade.pcm_trailling_stop_applied) { $script:emojiTrue } else { $script:emojiFalse })),
         [string]$trade.operation_chain_code,
         [string]$trade.operation_code,
         ($(if ($trade.is_first_operation) { $script:emojiTrue } else { $script:emojiFalse })),
         ($(if ($trade.is_turn_operation) { $script:emojiTrue } else { $script:emojiFalse })),
         ($(if ($trade.is_add_operation) { $script:emojiTrue } else { $script:emojiFalse })),
         [string]$trade.add_operation_code,
         (Format-Number $trade.profit)
      )
      $line = "| " + ($lineCells -join " | ") + " |"
      [void]$Builder.AppendLine($line)
   }

   [void]$Builder.AppendLine("")
}

$JsonPath = Normalize-LogPath -PathText $JsonPath
$NoTradesJsonPath = Normalize-LogPath -PathText $NoTradesJsonPath

if ([string]::IsNullOrWhiteSpace($JsonPath)) {
   throw "Informe o caminho do JSON de trades em -JsonPath."
}

if (-not (Test-Path -LiteralPath $JsonPath)) {
   throw "Arquivo JSON nao encontrado: $JsonPath"
}

$data = Get-Content -LiteralPath $JsonPath -Raw | ConvertFrom-Json
$rawTrades = @($data.trades)
$runConfig = $data.run_config
$tickDrawdownData = $data.tick_drawdown
$jsonFileName = [System.IO.Path]::GetFileName($JsonPath)
$script:IsHiran1Mode = ($jsonFileName.ToLowerInvariant().StartsWith("hiran1_"))
if (-not $script:IsHiran1Mode -and $null -ne $runConfig -and $null -ne $runConfig.selected_parameters) {
   $script:IsHiran1Mode = ($null -ne $runConfig.selected_parameters.PSObject.Properties["EnableRecontagem"])
}
$script:SecondaryOpLabel = if ($script:IsHiran1Mode) { "Recontagem" } else { "PCM" }
$script:SecondaryOpPrefix = if ($script:IsHiran1Mode) { "recontagem_" } else { "pcm_" }

$enableSecondaryOnNoTradeLimitTargetConfig = if ($script:IsHiran1Mode) {
   Get-RunParamBoolValue -SelectedParams $runConfig.selected_parameters -Name "EnableRecontagemOnNoTradeLimitTarget" -DefaultValue $false
} else {
   Get-RunParamBoolValue -SelectedParams $runConfig.selected_parameters -Name "EnablePCMOnNoTradeLimitTarget" -DefaultValue $false
}
if (-not $enableSecondaryOnNoTradeLimitTargetConfig) {
   $enableSecondaryOnNoTradeLimitTargetConfig = Get-RunParamBoolValue -SelectedParams $runConfig.selected_parameters -Name "EnableSecond_opOnNoTradeLimitTarget" -DefaultValue $false
}

$enableSecondaryConfig = if ($script:IsHiran1Mode) {
   Get-RunParamBoolValue -SelectedParams $runConfig.selected_parameters -Name "EnableRecontagem" -DefaultValue $false
} else {
   Get-RunParamBoolValue -SelectedParams $runConfig.selected_parameters -Name "EnablePCM" -DefaultValue $false
}
if (-not $enableSecondaryConfig) {
   $enableSecondaryConfig = Get-RunParamBoolValue -SelectedParams $runConfig.selected_parameters -Name "EnableSecond_op" -DefaultValue $false
}

$secondaryChannelBarsRaw = if ($script:IsHiran1Mode) {
   Get-RunParamValue -RunConfig $runConfig -Name "RecontagemChannelBars" -DefaultValue 0
} else {
   Get-RunParamValue -RunConfig $runConfig -Name "PCMChannelBars" -DefaultValue 0
}
$secondaryChannelBarsConfig = [int](To-Double $secondaryChannelBarsRaw)
if ($secondaryChannelBarsConfig -le 0) {
   $secondaryChannelBarsConfig = [int](To-Double (Get-RunParamValue -RunConfig $runConfig -Name "SecondOpChannelBars" -DefaultValue 0))
}

$secondaryMaxOperationsPerDayRaw = if ($script:IsHiran1Mode) {
   Get-RunParamValue -RunConfig $runConfig -Name "RecontagemMaxOperationsPerDay" -DefaultValue 0
} else {
   Get-RunParamValue -RunConfig $runConfig -Name "PCMMaxOperationsPerDay" -DefaultValue 0
}
$secondaryMaxOperationsPerDayConfig = [int](To-Double $secondaryMaxOperationsPerDayRaw)
if ($secondaryMaxOperationsPerDayConfig -le 0) {
   $secondaryMaxOperationsPerDayConfig = [int](To-Double (Get-RunParamValue -RunConfig $runConfig -Name "SecondOpMaxOperationsPerDay" -DefaultValue 0))
}

$secondaryReferenceTimeframeRaw = if ($script:IsHiran1Mode) {
   Get-RunParamRawValue -RunConfig $runConfig -Name "RecontagemReferenceTimeframe" -DefaultValue ""
} else {
   Get-RunParamRawValue -RunConfig $runConfig -Name "PCMReferenceTimeframe" -DefaultValue ""
}
$secondaryReferenceTimeframeConfig = [string]$secondaryReferenceTimeframeRaw
if ([string]::IsNullOrWhiteSpace($secondaryReferenceTimeframeConfig)) {
   $secondaryReferenceTimeframeConfig = [string](Get-RunParamRawValue -RunConfig $runConfig -Name "SecondOpReferenceTimeframe" -DefaultValue "")
}

$secondaryRuntimeLikelyEnabledConfig = if ($script:IsHiran1Mode) {
   (
      $enableSecondaryConfig -and
      ($secondaryChannelBarsConfig -ge 1) -and
      ($secondaryMaxOperationsPerDayConfig -gt 0) -and
      -not [string]::IsNullOrWhiteSpace($secondaryReferenceTimeframeConfig)
   )
} else {
   (
      $enableSecondaryConfig -and
      ($secondaryChannelBarsConfig -ge 4) -and
      ($secondaryMaxOperationsPerDayConfig -gt 0) -and
      ($secondaryReferenceTimeframeConfig -in @("PERIOD_M1", "PERIOD_M5", "PERIOD_M15"))
   )
}

$defaultOutputPath = "docs/relatorios/operacoes/RELATORIO_OPERACOES_JSON.md"
$normalizedOutputPath = ([string]$OutputPath).Trim() -replace '/', '\'
$normalizedDefaultOutputPath = $defaultOutputPath -replace '/', '\'
if ([string]::IsNullOrWhiteSpace($OutputPath) -or $normalizedOutputPath.Equals($normalizedDefaultOutputPath, [System.StringComparison]::OrdinalIgnoreCase)) {
   $OutputPath = Resolve-StandardOutputPath -RunConfig $runConfig -TickDrawdown $tickDrawdownData -RawTrades $rawTrades
}

$resolvedNoTradesPath = Resolve-NoTradesJsonPath -TradesPath $JsonPath -ExplicitNoTradesPath $NoTradesJsonPath
$hasNoTradesFile = (-not [string]::IsNullOrWhiteSpace($resolvedNoTradesPath)) -and (Test-Path -LiteralPath $resolvedNoTradesPath)
$noTradesData = $null
$noTradeRows = @()

if ($hasNoTradesFile) {
   try {
      $noTradesData = Get-Content -LiteralPath $resolvedNoTradesPath -Raw | ConvertFrom-Json
      $noTradeRows = @(
      foreach ($n in @($noTradesData.no_trade_days)) {
         $missingToLimitPointsValue = To-NullableDouble $n.missing_to_limit_points
         $rrMaxReachedValue = To-NullableDouble $n.rr_max_reached
         $rrMinRequiredValue = To-NullableDouble $n.rr_min_required
         [pscustomobject]@{
            date = [string]$n.date
            reason = [string]$n.reason
            channel_range = To-Double $n.channel_range
            timeframe = [string]$n.timeframe
            event_type = [string]$n.event_type
            entry_direction = Normalize-Direction $n.entry_direction
            limit_price = To-NullableDouble $n.limit_price
            closest_price = To-NullableDouble $n.closest_price
            stop_loss = To-NullableDouble $n.stop_loss
            take_profit = To-NullableDouble $n.take_profit
            missing_to_limit_points = $missingToLimitPointsValue
            rr_max_reached = $rrMaxReachedValue
            rr_min_required = $rrMinRequiredValue
            pcm_armed_from_notrade = Resolve-NoTradePCMArmedFlag -Row $n -EnablePCMOnNoTrade $enableSecondaryOnNoTradeLimitTargetConfig -PCMRuntimeLikelyEnabled $secondaryRuntimeLikelyEnabledConfig
         }
      }
      )
      $noTradeRows = @($noTradeRows | Sort-Object date, timeframe, reason)
      if ($null -eq $tickDrawdownData -and $null -ne $noTradesData) {
         $tickDrawdownData = $noTradesData.tick_drawdown
      }
   } catch {
      Write-Warning ("Falha ao ler no-trades: " + $resolvedNoTradesPath + " | " + $_.Exception.Message)
      $noTradeRows = @()
      $hasNoTradesFile = $false
   }
}

if ($rawTrades.Count -eq 0) {
   throw "Nenhuma operacao encontrada no JSON: $JsonPath"
}

$cfgMinRange = Get-RunParamValue -RunConfig $runConfig -Name "MinChannelRange" -DefaultValue 0.0
$cfgMaxRange = Get-RunParamValue -RunConfig $runConfig -Name "MaxChannelRange" -DefaultValue 0.0
$cfgSliced = Get-RunParamValue -RunConfig $runConfig -Name "SlicedThreshold" -DefaultValue 0.0
$cfgMinRR = Get-RunParamValue -RunConfig $runConfig -Name "MinRiskReward" -DefaultValue 0.8

if ($cfgSliced -lt $cfgMaxRange) { $cfgSliced = $cfgMaxRange }

$enrichedTrades = @()
for ($tradeIndex = 0; $tradeIndex -lt $rawTrades.Count; $tradeIndex++) {
   $t = $rawTrades[$tradeIndex]
   $entryTimeText = [string]$t.entry_time
   $exitTimeText = [string]$t.exit_time
   $entryDt = Parse-TradeDateTime $entryTimeText
   $exitDt = Parse-TradeDateTime $exitTimeText
   $triggerTimeText = [string]$t.trigger_time
   $triggerDt = Parse-TradeDateTime $triggerTimeText
   $channelDefText = Resolve-Channel-Definition-Time -Trade $t -OpenHour $OpeningHour -OpenMinute $OpeningMinute
   $channelDefDt = Parse-TradeDateTime $channelDefText
   $addOnCountValue = [int](To-Double $t.addon_count)
   $addOnLotsValue = To-Double $t.addon_total_lots
   $addOnAvgEntryValue = To-Double $t.addon_avg_entry_price
   $addOnProfitValue = To-Double $t.addon_profit
   $hasAddOnValue = ($addOnCountValue -gt 0) -or (Is-True $t.has_addon)
   $entryPriceValue = To-Double $t.entry_price
   $stopLossValue = To-Double $t.stop_loss
   $takeProfitValue = To-Double $t.take_profit
   $entryToStopPercentValue = 0.0
   if ($entryPriceValue -gt 0.0 -and $stopLossValue -gt 0.0) {
      $entryToStopPercentValue = ([math]::Abs($entryPriceValue - $stopLossValue) / $entryPriceValue) * 100.0
   }
   $entryToTPPercentValue = 0.0
   if ($entryPriceValue -gt 0.0 -and $takeProfitValue -gt 0.0) {
      $entryToTPPercentValue = ([math]::Abs($entryPriceValue - $takeProfitValue) / $entryPriceValue) * 100.0
   }
   $riskRewardValue = To-Double $t.risk_reward
   $hasProfitNetProp = ($null -ne $t.PSObject.Properties["profit_net"]) -and -not [string]::IsNullOrWhiteSpace([string]$t.profit_net)
   $profitValue = if ($hasProfitNetProp) { To-Double $t.profit_net } else { To-Double $t.profit }
   $profitGrossValue = if (($null -ne $t.PSObject.Properties["profit_gross"]) -and -not [string]::IsNullOrWhiteSpace([string]$t.profit_gross)) { To-Double $t.profit_gross } else { $profitValue }
   $swapValue = if (($null -ne $t.PSObject.Properties["swap"]) -and -not [string]::IsNullOrWhiteSpace([string]$t.swap)) { To-Double $t.swap } else { 0.0 }
   $commissionValue = if (($null -ne $t.PSObject.Properties["commission"]) -and -not [string]::IsNullOrWhiteSpace([string]$t.commission)) { To-Double $t.commission } else { 0.0 }
   $feeValue = if (($null -ne $t.PSObject.Properties["fee"]) -and -not [string]::IsNullOrWhiteSpace([string]$t.fee)) { To-Double $t.fee } else { 0.0 }
   $costsTotalValue = if (($null -ne $t.PSObject.Properties["costs_total"]) -and -not [string]::IsNullOrWhiteSpace([string]$t.costs_total)) {
      To-Double $t.costs_total
   } else {
      $swapValue + $commissionValue + $feeValue
   }
   $maxFloatingProfitValue = To-Double $t.max_floating_profit
   $maxFavorableToTPPercentValue = 0.0
   $hasMaxFavorableProp = ($null -ne $t.PSObject.Properties["max_favorable_to_tp_percent"])
   if ($hasMaxFavorableProp -and -not [string]::IsNullOrWhiteSpace([string]$t.max_favorable_to_tp_percent)) {
      $maxFavorableToTPPercentValue = To-Double $t.max_favorable_to_tp_percent
   } elseif ($riskRewardValue -gt 0.0 -and $profitValue -lt 0.0) {
      $tpReferenceProfitAbs = [math]::Abs($profitValue) * $riskRewardValue
      if ($tpReferenceProfitAbs -gt 0.0) {
         $maxFavorableToTPPercentValue = ([math]::Max(0.0, $maxFloatingProfitValue) / $tpReferenceProfitAbs) * 100.0
      }
   }
   if ($maxFavorableToTPPercentValue -lt 0.0) { $maxFavorableToTPPercentValue = 0.0 }
   if ($maxFavorableToTPPercentValue -gt 100.0) { $maxFavorableToTPPercentValue = 100.0 }
   $hasMaxAdverseProp = ($null -ne $t.PSObject.Properties["max_adverse_to_sl_percent"])
   $maxAdverseToSLPercentValue = 0.0
   if ($hasMaxAdverseProp -and -not [string]::IsNullOrWhiteSpace([string]$t.max_adverse_to_sl_percent)) {
      $maxAdverseToSLPercentValue = To-Double $t.max_adverse_to_sl_percent
   } elseif ([string]$t.result -eq "SL") {
      $maxAdverseToSLPercentValue = 100.0
   }

   $operationChainCodeValue = Resolve-Operation-ChainCode -Trade $t -FallbackIndex ($tradeIndex + 1)
   $isTurnOperationValue = Is-True $t.is_turn_operation
   if (-not $isTurnOperationValue) {
      $isTurnOperationValue = Is-True $t.is_reversal
   }
   $isPcmOperationValue = Is-True $t.is_pcm_operation
   if (-not $isPcmOperationValue) { $isPcmOperationValue = Is-True $t.is_recontagem_operation }
   if (-not $isPcmOperationValue) { $isPcmOperationValue = Is-True $t.is_Recontagem_operation }
   if (-not $isPcmOperationValue) { $isPcmOperationValue = Is-True $t.is_second_op_operation }
   if (-not $isPcmOperationValue) { $isPcmOperationValue = Is-True $t.is_Second_op_operation }
   $hasFirstOperationProp = ($null -ne $t.PSObject.Properties["is_first_operation"])
   $isFirstOperationValue = if ($hasFirstOperationProp) { Is-True $t.is_first_operation } else { -not $isTurnOperationValue }
   $hasAddOperationProp = ($null -ne $t.PSObject.Properties["is_add_operation"])
   $isAddOperationValue = if ($hasAddOperationProp) { Is-True $t.is_add_operation } else { $hasAddOnValue }
   $operationCodeRaw = if ($null -ne $t.PSObject.Properties["operation_code"]) { [string]$t.operation_code } else { "" }
   $addOperationCodeRaw = if ($null -ne $t.PSObject.Properties["add_operation_code"]) { [string]$t.add_operation_code } else { "" }
   if (-not $isPcmOperationValue -and -not [string]::IsNullOrWhiteSpace($operationCodeRaw)) {
      $operationCodeRawNorm = $operationCodeRaw.ToLowerInvariant()
      if ($operationCodeRawNorm.StartsWith("pcm_") -or $operationCodeRawNorm.StartsWith("recontagem_") -or $operationCodeRawNorm.StartsWith("second_op_")) {
         $isPcmOperationValue = $true
      }
   }
   $hasAddCodeHint = (
      (-not [string]::IsNullOrWhiteSpace($operationCodeRaw) -and $operationCodeRaw -like "add_*") -or
      (-not [string]::IsNullOrWhiteSpace($addOperationCodeRaw) -and $addOperationCodeRaw -like "add_*")
   )

   $profitVsAddOnDiff = [double]::MaxValue
   $entryVsAddOnDiff = [double]::MaxValue
   if ($addOnCountValue -gt 0) {
      $profitVsAddOnDiff = [math]::Abs($profitValue - $addOnProfitValue)
      if ($addOnLotsValue -gt 0.0 -and $addOnAvgEntryValue -gt 0.0) {
         $entryVsAddOnDiff = [math]::Abs($entryPriceValue - $addOnAvgEntryValue)
      }
   }
   $looksLikePureAddTicket = ($addOnCountValue -gt 0) -and (($profitVsAddOnDiff -le 0.01) -or ($entryVsAddOnDiff -le 0.01))

   # Recupera classificacao de add quando JSON vier inconsistente.
   if (-not $isAddOperationValue -and ($hasAddCodeHint -or $looksLikePureAddTicket)) {
      $isAddOperationValue = $true
   }
   # Protege contra falso positivo quando nao ha nenhum indicio de ticket add.
   if ($isAddOperationValue -and -not ($hasAddCodeHint -or $looksLikePureAddTicket)) {
      $isAddOperationValue = $false
   }
   if ($isPcmOperationValue) {
      $isFirstOperationValue = $false
      $isTurnOperationValue = $false
      $isAddOperationValue = $false
   } elseif ($isAddOperationValue) {
      $isFirstOperationValue = $false
   } elseif (-not $isTurnOperationValue) {
      $isFirstOperationValue = $true
   }
   $hasExplicitOperationCodeValue = (
      ($null -ne $t.PSObject.Properties["operation_chain_code"] -and -not [string]::IsNullOrWhiteSpace([string]$t.operation_chain_code)) -or
      ($null -ne $t.PSObject.Properties["operation_code"] -and -not [string]::IsNullOrWhiteSpace([string]$t.operation_code)) -or
      ($null -ne $t.PSObject.Properties["operation_chain_id"] -and -not [string]::IsNullOrWhiteSpace([string]$t.operation_chain_id))
   )
   $operationCodeValue = Resolve-Operation-Code -Trade $t -ChainCode $operationChainCodeValue -IsTurn $isTurnOperationValue
   $addOperationCodeValue = Resolve-Add-Operation-Code -Trade $t -ChainCode $operationChainCodeValue -HasAdd $isAddOperationValue
   if ($isAddOperationValue) {
      if (([string]::IsNullOrWhiteSpace($addOperationCodeValue) -or $addOperationCodeValue -eq "-") -and -not [string]::IsNullOrWhiteSpace($operationChainCodeValue)) {
         $addOperationCodeValue = ("add_" + $operationChainCodeValue)
      }
      if (-not [string]::IsNullOrWhiteSpace($addOperationCodeValue) -and $addOperationCodeValue -ne "-") {
         $operationCodeValue = $addOperationCodeValue
      }
   } else {
      $addOperationCodeValue = "-"
      if ($isPcmOperationValue -and -not [string]::IsNullOrWhiteSpace($operationChainCodeValue)) {
         if (
            [string]::IsNullOrWhiteSpace($operationCodeValue) -or
            $operationCodeValue -eq "-" -or
            $operationCodeValue -like "add_*" -or
            $operationCodeValue -like "first_*" -or
            $operationCodeValue -like "second_op_*"
         ) {
            $operationCodeValue = ($script:SecondaryOpPrefix + $operationChainCodeValue)
         }
      } elseif (-not $isTurnOperationValue -and -not [string]::IsNullOrWhiteSpace($operationChainCodeValue)) {
         if ([string]::IsNullOrWhiteSpace($operationCodeValue) -or $operationCodeValue -eq "-" -or $operationCodeValue -like "add_*") {
            $operationCodeValue = ("first_" + $operationChainCodeValue)
         }
      }
   }
   $pcmBreakEvenAppliedValue = Is-True $t.pcm_break_even_applied
   if (-not $pcmBreakEvenAppliedValue) { $pcmBreakEvenAppliedValue = Is-True $t.recontagem_break_even_applied }
   if (-not $pcmBreakEvenAppliedValue) { $pcmBreakEvenAppliedValue = Is-True $t.Recontagem_break_even_applied }
   if (-not $pcmBreakEvenAppliedValue) { $pcmBreakEvenAppliedValue = Is-True $t.second_op_break_even_applied }
   if (-not $pcmBreakEvenAppliedValue) { $pcmBreakEvenAppliedValue = Is-True $t.Second_op_break_even_applied }
   $pcmTraillingStopAppliedValue = Is-True $t.pcm_trailling_stop_applied
   if (-not $pcmTraillingStopAppliedValue) { $pcmTraillingStopAppliedValue = Is-True $t.recontagem_trailling_stop_applied }
   if (-not $pcmTraillingStopAppliedValue) { $pcmTraillingStopAppliedValue = Is-True $t.Recontagem_trailling_stop_applied }
    if (-not $pcmTraillingStopAppliedValue) { $pcmTraillingStopAppliedValue = Is-True $t.second_op_trailling_stop_applied }
    if (-not $pcmTraillingStopAppliedValue) { $pcmTraillingStopAppliedValue = Is-True $t.Second_op_trailling_stop_applied }
   if (-not $pcmTraillingStopAppliedValue) {
      $pcmTraillingStopAppliedValue = Is-True $t.pcm_trailing_stop_applied
   }
   if (-not $pcmTraillingStopAppliedValue) {
      $pcmTraillingStopAppliedValue = Is-True $t.second_op_trailing_stop_applied
   }
   if (-not $pcmTraillingStopAppliedValue) {
      $pcmTraillingStopAppliedValue = Is-True $t.Second_op_trailing_stop_applied
   }
   $resultValue = [string]$t.result
   $resultNorm = $resultValue.Trim().ToUpperInvariant()
   if ($isPcmOperationValue) {
      if ($pcmTraillingStopAppliedValue -and $resultNorm -eq "SL") {
         $resultValue = "TP"
         $resultNorm = "TP"
      } elseif ($pcmBreakEvenAppliedValue -and $resultNorm -eq "SL") {
         $resultValue = "BE"
         $resultNorm = "BE"
      }
   }
   if ([string]::IsNullOrWhiteSpace($resultNorm)) {
      if ($profitValue -gt 0.0) {
         $resultValue = "TP"
      } elseif ($profitValue -lt 0.0) {
         $resultValue = "SL"
      }
   }

   $enrichedTrades += [pscustomobject]@{
      date = [string]$t.date
      trigger_time = $triggerTimeText
      entry_time = $entryTimeText
      exit_time = $exitTimeText
      channel_def_time = $channelDefText
      channel_def_dt = $channelDefDt
      direction = Normalize-Direction $t.direction
      entry_type = Resolve-Entry-Execution-Type $t
      timeframe = [string]$t.timeframe
      entry_price = $entryPriceValue
      exit_price = To-Double $t.exit_price
      stop_loss = $stopLossValue
      take_profit = $takeProfitValue
      channel_range = To-Double $t.channel_range
      risk_reward = $riskRewardValue
      max_adverse_to_sl_percent = $maxAdverseToSLPercentValue
      entry_to_stop_percent = $entryToStopPercentValue
      entry_to_tp_percent = $entryToTPPercentValue
      max_favorable_to_tp_percent = $maxFavorableToTPPercentValue
      addon_count = $addOnCountValue
      addon_total_lots = $addOnLotsValue
      addon_avg_entry_price = $addOnAvgEntryValue
      addon_profit = $addOnProfitValue
      has_addon = $hasAddOnValue
      max_floating_profit = $maxFloatingProfitValue
      max_floating_drawdown = To-Double $t.max_floating_drawdown
      is_sliced = Is-True $t.is_sliced
      is_reversal = Is-True $t.is_reversal
      triggered_reversal = Is-True $t.triggered_reversal
      operation_chain_code = $operationChainCodeValue
      operation_code = $operationCodeValue
      add_operation_code = $addOperationCodeValue
      is_first_operation = $isFirstOperationValue
      is_turn_operation = $isTurnOperationValue
      is_pcm_operation = $isPcmOperationValue
      is_add_operation = $isAddOperationValue
      pcm_break_even_applied = $pcmBreakEvenAppliedValue
      pcm_trailling_stop_applied = $pcmTraillingStopAppliedValue
      is_add_duplicate_of_cycle = $false
      has_explicit_operation_code = $hasExplicitOperationCodeValue
      result = [string]$resultValue
      profit_gross = $profitGrossValue
      swap = $swapValue
      commission = $commissionValue
      fee = $feeValue
      costs_total = $costsTotalValue
      profit = $profitValue
      trigger_dt = $triggerDt
      entry_dt = $entryDt
      exit_dt = $exitDt
      day_of_week = Get-WeekdayName $entryDt
      day_of_week_key = if ($null -eq $entryDt) { -1 } else { [int]$entryDt.DayOfWeek }
      entry_hour = if ($null -eq $entryDt) { -1 } else { [int]$entryDt.Hour }
   }
}

# Fallback chain inference for legacy logs without explicit operation codes.
$legacyRows = @($enrichedTrades | Where-Object { -not $_.has_explicit_operation_code })
if ($legacyRows.Count -gt 0) {
   $maxChainNumeric = 0
   foreach ($r in $enrichedTrades) {
      $chainText = [string]$r.operation_chain_code
      if ($chainText -match '^op(\d+)$') {
         $num = [int]$Matches[1]
         if ($num -gt $maxChainNumeric) { $maxChainNumeric = $num }
      }
   }

   $nextChainNumeric = if ($maxChainNumeric -gt 0) { $maxChainNumeric + 1 } else { 1 }
   $pendingReversalChain = ""
   $chronological = @(
      $enrichedTrades |
      Sort-Object `
         @{ Expression = { if ($_.entry_dt -ne $null) { $_.entry_dt } else { [datetime]::MaxValue } }; Descending = $false }, `
         @{ Expression = { if ($_.exit_dt -ne $null) { $_.exit_dt } else { [datetime]::MaxValue } }; Descending = $false }
   )

   foreach ($row in $chronological) {
      if ($row.has_explicit_operation_code) {
         if ($row.triggered_reversal) {
            $pendingReversalChain = [string]$row.operation_chain_code
         } else {
            $pendingReversalChain = ""
         }
         continue
      }

      $resolvedChain = [string]$row.operation_chain_code
      if ($row.is_turn_operation -and -not [string]::IsNullOrWhiteSpace($pendingReversalChain)) {
         $resolvedChain = $pendingReversalChain
      } elseif ($resolvedChain -match '^op(\d+)$') {
         $num = [int]$Matches[1]
         if ($num -ge $nextChainNumeric) {
            $nextChainNumeric = $num + 1
         }
      } else {
         $resolvedChain = ("op" + [string]$nextChainNumeric)
         $nextChainNumeric++
      }

      $row.operation_chain_code = $resolvedChain
      $row.add_operation_code = if ($row.is_add_operation) { ("add_" + $resolvedChain) } else { "-" }
      if ($row.is_add_operation) {
         $row.operation_code = $row.add_operation_code
         $row.is_first_operation = $false
      } elseif ($row.is_pcm_operation) {
         $row.operation_code = ($script:SecondaryOpPrefix + $resolvedChain)
         $row.is_first_operation = $false
         $row.is_turn_operation = $false
      } elseif ($row.is_turn_operation) {
         $row.operation_code = ("turn_" + $resolvedChain)
      } else {
         $row.operation_code = ("first_" + $resolvedChain)
      }

      if ($row.triggered_reversal) {
         $pendingReversalChain = $resolvedChain
      } else {
         $pendingReversalChain = ""
      }
   }
}

# Reconcile operation flags and reversal trigger consistency.
$turnChains = @{}
foreach ($row in $enrichedTrades) {
   $chain = [string]$row.operation_chain_code
   if ([string]::IsNullOrWhiteSpace($chain) -or $chain -eq "-") { continue }
   if ($row.is_turn_operation) {
      $turnChains[$chain] = $true
   }
}
foreach ($row in $enrichedTrades) {
   $chain = [string]$row.operation_chain_code
   if ([string]::IsNullOrWhiteSpace($chain) -or $chain -eq "-") { continue }

   if ($row.is_add_operation) {
      $row.is_first_operation = $false
      if ([string]::IsNullOrWhiteSpace([string]$row.add_operation_code) -or [string]$row.add_operation_code -eq "-") {
         $row.add_operation_code = ("add_" + $chain)
      }
      if (-not [string]::IsNullOrWhiteSpace([string]$row.add_operation_code) -and [string]$row.add_operation_code -ne "-") {
         $row.operation_code = [string]$row.add_operation_code
      }
   } elseif ($row.is_pcm_operation) {
      $row.is_first_operation = $false
      $row.is_turn_operation = $false
      if (
         [string]::IsNullOrWhiteSpace([string]$row.operation_code) -or
         [string]$row.operation_code -eq "-" -or
         [string]$row.operation_code -like "first_*" -or
         [string]$row.operation_code -like "second_op_*"
      ) {
         $row.operation_code = ($script:SecondaryOpPrefix + $chain)
      }
   }

   if (-not $row.is_turn_operation -and -not $row.is_add_operation -and -not $row.is_pcm_operation -and [string]$row.result -eq "SL") {
      $row.triggered_reversal = $turnChains.ContainsKey($chain)
   }
}

# Identifica linhas add_op que duplicam o mesmo lucro ja agregado em first/turn.
# Criterio: mesmo operation_chain_code + exit_time, com linha base contendo addon_count>0 e
# addon_profit ~= soma(profit) das linhas add daquele fechamento.
$rowsByChainExit = @{}
foreach ($row in $enrichedTrades) {
   $chainKey = [string]$row.operation_chain_code
   $exitKey = [string]$row.exit_time
   $groupKey = $chainKey + "|" + $exitKey
   if (-not $rowsByChainExit.ContainsKey($groupKey)) {
      $rowsByChainExit[$groupKey] = @()
   }
   $rowsByChainExit[$groupKey] += $row
}

foreach ($bucket in $rowsByChainExit.Values) {
   $groupRows = @($bucket)
   $addRows = @($groupRows | Where-Object { $_.is_add_operation })
   $baseRows = @($groupRows | Where-Object { -not $_.is_add_operation })
   if ($addRows.Count -eq 0 -or $baseRows.Count -eq 0) { continue }

   $sumAddProfit = To-Double (($addRows | Measure-Object -Property profit -Sum).Sum)
   $hasAggregateMatch = $false
   foreach ($baseRow in $baseRows) {
      $baseAddCount = [int](To-Double $baseRow.addon_count)
      $baseAddProfit = To-Double $baseRow.addon_profit
      if ($baseAddCount -le 0) { continue }
      if ([math]::Abs($baseAddProfit) -le 0.01) { continue }
      if ([math]::Abs($baseAddProfit - $sumAddProfit) -le 0.02) {
         $hasAggregateMatch = $true
         break
      }
   }

   if ($hasAggregateMatch) {
      foreach ($addRow in $addRows) {
         $addRow.is_add_duplicate_of_cycle = $true
      }
   }
}

$calculationTrades = @($enrichedTrades | Where-Object { -not $_.is_add_duplicate_of_cycle })
if ($calculationTrades.Count -eq 0) {
   $calculationTrades = @($enrichedTrades)
}

$orderedTrades = @(
   $calculationTrades |
   Sort-Object `
      @{ Expression = { if ($_.exit_dt -ne $null) { $_.exit_dt } else { [datetime]::MaxValue } }; Descending = $false }, `
      @{ Expression = { if ($_.entry_dt -ne $null) { $_.entry_dt } else { [datetime]::MaxValue } }; Descending = $false }
)

$entryTimes = @($enrichedTrades | Where-Object { $_.entry_dt -ne $null } | Sort-Object entry_dt)
$exitTimes = @($enrichedTrades | Where-Object { $_.exit_dt -ne $null } | Sort-Object exit_dt)
$periodStart = if ($entryTimes.Count -gt 0) { $entryTimes[0].entry_dt.ToString("yyyy.MM.dd HH:mm", $invariant) } else { [string]($enrichedTrades[0].entry_time) }
$periodEnd = if ($exitTimes.Count -gt 0) { $exitTimes[-1].exit_dt.ToString("yyyy.MM.dd HH:mm", $invariant) } else { [string]($enrichedTrades[-1].exit_time) }

$totalTradesRaw = $enrichedTrades.Count
$totalTrades = $calculationTrades.Count
$nonAddTrades = @(
   $enrichedTrades |
   Where-Object {
      $opCode = ([string]$_.operation_code).ToLowerInvariant()
      $addCode = ([string]$_.add_operation_code).ToLowerInvariant()
      -not $_.is_add_operation -and
      -not $opCode.StartsWith("add_") -and
      -not $opCode.StartsWith("adon_") -and
      -not $addCode.StartsWith("add_") -and
      -not $addCode.StartsWith("adon_")
   }
)
$firstOpTrades = @(
   $nonAddTrades |
   Where-Object {
      $opCode = ([string]$_.operation_code).ToLowerInvariant()
      (-not $_.is_pcm_operation) -and
      (-not $_.is_turn_operation) -and
      (-not $_.is_reversal) -and
      ($_.is_first_operation -or $opCode.StartsWith("first_"))
   }
)
$turnofTrades = @(
   $nonAddTrades |
   Where-Object {
      $opCode = ([string]$_.operation_code).ToLowerInvariant()
      (-not $_.is_pcm_operation) -and
      ($_.is_turn_operation -or $_.is_reversal -or $opCode.StartsWith("turn_"))
   }
)

$tpTrades = @($firstOpTrades | Where-Object { $_.result -eq "TP" })
$slTrades = @($firstOpTrades | Where-Object { $_.result -eq "SL" })
$beTrades = @($firstOpTrades | Where-Object { $_.result -eq "BE" })
$reversalTrades = @($turnofTrades)
$turnofTpTrades = @($turnofTrades | Where-Object { $_.result -eq "TP" })
$turnofSlTrades = @($turnofTrades | Where-Object { $_.result -eq "SL" })
$turnofBeTrades = @($turnofTrades | Where-Object { $_.result -eq "BE" })
$pcmTrades = @($nonAddTrades | Where-Object { $_.is_pcm_operation })
$pcmTpTrades = @($pcmTrades | Where-Object { $_.result -eq "TP" })
$pcmSlTrades = @($pcmTrades | Where-Object { $_.result -eq "SL" })
$pcmBeTrades = @($pcmTrades | Where-Object { $_.result -eq "BE" })
$summaryTpCount = @($calculationTrades | Where-Object { $_.result -eq "TP" }).Count
$summarySlCount = @($calculationTrades | Where-Object { $_.result -eq "SL" }).Count
$summaryBeCount = @($calculationTrades | Where-Object { $_.result -eq "BE" }).Count
$summaryReversalCount = @($calculationTrades | Where-Object { $_.is_reversal }).Count
$triggeredReversalCount = @($calculationTrades | Where-Object { $_.triggered_reversal }).Count
$slicedCount = @($calculationTrades | Where-Object { $_.is_sliced }).Count
$buyCount = @($calculationTrades | Where-Object { $_.direction -eq "BUY" }).Count
$sellCount = @($calculationTrades | Where-Object { $_.direction -eq "SELL" }).Count
$addOnTrades = @($calculationTrades | Where-Object { $_.has_addon })
$addOnTradesCount = $addOnTrades.Count
# Secao AddOn puro: somente operacoes classificadas como ticket add.
$addOperationTrades = @($enrichedTrades | Where-Object { $_.is_add_operation })
$addOperationTradesCount = $addOperationTrades.Count
$addOnMetricsByChainExit = @{}
foreach ($addRow in $addOperationTrades) {
   $key = ([string]$addRow.operation_chain_code) + "|" + ([string]$addRow.exit_time)
   $addMfProfit = To-Double $addRow.max_floating_profit
   $addMfDrawdown = To-Double $addRow.max_floating_drawdown
   if (-not $addOnMetricsByChainExit.ContainsKey($key)) {
      $addOnMetricsByChainExit[$key] = [pscustomobject]@{
         max_floating_profit = $addMfProfit
         max_floating_drawdown = $addMfDrawdown
      }
   } else {
      $agg = $addOnMetricsByChainExit[$key]
      if ($addMfProfit -gt (To-Double $agg.max_floating_profit)) {
         $agg.max_floating_profit = $addMfProfit
      }
      if ($addMfDrawdown -lt (To-Double $agg.max_floating_drawdown)) {
         $agg.max_floating_drawdown = $addMfDrawdown
      }
   }
}

$addOnTradesDisplay = @()
foreach ($row in $addOnTrades) {
   $key = ([string]$row.operation_chain_code) + "|" + ([string]$row.exit_time)
   if (-not $addOnMetricsByChainExit.ContainsKey($key)) {
      $addOnTradesDisplay += $row
      continue
   }

   $rowCloneMap = [ordered]@{}
   foreach ($prop in $row.PSObject.Properties) {
      $rowCloneMap[[string]$prop.Name] = $prop.Value
   }
   $rowClone = [pscustomobject]$rowCloneMap
   $aggMetrics = $addOnMetricsByChainExit[$key]
   $rowClone.max_floating_profit = To-Double $aggMetrics.max_floating_profit
   $rowClone.max_floating_drawdown = To-Double $aggMetrics.max_floating_drawdown
   $addOnTradesDisplay += $rowClone
}

$addOnTrades = $addOnTradesDisplay
$totalAddOnEntries = $addOperationTradesCount
$totalAddOnLots = To-Double (($addOperationTrades | Measure-Object -Property addon_total_lots -Sum).Sum)
$totalAddOnProfit = To-Double (($addOperationTrades | Measure-Object -Property profit -Sum).Sum)
if ($totalAddOnEntries -le 0 -and $addOnTradesCount -gt 0) { $totalAddOnEntries = $addOnTradesCount }
$firstOperationCount = @($calculationTrades | Where-Object { $_.is_first_operation }).Count
$turnOperationCount = @($calculationTrades | Where-Object { $_.is_turn_operation }).Count
$pcmOperationCount = @($calculationTrades | Where-Object { $_.is_pcm_operation }).Count
$addOperationCount = @($enrichedTrades | Where-Object { $_.is_add_operation }).Count
$deduplicatedAddRowsCount = @($enrichedTrades | Where-Object { $_.is_add_duplicate_of_cycle }).Count
$avgMaxAdverseToSLPercent = if ($totalTrades -gt 0) { To-Double (($calculationTrades | Measure-Object -Property max_adverse_to_sl_percent -Average).Average) } else { 0.0 }
$totalGrossProfitFromRows = To-Double (($calculationTrades | Measure-Object -Property profit_gross -Sum).Sum)
$totalSwapFromRows = To-Double (($calculationTrades | Measure-Object -Property swap -Sum).Sum)
$totalCommissionFromRows = To-Double (($calculationTrades | Measure-Object -Property commission -Sum).Sum)
$totalFeeFromRows = To-Double (($calculationTrades | Measure-Object -Property fee -Sum).Sum)
$totalCostsFromRows = To-Double (($calculationTrades | Measure-Object -Property costs_total -Sum).Sum)

$overallStats = New-Stats $calculationTrades
$testerResult = Resolve-TesterResultFromLogs -TradesJsonPath $JsonPath

$initialBalanceForSummary = $null
if ($null -ne $testerResult -and $null -ne $testerResult.initial_balance) {
   $initialBalanceForSummary = To-Double $testerResult.initial_balance
} elseif ($null -ne $tickDrawdownData -and $null -ne $tickDrawdownData.daily -and @($tickDrawdownData.daily).Count -gt 0) {
   $initialBalanceForSummary = To-Double (@($tickDrawdownData.daily)[0].day_start_balance)
}

$finalBalanceForSummary = $null
if ($null -ne $testerResult -and $null -ne $testerResult.final_balance) {
   $finalBalanceForSummary = To-Double $testerResult.final_balance
} elseif ($null -ne $initialBalanceForSummary) {
   $finalBalanceForSummary = $initialBalanceForSummary + $overallStats.net_profit
}

$officialNetProfitForSummary = $overallStats.net_profit
if ($null -ne $initialBalanceForSummary -and $null -ne $finalBalanceForSummary) {
   $officialNetProfitForSummary = $finalBalanceForSummary - $initialBalanceForSummary
}

$drawdownInitialBalance = if ($null -ne $initialBalanceForSummary) { To-Double $initialBalanceForSummary } else { 0.0 }
if ($drawdownInitialBalance -le 0.0) {
   $drawdownInitialBalance = Resolve-InitialBalanceForOutput -RunConfig $runConfig -TickDrawdown $tickDrawdownData
}

$drawdownStats = Get-Drawdown-And-Streaks -Rows $orderedTrades -InitialBalance $drawdownInitialBalance
$recoveryFactor = if ($drawdownStats.max_drawdown -gt 0) { $overallStats.net_profit / $drawdownStats.max_drawdown } else { 0.0 }

$monthlyGroups = @(
   $calculationTrades |
   Group-Object { Month-Key ([string]$_.date) } |
   Sort-Object Name |
   ForEach-Object { [pscustomobject]@{ name = [string]$_.Name; rows = @($_.Group) } }
)

$directionGroups = @(
   [pscustomobject]@{ name = "BUY"; rows = @($calculationTrades | Where-Object { $_.direction -eq "BUY" }) },
   [pscustomobject]@{ name = "SELL"; rows = @($calculationTrades | Where-Object { $_.direction -eq "SELL" }) }
)

$entryTypeGroups = @(
   $calculationTrades |
   Group-Object entry_type |
   Sort-Object Name |
   ForEach-Object { [pscustomobject]@{ name = [string]$_.Name; rows = @($_.Group) } }
)

$timeframeGroups = @(
   $calculationTrades |
   Group-Object timeframe |
   Sort-Object Name |
   ForEach-Object { [pscustomobject]@{ name = [string]$_.Name; rows = @($_.Group) } }
)

$flagGroups = @(
   [pscustomobject]@{ name = "SLD $emojiTrue"; rows = @($calculationTrades | Where-Object { $_.is_sliced }) },
   [pscustomobject]@{ name = "SLD $emojiFalse"; rows = @($calculationTrades | Where-Object { -not $_.is_sliced }) },
   [pscustomobject]@{ name = "TurnOf $emojiTrue"; rows = @($calculationTrades | Where-Object { $_.is_reversal }) },
   [pscustomobject]@{ name = "TurnOf $emojiFalse"; rows = @($calculationTrades | Where-Object { -not $_.is_reversal }) },
   [pscustomobject]@{ name = "Triggered $emojiTrue"; rows = @($calculationTrades | Where-Object { $_.triggered_reversal }) },
   [pscustomobject]@{ name = "Triggered $emojiFalse"; rows = @($calculationTrades | Where-Object { -not $_.triggered_reversal }) },
   [pscustomobject]@{ name = "ADON $emojiTrue"; rows = @($calculationTrades | Where-Object { $_.has_addon }) },
   [pscustomobject]@{ name = "ADON $emojiFalse"; rows = @($calculationTrades | Where-Object { -not $_.has_addon }) }
)

$rangeGroups = @(
   [pscustomobject]@{
      name = "< MinChannelRange (" + (Format-Number $cfgMinRange) + ")"
      rows = @($calculationTrades | Where-Object { $_.channel_range -lt $cfgMinRange })
   },
   [pscustomobject]@{
      name = "Min..Max (" + (Format-Number $cfgMinRange) + " .. " + (Format-Number $cfgMaxRange) + ")"
      rows = @($calculationTrades | Where-Object { $_.channel_range -ge $cfgMinRange -and $_.channel_range -le $cfgMaxRange })
   },
   [pscustomobject]@{
      name = "Max..SLD (" + (Format-Number $cfgMaxRange) + " .. " + (Format-Number $cfgSliced) + ")"
      rows = @($calculationTrades | Where-Object { $_.channel_range -gt $cfgMaxRange -and $_.channel_range -lt $cfgSliced })
   },
   [pscustomobject]@{
      name = ">= SLDThreshold (" + (Format-Number $cfgSliced) + ")"
      rows = @($calculationTrades | Where-Object { $_.channel_range -ge $cfgSliced })
   }
)

$rrGroups = @(
   [pscustomobject]@{
      name = "< MinRiskReward (" + (Format-Number $cfgMinRR) + ")"
      rows = @($calculationTrades | Where-Object { $_.risk_reward -lt $cfgMinRR })
   },
   [pscustomobject]@{
      name = ">= MinRiskReward e < 1.00"
      rows = @($calculationTrades | Where-Object { $_.risk_reward -ge $cfgMinRR -and $_.risk_reward -lt 1.0 })
   },
   [pscustomobject]@{
      name = "1.00 a < 1.50"
      rows = @($calculationTrades | Where-Object { $_.risk_reward -ge 1.0 -and $_.risk_reward -lt 1.5 })
   },
   [pscustomobject]@{
      name = ">= 1.50"
      rows = @($calculationTrades | Where-Object { $_.risk_reward -ge 1.5 })
   }
)

$weekdayGroups = @(
   [pscustomobject]@{ name = "Seg"; rows = @($calculationTrades | Where-Object { $_.day_of_week_key -eq 1 }) },
   [pscustomobject]@{ name = "Ter"; rows = @($calculationTrades | Where-Object { $_.day_of_week_key -eq 2 }) },
   [pscustomobject]@{ name = "Qua"; rows = @($calculationTrades | Where-Object { $_.day_of_week_key -eq 3 }) },
   [pscustomobject]@{ name = "Qui"; rows = @($calculationTrades | Where-Object { $_.day_of_week_key -eq 4 }) },
   [pscustomobject]@{ name = "Sex"; rows = @($calculationTrades | Where-Object { $_.day_of_week_key -eq 5 }) },
   [pscustomobject]@{ name = "Sab"; rows = @($calculationTrades | Where-Object { $_.day_of_week_key -eq 6 }) },
   [pscustomobject]@{ name = "Dom"; rows = @($calculationTrades | Where-Object { $_.day_of_week_key -eq 0 }) }
)

$hourGroups = @(
   foreach ($h in 0..23) {
      $rows = @($calculationTrades | Where-Object { $_.entry_hour -eq $h })
      if ($rows.Count -gt 0) {
         [pscustomobject]@{ name = ("{0:00}h" -f $h); rows = $rows }
      }
   }
)

function Get-BestGroupByNet {
   param([array]$Groups, [int]$MinTrades = 5)
   $rows = @()
   foreach ($g in $Groups) {
      $s = New-Stats $g.rows
      if ($s.trades -ge $MinTrades) {
         $rows += [pscustomobject]@{ name = $g.name; stats = $s }
      }
   }
   if ($rows.Count -eq 0) { return $null }
   return @($rows | Sort-Object @{ Expression = { $_.stats.net_profit }; Descending = $true }, @{ Expression = { $_.stats.win_rate }; Descending = $true })[0]
}

function Get-WorstGroupByNet {
   param([array]$Groups, [int]$MinTrades = 5)
   $rows = @()
   foreach ($g in $Groups) {
      $s = New-Stats $g.rows
      if ($s.trades -ge $MinTrades) {
         $rows += [pscustomobject]@{ name = $g.name; stats = $s }
      }
   }
   if ($rows.Count -eq 0) { return $null }
   return @($rows | Sort-Object @{ Expression = { $_.stats.net_profit }; Descending = $false }, @{ Expression = { $_.stats.win_rate }; Descending = $false })[0]
}

$bestRange = Get-BestGroupByNet -Groups $rangeGroups -MinTrades 5
$worstRange = Get-WorstGroupByNet -Groups $rangeGroups -MinTrades 5
$bestHour = Get-BestGroupByNet -Groups $hourGroups -MinTrades 5
$worstHour = Get-WorstGroupByNet -Groups $hourGroups -MinTrades 5
$bestEntryType = Get-BestGroupByNet -Groups $entryTypeGroups -MinTrades 5

$generatedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$builder = [System.Text.StringBuilder]::new()

[void]$builder.AppendLine("# Relatorio de Operacoes - JSON")
[void]$builder.AppendLine("")
[void]$builder.AppendLine("- Arquivo fonte: $JsonPath")
[void]$builder.AppendLine("- Gerado em: $generatedAt")
[void]$builder.AppendLine("- Periodo das operacoes: $periodStart ate $periodEnd")
[void]$builder.AppendLine("")

Append-RunConfigSection -Builder $builder -RunConfig $runConfig -IsHiran1Mode $script:IsHiran1Mode

[void]$builder.AppendLine("## Resumo Geral")
[void]$builder.AppendLine("")
[void]$builder.AppendLine("- Total de operacoes: **$totalTrades**")
[void]$builder.AppendLine("- Linhas totais no JSON (bruto): **$totalTradesRaw** | Linhas add deduplicadas nas metricas: **$deduplicatedAddRowsCount**")
[void]$builder.AppendLine("- TP: **$summaryTpCount** | SL: **$summarySlCount** | BE: **$summaryBeCount**")
[void]$builder.AppendLine("- BUY: **$buyCount** | SELL: **$sellCount**")
[void]$builder.AppendLine("- TurnOf (is_turnof=$emojiTrue): **$summaryReversalCount**")
[void]$builder.AppendLine("- Gatilho de TurnOf (triggered_turnof=$emojiTrue): **$triggeredReversalCount**")
[void]$builder.AppendLine("- Classificacao de operacao: First **$firstOperationCount** | Turn **$turnOperationCount** | $($script:SecondaryOpLabel) **$pcmOperationCount** | Add **$addOperationCount**")
[void]$builder.AppendLine("- SLD (is_sld=$emojiTrue): **$slicedCount**")
[void]$builder.AppendLine("- Dias sem operacao (no_trade_days): **$($noTradeRows.Count)**")
[void]$builder.AppendLine("- Operacoes com ADON: **$addOnTradesCount** | Total de ADONs executados: **$totalAddOnEntries**")
[void]$builder.AppendLine("- Lotes totais de ADON: **" + (Format-Number $totalAddOnLots) + "** | PnL total dos ADONs: **" + (Format-Number $totalAddOnProfit) + "**")
[void]$builder.AppendLine("- Resultado bruto (soma profit_gross): **" + (Format-Number $totalGrossProfitFromRows) + "**")
[void]$builder.AppendLine("- Ajustes financeiros: Swap **" + (Format-Number $totalSwapFromRows) + "** | Comissao **" + (Format-Number $totalCommissionFromRows) + "** | Fee **" + (Format-Number $totalFeeFromRows) + "** | Total custos/ajustes **" + (Format-Number $totalCostsFromRows) + "**")
[void]$builder.AppendLine("- Lucro liquido oficial (compativel com Tester): **" + (Format-Number $officialNetProfitForSummary) + "**")
[void]$builder.AppendLine("- Lucro liquido analitico (soma profit): **" + (Format-Number $overallStats.net_profit) + "**")
if ($null -ne $initialBalanceForSummary) {
   [void]$builder.AppendLine("- Saldo inicial de referencia: **" + (Format-Number $initialBalanceForSummary) + "**")
}
if ($null -ne $finalBalanceForSummary) {
   [void]$builder.AppendLine("- Saldo final oficial: **" + (Format-Number $finalBalanceForSummary) + "**")
}
[void]$builder.AppendLine("- Media de profit por operacao: **" + (Format-Number ($officialNetProfitForSummary / [math]::Max(1, $totalTrades))) + "**")
[void]$builder.AppendLine("")

[void]$builder.AppendLine("## Metricas de Performance")
[void]$builder.AppendLine("")
[void]$builder.AppendLine("- Win rate: **" + (Format-Percent $overallStats.win_rate) + "**")
[void]$builder.AppendLine("- Gross Profit: **" + (Format-Number $overallStats.gross_profit) + "** | Gross Loss: **" + (Format-Number $overallStats.gross_loss) + "**")
[void]$builder.AppendLine("- Profit Factor: **$($overallStats.profit_factor_text)** | Payoff Ratio: **" + (Format-Number $overallStats.payoff_ratio) + "**")
[void]$builder.AppendLine("- Mediana de profit por trade: **" + (Format-Number $overallStats.median_profit) + "**")
[void]$builder.AppendLine("- Melhor trade: **" + (Format-Number $overallStats.best_trade) + "** | Pior trade: **" + (Format-Number $overallStats.worst_trade) + "**")
[void]$builder.AppendLine("- Max floating profit medio (MFE): **" + (Format-Number $overallStats.avg_max_floating_profit) + "** | Pior floating drawdown medio (MAE): **" + (Format-Number $overallStats.avg_max_floating_drawdown) + "**")
[void]$builder.AppendLine("- Distancia maxima media da entrada ate o SL: **" + (Format-Percent $avgMaxAdverseToSLPercent) + "**")
[void]$builder.AppendLine("- Melhor pico flutuante (MFE max): **" + (Format-Number $overallStats.best_floating_profit) + "** | Pior vale flutuante (MAE min): **" + (Format-Number $overallStats.worst_floating_drawdown) + "**")
[void]$builder.AppendLine("- Max Drawdown (sequencia por exit_time): **" + (Format-Number $drawdownStats.max_drawdown) + "** (" + (Format-Percent $drawdownStats.max_drawdown_pct) + ")")
[void]$builder.AppendLine("- Recovery Factor: **" + (Format-Number $recoveryFactor) + "**")
[void]$builder.AppendLine("- Max sequencia de ganhos: **$($drawdownStats.max_win_streak)** trades (**" + (Format-Number $drawdownStats.max_win_streak_profit) + "**)")
[void]$builder.AppendLine("- Max sequencia de perdas: **$($drawdownStats.max_loss_streak)** trades (**" + (Format-Number $drawdownStats.max_loss_streak_profit) + "**)")
[void]$builder.AppendLine("")

Append-TickDrawdownSection -Builder $builder -TickDrawdown $tickDrawdownData

[void]$builder.AppendLine("## ADON (Adicao em Flutuacao Negativa)")
[void]$builder.AppendLine("")
[void]$builder.AppendLine("- Operacoes com ADON: **$addOnTradesCount** / **$totalTrades**")
[void]$builder.AppendLine("- Operacoes ADON puras (tickets add): **$addOperationTradesCount**")
[void]$builder.AppendLine("- Quantidade total de ADONs executados: **$totalAddOnEntries**")
[void]$builder.AppendLine("- Lotes totais adicionados: **" + (Format-Number $totalAddOnLots) + "**")
[void]$builder.AppendLine("- PnL total dos ADONs: **" + (Format-Number $totalAddOnProfit) + "**")
[void]$builder.AppendLine("")

[void]$builder.AppendLine("## Insights para Otimizacao")
[void]$builder.AppendLine("")
if ($bestRange -ne $null) {
   [void]$builder.AppendLine("- Melhor faixa de range (>=5 trades): **$($bestRange.name)** | Net: **" + (Format-Number $bestRange.stats.net_profit) + "** | Win rate: **" + (Format-Percent $bestRange.stats.win_rate) + "**")
}
if ($worstRange -ne $null) {
   [void]$builder.AppendLine("- Pior faixa de range (>=5 trades): **$($worstRange.name)** | Net: **" + (Format-Number $worstRange.stats.net_profit) + "** | Win rate: **" + (Format-Percent $worstRange.stats.win_rate) + "**")
}
if ($bestEntryType -ne $null) {
   [void]$builder.AppendLine("- Melhor tipo de entrada (>=5 trades): **$($bestEntryType.name)** | Net: **" + (Format-Number $bestEntryType.stats.net_profit) + "** | PF: **$($bestEntryType.stats.profit_factor_text)**")
}
if ($bestHour -ne $null) {
   [void]$builder.AppendLine("- Melhor horario de entrada (>=5 trades): **$($bestHour.name)** | Net: **" + (Format-Number $bestHour.stats.net_profit) + "**")
}
if ($worstHour -ne $null) {
   [void]$builder.AppendLine("- Pior horario de entrada (>=5 trades): **$($worstHour.name)** | Net: **" + (Format-Number $worstHour.stats.net_profit) + "**")
}
[void]$builder.AppendLine("")

[void]$builder.AppendLine("## Resumo Mensal")
[void]$builder.AppendLine("")
[void]$builder.AppendLine("| Mes | Operacoes | TP | SL | Win Rate | Lucro Liquido | Profit Factor | Avg RR | Avg Range | DD Diario Max | DD Max Atingido |")
[void]$builder.AppendLine("|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
foreach ($group in $monthlyGroups) {
   $s = New-Stats $group.rows
   $orderedMonthlyRows = @(
      $group.rows |
      Sort-Object `
         @{ Expression = { if ($_.exit_dt -ne $null) { $_.exit_dt } else { [datetime]::MaxValue } }; Descending = $false }, `
         @{ Expression = { if ($_.entry_dt -ne $null) { $_.entry_dt } else { [datetime]::MaxValue } }; Descending = $false }
   )
   $monthlyDrawdown = Get-Drawdown-And-Streaks $orderedMonthlyRows
   $monthlyMaxDailyDrawdown = Get-MaxDailyDrawdown $orderedMonthlyRows
   $line = "| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} | {8} | {9} | {10} |" -f `
      [string]$group.name, `
      $s.trades, `
      $s.tp, `
      $s.sl, `
      (Format-Percent $s.win_rate), `
      (Format-Number $s.net_profit), `
      $s.profit_factor_text, `
      (Format-Number $s.avg_rr), `
      (Format-Number $s.avg_range), `
      (Format-Number $monthlyMaxDailyDrawdown), `
      (Format-Number $monthlyDrawdown.max_drawdown)
   [void]$builder.AppendLine($line)
}
[void]$builder.AppendLine("")

Append-Stats-Table -Builder $builder -Title "Analise por Direcao" -GroupHeader "Direcao" -Groups $directionGroups
Append-Stats-Table -Builder $builder -Title "Analise por Tipo de Entrada" -GroupHeader "Entry Type" -Groups $entryTypeGroups
Append-Stats-Table -Builder $builder -Title "Analise por Timeframe" -GroupHeader "Timeframe" -Groups $timeframeGroups
Append-Stats-Table -Builder $builder -Title "Analise por Flags" -GroupHeader "Flag" -Groups $flagGroups
Append-Stats-Table -Builder $builder -Title "Analise por Faixa de Range" -GroupHeader "Faixa" -Groups $rangeGroups
Append-Stats-Table -Builder $builder -Title "Analise por Faixa de RR" -GroupHeader "Faixa RR" -Groups $rrGroups
Append-Stats-Table -Builder $builder -Title "Analise por Dia da Semana" -GroupHeader "Dia" -Groups $weekdayGroups
Append-Stats-Table -Builder $builder -Title "Analise por Hora de Entrada" -GroupHeader "Hora" -Groups $hourGroups

Append-TopBottom-Table -Builder $builder -Title "Top 10 Operacoes (Maior Profit)" -Rows $enrichedTrades -TakeCount 10 -Descending $true
Append-TopBottom-Table -Builder $builder -Title "Top 10 Operacoes (Maior Prejuizo)" -Rows $enrichedTrades -TakeCount 10 -Descending $false

Append-Trade-Table -Builder $builder -Title "Operacoes (Detalhado)" -Rows $nonAddTrades -IncludeBothDistanceColumns $true
Append-Trade-Table -Builder $builder -Title "Operacoes com ADON" -Rows $addOnTrades -IncludeBothDistanceColumns $true
Append-Trade-Table -Builder $builder -Title "Operacoes ADON Puro (Somente Tickets Add)" -Rows $addOperationTrades -DistanceColumnHeader "Dist. ate TP (%)" -DistanceMetric "max_favorable_to_tp_percent" -IncludeBothDistanceColumns $true
Append-Trade-Table -Builder $builder -Title "Operacoes First_op TP (flag: first_*)" -Rows $tpTrades
Append-Trade-Table -Builder $builder -Title "Operacoes First_op SL (flag: first_*)" -Rows $slTrades -DistanceColumnHeader "Dist. ate TP (%)" -DistanceMetric "max_favorable_to_tp_percent"
Append-Trade-Table -Builder $builder -Title "Operacoes First_op BE (flag: first_*)" -Rows $beTrades -DistanceColumnHeader "Dist. ate TP (%)" -DistanceMetric "max_favorable_to_tp_percent"
Append-Trade-Table -Builder $builder -Title "Operacoes TurnOf TP (flag: turn_*)" -Rows $turnofTpTrades -DistanceColumnHeader "Dist. ate TP (%)" -DistanceMetric "max_favorable_to_tp_percent" -IncludeBothDistanceColumns $true
Append-Trade-Table -Builder $builder -Title "Operacoes TurnOf SL (flag: turn_*)" -Rows $turnofSlTrades -DistanceColumnHeader "Dist. ate TP (%)" -DistanceMetric "max_favorable_to_tp_percent" -IncludeBothDistanceColumns $true
Append-Trade-Table -Builder $builder -Title "Operacoes TurnOf BE (flag: turn_*)" -Rows $turnofBeTrades -DistanceColumnHeader "Dist. ate TP (%)" -DistanceMetric "max_favorable_to_tp_percent" -IncludeBothDistanceColumns $true
Append-Trade-Table -Builder $builder -Title ("Operacoes " + $script:SecondaryOpLabel + " TP") -Rows $pcmTpTrades -IncludeBothDistanceColumns $true
Append-Trade-Table -Builder $builder -Title ("Operacoes " + $script:SecondaryOpLabel + " SL") -Rows $pcmSlTrades -DistanceColumnHeader "Dist. ate TP (%)" -DistanceMetric "max_favorable_to_tp_percent" -IncludeBothDistanceColumns $true
Append-Trade-Table -Builder $builder -Title ("Operacoes " + $script:SecondaryOpLabel + " BE") -Rows $pcmBeTrades -DistanceColumnHeader "Dist. ate TP (%)" -DistanceMetric "max_favorable_to_tp_percent" -IncludeBothDistanceColumns $true

if ($hasNoTradesFile) {
   Append-NoTrades-Section -Builder $builder -SourcePath $resolvedNoTradesPath -NoTradeRows $noTradeRows -SecondaryOpLabel $script:SecondaryOpLabel
} else {
   [void]$builder.AppendLine("## Dias sem Operacao (NoTrade)")
   [void]$builder.AppendLine("")
   if ([string]::IsNullOrWhiteSpace($resolvedNoTradesPath)) {
      [void]$builder.AppendLine("Arquivo de no-trades nao informado.")
   } else {
      [void]$builder.AppendLine("Arquivo de no-trades nao encontrado: $resolvedNoTradesPath")
   }
   [void]$builder.AppendLine("")
}

$finalOutputPath = Get-UniqueOutputPath -PreferredPath $OutputPath
$outputDirectory = Split-Path -Path $finalOutputPath -Parent
if (-not [string]::IsNullOrWhiteSpace($outputDirectory) -and -not (Test-Path -LiteralPath $outputDirectory)) {
   New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}
Set-Content -LiteralPath $finalOutputPath -Value $builder.ToString() -Encoding UTF8
Write-Host "Relatorio gerado em: $finalOutputPath"
