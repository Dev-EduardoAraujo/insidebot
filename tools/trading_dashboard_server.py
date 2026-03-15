#!/usr/bin/env python3
"""
Trading Dashboard Server
Parses markdown reports and serves data via API
"""

import os
import re
import json
from pathlib import Path
from http.server import HTTPServer, SimpleHTTPRequestHandler
from urllib.parse import urlparse, parse_qs, unquote
import argparse
from datetime import datetime


class ReportParser:
    """Parse markdown trading reports"""

    @staticmethod
    def _row_value(row, keys):
        for key in keys:
            if key in row and row.get(key) is not None:
                value = str(row.get(key)).strip()
                if value != '':
                    return value
        return ''

    @staticmethod
    def _build_markdown_table(headers, rows):
        if not rows:
            return ''
        header_line = '| ' + ' | '.join(headers) + ' |'
        align_line = '| ' + ' | '.join(['---'] * len(headers)) + ' |'
        body_lines = []
        for row in rows:
            cells = [str(row.get(h, '')).replace('\n', ' ').strip() for h in headers]
            body_lines.append('| ' + ' | '.join(cells) + ' |')
        return '\n'.join([header_line, align_line] + body_lines)
    
    @staticmethod
    def parse_report(file_path):
        """Parse markdown report file"""
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
        is_hiran1_report = re.search(r'##\s+Operacoes\s+Recontagem', content, re.IGNORECASE) is not None

        max_drawdown_value, max_drawdown_pct = ReportParser.extract_max_drawdown(content)
        first_ops_value = ReportParser.extract_value(content, r'First\s*\*\*(\d+)\*\*')
        turn_ops_value = ReportParser.extract_value(content, r'Turn\s*\*\*(\d+)\*\*')
        addon_only_section = ReportParser.extract_first_section_table(
            content,
            [
                r'## Operacoes ADON Puro \(Somente Tickets Add\)',
                r'## Operacoes ADON Puro \(por Operacao com ADON\)',
                r'## Operacoes ADON \(Somente Tickets Add\)',
                r'## Operacoes AddOn Puro \(Somente Tickets Add\)',
                r'## Operacoes AddOn Puro \(por Operacao com AddOn\)',
                r'## Operacoes AddOn \(Somente Tickets Add\)',
            ],
        )
        section_tables = {
            'detailed_ops': ReportParser.extract_section_table(content, '## Operacoes \\(Detalhado\\)'),
            'addon_ops': ReportParser.extract_first_section_table(
                content,
                [r'## Operacoes com ADON', r'## Operacoes com AddOn'],
            ),
            'addon_only_ops': addon_only_section,
            'first_tp_ops': ReportParser.extract_first_section_table(
                content,
                [r'## Operacoes First_op TP', r'## Operacoes TP'],
            ),
            'first_sl_ops': ReportParser.extract_first_section_table(
                content,
                [r'## Operacoes First_op SL', r'## Operacoes SL'],
            ),
            'first_be_ops': ReportParser.extract_first_section_table(
                content,
                [r'## Operacoes First_op BE'],
            ),
            'tp_ops': ReportParser.extract_section_table(content, '## Operacoes TP'),
            'sl_ops': ReportParser.extract_section_table(content, '## Operacoes SL'),
            'turnof_tp_ops': ReportParser.extract_first_section_table(
                content,
                [r'## Operacoes TurnOf TP', r'## Operacoes turnof TP'],
            ),
            'turnof_sl_ops': ReportParser.extract_first_section_table(
                content,
                [r'## Operacoes TurnOf SL', r'## Operacoes turnof SL'],
            ),
            'turnof_be_ops': ReportParser.extract_first_section_table(
                content,
                [r'## Operacoes TurnOf BE', r'## Operacoes turnof BE'],
            ),
            'reversal_ops': ReportParser.extract_first_section_table(
                content,
                [r'## Operacoes TurnOf', r'## Operacoes turnof'],
            ),
            'pcm_ops': ReportParser.extract_first_section_table(
                content,
                [r'## Operacoes PCM', r'## Operacoes Recontagem'],
            ),
            'pcm_tp_ops': ReportParser.extract_first_section_table(
                content,
                [r'## Operacoes PCM TP', r'## Operacoes PCM - TP', r'## Operacoes Recontagem TP', r'## Operacoes Recontagem - TP'],
            ),
            'pcm_sl_ops': ReportParser.extract_first_section_table(
                content,
                [r'## Operacoes PCM SL', r'## Operacoes PCM - SL', r'## Operacoes Recontagem SL', r'## Operacoes Recontagem - SL'],
            ),
            'pcm_be_ops': ReportParser.extract_first_section_table(
                content,
                [r'## Operacoes PCM BE', r'## Operacoes PCM - BE', r'## Operacoes Recontagem BE', r'## Operacoes Recontagem - BE'],
            ),
        }
        no_trade_summary = ReportParser.parse_no_trade_summary(content)
        detailed_core_rows = ReportParser.parse_core_detailed_rows(section_tables.get('detailed_ops'))
        initial_balance_ref_text = ReportParser.extract_value(content, r'Saldo inicial de referencia:\s*\*\*([\d\.\,\-]+)\*\*')
        initial_balance_ref = ReportParser.parse_localized_number(initial_balance_ref_text)
        chart_timeseries = ReportParser.build_chart_timeseries(detailed_core_rows, initial_balance_ref)
        bot_parameters = ReportParser.parse_bot_parameters(content)
        dd_tick_daily = ReportParser.parse_dd_table(content)
        dd_open_daily = ReportParser.build_dd_open_daily(dd_tick_daily, section_tables.get('detailed_ops'), initial_balance_ref, bot_parameters)
        result_streaks = ReportParser.parse_result_streaks(section_tables.get('detailed_ops'))
        core_streaks = ReportParser.compute_streaks_from_rows(detailed_core_rows) if detailed_core_rows else None
        direction_analysis = ReportParser.build_direction_analysis(detailed_core_rows) if detailed_core_rows else ReportParser.parse_direction_table(content)
        entry_type_analysis = ReportParser.build_entry_type_analysis(detailed_core_rows) if detailed_core_rows else ReportParser.parse_entry_type_table(content)
        timeframe_analysis = ReportParser.build_timeframe_analysis(detailed_core_rows) if detailed_core_rows else ReportParser.parse_timeframe_table(content)
        weekday_analysis = ReportParser.build_weekday_analysis(detailed_core_rows) if detailed_core_rows else ReportParser.parse_weekday_table(content)
        weekday_flag_analysis = ReportParser.build_weekday_flag_analysis(detailed_core_rows) if detailed_core_rows else []
        entry_hour_analysis = ReportParser.build_entry_hour_analysis(detailed_core_rows) if detailed_core_rows else ReportParser.parse_entry_hour_table(content)
        operation_card_sections = ReportParser.build_operations_card_sections(detailed_core_rows)

        if first_ops_value is None:
            first_ops_value = operation_card_sections.get('first_op', {}).get('trades')
        if turn_ops_value is None:
            turn_ops_value = operation_card_sections.get('turnof', {}).get('trades')

        first_ops_count = ReportParser.parse_int(first_ops_value)
        turn_ops_count = ReportParser.parse_int(turn_ops_value)

        addon_only_stats = ReportParser.parse_section_trade_stats(section_tables.get('addon_only_ops'))
        turnof_tp_stats = ReportParser.parse_section_trade_stats(section_tables.get('turnof_tp_ops'))
        turnof_sl_stats = ReportParser.parse_section_trade_stats(section_tables.get('turnof_sl_ops'))
        turnof_be_stats = ReportParser.parse_section_trade_stats(section_tables.get('turnof_be_ops'))
        if (turnof_tp_stats['total'] + turnof_sl_stats['total'] + turnof_be_stats['total']) > 0:
            reversal_stats = ReportParser.merge_trade_stats([turnof_tp_stats, turnof_sl_stats, turnof_be_stats])
        else:
            reversal_stats = ReportParser.parse_section_trade_stats(section_tables.get('reversal_ops'))
        pcm_tp_stats = ReportParser.parse_section_trade_stats(section_tables.get('pcm_tp_ops'))
        pcm_sl_stats = ReportParser.parse_section_trade_stats(section_tables.get('pcm_sl_ops'))
        pcm_be_stats = ReportParser.parse_section_trade_stats(section_tables.get('pcm_be_ops'))
        if (pcm_tp_stats['total'] + pcm_sl_stats['total'] + pcm_be_stats['total']) > 0:
            pcm_stats = ReportParser.merge_trade_stats([pcm_tp_stats, pcm_sl_stats, pcm_be_stats])
        else:
            pcm_stats = ReportParser.parse_section_trade_stats(section_tables.get('pcm_ops'))
        operation_card_sections['addon'] = {
            'trades': str(addon_only_stats['total']),
            'tp': str(addon_only_stats['tp']),
            'sl': str(addon_only_stats['sl']),
            'win_rate': f"{addon_only_stats['win_rate']:.2f}%",
            'net_profit': f"{addon_only_stats['pnl']:.2f}",
            'avg_profit': f"{(addon_only_stats['pnl'] / addon_only_stats['total']):.2f}" if addon_only_stats['total'] > 0 else "0.00",
            'profit_factor': addon_only_stats['profit_factor'],
            'avg_rr': "0.00",
            'avg_range': "0.00",
        }
        operation_card_sections['pcm'] = {
            'trades': str(pcm_stats['total']),
            'tp': str(pcm_stats['tp']),
            'sl': str(pcm_stats['sl']),
            'win_rate': f"{pcm_stats['win_rate']:.2f}%",
            'net_profit': f"{pcm_stats['pnl']:.2f}",
            'avg_profit': f"{(pcm_stats['pnl'] / pcm_stats['total']):.2f}" if pcm_stats['total'] > 0 else "0.00",
            'profit_factor': pcm_stats['profit_factor'],
            'avg_rr': "0.00",
            'avg_range': "0.00",
        }
        
        data = {
            'file_name': os.path.basename(file_path),
            # Resumo Geral
            'total_operacoes': ReportParser.extract_value(content, r'Total de operacoes:\s*\*\*(\d+)\*\*'),
            'tp_count': ReportParser.extract_value(content, r'TP:\s*\*\*(\d+)\*\*'),
            'sl_count': ReportParser.extract_value(content, r'SL:\s*\*\*(\d+)\*\*'),
            'buy_count': ReportParser.extract_value(content, r'BUY:\s*\*\*(\d+)\*\*'),
            'sell_count': ReportParser.extract_value(content, r'SELL:\s*\*\*(\d+)\*\*'),
            'is_reversal_count': ReportParser.extract_value(content, r'(?:TurnOf \(is_turnof|turnof \(is_reversal)=(?:âœ…|✅)\):\s*\*\*(\d+)\*\*'),
            'triggered_reversal_count': ReportParser.extract_value(content, r'Gatilho de (?:TurnOf|turnof|virada) \((?:triggered_turnof|triggered_reversal)=(?:âœ…|✅)\):\s*\*\*(\d+)\*\*'),
            'first_ops': first_ops_value,
            'turn_ops': turn_ops_value,
            'ops_card_total': str(first_ops_count + turn_ops_count),
            'operations_card_sections': operation_card_sections,
            'add_ops': ReportParser.extract_value(content, r'Add\s*\*\*(\d+)\*\*'),
            'sliced_count': ReportParser.extract_value(content, r'(?:SLD \(is_sld|Sliced \(is_sliced)=(?:âœ…|✅)\):\s*\*\*(\d+)\*\*'),
            'no_trade_days': ReportParser.extract_value(content, r'Dias sem operacao \(no_trade_days\):\s*\*\*(\d+)\*\*'),
            'ops_with_addon': ReportParser.extract_value(content, r'Operacoes com (?:ADON|addon):\s*\*\*(\d+)\*\*'),
            'total_addons': ReportParser.extract_value(content, r'Total de (?:ADONs|addons) executados:\s*\*\*(\d+)\*\*'),
            'addon_total_lots': ReportParser.extract_value(content, r'Lotes totais de (?:ADON|addon):\s*\*\*([\d\.\,]+)\*\*'),
            'addon_total_pnl': ReportParser.extract_value(content, r'PnL total dos (?:ADONs|addons):\s*\*\*([\d\.\,\-]+)\*\*'),
            'addon_only_total': str(addon_only_stats['total']),
            'addon_only_tp': str(addon_only_stats['tp']),
            'addon_only_sl': str(addon_only_stats['sl']),
            'addon_only_pnl': f"{addon_only_stats['pnl']:.2f}",
            'addon_only_win_rate': f"{addon_only_stats['win_rate']:.2f}%",
            'turnof_total': str(reversal_stats['total']),
            'turnof_pnl': f"{reversal_stats['pnl']:.2f}",
            'turnof_win_rate': f"{reversal_stats['win_rate']:.2f}%",
            'pcm_total': str(pcm_stats['total']),
            'pcm_tp': str(pcm_stats['tp']),
            'pcm_sl': str(pcm_stats['sl']),
            'pcm_be': str(pcm_stats.get('be', 0)),
            'pcm_pnl': f"{pcm_stats['pnl']:.2f}",
            'pcm_win_rate': f"{pcm_stats['win_rate']:.2f}%",
            'lucro_liquido': ReportParser.extract_value(content, r'Lucro liquido.*?:\s*\*\*([\d\.\,\-]+)\*\*'),
            'media_profit': ReportParser.extract_value(content, r'Media de profit por operacao:\s*\*\*([\d\.\,\-]+)\*\*'),
            # Metricas de Performance
            'win_rate': ReportParser.extract_value(content, r'Win rate:\s*\*\*([\d\.]+%)\*\*'),
            'gross_profit': ReportParser.extract_value(content, r'Gross Profit:\s*\*\*([\d\.\,]+)\*\*'),
            'gross_loss': ReportParser.extract_value(content, r'Gross Loss:\s*\*\*([\d\.\,\-]+)\*\*'),
            'profit_factor': ReportParser.extract_value(content, r'Profit Factor:\s*\*\*([\d\.]+)\*\*'),
            'payoff_ratio': ReportParser.extract_value(content, r'Payoff Ratio:\s*\*\*([\d\.]+)\*\*'),
            'median_profit': ReportParser.extract_value(content, r'Mediana de profit por trade:\s*\*\*([\d\.\,\-]+)\*\*'),
            'best_trade': ReportParser.extract_value(content, r'Melhor trade:\s*\*\*([\d\.\,]+)\*\*'),
            'worst_trade': ReportParser.extract_value(content, r'Pior trade:\s*\*\*([\d\.\,\-]+)\*\*'),
            'avg_mfe': ReportParser.extract_value(content, r'Max floating profit medio \(MFE\):\s*\*\*([\d\.\,]+)\*\*'),
            'avg_mae': ReportParser.extract_value(content, r'Pior floating drawdown medio \(MAE\):\s*\*\*([\d\.\,\-]+)\*\*'),
            'avg_adverse_to_sl': ReportParser.extract_value(content, r'Distancia maxima media da entrada ate o SL:\s*\*\*([\d\.]+%)\*\*'),
            'max_mfe': ReportParser.extract_value(content, r'Melhor pico flutuante \(MFE max\):\s*\*\*([\d\.\,]+)\*\*'),
            'min_mae': ReportParser.extract_value(content, r'Pior vale flutuante \(MAE min\):\s*\*\*([\d\.\,\-]+)\*\*'),
            'max_drawdown': max_drawdown_value,
            'max_drawdown_pct': max_drawdown_pct,
            'recovery_factor': ReportParser.extract_value(content, r'Recovery Factor:\s*\*\*([\d\.]+)\*\*'),
            'max_win_streak': (
                str(core_streaks['max_win_streak'])
                if core_streaks else
                ReportParser.extract_value(content, r'Max sequencia de ganhos:\s*\*\*(\d+)\*\*\s*trades')
            ),
            'max_win_streak_value': (
                f"{core_streaks['max_win_streak_value']:.2f}"
                if core_streaks else
                ReportParser.extract_value(content, r'Max sequencia de ganhos:\s*\*\*\d+\*\*\s*trades\s*\(\*\*([\d\.\,]+)\*\*\)')
            ),
            'max_loss_streak': (
                str(core_streaks['max_loss_streak'])
                if core_streaks else
                ReportParser.extract_value(content, r'Max sequencia de perdas:\s*\*\*(\d+)\*\*\s*trades')
            ),
            'max_loss_streak_value': (
                f"{core_streaks['max_loss_streak_value']:.2f}"
                if core_streaks else
                ReportParser.extract_value(content, r'Max sequencia de perdas:\s*\*\*\d+\*\*\s*trades\s*\(\*\*([\d\.\,\-]+)\*\*\)')
            ),
            'max_tp_streak': str(core_streaks['max_tp_streak']) if core_streaks else str(result_streaks['tp']),
            'max_sl_streak': str(core_streaks['max_sl_streak']) if core_streaks else str(result_streaks['sl']),
            # DD Tick a Tick
            'max_dd_tick_floating': ReportParser.extract_value(content, r'Max DD intraday flutuante.*?:\s*\*\*([\d\.\,\-]+)\*\*'),
            'max_dd_tick_floating_pct': ReportParser.extract_value(content, r'Max DD intraday flutuante.*?em % do saldo do dia:\s*\*\*([\d\.]+%)\*\*'),
            'max_dd_tick_combined': ReportParser.extract_value(content, r'Max DD\+Limit.*?:\s*\*\*([\d\.\,\-]+)\*\*'),
            'sum_daily_dd_floating': ReportParser.extract_value(content, r'Soma do DD maximo diario \(flutuante\):\s*\*\*([\d\.\,\-]+)\*\*'),
            'sum_daily_dd_combined': ReportParser.extract_value(content, r'Soma do DD maximo diario \+ LIMIT pendente:\s*\*\*([\d\.\,\-]+)\*\*'),
            'days_monitored': ReportParser.extract_value(content, r'Dias monitorados:\s*\*\*(\d+)\*\*'),
            'peak_floating_positions': ReportParser.extract_value(content, r'Dia com mais operacoes flutuantes:.*?\*\*(\d+)\*\*\s*posicoes'),
            'peak_floating_date': ReportParser.extract_value(content, r'Dia com mais operacoes flutuantes:\s*\*\*([\d\.]+)\*\*'),
            'peak_floating_time': ReportParser.extract_value(content, r'Hora do pico:\s*\*\*([\d\.\s:]+)\*\*'),
            'initial_balance_ref': f"{initial_balance_ref:.2f}",
            'bot_parameters': bot_parameters,
            'monthly_summary': ReportParser.parse_monthly_table(content),
            'chart_timeseries': chart_timeseries,
            'direction_analysis': direction_analysis,
            'entry_type_analysis': entry_type_analysis,
            'timeframe_analysis': timeframe_analysis,
            'flags_analysis': ReportParser.parse_flags_table(content),
            'weekday_analysis': weekday_analysis,
            'weekday_flag_analysis': weekday_flag_analysis,
            'entry_hour_analysis': entry_hour_analysis,
            'top_trades': ReportParser.parse_top_trades(content, True),
            'worst_trades': ReportParser.parse_top_trades(content, False),
            'dd_tick_daily': dd_tick_daily,
            'dd_open_daily': dd_open_daily,
            'section_tables': section_tables,
            'no_trade_summary': no_trade_summary,
            'secondary_op_label': 'Recontagem'
        }
        
        return data

    @staticmethod
    def parse_int(value):
        """Parse integer safely"""
        if value is None:
            return 0
        try:
            return int(str(value).strip())
        except (ValueError, TypeError):
            return 0
    
    @staticmethod
    def extract_value(content, pattern):
        """Extract value using regex pattern"""
        match = re.search(pattern, content)
        if match:
            return match.group(1)
        return None

    @staticmethod
    def extract_max_drawdown(content):
        """Extract max drawdown absolute and percent supporting both markdown formats"""
        # Current format in report:
        # Max Drawdown (...): **13291.61** (44.26%)
        match = re.search(
            r'Max Drawdown.*?:\s*\*\*([\d\.,\-]+)\*\*\s*\(([\d\.,]+%)\)',
            content
        )
        if match:
            return match.group(1), match.group(2)

        # Legacy fallback:
        # Max Drawdown (...): **13291.61 (44.26%)**
        match = re.search(
            r'Max Drawdown.*?:\s*\*\*([\d\.,\-]+)\s*\(([\d\.,]+%)\)\*\*',
            content
        )
        if match:
            return match.group(1), match.group(2)

        return None, None

    @staticmethod
    def parse_markdown_table(table_markdown):
        """Parse a markdown table into list of dict rows"""
        if not table_markdown:
            return []

        lines = []
        for raw_line in table_markdown.strip().splitlines():
            line = raw_line.strip()
            if not line or '|' not in line:
                continue

            # Tolerate hidden chars/prefixes before first pipe.
            first_pipe = line.find('|')
            last_pipe = line.rfind('|')
            if first_pipe < 0 or last_pipe <= first_pipe:
                continue
            normalized = line[first_pipe:last_pipe + 1]
            if normalized.count('|') < 2:
                continue
            lines.append(normalized)
        if len(lines) < 2:
            return []

        headers = [h.strip() for h in lines[0].strip('|').split('|')]
        rows = []

        for line in lines[2:]:
            cells = [c.strip() for c in line.strip('|').split('|')]
            if len(cells) < len(headers):
                cells.extend([''] * (len(headers) - len(cells)))
            row = {headers[i]: cells[i] for i in range(len(headers))}
            rows.append(row)

        return rows

    @staticmethod
    def parse_result_streaks(detailed_section):
        """Compute max TP/SL consecutive streak from detailed operations table"""
        if not detailed_section or not detailed_section.get('table'):
            return {'tp': 0, 'sl': 0}

        rows = ReportParser.parse_markdown_table(detailed_section.get('table', ''))
        max_tp = 0
        max_sl = 0
        current_tp = 0
        current_sl = 0

        for row in rows:
            result = (row.get('Result') or '').strip().upper()
            if result == 'TP':
                current_tp += 1
                current_sl = 0
            elif result == 'SL':
                current_sl += 1
                current_tp = 0
            else:
                current_tp = 0
                current_sl = 0

            if current_tp > max_tp:
                max_tp = current_tp
            if current_sl > max_sl:
                max_sl = current_sl

        return {'tp': max_tp, 'sl': max_sl}

    @staticmethod
    def parse_localized_number(value):
        """Parse localized numeric strings safely (pt-BR and en-US styles)."""
        if value is None:
            return 0.0

        text = str(value).strip()
        if not text:
            return 0.0

        text = text.replace('%', '').replace(' ', '')

        # Handle both separators safely.
        if ',' in text and '.' in text:
            if text.rfind(',') > text.rfind('.'):
                text = text.replace('.', '').replace(',', '.')
            else:
                text = text.replace(',', '')
        elif ',' in text:
            text = text.replace('.', '').replace(',', '.')

        # Keep only valid numeric characters.
        text = re.sub(r'[^0-9\.\-]', '', text)
        if not text or text == '-' or text == '.':
            return 0.0

        try:
            return float(text)
        except ValueError:
            return 0.0

    @staticmethod
    def is_truthy_flag(value):
        """Interpret report booleans from emojis/text."""
        if value is None:
            return False

        text = str(value).strip().lower()
        if not text:
            return False

        if '✅' in text:
            return True
        if '❌' in text:
            return False

        return text in {'true', '1', 'yes', 'sim', 'on'}

    @staticmethod
    def normalize_result(value):
        """Normalize result text to TP/SL/BE/empty."""
        text = str(value or '').strip().upper()
        if text == 'TP':
            return 'TP'
        if text == 'SL':
            return 'SL'
        if text == 'BE':
            return 'BE'
        return ''

    @staticmethod
    def parse_datetime_value(value):
        """Parse datetime from report fields."""
        if value is None:
            return None

        text = str(value).strip()
        if not text or text == '-':
            return None

        formats = (
            '%Y.%m.%d %H:%M:%S',
            '%Y.%m.%d %H:%M',
            '%Y-%m-%d %H:%M:%S',
            '%Y-%m-%d %H:%M',
            '%Y.%m.%d',
            '%Y-%m-%d',
        )
        for fmt in formats:
            try:
                return datetime.strptime(text, fmt)
            except ValueError:
                continue
        return None

    @staticmethod
    def parse_core_detailed_rows(detailed_section):
        """Return detailed rows filtered to first_op and turnof only (exclude pure add-on rows)."""
        if not detailed_section or not detailed_section.get('table'):
            return []

        rows = ReportParser.parse_markdown_table(detailed_section.get('table', ''))
        if not rows:
            return []

        normalized_rows = []
        for idx, row in enumerate(rows):
            op_code = str(row.get('Op Code') or row.get('Flag Op') or '').strip().lower()

            first_flag = ReportParser.is_truthy_flag(row.get('First Op'))
            turn_flag = ReportParser.is_truthy_flag(row.get('Turn Op') or row.get('TurnOf Op'))
            add_flag = ReportParser.is_truthy_flag(row.get('Add Op') or row.get('ADON Op'))

            is_op_code_first = op_code.startswith('first_op') or op_code.startswith('first_')
            is_op_code_turn = (
                op_code.startswith('turn_op')
                or op_code.startswith('turnof_op')
                or op_code.startswith('turn_')
                or op_code.startswith('turnof_')
            )
            is_op_code_add = (
                op_code.startswith('add_op')
                or op_code.startswith('adon_op')
                or op_code.startswith('add_')
                or op_code.startswith('adon_')
            )

            if is_op_code_first:
                first_flag = True
            if is_op_code_turn:
                turn_flag = True
            if is_op_code_add:
                add_flag = True

            # Keep candidate rows for core filtering (first/turn/add),
            # deduping is applied in a second pass below.
            if not (first_flag or turn_flag or add_flag):
                continue

            result_norm = ReportParser.normalize_result(row.get('Result'))
            profit_num = ReportParser.parse_localized_number(row.get('Profit'))
            rr_num = ReportParser.parse_localized_number(row.get('RR'))
            range_num = ReportParser.parse_localized_number(row.get('Channel Range'))
            sliced_flag = ReportParser.is_truthy_flag(row.get('Sliced') or row.get('SLD'))

            entry_dt = (
                ReportParser.parse_datetime_value(row.get('Entry Time'))
                or ReportParser.parse_datetime_value(row.get('Trigger Time'))
                or ReportParser.parse_datetime_value(row.get('Date'))
            )
            exit_dt = ReportParser.parse_datetime_value(row.get('Exit Time'))
            op_chain = str(row.get('Op Chain') or '').strip()
            exit_time_txt = str(row.get('Exit Time') or '').strip()
            addon_count_num = ReportParser.parse_localized_number(
                row.get('ADON Cnt') or row.get('AddOn Cnt') or row.get('Addon Cnt')
            )
            addon_profit_num = ReportParser.parse_localized_number(
                row.get('ADON Profit') or row.get('AddOn Profit') or row.get('Addon Profit')
            )

            normalized = dict(row)
            normalized['_idx'] = idx
            normalized['_entry_dt'] = entry_dt
            normalized['_exit_dt'] = exit_dt
            normalized['_result_norm'] = result_norm
            normalized['_profit_num'] = profit_num
            normalized['_rr_num'] = rr_num
            normalized['_range_num'] = range_num
            normalized['_sliced_flag'] = sliced_flag
            normalized['_first_flag'] = first_flag
            normalized['_turn_flag'] = turn_flag
            normalized['_add_flag'] = add_flag
            normalized['_op_code_add'] = is_op_code_add
            normalized['_group_key'] = f"{op_chain}|{exit_time_txt}"
            normalized['_addon_count_num'] = addon_count_num
            normalized['_addon_profit_num'] = addon_profit_num
            normalized['_is_add_duplicate_cycle'] = False
            normalized_rows.append(normalized)

        # Replicate report dedup heuristic: if base row already aggregates add-on profit
        # for the same chain+exit, mark add-on rows as duplicates for core metrics.
        grouped_rows = {}
        for row in normalized_rows:
            group_key = row.get('_group_key') or ''
            grouped_rows.setdefault(group_key, []).append(row)

        for _, group_rows in grouped_rows.items():
            add_rows = [r for r in group_rows if bool(r.get('_add_flag'))]
            base_rows = [r for r in group_rows if not bool(r.get('_add_flag'))]
            if not add_rows or not base_rows:
                continue

            sum_add_profit = sum(float(r.get('_profit_num') or 0.0) for r in add_rows)
            has_aggregate_match = False
            for base_row in base_rows:
                base_add_count = float(base_row.get('_addon_count_num') or 0.0)
                base_add_profit = float(base_row.get('_addon_profit_num') or 0.0)
                if base_add_count <= 0.0:
                    continue
                if abs(base_add_profit) <= 0.01:
                    continue
                if abs(base_add_profit - sum_add_profit) <= 0.02:
                    has_aggregate_match = True
                    break

            if has_aggregate_match:
                for add_row in add_rows:
                    add_row['_is_add_duplicate_cycle'] = True

        core_rows = []
        for row in normalized_rows:
            add_flag = bool(row.get('_add_flag'))
            first_flag = bool(row.get('_first_flag'))
            turn_flag = bool(row.get('_turn_flag'))

            # Keep first/turn rows even when ADON exists.
            # Exclude only pure ADON rows, except turn/first rows not deduplicated.
            if add_flag:
                if bool(row.get('_is_add_duplicate_cycle')):
                    continue
                if not (first_flag or turn_flag):
                    continue
            elif not (first_flag or turn_flag):
                continue

            core_rows.append(row)

        core_rows.sort(
            key=lambda r: (
                r.get('_exit_dt') is None and r.get('_entry_dt') is None,
                r.get('_exit_dt') or r.get('_entry_dt') or datetime.min,
                r.get('_idx', 0),
            )
        )
        return core_rows

    @staticmethod
    def compute_streaks_from_rows(rows):
        """Compute streaks using only filtered core rows."""
        if not rows:
            return {
                'max_tp_streak': 0,
                'max_sl_streak': 0,
                'max_win_streak': 0,
                'max_win_streak_value': 0.0,
                'max_loss_streak': 0,
                'max_loss_streak_value': 0.0,
            }

        max_tp_streak = 0
        max_sl_streak = 0
        current_tp = 0
        current_sl = 0

        max_win_streak = 0
        max_win_streak_value = 0.0
        max_loss_streak = 0
        max_loss_streak_value = 0.0
        current_win_streak = 0
        current_win_value = 0.0
        current_loss_streak = 0
        current_loss_value = 0.0

        for row in rows:
            result = row.get('_result_norm') or ReportParser.normalize_result(row.get('Result'))
            profit = row.get('_profit_num')
            if profit is None:
                profit = ReportParser.parse_localized_number(row.get('Profit'))

            if not result:
                if profit > 0:
                    result = 'TP'
                elif profit < 0:
                    result = 'SL'

            if result == 'TP':
                current_tp += 1
                current_sl = 0
            elif result == 'SL':
                current_sl += 1
                current_tp = 0
            else:
                current_tp = 0
                current_sl = 0

            max_tp_streak = max(max_tp_streak, current_tp)
            max_sl_streak = max(max_sl_streak, current_sl)

            if profit > 0:
                current_win_streak += 1
                current_win_value += profit
                if current_loss_streak > 0:
                    if (
                        current_loss_streak > max_loss_streak
                        or (
                            current_loss_streak == max_loss_streak
                            and current_loss_value < max_loss_streak_value
                        )
                    ):
                        max_loss_streak = current_loss_streak
                        max_loss_streak_value = current_loss_value
                current_loss_streak = 0
                current_loss_value = 0.0
            elif profit < 0:
                current_loss_streak += 1
                current_loss_value += profit
                if current_win_streak > 0:
                    if (
                        current_win_streak > max_win_streak
                        or (
                            current_win_streak == max_win_streak
                            and current_win_value > max_win_streak_value
                        )
                    ):
                        max_win_streak = current_win_streak
                        max_win_streak_value = current_win_value
                current_win_streak = 0
                current_win_value = 0.0
            else:
                if current_win_streak > 0:
                    if (
                        current_win_streak > max_win_streak
                        or (
                            current_win_streak == max_win_streak
                            and current_win_value > max_win_streak_value
                        )
                    ):
                        max_win_streak = current_win_streak
                        max_win_streak_value = current_win_value
                if current_loss_streak > 0:
                    if (
                        current_loss_streak > max_loss_streak
                        or (
                            current_loss_streak == max_loss_streak
                            and current_loss_value < max_loss_streak_value
                        )
                    ):
                        max_loss_streak = current_loss_streak
                        max_loss_streak_value = current_loss_value
                current_win_streak = 0
                current_win_value = 0.0
                current_loss_streak = 0
                current_loss_value = 0.0

        if current_win_streak > 0:
            if (
                current_win_streak > max_win_streak
                or (
                    current_win_streak == max_win_streak
                    and current_win_value > max_win_streak_value
                )
            ):
                max_win_streak = current_win_streak
                max_win_streak_value = current_win_value

        if current_loss_streak > 0:
            if (
                current_loss_streak > max_loss_streak
                or (
                    current_loss_streak == max_loss_streak
                    and current_loss_value < max_loss_streak_value
                )
            ):
                max_loss_streak = current_loss_streak
                max_loss_streak_value = current_loss_value

        return {
            'max_tp_streak': max_tp_streak,
            'max_sl_streak': max_sl_streak,
            'max_win_streak': max_win_streak,
            'max_win_streak_value': max_win_streak_value,
            'max_loss_streak': max_loss_streak,
            'max_loss_streak_value': max_loss_streak_value,
        }

    @staticmethod
    def summarize_group(rows):
        """Aggregate a group of rows into dashboard metrics."""
        trades = len(rows)
        if trades == 0:
            return {
                'trades': '0',
                'tp': '0',
                'sl': '0',
                'win_rate': '0.00%',
                'net_profit': '0.00',
                'avg_profit': '0.00',
                'profit_factor': '0.00',
                'avg_rr': '0.00',
                'avg_range': '0.00',
            }

        tp_count = 0
        sl_count = 0
        net_profit = 0.0
        gross_profit = 0.0
        gross_loss = 0.0
        rr_sum = 0.0
        range_sum = 0.0

        for row in rows:
            result = row.get('_result_norm') or ReportParser.normalize_result(row.get('Result'))
            profit = row.get('_profit_num')
            if profit is None:
                profit = ReportParser.parse_localized_number(row.get('Profit'))

            if not result:
                if profit > 0:
                    result = 'TP'
                elif profit < 0:
                    result = 'SL'

            if result == 'TP':
                tp_count += 1
            elif result == 'SL':
                sl_count += 1

            net_profit += profit
            if profit > 0:
                gross_profit += profit
            elif profit < 0:
                gross_loss += profit

            rr_value = row.get('_rr_num')
            if rr_value is None:
                rr_value = ReportParser.parse_localized_number(row.get('RR'))
            rr_sum += rr_value

            range_value = row.get('_range_num')
            if range_value is None:
                range_value = ReportParser.parse_localized_number(row.get('Channel Range'))
            range_sum += range_value

        win_rate = (tp_count / trades) * 100.0
        avg_profit = net_profit / trades
        avg_rr = rr_sum / trades
        avg_range = range_sum / trades

        if abs(gross_loss) > 1e-9:
            profit_factor = f"{(gross_profit / abs(gross_loss)):.2f}"
        elif gross_profit > 0:
            profit_factor = 'INF'
        else:
            profit_factor = '0.00'

        return {
            'trades': str(trades),
            'tp': str(tp_count),
            'sl': str(sl_count),
            'win_rate': f"{win_rate:.2f}%",
            'net_profit': f"{net_profit:.2f}",
            'avg_profit': f"{avg_profit:.2f}",
            'profit_factor': profit_factor,
            'avg_rr': f"{avg_rr:.2f}",
            'avg_range': f"{avg_range:.2f}",
        }

    @staticmethod
    def build_operations_card_sections(rows):
        """Build 3 operation sections for card: first_op, sliced, turnof."""
        rows = rows or []
        first_rows = [r for r in rows if bool(r.get('_first_flag'))]
        turn_rows = [r for r in rows if bool(r.get('_turn_flag'))]
        sliced_rows = [r for r in rows if bool(r.get('_sliced_flag'))]

        return {
            'first_op': ReportParser.summarize_group(first_rows),
            'sliced': ReportParser.summarize_group(sliced_rows),
            'turnof': ReportParser.summarize_group(turn_rows),
        }

    @staticmethod
    def _bucket_key_and_start(dt, granularity):
        """Return aggregation key/start datetime for day/week/month."""
        if dt is None:
            return None, None

        if granularity == 'day':
            return dt.strftime('%Y-%m-%d'), datetime(dt.year, dt.month, dt.day)

        if granularity == 'week':
            iso = dt.isocalendar()
            week_year = iso[0]
            week_num = iso[1]
            week_start = datetime.fromisocalendar(week_year, week_num, 1)
            return f"{week_year}-W{week_num:02d}", week_start

        # month (default)
        return dt.strftime('%Y-%m'), datetime(dt.year, dt.month, 1)

    @staticmethod
    def build_chart_timeseries(rows, initial_balance_ref=0.0):
        """Build chart data for day/week/month with PnL, WinRate, traded days and DD on account peak."""
        rows = rows or []
        if not rows:
            return {'day': [], 'week': [], 'month': []}

        ordered_rows = sorted(
            rows,
            key=lambda r: (
                r.get('_exit_dt') is None and r.get('_entry_dt') is None,
                r.get('_exit_dt') or r.get('_entry_dt') or datetime.min,
                r.get('_idx', 0),
            )
        )

        output = {}
        for granularity in ('day', 'week', 'month'):
            account_equity = initial_balance_ref if initial_balance_ref > 0 else 0.0
            account_peak = account_equity
            buckets = {}

            for row in ordered_rows:
                event_dt = row.get('_exit_dt') or row.get('_entry_dt')
                if event_dt is None:
                    continue

                key, start_dt = ReportParser._bucket_key_and_start(event_dt, granularity)
                if key is None:
                    continue

                if key not in buckets:
                    buckets[key] = {
                        'start_dt': start_dt,
                        'trades': 0,
                        'tp': 0,
                        'sl': 0,
                        'net_profit': 0.0,
                        'max_dd_peak_balance': 0.0,
                        'traded_days_set': set(),
                    }

                bucket = buckets[key]
                profit = row.get('_profit_num')
                if profit is None:
                    profit = ReportParser.parse_localized_number(row.get('Profit'))
                result = row.get('_result_norm') or ReportParser.normalize_result(row.get('Result'))

                account_equity += profit
                if account_equity > account_peak:
                    account_peak = account_equity
                dd_value = account_peak - account_equity

                bucket['trades'] += 1
                bucket['net_profit'] += profit
                if dd_value > bucket['max_dd_peak_balance']:
                    bucket['max_dd_peak_balance'] = dd_value

                if result == 'TP' or (not result and profit > 0):
                    bucket['tp'] += 1
                elif result == 'SL' or (not result and profit < 0):
                    bucket['sl'] += 1

                entry_dt = row.get('_entry_dt') or event_dt
                bucket['traded_days_set'].add(entry_dt.strftime('%Y-%m-%d'))

            series = []
            for key, bucket in sorted(buckets.items(), key=lambda item: item[1]['start_dt']):
                trades = bucket['trades']
                tp = bucket['tp']
                win_rate = (tp / trades) * 100.0 if trades > 0 else 0.0
                series.append({
                    'period': key,
                    'trades': str(trades),
                    'tp': str(tp),
                    'sl': str(bucket['sl']),
                    'win_rate': f"{win_rate:.2f}",
                    'net_profit': f"{bucket['net_profit']:.2f}",
                    'traded_days': str(len(bucket['traded_days_set'])),
                    'max_dd_peak_balance': f"{bucket['max_dd_peak_balance']:.2f}",
                })

            output[granularity] = series

        return output

    @staticmethod
    def build_direction_analysis(rows):
        """Build direction analysis from core rows."""
        if not rows:
            return []

        grouped = {}
        for row in rows:
            direction = str(row.get('Direction') or '-').strip().upper()
            grouped.setdefault(direction, []).append(row)

        ordered_keys = [k for k in ('BUY', 'SELL') if k in grouped]
        ordered_keys.extend(sorted([k for k in grouped.keys() if k not in {'BUY', 'SELL'}]))

        result = []
        for key in ordered_keys:
            summary = ReportParser.summarize_group(grouped[key])
            result.append({
                'direction': key,
                'trades': summary['trades'],
                'tp': summary['tp'],
                'sl': summary['sl'],
                'win_rate': summary['win_rate'],
                'net_profit': summary['net_profit'],
                'avg_profit': summary['avg_profit'],
                'profit_factor': summary['profit_factor'],
                'avg_rr': summary['avg_rr'],
                'avg_range': summary['avg_range'],
            })
        return result

    @staticmethod
    def build_entry_type_analysis(rows):
        """Build entry-type analysis from core rows."""
        if not rows:
            return []

        grouped = {}
        for row in rows:
            entry_type = str(row.get('Entry Type') or '-').strip().upper()
            grouped.setdefault(entry_type, []).append(row)

        ordered_keys = [k for k in ('LIMIT', 'MARKET', 'STOP') if k in grouped]
        ordered_keys.extend(sorted([k for k in grouped.keys() if k not in {'LIMIT', 'MARKET', 'STOP'}]))

        result = []
        for key in ordered_keys:
            summary = ReportParser.summarize_group(grouped[key])
            result.append({
                'entry_type': key,
                'trades': summary['trades'],
                'tp': summary['tp'],
                'sl': summary['sl'],
                'win_rate': summary['win_rate'],
                'net_profit': summary['net_profit'],
                'avg_profit': summary['avg_profit'],
                'profit_factor': summary['profit_factor'],
                'avg_rr': summary['avg_rr'],
                'avg_range': summary['avg_range'],
            })
        return result

    @staticmethod
    def build_timeframe_analysis(rows):
        """Build timeframe analysis from core rows when timeframe column exists."""
        if not rows:
            return []

        has_timeframe = any(str(r.get('Timeframe') or '').strip() not in {'', '-'} for r in rows)
        if not has_timeframe:
            return []

        grouped = {}
        for row in rows:
            timeframe = str(row.get('Timeframe') or '-').strip()
            grouped.setdefault(timeframe, []).append(row)

        result = []
        for key in sorted(grouped.keys()):
            summary = ReportParser.summarize_group(grouped[key])
            result.append({
                'timeframe': key,
                'trades': summary['trades'],
                'tp': summary['tp'],
                'sl': summary['sl'],
                'win_rate': summary['win_rate'],
                'net_profit': summary['net_profit'],
                'avg_profit': summary['avg_profit'],
                'profit_factor': summary['profit_factor'],
                'avg_rr': summary['avg_rr'],
                'avg_range': summary['avg_range'],
            })
        return result

    @staticmethod
    def build_weekday_analysis(rows):
        """Build weekday analysis from core rows."""
        weekday_labels = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sab', 'Dom']
        grouped = {label: [] for label in weekday_labels}

        for row in rows or []:
            entry_dt = row.get('_entry_dt') or ReportParser.parse_datetime_value(row.get('Entry Time')) or ReportParser.parse_datetime_value(row.get('Date'))
            if entry_dt is None:
                continue
            weekday_idx = entry_dt.weekday()  # Monday=0
            grouped[weekday_labels[weekday_idx]].append(row)

        result = []
        for label in weekday_labels:
            summary = ReportParser.summarize_group(grouped[label])
            result.append({
                'weekday': label,
                'trades': summary['trades'],
                'tp': summary['tp'],
                'sl': summary['sl'],
                'win_rate': summary['win_rate'],
                'net_profit': summary['net_profit'],
                'avg_profit': summary['avg_profit'],
                'profit_factor': summary['profit_factor'],
                'avg_rr': summary['avg_rr'],
                'avg_range': summary['avg_range'],
            })
        return result

    @staticmethod
    def build_weekday_flag_analysis(rows):
        """Build weekday analysis segmented by flag (First_op / TurnOf)."""
        weekday_labels = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sab', 'Dom']
        grouped = {label: [] for label in weekday_labels}

        for row in rows or []:
            entry_dt = row.get('_entry_dt') or ReportParser.parse_datetime_value(row.get('Entry Time')) or ReportParser.parse_datetime_value(row.get('Date'))
            if entry_dt is None:
                continue
            weekday_idx = entry_dt.weekday()  # Monday=0
            grouped[weekday_labels[weekday_idx]].append(row)

        result = []
        for label in weekday_labels:
            day_rows = grouped[label]
            first_rows = [r for r in day_rows if bool(r.get('_first_flag'))]
            turn_rows = [r for r in day_rows if bool(r.get('_turn_flag'))]

            for flag_name, flag_rows in (('First_op', first_rows), ('TurnOf', turn_rows)):
                summary = ReportParser.summarize_group(flag_rows)
                result.append({
                    'weekday': label,
                    'flag': flag_name,
                    'trades': summary['trades'],
                    'tp': summary['tp'],
                    'sl': summary['sl'],
                    'win_rate': summary['win_rate'],
                    'net_profit': summary['net_profit'],
                    'profit_factor': summary['profit_factor'],
                })

        return result

    @staticmethod
    def build_entry_hour_analysis(rows):
        """Build entry-hour analysis from core rows."""
        grouped = {}

        for row in rows or []:
            entry_dt = row.get('_entry_dt') or ReportParser.parse_datetime_value(row.get('Entry Time')) or ReportParser.parse_datetime_value(row.get('Date'))
            if entry_dt is None:
                continue
            grouped.setdefault(entry_dt.hour, []).append(row)

        result = []
        for hour in sorted(grouped.keys()):
            summary = ReportParser.summarize_group(grouped[hour])
            result.append({
                'hour': f"{hour:02d}h",
                'trades': summary['trades'],
                'tp': summary['tp'],
                'sl': summary['sl'],
                'win_rate': summary['win_rate'],
                'net_profit': summary['net_profit'],
                'avg_profit': summary['avg_profit'],
                'profit_factor': summary['profit_factor'],
                'avg_rr': summary['avg_rr'],
                'avg_range': summary['avg_range'],
            })
        return result

    @staticmethod
    def parse_section_trade_stats(section):
        """Compute total/wins/win_rate/pnl from a trade table section."""
        if not section or not section.get('table'):
            return {
                'total': 0,
                'wins': 0,
                'tp': 0,
                'sl': 0,
                'be': 0,
                'win_rate': 0.0,
                'pnl': 0.0,
                'gross_profit': 0.0,
                'gross_loss_abs': 0.0,
                'profit_factor': '0.00',
            }

        rows = ReportParser.parse_markdown_table(section.get('table', ''))
        if not rows:
            return {
                'total': 0,
                'wins': 0,
                'tp': 0,
                'sl': 0,
                'be': 0,
                'win_rate': 0.0,
                'pnl': 0.0,
                'gross_profit': 0.0,
                'gross_loss_abs': 0.0,
                'profit_factor': '0.00',
            }

        wins = 0
        tp = 0
        sl = 0
        be = 0
        pnl = 0.0
        gross_profit = 0.0
        gross_loss_abs = 0.0
        for row in rows:
            result_text = str(row.get('Result', '')).strip().upper()
            profit_value = ReportParser.parse_localized_number(row.get('Profit', 0))
            pnl += profit_value
            if profit_value > 0:
                gross_profit += profit_value
            elif profit_value < 0:
                gross_loss_abs += abs(profit_value)

            if result_text == 'TP':
                wins += 1
                tp += 1
            elif result_text == 'SL':
                sl += 1
            elif result_text == 'BE':
                be += 1
                if profit_value >= 0:
                    wins += 1
            elif result_text == '':
                # Fallback if Result column is missing/empty.
                if profit_value > 0:
                    wins += 1
                    tp += 1
                elif profit_value < 0:
                    sl += 1

        total = len(rows)
        win_rate = (wins / total) * 100.0 if total > 0 else 0.0
        if gross_loss_abs > 1e-9:
            profit_factor = f"{(gross_profit / gross_loss_abs):.2f}"
        elif gross_profit > 0:
            profit_factor = 'INF'
        else:
            profit_factor = '0.00'

        return {
            'total': total,
            'wins': wins,
            'tp': tp,
            'sl': sl,
            'be': be,
            'win_rate': win_rate,
            'pnl': pnl,
            'gross_profit': gross_profit,
            'gross_loss_abs': gross_loss_abs,
            'profit_factor': profit_factor,
        }

    @staticmethod
    def merge_trade_stats(stats_list):
        """Merge multiple parse_section_trade_stats outputs."""
        totals = {
            'total': 0,
            'wins': 0,
            'tp': 0,
            'sl': 0,
            'be': 0,
            'pnl': 0.0,
            'gross_profit': 0.0,
            'gross_loss_abs': 0.0,
        }
        for stats in stats_list or []:
            if not stats:
                continue
            totals['total'] += int(stats.get('total', 0))
            totals['wins'] += int(stats.get('wins', 0))
            totals['tp'] += int(stats.get('tp', 0))
            totals['sl'] += int(stats.get('sl', 0))
            totals['be'] += int(stats.get('be', 0))
            totals['pnl'] += float(stats.get('pnl', 0.0))
            totals['gross_profit'] += float(stats.get('gross_profit', 0.0))
            totals['gross_loss_abs'] += float(stats.get('gross_loss_abs', 0.0))

        total = totals['total']
        win_rate = (totals['wins'] / total) * 100.0 if total > 0 else 0.0
        if totals['gross_loss_abs'] > 1e-9:
            profit_factor = f"{(totals['gross_profit'] / totals['gross_loss_abs']):.2f}"
        elif totals['gross_profit'] > 0:
            profit_factor = 'INF'
        else:
            profit_factor = '0.00'

        return {
            'total': total,
            'wins': totals['wins'],
            'tp': totals['tp'],
            'sl': totals['sl'],
            'be': totals['be'],
            'win_rate': win_rate,
            'pnl': totals['pnl'],
            'gross_profit': totals['gross_profit'],
            'gross_loss_abs': totals['gross_loss_abs'],
            'profit_factor': profit_factor,
        }
    
    @staticmethod
    def parse_bot_parameters(content):
        """Parse bot parameters section"""
        section = re.search(r'## Parametros do Bot(.*?)## Resumo Geral', content, re.DOTALL)
        if not section:
            return {}
        
        params_text = section.group(1)
        params = {}
        
        # Extract basic info
        params['symbol'] = ReportParser.extract_value(params_text, r'Simbolo:\s*([\w\.]+)')
        params['start_date'] = ReportParser.extract_value(params_text, r'Inicio da execucao:\s*([\d\.\s:]+)')
        params['end_date'] = ReportParser.extract_value(params_text, r'Fim da execucao:\s*([\d\.\s:]+)')
        
        # Extract all parameter tables - match parameter name and value
        table_pattern = r'\|\s*([^\|]+?)\s*\|\s*([^\|\n]+?)\s*\|'
        matches = re.findall(table_pattern, params_text)
        
        for match in matches:
            key = match[0].strip()
            value = match[1].strip()
            # Skip table headers and separators
            if key and key not in ['Parametro', 'Parametro (painel MQL)', 'Valor utilizado', 'Valor'] and not key.startswith('---'):
                params[key] = value
        
        return params
    
    @staticmethod
    def parse_monthly_table(content):
        """Parse monthly summary table"""
        pattern = r'\| (\d{4}-\d{2}) \| (\d+) \|.*?\| ([\d\.]+%) \| ([\d\.\,\-]+) \|.*?\| ([\d\.\,\-]+) \|'
        matches = re.findall(pattern, content)
        
        result = []
        for match in matches:
            result.append({
                'month': match[0],
                'trades': match[1],
                'win_rate': match[2],
                'net_profit': match[3],
                'max_dd': match[4]
            })
        
        return result
    
    @staticmethod
    def parse_direction_table(content):
        """Parse direction analysis table"""
        section = re.search(r'## Analise por Direcao(.*?)##', content, re.DOTALL)
        if not section:
            return []
        
        pattern = r'\| (BUY|SELL) \| (\d+) \|.*?\| ([\d\.]+%) \| ([\d\.\,\-]+) \|.*?\| ([\d\.]+) \|'
        matches = re.findall(pattern, section.group(1))
        
        result = []
        for match in matches:
            result.append({
                'direction': match[0],
                'trades': match[1],
                'win_rate': match[2],
                'net_profit': match[3],
                'profit_factor': match[4]
            })
        
        return result
    
    @staticmethod
    def parse_entry_type_table(content):
        """Parse entry type analysis table"""
        section = re.search(r'## Analise por Tipo de Entrada(.*?)##', content, re.DOTALL)
        if not section:
            return []
        
        pattern = r'\| (LIMIT|MARKET|STOP) \| (\d+) \|.*?\| ([\d\.]+%) \| ([\d\.\,\-]+) \|.*?\| ([\d\.]+) \|'
        matches = re.findall(pattern, section.group(1))
        
        result = []
        for match in matches:
            result.append({
                'entry_type': match[0],
                'trades': match[1],
                'win_rate': match[2],
                'net_profit': match[3],
                'profit_factor': match[4]
            })
        
        return result
    
    @staticmethod
    def parse_timeframe_table(content):
        """Parse timeframe analysis table"""
        section = re.search(r'## Analise por Timeframe(.*?)##', content, re.DOTALL)
        if not section:
            return []
        
        pattern = r'\| (PERIOD_\w+) \| (\d+) \|.*?\| ([\d\.]+%) \| ([\d\.\,\-]+) \|'
        matches = re.findall(pattern, section.group(1))
        
        result = []
        for match in matches:
            result.append({
                'timeframe': match[0],
                'trades': match[1],
                'win_rate': match[2],
                'net_profit': match[3]
            })
        
        return result
    
    @staticmethod
    def parse_flags_table(content):
        """Parse flags analysis table"""
        section = re.search(r'## Analise por Flags(.*?)##', content, re.DOTALL)
        if not section:
            return []

        table_match = re.search(r'(\|.*?\|.*?\n(?:\|.*?\|.*?\n)+)', section.group(1), re.DOTALL)
        if not table_match:
            return []

        rows = ReportParser.parse_markdown_table(table_match.group(1).strip())
        result = []
        for row in rows:
            raw_flag = str(row.get('Flag', '')).strip()
            status = '-'
            flag_name = raw_flag

            if raw_flag.endswith('✅'):
                status = 'ON'
                flag_name = raw_flag[:-1].strip()
            elif raw_flag.endswith('❌'):
                status = 'OFF'
                flag_name = raw_flag[:-1].strip()

            result.append({
                'flag': flag_name,
                'status': status,
                'trades': row.get('Trades', '0'),
                'win_rate': row.get('Win Rate', '0.00%'),
                'net_profit': row.get('Net Profit', '0.00')
            })

        return result[:12]

    @staticmethod
    def parse_weekday_table(content):
        """Parse weekday analysis table"""
        section = re.search(r'## Analise por Dia da Semana(.*?)##', content, re.DOTALL)
        if not section:
            return []

        pattern = r'\| (Seg|Ter|Qua|Qui|Sex|Sab|Dom) \| (\d+) \| (\d+) \| (\d+) \| ([\d\.]+%) \| ([\d\.\,\-]+) \| ([\d\.\,\-]+) \| ([\d\.]+|INF) \| ([\d\.]+) \| ([\d\.]+) \|'
        matches = re.findall(pattern, section.group(1))

        result = []
        for match in matches:
            result.append({
                'weekday': match[0],
                'trades': match[1],
                'tp': match[2],
                'sl': match[3],
                'win_rate': match[4],
                'net_profit': match[5],
                'avg_profit': match[6],
                'profit_factor': match[7],
                'avg_rr': match[8],
                'avg_range': match[9]
            })

        return result

    @staticmethod
    def parse_entry_hour_table(content):
        """Parse entry hour analysis table"""
        section = re.search(r'## Analise por Hora de Entrada(.*?)##', content, re.DOTALL)
        if not section:
            return []
        
        pattern = r'\| (\d+)h \| (\d+) \| (\d+) \| (\d+) \| ([\d\.]+%) \| ([\d\.\,\-]+) \| ([\d\.\,\-]+) \| ([\d\.]+|INF) \| ([\d\.]+) \| ([\d\.]+) \|'
        matches = re.findall(pattern, section.group(1))
        
        result = []
        for match in matches:
            result.append({
                'hour': match[0] + 'h',
                'trades': match[1],
                'tp': match[2],
                'sl': match[3],
                'win_rate': match[4],
                'net_profit': match[5],
                'avg_profit': match[6],
                'profit_factor': match[7],
                'avg_rr': match[8],
                'avg_range': match[9]
            })
        
        return result
    
    @staticmethod
    def parse_top_trades(content, is_best):
        """Parse top/worst trades"""
        section_name = "Maior Profit" if is_best else "Maior Prejuizo"
        section = re.search(f'## Top 10 Operacoes \\({section_name}\\)(.*?)##', content, re.DOTALL)
        if not section:
            return []
        
        pattern = r'\| \d+ \| ([\d\.\-]+) \|.*?\| (BUY|SELL) \| (\w+) \|.*?\| ([\d\.]+) \|.*?\| ([\d\.\,\-]+) \|'
        matches = re.findall(pattern, section.group(1))
        
        result = []
        for match in matches[:10]:
            result.append({
                'date': match[0],
                'direction': match[1],
                'entry_type': match[2],
                'channel_range': match[3],
                'profit': match[4]
            })
        
        return result
    
    @staticmethod
    def parse_dd_table(content):
        """Parse DD tick daily table"""
        section = re.search(r'### Detalhe Diario(.*?)##', content, re.DOTALL)
        if not section:
            return []
        
        pattern = r'\| ([\d\.\-]+) \| ([\d\.\,]+) \| ([\d\.\-: ]+) \| ([\d\.\,]+) \| ([\d\.\-: ]+) \| ([\d\.\,]+) \| ([\d\.\-: ]+) \| (\d+) \|'
        matches = re.findall(pattern, section.group(1))
        
        result = []
        for match in matches:
            result.append({
                'date': match[0],
                'max_floating_dd': match[1],
                'max_floating_time': match[2],
                'max_limit_risk': match[3],
                'max_limit_time': match[4],
                'max_combined': match[5],
                'max_combined_time': match[6],
                'limits_at_peak': match[7]
            })
        
        return result

    @staticmethod
    def resolve_limit_from_percent_and_amount(base_value, percent_cfg, amount_cfg):
        """Replicate EA config resolution for DD limits."""
        limit_by_percent = 0.0
        if percent_cfg > 0.0 and base_value > 0.0:
            limit_by_percent = base_value * (percent_cfg / 100.0)

        if amount_cfg > 0.0:
            if limit_by_percent > 0.0:
                return min(limit_by_percent, amount_cfg)
            return amount_cfg

        return limit_by_percent

    @staticmethod
    def build_dd_open_daily(dd_tick_daily, detailed_section, initial_balance_ref, bot_params):
        """Build daily opening-balance DD limits table for dashboard dropdown."""
        dd_tick_daily = dd_tick_daily or []
        if not dd_tick_daily:
            return []

        bot_params = bot_params or {}

        drawdown_ref = str(
            bot_params.get('DrawdownPercentReference')
            or bot_params.get('Referencia DD percentual')
            or ''
        ).strip().upper()
        use_initial_deposit_ref = (
            ('INITIAL' in drawdown_ref)
            or ('DEPOSITO' in drawdown_ref)
            or ('DEPOSITO' in drawdown_ref)
        )

        force_day_when_below_initial = ReportParser.is_truthy_flag(
            bot_params.get('ForceDayBalanceDDWhenUnderInitialDeposit')
            or bot_params.get('Forcar DD no saldo dia se abaixo do deposito inicial')
        )

        max_daily_dd_pct = ReportParser.parse_localized_number(bot_params.get('MaxDailyDrawdownPercent'))
        max_dd_pct = ReportParser.parse_localized_number(bot_params.get('MaxDrawdownPercent'))
        max_daily_dd_abs = ReportParser.parse_localized_number(bot_params.get('MaxDailyDrawdownAmount'))
        max_dd_abs = ReportParser.parse_localized_number(bot_params.get('MaxDrawdownAmount'))

        # Sum realized PnL by exit date to reconstruct daily opening balance.
        daily_profit_map = {}
        if detailed_section and detailed_section.get('table'):
            detailed_rows = ReportParser.parse_markdown_table(detailed_section.get('table', ''))
            for row in detailed_rows:
                exit_dt = (
                    ReportParser.parse_datetime_value(row.get('Exit Time'))
                    or ReportParser.parse_datetime_value(row.get('Date'))
                )
                if exit_dt is None:
                    continue
                date_key = exit_dt.strftime('%Y-%m-%d')
                profit = ReportParser.parse_localized_number(row.get('Profit'))
                daily_profit_map[date_key] = daily_profit_map.get(date_key, 0.0) + profit

        # Keep order aligned by calendar day from DD table.
        dd_rows = []
        for row in dd_tick_daily:
            date_text = str(row.get('date') or '').strip()
            date_dt = ReportParser.parse_datetime_value(date_text)
            if date_dt is None:
                continue
            dd_rows.append({
                'date_text': date_text,
                'date_key': date_dt.strftime('%Y-%m-%d'),
                'date_dt': date_dt
            })
        dd_rows.sort(key=lambda item: item['date_dt'])

        if not dd_rows:
            return []

        running_balance = initial_balance_ref if initial_balance_ref > 0.0 else 0.0
        peak_balance = running_balance
        output = []

        for day in dd_rows:
            day_key = day['date_key']
            day_open_balance = running_balance

            force_day_ref = (
                force_day_when_below_initial
                and initial_balance_ref > 0.0
                and day_open_balance < initial_balance_ref
            )

            if force_day_ref:
                daily_base = day_open_balance
                max_base = day_open_balance
                effective_ref = 'DAY_BALANCE_FORCED'
            elif use_initial_deposit_ref:
                daily_base = initial_balance_ref
                max_base = initial_balance_ref
                effective_ref = 'INITIAL_DEPOSIT'
            else:
                daily_base = day_open_balance if day_open_balance > 0.0 else initial_balance_ref
                max_base = peak_balance if peak_balance > 0.0 else daily_base
                effective_ref = 'DAY_BALANCE'

            daily_limit = ReportParser.resolve_limit_from_percent_and_amount(
                daily_base, max_daily_dd_pct, max_daily_dd_abs
            )
            max_limit = ReportParser.resolve_limit_from_percent_and_amount(
                max_base, max_dd_pct, max_dd_abs
            )

            output.append({
                'date': day['date_text'],
                'day_open_balance': f"{day_open_balance:.2f}",
                'daily_dd_allowed': f"{daily_limit:.2f}",
                'max_dd_allowed': f"{max_limit:.2f}",
                'effective_ref': effective_ref
            })

            running_balance += daily_profit_map.get(day_key, 0.0)
            if running_balance > peak_balance:
                peak_balance = running_balance

        return output
    
    @staticmethod
    def extract_section_table(content, section_title):
        """Extract complete section markdown table"""
        section = re.search(f'{section_title}(.*?)(?=##|$)', content, re.DOTALL | re.IGNORECASE)
        if not section:
            return None
        
        section_text = section.group(1).strip()
        
        # Extract total
        total_match = re.search(r'Total:\s*\*\*(\d+)\*\*', section_text)
        total = total_match.group(1) if total_match else '0'

        # Extract table lines robustly (supports missing trailing newline on last row).
        table_lines = []
        for raw_line in section_text.splitlines():
            line = raw_line.strip()
            if not line or '|' not in line:
                continue
            first_pipe = line.find('|')
            last_pipe = line.rfind('|')
            if first_pipe < 0 or last_pipe <= first_pipe:
                continue
            normalized = line[first_pipe:last_pipe + 1]
            if normalized.count('|') < 2:
                continue
            table_lines.append(normalized)
        table_markdown = '\n'.join(table_lines) if len(table_lines) >= 2 else ''
        
        return {
            'total': total,
            'table': table_markdown
        }

    @staticmethod
    def extract_first_section_table(content, section_titles):
        """Try multiple section-title regex patterns and return first table found."""
        for title in section_titles:
            section = ReportParser.extract_section_table(content, title)
            if section is not None:
                return section
        return None
    
    @staticmethod
    def parse_no_trade_summary(content):
        """Parse no-trade days summary"""
        section = re.search(r'## Dias sem Operacao \(NoTrade\)(.*?)$', content, re.DOTALL)
        if not section:
            return None
        
        section_text = section.group(1)
        
        source_match = re.search(r'Arquivo fonte no-trades:\s*(.+)', section_text)
        source_path = source_match.group(1).strip() if source_match else ''

        # Extract total
        total_match = re.search(r'Total de dias sem operacao:\s*\*\*(\d+)\*\*', section_text)
        total = total_match.group(1) if total_match else '0'

        reasons_section_match = re.search(
            r'### Resumo por Motivo(.*?)(?=\n### |\n## |\Z)',
            section_text,
            re.DOTALL
        )
        reasons_table = ''
        reasons_rows = []
        if reasons_section_match:
            reasons_text = reasons_section_match.group(1)
            table_match = re.search(r'(\|.*?\|.*?\n(?:\|.*?\|.*?\n)+)', reasons_text, re.DOTALL)
            if table_match:
                reasons_table = table_match.group(1).strip()
                reasons_rows = ReportParser.parse_markdown_table(reasons_table)

        details_section_match = re.search(
            r'### Detalhes de Dias sem Operacao(.*?)(?=\n### |\n## |\Z)',
            section_text,
            re.DOTALL
        )
        details_table = ''
        details_rows = []
        if details_section_match:
            details_text = details_section_match.group(1)
            table_match = re.search(r'(\|.*?\|.*?\n(?:\|.*?\|.*?\n)+)', details_text, re.DOTALL)
            if table_match:
                details_table = table_match.group(1).strip()
                details_rows = ReportParser.parse_markdown_table(details_table)

        limit_canceled = 0
        for row in reasons_rows:
            motivo = (row.get('Motivo') or '').strip()
            dias = row.get('Dias') or '0'
            try:
                dias_int = int(dias)
            except ValueError:
                dias_int = 0
            if 'Limit cancelada' in motivo:
                limit_canceled += dias_int

        # First_op nao ativada: eventos de LIMIT cancelada/não enviada antes da execucao.
        first_op_not_activated_rows = []
        for row in details_rows:
            reason = (ReportParser._row_value(row, ['Reason', 'Motivo'])).lower()
            event_type = (ReportParser._row_value(row, ['Event Type', 'Evento', 'EventType'])).upper()

            is_limit_not_activated = False
            if event_type:
                if event_type.startswith('LIMIT_') and ('CANCELED' in event_type or 'SKIPPED' in event_type or 'RETRY' in event_type):
                    is_limit_not_activated = True
            if not is_limit_not_activated:
                if ('limit cancelada' in reason or
                        'limit nao enviada' in reason or
                        'retry limit cancelada' in reason or
                        reason.startswith('limit ')):
                    is_limit_not_activated = True

            if not is_limit_not_activated:
                continue

            first_op_not_activated_rows.append({
                '#': str(len(first_op_not_activated_rows) + 1),
                'Date': ReportParser._row_value(row, ['Date', 'Data']) or '-',
                'Channel Range': ReportParser._row_value(row, ['Channel Range', 'Range do Canal']) or '-',
                'Timeframe': ReportParser._row_value(row, ['Timeframe']) or '-',
                'Faltou LIMIT (pts)': ReportParser._row_value(row, ['Faltou LIMIT (pts)', 'Missing LIMIT (pts)']) or '-',
                'RR Max': ReportParser._row_value(row, ['RR Max']) or '-',
                'RR Min': ReportParser._row_value(row, ['RR Min']) or '-',
            })

        first_op_not_activated_headers = ['#', 'Date', 'Channel Range', 'Timeframe', 'Faltou LIMIT (pts)', 'RR Max', 'RR Min']
        first_op_not_activated_table = ReportParser._build_markdown_table(
            first_op_not_activated_headers,
            first_op_not_activated_rows
        )

        return {
            'total': total,
            'limit_canceled': str(limit_canceled),
            'reasons_count': str(len(reasons_rows)),
            'source_path': source_path,
            'reason_table': reasons_table,
            'details_table': details_table,
            'details_count': str(len(details_rows)),
            'first_op_not_activated_count': str(len(first_op_not_activated_rows)),
            'first_op_not_activated_table': first_op_not_activated_table
        }


