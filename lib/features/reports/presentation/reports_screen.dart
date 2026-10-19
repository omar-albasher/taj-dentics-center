import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/app_formatters.dart';
import 'package:csv/csv.dart';
import 'package:file_saver/file_saver.dart';
import 'package:admin_dashboard/core/widgets/app_error_widget.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/responsive.dart';
import '../data/reports_repository.dart';
import 'dart:typed_data';
import 'package:admin_dashboard/core/widgets/keep_alive_wrapper.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

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
            Text(
              'التقارير',
              style: TextStyle(
                fontSize: Responsive.fontSize(context, 28),
                fontWeight: FontWeight.w900,
                color: AppColors.gold,
                fontFamily: 'Cairo',
              ),
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
                Tab(text: 'المستحقات'),
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
                  KeepAliveWrapper(child: _ProfitLossTab(onExport: _exportCsv)),
                  KeepAliveWrapper(child: _OverdueReportTab(onExport: _exportCsv)),
                  KeepAliveWrapper(child: _CourseRevenueTab(onExport: _exportCsv)),
                  KeepAliveWrapper(child: _PaymentMethodsAndCashTab(onExport: _exportCsv)),
                  KeepAliveWrapper(child: _DebtAgingAndDiscountsTab(onExport: _exportCsv)),
                  KeepAliveWrapper(child: _ExpensesByCategoryTab(onExport: _exportCsv)),
                  KeepAliveWrapper(child: _AttendanceReportTab(onExport: _exportCsv)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Profit & Loss Tab ───
class _ProfitLossTab extends ConsumerWidget {
  final Function(List<List<dynamic>>, String) onExport;
  const _ProfitLossTab({required this.onExport});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportAsync = ref.watch(profitLossProvider);
    final fmt = AppFormatters.amount;

    return reportAsync.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(color: AppColors.gold)),
      error: (e, _) => AppErrorWidget(
        message: 'خطأ: $e',
        onRetry: () => ref.invalidate(profitLossProvider),
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return Center(
            child: Text('لا توجد بيانات',
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontFamily: 'Cairo',
                    fontSize: Responsive.fontSize(context, 16))),
          );
        }

        double totalIncome = 0;
        double totalExpenses = 0;
        double totalProfit = 0;

        for (final r in rows) {
          totalIncome += (r['total_income'] as num?)?.toDouble() ?? 0;
          totalExpenses += (r['total_expenses'] as num?)?.toDouble() ?? 0;
          totalProfit += (r['net_profit'] as num?)?.toDouble() ?? 0;
        }

        return Column(
          children: [
            // Summary Cards
            Row(
              children: [
                _ReportCard(
                  label: 'إجمالي الإيرادات',
                  value: '${fmt.format(totalIncome.toInt())} ل.س',
                  color: AppColors.success,
                  icon: Icons.trending_up,
                ),
                SizedBox(width: Responsive.spacing(context, 12)),
                _ReportCard(
                  label: 'إجمالي المصاريف',
                  value: '${fmt.format(totalExpenses.toInt())} ل.س',
                  color: AppColors.error,
                  icon: Icons.trending_down,
                ),
                SizedBox(width: Responsive.spacing(context, 12)),
                _ReportCard(
                  label: 'صافي الربح',
                  value: '${fmt.format(totalProfit.toInt())} ل.س',
                  color: totalProfit >= 0 ? AppColors.gold : AppColors.error,
                  icon: Icons.account_balance,
                ),
              ],
            ),

            SizedBox(height: Responsive.spacing(context, 16)),

            // Export Button
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () {
                  final csvRows = [
                    ['الشهر', 'الإيرادات', 'المصاريف', 'صافي الربح'],
                    ...rows.map((r) => [
                          r['month'] ?? '',
                          r['total_income'] ?? 0,
                          r['total_expenses'] ?? 0,
                          r['net_profit'] ?? 0,
                        ]),
                  ];
                  onExport(csvRows, 'profit_loss_report');
                },
                icon: const Icon(Icons.download, color: AppColors.gold),
                label: const Text('تصدير CSV',
                    style:
                        TextStyle(color: AppColors.gold, fontFamily: 'Cairo')),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.gold),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),

            SizedBox(height: Responsive.spacing(context, 12)),

            // Table
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Column(
                  children: [
                    // Header
                    Container(
                      padding: EdgeInsets.all(Responsive.spacing(context, 16)),
                      decoration: const BoxDecoration(
                        border: Border(
                            bottom: BorderSide(color: AppColors.divider)),
                      ),
                      child: Row(
                        children: [
                          _TableHeader('الشهر', flex: 2),
                          _TableHeader('الإيرادات'),
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
                          final income =
                              (r['total_income'] as num?)?.toDouble() ?? 0;
                          final expense =
                              (r['total_expenses'] as num?)?.toDouble() ?? 0;
                          final profit =
                              (r['net_profit'] as num?)?.toDouble() ?? 0;
                          final month = r['month'] != null
                              ? AppFormatters.monthShortAr
                                  .format(DateTime.parse(r['month']))
                              : '';

                          return Padding(
                            padding:
                                EdgeInsets.all(Responsive.spacing(context, 16)),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: Text(month,
                                      style: const TextStyle(
                                          color: AppColors.textPrimary,
                                          fontFamily: 'Cairo')),
                                ),
                                Expanded(
                                  child: Text(
                                    fmt.format(income.toInt()),
                                    style: const TextStyle(
                                        color: AppColors.success,
                                        fontFamily: 'Cairo',
                                        fontWeight: FontWeight.w700),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    fmt.format(expense.toInt()),
                                    style: const TextStyle(
                                        color: AppColors.error,
                                        fontFamily: 'Cairo',
                                        fontWeight: FontWeight.w700),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    fmt.format(profit.toInt()),
                                    style: TextStyle(
                                        color: profit >= 0
                                            ? AppColors.gold
                                            : AppColors.error,
                                        fontFamily: 'Cairo',
                                        fontWeight: FontWeight.w700),
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

// ─── Overdue Report Tab ───
class _OverdueReportTab extends ConsumerWidget {
  final Function(List<List<dynamic>>, String) onExport;
  const _OverdueReportTab({required this.onExport});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportAsync = ref.watch(overdueReportProvider);
    final fmt = AppFormatters.amount;

    return reportAsync.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(color: AppColors.gold)),
      error: (e, _) => AppErrorWidget(
        message: 'خطأ: $e',
        onRetry: () => ref.invalidate(overdueReportProvider),
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return Center(
            child: Text('🎉 لا توجد مستحقات متأخرة',
                style: TextStyle(
                    color: AppColors.success,
                    fontFamily: 'Cairo',
                    fontSize: Responsive.fontSize(context, 16))),
          );
        }

        final totalBalance = rows.fold(
          0.0,
          (sum, r) => sum + ((r['balance_due'] as num?)?.toDouble() ?? 0),
        );

        return Column(
          children: [
            _ReportCard(
              label: 'إجمالي المستحقات',
              value: '${fmt.format(totalBalance.toInt())} ل.س',
              color: AppColors.error,
              icon: Icons.warning_amber,
            ),
            SizedBox(height: Responsive.spacing(context, 12)),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () {
                  final csvRows = [
                    [
                      'الاسم',
                      'الكورس',
                      'الهاتف',
                      'المستحق',
                      'المدفوع',
                      'المتبقي'
                    ],
                    ...rows.map((r) => [
                          r['trainee_name'] ?? '',
                          r['course_name'] ?? '',
                          r['phone'] ?? '',
                          r['total_due'] ?? 0,
                          r['total_paid'] ?? 0,
                          r['balance_due'] ?? 0,
                        ]),
                  ];
                  onExport(csvRows, 'overdue_report');
                },
                icon: const Icon(Icons.download, color: AppColors.gold),
                label: const Text('تصدير CSV',
                    style:
                        TextStyle(color: AppColors.gold, fontFamily: 'Cairo')),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.gold),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
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

                  return Container(
                    padding: EdgeInsets.all(Responsive.spacing(context, 16)),
                    decoration: BoxDecoration(
                      color: AppColors.cardBg,
                      borderRadius: BorderRadius.circular(16),
                      border:
                          Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: AppColors.error.withValues(alpha: 0.15),
                          child: Text('${index + 1}',
                              style: const TextStyle(
                                  color: AppColors.error,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'Cairo')),
                        ),
                        SizedBox(width: Responsive.spacing(context, 12)),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r['trainee_name'] ?? '',
                                  style: TextStyle(
                                      fontSize:
                                          Responsive.fontSize(context, 15),
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimary,
                                      fontFamily: 'Cairo')),
                              Text(r['course_name'] ?? '',
                                  style: TextStyle(
                                      fontSize:
                                          Responsive.fontSize(context, 12),
                                      color: AppColors.textSecondary,
                                      fontFamily: 'Cairo')),
                            ],
                          ),
                        ),
                        Text(
                          '${fmt.format(balance.toInt())} ل.س',
                          style: TextStyle(
                              fontSize: Responsive.fontSize(context, 15),
                              fontWeight: FontWeight.w900,
                              color: AppColors.error,
                              fontFamily: 'Cairo'),
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

// ─── Course Revenue Tab ───
class _CourseRevenueTab extends ConsumerWidget {
  final Function(List<List<dynamic>>, String) onExport;
  const _CourseRevenueTab({required this.onExport});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportAsync = ref.watch(courseRevenueProvider);
    final fmt = AppFormatters.amount;

    return reportAsync.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(color: AppColors.gold)),
      error: (e, _) => AppErrorWidget(
        message: 'خطأ: $e',
        onRetry: () => ref.invalidate(courseRevenueProvider),
      ),
      data: (rows) {
        // Group by course and currency
        final Map<String, Map<String, dynamic>> grouped = {};
        for (final r in rows) {
          final name = r['course_name'] as String? ?? '';
          final currency = r['currency'] as String? ?? 'SYP';
          final key = '${name}_$currency';
          if (!grouped.containsKey(key)) {
            grouped[key] = {
              'course_name': name,
              'currency': currency,
              'total_due': 0.0,
              'total_paid': 0.0,
              'count': 0,
            };
          }
          grouped[key]!['total_due'] +=
              (r['total_due'] as num?)?.toDouble() ?? 0;
          grouped[key]!['total_paid'] +=
              (r['total_paid'] as num?)?.toDouble() ?? 0;
          grouped[key]!['count'] += 1;
        }

        final courses = grouped.values.toList();

        return Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () {
                  final csvRows = [
                    ['الكورس', 'العملة', 'عدد المتدربين', 'إجمالي الرسوم', 'المحصّل'],
                    ...courses.map((c) => [
                          c['course_name'],
                          c['currency'],
                          c['count'],
                          c['total_due'],
                          c['total_paid'],
                        ]),
                  ];
                  onExport(csvRows, 'course_revenue_report');
                },
                icon: const Icon(Icons.download, color: AppColors.gold),
                label: const Text('تصدير CSV',
                    style:
                        TextStyle(color: AppColors.gold, fontFamily: 'Cairo')),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.gold),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
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
                  final due = (c['total_due'] as num).toDouble();
                  final paid = (c['total_paid'] as num).toDouble();
                  final pct = due > 0 ? (paid / due * 100) : 0.0;

                  return Container(
                    padding: EdgeInsets.all(Responsive.spacing(context, 16)),
                    decoration: BoxDecoration(
                      color: AppColors.cardBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(c['course_name'] ?? '',
                                  style: TextStyle(
                                      fontSize:
                                          Responsive.fontSize(context, 16),
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.gold,
                                      fontFamily: 'Cairo')),
                            ),
                            Text('${c['count']} متدرب',
                                style: TextStyle(
                                    fontSize: Responsive.fontSize(context, 13),
                                    color: AppColors.textSecondary,
                                    fontFamily: 'Cairo')),
                          ],
                        ),
                        SizedBox(height: Responsive.spacing(context, 8)),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      'المحصّل: ${fmt.format(paid.toInt())} ${c['currency'] == 'USD' ? '\$' : 'ل.س'}',
                                      style: const TextStyle(
                                          color: AppColors.success,
                                          fontFamily: 'Cairo',
                                          fontWeight: FontWeight.w700)),
                                  Text(
                                      'الإجمالي: ${fmt.format(due.toInt())} ${c['currency'] == 'USD' ? '\$' : 'ل.س'}',
                                      style: const TextStyle(
                                          color: AppColors.textSecondary,
                                          fontFamily: 'Cairo')),
                                ],
                              ),
                            ),
                            Text('${pct.toStringAsFixed(0)}%',
                                style: TextStyle(
                                    fontSize: Responsive.fontSize(context, 18),
                                    fontWeight: FontWeight.w900,
                                    color: pct >= 75
                                        ? AppColors.success
                                        : pct >= 50
                                            ? AppColors.warning
                                            : AppColors.error,
                                    fontFamily: 'Cairo')),
                          ],
                        ),
                        SizedBox(height: Responsive.spacing(context, 8)),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: pct / 100,
                            backgroundColor: AppColors.divider,
                            valueColor: AlwaysStoppedAnimation(
                              pct >= 75
                                  ? AppColors.success
                                  : pct >= 50
                                      ? AppColors.warning
                                      : AppColors.error,
                            ),
                            minHeight: 8,
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

