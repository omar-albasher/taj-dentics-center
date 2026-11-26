import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' as intl;
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/app_error_handler.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../core/widgets/app_error_widget.dart';
import '../data/reports_repository.dart';
import '../domain/accounting_period_models.dart';

class AccountingPeriodsScreen extends ConsumerStatefulWidget {
  const AccountingPeriodsScreen({super.key});

  @override
  ConsumerState<AccountingPeriodsScreen> createState() =>
      _AccountingPeriodsScreenState();
}

class _AccountingPeriodsScreenState
    extends ConsumerState<AccountingPeriodsScreen> {
  bool _isActionLoading = false;

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
        ),
        backgroundColor: isError ? AppColors.error : AppColors.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _handleClosePeriodDialog([DateTime? initialMonth]) async {
    final now = DateTime.now();
    // Default to initialMonth or previous month
    var selectedMonth = initialMonth ?? DateTime(now.year, now.month - 1, 1);
    var isForce = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final y = selectedMonth.year;
            final m = selectedMonth.month.toString().padLeft(2, '0');
            final monthStr = '$y-$m';

            return AlertDialog(
              backgroundColor: AppColors.cardBg,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: AppColors.divider),
              ),
              title: const Row(
                children: [
                  Icon(Icons.lock_outline, color: AppColors.gold, size: 24),
                  SizedBox(width: 8),
                  Text(
                    'إقفال فترة محاسبية',
                    style: TextStyle(
                      color: AppColors.gold,
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 440,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'اختر الشهر المراد إقفاله. سيؤدي الإقفال إلى منع أي تعديل أو إضافة أو حذف للحركات المالية التابعة لهذا الشهر.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Month Picker Row
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.calendar_month,
                            color: AppColors.gold,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'الشهر المحدد: $monthStr',
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: selectedMonth,
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2035),
                                helpText: 'اختر يوماً ضمن الشهر المطلوب إقفاله',
                              );
                              if (picked != null) {
                                setDialogState(() {
                                  selectedMonth =
                                      DateTime(picked.year, picked.month, 1);
                                });
                              }
                            },
                            child: const Text(
                              'تغيير',
                              style: TextStyle(
                                color: AppColors.gold,
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Force Toggle
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      activeColor: AppColors.gold,
                      checkColor: AppColors.background,
                      title: const Text(
                        'إقفال إجباري (Force Override)',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      subtitle: const Text(
                        'مطلوب إذا كان الشهر هو الشهر الجاري، أو لتجاوز فحص مسودات الرواتب والأتعاب غير المولدة.',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontFamily: 'Cairo',
                          fontSize: 11,
                        ),
                      ),
                      value: isForce,
                      onChanged: (val) {
                        setDialogState(() {
                          isForce = val ?? false;
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text(
                    'إلغاء',
                    style: TextStyle(color: AppColors.textSecondary, fontFamily: 'Cairo'),
                  ),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.lock, size: 16),
                  label: const Text(
                    'تأكيد الإقفال',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.gold,
                    foregroundColor: AppColors.background,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    await _executeClosePeriod(selectedMonth, force: isForce);
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _executeClosePeriod(DateTime month, {required bool force}) async {
    setState(() => _isActionLoading = true);
    try {
      final repo = ref.read(reportsRepositoryProvider);
      final res = await repo.closeAccountingPeriod(month, force: force);
      ref.invalidate(accountingPeriodsProvider);
      if (res.isAlreadyClosed) {
        _showSnackBar('الفترة ${res.periodMonth} مقفلة مسبقاً.');
      } else {
        _showSnackBar('تم إقفال الفترة ${res.periodMonth} بنجاح.');
      }
    } catch (e) {
      _showSnackBar(AppErrorHandler.friendlyMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  Future<void> _handleReopenDialog(AccountingPeriod period) async {
    final controller = TextEditingController();
    var currentLength = 0;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isValid = currentLength >= 10;

            return AlertDialog(
              backgroundColor: AppColors.cardBg,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: AppColors.divider),
              ),
              title: Row(
                children: [
                  const Icon(Icons.lock_open, color: AppColors.gold, size: 24),
                  const SizedBox(width: 8),
                  Text(
                    'إعادة فتح الفترة ${period.monthKey}',
                    style: const TextStyle(
                      color: AppColors.gold,
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 440,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'إعادة فتح فترة مقفلة هو إجراء استثنائي يتطلب مسوغاً واضحاً ومفصلاً. سيتم توثيق هذا الإجراء والمسوّغ في سجل التدقيق الأمني (Audit Log).',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: controller,
                      maxLines: 3,
                      onChanged: (val) {
                        setDialogState(() {
                          currentLength = val.trim().length;
                        });
                      },
                      decoration: InputDecoration(
                        labelText: 'سبب إعادة الفتح (10 أحرف على الأقل)',
                        labelStyle: const TextStyle(
                          color: AppColors.textSecondary,
                          fontFamily: 'Cairo',
                        ),
                        hintText: 'مثال: تصحيح قيد مصروف أتعاب مدرب تم إدخاله بالخطأ...',
                        hintStyle: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontFamily: 'Cairo',
                        ),
                        counterText: '$currentLength / 10 أحرف كحد أدنى',
                        counterStyle: TextStyle(
                          color: isValid ? AppColors.success : AppColors.error,
                          fontFamily: 'Cairo',
                          fontSize: 11,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: AppColors.divider),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: AppColors.gold),
                        ),
                        filled: true,
                        fillColor: AppColors.background,
                      ),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontFamily: 'Cairo',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text(
                    'إلغاء',
                    style: TextStyle(color: AppColors.textSecondary, fontFamily: 'Cairo'),
                  ),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text(
                    'تأكيد إعادة الفتح',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.warning,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: isValid
                      ? () async {
                          final reason = controller.text.trim();
                          Navigator.of(ctx).pop();
                          await _executeReopenPeriod(period.periodMonth, reason);
                        }
                      : null,
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _executeReopenPeriod(DateTime month, String reason) async {
    setState(() => _isActionLoading = true);
    try {
      final repo = ref.read(reportsRepositoryProvider);
      final res = await repo.reopenAccountingPeriod(month, reason);
      ref.invalidate(accountingPeriodsProvider);
      _showSnackBar(
        'تمت إعادة فتح الفترة ${res.periodMonth} بنجاح (المرة رقم ${res.reopenCount}).',
      );
    } catch (e) {
      _showSnackBar(AppErrorHandler.friendlyMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final periodsAsync = ref.watch(accountingPeriodsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.cardBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_forward_ios, color: AppColors.gold, size: 20),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'العودة',
        ),
        title: const Text(
          'إقفال الفترات المحاسبية (C7)',
          style: TextStyle(
            color: AppColors.gold,
            fontFamily: 'Cairo',
            fontWeight: FontWeight.w900,
            fontSize: 20,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.gold),
            onPressed: () => ref.invalidate(accountingPeriodsProvider),
            tooltip: 'تحديث البيانات',
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.add_moderator, size: 18),
              label: const Text(
                'إقفال فترة جديدة',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: AppColors.background,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              onPressed: _isActionLoading ? null : _handleClosePeriodDialog,
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Padding(
            padding: EdgeInsets.all(Responsive.spacing(context, 24)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Info Banner
                _buildInfoBanner(),
                const SizedBox(height: 20),
                // Main Content
                Expanded(
                  child: periodsAsync.when(
                    data: (periods) => _buildPeriodsList(periods),
                    loading: () => const Center(
                      child: CircularProgressIndicator(color: AppColors.gold),
                    ),
                    error: (err, stack) => AppErrorWidget(
                      message: AppErrorHandler.friendlyMessage(err),
                      onRetry: () => ref.invalidate(accountingPeriodsProvider),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_isActionLoading)
            Container(
              color: Colors.black.withValues(alpha: 0.3),
              child: const Center(
                child: CircularProgressIndicator(color: AppColors.gold),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
      ),
      child: const Row(
        children: [
          Icon(Icons.shield_outlined, color: AppColors.gold, size: 28),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'الحماية المحاسبية للفترات المغلقة',
                  style: TextStyle(
                    color: AppColors.gold,
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'عند إقفال أي شهر ميلادي، تُمنع فوراً أي إضافة أو تعديل أو حذف للحركات المالية (الدفعات، الاستردادات، المصاريف، أتعاب المدربين، ومسيرات الرواتب) الواقعة ضمن هذا الشهر، لضمان صحة ونزاهة القوائم والتقارير المالية التاريخية.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodsList(List<AccountingPeriod> periods) {
    if (periods.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lock_clock_outlined,
              size: 64,
              color: AppColors.textSecondary.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            const Text(
              'لا توجد فترات محاسبية مسجلة حتى الآن',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'يمكنك البدء بإقفال الشهور السابقة بالنقر على "إقفال فترة جديدة" أعلاه.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontFamily: 'Cairo',
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    final dateFormatter = intl.DateFormat('yyyy/MM/dd HH:mm');

    return Card(
      color: AppColors.cardBg,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.divider),
      ),
      child: ListView.separated(
        itemCount: periods.length,
        separatorBuilder: (_, __) => const Divider(color: AppColors.divider, height: 1),
        itemBuilder: (context, index) {
          final period = periods[index];
          final isClosed = period.isClosed;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              children: [
                // Icon & Month Name
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isClosed
                        ? AppColors.error.withValues(alpha: 0.15)
                        : AppColors.success.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isClosed ? Icons.lock : Icons.lock_open,
                    color: isClosed ? AppColors.error : AppColors.success,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 16),
                // Period Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            period.formattedArabic,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Status Badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: isClosed
                                  ? AppColors.error.withValues(alpha: 0.15)
                                  : AppColors.success.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isClosed
                                    ? AppColors.error.withValues(alpha: 0.4)
                                    : AppColors.success.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Text(
                              isClosed ? 'مغلقة' : 'مفتوحة',
                              style: TextStyle(
                                color: isClosed ? AppColors.error : AppColors.success,
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          if (period.reopenCount > 0) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.warning.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: AppColors.warning.withValues(alpha: 0.4),
                                ),
                              ),
                              child: Text(
                                'أعيد فتحها ${period.reopenCount} مرة',
                                style: const TextStyle(
                                  color: AppColors.warning,
                                  fontFamily: 'Cairo',
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Details string
                      if (isClosed && period.closedAt != null)
                        Text(
                          'تاريخ الإقفال: ${dateFormatter.format(period.closedAt!.toLocal())}',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontFamily: 'Cairo',
                            fontSize: 12,
                          ),
                        )
                      else if (!isClosed && period.reopenedAt != null)
                        Text(
                          'أعيد فتحها: ${dateFormatter.format(period.reopenedAt!.toLocal())} — المسوّغ: ${period.reopenReason ?? "غير محدد"}',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontFamily: 'Cairo',
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                // Actions
                if (isClosed)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.lock_open, size: 16),
                    label: const Text(
                      'إعادة فتح',
                      style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.warning,
                      side: const BorderSide(color: AppColors.warning),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: _isActionLoading
                        ? null
                        : () => _handleReopenDialog(period),
                  )
                else
                  ElevatedButton.icon(
                    icon: const Icon(Icons.lock, size: 16),
                    label: const Text(
                      'إعادة إقفال',
                      style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.gold,
                      foregroundColor: AppColors.background,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: _isActionLoading
                        ? null
                        : () => _handleClosePeriodDialog(period.periodMonth),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
