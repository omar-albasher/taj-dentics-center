import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/app_error_handler.dart';
import '../data/backup_repository.dart';

class ExportDataDialog extends ConsumerStatefulWidget {
  const ExportDataDialog({super.key});

  @override
  ConsumerState<ExportDataDialog> createState() => _ExportDataDialogState();
}

class _ExportDataDialogState extends ConsumerState<ExportDataDialog> {
  bool _isLoading = false;
  String? _errorMessage;
  Map<String, dynamic>? _exportedSummary;
  String? _exportVersion;
  String? _auditFilterApplied;

  Future<void> _handleExport() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final repo = ref.read(backupRepositoryProvider);
      final data = await repo.exportSystemData();

      // حفظ وتنزيل الملف
      await repo.saveExportToFile(data);

      final metadata = data['metadata'] as Map<String, dynamic>? ?? {};
      final counts = metadata['counts'] as Map<String, dynamic>? ?? {};
      final version = metadata['version']?.toString() ?? '2.0.0';
      final auditFilter = metadata['audit_filter_applied']?.toString();

      if (mounted) {
        setState(() {
          _isLoading = false;
          _exportedSummary = counts;
          _exportVersion = version;
          _auditFilterApplied = auditFilter;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = AppErrorHandler.friendlyMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.divider),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.gold.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.cloud_download_outlined,
                      color: AppColors.gold,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'تصدير شامل لبيانات النظام',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          'System Data Export v2.0.0 (JSON)',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppColors.textSecondary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),

              const SizedBox(height: 18),
              const Divider(color: AppColors.divider, height: 1),
              const SizedBox(height: 18),

              // Description
              const Text(
                'تقوم هذه الميزة بتجهيز وتنزيل ملف JSON شامل يحتوي على نسخة كاملة لبيانات العمل الحالية بالمركز والمخبر (27 جدولاً)، للحفظ والأرشفة المستقلة خارج السيرفر.',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 13,
                  color: AppColors.textPrimary,
                  height: 1.5,
                ),
              ),

              const SizedBox(height: 14),

