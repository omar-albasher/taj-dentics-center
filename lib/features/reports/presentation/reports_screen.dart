import 'dart:convert';
import 'dart:typed_data';
import 'package:admin_dashboard/core/constants/app_colors.dart';
import 'package:admin_dashboard/core/utils/app_error_handler.dart';
import 'package:admin_dashboard/core/utils/app_formatters.dart';
import 'package:admin_dashboard/core/utils/responsive.dart';
import 'package:admin_dashboard/core/widgets/app_error_widget.dart';
import 'package:admin_dashboard/core/widgets/keep_alive_wrapper.dart';
import 'package:csv/csv.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/reports_repository.dart';

String _money(num value, String? currency) {
  final formatted = AppFormatters.amount.format(value.round());
  final c = currency?.toUpperCase() ?? 'SYP';
  if (c == 'USD') return '\$$formatted';
  return '$formatted ل.س';
}

String _dualMoney({
  required num syp,
  required num usd,
  required String currencyFilter,
}) {
  if (currencyFilter == 'SYP') return _money(syp, 'SYP');
  if (currencyFilter == 'USD') return _money(usd, 'USD');
  if (syp == 0 && usd == 0) return '0 ل.س';
  if (syp > 0 && usd == 0) return _money(syp, 'SYP');
  if (syp == 0 && usd > 0) return _money(usd, 'USD');
  return '${_money(syp, 'SYP')} | ${_money(usd, 'USD')}';
}

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedCurrency = 'SYP'; // 'SYP', 'USD', 'الكل'

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 7, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _exportCsv(List<List<dynamic>> rows, String filename) async {
    final csv = '\uFEFF${const ListToCsvConverter().convert(rows)}';
    final bytes = utf8.encode(csv);
    await FileSaver.instance.saveFile(
      name: filename,
      bytes: Uint8List.fromList(bytes),
      ext: 'csv',
      mimeType: MimeType.csv,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Padding(
        padding: EdgeInsets.all(Responsive.spacing(context, 24)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with Currency Switcher
            Row(
              children: [
                Text(
                  'التقارير المالية والأكاديمية',
                  style: TextStyle(
                    fontSize: Responsive.fontSize(context, 26),
                    fontWeight: FontWeight.w900,
                    color: AppColors.gold,
                    fontFamily: 'Cairo',
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.cardBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _CurrencyPill(
                        label: 'ليرة سورية (SYP)',
                        value: 'SYP',
                        selected: _selectedCurrency,
                        onTap: (v) => setState(() => _selectedCurrency = v),
                      ),
                      _CurrencyPill(
                        label: 'دولار (USD)',
                        value: 'USD',
                        selected: _selectedCurrency,
                        onTap: (v) => setState(() => _selectedCurrency = v),
                      ),
                      _CurrencyPill(
                        label: 'الكل (مفصول)',
                        value: 'الكل',
                        selected: _selectedCurrency,
                        onTap: (v) => setState(() => _selectedCurrency = v),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: Responsive.spacing(context, 16)),
            TabBar(
              controller: _tabController,
              labelColor: AppColors.gold,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.gold,
              isScrollable: true,
              labelStyle: const TextStyle(
                  fontFamily: 'Cairo', fontWeight: FontWeight.w700),
              tabs: const [
                Tab(text: 'الربح والخسارة'),
                Tab(text: 'المستحقات المتأخرة'),
                Tab(text: 'إيرادات الكورسات'),
                Tab(text: 'السيولة وطرق الدفع'),
                Tab(text: 'أعمار الديون والخصومات'),
                Tab(text: 'توزيع المصاريف'),
                Tab(text: 'الحضور'),
              ],
            ),
            SizedBox(height: Responsive.spacing(context, 16)),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  KeepAliveWrapper(
                    child: _ProfitLossTab(
                      currencyFilter: _selectedCurrency,
                      onExport: _exportCsv,
                    ),
                  ),
                  KeepAliveWrapper(
                    child: _OverdueReportTab(
                      currencyFilter: _selectedCurrency,
                      onExport: _exportCsv,
                    ),
                  ),
                  KeepAliveWrapper(
                    child: _CourseRevenueTab(
                      currencyFilter: _selectedCurrency,
                      onExport: _exportCsv,
                    ),
                  ),
                  KeepAliveWrapper(
                    child: _PaymentMethodsAndCashTab(
                      currencyFilter: _selectedCurrency,
                      onExport: _exportCsv,
                    ),
                  ),
                  KeepAliveWrapper(
                    child: _DebtAgingAndDiscountsTab(
                      currencyFilter: _selectedCurrency,
                      onExport: _exportCsv,
                    ),
                  ),
                  KeepAliveWrapper(
                    child: _ExpensesByCategoryTab(
                      currencyFilter: _selectedCurrency,
                      onExport: _exportCsv,
                    ),
                  ),
                  KeepAliveWrapper(
                    child: _AttendanceReportTab(onExport: _exportCsv),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CurrencyPill extends StatelessWidget {
  final String label;
  final String value;
  final String selected;
  final Function(String) onTap;

  const _CurrencyPill({
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = selected == value;
    return GestureDetector(
      onTap: () => onTap(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.gold.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppColors.gold : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? AppColors.gold : AppColors.textSecondary,
            fontFamily: 'Cairo',
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

// ─── 1. Profit & Loss Tab (v2) ───
class _ProfitLossTab extends ConsumerWidget {
  final String currencyFilter;
  final Function(List<List<dynamic>>, String) onExport;

  const _ProfitLossTab({
    required this.currencyFilter,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportAsync = ref.watch(profitLossProvider);

    return reportAsync.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(color: AppColors.gold)),
      error: (e, _) => AppErrorWidget(
        message: AppErrorHandler.friendlyMessage(e),
        onRetry: () => ref.invalidate(profitLossProvider),
      ),
      data: (allRows) {
        final rows = currencyFilter == 'الكل'
            ? allRows
            : allRows.where((r) => r['currency'] == currencyFilter).toList();

        if (rows.isEmpty) {
          return Center(
            child: Text(
              'لا توجد بيانات لهذه العملة',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontFamily: 'Cairo',
                fontSize: Responsive.fontSize(context, 16),
              ),
            ),
          );
        }

        // Calculate totals separated by currency
        double cashIncomeSyp = 0, refundsSyp = 0, expensesSyp = 0, profitSyp = 0;
        double cashIncomeUsd = 0, refundsUsd = 0, expensesUsd = 0, profitUsd = 0;

        for (final r in rows) {
          final curr = r['currency'] as String? ?? 'SYP';
          final cash = (r['cash_income'] as num?)?.toDouble() ?? 0;
          final refAmt = (r['refunds'] as num?)?.toDouble() ?? 0;
          final exp = (r['expenses'] as num?)?.toDouble() ?? 0;
          final prof = (r['net_profit'] as num?)?.toDouble() ?? 0;

          if (curr == 'USD') {
            cashIncomeUsd += cash;
            refundsUsd += refAmt;
            expensesUsd += exp;
            profitUsd += prof;
          } else {
            cashIncomeSyp += cash;
            refundsSyp += refAmt;
            expensesSyp += exp;
            profitSyp += prof;
          }
        }

        return Column(
          children: [
            // Summary Cards
            Row(
              children: [
                _ReportCard(
                  label: 'المقبوض النقدي (Gross)',
                  value: _dualMoney(
                    syp: cashIncomeSyp,
                    usd: cashIncomeUsd,
                    currencyFilter: currencyFilter,
                  ),
                  color: AppColors.success,
                  icon: Icons.trending_up,
                ),
                SizedBox(width: Responsive.spacing(context, 10)),
                _ReportCard(
                  label: 'الاستردادات',
                  value: _dualMoney(
                    syp: refundsSyp,
                    usd: refundsUsd,
                    currencyFilter: currencyFilter,
                  ),
                  color: AppColors.error,
                  icon: Icons.assignment_return,
                ),
                SizedBox(width: Responsive.spacing(context, 10)),
                _ReportCard(
                  label: 'إجمالي المصاريف',
                  value: _dualMoney(
                    syp: expensesSyp,
                    usd: expensesUsd,
                    currencyFilter: currencyFilter,
                  ),
                  color: AppColors.warning,
                  icon: Icons.trending_down,
                ),
                SizedBox(width: Responsive.spacing(context, 10)),
                _ReportCard(
                  label: 'صافي الربح الحقيقي',
                  value: _dualMoney(
                    syp: profitSyp,
                    usd: profitUsd,
                    currencyFilter: currencyFilter,
                  ),
                  color: (profitSyp + profitUsd >= 0) ? AppColors.gold : AppColors.error,
                  icon: Icons.account_balance,
                ),
              ],
            ),

            SizedBox(height: Responsive.spacing(context, 14)),

            // Export Button
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () {
                  final csvRows = [
                    [
                      'الشهر',
                      'العملة',
                      'المقبوض النقدي',
                      'الاستردادات',
                      'صافي المقبوض',
                      'المصاريف',
                      'صافي الربح',
                    ],
                    ...rows.map((r) => [
                          r['month'] ?? '',
                          r['currency'] ?? '',
                          r['cash_income'] ?? 0,
                          r['refunds'] ?? 0,
                          r['net_income'] ?? 0,
                          r['expenses'] ?? 0,
                          r['net_profit'] ?? 0,
                        ]),
                  ];
                  onExport(csvRows, 'profit_loss_report_v2');
                },
                icon: const Icon(Icons.download, color: AppColors.gold, size: 18),
                label: const Text(
                  'تصدير CSV',
                  style: TextStyle(color: AppColors.gold, fontFamily: 'Cairo', fontSize: 12),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.gold),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),

            SizedBox(height: Responsive.spacing(context, 10)),

            // Data Table
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.cardBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: EdgeInsets.all(Responsive.spacing(context, 14)),
                      decoration: const BoxDecoration(
                        border: Border(bottom: BorderSide(color: AppColors.divider)),
                      ),
                      child: Row(
                        children: [
                          _TableHeader('الشهر', flex: 2),
                          _TableHeader('العملة'),
                          _TableHeader('المقبوض'),
                          _TableHeader('الاسترداد'),
                          _TableHeader('صافي الإيراد'),
                          _TableHeader('المصاريف'),
                          _TableHeader('صافي الربح'),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        itemCount: rows.length,
                        separatorBuilder: (_, __) =>
                            const Divider(color: AppColors.divider, height: 1),
                        itemBuilder: (context, index) {
                          final r = rows[index];
                          final curr = r['currency'] as String? ?? 'SYP';
                          final cash = (r['cash_income'] as num?)?.toDouble() ?? 0;
                          final refAmt = (r['refunds'] as num?)?.toDouble() ?? 0;
                          final netInc = (r['net_income'] as num?)?.toDouble() ?? 0;
                          final exp = (r['expenses'] as num?)?.toDouble() ?? 0;
                          final profit = (r['net_profit'] as num?)?.toDouble() ?? 0;
                          final month = r['month'] != null
                              ? AppFormatters.monthShortAr.format(DateTime.parse(r['month']))
                              : '';

                          return Padding(
                            padding: EdgeInsets.all(Responsive.spacing(context, 14)),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    month,
                                    style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontFamily: 'Cairo',
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    curr,
                                    style: TextStyle(
                                      color: curr == 'USD' ? AppColors.gold : AppColors.textSecondary,
                                      fontFamily: 'Cairo',
                                      fontWeight: FontWeight.w700,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    _money(cash, curr),
                                    style: const TextStyle(
                                      color: AppColors.success,
                                      fontFamily: 'Cairo',
                                      fontWeight: FontWeight.w700,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    _money(refAmt, curr),
                                    style: const TextStyle(
                                      color: AppColors.error,
                                      fontFamily: 'Cairo',
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    _money(netInc, curr),
                                    style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontFamily: 'Cairo',
                                      fontWeight: FontWeight.w700,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    _money(exp, curr),
                                    style: const TextStyle(
                                      color: AppColors.warning,
                                      fontFamily: 'Cairo',
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    _money(profit, curr),
                                    style: TextStyle(
                                      color: profit >= 0 ? AppColors.gold : AppColors.error,
                                      fontFamily: 'Cairo',
                                      fontWeight: FontWeight.w700,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─── 2. Overdue Report Tab ───
class _OverdueReportTab extends ConsumerWidget {
  final String currencyFilter;
  final Function(List<List<dynamic>>, String) onExport;

  const _OverdueReportTab({
    required this.currencyFilter,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportAsync = ref.watch(overdueReportProvider);

    return reportAsync.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(color: AppColors.gold)),
      error: (e, _) => AppErrorWidget(
        message: AppErrorHandler.friendlyMessage(e),
        onRetry: () => ref.invalidate(overdueReportProvider),
      ),
      data: (allRows) {
        final rows = currencyFilter == 'الكل'
            ? allRows
            : allRows.where((r) => r['currency'] == currencyFilter).toList();

        if (rows.isEmpty) {
          return Center(
            child: Text(
              '🎉 لا توجد مستحقات متأخرة لهذه العملة',
              style: TextStyle(
                color: AppColors.success,
                fontFamily: 'Cairo',
                fontSize: Responsive.fontSize(context, 16),
              ),
            ),
          );
        }

        double totalSyp = 0;
        double totalUsd = 0;
        for (final r in rows) {
          final curr = r['currency'] as String? ?? 'SYP';
          final bal = (r['balance_due'] as num?)?.toDouble() ?? 0;
          if (curr == 'USD') {
            totalUsd += bal;
          } else {
            totalSyp += bal;
          }
        }

        return Column(
          children: [
            _ReportCard(
              label: 'إجمالي المستحقات المتأخرة',
              value: _dualMoney(
                syp: totalSyp,
                usd: totalUsd,
                currencyFilter: currencyFilter,
              ),
              color: AppColors.error,
              icon: Icons.warning_amber,
            ),
            SizedBox(height: Responsive.spacing(context, 12)),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () {
                  final csvRows = [
                    ['الاسم', 'الكود', 'الكورس', 'العملة', 'الهاتف', 'المتبقي'],
                    ...rows.map((r) => [
                          r['trainee_name'] ?? '',
                          r['trainee_code'] ?? '',
                          r['course_name'] ?? '',
                          r['currency'] ?? '',
                          r['phone'] ?? '',
                          r['balance_due'] ?? 0,
                        ]),
                  ];
                  onExport(csvRows, 'overdue_payments_report');
                },
                icon: const Icon(Icons.download, color: AppColors.gold, size: 18),
                label: const Text(
                  'تصدير CSV',
                  style: TextStyle(color: AppColors.gold, fontFamily: 'Cairo', fontSize: 12),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.gold),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            SizedBox(height: Responsive.spacing(context, 12)),
            Expanded(
              child: ListView.separated(
                itemCount: rows.length,
                separatorBuilder: (_, __) =>
                    SizedBox(height: Responsive.spacing(context, 8)),
                itemBuilder: (context, index) {
                  final r = rows[index];
                  final balance = (r['balance_due'] as num?)?.toDouble() ?? 0;
                  final curr = r['currency'] as String? ?? 'SYP';

                  return Container(
                    padding: EdgeInsets.all(Responsive.spacing(context, 16)),
                    decoration: BoxDecoration(
                      color: AppColors.cardBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: AppColors.error.withValues(alpha: 0.15),
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(
                              color: AppColors.error,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'Cairo',
                            ),
                          ),
                        ),
                        SizedBox(width: Responsive.spacing(context, 12)),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    r['trainee_name'] ?? '',
                                    style: TextStyle(
                                      fontSize: Responsive.fontSize(context, 15),
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimary,
                                      fontFamily: 'Cairo',
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.surface,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      r['trainee_code'] ?? '',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontFamily: 'Cairo',
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                '${r['course_name'] ?? ''} - هاتف: ${r['phone'] ?? 'غير مسجل'}',
                                style: TextStyle(
                                  fontSize: Responsive.fontSize(context, 12),
                                  color: AppColors.textSecondary,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          _money(balance, curr),
                          style: TextStyle(
                            fontSize: Responsive.fontSize(context, 15),
                            fontWeight: FontWeight.w900,
                            color: AppColors.error,
                            fontFamily: 'Cairo',
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─── 3. Course Revenue Tab (v2) ───
class _CourseRevenueTab extends ConsumerWidget {
  final String currencyFilter;
  final Function(List<List<dynamic>>, String) onExport;

  const _CourseRevenueTab({
    required this.currencyFilter,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportAsync = ref.watch(courseRevenueProvider);

    return reportAsync.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(color: AppColors.gold)),
      error: (e, _) => AppErrorWidget(
        message: AppErrorHandler.friendlyMessage(e),
        onRetry: () => ref.invalidate(courseRevenueProvider),
      ),
      data: (allRows) {
        // v2 view is ALREADY aggregated per (course_name, currency)
        final courses = currencyFilter == 'الكل'
            ? allRows
            : allRows.where((r) => r['currency'] == currencyFilter).toList();

        if (courses.isEmpty) {
          return Center(
            child: Text(
              'لا توجد إيرادات مسجلة لهذه العملة',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontFamily: 'Cairo',
                fontSize: Responsive.fontSize(context, 16),
              ),
            ),
          );
        }

        return Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () {
                  final csvRows = [
                    [
                      'الكورس',
                      'العملة',
                      'الطلاب غير المنسحبين',
                      'المنسحبون',
                      'المتوقع لغير المنسحبين',
                      'المحصّل لغير المنسحبين',
                      'المتبقي لغير المنسحبين',
                      'إجمالي النقد (مع المنسحبين)',
                      'نسبة التحصيل',
                    ],
                    ...courses.map((c) {
                      final due = (c['active_expected_net_due'] as num?)?.toDouble() ?? 0;
                      final paid = (c['active_net_paid'] as num?)?.toDouble() ?? 0;
                      final pct = due > 0 ? (paid / due * 100).toStringAsFixed(1) : '0';
                      return [
                        c['course_name'] ?? c['course_title'] ?? '',
                        c['currency'] ?? '',
                        c['active_enrollments'] ?? 0,
                        c['withdrawn_enrollments'] ?? 0,
                        due,
                        paid,
                        c['active_outstanding'] ?? 0,
                        c['total_paid'] ?? 0,
                        '$pct%',
                      ];
                    }),
                  ];
                  onExport(csvRows, 'course_revenue_v2_report');
                },
                icon: const Icon(Icons.download, color: AppColors.gold, size: 18),
                label: const Text(
                  'تصدير CSV',
                  style: TextStyle(color: AppColors.gold, fontFamily: 'Cairo', fontSize: 12),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.gold),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            SizedBox(height: Responsive.spacing(context, 12)),
            Expanded(
              child: ListView.separated(
                itemCount: courses.length,
                separatorBuilder: (_, __) =>
                    SizedBox(height: Responsive.spacing(context, 8)),
                itemBuilder: (context, index) {
                  final c = courses[index];
                  final curr = c['currency'] as String? ?? 'SYP';
                  final due = (c['active_expected_net_due'] as num?)?.toDouble() ?? 0;
                  final activePaid = (c['active_net_paid'] as num?)?.toDouble() ?? 0;
                  final outstanding = (c['active_outstanding'] as num?)?.toDouble() ?? 0;
                  final totalCash = (c['total_paid'] as num?)?.toDouble() ?? 0;
                  final activeCount = c['active_enrollments'] ?? 0;
                  final withdrawnCount = c['withdrawn_enrollments'] ?? 0;

                  // Auditor rule: Collection % = active_net_paid / active_expected_net_due
                  final pct = due > 0 ? (activePaid / due * 100) : 0.0;

                  return Container(
                    padding: EdgeInsets.all(Responsive.spacing(context, 16)),
                    decoration: BoxDecoration(
                      color: AppColors.cardBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                c['course_name'] ?? c['course_title'] ?? '',
                                style: TextStyle(
                                  fontSize: Responsive.fontSize(context, 16),
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: curr == 'USD'
                                    ? AppColors.gold.withValues(alpha: 0.2)
                                    : AppColors.surface,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: curr == 'USD' ? AppColors.gold : AppColors.divider,
                                ),
                              ),
                              child: Text(
                                curr,
                                style: TextStyle(
                                  color: curr == 'USD' ? AppColors.gold : AppColors.textSecondary,
                                  fontFamily: 'Cairo',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              '$activeCount نشط${withdrawnCount > 0 ? ' ($withdrawnCount منسحب)' : ''}',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontFamily: 'Cairo',
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: Responsive.spacing(context, 10)),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: (pct / 100).clamp(0.0, 1.0),
                            backgroundColor: AppColors.divider,
                            valueColor: AlwaysStoppedAnimation(
                              pct >= 80 ? AppColors.success : AppColors.gold,
                            ),
                            minHeight: 8,
                          ),
                        ),
                        SizedBox(height: Responsive.spacing(context, 10)),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'المحصّل الفعلي النشط: ${_money(activePaid, curr)}',
                              style: const TextStyle(
                                color: AppColors.success,
                                fontFamily: 'Cairo',
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'المتوقع النشط: ${_money(due, curr)}',
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontFamily: 'Cairo',
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              'المتبقي: ${_money(outstanding, curr)}',
                              style: const TextStyle(
                                color: AppColors.warning,
                                fontFamily: 'Cairo',
                                fontSize: 12,
                              ),
                            ),
                            if (totalCash != activePaid)
                              Text(
                                'النقد الشامل: ${_money(totalCash, curr)}',
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontFamily: 'Cairo',
                                  fontSize: 11,
                                ),
                              ),
                            Text(
                              'نسبة التحصيل: ${pct.toStringAsFixed(1)}%',
                              style: TextStyle(
                                color: pct >= 80 ? AppColors.success : AppColors.gold,
                                fontWeight: FontWeight.w700,
                                fontFamily: 'Cairo',
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─── 4. Payment Methods & Cash Tab (v2) ───
class _PaymentMethodsAndCashTab extends ConsumerWidget {
  final String currencyFilter;
  final Function(List<List<dynamic>>, String) onExport;

  const _PaymentMethodsAndCashTab({
    required this.currencyFilter,
    required this.onExport,
  });

  String _getMethodLabel(String? method) {
    switch (method) {
      case 'cash':
        return 'نقداً';
      case 'sham_cash':
        return 'شام كاش';
      case 'hawala':
        return 'حوالة';
      case 'transfer':
      case 'bank_transfer':
        return 'حوالة / تحويل بنكي';
      case 'electronic':
        return 'دفع إلكتروني';
      case 'pos':
        return 'نقطة بيع POS';
      case 'cheque':
        return 'شيك';
      default:
        return method ?? 'أخرى';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cashAsync = ref.watch(cashVsAccrualProvider);
    final methodsAsync = ref.watch(revenueByMethodProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Cash vs Accrual KPIs (v2)
        cashAsync.when(
          loading: () => const SizedBox(
            height: 80,
            child: Center(child: CircularProgressIndicator(color: AppColors.gold)),
          ),
          error: (e, _) => Text(
            'خطأ بمؤشرات السيولة: $e',
            style: const TextStyle(color: AppColors.error, fontFamily: 'Cairo'),
          ),
          data: (allKpis) {
            final kpis = currencyFilter == 'الكل'
                ? allKpis
                : allKpis.where((k) => k['currency'] == currencyFilter).toList();

            double collectedSyp = 0, pendingSyp = 0, expectedSyp = 0;
            double collectedUsd = 0, pendingUsd = 0, expectedUsd = 0;

            for (final k in kpis) {
              final curr = k['currency'] as String? ?? 'SYP';
              final coll = (k['cash_collected'] as num?)?.toDouble() ?? 0;
              final pend = (k['active_outstanding'] as num?)?.toDouble() ?? 0;
              final exp = (k['active_expected_net_due'] as num?)?.toDouble() ?? 0;

              if (curr == 'USD') {
                collectedUsd += coll;
                pendingUsd += pend;
                expectedUsd += exp;
              } else {
                collectedSyp += coll;
                pendingSyp += pend;
                expectedSyp += exp;
              }
            }

            return Row(
              children: [
                _ReportCard(
                  label: 'السيولة المحصّلة فعلياً (Cash)',
                  value: _dualMoney(
                    syp: collectedSyp,
                    usd: collectedUsd,
                    currencyFilter: currencyFilter,
                  ),
                  color: AppColors.success,
                  icon: Icons.account_balance_wallet,
                ),
                SizedBox(width: Responsive.spacing(context, 10)),
                _ReportCard(
                  label: 'المستحقات المتوقعة النشطة (Accrual)',
                  value: _dualMoney(
                    syp: pendingSyp,
                    usd: pendingUsd,
                    currencyFilter: currencyFilter,
                  ),
                  color: AppColors.warning,
                  icon: Icons.hourglass_top,
                ),
                SizedBox(width: Responsive.spacing(context, 10)),
                _ReportCard(
                  label: 'إجمالي العقود النشطة',
                  value: _dualMoney(
                    syp: expectedSyp,
                    usd: expectedUsd,
                    currencyFilter: currencyFilter,
                  ),
                  color: AppColors.gold,
                  icon: Icons.pie_chart_outline,
                ),
              ],
            );
          },
        ),

        SizedBox(height: Responsive.spacing(context, 16)),

        // Revenue by Method Table (v2)
        Expanded(
          child: methodsAsync.when(
            loading: () =>
                const Center(child: CircularProgressIndicator(color: AppColors.gold)),
            error: (e, _) => AppErrorWidget(
              message: AppErrorHandler.friendlyMessage(e),
              onRetry: () => ref.invalidate(revenueByMethodProvider),
            ),
            data: (allRows) {
              final rows = currencyFilter == 'الكل'
                  ? allRows
                  : allRows.where((r) => r['currency'] == currencyFilter).toList();

              if (rows.isEmpty) {
                return Center(
                  child: Text(
                    'لا توجد دفعات مسجلة لهذه العملة',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontFamily: 'Cairo',
                      fontSize: Responsive.fontSize(context, 16),
                    ),
                  ),
                );
              }

              // Auditor rule: Calculate totals WITHIN EACH CURRENCY
              final Map<String, double> netPerCurrency = {};
              for (final r in rows) {
                final curr = r['currency'] as String? ?? 'SYP';
                final net = (r['net_collected'] as num?)?.toDouble() ?? 0;
                netPerCurrency[curr] = (netPerCurrency[curr] ?? 0) + net;
              }

              return Column(
                children: [
                  Row(
                    children: [
                      Text(
                        'توزيع المقبوضات حسب وسيلة الدفع (v2)',
                        style: TextStyle(
                          fontSize: Responsive.fontSize(context, 16),
                          fontWeight: FontWeight.w700,
                          color: AppColors.gold,
                          fontFamily: 'Cairo',
                        ),
                      ),
                      const Spacer(),
                      OutlinedButton.icon(
                        onPressed: () {
                          final csv = [
                            [
                              'طريقة الدفع',
                              'العملة',
                              'عدد الدفعات',
                              'المقبوض الإجمالي',
                              'الاستردادات',
                              'الصافي',
                              'النسبة (ضمن العملة)'
                            ],
                            ...rows.map((r) {
                              final curr = r['currency'] as String? ?? 'SYP';
                              final net = (r['net_collected'] as num?)?.toDouble() ?? 0;
                              final totalCurr = netPerCurrency[curr] ?? 0;
                              final pct = totalCurr > 0
                                  ? (net / totalCurr * 100).toStringAsFixed(1)
                                  : '0';
                              return [
                                _getMethodLabel(r['method']),
                                curr,
                                r['payment_count'] ?? 0,
                                r['gross_collected'] ?? 0,
                                r['refunds'] ?? 0,
                                net,
                                '$pct%',
                              ];
                            }),
                          ];
                          onExport(csv, 'revenue_by_method_v2');
                        },
                        icon: const Icon(Icons.download, color: AppColors.gold, size: 18),
                        label: const Text(
                          'تصدير CSV',
                          style: TextStyle(color: AppColors.gold, fontFamily: 'Cairo', fontSize: 12),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.gold),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: Responsive.spacing(context, 12)),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.cardBg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: Column(
                        children: [
                          Container(
                            padding: EdgeInsets.all(Responsive.spacing(context, 14)),
                            decoration: const BoxDecoration(
                              border: Border(bottom: BorderSide(color: AppColors.divider)),
                            ),
                            child: Row(
                              children: [
                                _TableHeader('طريقة الدفع', flex: 2),
                                _TableHeader('العملة'),
                                _TableHeader('عدد الدفعات'),
                                _TableHeader('المقبوض الإجمالي'),
                                _TableHeader('الاستردادات'),
                                _TableHeader('الصافي المحصل'),
                                _TableHeader('النسبة (ضمن العملة)'),
                              ],
                            ),
                          ),
                          Expanded(
                            child: ListView.separated(
                              itemCount: rows.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(color: AppColors.divider, height: 1),
                              itemBuilder: (context, index) {
                                final r = rows[index];
                                final curr = r['currency'] as String? ?? 'SYP';
                                final gross = (r['gross_collected'] as num?)?.toDouble() ?? 0;
                                final refunds = (r['refunds'] as num?)?.toDouble() ?? 0;
                                final net = (r['net_collected'] as num?)?.toDouble() ?? 0;
                                final totalCurr = netPerCurrency[curr] ?? 0;
                                final pct = totalCurr > 0
                                    ? (net / totalCurr * 100).toStringAsFixed(1)
                                    : '0';

                                return Padding(
                                  padding: EdgeInsets.all(Responsive.spacing(context, 14)),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                          _getMethodLabel(r['method']),
                                          style: const TextStyle(
                                            color: AppColors.textPrimary,
                                            fontFamily: 'Cairo',
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          curr,
                                          style: TextStyle(
                                            color: curr == 'USD'
                                                ? AppColors.gold
                                                : AppColors.textSecondary,
                                            fontFamily: 'Cairo',
                                            fontWeight: FontWeight.w700,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          '${r['payment_count'] ?? 0}',
                                          style: const TextStyle(
                                            color: AppColors.textSecondary,
                                            fontFamily: 'Cairo',
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          _money(gross, curr),
                                          style: const TextStyle(
                                            color: AppColors.textPrimary,
                                            fontFamily: 'Cairo',
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          _money(refunds, curr),
                                          style: const TextStyle(
                                            color: AppColors.error,
                                            fontFamily: 'Cairo',
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          _money(net, curr),
                                          style: const TextStyle(
                                            color: AppColors.success,
                                            fontFamily: 'Cairo',
                                            fontWeight: FontWeight.w700,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          '$pct%',
                                          style: const TextStyle(
                                            color: AppColors.gold,
                                            fontFamily: 'Cairo',
                                            fontWeight: FontWeight.w700,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─── 5. Debt Aging & Discounts Tab (v2) ───
class _DebtAgingAndDiscountsTab extends ConsumerWidget {
  final String currencyFilter;
  final Function(List<List<dynamic>>, String) onExport;

  const _DebtAgingAndDiscountsTab({
    required this.currencyFilter,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agingAsync = ref.watch(debtAgingReportProvider);
    final discountsAsync = ref.watch(discountsReportProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'تصنيف أعمار الديون والمستحقات (Debt Aging v2)',
          style: TextStyle(
            fontSize: Responsive.fontSize(context, 16),
            fontWeight: FontWeight.w700,
            color: AppColors.gold,
            fontFamily: 'Cairo',
          ),
        ),
        SizedBox(height: Responsive.spacing(context, 8)),
        // Debt Aging Cards: exact values '1-30', '31-90', '>90'
        agingAsync.when(
          loading: () => const SizedBox(
            height: 80,
            child: Center(child: CircularProgressIndicator(color: AppColors.gold)),
          ),
          error: (e, _) => Text(
            'خطأ بأعمار الديون: $e',
            style: const TextStyle(color: AppColors.error, fontFamily: 'Cairo'),
          ),
          data: (allRows) {
            final rows = currencyFilter == 'الكل'
                ? allRows
                : allRows.where((r) => r['currency'] == currencyFilter).toList();

            double less30Syp = 0, midSyp = 0, over90Syp = 0;
            double less30Usd = 0, midUsd = 0, over90Usd = 0;

            for (final r in rows) {
              final b = ((r['total_overdue_balance'] ?? r['overdue_balance']) as num?)?.toDouble() ?? 0;
              final bucket = r['aging_bucket'];
              final curr = r['currency'] as String? ?? 'SYP';

              if (curr == 'USD') {
                if (bucket == '1-30') less30Usd += b;
                if (bucket == '31-90') midUsd += b;
                if (bucket == '>90') over90Usd += b;
              } else {
                if (bucket == '1-30') less30Syp += b;
                if (bucket == '31-90') midSyp += b;
                if (bucket == '>90') over90Syp += b;
              }
            }

            return Row(
              children: [
                _ReportCard(
                  label: 'أقل من شهر (1-30 يوم)',
                  value: _dualMoney(
                    syp: less30Syp,
                    usd: less30Usd,
                    currencyFilter: currencyFilter,
                  ),
                  color: AppColors.textPrimary,
                  icon: Icons.timer_outlined,
                ),
                SizedBox(width: Responsive.spacing(context, 10)),
                _ReportCard(
                  label: 'من شهر إلى 3 أشهر (31-90 يوم)',
                  value: _dualMoney(
                    syp: midSyp,
                    usd: midUsd,
                    currencyFilter: currencyFilter,
                  ),
                  color: AppColors.warning,
                  icon: Icons.warning_amber_rounded,
                ),
                SizedBox(width: Responsive.spacing(context, 10)),
                _ReportCard(
                  label: 'متأخر حرج (> 90 يوم)',
                  value: _dualMoney(
                    syp: over90Syp,
                    usd: over90Usd,
                    currencyFilter: currencyFilter,
                  ),
                  color: AppColors.error,
                  icon: Icons.error_outline,
                ),
              ],
            );
          },
        ),

        SizedBox(height: Responsive.spacing(context, 16)),

        // Discounts Report (Option A: per-enrollment detailed table)
        Row(
          children: [
            Text(
              'سجل الخصومات الممنوحة التفصيلي (Discounts Report v2)',
              style: TextStyle(
                fontSize: Responsive.fontSize(context, 16),
                fontWeight: FontWeight.w700,
                color: AppColors.gold,
                fontFamily: 'Cairo',
              ),
            ),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: () {
                final discounts = discountsAsync.asData?.value ?? [];
                final filtered = currencyFilter == 'الكل'
                    ? discounts
                    : discounts.where((d) => d['currency'] == currencyFilter).toList();

                final csv = [
                  [
                    'المتدرب',
                    'الكود',
                    'الكورس',
                    'العملة',
                    'الخصم الأصلي',
                    'التعديلات اليدوية',
                    'إجمالي الخصم'
                  ],
                  ...filtered.map((d) => [
                        d['trainee_name'] ?? '',
                        d['trainee_code'] ?? '',
                        d['course_name'] ?? '',
                        d['currency'] ?? '',
                        d['original_discount'] ?? 0,
                        d['manual_discounts'] ?? 0,
                        d['total_discounts'] ?? 0,
                      ]),
                ];
                onExport(csv, 'discounts_report_v2');
              },
              icon: const Icon(Icons.download, color: AppColors.gold, size: 18),
              label: const Text(
                'تصدير CSV',
                style: TextStyle(color: AppColors.gold, fontFamily: 'Cairo', fontSize: 12),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.gold),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        SizedBox(height: Responsive.spacing(context, 10)),

        Expanded(
          child: discountsAsync.when(
            loading: () =>
                const Center(child: CircularProgressIndicator(color: AppColors.gold)),
            error: (e, _) => AppErrorWidget(
              message: AppErrorHandler.friendlyMessage(e),
              onRetry: () => ref.invalidate(discountsReportProvider),
            ),
            data: (allDiscounts) {
              final discounts = currencyFilter == 'الكل'
                  ? allDiscounts
                  : allDiscounts.where((d) => d['currency'] == currencyFilter).toList();

              if (discounts.isEmpty) {
                return Center(
                  child: Text(
                    'لا توجد خصومات ممنوحة لهذه العملة',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontFamily: 'Cairo',
                      fontSize: Responsive.fontSize(context, 16),
                    ),
                  ),
                );
              }

              return Container(
                decoration: BoxDecoration(
                  color: AppColors.cardBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: EdgeInsets.all(Responsive.spacing(context, 14)),
                      decoration: const BoxDecoration(
                        border: Border(bottom: BorderSide(color: AppColors.divider)),
                      ),
                      child: Row(
                        children: [
                          _TableHeader('المتدرب', flex: 2),
                          _TableHeader('الكود'),
                          _TableHeader('الكورس', flex: 2),
                          _TableHeader('العملة'),
                          _TableHeader('الخصم الأصلي'),
                          _TableHeader('تعديل يدوي'),
                          _TableHeader('إجمالي الخصم'),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        itemCount: discounts.length,
                        separatorBuilder: (_, __) =>
                            const Divider(color: AppColors.divider, height: 1),
                        itemBuilder: (context, index) {
                          final d = discounts[index];
                          final curr = d['currency'] as String? ?? 'SYP';
                          final orig = (d['original_discount'] as num?)?.toDouble() ?? 0;
                          final manual = (d['manual_discounts'] as num?)?.toDouble() ?? 0;
                          final total = (d['total_discounts'] as num?)?.toDouble() ?? 0;

                          return Padding(
                            padding: EdgeInsets.all(Responsive.spacing(context, 14)),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    d['trainee_name'] ?? '',
                                    style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontFamily: 'Cairo',
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    d['trainee_code'] ?? '',
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontFamily: 'Cairo',
                                      fontSize: 12,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    d['course_name'] ?? '',
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontFamily: 'Cairo',
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    curr,
                                    style: TextStyle(
                                      color: curr == 'USD'
                                          ? AppColors.gold
                                          : AppColors.textSecondary,
                                      fontFamily: 'Cairo',
                                      fontWeight: FontWeight.w700,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    _money(orig, curr),
                                    style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontFamily: 'Cairo',
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    _money(manual, curr),
                                    style: const TextStyle(
                                      color: AppColors.warning,
                                      fontFamily: 'Cairo',
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    _money(total, curr),
                                    style: const TextStyle(
                                      color: AppColors.gold,
                                      fontFamily: 'Cairo',
                                      fontWeight: FontWeight.w700,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─── 6. Expenses by Category Tab (v2) ───
class _ExpensesByCategoryTab extends ConsumerWidget {
  final String currencyFilter;
  final Function(List<List<dynamic>>, String) onExport;

  const _ExpensesByCategoryTab({
    required this.currencyFilter,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportAsync = ref.watch(expensesByCategoryProvider);

    return reportAsync.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(color: AppColors.gold)),
      error: (e, _) => AppErrorWidget(
        message: AppErrorHandler.friendlyMessage(e),
        onRetry: () => ref.invalidate(expensesByCategoryProvider),
      ),
      data: (allRows) {
        final rows = currencyFilter == 'الكل'
            ? allRows
            : allRows.where((r) => r['currency'] == currencyFilter).toList();

        if (rows.isEmpty) {
          return Center(
            child: Text(
              'لا توجد مصاريف مسجلة لهذه العملة',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontFamily: 'Cairo',
                fontSize: Responsive.fontSize(context, 16),
              ),
            ),
          );
        }

        // Auditor rule: Calculate total expenses WITHIN EACH CURRENCY
        final Map<String, double> totalPerCurrency = {};
        for (final r in rows) {
          final curr = r['currency'] as String? ?? 'SYP';
          final spent = (r['total_spent'] as num?)?.toDouble() ?? 0;
          totalPerCurrency[curr] = (totalPerCurrency[curr] ?? 0) + spent;
        }

        return Column(
          children: [
            Row(
              children: [
                Text(
                  'توزيع المصاريف حسب الفئة والعملة (v2)',
                  style: TextStyle(
                    fontSize: Responsive.fontSize(context, 16),
                    fontWeight: FontWeight.w700,
                    color: AppColors.gold,
                    fontFamily: 'Cairo',
                  ),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: () {
                    final csv = [
                      ['الفئة', 'العملة', 'عدد العمليات', 'إجمالي المصروف', 'النسبة'],
                      ...rows.map((r) {
                        final curr = r['currency'] as String? ?? 'SYP';
                        final amt = (r['total_spent'] as num?)?.toDouble() ?? 0;
                        final totalCurr = totalPerCurrency[curr] ?? 0;
                        final pct = totalCurr > 0
                            ? (amt / totalCurr * 100).toStringAsFixed(1)
                            : '0';
                        return [
                          r['category'],
                          curr,
                          r['expense_count'],
                          amt,
                          '$pct%',
                        ];
                      }),
                    ];
                    onExport(csv, 'expenses_by_category_v2');
                  },
                  icon: const Icon(Icons.download, color: AppColors.gold, size: 18),
                  label: const Text(
                    'تصدير CSV',
                    style: TextStyle(color: AppColors.gold, fontFamily: 'Cairo', fontSize: 12),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.gold),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
            SizedBox(height: Responsive.spacing(context, 12)),
            Expanded(
              child: ListView.separated(
                itemCount: rows.length,
                separatorBuilder: (_, __) =>
                    SizedBox(height: Responsive.spacing(context, 8)),
                itemBuilder: (context, index) {
                  final r = rows[index];
                  final cat = r['category'] as String? ?? 'عام';
                  final count = r['expense_count'] ?? 0;
                  final total = (r['total_spent'] as num?)?.toDouble() ?? 0;
                  final curr = r['currency'] as String? ?? 'SYP';
                  final totalCurr = totalPerCurrency[curr] ?? 0;
                  final pct = totalCurr > 0
                      ? (total / totalCurr * 100).toStringAsFixed(1)
                      : '0';

                  return Container(
                    padding: EdgeInsets.all(Responsive.spacing(context, 16)),
                    decoration: BoxDecoration(
                      color: AppColors.cardBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: AppColors.error.withValues(alpha: 0.15),
                          child: const Icon(Icons.receipt_long, color: AppColors.error),
                        ),
                        SizedBox(width: Responsive.spacing(context, 12)),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                cat,
                                style: TextStyle(
                                  fontSize: Responsive.fontSize(context, 15),
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                              Text(
                                '$count عمليات مسجلة',
                                style: TextStyle(
                                  fontSize: Responsive.fontSize(context, 12),
                                  color: AppColors.textSecondary,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              _money(total, curr),
                              style: TextStyle(
                                fontSize: Responsive.fontSize(context, 15),
                                fontWeight: FontWeight.w900,
                                color: AppColors.error,
                                fontFamily: 'Cairo',
                              ),
                            ),
                            Text(
                              '$pct% من مصاريف $curr',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                                fontFamily: 'Cairo',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─── 7. Attendance Report Tab ───
class _AttendanceReportTab extends ConsumerWidget {
  final Function(List<List<dynamic>>, String) onExport;

  const _AttendanceReportTab({required this.onExport});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportAsync = ref.watch(attendanceReportProvider);

    return reportAsync.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(color: AppColors.gold)),
      error: (e, _) => AppErrorWidget(
        message: AppErrorHandler.friendlyMessage(e),
        onRetry: () => ref.invalidate(attendanceReportProvider),
      ),
      data: (rows) {
        return Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () {
                  final csvRows = [
                    [
                      'المتدرب',
                      'الكورس',
                      'الجلسات المحضورة',
                      'الإجمالي',
                      'النسبة'
                    ],
                    ...rows.map((r) => [
                          r['trainee_name'] ?? '',
                          r['course_name'] ?? '',
                          r['sessions_attended'] ?? 0,
                          r['total_sessions'] ?? 0,
                          '${r['attendance_percentage'] ?? 0}%',
                        ]),
                  ];
                  onExport(csvRows, 'attendance_report');
                },
                icon: const Icon(Icons.download, color: AppColors.gold, size: 18),
                label: const Text(
                  'تصدير CSV',
                  style: TextStyle(color: AppColors.gold, fontFamily: 'Cairo', fontSize: 12),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.gold),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            SizedBox(height: Responsive.spacing(context, 12)),
            Expanded(
              child: ListView.separated(
                itemCount: rows.length,
                separatorBuilder: (_, __) =>
                    SizedBox(height: Responsive.spacing(context, 8)),
                itemBuilder: (context, index) {
                  final r = rows[index];
                  final pct =
                      (r['attendance_percentage'] as num?)?.toDouble() ?? 0;

                  return Container(
                    padding: EdgeInsets.all(Responsive.spacing(context, 16)),
                    decoration: BoxDecoration(
                      color: AppColors.cardBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                r['trainee_name'] ?? '',
                                style: TextStyle(
                                  fontSize: Responsive.fontSize(context, 15),
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                              Text(
                                '${r['course_name'] ?? ''} - ${r['sessions_attended'] ?? 0} من ${r['total_sessions'] ?? 0} جلسة',
                                style: TextStyle(
                                  fontSize: Responsive.fontSize(context, 12),
                                  color: AppColors.textSecondary,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: (pct >= 75 ? AppColors.success : AppColors.error)
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${pct.toStringAsFixed(0)}%',
                            style: TextStyle(
                              color: pct >= 75 ? AppColors.success : AppColors.error,
                              fontWeight: FontWeight.w900,
                              fontFamily: 'Cairo',
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─── Shared UI Components ───
class _ReportCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _ReportCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.all(Responsive.spacing(context, 14)),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            SizedBox(width: Responsive.spacing(context, 10)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: Responsive.fontSize(context, 11),
                      color: AppColors.textSecondary,
                      fontFamily: 'Cairo',
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: Responsive.fontSize(context, 14),
                      fontWeight: FontWeight.w900,
                      color: color,
                      fontFamily: 'Cairo',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  final String text;
  final int flex;

  const _TableHeader(this.text, {this.flex = 1});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.gold,
          fontFamily: 'Cairo',
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
