import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/responsive.dart';

final auditLogProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final response = await Supabase.instance.client.from('audit_log').select('''
        *,
        users!audit_log_performed_by_fkey(full_name)
      ''').order('performed_at', ascending: false).limit(100);
  return List<Map<String, dynamic>>.from(response);
});

class AuditScreen extends ConsumerStatefulWidget {
  const AuditScreen({super.key});

  @override
  ConsumerState<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends ConsumerState<AuditScreen> {
  String _filterTable = 'الكل';
  String _filterOp = 'الكل';

  static const _tables = [
    'الكل',
    'payments',
    'enrollments',
    'attendance',
    'expenses',
    'sessions'
  ];
  static const _ops = ['الكل', 'INSERT', 'UPDATE', 'DELETE'];

  @override
  Widget build(BuildContext context) {
    final auditAsync = ref.watch(auditLogProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Padding(
        padding: EdgeInsets.all(Responsive.spacing(context, 24)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'سجل التدقيق',
                  style: TextStyle(
                    fontSize: Responsive.fontSize(context, 28),
                    fontWeight: FontWeight.w900,
                    color: AppColors.gold,
                    fontFamily: 'Cairo',
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh, color: AppColors.gold),
                  onPressed: () => ref.invalidate(auditLogProvider),
                ),
              ],
            ),

            SizedBox(height: Responsive.spacing(context, 16)),

            // Filters
            Row(
              children: [
                _FilterChips(
                  label: 'الجدول:',
                  options: _tables,
                  selected: _filterTable,
                  onSelected: (v) => setState(() => _filterTable = v),
                ),
                SizedBox(width: Responsive.spacing(context, 16)),
                _FilterChips(
                  label: 'العملية:',
                  options: _ops,
                  selected: _filterOp,
                  onSelected: (v) => setState(() => _filterOp = v),
                ),
              ],
            ),

            SizedBox(height: Responsive.spacing(context, 16)),

            Expanded(
              child: auditAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(color: AppColors.gold),
                ),
                error: (e, _) => Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline,
                          color: AppColors.error, size: 48),
                      const SizedBox(height: 16),
                      Text('خطأ: $e',
                          style: const TextStyle(
                              color: AppColors.error, fontFamily: 'Cairo')),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: () => ref.invalidate(auditLogProvider),
                        child: const Text('إعادة المحاولة',
                            style: TextStyle(fontFamily: 'Cairo')),
                      ),
                    ],
                  ),
                ),
                data: (logs) {
                  final filtered = logs.where((log) {
                    final tableMatch = _filterTable == 'الكل' ||
                        log['table_name'] == _filterTable;
                    final opMatch =
                        _filterOp == 'الكل' || log['operation'] == _filterOp;
                    return tableMatch && opMatch;
                  }).toList();

                  if (filtered.isEmpty) {
                    return Center(
                      child: Text('لا توجد سجلات',
                          style: TextStyle(
                              color: AppColors.textSecondary,
                              fontFamily: 'Cairo',
                              fontSize: Responsive.fontSize(context, 16))),
                    );
                  }

                  return ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) =>
                        SizedBox(height: Responsive.spacing(context, 8)),
                    itemBuilder: (context, index) {
                      final log = filtered[index];
                      final op = log['operation'] as String? ?? '';
                      final date = DateTime.tryParse(log['performed_at'] ?? '');
                      final user = log['users'] as Map<String, dynamic>?;
                      final userName = user?['full_name'] ?? 'النظام';

                      Color opColor;
                      IconData opIcon;
                      switch (op) {
                        case 'INSERT':
                          opColor = AppColors.success;
                          opIcon = Icons.add_circle_outline;
                          break;
                        case 'UPDATE':
                          opColor = AppColors.warning;
                          opIcon = Icons.edit_outlined;
                          break;
                        case 'DELETE':
                          opColor = AppColors.error;
                          opIcon = Icons.delete_outline;
                          break;
                        default:
                          opColor = AppColors.textSecondary;
                          opIcon = Icons.info_outline;
                      }

                      return Container(
                        padding:
                            EdgeInsets.all(Responsive.spacing(context, 16)),
                        decoration: BoxDecoration(
                          color: AppColors.cardBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: opColor.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: opColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(opIcon, color: opColor, size: 20),
                            ),
                            SizedBox(width: Responsive.spacing(context, 12)),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: opColor.withValues(alpha: 0.15),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Text(op,
                                            style: TextStyle(
                                                color: opColor,
                                                fontFamily: 'Cairo',
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700)),
                                      ),
                                      SizedBox(
                                          width:
                                              Responsive.spacing(context, 8)),
                                      Text(
                                        log['table_name'] ?? '',
                                        style: TextStyle(
                                            fontSize: Responsive.fontSize(
                                                context, 13),
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.textPrimary,
                                            fontFamily: 'Cairo'),
                                      ),
                                    ],
                                  ),
                                  SizedBox(
                                      height: Responsive.spacing(context, 4)),
                                  Text(
                                    'بواسطة: $userName',
                                    style: TextStyle(
                                        fontSize:
                                            Responsive.fontSize(context, 12),
                                        color: AppColors.textSecondary,
                                        fontFamily: 'Cairo'),
                                  ),
                                ],
                              ),
                            ),
                            if (date != null)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    DateFormat('yyyy/MM/dd').format(date),
                                    style: TextStyle(
                                        fontSize:
                                            Responsive.fontSize(context, 11),
                                        color: AppColors.textSecondary,
                                        fontFamily: 'Cairo'),
                                  ),
                                  Text(
                                    DateFormat('HH:mm').format(date),
                                    style: TextStyle(
                                        fontSize:
                                            Responsive.fontSize(context, 13),
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.textPrimary,
                                        fontFamily: 'Cairo'),
                                  ),
                                ],
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
        ),
      ),
    );
  }
}

class _FilterChips extends StatelessWidget {
  final String label;
  final List<String> options;
  final String selected;
  final Function(String) onSelected;

  const _FilterChips({
    required this.label,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label,
            style: const TextStyle(
                color: AppColors.textSecondary, fontFamily: 'Cairo')),
        const SizedBox(width: 8),
        ...options.map((o) => Padding(
              padding: const EdgeInsets.only(left: 6),
              child: GestureDetector(
                onTap: () => onSelected(o),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: selected == o
                        ? AppColors.gold.withValues(alpha: 0.2)
                        : AppColors.cardBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selected == o ? AppColors.gold : AppColors.divider,
                    ),
                  ),
                  child: Text(o,
                      style: TextStyle(
                          color: selected == o
                              ? AppColors.gold
                              : AppColors.textSecondary,
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          fontWeight: selected == o
                              ? FontWeight.w700
                              : FontWeight.w400)),
                ),
              ),
            )),
      ],
    );
  }
}
