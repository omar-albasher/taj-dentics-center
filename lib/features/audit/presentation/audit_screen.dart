import 'dart:convert';
import 'dart:typed_data';
import 'package:csv/csv.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/app_error_handler.dart';
import '../../../core/utils/app_formatters.dart';
import '../../../core/utils/responsive.dart';
import '../data/audit_repository.dart';

class AuditScreen extends ConsumerStatefulWidget {
  const AuditScreen({super.key});

  @override
  ConsumerState<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends ConsumerState<AuditScreen> {
  bool _isExporting = false;

  static const _tables = [
    'الكل',
    ...AuditRepository.defaultTrackedTables,
  ];

  static const _ops = ['الكل', 'INSERT', 'UPDATE', 'DELETE'];

  Future<void> _pickDateRange() async {
    final currentParams = ref.read(auditFilterParamsProvider);
    DateTimeRange? initialRange;
    if (currentParams.fromDate != null && currentParams.toDate != null) {
      initialRange = DateTimeRange(
        start: currentParams.fromDate!,
        end: currentParams.toDate!,
      );
    }

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2025, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: initialRange,
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
          child: child!,
        );
      },
    );

    if (picked != null) {
      ref.read(auditFilterParamsProvider.notifier).updateParams(
            (p) => p.copyWith(
              fromDate: picked.start,
              toDate: picked.end,
              page: 1,
            ),
          );
    }
  }

  void _clearDateRange() {
    ref.read(auditFilterParamsProvider.notifier).updateParams(
          (p) => p.copyWith(
            clearFromDate: true,
            clearToDate: true,
            page: 1,
          ),
        );
  }

  Future<void> _exportCsv() async {
    setState(() => _isExporting = true);
    try {
      final repo = ref.read(auditRepositoryProvider);
      final params = ref.read(auditFilterParamsProvider);
      final logs = await repo.fetchLogsForExport(params, maxLimit: 5000);

      if (logs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('لا توجد سجلات تطابق الفلتر للتصدير',
                  style: TextStyle(fontFamily: 'Cairo')),
              backgroundColor: AppColors.warning,
            ),
          );
        }
        return;
      }

      final csvRows = [
        [
          'ID',
          'الجدول',
          'العملية',
          'المعرف',
          'التاريخ والوقت',
          'اسم الفاعل',
          'بريد الفاعل',
          'مصدر الفاعل',
          'دور الفاعل',
        ],
        ...logs.map((l) {
          final user = l['users'] as Map<String, dynamic>?;
          return [
            l['id'],
            l['table_name'],
            l['operation'],
            l['record_id'],
            l['performed_at'],
            user?['full_name'] ?? 'النظام',
            user?['email'] ?? '',
            l['actor_source'] ?? '',
            l['actor_role'] ?? '',
          ];
        }),
      ];

      final csv = '\uFEFF${const ListToCsvConverter().convert(csvRows)}';
      final bytes = utf8.encode(csv);
      final fileName =
          'audit_export_${DateTime.now().toIso8601String().substring(0, 10)}';

      await FileSaver.instance.saveFile(
        name: fileName,
        bytes: Uint8List.fromList(bytes),
        ext: 'csv',
        mimeType: MimeType.csv,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم تصدير ${logs.length} سجلاً بنجاح (سقف التصدير: 5000 سجل)',
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppErrorHandler.friendlyMessage(e),
                style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final params = ref.watch(auditFilterParamsProvider);
    final auditAsync = ref.watch(auditLogsPaginatedProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Padding(
        padding: EdgeInsets.all(Responsive.spacing(context, 24)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title & Actions Bar
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
                // Date Range Button
                OutlinedButton.icon(
                  onPressed: _pickDateRange,
                  icon: const Icon(Icons.date_range, color: AppColors.gold, size: 18),
                  label: Text(
                    params.fromDate != null && params.toDate != null
                        ? '${AppFormatters.dateOnly.format(params.fromDate!)} - ${AppFormatters.dateOnly.format(params.toDate!)}'
                        : 'تحديد الفترة',
                    style: const TextStyle(
                      color: AppColors.gold,
                      fontFamily: 'Cairo',
                      fontSize: 12,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.gold),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                if (params.fromDate != null) ...[
                  const SizedBox(width: 6),
                  IconButton(
                    icon: const Icon(Icons.clear, color: AppColors.error, size: 18),
                    tooltip: 'إلغاء فلتر التاريخ',
                    onPressed: _clearDateRange,
                  ),
                ],
                const SizedBox(width: 12),
                // CSV Export Button
                OutlinedButton.icon(
                  onPressed: _isExporting ? null : _exportCsv,
                  icon: _isExporting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.gold,
                          ),
                        )
                      : const Icon(Icons.download, color: AppColors.gold, size: 18),
                  label: const Text(
                    'تصدير CSV',
                    style: TextStyle(
                      color: AppColors.gold,
                      fontFamily: 'Cairo',
                      fontSize: 12,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.gold),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Refresh Button
                IconButton(
                  icon: const Icon(Icons.refresh, color: AppColors.gold),
                  tooltip: 'تحديث',
                  onPressed: () => ref.invalidate(auditLogsPaginatedProvider),
                ),
              ],
            ),

            SizedBox(height: Responsive.spacing(context, 16)),

            // Filter Chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _FilterChips(
                    label: 'الجدول:',
                    options: _tables,
                    selected: params.tableName ?? 'الكل',
                    onSelected: (v) {
                      ref.read(auditFilterParamsProvider.notifier).updateParams(
                            (p) => p.copyWith(
                              tableName: v == 'الكل' ? '' : v,
                              page: 1,
                            ),
                          );
                    },
                  ),
                  SizedBox(width: Responsive.spacing(context, 20)),
                  _FilterChips(
                    label: 'العملية:',
                    options: _ops,
                    selected: params.operation ?? 'الكل',
                    onSelected: (v) {
                      ref.read(auditFilterParamsProvider.notifier).updateParams(
                            (p) => p.copyWith(
                              operation: v == 'الكل' ? '' : v,
                              page: 1,
                            ),
                          );
                    },
                  ),
                ],
              ),
            ),

            SizedBox(height: Responsive.spacing(context, 14)),

            // Content Area
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
                      Text(
                        AppErrorHandler.friendlyMessage(e),
                        style: const TextStyle(
                          color: AppColors.error,
                          fontFamily: 'Cairo',
                        ),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: () =>
                            ref.invalidate(auditLogsPaginatedProvider),
                        child: const Text('إعادة المحاولة',
                            style: TextStyle(fontFamily: 'Cairo')),
                      ),
                    ],
                  ),
                ),
                data: (result) {
                  final logs = result.logs;

                  if (logs.isEmpty) {
                    return Center(
                      child: Text(
                        'لا توجد سجلات تطابق الفلتر المحدد',
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
                      // Status / Count Bar
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Text(
                              'إجمالي السجلات: ${result.totalCount}',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontFamily: 'Cairo',
                                fontSize: 12,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              'صفحة ${result.currentPage} من ${result.totalPages == 0 ? 1 : result.totalPages}',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontFamily: 'Cairo',
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Logs List
                      Expanded(
                        child: ListView.separated(
                          itemCount: logs.length,
                          separatorBuilder: (_, __) =>
                              SizedBox(height: Responsive.spacing(context, 8)),
                          itemBuilder: (context, index) {
                            final log = logs[index];
                            final op = log['operation'] as String? ?? '';
                            final date =
                                DateTime.tryParse(log['performed_at'] ?? '');
                            final user =
                                log['users'] as Map<String, dynamic>?;
                            final userName =
                                user?['full_name'] ?? 'النظام';
                            final actorSource =
                                log['actor_source'] as String? ?? 'system';
                            final actorRole =
                                log['actor_role'] as String?;

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
                              padding: EdgeInsets.all(
                                  Responsive.spacing(context, 14)),
                              decoration: BoxDecoration(
                                color: AppColors.cardBg,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                    color: opColor.withValues(alpha: 0.2)),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color: opColor.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child:
                                        Icon(opIcon, color: opColor, size: 20),
                                  ),
                                  SizedBox(
                                      width: Responsive.spacing(context, 12)),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            // Operation Badge
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 2),
                                              decoration: BoxDecoration(
                                                color: opColor
                                                    .withValues(alpha: 0.15),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                op,
                                                style: TextStyle(
                                                  color: opColor,
                                                  fontFamily: 'Cairo',
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                            SizedBox(
                                                width: Responsive.spacing(
                                                    context, 8)),
                                            // Table Name
                                            Text(
                                              log['table_name'] ?? '',
                                              style: TextStyle(
                                                fontSize:
                                                    Responsive.fontSize(
                                                        context, 13),
                                                fontWeight: FontWeight.w700,
                                                color: AppColors.textPrimary,
                                                fontFamily: 'Cairo',
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            // Actor Source Badge
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2),
                                              decoration: BoxDecoration(
                                                color: AppColors.surface,
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                                border: Border.all(
                                                  color: AppColors.divider,
                                                ),
                                              ),
                                              child: Text(
                                                'المصدر: $actorSource',
                                                style: const TextStyle(
                                                  fontSize: 10,
                                                  fontFamily: 'Cairo',
                                                  color: AppColors
                                                      .textSecondary,
                                                ),
                                              ),
                                            ),
                                            if (actorRole != null &&
                                                actorRole.isNotEmpty) ...[
                                              const SizedBox(width: 6),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: AppColors.gold
                                                      .withValues(alpha: 0.1),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                  border: Border.all(
                                                    color: AppColors.gold
                                                        .withValues(alpha: 0.4),
                                                  ),
                                                ),
                                                child: Text(
                                                  actorRole,
                                                  style: const TextStyle(
                                                    fontSize: 10,
                                                    fontFamily: 'Cairo',
                                                    color: AppColors.gold,
                                                    fontWeight:
                                                        FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        SizedBox(
                                            height:
                                                Responsive.spacing(context, 4)),
                                        Text(
                                          'بواسطة: $userName',
                                          style: TextStyle(
                                            fontSize: Responsive.fontSize(
                                                context, 12),
                                            color: AppColors.textSecondary,
                                            fontFamily: 'Cairo',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (date != null)
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          AppFormatters.dateOnly.format(date),
                                          style: TextStyle(
                                            fontSize: Responsive.fontSize(
                                                context, 11),
                                            color: AppColors.textSecondary,
                                            fontFamily: 'Cairo',
                                          ),
                                        ),
                                        Text(
                                          AppFormatters.timeOnly.format(date),
                                          style: TextStyle(
                                            fontSize: Responsive.fontSize(
                                                context, 13),
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.textPrimary,
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

                      // Pagination Controls
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            OutlinedButton.icon(
                              onPressed: result.hasPrevPage
                                  ? () {
                                      ref
                                          .read(
                                              auditFilterParamsProvider.notifier)
                                          .updateParams(
                                            (p) =>
                                                p.copyWith(page: p.page - 1),
                                          );
                                    }
                                  : null,
                              icon: const Icon(Icons.arrow_forward_ios,
                                  size: 14),
                              label: const Text('السابق',
                                  style: TextStyle(fontFamily: 'Cairo')),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: AppColors.gold),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: Text(
                                '${result.currentPage} / ${result.totalPages == 0 ? 1 : result.totalPages}',
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: result.hasNextPage
                                  ? () {
                                      ref
                                          .read(
                                              auditFilterParamsProvider.notifier)
                                          .updateParams(
                                            (p) =>
                                                p.copyWith(page: p.page + 1),
                                          );
                                    }
                                  : null,
                              icon: const Icon(Icons.arrow_back_ios, size: 14),
                              label: const Text('التالي',
                                  style: TextStyle(fontFamily: 'Cairo')),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: AppColors.gold),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
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
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontFamily: 'Cairo',
            fontSize: 12,
          ),
        ),
        const SizedBox(width: 8),
        ...options.map((o) {
          final isSelected = (selected.isEmpty && o == 'الكل') || selected == o;
          return Padding(
            padding: const EdgeInsets.only(left: 6),
            child: GestureDetector(
              onTap: () => onSelected(o),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.gold.withValues(alpha: 0.2)
                      : AppColors.cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected ? AppColors.gold : AppColors.divider,
                  ),
                ),
                child: Text(
                  o,
                  style: TextStyle(
                    color: isSelected
                        ? AppColors.gold
                        : AppColors.textSecondary,
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    fontWeight:
                        isSelected ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}
