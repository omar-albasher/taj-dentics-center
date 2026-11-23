import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/app_error_handler.dart';
import '../../../../core/utils/app_formatters.dart';
import '../../../../core/widgets/app_error_widget.dart';
import '../../data/reports_repository.dart';
import '../../domain/financial_statement_models.dart';

class FinancialStatementsTab extends ConsumerStatefulWidget {
  final String currencyFilter;
  final Future<void> Function(List<List<dynamic>> rows, String filename)
      onExport;

  const FinancialStatementsTab({
    super.key,
    required this.currencyFilter,
    required this.onExport,
  });

  @override
  ConsumerState<FinancialStatementsTab> createState() =>
      _FinancialStatementsTabState();
}

class _FinancialStatementsTabState
    extends ConsumerState<FinancialStatementsTab> {
  final _amountFormat = NumberFormat('#,##0.##');

  String _formatMoney(double amount, String currency) {
    final formatted = _amountFormat.format(amount);
    if (currency == 'USD') return '\$$formatted';
    return '$formatted ل.س';
  }

  void _setPreset(String preset) {
    final now = DateTime.now();
    DateTime from;
    DateTime to = now;

    switch (preset) {
      case 'this_month':
        from = DateTime(now.year, now.month, 1);
        break;
      case 'last_month':
        from = DateTime(now.year, now.month - 1, 1);
        to = DateTime(now.year, now.month, 0); // Last day of previous month
        break;
      case 'this_quarter':
        final currentQuarter = ((now.month - 1) / 3).floor();
        from = DateTime(now.year, currentQuarter * 3 + 1, 1);
        break;
      case 'this_year':
        from = DateTime(now.year, 1, 1);
        break;
      case 'all_time':
        from = DateTime(2000, 1, 1);
        break;
      default:
        from = DateTime(now.year, now.month, 1);
    }

    ref.read(financialStatementPeriodProvider.notifier).setPeriod(
          FinancialStatementPeriod(from: from, to: to),
        );
  }

  Future<void> _pickDateRange(FinancialStatementPeriod current) async {
    final firstDate = DateTime(2000, 1, 1);
    final lastDate = DateTime.now();
    final clampedStart =
        current.from.isBefore(firstDate) ? firstDate : current.from;
    final clampedEnd = current.to.isAfter(lastDate) ? lastDate : current.to;
    final safeStart =
        clampedStart.isAfter(clampedEnd) ? clampedEnd : clampedStart;

    final picked = await showDateRangePicker(
      context: context,
      firstDate: firstDate,
      lastDate: lastDate,
      initialDateRange: DateTimeRange(start: safeStart, end: clampedEnd),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.gold,
              onPrimary: Colors.black,
              surface: AppColors.cardBg,
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: child!,
          ),
        );
      },
    );

    if (picked != null) {
      ref.read(financialStatementPeriodProvider.notifier).setPeriod(
            FinancialStatementPeriod(from: picked.start, to: picked.end),
          );
    }
  }

  Future<void> _exportFinancials(
    ProfitLossStatement pnl,
    CashFlowStatement cf,
    List<ExpenseBreakdownItem> expenses,
    FinancialStatementPeriod period,
  ) async {
    final rows = <List<dynamic>>[];

    // 1. Header
    rows.add(['مركز تاج دنتكس لطب الأسنان - القوائم المالية v3']);
    rows.add(['الفترة:', '${period.fromIso} إلى ${period.toIso}']);
    rows.add([]);

    // 2. P&L
    rows.add(['--- قائمة الدخل (الأساس النقدي) ---']);
    rows.add([
      'القسم',
      'العملة',
      'الإيرادات المقبوضة',
      'الاستردادات',
      'المصاريف',
      'صافي الربح',
      'ملاحظات / بند استرشادي'
    ]);
    for (final line in pnl.lines) {
      rows.add([
        line.isAcademy ? 'الأكاديمية' : 'المخبر (غير مرتبط بالخزينة)',
        line.currency,
        line.income,
        line.refunds,
        line.expenses,
        line.net,
        line.isLab && line.hasMemorandum
            ? 'مستحق غير محصّل من فواتير المخبر: ${line.memorandumUncollected}'
            : '',
      ]);
    }
    rows.add([]);

    // 3. Cash Flow
    rows.add(['--- قائمة التدفق النقدي (من واقع دفتر العهدة C2) ---']);
    rows.add([
      'الحساب',
      'النوع',
      'العملة',
      'الرصيد الافتتاحي',
      'إجمالي الوارد',
      'إجمالي الصادر',
      'الرصيد الختامي',
      'عدد الحركات',
      'التوازن المحاسبي'
    ]);
    for (final acc in cf.accounts) {
      rows.add([
        acc.accountNameAr,
        acc.accountTypeLabel,
        acc.currency,
        acc.openingBalance,
        acc.inflows,
        acc.outflows,
        acc.closingBalance,
        acc.txCount,
        acc.identityHolds ? 'متوازن' : 'غير متوازن',
      ]);
    }
    rows.add([]);

    // 4. Expenses breakdown
    rows.add(['--- تفصيل المصاريف التشغيلية ---']);
    rows.add(['القسم', 'العملة', 'الحساب', 'الفئة', 'المبلغ', 'العدد']);
    for (final exp in expenses) {
      rows.add([
        exp.isAcademy ? 'الأكاديمية' : 'المخبر',
        exp.currency,
        exp.accountNameAr ?? '—',
        exp.categoryLabel,
        exp.amount,
        exp.expenseCount,
      ]);
    }

    final filename = 'financial_statements_${period.fromIso}_${period.toIso}';
    await widget.onExport(rows, filename);
  }

  @override
  Widget build(BuildContext context) {
    final period = ref.watch(financialStatementPeriodProvider);
    final pnlAsync = ref.watch(c4ProfitLossProvider);
    final cfAsync = ref.watch(c4CashFlowProvider);
    final expAsync = ref.watch(c4ExpenseBreakdownProvider);
    final integrityAsync = ref.watch(c4FinancialIntegrityProvider);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Period Bar & Actions
          _buildPeriodToolbar(context, period, pnlAsync, cfAsync, expAsync),
          const SizedBox(height: 16),

          // Financial Integrity Badge
          integrityAsync.when(
            data: _buildIntegrityBanner,
            loading: () => const LinearProgressIndicator(
                color: AppColors.gold, minHeight: 2),
            error: (e, _) => AppErrorWidget(
              message:
                  'تعذر التحقق من التكامل المحاسبي\n${AppErrorHandler.friendlyMessage(e)}',
              onRetry: () => ref.invalidate(c4FinancialIntegrityProvider),
            ),
          ),
          const SizedBox(height: 16),

          // P&L Section
          pnlAsync.when(
            data: (pnl) => _buildProfitLossSection(context, pnl),
            loading: () => const Center(
                child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(color: AppColors.gold))),
            error: (e, _) => AppErrorWidget(
              message:
                  'تعذر تحميل قائمة الدخل\n${AppErrorHandler.friendlyMessage(e)}',
              onRetry: () => ref.invalidate(c4ProfitLossProvider),
            ),
          ),
          const SizedBox(height: 24),

          // Expense Breakdown Section
          expAsync.when(
            data: (expenses) =>
                _buildExpenseBreakdownSection(context, expenses),
            loading: () => const SizedBox.shrink(),
            error: (e, _) => AppErrorWidget(
              message:
                  'تعذر تحميل تفصيل المصاريف\n${AppErrorHandler.friendlyMessage(e)}',
              onRetry: () => ref.invalidate(c4ExpenseBreakdownProvider),
            ),
          ),
          const SizedBox(height: 24),

          // Cash Flow Section
          cfAsync.when(
            data: (cf) => _buildCashFlowSection(context, cf),
            loading: () => const Center(
                child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(color: AppColors.gold))),
            error: (e, _) => AppErrorWidget(
              message:
                  'تعذر تحميل قائمة التدفق النقدي\n${AppErrorHandler.friendlyMessage(e)}',
              onRetry: () => ref.invalidate(c4CashFlowProvider),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildPeriodToolbar(
    BuildContext context,
    FinancialStatementPeriod period,
    AsyncValue<ProfitLossStatement> pnlAsync,
    AsyncValue<CashFlowStatement> cfAsync,
    AsyncValue<List<ExpenseBreakdownItem>> expAsync,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // Range Picker Button
          OutlinedButton.icon(
            onPressed: () => _pickDateRange(period),
            icon: const Icon(Icons.date_range, color: AppColors.gold, size: 18),
            label: Text(
              '${AppFormatters.dateOnly.format(period.from)} — ${AppFormatters.dateOnly.format(period.to)}',
              style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              side: const BorderSide(color: AppColors.gold, width: 1.2),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),

          // Quick Presets
          _PresetChip(
              label: 'الشهر الحالي', onTap: () => _setPreset('this_month')),
          _PresetChip(
              label: 'الشهر الماضي', onTap: () => _setPreset('last_month')),
          _PresetChip(
              label: 'هذا الربع', onTap: () => _setPreset('this_quarter')),
          _PresetChip(label: 'هذا العام', onTap: () => _setPreset('this_year')),
          _PresetChip(label: 'كل المدة', onTap: () => _setPreset('all_time')),

          // Refresh button
          IconButton(
            tooltip: 'تحديث القوائم المالية',
            icon: const Icon(Icons.refresh, color: AppColors.textSecondary),
            onPressed: () {
              ref.invalidate(c4ProfitLossProvider);
              ref.invalidate(c4CashFlowProvider);
              ref.invalidate(c4ExpenseBreakdownProvider);
              ref.invalidate(c4FinancialIntegrityProvider);
            },
          ),

          // Export button
          ElevatedButton.icon(
            onPressed: (pnlAsync.hasValue &&
                    cfAsync.hasValue &&
                    expAsync.hasValue)
                ? () => _exportFinancials(
                    pnlAsync.value!, cfAsync.value!, expAsync.value!, period)
                : null,
            icon: const Icon(Icons.download, size: 18),
            label: const Text('تصدير القوائم (CSV)',
                style: TextStyle(fontFamily: 'Cairo', fontSize: 12)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.gold,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIntegrityBanner(FinancialIntegrityReport report) {
    if (report.isBalanced) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.success.withAlpha(20),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.success.withAlpha(80)),
        ),
        child: const Row(
          children: [
            Icon(Icons.verified, color: AppColors.success, size: 18),
            SizedBox(width: 8),
            Text(
              'سلامة التكامل المحاسبي مؤكدة 100%: حركات الدفعات والمصاريف مطابقة تماماً لقيود دفتر العهدة (All-time Balanced).',
              style: TextStyle(
                  fontFamily: 'Cairo', fontSize: 12, color: AppColors.success),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.error.withAlpha(25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: AppColors.error, size: 22),
              const SizedBox(width: 8),
              Text(
                'تنبيه: اكتشاف عدم توازن بين سجلات الأحداث ودفتر العهدة (${report.unbalanced.length} فروقات)',
                style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: AppColors.error),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...report.unbalanced.map((line) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '• حركة [${line.sourceType}] بعملة ${line.currency}: إجمالي الأحداث = ${line.eventsTotal} | إجمالي الدفتر = ${line.ledgerTotal} | الفرق = ${line.diff}',
                  style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      color: AppColors.textPrimary),
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildProfitLossSection(
      BuildContext context, ProfitLossStatement pnl) {
    final filteredCurrencies = widget.currencyFilter == 'الكل'
        ? pnl.currencies
        : pnl.currencies.where((c) => c == widget.currencyFilter).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.analytics_outlined,
                color: AppColors.gold, size: 22),
            const SizedBox(width: 8),
            const Text(
              'قائمة الدخل والأرباح والخسائر (الأساس النقدي Cash Basis)',
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.gold.withAlpha(25),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'توقيت الأعمال: آسيا/دمشق',
                style: TextStyle(
                    fontFamily: 'Cairo', fontSize: 11, color: AppColors.gold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // KPI Summary Cards
        _buildPnlKpis(pnl, filteredCurrencies),
        const SizedBox(height: 16),

        // Table
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.cardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.divider),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor:
                  WidgetStateProperty.all(AppColors.background.withAlpha(120)),
              dataRowMinHeight: 52,
              dataRowMaxHeight: 56,
              columns: const [
                DataColumn(
                    label: Text('القسم التشغيلي',
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            color: AppColors.gold))),
                DataColumn(
                    label: Text('العملة',
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            color: AppColors.gold))),
                DataColumn(
                    label: Text('الإيرادات المقبوضة',
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            color: AppColors.gold))),
                DataColumn(
                    label: Text('الاستردادات (-)',
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            color: AppColors.gold))),
                DataColumn(
                    label: Text('المصاريف التشغيلية (-)',
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            color: AppColors.gold))),
                DataColumn(
                    label: Text('صافي الربح النقدي',
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            color: AppColors.gold))),
                DataColumn(
                    label: Text('ملاحظات / بنود استرشادية',
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            color: AppColors.gold))),
              ],
              rows: [
                // Academy Rows
                ...pnl.academy
                    .where((l) =>
                        widget.currencyFilter == 'الكل' ||
                        l.currency == widget.currencyFilter)
                    .map((line) => _buildPnlRow(line, isLab: false)),

                // Lab Rows
                ...pnl.lab
                    .where((l) =>
                        widget.currencyFilter == 'الكل' ||
                        l.currency == widget.currencyFilter)
                    .map((line) => _buildPnlRow(line, isLab: true)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPnlKpis(ProfitLossStatement pnl, List<String> currencies) {
    return Wrap(
      spacing: 16,
      runSpacing: 12,
      children: currencies.map((curr) {
        final acad = pnl.lineFor('academy', curr);
        final lab = pnl.lineFor('lab', curr);
        final acadNet = acad?.net ?? 0.0;
        final labNet = lab?.net ?? 0.0;
        final memo = pnl.memorandumFor(curr);
        final isUsd = curr == 'USD';

        return Container(
          width: 320,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.cardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isUsd
                  ? Colors.lightBlueAccent.withAlpha(60)
                  : AppColors.gold.withAlpha(60),
              width: 1.2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      'صافي أرباح الأكاديمية ($curr)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 13,
                          color: AppColors.textSecondary),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isUsd
                          ? Colors.blue.withAlpha(30)
                          : AppColors.gold.withAlpha(30),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      curr,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isUsd ? Colors.lightBlueAccent : AppColors.gold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _formatMoney(acadNet, curr),
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: acadNet >= 0 ? AppColors.success : AppColors.error,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'المخبر (قسم منفصل): ${_formatMoney(labNet, curr)}',
                style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    color: AppColors.textSecondary),
              ),
              if (memo > 0) ...[
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.amber.withAlpha(20),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'بند استرشادي: مستحق غير محصّل من المخبر: ${_formatMoney(memo, curr)}',
                    style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 10,
                        color: Colors.amberAccent),
                  ),
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }

  DataRow _buildPnlRow(ProfitLossLine line, {required bool isLab}) {
    return DataRow(
      cells: [
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isLab ? 'المخبر الطبي' : 'الأكاديمية التدريبية',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: isLab ? Colors.lightBlueAccent : AppColors.textPrimary,
                ),
              ),
              if (isLab) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.blueGrey.withAlpha(50),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('غير مرتبط بالخزينة',
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 9,
                          color: Colors.white70)),
                ),
              ],
            ],
          ),
        ),
        DataCell(Text(line.currency,
            style: const TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
                fontSize: 12))),
        DataCell(Text(_formatMoney(line.income, line.currency),
            style: const TextStyle(
                fontFamily: 'Cairo', color: AppColors.success, fontSize: 12))),
        DataCell(Text(_formatMoney(line.refunds, line.currency),
            style: const TextStyle(
                fontFamily: 'Cairo', color: AppColors.error, fontSize: 12))),
        DataCell(Text(_formatMoney(line.expenses, line.currency),
            style: const TextStyle(
                fontFamily: 'Cairo', color: AppColors.error, fontSize: 12))),
        DataCell(
          Text(
            _formatMoney(line.net, line.currency),
            style: TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: line.net >= 0 ? AppColors.success : AppColors.error,
            ),
          ),
        ),
        DataCell(
          isLab && line.hasMemorandum
              ? Text(
                  'المستحق غير المحصّل من الفواتير: ${_formatMoney(line.memorandumUncollected, line.currency)}',
                  style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11,
                      color: Colors.amberAccent),
                )
              : const Text('—',
                  style: TextStyle(color: AppColors.textSecondary)),
        ),
      ],
    );
  }

  Widget _buildExpenseBreakdownSection(
      BuildContext context, List<ExpenseBreakdownItem> expenses) {
    final filtered = widget.currencyFilter == 'الكل'
        ? expenses
        : expenses.where((e) => e.currency == widget.currencyFilter).toList();

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: false,
        backgroundColor: AppColors.cardBg,
        collapsedBackgroundColor: AppColors.cardBg,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: AppColors.divider)),
        collapsedShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: AppColors.divider)),
        leading: const Icon(Icons.pie_chart_outline, color: AppColors.gold),
        title: const Text(
          'تفصيل بنود المصاريف التشغيلية (Expenses Breakdown)',
          style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary),
        ),
        subtitle: Text(
          'عرض تصنيف المصاريف وحسابات الدفع (${filtered.length} تصنيف)',
          style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 11,
              color: AppColors.textSecondary),
        ),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(
                      label: Text('القسم',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                              color: AppColors.gold))),
                  DataColumn(
                      label: Text('العملة',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                              color: AppColors.gold))),
                  DataColumn(
                      label: Text('فئة المصروف',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                              color: AppColors.gold))),
                  DataColumn(
                      label: Text('حساب الصرف (الخزينة)',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                              color: AppColors.gold))),
                  DataColumn(
                      label: Text('عدد الحركات',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                              color: AppColors.gold))),
                  DataColumn(
                      label: Text('إجمالي المبلغ',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                              color: AppColors.gold))),
                ],
                rows: filtered.map((e) {
                  return DataRow(
                    cells: [
                      DataCell(Text(e.isAcademy ? 'الأكاديمية' : 'المخبر',
                          style: const TextStyle(
                              fontFamily: 'Cairo', fontSize: 12))),
                      DataCell(Text(e.currency,
                          style: const TextStyle(
                              fontFamily: 'Cairo', fontSize: 12))),
                      DataCell(
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.gold.withAlpha(20),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(e.categoryLabel,
                              style: const TextStyle(
                                  fontFamily: 'Cairo', fontSize: 11)),
                        ),
                      ),
                      DataCell(Text(e.accountNameAr ?? '—',
                          style: const TextStyle(
                              fontFamily: 'Cairo', fontSize: 12))),
                      DataCell(Text('${e.expenseCount}',
                          style: const TextStyle(
                              fontFamily: 'Cairo', fontSize: 12))),
                      DataCell(Text(_formatMoney(e.amount, e.currency),
                          style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: AppColors.error))),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCashFlowSection(BuildContext context, CashFlowStatement cf) {
    final filteredAccounts = widget.currencyFilter == 'الكل'
        ? cf.accounts
        : cf.accounts
            .where((a) => a.currency == widget.currencyFilter)
            .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.account_balance_outlined,
                color: AppColors.gold, size: 22),
            const SizedBox(width: 8),
            const Text(
              'قائمة التدفق النقدي من واقع دفتر العهدة (Custody Cash Flow)',
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.success.withAlpha(25),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('مشتقة من دفتر C2',
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 10,
                      color: AppColors.success)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.cardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.divider),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor:
                  WidgetStateProperty.all(AppColors.background.withAlpha(120)),
              dataRowMinHeight: 52,
              dataRowMaxHeight: 56,
              columns: const [
                DataColumn(
                    label: Text('الحساب والخزينة',
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            color: AppColors.gold))),
                DataColumn(
                    label: Text('النوع والعملة',
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            color: AppColors.gold))),
                DataColumn(
                    label: Text('الرصيد الافتتاحي',
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            color: AppColors.gold))),
                DataColumn(
                    label: Text('إجمالي الوارد (+)',
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            color: AppColors.gold))),
                DataColumn(
                    label: Text('إجمالي الصادر (-)',
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            color: AppColors.gold))),
                DataColumn(
                    label: Text('الرصيد الختامي',
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            color: AppColors.gold))),
                DataColumn(
                    label: Text('الحركات',
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            color: AppColors.gold))),
                DataColumn(
                    label: Text('التوازن',
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            color: AppColors.gold))),
              ],
              rows: filteredAccounts.map((acc) {
                return DataRow(
                  cells: [
                    DataCell(
                      Text(
                        acc.accountNameAr,
                        style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            fontSize: 12),
                      ),
                    ),
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(acc.accountTypeLabel,
                              style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 11,
                                  color: AppColors.textSecondary)),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: acc.currency == 'USD'
                                  ? Colors.blue.withAlpha(25)
                                  : AppColors.gold.withAlpha(25),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              acc.currency,
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 10,
                                color: acc.currency == 'USD'
                                    ? Colors.lightBlueAccent
                                    : AppColors.gold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    DataCell(Text(
                        _formatMoney(acc.openingBalance, acc.currency),
                        style: const TextStyle(
                            fontFamily: 'Cairo', fontSize: 12))),
                    DataCell(Text(_formatMoney(acc.inflows, acc.currency),
                        style: const TextStyle(
                            fontFamily: 'Cairo',
                            color: AppColors.success,
                            fontSize: 12))),
                    DataCell(Text(_formatMoney(acc.outflows, acc.currency),
                        style: const TextStyle(
                            fontFamily: 'Cairo',
                            color: AppColors.error,
                            fontSize: 12))),
                    DataCell(
                      Text(
                        _formatMoney(acc.closingBalance, acc.currency),
                        style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: AppColors.textPrimary),
                      ),
                    ),
                    DataCell(Text('${acc.txCount}',
                        style: const TextStyle(
                            fontFamily: 'Cairo', fontSize: 12))),
                    DataCell(
                      acc.identityHolds
                          ? const Icon(Icons.check_circle_outline,
                              color: AppColors.success, size: 18)
                          : const Icon(Icons.error_outline,
                              color: AppColors.error, size: 18),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }
}

class _PresetChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _PresetChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label,
          style: const TextStyle(fontFamily: 'Cairo', fontSize: 11)),
      onPressed: onTap,
      backgroundColor: AppColors.background,
      side: const BorderSide(color: AppColors.divider),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }
}
