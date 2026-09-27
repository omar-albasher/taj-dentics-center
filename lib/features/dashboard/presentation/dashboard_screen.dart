import 'package:admin_dashboard/core/constants/app_colors.dart';
import 'package:admin_dashboard/core/utils/responsive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../data/dashboard_repository.dart';
import 'package:admin_dashboard/core/widgets/app_error_widget.dart';

// غيّر StatefulWidget → ConsumerWidget
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kpisAsync = ref.watch(kpisProvider);
    final overdueAsync = ref.watch(overdueProvider);
    final isDesktop = Responsive.isDesktop(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        padding: EdgeInsets.all(Responsive.spacing(context, 24)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'لوحة التحكم',
                      style: TextStyle(
                        fontSize: Responsive.fontSize(context, 28),
                        fontWeight: FontWeight.w900,
                        color: AppColors.gold,
                        fontFamily: 'Cairo',
                      ),
                    ),
                    Text(
                      DateFormat('EEEE، d MMMM yyyy', 'ar')
                          .format(DateTime.now()),
                      style: TextStyle(
                        fontSize: Responsive.fontSize(context, 14),
                        color: AppColors.textSecondary,
                        fontFamily: 'Cairo',
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh, color: AppColors.gold),
                  onPressed: () {
                    ref.invalidate(kpisProvider);
                    ref.invalidate(overdueProvider);
                  },
                ),
              ],
            ),

            SizedBox(height: Responsive.spacing(context, 24)),

            kpisAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.gold),
              ),
              error: (e, _) => AppErrorWidget(
                message: 'خطأ: $e',
                onRetry: () => ref.invalidate(kpisProvider),
              ),
              data: (data) {
                final fmt = NumberFormat('#,###');
                double _v(String key) => (data[key] as num?)?.toDouble() ?? 0.0;

                final paidSYP = _v('total_paid_syp');
                final paidUSD = _v('total_paid_usd');
                final profitSYP = _v('net_profit_syp');
                final profitUSD = _v('net_profit_usd');
                final balanceSYP = _v('total_balance_syp');
                final balanceUSD = _v('total_balance_usd');

                final kpis = [
                  _KpiData(
                    title: 'إجمالي المتدربين',
                    value: '${data['total_trainees'] ?? 0}',
                    subtitle: 'متدرب مسجل',
                    icon: Icons.people,
                    color: AppColors.gold,
                  ),
                  _KpiData(
                    title: 'الإيرادات',
                    value: '${fmt.format(paidSYP.toInt())} ل.س',
                    subtitle: '\$ ${fmt.format(paidUSD.toInt())}',
                    icon: Icons.trending_up,
                    color: AppColors.success,
                  ),
                  _KpiData(
                    title: 'صافي الربح',
                    value: '${fmt.format(profitSYP.toInt())} ل.س',
                    subtitle: '\$ ${fmt.format(profitUSD.toInt())}',
                    icon: Icons.account_balance,
                    color: AppColors.darkGreen,
                  ),
                  _KpiData(
                    title: 'المستحقات',
                    value: '${fmt.format(balanceSYP.toInt())} ل.س',
                    subtitle:
                        '\$ ${fmt.format(balanceUSD.toInt())} (${data['partial_count'] ?? 0} جزئي • ${data['unpaid_count'] ?? 0} غير مدفوع)',
                    icon: Icons.warning_amber,
                    color: AppColors.warning,
                  ),
                ];

                return GridView.count(
                  crossAxisCount: isDesktop ? 4 : 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: Responsive.spacing(context, 16),
                  mainAxisSpacing: Responsive.spacing(context, 16),
                  childAspectRatio: isDesktop ? 1.5 : 0.5,
                  children: kpis.map((k) => _KpiCard(data: k)).toList(),
                );
              },
            ),

            SizedBox(height: Responsive.spacing(context, 24)),

            // Overdue
            Text(
              'المتأخرون بالدفع',
              style: TextStyle(
                fontSize: Responsive.fontSize(context, 18),
                fontWeight: FontWeight.w700,
                color: AppColors.gold,
                fontFamily: 'Cairo',
              ),
            ),
            SizedBox(height: Responsive.spacing(context, 12)),

            overdueAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.gold),
              ),
              error: (e, _) => AppErrorWidget(
                message: 'خطأ: $e',
                onRetry: () => ref.invalidate(overdueProvider),
              ),
              data: (list) {
                if (list.isEmpty) {
                  return Container(
                    padding: EdgeInsets.all(Responsive.spacing(context, 24)),
                    decoration: BoxDecoration(
                      color: AppColors.cardBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: const Center(
                      child: Text(
                        '🎉 لا توجد مستحقات متأخرة',
                        style: TextStyle(
                          color: AppColors.success,
                          fontFamily: 'Cairo',
                          fontSize: 16,
                        ),
                      ),
                    ),
                  );
                }

                return Container(
                  decoration: BoxDecoration(
                    color: AppColors.cardBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Column(
                    children: list.asMap().entries.map((entry) {
                      final i = entry.key;
                      final e = entry.value;
                      return Column(
                        children: [
                          ListTile(
                            leading: CircleAvatar(
                              backgroundColor:
                                  AppColors.error.withValues(alpha: 0.15),
                              child: Text(
                                '${i + 1}',
                                style: const TextStyle(
                                  color: AppColors.error,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                            ),
                            title: Text(
                              e['trainee_name'] ?? '',
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              e['course_name'] ?? '',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontFamily: 'Cairo',
                              ),
                            ),
                            trailing: Text(
                              '${_formatAmount((e['balance_due'] as num?)?.toDouble() ?? 0)} ل.س',
                              style: const TextStyle(
                                color: AppColors.error,
                                fontWeight: FontWeight.w700,
                                fontFamily: 'Cairo',
                              ),
                            ),
                          ),
                          if (i < list.length - 1)
                            const Divider(color: AppColors.divider, height: 1),
                        ],
                      );
                    }).toList(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String _formatAmount(double amount) =>
      NumberFormat('#,###').format(amount.toInt());
}



class _KpiData {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _KpiData({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });
}

class _KpiCard extends StatelessWidget {
  final _KpiData data;
  const _KpiCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(Responsive.spacing(context, 16)),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: data.color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(Responsive.spacing(context, 8)),
            decoration: BoxDecoration(
              color: data.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              data.icon,
              color: data.color,
              size: Responsive.iconSize(context, 18),
            ),
          ),
          const Spacer(),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              data.value,
              style: TextStyle(
                fontSize: Responsive.fontSize(context, 20),
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary,
                fontFamily: 'Cairo',
              ),
            ),
          ),
          Text(
            data.title,
            style: TextStyle(
              fontSize: Responsive.fontSize(context, 12),
              fontWeight: FontWeight.w700,
              color: data.color,
              fontFamily: 'Cairo',
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            data.subtitle,
            style: TextStyle(
              fontSize: Responsive.fontSize(context, 10),
              color: AppColors.textSecondary,
              fontFamily: 'Cairo',
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