              // Security Warning Box
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.shield_outlined, color: AppColors.warning, size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'تنبيه أمان وخصوصية: يحتوي هذا الملف على بيانات عمل حساسة (أرقام الهواتف، السجلات المالية، والملاحظات الأكاديمية). يُرجى حفظه في مكان آمن وعدم تداوله.',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          color: AppColors.warning,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Architecture Clarity Note
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.divider.withValues(alpha: 0.5)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, color: AppColors.textSecondary, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'الملف مخصص لأرشفة وحفظ بيانات العمل المستقلة. استعادة البنية الهيكلية الكاملة (Schema والسياسات والدوال) تتم مركزياً عبر منصة Supabase.',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11,
                          color: AppColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Success Summary State
              if (_exportedSummary != null) ...[
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.success.withValues(alpha: 0.4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.check_circle_outline, color: AppColors.success, size: 22),
                          const SizedBox(width: 8),
                          Text(
                            'تم تصدير وتنزيل الملف بنجاح! (الإصدار ${_exportVersion ?? '2.0.0'})',
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.success,
                            ),
                          ),
                        ],
                      ),
                      if (_auditFilterApplied != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          'تصفية التدقيق المطبقة: منذ ${_auditFilterApplied!.substring(0, 10)} (آخر 90 يوماً افتراضياً)',
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),

                      // Group 1: Academic
                      _SectionHeader(title: 'القطاع الأكاديمي والتدريب:'),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          _SummaryChip(label: 'المتدربون', count: _exportedSummary!['trainees']),
                          _SummaryChip(label: 'الكورسات', count: _exportedSummary!['courses']),
                          _SummaryChip(label: 'المجموعات', count: _exportedSummary!['cohorts']),
                          _SummaryChip(label: 'التسجيلات', count: _exportedSummary!['enrollments']),
                          _SummaryChip(label: 'الجلسات', count: _exportedSummary!['sessions']),
                          _SummaryChip(label: 'الحضور', count: _exportedSummary!['attendance']),
                          _SummaryChip(label: 'المواد التدريبية', count: _exportedSummary!['course_materials']),
                          _SummaryChip(label: 'قائمة الانتظار', count: _exportedSummary!['course_waitlist']),
                          _SummaryChip(label: 'الإحالات', count: _exportedSummary!['referrals']),
                        ],
                      ),

                      const SizedBox(height: 12),
                      // Group 2: Financial
                      _SectionHeader(title: 'السجلات والعمليات المالية:'),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          _SummaryChip(label: 'الدفعات', count: _exportedSummary!['payments']),
                          _SummaryChip(label: 'المصاريف', count: _exportedSummary!['expenses']),
                          _SummaryChip(label: 'الأقساط المجدولة', count: _exportedSummary!['installment_schedule']),
                          _SummaryChip(label: 'تخصيص الدفعات', count: _exportedSummary!['payment_allocations']),
                          _SummaryChip(label: 'الاستردادات', count: _exportedSummary!['payment_refunds']),
                          _SummaryChip(label: 'تعديلات الرسوم', count: _exportedSummary!['fee_adjustments']),
                          _SummaryChip(label: 'الانسحابات', count: _exportedSummary!['enrollment_withdrawals']),
                          _SummaryChip(label: 'الأهداف الشهرية', count: _exportedSummary!['monthly_targets']),
                        ],
                      ),

                      const SizedBox(height: 12),
                      // Group 3: Dental Lab
                      _SectionHeader(title: 'مخبر الأسنان:'),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          _SummaryChip(label: 'عملاء المخبر', count: _exportedSummary!['lab_clients']),
                          _SummaryChip(label: 'فواتير المخبر', count: _exportedSummary!['lab_invoices']),
                          _SummaryChip(label: 'بنود الفواتير', count: _exportedSummary!['lab_invoice_items']),
                          _SummaryChip(label: 'دفعات المخبر', count: _exportedSummary!['lab_payments']),
                          _SummaryChip(label: 'مصاريف المخبر', count: _exportedSummary!['lab_expenses']),
                        ],
                      ),

                      const SizedBox(height: 12),
                      // Group 4: System & Surveys & Audit
                      _SectionHeader(title: 'النظام والاستبيانات وسجل التدقيق:'),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          _SummaryChip(label: 'المستخدمون', count: _exportedSummary!['users']),
                          _SummaryChip(
                            label: 'سجل التدقيق (آخر 90 يوماً افتراضياً)',
                            count: _exportedSummary!['audit_log'],
                            isHighlighted: true,
                          ),
                          _SummaryChip(label: 'نماذج الاستبيان', count: _exportedSummary!['survey_templates']),
                          _SummaryChip(label: 'إرسال الاستبيانات', count: _exportedSummary!['survey_dispatches']),
                          _SummaryChip(label: 'ردود الاستبيان', count: _exportedSummary!['survey_responses']),
                        ],
                      ),
                    ],
                  ),
                ),
              ],

              // Error State
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.error),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: AppColors.error, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            color: AppColors.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (_exportedSummary == null) ...[
                    TextButton(
                      onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                      child: const Text(
                        'إلغاء',
                        style: TextStyle(fontFamily: 'Cairo', color: AppColors.textSecondary),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.gold,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: _isLoading ? null : _handleExport,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.black,
                              ),
                            )
                          : const Icon(Icons.download_rounded, size: 20),
                      label: Text(
                        _isLoading ? 'جارٍ التجهيز والتنزيل...' : 'تصدير وتنزيل الملف الآن',
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ] else ...[
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.surface,
                        foregroundColor: AppColors.textPrimary,
                        side: const BorderSide(color: AppColors.divider),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text(
                        'تم وإغلاق',
                        style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontFamily: 'Cairo',
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: AppColors.gold,
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final dynamic count;
  final bool isHighlighted;

  const _SummaryChip({
    required this.label,
    required this.count,
    this.isHighlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isHighlighted ? AppColors.gold.withValues(alpha: 0.15) : AppColors.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isHighlighted ? AppColors.gold : AppColors.divider.withValues(alpha: 0.6),
        ),
      ),
      child: Text(
        '$label: ${count ?? 0}',
        style: TextStyle(
          fontFamily: 'Cairo',
          fontSize: 11,
          color: isHighlighted ? AppColors.gold : AppColors.textPrimary,
          fontWeight: isHighlighted ? FontWeight.w700 : FontWeight.w600,
        ),
      ),
    );
  }
}