class DashboardHandler(SimpleHTTPRequestHandler):
    """HTTP request handler for dashboard"""
    
    reports_dir = None
    project_root = None
    
    def end_headers(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Cache-Control', 'no-store, no-cache, must-revalidate')
        super().end_headers()

    def send_json(self, status_code, payload):
        self.send_response(status_code)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(payload, ensure_ascii=False).encode('utf-8'))

    def get_reports_root(self):
        return Path(self.project_root, self.reports_dir).resolve()

    def resolve_report_path(self, report_path):
        if report_path is None:
            raise ValueError('Missing path parameter')

        reports_root = self.get_reports_root()
        candidate = Path(str(report_path))
        if not candidate.is_absolute():
            candidate = reports_root / candidate
        candidate = candidate.resolve()

        if reports_root != candidate and reports_root not in candidate.parents:
            raise ValueError('Invalid report path')
        return candidate

    def build_report_meta(self, file_path):
        reports_root = self.get_reports_root()
        rel_path = str(file_path.relative_to(reports_root)).replace('\\', '/')
        path_parts = rel_path.split('/')
        asset = path_parts[0] if len(path_parts) >= 2 else "ROOT"
        initial_balance = path_parts[1] if len(path_parts) >= 3 else "ROOT"
        return {
            'name': rel_path,
            'path': str(file_path.resolve()),
            'relative_path': rel_path,
            'asset': asset,
            'initial_balance': initial_balance,
        }
    
    def do_GET(self):
        """Handle GET requests"""
        parsed_path = urlparse(self.path)
        
        if parsed_path.path == '/api/reports':
            self.handle_reports_list()
        elif parsed_path.path == '/api/report':
            query = parse_qs(parsed_path.query)
            report_path = query.get('path', [None])[0]
            if report_path:
                self.handle_report_data(unquote(report_path))
            else:
                self.send_error(400, 'Missing path parameter')
        else:
            super().do_GET()

    def do_POST(self):
        """Handle POST requests"""
        parsed_path = urlparse(self.path)

        if parsed_path.path not in ('/api/report/rename', '/api/report/delete'):
            self.send_error(404, 'Not found')
            return

        content_len = int(self.headers.get('Content-Length', '0') or 0)
        raw_body = self.rfile.read(content_len) if content_len > 0 else b'{}'
        try:
            payload = json.loads(raw_body.decode('utf-8'))
        except Exception:
            self.send_json(400, {'ok': False, 'error': 'invalid_json'})
            return

        if parsed_path.path == '/api/report/rename':
            self.handle_report_rename(payload)
            return
        if parsed_path.path == '/api/report/delete':
            self.handle_report_delete(payload)
            return
    
    def handle_reports_list(self):
        """Return list of available reports"""
        reports = []
        
        reports_path = self.get_reports_root()
        print(f'Looking for reports in: {reports_path}')
        
        if reports_path.exists():
            md_files = sorted(reports_path.rglob('*.md'))
            print(f'Found {len(md_files)} report file(s) recursively')
            for file_path in md_files:
                reports.append(self.build_report_meta(file_path))
        else:
            print(f'Reports directory does not exist: {reports_path}')
        
        reports.sort(key=lambda x: x.get('relative_path', x.get('name', '')).lower(), reverse=True)
        print(f'Returning {len(reports)} reports')
        self.send_json(200, reports)
    
    def handle_report_data(self, report_path):
        """Parse and return report data"""
        try:
            resolved_path = self.resolve_report_path(report_path)
            if not resolved_path.exists():
                self.send_error(404, f'Report not found: {resolved_path}')
                return
                
            data = ReportParser.parse_report(str(resolved_path))
            self.send_json(200, data)
        except Exception as e:
            print(f'Error parsing report: {str(e)}')
            self.send_error(500, f'Error parsing report: {str(e)}')

    def handle_report_rename(self, payload):
        try:
            old_path = self.resolve_report_path(payload.get('path'))
            if not old_path.exists() or not old_path.is_file():
                self.send_json(404, {'ok': False, 'error': 'report_not_found'})
                return

            new_name = str(payload.get('new_name') or '').strip()
            if not new_name:
                self.send_json(400, {'ok': False, 'error': 'missing_new_name'})
                return
            if '/' in new_name or '\\' in new_name:
                self.send_json(400, {'ok': False, 'error': 'invalid_new_name'})
                return
            if not new_name.lower().endswith('.md'):
                new_name += '.md'

            new_path = old_path.with_name(new_name).resolve()
            reports_root = self.get_reports_root()
            if reports_root != new_path and reports_root not in new_path.parents:
                self.send_json(400, {'ok': False, 'error': 'invalid_target_path'})
                return
            if new_path.exists():
                self.send_json(409, {'ok': False, 'error': 'target_exists'})
                return

            old_path.rename(new_path)
            self.send_json(200, {'ok': True, 'report': self.build_report_meta(new_path)})
        except ValueError as e:
            self.send_json(400, {'ok': False, 'error': str(e)})
        except Exception as e:
            print(f'Error renaming report: {str(e)}')
            self.send_json(500, {'ok': False, 'error': 'rename_failed', 'message': str(e)})

    def handle_report_delete(self, payload):
        try:
            report_path = self.resolve_report_path(payload.get('path'))
            if not report_path.exists() or not report_path.is_file():
                self.send_json(404, {'ok': False, 'error': 'report_not_found'})
                return

            report_path.unlink()
            self.send_json(200, {'ok': True})
        except ValueError as e:
            self.send_json(400, {'ok': False, 'error': str(e)})
        except Exception as e:
            print(f'Error deleting report: {str(e)}')
            self.send_json(500, {'ok': False, 'error': 'delete_failed', 'message': str(e)})


def main():
    parser = argparse.ArgumentParser(description='Trading Dashboard Server')
    parser.add_argument('--host', default='127.0.0.1', help='Server host')
    parser.add_argument('--port', type=int, default=8788, help='Server port')
    parser.add_argument('--reports-dir', default='docs\\relatorios\\operacoes', help='Reports directory')
    
    args = parser.parse_args()
    
    # Get project root
    project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    
    # Set reports directory
    DashboardHandler.reports_dir = args.reports_dir
    DashboardHandler.project_root = project_root
    
    # Change to dashboard directory
    dashboard_dir = os.path.join(os.path.dirname(__file__), 'trading_dashboard')
    if not os.path.exists(dashboard_dir):
        print(f'Error: Dashboard directory not found: {dashboard_dir}')
        return
    
    os.chdir(dashboard_dir)
    
    # Start server
    server = HTTPServer((args.host, args.port), DashboardHandler)
    print(f'Trading Dashboard Server running at http://{args.host}:{args.port}')
    print(f'Project root: {project_root}')
    print(f'Reports directory: {os.path.join(project_root, args.reports_dir)}')
    print('Press Ctrl+C to stop')
    print()
    
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print('\nServer stopped')


if __name__ == '__main__':
    main()
