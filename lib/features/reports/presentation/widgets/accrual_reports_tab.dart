import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/app_error_handler.dart';
import '../../../../core/widgets/app_error_widget.dart';
import '../../data/reports_repository.dart';
import '../../domain/accrual_models.dart';
import '../../domain/financial_statement_models.dart';

class _CurrencyTotals {
  double earned = 0;
  double unearned = 0;
  double accrued = 0;
  double netPaid = 0;

  void add(AccrualRevenueReportRow r) {
    earned += r.earnedRevenue;
    unearned += r.unearnedRevenue;
    accrued += r.accruedReceivables;
    netPaid += r.netPaid;
  }
}

class AccrualReportsTab extends ConsumerStatefulWidget {
  final String currencyFilter;
  final Future<void> Function(List<List<dynamic>> rows, String filename)
      onExport;

  const AccrualReportsTab({
    super.key,
    required this.currencyFilter,
    required this.onExport,
  });

  @override
  ConsumerState<AccrualReportsTab> createState() => _AccrualReportsTabState();
}

class _AccrualReportsTabState extends ConsumerState<AccrualReportsTab> {
  final _amountFormat = NumberFormat('#,##0.##');
  int _selectedSubView = 0; // 0: As-Of Report, 1: Reconciliation Bridge

  String _formatMoney(double amount, String currency) {
    final formatted = _amountFormat.format(amount);
    final c = currency.toUpperCase();
    if (c == 'USD') return '\$$formatted';
    if (c == 'SYP') return '$formatted ل.س';
    return '$formatted $c';
  }

