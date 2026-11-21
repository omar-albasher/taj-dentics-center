import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/app_error_handler.dart';
import '../../../../core/utils/app_formatters.dart';
import '../../data/compensation_repository.dart';
import '../../domain/compensation_models.dart';

class GenerateDuesDialog extends ConsumerStatefulWidget {
  final DateTime initialMonth;
  final List<CohortTrainerRate> cohorts;

  const GenerateDuesDialog({
    super.key,
    required this.initialMonth,
    required this.cohorts,
  });

  static Future<bool?> show(
    BuildContext context, {
    required DateTime initialMonth,
    required List<CohortTrainerRate> cohorts,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => GenerateDuesDialog(
        initialMonth: initialMonth,
        cohorts: cohorts,
      ),
    );
  }

  @override
  ConsumerState<GenerateDuesDialog> createState() => _GenerateDuesDialogState();
}

class _GenerateDuesDialogState extends ConsumerState<GenerateDuesDialog> {
  CohortTrainerRate? _selectedCohort;
  late DateTime _selectedMonth;
  bool _isLoading = false;
  String? _errorMessage;
  int? _generatedCount;

  @override
  void initState() {
    super.initState();
    _selectedMonth = firstOfMonth(widget.initialMonth);
    if (widget.cohorts.isNotEmpty) {
      _selectedCohort = widget.cohorts.first;
    }
  }

  Future<void> _submit() async {
    if (_selectedCohort == null) {
      setState(() => _errorMessage = 'يرجى اختيار الدفعة التدريبية');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _generatedCount = null;
    });

    try {
      final count = await ref
          .read(compensationRepositoryProvider)
          .generateTrainerDues(_selectedCohort!.cohortId, _selectedMonth);

      ref.invalidate(trainerDuesProvider(_selectedMonth));
      if (mounted) {
        setState(() {
          _generatedCount = count;
          _isLoading = false;
        });
        if (count > 0) {
          Future.delayed(const Duration(milliseconds: 700), () {
            if (mounted) Navigator.of(context).pop(true);
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = AppErrorHandler.friendlyMessage(e);
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        backgroundColor: AppColors.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.gold.withAlpha(30),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.calculate_outlined,
                          color: AppColors.gold, size: 24),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'توليد مستحقات أتعاب المدرب',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo',
                            ),
                          ),
                          Text(
                            'حساب الأتعاب من مقبوضات الدفعة خلال الشهر المحدد',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                              fontFamily: 'Cairo',
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close,
                          color: AppColors.textSecondary),
                      onPressed:
                          _isLoading ? null : () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(color: AppColors.divider),
                const SizedBox(height: 16),

                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.error.withAlpha(30),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.error),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline,
                            color: AppColors.error, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              color: AppColors.error,
                              fontSize: 12,
                              fontFamily: 'Cairo',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                if (_generatedCount != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.success.withAlpha(30),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.success),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_outline,
                            color: AppColors.success, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _generatedCount! > 0
                                ? 'تم توليد $_generatedCount بند مستحقات بنجاح!'
                                : 'لم يتم العثور على مقبوضات جديدة غير محسوبة لهذه الدفعة في الشهر المحدد.',
                            style: const TextStyle(
                              color: AppColors.success,
                              fontSize: 12,
                              fontFamily: 'Cairo',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Month selector display
                const Text(
                  'شهر الاستحقاق',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_month,
                          color: AppColors.gold, size: 20),
                      const SizedBox(width: 10),
                      Text(
                        AppFormatters.monthYearAr.format(_selectedMonth),
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Cohort selector
                const Text(
                  'الدفعة التدريبية',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<CohortTrainerRate>(
                  initialValue: _selectedCohort,
                  dropdownColor: AppColors.surface,
                  items: widget.cohorts.map((c) {
                    return DropdownMenuItem(
                      value: c,
                      child: Text(
                        '${c.courseName} - ${c.cohortName} (${c.trainerName.isEmpty ? "بدون مدرب" : c.trainerName})',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontFamily: 'Cairo',
                          fontSize: 13,
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: _isLoading
                      ? null
                      : (val) => setState(() => _selectedCohort = val),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppColors.surface,
                    prefixIcon: const Icon(Icons.group_work_outlined,
                        color: AppColors.gold, size: 20),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.divider),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.divider),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          const BorderSide(color: AppColors.gold, width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, size: 16, color: AppColors.gold),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'تقوم العملية بجمع كل مقبوضات الطلاب للدفعة في الشهر، وتطبيق النسبة المئوية المحددة للدفعة لتوليد مستحق المدرب بدقة.',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontFamily: 'Cairo',
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed:
                          _isLoading ? null : () => Navigator.pop(context),
                      child: const Text(
                        'إغلاق',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.gold,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.black,
                              ),
                            )
                          : const Text(
                              'توليد المستحقات',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
