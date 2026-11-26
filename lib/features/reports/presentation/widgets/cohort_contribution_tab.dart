import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/app_error_handler.dart';
import '../../../../core/widgets/app_error_widget.dart';
import '../../data/reports_repository.dart';
import '../../domain/cohort_contribution_models.dart';

class CohortContributionTab extends ConsumerStatefulWidget {
  final String currencyFilter;
  final Future<void> Function(List<List<dynamic>> rows, String filename)
      onExport;

  const CohortContributionTab({
    super.key,
    required this.currencyFilter,
    required this.onExport,
  });

  @override
  ConsumerState<CohortContributionTab> createState() =>
      _CohortContributionTabState();
}

class _CohortContributionTabState extends ConsumerState<CohortContributionTab> {
  final _amountFormat = NumberFormat('#,##0.##');

  String _formatMoney(double amount, String currency) {
    final formatted = _amountFormat.format(amount);
    final c = currency.toUpperCase();
    if (c == 'USD') return '\$$formatted';
    if (c == 'SYP') return '$formatted ل.س';
    return '$formatted $c';
  }

  String _formatRatio(double? ratio) {
    if (ratio == null) return '—';
    return '${(ratio * 100).toStringAsFixed(1)}%';
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
      ref.read(cohortContributionAsOfDateProvider.notifier).setDate(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final asOf = ref.watch(cohortContributionAsOfDateProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppColors.gold.withValues(alpha: 0.4)),
                ),
                child: const Text(
                  'هامش مساهمة قبل المصاريف المشتركة',
                  style: TextStyle(
                    color: AppColors.gold,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _pickAsOfDate(asOf),
                icon: const Icon(Icons.calendar_today_rounded,
                    size: 16, color: AppColors.gold),
                label: Text(
                  'حتى تاريخ: ${DateFormat('yyyy/MM/dd').format(asOf)}',
                  style: const TextStyle(color: AppColors.textPrimary),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.divider),
                  backgroundColor: AppColors.cardBg,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'الإيراد المكتسب (C5) ناقص أتعاب المدرب (C3) لكل فوج وعملة. المصاريف المشتركة غير موزعة على الأفواج، لذا هذا الهامش ليس ربحاً صافياً للفوج.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 16),
          _buildReportSection(),
        ],
      ),
    );
  }

  Widget _buildReportSection() {
    final reportAsync = ref.watch(cohortContributionReportProvider);

    return reportAsync.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(48.0),
          child: CircularProgressIndicator(color: AppColors.gold),
        ),
      ),
      error: (e, s) => AppErrorWidget(
        message: AppErrorHandler.friendlyMessage(e),
        onRetry: () => ref.refresh(cohortContributionReportProvider),
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
                'لا توجد بيانات هامش مساهمة حتى هذا التاريخ',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
              ),
            ),
          );
        }

        final rowsByCurrency = <String, List<CohortContributionRow>>{};
        for (final r in filteredRows) {
          rowsByCurrency.putIfAbsent(r.currency, () => []).add(r);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...rowsByCurrency.entries.map((entry) {
              final summary = CohortContributionSummary.fromRows(
                entry.key,
                entry.value,
              );
              return _buildCurrencySummary(summary);
            }),
            const SizedBox(height: 12),
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
                          'تفاصيل هامش المساهمة (${filteredRows.length})',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const Spacer(),
                        ElevatedButton.icon(
                          onPressed: () => _exportCsv(filteredRows),
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
                        DataColumn(label: Text('الفوج')),
                        DataColumn(label: Text('الدورة')),
                        DataColumn(label: Text('العملة')),
                        DataColumn(label: Text('الإيراد المكتسب')),
                        DataColumn(label: Text('أتعاب المدرب')),
                        DataColumn(label: Text('هامش المساهمة')),
                        DataColumn(label: Text('نسبة الهامش')),
                        DataColumn(label: Text('المتدربون')),
                        DataColumn(label: Text('حالة الأتعاب')),
                      ],
                      rows: filteredRows.map((r) {
                        return DataRow(
                          cells: [
                            DataCell(Text(r.cohortName)),
                            DataCell(Text(r.courseName)),
                            DataCell(Text(r.currency)),
                            DataCell(Text(
                              _formatMoney(r.earnedRevenue, r.currency),
                              style: const TextStyle(color: Colors.greenAccent),
                            )),
                            DataCell(Text(
                              _formatMoney(r.trainerCost, r.currency),
                              style:
                                  const TextStyle(color: Colors.orangeAccent),
                            )),
                            DataCell(Text(
                              _formatMoney(
                                  r.contributionMargin, r.currency),
                              style: TextStyle(
                                color: r.contributionMargin >= 0
                                    ? AppColors.gold
                                    : Colors.redAccent,
                                fontWeight: FontWeight.bold,
                              ),
                            )),
                            DataCell(Text(_formatRatio(r.marginRatio))),
                            DataCell(Text('${r.traineesCount}')),
                            DataCell(r.hasTrainerCost
                                ? const Text(
                                    'مسجّلة',
                                    style:
                                        TextStyle(color: AppColors.success),
                                  )
                                : _buildMissingCostBadge()),
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

  Widget _buildCurrencySummary(CohortContributionSummary summary) {
    final curr = summary.currency;
    final currencyLabel = curr == 'USD'
        ? 'الدولار الأمريكي (USD)'
        : curr == 'SYP'
            ? 'الليرة السورية (SYP)'
            : curr;
    final ratio = summary.weightedMarginRatio;

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
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
              const SizedBox(width: 8),
              Text(
                '${summary.cohortsCount} فوج',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12),
              ),
              if (summary.cohortsWithoutTrainerCost > 0) ...[
                const SizedBox(width: 8),
                Text(
                  '(${summary.cohortsWithoutTrainerCost} بلا أتعاب مسجّلة)',
                  style: const TextStyle(
                      color: Colors.orangeAccent, fontSize: 12),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  title: 'الإيراد المكتسب (Earned)',
                  value: _formatMoney(summary.earnedRevenue, curr),
                  icon: Icons.check_circle_outline_rounded,
                  color: Colors.greenAccent,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricCard(
                  title: 'أتعاب المدرب (Trainer Cost)',
                  value: _formatMoney(summary.trainerCost, curr),
                  icon: Icons.price_check_rounded,
                  color: Colors.orangeAccent,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricCard(
                  title: 'هامش المساهمة (Contribution)',
                  value: _formatMoney(summary.contributionMargin, curr),
                  icon: Icons.account_balance_wallet_outlined,
                  color: summary.contributionMargin >= 0
                      ? AppColors.gold
                      : Colors.redAccent,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricCard(
                  title: 'نسبة الهامش المرجّحة (Σهامش/Σمكتسب)',
                  value: _formatRatio(ratio),
                  icon: Icons.percent_rounded,
                  color: (ratio ?? 0) >= 0 ? AppColors.gold : Colors.redAccent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
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
            value,
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

  Widget _buildMissingCostBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.orangeAccent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.5)),
      ),
      child: const Text(
        'لا توجد أتعاب مسجّلة',
        style: TextStyle(
          color: Colors.orangeAccent,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Future<void> _exportCsv(List<CohortContributionRow> rows) async {
    final csvRows = <List<dynamic>>[
      [
        'الفوج',
        'الدورة',
        'العملة',
        'الإيراد المكتسب',
        'أتعاب المدرب',
        'هامش المساهمة',
        'نسبة الهامش',
        'عدد المتدربين',
        'هل توجد أتعاب مسجّلة',
      ],
      ...rows.map((r) => [
            r.cohortName,
            r.courseName,
            r.currency,
            r.earnedRevenue,
            r.trainerCost,
            r.contributionMargin,
            r.marginRatio == null
                ? ''
                : '${(r.marginRatio! * 100).toStringAsFixed(2)}%',
            r.traineesCount,
            r.hasTrainerCost ? 'نعم' : 'لا',
          ]),
    ];

    final dateStr = DateFormat('yyyyMMdd')
        .format(ref.read(cohortContributionAsOfDateProvider));
    await widget.onExport(csvRows, 'cohort_contribution_report_$dateStr');
  }
}