// ─── Attendance Report Tab ───
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
        message: 'خطأ: $e',
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
                icon: const Icon(Icons.download, color: AppColors.gold),
                label: const Text('تصدير CSV',
                    style:
                        TextStyle(color: AppColors.gold, fontFamily: 'Cairo')),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.gold),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
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
                  final attended =
                      (r['sessions_attended'] as num?)?.toInt() ?? 0;
                  final total = (r['total_sessions'] as num?)?.toInt() ?? 1;
                  final pct =
                      (r['attendance_percentage'] as num?)?.toDouble() ?? 0;

                  return Container(
                    padding: EdgeInsets.all(Responsive.spacing(context, 16)),
                    decoration: BoxDecoration(
                      color: AppColors.cardBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r['trainee_name'] ?? '',
                                  style: TextStyle(
                                      fontSize:
                                          Responsive.fontSize(context, 15),
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimary,
                                      fontFamily: 'Cairo')),
                              Text(r['course_name'] ?? '',
                                  style: TextStyle(
                                      fontSize:
                                          Responsive.fontSize(context, 12),
                                      color: AppColors.textSecondary,
                                      fontFamily: 'Cairo')),
                              SizedBox(height: Responsive.spacing(context, 8)),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: LinearProgressIndicator(
                                  value: pct / 100,
                                  backgroundColor: AppColors.divider,
                                  valueColor: AlwaysStoppedAnimation(
                                    pct >= 75
                                        ? AppColors.success
                                        : pct >= 50
                                            ? AppColors.warning
                                            : AppColors.error,
                                  ),
                                  minHeight: 6,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(width: Responsive.spacing(context, 16)),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('$attended/$total',
                                style: TextStyle(
                                    fontSize: Responsive.fontSize(context, 16),
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.textPrimary,
                                    fontFamily: 'Cairo')),
                            Text('${pct.toStringAsFixed(0)}%',
                                style: TextStyle(
                                    fontSize: Responsive.fontSize(context, 13),
                                    fontWeight: FontWeight.w700,
                                    color: pct >= 75
                                        ? AppColors.success
                                        : pct >= 50
                                            ? AppColors.warning
                                            : AppColors.error,
                                    fontFamily: 'Cairo')),
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

// ─── Helpers ───

// ─── Payment Methods & Cash Tab (Phase 4.5) ───
class _PaymentMethodsAndCashTab extends ConsumerWidget {
  final Function(List<List<dynamic>>, String) onExport;
  const _PaymentMethodsAndCashTab({required this.onExport});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cashAsync = ref.watch(cashVsAccrualProvider);
    final methodsAsync = ref.watch(revenueByMethodProvider);
    final fmt = AppFormatters.amount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Cash vs Accrual KPIs
        cashAsync.when(
          loading: () => const SizedBox(height: 80, child: Center(child: CircularProgressIndicator(color: AppColors.gold))),
          error: (e, _) => Text('خطأ بمؤشرات السيولة: $e', style: const TextStyle(color: AppColors.error, fontFamily: 'Cairo')),
          data: (kpis) {
            double collected = 0;
            double pending = 0;
            double expected = 0;
            for (final k in kpis) {
              collected += (k['collected_cash'] as num?)?.toDouble() ?? 0;
              pending += (k['pending_accrual'] as num?)?.toDouble() ?? 0;
              expected += (k['total_expected'] as num?)?.toDouble() ?? 0;
            }
            return Row(
              children: [
                _ReportCard(
                  label: 'السيولة المحصّلة فعلياً (Cash)',
                  value: '${fmt.format(collected.toInt())} ل.س',
                  color: AppColors.success,
                  icon: Icons.account_balance_wallet,
                ),
                SizedBox(width: Responsive.spacing(context, 12)),
                _ReportCard(
                  label: 'المستحقات المتوقعة (Accrual)',
                  value: '${fmt.format(pending.toInt())} ل.س',
                  color: AppColors.warning,
                  icon: Icons.hourglass_top,
                ),
                SizedBox(width: Responsive.spacing(context, 12)),
                _ReportCard(
                  label: 'إجمالي العقود النشطة',
                  value: '${fmt.format(expected.toInt())} ل.س',
                  color: AppColors.gold,
                  icon: Icons.pie_chart_outline,
                ),
              ],
            );
          },
        ),
        SizedBox(height: Responsive.spacing(context, 16)),

        // Revenue by Payment Method Table
        Expanded(
          child: methodsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator(color: AppColors.gold)),
            error: (e, _) => AppErrorWidget(message: 'خطأ: $e', onRetry: () => ref.invalidate(revenueByMethodProvider)),
            data: (rows) {
              if (rows.isEmpty) {
                return Center(
                  child: Text('لا توجد دفعات مسجلة',
                      style: TextStyle(color: AppColors.textSecondary, fontFamily: 'Cairo', fontSize: Responsive.fontSize(context, 16))),
                );
              }

              double totalRevenue = 0;
              for (final r in rows) {
                totalRevenue += (r['total_amount'] as num?)?.toDouble() ?? 0;
              }

              return Column(
                children: [
                  Row(
                    children: [
                      Text(
                        'توزيع المقبوضات حسب وسيلة الدفع',
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
                            ['طريقة الدفع', 'العملة', 'عدد الدفعات', 'إجمالي المبلغ', 'النسبة'],
                            ...rows.map((r) {
                              final amt = (r['total_amount'] as num?)?.toDouble() ?? 0;
                              final pct = totalRevenue > 0 ? (amt / totalRevenue * 100).toStringAsFixed(1) : '0';
                              return [
                                _getMethodLabel(r['method']),
                                r['currency'] ?? 'SYP',
                                r['payments_count'] ?? 0,
                                amt,
                                '$pct%',
                              ];
                            }),
                          ];
                          onExport(csv, 'revenue_by_method');
                        },
                        icon: const Icon(Icons.download, color: AppColors.gold, size: 18),
                        label: const Text('تصدير CSV', style: TextStyle(color: AppColors.gold, fontFamily: 'Cairo')),
                        style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.gold), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      ),
                    ],
                  ),
                  SizedBox(height: Responsive.spacing(context, 12)),
                  Expanded(
                    child: ListView.separated(
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => SizedBox(height: Responsive.spacing(context, 8)),
                      itemBuilder: (context, index) {
                        final r = rows[index];
                        final method = r['method'] as String? ?? 'cash';
                        final amount = (r['total_amount'] as num?)?.toDouble() ?? 0;
                        final count = r['payments_count'] ?? 0;
                        final currency = r['currency'] ?? 'SYP';
                        final pct = totalRevenue > 0 ? (amount / totalRevenue * 100).toStringAsFixed(1) : '0';

                        return Container(
                          padding: EdgeInsets.all(Responsive.spacing(context, 16)),
                          decoration: BoxDecoration(
                            color: AppColors.cardBg,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.divider),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: AppColors.gold.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(_getMethodIcon(method), color: AppColors.gold),
                              ),
                              SizedBox(width: Responsive.spacing(context, 12)),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _getMethodLabel(method),
                                      style: TextStyle(
                                        fontSize: Responsive.fontSize(context, 15),
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.textPrimary,
                                        fontFamily: 'Cairo',
                                      ),
                                    ),
                                    Text(
                                      '$count دفعة مسجلة • النسبة: $pct%',
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
                                '${fmt.format(amount.toInt())} ${currency == 'USD' ? r'$' : 'ل.س'}',
                                style: TextStyle(
                                  fontSize: Responsive.fontSize(context, 16),
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.success,
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
          ),
        ),
      ],
    );
  }

  String _getMethodLabel(String? method) {
    switch (method) {
      case 'cash': return 'نقداً (Cash)';
      case 'sham_cash': return 'شام كاش (Sham Cash)';
      case 'hawala': return 'حوالة (هرم)';
      case 'transfer': return 'تحويل بنكي';
      default: return 'أخرى';
    }
  }

  IconData _getMethodIcon(String? method) {
    switch (method) {
      case 'cash': return Icons.payments_outlined;
      case 'sham_cash': return Icons.phone_android;
      case 'hawala': return Icons.receipt_long;
      case 'transfer': return Icons.account_balance;
      default: return Icons.more_horiz;
    }
  }
}

// ─── Debt Aging & Discounts Tab (Phase 4.5) ───
class _DebtAgingAndDiscountsTab extends ConsumerWidget {
  final Function(List<List<dynamic>>, String) onExport;
  const _DebtAgingAndDiscountsTab({required this.onExport});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agingAsync = ref.watch(debtAgingReportProvider);
    final discountsAsync = ref.watch(discountsReportProvider);
    final fmt = AppFormatters.amount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Debt Aging Cards
        Text(
          'تصنيف أعمار الديون والمستحقات (Debt Aging)',
          style: TextStyle(
            fontSize: Responsive.fontSize(context, 16),
            fontWeight: FontWeight.w700,
            color: AppColors.gold,
            fontFamily: 'Cairo',
          ),
        ),
        SizedBox(height: Responsive.spacing(context, 8)),
        agingAsync.when(
          loading: () => const SizedBox(height: 80, child: Center(child: CircularProgressIndicator(color: AppColors.gold))),
          error: (e, _) => Text('خطأ بأعمار الديون: $e', style: const TextStyle(color: AppColors.error, fontFamily: 'Cairo')),
          data: (rows) {
            double less30 = 0;
            double mid30_90 = 0;
            double over90 = 0;
            for (final r in rows) {
              final b = (r['total_overdue_balance'] as num?)?.toDouble() ?? 0;
              final bracket = r['aging_bracket'];
              if (bracket == 'less_than_30') {
                less30 += b;
              } else if (bracket == 'between_30_and_90') {
                mid30_90 += b;
              } else if (bracket == 'more_than_90') {
                over90 += b;
              }
            }
            return Row(
              children: [
                _ReportCard(
                  label: 'أقل من شهر (< 30 يوم)',
                  value: '${fmt.format(less30.toInt())} ل.س',
                  color: AppColors.textPrimary,
                  icon: Icons.timer_outlined,
                ),
                SizedBox(width: Responsive.spacing(context, 12)),
                _ReportCard(
                  label: 'من شهر إلى 3 أشهر (30-90 يوم)',
                  value: '${fmt.format(mid30_90.toInt())} ل.س',
                  color: AppColors.warning,
                  icon: Icons.warning_amber_rounded,
                ),
                SizedBox(width: Responsive.spacing(context, 12)),
                _ReportCard(
                  label: 'متأخر حرج (> 90 يوم)',
                  value: '${fmt.format(over90.toInt())} ل.س',
                  color: AppColors.error,
                  icon: Icons.error_outline,
                ),
              ],
            );
          },
        ),
        SizedBox(height: Responsive.spacing(context, 20)),

        // Discounts Report
        Row(
          children: [
            Text(
              'تقرير الخصومات الممنوحة حسب الكورس',
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
                final csv = [
                  ['الكورس', 'العملة', 'عدد المتدربين الممنوحين', 'إجمالي الخصم'],
                  ...discounts.map((d) => [
                    d['course_name'],
                    d['currency'],
                    d['discounted_trainees_count'],
                    d['total_discounts'],
                  ]),
                ];
                onExport(csv, 'discounts_report');
              },
              icon: const Icon(Icons.download, color: AppColors.gold, size: 18),
              label: const Text('تصدير CSV', style: TextStyle(color: AppColors.gold, fontFamily: 'Cairo')),
              style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.gold), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            ),
          ],
        ),
        SizedBox(height: Responsive.spacing(context, 12)),
        Expanded(
          child: discountsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator(color: AppColors.gold)),
            error: (e, _) => AppErrorWidget(message: 'خطأ: $e', onRetry: () => ref.invalidate(discountsReportProvider)),
            data: (discounts) {
              if (discounts.isEmpty) {
                return Center(
                  child: Text('لا توجد خصومات ممنوحة',
                      style: TextStyle(color: AppColors.textSecondary, fontFamily: 'Cairo', fontSize: Responsive.fontSize(context, 16))),
                );
              }
              return ListView.separated(
                itemCount: discounts.length,
                separatorBuilder: (_, __) => SizedBox(height: Responsive.spacing(context, 8)),
                itemBuilder: (context, index) {
                  final d = discounts[index];
                  final course = d['course_name'] ?? '';
                  final count = d['discounted_trainees_count'] ?? 0;
                  final total = (d['total_discounts'] as num?)?.toDouble() ?? 0;
                  final currency = d['currency'] ?? 'SYP';

                  return Container(
                    padding: EdgeInsets.all(Responsive.spacing(context, 16)),
                    decoration: BoxDecoration(
                      color: AppColors.cardBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.warning.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.discount_outlined, color: AppColors.warning),
                        ),
                        SizedBox(width: Responsive.spacing(context, 12)),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                course,
                                style: TextStyle(
                                  fontSize: Responsive.fontSize(context, 15),
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                              Text(
                                '$count متدرب حاصل على خصم',
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
                          '${fmt.format(total.toInt())} ${currency == 'USD' ? r'$' : 'ل.س'}',
                          style: TextStyle(
                            fontSize: Responsive.fontSize(context, 16),
                            fontWeight: FontWeight.w900,
                            color: AppColors.warning,
                            fontFamily: 'Cairo',
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─── Expenses by Category Tab (Phase 4.5) ───
class _ExpensesByCategoryTab extends ConsumerWidget {
  final Function(List<List<dynamic>>, String) onExport;
  const _ExpensesByCategoryTab({required this.onExport});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportAsync = ref.watch(expensesByCategoryProvider);
    final fmt = AppFormatters.amount;

    return reportAsync.when(
      loading: () => const Center(child: CircularProgressIndicator(color: AppColors.gold)),
      error: (e, _) => AppErrorWidget(message: 'خطأ: $e', onRetry: () => ref.invalidate(expensesByCategoryProvider)),
      data: (rows) {
        if (rows.isEmpty) {
          return Center(
            child: Text('لا توجد مصاريف مسجلة',
                style: TextStyle(color: AppColors.textSecondary, fontFamily: 'Cairo', fontSize: Responsive.fontSize(context, 16))),
          );
        }

        double totalExpenses = 0;
        for (final r in rows) {
          totalExpenses += (r['total_spent'] as num?)?.toDouble() ?? 0;
        }

        return Column(
          children: [
            Row(
              children: [
                Text(
                  'توزيع المصاريف حسب الفئة',
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
                        final amt = (r['total_spent'] as num?)?.toDouble() ?? 0;
                        final pct = totalExpenses > 0 ? (amt / totalExpenses * 100).toStringAsFixed(1) : '0';
                        return [
                          r['category'],
                          r['currency'],
                          r['expense_count'],
                          amt,
                          '$pct%',
                        ];
                      }),
                    ];
                    onExport(csv, 'expenses_by_category');
                  },
                  icon: const Icon(Icons.download, color: AppColors.gold, size: 18),
                  label: const Text('تصدير CSV', style: TextStyle(color: AppColors.gold, fontFamily: 'Cairo')),
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.gold), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                ),
              ],
            ),
            SizedBox(height: Responsive.spacing(context, 12)),
            Expanded(
              child: ListView.separated(
                itemCount: rows.length,
                separatorBuilder: (_, __) => SizedBox(height: Responsive.spacing(context, 8)),
                itemBuilder: (context, index) {
                  final r = rows[index];
                  final cat = r['category'] as String? ?? 'عام';
                  final count = r['expense_count'] ?? 0;
                  final total = (r['total_spent'] as num?)?.toDouble() ?? 0;
                  final currency = r['currency'] ?? 'SYP';
                  final pct = totalExpenses > 0 ? (total / totalExpenses * 100).toStringAsFixed(1) : '0';

                  return Container(
                    padding: EdgeInsets.all(Responsive.spacing(context, 16)),
                    decoration: BoxDecoration(
                      color: AppColors.cardBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.error.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.receipt_outlined, color: AppColors.error),
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
                                '$count سند صرف • النسبة: $pct%',
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
                          '${fmt.format(total.toInt())} ${currency == 'USD' ? r'$' : 'ل.س'}',
                          style: TextStyle(
                            fontSize: Responsive.fontSize(context, 16),
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
        padding: EdgeInsets.all(Responsive.spacing(context, 16)),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 28),
            SizedBox(width: Responsive.spacing(context, 12)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: Responsive.fontSize(context, 12),
                          color: AppColors.textSecondary,
                          fontFamily: 'Cairo')),
                  Text(value,
                      style: TextStyle(
                          fontSize: Responsive.fontSize(context, 16),
                          fontWeight: FontWeight.w900,
                          color: color,
                          fontFamily: 'Cairo'),
                      overflow: TextOverflow.ellipsis),
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
        ),
        textAlign: flex == 1 ? TextAlign.center : TextAlign.start,
      ),
    );
  }
}
