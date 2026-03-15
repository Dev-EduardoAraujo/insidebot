// Trading Dashboard Application
class TradingDashboard {
    constructor() {
        this.currentData = null;
        this.reports = [];
        this.monthlyChart = null;
        this.chartBarScale = 1.0;
        this.chartWheelHandler = null;
        this.chartDblClickHandler = null;
        this.init();
    }

    init() {
        this.loadReportsList();
        this.setupEventListeners();
    }

    setupEventListeners() {
        document.getElementById('btnReload').addEventListener('click', () => {
            this.loadReportsList();
        });

        document.getElementById('selectReport').addEventListener('change', (e) => {
            this.updateReportActionsState();
            if (e.target.value) {
                this.loadReport(e.target.value);
            }
        });

        const renameBtn = document.getElementById('btnRenameReport');
        if (renameBtn) {
            renameBtn.addEventListener('click', () => {
                this.renameSelectedReport();
            });
        }

        const deleteBtn = document.getElementById('btnDeleteReport');
        if (deleteBtn) {
            deleteBtn.addEventListener('click', () => {
                this.deleteSelectedReport();
            });
        }

        const assetSelect = document.getElementById('selectAsset');
        if (assetSelect) {
            assetSelect.addEventListener('change', () => {
                this.populateReportOptions();
            });
        }

        const balanceSelect = document.getElementById('selectInitialBalance');
        if (balanceSelect) {
            balanceSelect.addEventListener('change', () => {
                this.populateReportOptions();
            });
        }

        const granularitySelect = document.getElementById('chartGranularity');
        if (granularitySelect) {
            granularitySelect.addEventListener('change', () => {
                if (this.currentData) {
                    this.renderMonthlyChart();
                }
            });
        }

        const resetBtn = document.getElementById('chartResetBtn');
        if (resetBtn) {
            resetBtn.addEventListener('click', () => {
                this.resetChartInteractions();
            });
        }
    }

    async loadReportsList() {
        try {
            const response = await fetch('/api/reports');
            if (!response.ok) {
                throw new Error(`HTTP error! status: ${response.status}`);
            }
            const reports = await response.json();
            this.reports = Array.isArray(reports) ? reports : [];
            this.populateReportFilters();
            this.populateReportOptions();
            
            console.log(`Loaded ${reports.length} reports`);
        } catch (error) {
            console.error('Erro ao carregar lista de relatorios:', error);
            alert('Erro ao carregar relatorios. Verifique o console.');
        }
    }

    populateReportFilters() {
        const assetSelect = document.getElementById('selectAsset');
        const balanceSelect = document.getElementById('selectInitialBalance');
        if (!assetSelect || !balanceSelect) return;

        const selectedAsset = assetSelect.value || '';
        const selectedBalance = balanceSelect.value || '';

        const assets = [...new Set(this.reports.map((r) => String(r.asset || 'ROOT')))].sort();
        const balances = [...new Set(this.reports.map((r) => String(r.initial_balance || 'ROOT')))].sort((a, b) => {
            const aNum = parseFloat(String(a).replace(/[^0-9.]/g, ''));
            const bNum = parseFloat(String(b).replace(/[^0-9.]/g, ''));
            if (!Number.isNaN(aNum) && !Number.isNaN(bNum) && aNum !== bNum) return aNum - bNum;
            return String(a).localeCompare(String(b));
        });

        assetSelect.innerHTML = '<option value="">Ativo: todos</option>';
        assets.forEach((asset) => {
            const option = document.createElement('option');
            option.value = asset;
            option.textContent = asset;
            assetSelect.appendChild(option);
        });

        balanceSelect.innerHTML = '<option value="">Saldo inicial: todos</option>';
        balances.forEach((balance) => {
            const option = document.createElement('option');
            option.value = balance;
            option.textContent = balance;
            balanceSelect.appendChild(option);
        });

        if (selectedAsset && assets.includes(selectedAsset)) {
            assetSelect.value = selectedAsset;
        }
        if (selectedBalance && balances.includes(selectedBalance)) {
            balanceSelect.value = selectedBalance;
        }
    }

    getFilteredReports() {
        const asset = (document.getElementById('selectAsset')?.value || '').trim();
        const balance = (document.getElementById('selectInitialBalance')?.value || '').trim();

        return this.reports.filter((report) => {
            const reportAsset = String(report.asset || 'ROOT');
            const reportBalance = String(report.initial_balance || 'ROOT');
            if (asset && reportAsset !== asset) return false;
            if (balance && reportBalance !== balance) return false;
            return true;
        });
    }

    populateReportOptions() {
        const select = document.getElementById('selectReport');
        if (!select) return;

        const previousValue = select.value || '';
        const filteredReports = this.getFilteredReports();
        select.innerHTML = '<option value="">Selecione um relatorio...</option>';

        filteredReports.forEach((report) => {
            const option = document.createElement('option');
            option.value = report.path;
            option.textContent = report.relative_path || report.name || report.path;
            select.appendChild(option);
        });

        const canRestorePrevious = filteredReports.some((r) => r.path === previousValue);
        if (canRestorePrevious) {
            select.value = previousValue;
        }
        this.updateReportActionsState();
    }

    updateReportActionsState() {
        const select = document.getElementById('selectReport');
        const hasSelection = !!(select && select.value);
        const renameBtn = document.getElementById('btnRenameReport');
        const deleteBtn = document.getElementById('btnDeleteReport');
        if (renameBtn) renameBtn.disabled = !hasSelection;
        if (deleteBtn) deleteBtn.disabled = !hasSelection;
    }

    getSelectedReportPath() {
        const select = document.getElementById('selectReport');
        if (!select || !select.value) return '';
        return select.value;
    }

    getSelectedReportName() {
        const select = document.getElementById('selectReport');
        if (!select || select.selectedIndex < 0) return '';
        const option = select.options[select.selectedIndex];
        const label = option ? (option.textContent || option.value || '') : '';
        return this.extractFileName(label);
    }

    extractFileName(pathText) {
        const text = String(pathText || '').trim();
        if (!text) return '';
        const parts = text.split(/[\\/]/);
        return parts[parts.length - 1] || '';
    }