  Future<void> _pickAsOfDate(DateTime current) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 365)),
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
      ref.read(accrualAsOfDateProvider.notifier).setDate(picked);
    }
  }

  Future<void> _pickReconciliationPeriod(FinancialStatementPeriod current) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: current.from, end: current.to),
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
      ref.read(accrualReconciliationPeriodProvider.notifier).setPeriod(
            FinancialStatementPeriod(from: picked.start, to: picked.end),
          );
    }
  }

  Future<void> _showCompleteCohortDialog(BuildContext context) async {
    final reportAsync = ref.read(accrualRevenueReportProvider);
    final cohorts = <String, String>{};
    reportAsync.whenData((rows) {
      for (final r in rows) {
        if (r.cohortId.isNotEmpty) {
          cohorts[r.cohortId] =
              r.cohortName.isNotEmpty ? r.cohortName : r.cohortId;
        }
      }
    });

    String? selectedCohortId = cohorts.isNotEmpty ? cohorts.keys.first : null;
    final cohortIdController =
        TextEditingController(text: selectedCohortId ?? '');
    bool force = false;
    bool isSubmitting = false;
    String? errorMessage;

    try {
      await showDialog<void>(
        context: context,
        builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.cardBg,
              title: const Row(
                children: [
                  Icon(Icons.lock_clock_rounded, color: Colors.orangeAccent),
                  SizedBox(width: 8),
                  Text(
                    'إقفال فوج دراسي (Complete Cohort)',
                    style: TextStyle(color: AppColors.gold, fontSize: 18),
                  ),
                ],
              ),
              content: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'سيتم نقل جميع التسجيلات النشطة في الفوج إلى مكتملة (completed) وتحديد تاريخ الإنجاز الفعلي (completed_at) وتجميد الفوج.',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    if (cohorts.isNotEmpty) ...[
                      const Text(
                        'اختر الفوج:',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue: selectedCohortId,
                        dropdownColor: AppColors.cardBg,
                        style: const TextStyle(color: AppColors.textPrimary),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: AppColors.background,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        items: cohorts.entries.map((e) {
                          return DropdownMenuItem(
                              value: e.key, child: Text(e.value));
                        }).toList(),
                        onChanged: (val) {
                          setDialogState(() {
                            selectedCohortId = val;
                            cohortIdController.text = val ?? '';
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: cohortIdController,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        labelText: 'معرف الفوج (Cohort UUID)',
                        labelStyle:
                            const TextStyle(color: AppColors.textSecondary),
                        filled: true,
                        fillColor: AppColors.background,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      onChanged: (val) => selectedCohortId = val.trim(),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: force
                                ? Colors.orangeAccent
                                : AppColors.divider),
                      ),
                      child: Row(
                        children: [
                          Checkbox(
                            value: force,
                            activeColor: Colors.orangeAccent,
                            onChanged: (val) {
                              setDialogState(() => force = val ?? false);
                            },
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'تجاوز إداري (p_force)',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  force
                                      ? 'تنبيه: سيتم إقفال الفوج حتى مع وجود جلسات مجدولة أو جارية لم تُغلق بعد!'
                                      : 'ملاحظة: بدون تجاوز، سيرفض النظام الإقفال إذا وُجدت جلسات غير مغلقة.',
                                  style: TextStyle(
                                    color: force
                                        ? Colors.orangeAccent
                                        : AppColors.textSecondary,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        errorMessage!,
                        style: const TextStyle(
                            color: Colors.redAccent, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      isSubmitting ? null : () => Navigator.pop(dialogCtx),
                  child: const Text('إلغاء',
                      style: TextStyle(color: AppColors.textSecondary)),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final targetId = cohortIdController.text.trim();
                          if (targetId.isEmpty) {
                            setDialogState(() =>
                                errorMessage = 'يرجى إدخال أو اختيار معرف الفوج');
                            return;
                          }
                          setDialogState(() {
                            isSubmitting = true;
                            errorMessage = null;
                          });

                          try {
                            final res = await ref
                                .read(reportsRepositoryProvider)
                                .completeCohort(targetId, force: force);
                            if (context.mounted) {
                              final messenger = ScaffoldMessenger.of(context);
                              Navigator.pop(dialogCtx);
                              messenger.showSnackBar(
                                SnackBar(
                                  backgroundColor: Colors.green,
                                  content: Text(
                                    '${res.message} (أُغلق ${res.closedEnrollments} تسجيل)',
                                  ),
                                ),
                              );
                              ref.invalidate(accrualRevenueReportProvider);
                              ref.invalidate(accrualReconciliationProvider);
                            }
                          } catch (e) {
                            setDialogState(() {
                              isSubmitting = false;
                              errorMessage = AppErrorHandler.friendlyMessage(e);
                            });
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orangeAccent,
                    foregroundColor: Colors.black,
                  ),
                  child: isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black),
                        )
                      : const Text('تأكيد الإقفال',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
    } finally {
      cohortIdController.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Sub-navigation & Actions bar with responsive wrap
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(
                    value: 0,
                    label: Text('تقرير الاستحقاق التراكمي (As-Of)'),
                    icon: Icon(Icons.account_balance_wallet_outlined),
                  ),
                  ButtonSegment(
                    value: 1,
                    label: Text('جسر تسوية الإيرادات (Reconciliation)'),
                    icon: Icon(Icons.compare_arrows_rounded),
                  ),
                ],
                selected: {_selectedSubView},
                onSelectionChanged: (set) {
                  setState(() => _selectedSubView = set.first);
                },
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return AppColors.gold.withValues(alpha: 0.2);
                    }
                    return AppColors.cardBg;
                  }),
                  foregroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return AppColors.gold;
                    }
                    return AppColors.textSecondary;
                  }),
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _showCompleteCohortDialog(context),
                    icon: const Icon(Icons.lock_clock_rounded,
                        size: 16, color: Colors.orangeAccent),
                    label: const Text(
                      'إقفال فوج إدارياً',
                      style: TextStyle(color: Colors.orangeAccent),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.orangeAccent),
                      backgroundColor: AppColors.cardBg,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                  ),
                  if (_selectedSubView == 0) _buildAsOfDatePicker(),
                  if (_selectedSubView == 1) _buildReconciliationDatePicker(),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_selectedSubView == 0) _buildAsOfReportSection(),
          if (_selectedSubView == 1) _buildReconciliationSection(),
        ],
      ),
    );
  }

  Widget _buildAsOfDatePicker() {
    final asOf = ref.watch(accrualAsOfDateProvider);
    final dateStr = DateFormat('yyyy/MM/dd').format(asOf);

    return OutlinedButton.icon(
      onPressed: () => _pickAsOfDate(asOf),
      icon: const Icon(Icons.calendar_today_rounded,
          size: 16, color: AppColors.gold),
      label: Text('حتى تاريخ: $dateStr',
          style: const TextStyle(color: AppColors.textPrimary)),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: AppColors.divider),
        backgroundColor: AppColors.cardBg,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  Widget _buildReconciliationDatePicker() {
    final period = ref.watch(accrualReconciliationPeriodProvider);
    final fromStr = DateFormat('yyyy/MM/dd').format(period.from);
    final toStr = DateFormat('yyyy/MM/dd').format(period.to);

    return OutlinedButton.icon(
      onPressed: () => _pickReconciliationPeriod(period),
      icon:
          const Icon(Icons.date_range_rounded, size: 16, color: AppColors.gold),
      label: Text('$fromStr - $toStr',
          style: const TextStyle(color: AppColors.textPrimary)),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: AppColors.divider),
        backgroundColor: AppColors.cardBg,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  Widget _buildAsOfReportSection() {
    final reportAsync = ref.watch(accrualRevenueReportProvider);

    return reportAsync.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(48.0),
          child: CircularProgressIndicator(color: AppColors.gold),
        ),
      ),
      error: (e, s) => AppErrorWidget(
        message: AppErrorHandler.friendlyMessage(e),
        onRetry: () => ref.refresh(accrualRevenueReportProvider),
      ),
      data: (rows) {
        final filteredRows = widget.currencyFilter == 'الكل'
            ? rows
            : rows.where((r) => r.currency == widget.currencyFilter).toList();

        if (filteredRows.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: AppColors.cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.divider),
            ),
            child: const Center(
              child: Text(
                'لا توجد بيانات استحقاق مسجلة حتى هذا التاريخ',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
              ),
            ),
          );
        }

        // Aggregate Totals strictly partitioned by currency
        final totalsByCurrency = <String, _CurrencyTotals>{};
        for (final r in filteredRows) {
          totalsByCurrency.putIfAbsent(r.currency, _CurrencyTotals.new).add(r);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // KPI Summary Row(s) - strictly rendered per currency, NEVER mixed!
            ...totalsByCurrency.entries.map((entry) {
              final curr = entry.key;
              final t = entry.value;
              final currencyLabel = curr == 'USD'
                  ? 'الدولار الأمريكي (USD)'
                  : curr == 'SYP'
                      ? 'الليرة السورية (SYP)'
                      : curr;

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.cardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.gold.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color: AppColors.gold.withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            currencyLabel,
                            style: const TextStyle(
                              color: AppColors.gold,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _buildMetricCard(
                            title: 'الإيراد المكتسب (Earned)',
                            amount: t.earned,
                            currency: curr,
                            icon: Icons.check_circle_outline_rounded,
                            color: Colors.greenAccent,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildMetricCard(
                            title: 'الإيراد المؤجل (Unearned)',
                            amount: t.unearned,
                            currency: curr,
                            icon: Icons.hourglass_bottom_rounded,
                            color: Colors.amberAccent,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildMetricCard(
                            title: 'مستحقات غير محصلة (Accrued)',
                            amount: t.accrued,
                            currency: curr,
                            icon: Icons.warning_amber_rounded,
                            color: Colors.orangeAccent,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildMetricCard(
                            title: 'صافي المحصل نقداً (Net Paid)',
                            amount: t.netPaid,
                            currency: curr,
                            icon: Icons.payments_outlined,
                            color: AppColors.gold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 12),
            // Data Table Card
            Container(
              decoration: BoxDecoration(
                color: AppColors.cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.divider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Text(
                          'تفاصيل استحقاق التسجيلات (${filteredRows.length})',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const Spacer(),
                        ElevatedButton.icon(
                          onPressed: () => _exportAsOfCsv(filteredRows),
                          icon: const Icon(Icons.download_rounded, size: 16),
                          label: const Text('تصدير CSV'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                AppColors.gold.withValues(alpha: 0.15),
                            foregroundColor: AppColors.gold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: AppColors.divider),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      headingTextStyle: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.gold,
                        fontFamily: 'Cairo',
                      ),
                      columns: const [
                        DataColumn(label: Text('المتدرب')),
                        DataColumn(label: Text('الفوج / الدورة')),
                        DataColumn(label: Text('الحالة')),
                        DataColumn(label: Text('الجلسات (منجزة/خطة)')),
                        DataColumn(label: Text('نسبة الإنجاز')),
                        DataColumn(label: Text('صافي المستحق')),
                        DataColumn(label: Text('المحصل نقداً')),
                        DataColumn(label: Text('الإيراد المكتسب')),
                        DataColumn(label: Text('الإيراد المؤجل')),
                        DataColumn(label: Text('مستحق غير محصل')),
                      ],
                      rows: filteredRows.map((r) {
                        return DataRow(
                          cells: [
                            DataCell(Text(r.traineeName)),
                            DataCell(Text('${r.cohortName} - ${r.courseName}')),
                            DataCell(_buildStatusBadge(r.lifecycleStatus)),
                            DataCell(Text(
                                '${r.deliveredSinceEnrolled} / ${r.plannedRemaining}')),
                            DataCell(Text(
                                '${(r.completionRatio * 100).toStringAsFixed(1)}%')),
                            DataCell(Text(_formatMoney(r.netDue, r.currency))),
                            DataCell(Text(_formatMoney(r.netPaid, r.currency))),
                            DataCell(Text(
                              _formatMoney(r.earnedRevenue, r.currency),
                              style: const TextStyle(
                                  color: Colors.greenAccent,
                                  fontWeight: FontWeight.bold),
                            )),
                            DataCell(Text(
                              _formatMoney(r.unearnedRevenue, r.currency),
                              style:
                                  const TextStyle(color: Colors.amberAccent),
                            )),
                            DataCell(Text(
                              _formatMoney(r.accruedReceivables, r.currency),
                              style:
                                  const TextStyle(color: Colors.orangeAccent),
                            )),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildReconciliationSection() {
    final reconAsync = ref.watch(accrualReconciliationProvider);

    return reconAsync.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(48.0),
          child: CircularProgressIndicator(color: AppColors.gold),
        ),
      ),
      error: (e, s) => AppErrorWidget(
        message: AppErrorHandler.friendlyMessage(e),
        onRetry: () => ref.refresh(accrualReconciliationProvider),
      ),
      data: (rows) {
        final filteredRows = widget.currencyFilter == 'الكل'
            ? rows
            : rows.where((r) => r.currency == widget.currencyFilter).toList();

        if (filteredRows.isEmpty) {
          return const Center(child: Text('لا توجد بيانات تسوية للفترة'));
        }

        return Column(
          children: filteredRows.map((row) {
            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: row.isReconciled
                      ? Colors.green.withValues(alpha: 0.4)
                      : Colors.red.withValues(alpha: 0.4),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text(
                        'تسوية العملة: ${row.currency}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.gold,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: row.isReconciled
                              ? Colors.green.withValues(alpha: 0.15)
                              : Colors.red.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: row.isReconciled ? Colors.green : Colors.red,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              row.isReconciled
                                  ? Icons.check_circle
                                  : Icons.error_outline,
                              size: 16,
                              color:
                                  row.isReconciled ? Colors.green : Colors.red,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              row.isReconciled
                                  ? 'المعادلة متطابقة ومتوازنة'
                                  : 'يوجد فارق تسوية',
                              style: TextStyle(
                                color: row.isReconciled
                                    ? Colors.green
                                    : Colors.red,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24, color: AppColors.divider),
                  Row(
                    children: [
                      Expanded(
                        child: _buildReconBox(
                          'الرصيد الافتتاحي المؤجل',
                          _formatMoney(row.openingUnearned, row.currency),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildReconBox(
                          'التغير في المؤجل (Δ Unearned)',
                          _formatMoney(row.deltaUnearned, row.currency),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildReconBox(
                          'الرصيد الختامي المؤجل',
                          _formatMoney(row.closingUnearned, row.currency),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildReconBox(
                          'إيراد الفترة المكتسب',
                          _formatMoney(row.periodEarnedRevenue, row.currency),
                          color: Colors.greenAccent,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildReconBox(
                          'مقبوضات نقدية للفترة',
                          _formatMoney(row.periodCashPayments, row.currency),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildReconBox(
                          'استردادات نقدية للفترة',
                          _formatMoney(row.periodCashRefunds, row.currency),
                          color: Colors.orangeAccent,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildReconBox(
                          'صافي التدفق النقدي للفترة',
                          _formatMoney(row.periodCashNet, row.currency),
                          color: AppColors.gold,
                        ),
                      ),
                    ],
                  ),
                  if (!row.isReconciled) ...[
                    const SizedBox(height: 12),
                    Text(
                      'فارق التسوية غير المتوازن: ${_formatMoney(row.reconciliationDiff, row.currency)}',
                      style: const TextStyle(
                          color: Colors.red, fontWeight: FontWeight.bold),
                    ),
                  ],
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildMetricCard({
    required String title,
    required double amount,
    required String currency,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _formatMoney(amount, currency),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReconBox(String label, String value, {Color? color}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
                fontSize: 11, color: AppColors.textSecondary),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color ?? AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color;
    String label;

    switch (status) {
      case 'active':
        color = Colors.blue;
        label = 'نشط';
        break;
      case 'completed':
        color = Colors.green;
        label = 'مكتمل';
        break;
      case 'withdrawn':
        color = Colors.orange;
        label = 'منسحب';
        break;
      default:
        color = Colors.grey;
        label = status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style:
            TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }

  Future<void> _exportAsOfCsv(List<AccrualRevenueReportRow> rows) async {
    final csvRows = <List<dynamic>>[
      [
        'المتدرب',
        'الفوج',
        'الدورة',
        'الحالة',
        'العملة',
        'تاريخ التسجيل',
        'صافي المستحق',
        'المحصل نقداً',
        'الجلسات السابقة',
        'المتبقي المخطط',
        'المنجز منذ التسجيل',
        'نسبة الإنجاز',
        'الإيراد المكتسب',
        'الإيراد المؤجل',
        'المستحق غير المحصل',
      ],
      ...rows.map((r) => [
            r.traineeName,
            r.cohortName,
            r.courseName,
            r.lifecycleStatus,
            r.currency,
            DateFormat('yyyy-MM-dd').format(r.enrolledAt),
            r.netDue,
            r.netPaid,
            r.sessionsPrior,
            r.plannedRemaining,
            r.deliveredSinceEnrolled,
            '${(r.completionRatio * 100).toStringAsFixed(2)}%',
            r.earnedRevenue,
            r.unearnedRevenue,
            r.accruedReceivables,
          ]),
    ];

    final dateStr =
        DateFormat('yyyyMMdd').format(ref.read(accrualAsOfDateProvider));
    await widget.onExport(csvRows, 'accrual_revenue_report_$dateStr');
  }
}