    async apiPost(url, payload) {
        const response = await fetch(url, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload || {})
        });
        let data = null;
        try {
            data = await response.json();
        } catch (_) {
            data = null;
        }
        if (!response.ok) {
            const error = new Error((data && data.error) ? data.error : `http_${response.status}`);
            error.status = response.status;
            error.payload = data;
            throw error;
        }
        return data || {};
    }

    formatReportActionError(action, error) {
        const code = String((error && error.message) || '').trim();
        const map = {
            report_not_found: 'Relatorio nao encontrado.',
            missing_new_name: 'Informe o novo nome do relatorio.',
            invalid_new_name: 'Nome invalido. Use apenas o nome do arquivo.',
            invalid_target_path: 'Destino invalido.',
            target_exists: 'Ja existe um arquivo com esse nome.',
            invalid_json: 'Payload invalido enviado ao servidor.'
        };
        const msg = map[code] || `Falha ao ${action} relatorio (${code || 'erro_desconhecido'}).`;
        return msg;
    }

    async renameSelectedReport() {
        const selectedPath = this.getSelectedReportPath();
        if (!selectedPath) {
            alert('Selecione um relatorio para renomear.');
            return;
        }

        const currentName = this.getSelectedReportName() || this.extractFileName(selectedPath);
        const newNameRaw = window.prompt('Novo nome do relatorio (.md opcional):', currentName);
        if (newNameRaw === null) return;

        const newName = String(newNameRaw || '').trim();
        if (!newName) {
            alert('Nome invalido.');
            return;
        }

        try {
            const result = await this.apiPost('/api/report/rename', {
                path: selectedPath,
                new_name: newName
            });

            await this.loadReportsList();
            const select = document.getElementById('selectReport');
            const newPath = (result && result.report && result.report.path) ? result.report.path : '';
            const hasNewPath = newPath && Array.from(select.options).some((opt) => opt.value === newPath);

            if (hasNewPath) {
                select.value = newPath;
                this.updateReportActionsState();
                await this.loadReport(newPath);
            }

            alert('Relatorio renomeado com sucesso.');
        } catch (error) {
            console.error('Erro ao renomear relatorio:', error);
            alert(this.formatReportActionError('renomear', error));
        }
    }

    async deleteSelectedReport() {
        const selectedPath = this.getSelectedReportPath();
        if (!selectedPath) {
            alert('Selecione um relatorio para excluir.');
            return;
        }

        const reportName = this.getSelectedReportName() || this.extractFileName(selectedPath);
        const firstConfirm = window.confirm(`Excluir relatorio "${reportName}"?`);
        if (!firstConfirm) return;
        const secondConfirm = window.confirm('Confirmar exclusao definitiva do arquivo?');
        if (!secondConfirm) return;

        try {
            await this.apiPost('/api/report/delete', { path: selectedPath });

            await this.loadReportsList();
            const select = document.getElementById('selectReport');
            const firstReportOption = Array.from(select.options).find((opt) => !!opt.value);
            if (firstReportOption) {
                select.value = firstReportOption.value;
                this.updateReportActionsState();
                await this.loadReport(firstReportOption.value);
            } else {
                select.value = '';
                this.updateReportActionsState();
                this.currentData = null;
            }

            alert('Relatorio excluido com sucesso.');
        } catch (error) {
            console.error('Erro ao excluir relatorio:', error);
            alert(this.formatReportActionError('excluir', error));
        }
    }

    async loadReport(path) {
        try {
            const response = await fetch(`/api/report?path=${encodeURIComponent(path)}`);
            if (!response.ok) {
                throw new Error(`HTTP error! status: ${response.status}`);
            }
            const data = await response.json();
            this.currentData = data;
            console.log('Report data loaded:', data);
            this.renderDashboard();
        } catch (error) {
            console.error('Erro ao carregar relatorio:', error);
            alert('Erro ao carregar relatorio. Verifique o console.');
        }
    }

    renderDashboard() {
        if (!this.currentData) return;

        this.renderBotParameters();
        this.renderSummaryCards();
        this.renderMonthlyChart();
        this.renderMetricsTables();
        this.renderTopTradesDropdowns();
        this.renderDDTickDropdown();
        this.renderDDOpenDropdown();
        this.renderAdditionalSections();
    }

    renderAdditionalSections() {
        const data = this.currentData;
        const tables = data.section_tables || {};
        const secondaryOpLabel = data.secondary_op_label || 'Recontagem';
        this.setText('firstOpsTpTitle', 'Operacoes First_op TP');
        this.setText('firstOpsSlTitle', 'Operacoes First_op SL');
        this.setText('firstOpsBeTitle', 'Operacoes First_op BE');
        this.setText('turnofOpsTpTitle', 'Operacoes TurnOf TP');
        this.setText('turnofOpsSlTitle', 'Operacoes TurnOf SL');
        this.setText('turnofOpsBeTitle', 'Operacoes TurnOf BE');
        this.setText('secondaryOpsTpTitle', `Operacoes ${secondaryOpLabel} TP`);
        this.setText('secondaryOpsSlTitle', `Operacoes ${secondaryOpLabel} SL`);
        this.setText('secondaryOpsBeTitle', `Operacoes ${secondaryOpLabel} BE`);
        
        // Detailed Operations
        if (tables.detailed_ops) {
            document.getElementById('detailedOps').innerHTML = this.renderTableSection(tables.detailed_ops, {
                addDailyClosingBalance: true,
                excludeAddonOps: true
            });
        }
        
        // AddOn Operations
        if (tables.addon_ops) {
            document.getElementById('addonOps').innerHTML = this.renderTableSection(tables.addon_ops);
        }
        
        // AddOn Only Operations (real add tickets)
        if (tables.addon_only_ops) {
            document.getElementById('addonOnlyOps').innerHTML = this.renderTableSection(tables.addon_only_ops);
        }
        
        // First_op Operations (split TP/SL/BE)
        if (tables.first_tp_ops) {
            document.getElementById('firstTpOps').innerHTML = this.renderTableSection(tables.first_tp_ops, { excludeAddonOps: true });
        } else if (tables.tp_ops) {
            document.getElementById('firstTpOps').innerHTML = this.renderTableSection(tables.tp_ops, { excludeAddonOps: true });
        } else {
            document.getElementById('firstTpOps').innerHTML = this.renderTableSection(null);
        }
        if (tables.first_sl_ops) {
            document.getElementById('firstSlOps').innerHTML = this.renderTableSection(tables.first_sl_ops, { excludeAddonOps: true });
        } else if (tables.sl_ops) {
            document.getElementById('firstSlOps').innerHTML = this.renderTableSection(tables.sl_ops, { excludeAddonOps: true });
        } else {
            document.getElementById('firstSlOps').innerHTML = this.renderTableSection(null);
        }
        if (tables.first_be_ops) {
            document.getElementById('firstBeOps').innerHTML = this.renderTableSection(tables.first_be_ops, { excludeAddonOps: true });
        } else {
            document.getElementById('firstBeOps').innerHTML = this.renderTableSection(null);
        }

        // TurnOf Operations (split TP/SL/BE)
        if (tables.turnof_tp_ops) {
            document.getElementById('turnofTpOps').innerHTML = this.renderTableSection(tables.turnof_tp_ops, { excludeAddonOps: true });
        } else if (tables.reversal_ops) {
            document.getElementById('turnofTpOps').innerHTML = this.renderTableSection(tables.reversal_ops, { excludeAddonOps: true });
        } else {
            document.getElementById('turnofTpOps').innerHTML = this.renderTableSection(null);
        }
        if (tables.turnof_sl_ops) {
            document.getElementById('turnofSlOps').innerHTML = this.renderTableSection(tables.turnof_sl_ops, { excludeAddonOps: true });
        } else {
            document.getElementById('turnofSlOps').innerHTML = this.renderTableSection(null);
        }
        if (tables.turnof_be_ops) {
            document.getElementById('turnofBeOps').innerHTML = this.renderTableSection(tables.turnof_be_ops, { excludeAddonOps: true });
        } else {
            document.getElementById('turnofBeOps').innerHTML = this.renderTableSection(null);
        }

        // Recontagem Operations (split)
        if (tables.pcm_tp_ops) {
            document.getElementById('pcmTpOps').innerHTML = this.renderTableSection(tables.pcm_tp_ops, { excludeAddonOps: true });
        } else if (tables.pcm_ops) {
            document.getElementById('pcmTpOps').innerHTML = this.renderTableSection(tables.pcm_ops, { excludeAddonOps: true });
        } else {
            document.getElementById('pcmTpOps').innerHTML = this.renderTableSection(null);
        }
        if (tables.pcm_sl_ops) {
            document.getElementById('pcmSlOps').innerHTML = this.renderTableSection(tables.pcm_sl_ops, { excludeAddonOps: true });
        } else {
            document.getElementById('pcmSlOps').innerHTML = this.renderTableSection(null);
        }
        if (tables.pcm_be_ops) {
            document.getElementById('pcmBeOps').innerHTML = this.renderTableSection(tables.pcm_be_ops, { excludeAddonOps: true });
        } else {
            document.getElementById('pcmBeOps').innerHTML = this.renderTableSection(null);
        }
        
        // No Trade Days
        const noTradeData = data.no_trade_summary;
        if (noTradeData) {
            document.getElementById('noTradeDropdown').innerHTML = `
                <div class="table-section">
                    <div class="table-header">Total: <strong>${noTradeData.total}</strong> dias</div>
                    <div class="table-info">LIMIT canceladas: ${noTradeData.limit_canceled} | Motivos unicos: ${noTradeData.reasons_count} | Dias detalhados: ${noTradeData.details_count || '-'}</div>
                    ${noTradeData.source_path ? `<div class="table-info">Fonte: ${noTradeData.source_path}</div>` : ''}
                    <h4 class="metric-title" style="margin-top: 1rem;">Resumo por Motivo</h4>
                    <div class="table-container">
                        ${noTradeData.reason_table ? this.markdownTableToHtml(noTradeData.reason_table) : '<p style="color: var(--text-muted); text-align: center; padding: 1rem;">Sem dados</p>'}
                    </div>
                    <h4 class="metric-title" style="margin-top: 1rem;">Detalhes de Dias sem Operacao</h4>
                    <div class="table-container">
                        ${noTradeData.details_table ? this.markdownTableToHtml(noTradeData.details_table) : '<p style="color: var(--text-muted); text-align: center; padding: 1rem;">Sem dados</p>'}
                    </div>
                </div>
            `;

            document.getElementById('firstOpNotActivatedDropdown').innerHTML = `
                <div class="table-section">
                    <div class="table-header">Total: <strong>${noTradeData.first_op_not_activated_count || '0'}</strong> eventos</div>
                    <div class="table-info">Eventos de first_op nao ativada por LIMIT cancelada/nao enviada antes da execucao</div>
                    <div class="table-container">
                        ${noTradeData.first_op_not_activated_table ? this.markdownTableToHtml(noTradeData.first_op_not_activated_table) : '<p style="color: var(--text-muted); text-align: center; padding: 1rem;">Sem dados</p>'}
                    </div>
                </div>
            `;
        } else {
            document.getElementById('noTradeDropdown').innerHTML = '<p style="color: var(--text-muted); text-align: center; padding: 1rem;">Sem dados</p>';
            document.getElementById('firstOpNotActivatedDropdown').innerHTML = '<p style="color: var(--text-muted); text-align: center; padding: 1rem;">Sem dados</p>';
        }
    }
    
    renderTableSection(section, options = {}) {
        if (!section || !section.table) {
            return '<p style="color: var(--text-muted); text-align: center; padding: 1rem;">Sem dados</p>';
        }

        let tableMarkdown = section.table;
        let total = section.total;
        if (options.excludeAddonOps) {
            const filtered = this.filterOutAddonRows(tableMarkdown);
            tableMarkdown = filtered.table;
            total = String(filtered.total);
        }
        if (!tableMarkdown || !tableMarkdown.trim()) {
            return '<p style="color: var(--text-muted); text-align: center; padding: 1rem;">Sem dados</p>';
        }
        
        return `
            <div class="table-section">
                <div class="table-header">Total: <strong>${total}</strong> operacoes</div>
                <div class="table-container">
                    ${this.markdownTableToHtml(tableMarkdown, options)}
                </div>
            </div>
        `;
    }

    isTruthyTableCell(value) {
        const text = String(value || '').trim().toLowerCase();
        return (
            text === '✅' ||
            text === 'âœ…' ||
            text === 'true' ||
            text === 'sim' ||
            text === 'yes' ||
            text === '1'
        );
    }

    filterOutAddonRows(markdown) {
        const lines = String(markdown || '').trim().split('\n');
        if (lines.length < 2) {
            return { table: markdown, total: 0 };
        }

        const headerLine = lines[0];
        const separatorLine = lines[1];
        const rowLines = lines.slice(2).filter((line) => line.trim());
        const headers = headerLine.split('|').map((h) => h.trim()).filter((h) => h);

        const adonOpIdx = headers.findIndex((h) => {
            const normalized = this.normalizeTableHeader(h);
            return normalized === 'adon op' || normalized === 'adonop';
        });
        const opCodeIdx = headers.findIndex((h) => {
            const normalized = this.normalizeTableHeader(h);
            return normalized === 'op code' || normalized === 'opcode';
        });

        if (adonOpIdx < 0 && opCodeIdx < 0) {
            return { table: markdown, total: rowLines.length };
        }

        const filteredRows = rowLines.filter((line) => {
            const cells = line.split('|').map((c) => c.trim()).filter((c) => c !== '');
            const adonOpCell = adonOpIdx >= 0 ? cells[adonOpIdx] : '';
            const opCodeCell = String(opCodeIdx >= 0 ? (cells[opCodeIdx] || '') : '').trim().toLowerCase();
            const isAddonOperation =
                this.isTruthyTableCell(adonOpCell) ||
                opCodeCell.startsWith('add_') ||
                opCodeCell.startsWith('adon_');
            return !isAddonOperation;
        });

        const filteredTable = [headerLine, separatorLine, ...filteredRows].join('\n');
        return { table: filteredTable, total: filteredRows.length };
    }
    
    markdownTableToHtml(markdown, options = {}) {
        const lines = markdown.trim().split('\n');
        if (lines.length < 2) return '<p>Tabela invalida</p>';
        
        // Parse header
        let headers = lines[0].split('|').map(h => h.trim()).filter(h => h);
        
        // Parse rows (skip separator line)
        let rows = lines.slice(2).map(line => 
            line.split('|').map(cell => cell.trim()).filter(cell => cell !== '')
        );

        if (options.addDailyClosingBalance) {
            const dateIdx = headers.findIndex(h => this.normalizeTableHeader(h) === 'date');
            const profitIdx = headers.findIndex(h => this.normalizeTableHeader(h) === 'profit');

            if (dateIdx >= 0 && profitIdx >= 0) {
                const initialBalance = this.parseNumberSafe(
                    (this.currentData && this.currentData.initial_balance_ref) || 0
                );
                let runningBalance = initialBalance;
                const closingBalanceByDate = {};

                rows.forEach((row) => {
                    const rowDate = (row[dateIdx] || '').trim();
                    if (!rowDate) return;
                    const rowProfit = this.parseNumberSafe(row[profitIdx]);
                    runningBalance += rowProfit;
                    closingBalanceByDate[rowDate] = runningBalance;
                });

                headers = [...headers, 'Saldo Fech. Dia'];
                rows = rows.map((row) => {
                    const rowDate = (row[dateIdx] || '').trim();
                    if (!rowDate || closingBalanceByDate[rowDate] === undefined) {
                        return [...row, '-'];
                    }
                    return [...row, this.formatCurrency(closingBalanceByDate[rowDate])];
                });
            }
        }

        const profitColIdx = headers.findIndex(h => this.normalizeTableHeader(h) === 'profit');
        
        let html = '<table class="ops-table"><thead><tr>';
        headers.forEach(header => {
            html += `<th>${header}</th>`;
        });
        html += '</tr></thead><tbody>';
        
        rows.forEach(row => {
            html += '<tr>';
            row.forEach((cell, idx) => {
                // Color only the profit column.
                if (idx === profitColIdx) {
                    const value = this.parseNumberSafe(cell);
                    const colorClass = value >= 0 ? 'profit-positive' : 'profit-negative';
                    html += `<td class="${colorClass}">${cell}</td>`;
                } else {
                    html += `<td>${cell}</td>`;
                }
            });
            html += '</tr>';
        });
        
        html += '</tbody></table>';
        return html;
    }

    normalizeTableHeader(header) {
        return String(header || '')
            .normalize('NFD')
            .replace(/[\u0300-\u036f]/g, '')
            .trim()
            .toLowerCase();
    }

    renderBotParameters() {
        const params = this.currentData.bot_parameters || {};
        const secondaryOpLabel = (this.currentData && this.currentData.secondary_op_label) || 'Recontagem';
        const container = document.getElementById('botParams');
        
        if (!params || Object.keys(params).length === 0) {
            container.innerHTML = '<p style="color: var(--text-muted); text-align: center; padding: 1rem;">Parametros nao disponiveis</p>';
            return;
        }

        const groups = [
            {
                title: 'Informacoes Gerais',
                keys: ['symbol', 'start_date', 'end_date']
            },
            {
                title: 'Gatilho e Canal',
                keys: ['OpeningHour', 'OpeningMinute', 'FirstEntryMaxHour', 'MaxEntryHour', 'ChannelTimeframe', 'EnableM15Fallback', 'MinChannelRange', 'MaxChannelRange', 'SLDThreshold', 'SlicedThreshold', 'BreakoutMinTolerancePoints', 'Tolerancia minima de rompimento (pontos)']
            },
            {
                title: 'Parametros de Stop e TP',
                keys: ['StopLossIncrement', 'TPMultiplier', 'TPReductionPercent', 'SLDMultiplier', 'SlicedMultiplier']
            },
            {
                title: 'Risco e Retorno',
                keys: [
                    'RiskPercent', 'UseInitialDepositForRisk', 'Usar deposito inicial da conta como base fixa do risco',
                    'InitialDepositReferenceValue', 'Deposito inicial',
                    'FixedLotAllEntries', 'Lote fixo para todas as entradas (0 desativa)',
                    'MinRiskReward',
                    'DrawdownPercentReference', 'Referencia DD percentual',
                    'MaxDailyDrawdownPercent', 'MaxDrawdownPercent',
                    'MaxDailyDrawdownAmount', 'MaxDrawdownAmount',
                    'ForceDayBalanceDDWhenUnderInitialDeposit',
                    'EnableVerboseDDLogs', 'Verbose DD logs',
                    'DDVerboseLogIntervalSeconds', 'Intervalo verbose DD (s)'
                ]
            },
            {
                title: 'TurnOf',
                keys: [
                    'EnableReversal', 'EnableTurnOf',
                    'EnableOvernightReversal', 'EnableOvernightTurnOf',
                    'ReversalMultiplier', 'Multiplicador base do range na TurnOf',
                    'ReversalSLDistanceFactor', 'Fator de distancia do SL na TurnOf',
                    'ReversalTPDistanceFactor', 'Fator de distancia do TP na TurnOf',
                    'AllowReversalAfterMaxEntryHour', 'AllowTurnOfAfterMaxEntryHour',
                    'RearmCanceledReversalNextDay', 'RearmCanceledTurnOfNextDay'
                ]
            },
            {
                title: 'Overnight',
                keys: ['AllowTradeWithOvernight', 'KeepPositionsOvernight', 'KeepPositionsOverWeekend', 'CloseMinutesBeforeMarketClose']
            },
            {
                title: 'Modo de Execucao',
                keys: [
                    'Priorizar LIMIT nas entradas; fechamentos e TurnOfs podem usar mercado',
                    'Priorizar LIMIT nas entradas; fechamentos e turnofs podem usar mercado',
                    'Priorizar LIMIT na primeira entrada do dia',
                    'Priorizar LIMIT na TurnOf',
                    'Priorizar LIMIT na turnof',
                    'Priorizar LIMIT na TurnOf de overnight',
                    'Priorizar LIMIT na turnof de overnight',
                    'Priorizar LIMIT na adicao em flutuacao negativa',
                    'Se LIMIT da TurnOf falhar, usar mercado',
                    'Se LIMIT da turnof falhar, usar mercado',
                    'Se LIMIT da TurnOf overnight falhar, usar mercado',
                    'Se LIMIT da turnof overnight falhar, usar mercado',
                    'StrictLimitOnly',
                    'PreferLimitMainEntry',
                    'PreferLimitReversal',
                    'PreferLimitOvernightReversal',
                    'PreferLimitNegativeAddOn',
                    'AllowMarketFallbackReversal',
                    'AllowMarketFallbackOvernightReversal'
                ]
            },
            {
                title: 'Adicao em Flutuacao Negativa',
                keys: ['EnableNegativeAddOn', 'NegativeAddMaxEntries', 'NegativeAddTriggerPercent', 'NegativeAddLotMultiplier', 'NegativeAddUseSameSLTP', 'EnableNegativeAddTPAdjustment', 'NegativeAddTPDistancePercent', 'NegativeAddTPAdjustOnReversal', 'EnableNegativeAddDebugLogs', 'NegativeAddDebugIntervalSeconds']
            },
            {
                title: `Parametros de Estrategia ${secondaryOpLabel}`,
                keys: [
                    'EnablePCM', 'EnableRecontagem',
                    'EnableSecondOp', 'EnableSecondOpOnNoTradeLimitTarget', 'EnableSecondOpOnFirstOpStopLoss',
                    'EnablePCMOnNoTradeLimitTarget', 'EnableRecontagemOnNoTradeLimitTarget', 'EnableRecontagemOnFirstOpStopLoss',
                    'Habilitar PCM em NoTrade por LIMIT no alvo', 'Habilitar Recontagem em NoTrade por LIMIT no alvo',
                    'BreakEven', 'PCMBreakEven', 'Break even',
                    'PCMBreakEvenTriggerPercent', 'RecontagemBreakEvenTriggerPercent',
                    'Gatilho Break even PCM (% da distancia ate TP)', 'Gatilho Break even Recontagem (% da distancia ate TP)',
                    'TraillingStop', 'TrailingStop', 'Trailling stop',
                    'PCMTPReductionPercent', 'RecontagemTPReductionPercent', 'SecondOpTPReductionPercent',
                    'Reducao TP PCM (%)', 'Reducao TP Recontagem (%)',
                    'PCMRiskPercent', 'RecontagemRiskPercent', 'SecondOpRiskPercent',
                    'Risco por operacao PCM (%)', 'Risco por operacao Recontagem (%)',
                    'PCMNegativeAddTPDistancePercent', 'RecontagemNegativeAddTPDistancePercent', 'SecondOpNegativeAddTPDistancePercent',
                    'Distancia TP apos ADON em PCM (% da dist. ate SL)', 'Distancia TP apos ADON em Recontagem (% da dist. ate SL)',
                    'PCMUseMainChannelRangeParams', 'RecontagemUseMainChannelRangeParams', 'SecondOpUseMainChannelRangeParams',
                    'PCMMinChannelRange', 'RecontagemMinChannelRange', 'SecondOpMinChannelRange',
                    'PCMMaxChannelRange', 'RecontagemMaxChannelRange', 'SecondOpMaxChannelRange',
                    'PCMSlicedThreshold', 'RecontagemSlicedThreshold', 'SecondOpSlicedThreshold',
                    'PCMChannelBars', 'RecontagemChannelBars', 'SecondOpChannelBars',
                    'PCMMaxNoTradeRecounts', 'RecontagemMaxNoTradeRecounts', 'SecondOpMaxNoTradeRecounts',
                    'PCMMaxOperationsPerDay', 'RecontagemMaxOperationsPerDay', 'SecondOpMaxOperationsPerDay',
                    'PCMIgnoreFirstEntryMaxHour', 'RecontagemIgnoreFirstEntryMaxHour', 'SecondOpIgnoreFirstEntryMaxHour',
                    'PCMReferenceTimeframe', 'RecontagemReferenceTimeframe', 'SecondOpReferenceTimeframe',
                    'PCMEnableSkipLargeCandle', 'RecontagemEnableSkipLargeCandle', 'SecondOpEnableSkipLargeCandle',
                    'PCMMaxCandlePoints', 'RecontagemMaxCandlePoints', 'SecondOpMaxCandlePoints',
                    'EnablePCMHourLimit', 'EnableRecontagemHourLimit', 'EnableSecondOpHourLimit',
                    'PCMEntryMaxHour', 'RecontagemEntryMaxHour', 'SecondOpEntryMaxHour',
                    'PCMEntryMaxMinute', 'RecontagemEntryMaxMinute', 'SecondOpEntryMaxMinute',
                    'EnablePCMVerboseLogs', 'EnableRecontagemVerboseLogs', 'EnableSecondOpVerboseLogs',
                    'PCMVerboseIntervalSeconds', 'RecontagemVerboseIntervalSeconds', 'SecondOpVerboseIntervalSeconds'
                ]
            },
            {
                title: 'Interface e Log',
                keys: ['DrawChannels', 'EnableLogging', 'MagicNumber']
            },
            {
                title: 'Parametros adicionais (nao mapeados)',
                keys: []
            }
        ];

        const toDisplayKey = (key) => {
            if (key === 'symbol') return 'Simbolo';
            if (key === 'start_date') return 'Inicio';
            if (key === 'end_date') return 'Fim';
            return String(key)
                .replace(/Sliced/gi, 'SLD')
                .replace(/Reversal/gi, 'TurnOf')
                .replace(/AddOn/gi, 'ADON')
                .replace(/addon/gi, 'ADON')
                .replace(/PCM/gi, 'Recontagem')
                .replace(/turnof/gi, 'TurnOf');
        };

        const renderedKeys = new Set();
        let html = '<div class="params-grid">';
        const appendGroup = (groupName, keys) => {
            const entries = [];
            keys.forEach((key) => {
                if (params[key] === undefined || renderedKeys.has(key)) return;
                renderedKeys.add(key);
                entries.push({ key, value: params[key] });
            });
            if (entries.length === 0) return;

            html += `<div class="param-group">`;
            html += `<div class="param-group-title">${groupName}</div>`;
            entries.forEach((entry) => {
                html += `
                    <div class="param-item">
                        <span class="param-key">${toDisplayKey(entry.key)}</span>
                        <span class="param-value">${entry.value}</span>
                    </div>
                `;
            });
            html += `</div>`;
        };

        groups.forEach((group) => appendGroup(group.title, group.keys));

        const fallbackByGroup = {};
        const fallbackGroupOrder = groups.map((g) => g.title);
        const classifyRemainingKey = (key) => {
            const text = String(key || '');
            if (/secondop|recontagem|pcm|break.?even|traill?ing/i.test(text)) return `Parametros de Estrategia ${secondaryOpLabel}`;
            if (/reversal|turnof|virada/i.test(text)) return 'TurnOf';
            if (/negativeadd|adon|addon/i.test(text)) return 'Adicao em Flutuacao Negativa';
            if (/overnight|weekend|marketclose/i.test(text)) return 'Overnight';
            if (/strictlimit|preferlimit|marketfallback|limit/i.test(text)) return 'Modo de Execucao';
            if (/drawdown|risk|minriskreward|deposit|fixedlot|dd/i.test(text)) return 'Risco e Retorno';
            if (/stoploss|tp|multiplier|sld|sliced/i.test(text)) return 'Parametros de Stop e TP';
            if (/opening|entrymax|channel|range|tolerance|timeframe|fallback/i.test(text)) return 'Gatilho e Canal';
            if (/drawchannels|enablelogging|magicnumber/i.test(text)) return 'Interface e Log';
            return 'Parametros adicionais (nao mapeados)';
        };

        Object.keys(params)
            .filter((k) => !renderedKeys.has(k))
            .forEach((k) => {
                const groupName = classifyRemainingKey(k);
                if (!fallbackByGroup[groupName]) fallbackByGroup[groupName] = [];
                fallbackByGroup[groupName].push(k);
            });

        fallbackGroupOrder.forEach((groupName) => {
            const extraKeys = fallbackByGroup[groupName] || [];
            if (extraKeys.length > 0) {
                appendGroup(groupName, extraKeys);
            }
        });

        html += '</div>';
        container.innerHTML = html;
    }

    renderSummaryCards() {
        const data = this.currentData;
        const secondaryOpLabel = data.secondary_op_label || 'Recontagem';
        this.setText('secondaryOpsCardLabel', secondaryOpLabel);

        // Operacoes (First_op + Turnof) no card principal; Others mostra ADON/SLD/Recontagem
        const opSections = data.operations_card_sections || {};
        const firstSection = opSections.first_op || {};
        const slicedSection = opSections.sliced || {};
        const turnofSection = opSections.turnof || {};
        const addonSection = opSections.addon || {};
        const pcmSection = opSections.pcm || {};

        const firstCount = this.parseIntSafe(firstSection.trades) || this.parseIntSafe(data.first_ops);
        const turnCount = this.parseIntSafe(turnofSection.trades) || this.parseIntSafe(data.turn_ops);
        const totalOpsCard = this.parseIntSafe(data.ops_card_total) || (firstCount + turnCount);
        document.getElementById('totalOps').textContent = totalOpsCard > 0 ? `${totalOpsCard}` : (data.total_operacoes || '-');

        this.setText('firstOpsCount', firstSection.trades || (firstCount > 0 ? `${firstCount}` : '-'));
        this.setText('firstOpsTP', firstSection.tp || '-');
        this.setText('firstOpsSL', firstSection.sl || '-');
        this.setText('firstOpsWinrate', firstSection.win_rate || '-');
        this.setSectionPnL('firstOpsPnL', firstSection.net_profit);

        this.setText('turnofOpsCount', turnofSection.trades || (turnCount > 0 ? `${turnCount}` : '-'));
        this.setText('turnofOpsTP', turnofSection.tp || '-');
        this.setText('turnofOpsSL', turnofSection.sl || '-');
        this.setText('turnofOpsWinrate', turnofSection.win_rate || '-');
        this.setSectionPnL('turnofOpsPnL', turnofSection.net_profit);
        
        // Performance
        const netProfit = parseFloat((data.lucro_liquido || '0').replace(',', ''));
        document.getElementById('netProfit').textContent = this.formatCurrency(netProfit);
        document.getElementById('netProfit').style.color = netProfit >= 0 ? 'var(--green-400)' : 'var(--red-400)';
        
        document.getElementById('winRate').textContent = data.win_rate || '-';
        document.getElementById('profitFactor').textContent = data.profit_factor || '-';
        document.getElementById('payoffRatio').textContent = data.payoff_ratio || '-';
        
        const grossProfit = parseFloat((data.gross_profit || '0').replace(',', ''));
        document.getElementById('grossProfit').textContent = this.formatCurrency(grossProfit);
        document.getElementById('grossProfit').style.color = 'var(--green-400)';
        
        const grossLoss = parseFloat((data.gross_loss || '0').replace(',', ''));
        document.getElementById('grossLoss').textContent = this.formatCurrency(grossLoss);
        document.getElementById('grossLoss').style.color = 'var(--red-400)';
        
        const avgProfit = parseFloat((data.media_profit || '0').replace(',', ''));
        document.getElementById('avgProfit').textContent = this.formatCurrency(avgProfit);
        
        const medianProfit = parseFloat((data.median_profit || '0').replace(',', ''));
        document.getElementById('medianProfit').textContent = this.formatCurrency(medianProfit);
        
        document.getElementById('recoveryFactor').textContent = data.recovery_factor || '-';
        
        // Drawdown
        const maxDD = parseFloat((data.max_drawdown || '0').replace(',', ''));
        document.getElementById('maxDD').textContent = this.formatCurrency(maxDD);
        document.getElementById('maxDD').style.color = 'var(--red-400)';
        
        document.getElementById('maxDDPct').textContent = data.max_drawdown_pct || data.max_dd_tick_floating_pct || '-';
        document.getElementById('maxDDTick').textContent = this.formatCurrency(data.max_dd_tick_floating || 0);
        document.getElementById('maxDDTickPct').textContent = data.max_dd_tick_floating_pct || '-';
        document.getElementById('maxDDCombined').textContent = this.formatCurrency(data.max_dd_tick_combined || 0);
        document.getElementById('peakFloatingDate').textContent = data.peak_floating_date || '-';
        document.getElementById('peakFloatingTime').textContent = data.peak_floating_time || '-';
        document.getElementById('peakFloatingPositions').textContent = data.peak_floating_positions ? `${data.peak_floating_positions} pos` : '-';
        document.getElementById('daysMonitored').textContent = data.days_monitored || '-';
        
        // Extremos
        const bestTrade = parseFloat((data.best_trade || '0').replace(',', ''));
        document.getElementById('bestTrade').textContent = this.formatCurrency(bestTrade);
        document.getElementById('bestTrade').style.color = 'var(--green-400)';
        
        const worstTrade = parseFloat((data.worst_trade || '0').replace(',', ''));
        document.getElementById('worstTrade').textContent = this.formatCurrency(worstTrade);
        
        const avgMFE = parseFloat((data.avg_mfe || '0').replace(',', ''));
        document.getElementById('avgMFE').textContent = this.formatCurrency(avgMFE);
        
        const avgMAE = parseFloat((data.avg_mae || '0').replace(',', ''));
        document.getElementById('avgMAE').textContent = this.formatCurrency(avgMAE);
        
        const maxMFE = parseFloat((data.max_mfe || '0').replace(',', ''));
        document.getElementById('maxMFE').textContent = this.formatCurrency(maxMFE);
        
        const minMAE = parseFloat((data.min_mae || '0').replace(',', ''));
        document.getElementById('minMAE').textContent = this.formatCurrency(minMAE);
        
        document.getElementById('avgAdverseToSL').textContent = data.avg_adverse_to_sl || '-';
        
        // Others (Addons + Sliced + Recontagem)
        const addonCount = this.parseIntSafe(addonSection.trades) || this.parseIntSafe(data.addon_only_total) || this.parseIntSafe(data.total_addons);
        const slicedCount = this.parseIntSafe(slicedSection.trades);
        const pcmCount = this.parseIntSafe(pcmSection.trades) || this.parseIntSafe(data.pcm_total);
        this.setText('opsWithAddon', `${addonCount + slicedCount + pcmCount}`);

        this.setText('addonOpsCount', addonSection.trades || data.addon_only_total || data.total_addons || '-');
        this.setText('addonOpsTP', addonSection.tp || data.addon_only_tp || '-');
        this.setText('addonOpsSL', addonSection.sl || data.addon_only_sl || '-');
        this.setText('addonOpsWinrate', addonSection.win_rate || data.addon_only_win_rate || '-');
        this.setSectionPnL('addonOpsPnL', addonSection.net_profit || data.addon_only_pnl);

        this.setText('slicedOpsCount', slicedSection.trades || '-');
        this.setText('slicedOpsTP', slicedSection.tp || '-');
        this.setText('slicedOpsSL', slicedSection.sl || '-');
        this.setText('slicedOpsWinrate', slicedSection.win_rate || '-');
        this.setSectionPnL('slicedOpsPnL', slicedSection.net_profit);

        this.setText('pcmOpsCount', pcmSection.trades || data.pcm_total || '-');
        this.setText('pcmOpsTP', pcmSection.tp || data.pcm_tp || '-');
        this.setText('pcmOpsSL', pcmSection.sl || data.pcm_sl || '-');
        this.setText('pcmOpsWinrate', pcmSection.win_rate || data.pcm_win_rate || '-');
        this.setSectionPnL('pcmOpsPnL', pcmSection.net_profit || data.pcm_pnl);
        
        // Sequencias
        document.getElementById('maxWinStreak').textContent = data.max_win_streak ? `${data.max_win_streak} trades` : '-';
        
        const maxWinStreakValue = parseFloat((data.max_win_streak_value || '0').replace(',', ''));
        document.getElementById('maxWinStreakValue').textContent = this.formatCurrency(maxWinStreakValue);
        
        const maxLossStreakEl = document.getElementById('maxLossStreak');
        if (maxLossStreakEl) {
            maxLossStreakEl.textContent = data.max_loss_streak ? `${data.max_loss_streak} trades` : '-';
        }
        
        const maxLossStreakValue = parseFloat((data.max_loss_streak_value || '0').replace(',', ''));
        document.getElementById('maxLossStreakValue').textContent = this.formatCurrency(maxLossStreakValue);
        
        document.getElementById('maxTPStreak').textContent = data.max_tp_streak ? `${data.max_tp_streak} trades` : '-';
        document.getElementById('maxSLStreak').textContent = data.max_sl_streak ? `${data.max_sl_streak} trades` : '-';
    }

    renderMonthlyChart() {
        const granularity = (document.getElementById('chartGranularity') || {}).value || 'month';
        const data = this.getChartSeries(granularity);
        const titleByGranularity = {
            day: 'Resumo Diario',
            week: 'Resumo Semanal',
            month: 'Resumo Mensal'
        };
        this.setText('chartTitle', titleByGranularity[granularity] || 'Resumo Temporal');
        
        const ctx = document.getElementById('monthlyChart');
        
        if (this.monthlyChart) {
            this.monthlyChart.destroy();
        }

        const rawPeriods = data.map(m => m.period || m.month || '-');
        const labels = rawPeriods.map(p => this.formatChartPeriodLabel(p, granularity));
        const profits = data.map(m => this.parseNumberSafe(m.net_profit));
        const ddPeakBalance = data.map(m => this.parseNumberSafe(m.max_dd_peak_balance || m.max_dd));
        const winRates = data.map(m => this.parseNumberSafe(String(m.win_rate || '0').replace('%', '')));
        const tradedDays = data.map(m => this.parseNumberSafe(m.traded_days));
        const readability = this.getChartReadabilityConfig(granularity, labels.length);
        const barVisual = this.getBarVisualOptions();
        const barPercentage = this.clamp(barVisual.barPercentage * readability.barDensityFactor, 0.12, 1.0);
        const categoryPercentage = this.clamp(barVisual.categoryPercentage * readability.barDensityFactor, 0.18, 1.0);

        this.monthlyChart = new Chart(ctx, {
            type: 'line',
            data: {
                labels: labels,
                datasets: [
                    {
                        label: 'PnL',
                        data: profits,
                        backgroundColor: profits.map(p => p >= 0 ? 'rgba(34, 197, 94, 0.8)' : 'rgba(239, 68, 68, 0.8)'),
                        borderColor: profits.map(p => p >= 0 ? '#22c55e' : '#ef4444'),
                        borderWidth: 1,
                        barPercentage: barPercentage,
                        categoryPercentage: categoryPercentage,
                        order: 10,
                        yAxisID: 'yCurrency',
                        type: 'bar'
                    },
                    {
                        label: 'DD Maximo (Pico Saldo)',
                        data: ddPeakBalance,
                        backgroundColor: 'rgba(239, 68, 68, 0.12)',
                        borderColor: '#ef4444',
                        borderWidth: 2,
                        pointRadius: readability.pointRadius,
                        tension: 0.25,
                        order: 1,
                        yAxisID: 'yCurrency',
                        type: 'line'
                    },
                    {
                        label: 'Win Rate (%)',
                        data: winRates,
                        backgroundColor: 'rgba(99, 102, 241, 0.15)',
                        borderColor: '#6366f1',
                        borderWidth: 2,
                        pointRadius: readability.pointRadius,
                        tension: 0.25,
                        order: 1,
                        yAxisID: 'yPercent',
                        type: 'line'
                    },
                    {
                        label: 'Dias Operados',
                        data: tradedDays,
                        backgroundColor: 'rgba(250, 204, 21, 0.15)',
                        borderColor: '#facc15',
                        borderWidth: 2,
                        pointRadius: readability.pointRadius,
                        tension: 0.25,
                        order: 1,
                        yAxisID: 'yDays',
                        type: 'line'
                    }
                ]
            },
            options: {
                responsive: true,
                maintainAspectRatio: true,
                aspectRatio: 3,
                plugins: {
                    legend: {
                        labels: {
                            color: '#d1d5db',
                            font: {
                                size: 12
                            }
                        }
                    },
                    tooltip: {
                        callbacks: {
                            title: (items) => {
                                if (!items || items.length === 0) {
                                    return '';
                                }
                                const idx = items[0].dataIndex;
                                return rawPeriods[idx] || items[0].label || '';
                            }
                        }
                    },
                    zoom: {
                        limits: {
                            x: { min: 0, max: Math.max(0, labels.length - 1) }
                        },
                        pan: {
                            enabled: true,
                            mode: 'x',
                            modifierKey: 'ctrl'
                        },
                        zoom: {
                            wheel: { enabled: true },
                            pinch: { enabled: true },
                            drag: {
                                enabled: true,
                                backgroundColor: 'rgba(99, 102, 241, 0.18)',
                                borderColor: '#6366f1',
                                borderWidth: 1
                            },
                            mode: 'x'
                        }
                    }
                },
                scales: {
                    yCurrency: {
                        type: 'linear',
                        position: 'left',
                        ticks: {
                            color: '#9ca3af',
                            font: {
                                size: 11
                            }
                        },
                        grid: {
                            color: '#374151'
                        }
                    },
                    yPercent: {
                        type: 'linear',
                        position: 'right',
                        min: 0,
                        max: 100,
                        ticks: {
                            color: '#9ca3af',
                            font: {
                                size: 11
                            },
                            callback: (value) => `${value}%`
                        },
                        grid: {
                            drawOnChartArea: false
                        }
                    },
                    yDays: {
                        type: 'linear',
                        position: 'right',
                        offset: true,
                        min: 0,
                        ticks: {
                            color: '#9ca3af',
                            font: {
                                size: 11
                            }
                        },
                        grid: {
                            drawOnChartArea: false
                        }
                    },
                    x: {
                        min: readability.xMin,
                        max: readability.xMax,
                        ticks: {
                            color: '#9ca3af',
                            autoSkip: true,
                            maxTicksLimit: readability.maxTicks,
                            maxRotation: readability.labelRotation,
                            minRotation: readability.labelRotation,
                            font: {
                                size: 11
                            }
                        },
                        grid: {
                            color: '#374151'
                        }
                    }
                }
            }
        });

        this.bindChartMouseInteractions();
    }

    getChartReadabilityConfig(granularity, totalPoints) {
        const count = Number.isFinite(totalPoints) ? totalPoints : 0;
        const cfg = {
            windowSize: count,
            maxTicks: 12,
            labelRotation: 0,
            barDensityFactor: 1.0,
            pointRadius: 2,
            xMin: undefined,
            xMax: undefined
        };

        if (granularity === 'day') {
            cfg.windowSize = Math.min(45, count);
            cfg.maxTicks = 8;
            cfg.barDensityFactor = 0.68;
            cfg.pointRadius = 0;
        } else if (granularity === 'week') {
            cfg.windowSize = Math.min(32, count);
            cfg.maxTicks = 10;
            cfg.barDensityFactor = 0.85;
            cfg.pointRadius = 1;
        } else {
            cfg.windowSize = count;
            cfg.maxTicks = 12;
            cfg.barDensityFactor = 1.0;
            cfg.pointRadius = 2;
        }

        if (count > cfg.windowSize) {
            cfg.xMin = count - cfg.windowSize;
            cfg.xMax = count - 1;
        }
        return cfg;
    }

    formatChartPeriodLabel(period, granularity) {
        const text = String(period || '').trim();
        if (!text) {
            return '-';
        }

        if (granularity === 'day') {
            const m = text.match(/^(\d{4})-(\d{2})-(\d{2})$/);
            if (m) {
                return `${m[3]}/${m[2]}`;
            }
        }

        if (granularity === 'week') {
            const m = text.match(/^(\d{4})-W(\d{2})$/);
            if (m) {
                return `W${m[2]}/${m[1].slice(-2)}`;
            }
        }

        if (granularity === 'month') {
            const m = text.match(/^(\d{4})-(\d{2})$/);
            if (m) {
                return `${m[2]}/${m[1].slice(-2)}`;
            }
        }

        return text;
    }

    bindChartMouseInteractions() {
        if (!this.monthlyChart || !this.monthlyChart.canvas) {
            return;
        }

        const canvas = this.monthlyChart.canvas;

        if (this.chartWheelHandler) {
            canvas.removeEventListener('wheel', this.chartWheelHandler);
        }
        if (this.chartDblClickHandler) {
            canvas.removeEventListener('dblclick', this.chartDblClickHandler);
        }

        this.chartWheelHandler = (event) => {
            // Shift + wheel controls bar width scale.
            if (!event.shiftKey) {
                return;
            }
            event.preventDefault();
            const step = event.deltaY < 0 ? 0.06 : -0.06;
            this.chartBarScale = Math.max(0.35, Math.min(1.35, this.chartBarScale + step));
            this.applyBarScaleToChart();
        };

        this.chartDblClickHandler = (event) => {
            event.preventDefault();
            this.resetChartInteractions();
        };

        canvas.addEventListener('wheel', this.chartWheelHandler, { passive: false });
        canvas.addEventListener('dblclick', this.chartDblClickHandler);
    }

    getBarVisualOptions() {
        const baseBar = 0.85;
        const baseCat = 0.9;
        return {
            barPercentage: Math.max(0.2, Math.min(1.0, baseBar * this.chartBarScale)),
            categoryPercentage: Math.max(0.25, Math.min(1.0, baseCat * this.chartBarScale))
        };
    }

    applyBarScaleToChart() {
        if (!this.monthlyChart) {
            return;
        }
        const ds = (this.monthlyChart.data && this.monthlyChart.data.datasets) || [];
        if (ds.length === 0) {
            return;
        }
        const barDataset = ds.find(d => d.type === 'bar') || ds[0];
        const granularity = (document.getElementById('chartGranularity') || {}).value || 'month';
        const labelsCount = (this.monthlyChart.data && this.monthlyChart.data.labels && this.monthlyChart.data.labels.length) || 0;
        const readability = this.getChartReadabilityConfig(granularity, labelsCount);
        const opts = this.getBarVisualOptions();
        barDataset.barPercentage = this.clamp(opts.barPercentage * readability.barDensityFactor, 0.12, 1.0);
        barDataset.categoryPercentage = this.clamp(opts.categoryPercentage * readability.barDensityFactor, 0.18, 1.0);
        this.monthlyChart.update('none');
    }

    resetChartInteractions() {
        this.chartBarScale = 1.0;
        this.applyBarScaleToChart();
        if (this.monthlyChart && typeof this.monthlyChart.resetZoom === 'function') {
            this.monthlyChart.resetZoom();
        }
    }

    getChartSeries(granularity) {
        const ts = (this.currentData && this.currentData.chart_timeseries) || {};
        const rows = ts[granularity];
        if (Array.isArray(rows) && rows.length > 0) {
            return rows;
        }

        // Fallback legado para grafico mensal em relatorios antigos.
        if (granularity === 'month') {
            const monthly = this.currentData.monthly_summary || [];
            return monthly.map(m => ({
                period: m.month || '-',
                net_profit: m.net_profit || '0',
                win_rate: (m.win_rate || '0').toString().replace('%', ''),
                traded_days: '0',
                max_dd_peak_balance: m.max_dd || '0'
            }));
        }
        return [];
    }

    renderMetricsTables() {
        // General Analysis (Direction + Entry Type + Timeframe in one card)
        const directionData = this.currentData.direction_analysis || [];
        const entryTypeData = this.currentData.entry_type_analysis || [];
        const timeframeData = this.currentData.timeframe_analysis || [];
        
        let combinedData = [];
        if (directionData.length > 0) combinedData = combinedData.concat(directionData);
        if (entryTypeData.length > 0) combinedData = combinedData.concat(entryTypeData);
        if (timeframeData.length > 0) combinedData = combinedData.concat(timeframeData);
        
        this.renderTable('generalAnalysis', combinedData, [
            { key: 'direction', label: 'Categoria', customKey: (row) => row.direction || row.entry_type || row.timeframe },
            { key: 'trades', label: 'Trades' },
            { key: 'win_rate', label: 'Win Rate' },
            { key: 'net_profit', label: 'PnL', format: 'currency' },
            { key: 'profit_factor', label: 'PF' }
        ]);

        // Flags Analysis
        const flagsData = this.currentData.flags_analysis || [];
        this.renderTable('flagsTable', flagsData, [
            { key: 'flag', label: 'Flag' },
            { key: 'status', label: 'Status' },
            { key: 'trades', label: 'Trades' },
            { key: 'win_rate', label: 'Win Rate' },
            { key: 'net_profit', label: 'PnL', format: 'currency' }
        ]);

        // Weekday Analysis
        const weekdayData = this.currentData.weekday_analysis || [];
        this.renderTable('weekdayTable', weekdayData, [
            { key: 'weekday', label: 'Dia' },
            { key: 'trades', label: 'Trades' },
            { key: 'win_rate', label: 'Win Rate' },
            { key: 'net_profit', label: 'PnL', format: 'currency' },
            { key: 'profit_factor', label: 'PF' }
        ]);

        // Weekday by Flag Analysis
        const weekdayFlagData = this.currentData.weekday_flag_analysis || [];
        this.renderTable('weekdayFlagTable', weekdayFlagData, [
            { key: 'weekday', label: 'Dia' },
            { key: 'flag', label: 'Flag' },
            { key: 'trades', label: 'Trades' },
            { key: 'tp', label: 'TP' },
            { key: 'sl', label: 'SL' },
            { key: 'win_rate', label: 'Win Rate' },
            { key: 'net_profit', label: 'PnL', format: 'currency' },
            { key: 'profit_factor', label: 'PF' }
        ]);

        // Entry Hour Analysis
        const entryHourData = this.currentData.entry_hour_analysis || [];
        this.renderTable('entryHourTable', entryHourData, [
            { key: 'hour', label: 'Hora' },
            { key: 'trades', label: 'Trades' },
            { key: 'win_rate', label: 'Win Rate' },
            { key: 'net_profit', label: 'PnL', format: 'currency' },
            { key: 'profit_factor', label: 'PF' }
        ]);
    }

    renderTable(containerId, data, columns) {
        const container = document.getElementById(containerId);
        
        if (!data || data.length === 0) {
            container.innerHTML = '<p style="color: var(--text-muted); text-align: center; padding: 1rem;">Sem dados</p>';
            return;
        }

        let html = '<table><thead><tr>';
        columns.forEach(col => {
            html += `<th>${col.label}</th>`;
        });
        html += '</tr></thead><tbody>';

        data.forEach(row => {
            html += '<tr>';
            columns.forEach(col => {
                let value;
                if (col.customKey) {
                    value = col.customKey(row);
                } else {
                    value = row[col.key] || '-';
                }
                
                if (col.format === 'currency') {
                    const num = parseFloat(value);
                    value = this.formatCurrency(num);
                    const colorClass = num >= 0 ? 'badge-green' : 'badge-red';
                    html += `<td class="${colorClass}">${value}</td>`;
                } else {
                    html += `<td>${value}</td>`;
                }
            });
            html += '</tr>';
        });

        html += '</tbody></table>';
        container.innerHTML = html;
    }

    renderTopTradesDropdowns() {
        const topTrades = this.currentData.top_trades || [];
        const worstTrades = this.currentData.worst_trades || [];

        document.getElementById('topTradesDropdown').innerHTML = this.renderTradesTable(topTrades, true);
        document.getElementById('worstTradesDropdown').innerHTML = this.renderTradesTable(worstTrades, false);
    }

    renderTradesTable(trades, isPositive) {
        if (!trades || trades.length === 0) {
            return '<p style="color: var(--text-muted); text-align: center; padding: 1rem;">Sem dados</p>';
        }

        let html = '<div class="table-container"><table class="ops-table"><thead><tr>';
        html += '<th>#</th><th>Data</th><th>Direcao</th><th>Tipo Entrada</th><th>Channel Range</th><th>Profit</th>';
        html += '</tr></thead><tbody>';

        trades.forEach((trade, index) => {
            const profit = parseFloat(trade.profit || 0);
            const profitClass = profit >= 0 ? 'profit-positive' : 'profit-negative';
            
            html += `
                <tr>
                    <td>${index + 1}</td>
                    <td>${trade.date || '-'}</td>
                    <td>${trade.direction || '-'}</td>
                    <td>${trade.entry_type || '-'}</td>
                    <td>${trade.channel_range || '-'}</td>
                    <td class="${profitClass}">${this.formatCurrency(profit)}</td>
                </tr>
            `;
        });

        html += '</tbody></table></div>';
        return html;
    }

    renderDDTickDropdown() {
        const ddData = this.currentData.dd_tick_daily || [];
        
        if (!ddData || ddData.length === 0) {
            document.getElementById('ddTickDropdown').innerHTML = '<p style="color: var(--text-muted); text-align: center; padding: 1rem;">Sem dados</p>';
            return;
        }

        let html = '<div class="table-container"><table class="ops-table"><thead><tr>';
        html += '<th>Data</th><th>Max Floating DD</th><th>Hora</th><th>Max LIMIT Risk</th><th>Hora</th><th>Max Combinado</th><th>Hora</th><th>LIMITs no Pico</th>';
        html += '</tr></thead><tbody>';

        ddData.forEach(day => {
            html += `
                <tr>
                    <td>${day.date || '-'}</td>
                    <td class="profit-negative">${this.formatCurrency(day.max_floating_dd || 0)}</td>
                    <td>${day.max_floating_time || '-'}</td>
                    <td class="profit-negative">${this.formatCurrency(day.max_limit_risk || 0)}</td>
                    <td>${day.max_limit_time || '-'}</td>
                    <td class="profit-negative">${this.formatCurrency(day.max_combined || 0)}</td>
                    <td>${day.max_combined_time || '-'}</td>
                    <td>${day.limits_at_peak || '0'}</td>
                </tr>
            `;
        });

        html += '</tbody></table></div>';
        document.getElementById('ddTickDropdown').innerHTML = html;
    }

    renderDDOpenDropdown() {
        const ddOpenData = this.currentData.dd_open_daily || [];
        const container = document.getElementById('ddOpenDropdown');

        if (!container) {
            return;
        }

        if (!ddOpenData || ddOpenData.length === 0) {
            container.innerHTML = '<p style="color: var(--text-muted); text-align: center; padding: 1rem;">Sem dados</p>';
            return;
        }

        let html = '<div class="table-container"><table class="ops-table"><thead><tr>';
        html += '<th>Data</th><th>Saldo Inicio Dia</th><th>DD Max Diario Permitido</th><th>DD Max Geral Permitido</th>';
        html += '</tr></thead><tbody>';

        ddOpenData.forEach(day => {
            html += `
                <tr>
                    <td>${day.date || '-'}</td>
                    <td>${this.formatCurrency(day.day_open_balance || 0)}</td>
                    <td class="profit-negative">${this.formatCurrency(day.daily_dd_allowed || 0)}</td>
                    <td class="profit-negative">${this.formatCurrency(day.max_dd_allowed || 0)}</td>
                </tr>
            `;
        });

        html += '</tbody></table></div>';
        container.innerHTML = html;
    }

    formatCurrency(value) {
        const num = parseFloat(value) || 0;
        return new Intl.NumberFormat('pt-BR', {
            minimumFractionDigits: 2,
            maximumFractionDigits: 2
        }).format(num);
    }

    parseIntSafe(value) {
        const parsed = parseInt(value, 10);
        return Number.isFinite(parsed) ? parsed : 0;
    }

    parseNumberSafe(value) {
        if (value === undefined || value === null) {
            return 0;
        }
        const text = String(value).trim();
        if (!text) {
            return 0;
        }

        // Handle pt-BR and en-US formats.
        let normalized = text.replace(/%/g, '').replace(/\s+/g, '');
        if (normalized.includes(',') && normalized.includes('.')) {
            if (normalized.lastIndexOf(',') > normalized.lastIndexOf('.')) {
                normalized = normalized.replace(/\./g, '').replace(',', '.');
            } else {
                normalized = normalized.replace(/,/g, '');
            }
        } else if (normalized.includes(',')) {
            normalized = normalized.replace(/\./g, '').replace(',', '.');
        }

        const num = parseFloat(normalized);
        return Number.isFinite(num) ? num : 0;
    }

    clamp(value, min, max) {
        return Math.max(min, Math.min(max, value));
    }

    setText(id, value) {
        const el = document.getElementById(id);
        if (el) {
            el.textContent = value;
        }
    }

    setSectionPnL(id, value) {
        const el = document.getElementById(id);
        if (!el) return;

        const raw = value === undefined || value === null || value === '' ? '0' : String(value);
        const parsed = parseFloat(raw.replace(',', '')) || 0;
        el.textContent = this.formatCurrency(parsed);
        el.style.color = parsed >= 0 ? 'var(--green-400)' : 'var(--red-400)';
    }
}

// Initialize dashboard
document.addEventListener('DOMContentLoaded', () => {
    new TradingDashboard();
});




