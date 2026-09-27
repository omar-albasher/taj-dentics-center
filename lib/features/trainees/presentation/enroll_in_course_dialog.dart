import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/responsive.dart';
import '../../courses/data/courses_repository.dart';

class EnrollInCourseDialog extends ConsumerStatefulWidget {
  final String traineeId;
  final String traineeName;
  final VoidCallback onEnrolled;

  const EnrollInCourseDialog({
    super.key,
    required this.traineeId,
    required this.traineeName,
    required this.onEnrolled,
  });

  @override
  ConsumerState<EnrollInCourseDialog> createState() =>
      _EnrollInCourseDialogState();
}

class _EnrollInCourseDialogState extends ConsumerState<EnrollInCourseDialog> {
  String? _selectedCohortId;
  final _priceCtrl = TextEditingController();
  final _discountCtrl = TextEditingController(text: '0');
  String _currency = 'SYP';
  bool _loading = false;

  @override
  void dispose() {
    _priceCtrl.dispose();
    _discountCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selectedCohortId == null || _priceCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى تعبئة الحقول الإلزامية'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      await ref.read(coursesRepositoryProvider).enrollTrainee(
            traineeId: widget.traineeId,
            cohortId: _selectedCohortId!,
            totalDue: double.parse(_priceCtrl.text),
            discountAmount: double.tryParse(_discountCtrl.text) ?? 0,
            currency: _currency,
          );

      if (!mounted) return;
      Navigator.pop(context);
      widget.onEnrolled();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تسجيل المتدرب بنجاح ✓'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ: $e'), backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cohortsAsync = ref.watch(allActiveCohortsProvider);

    return Dialog(
      backgroundColor: AppColors.cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: EdgeInsets.all(Responsive.spacing(context, 24)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.school, color: AppColors.gold),
                  SizedBox(width: Responsive.spacing(context, 8)),
                  Expanded(
                    child: Text(
                      'تسجيل بكورس — ${widget.traineeName}',
                      style: TextStyle(
                        fontSize: Responsive.fontSize(context, 16),
                        fontWeight: FontWeight.w700,
                        color: AppColors.gold,
                        fontFamily: 'Cairo',
                      ),
                    ),
                  ),
                  IconButton(
                    icon:
                        const Icon(Icons.close, color: AppColors.textSecondary),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(color: AppColors.divider),
              SizedBox(height: Responsive.spacing(context, 16)),

              // Cohort Dropdown
              cohortsAsync.when(
                loading: () =>
                    const CircularProgressIndicator(color: AppColors.gold),
                error: (e, _) => Text('خطأ: $e',
                    style: const TextStyle(
                        color: AppColors.error, fontFamily: 'Cairo')),
                data: (cohorts) {
                  if (cohorts.isEmpty) {
                    return Text(
                      'لا توجد مجموعات متاحة — أنشئ مجموعة من شاشة الكورسات أولاً',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontFamily: 'Cairo',
                        fontSize: Responsive.fontSize(context, 13),
                      ),
                    );
                  }

                  return DropdownButtonFormField<String>(
                    value: _selectedCohortId,
                    dropdownColor: AppColors.cardBg,
                    decoration: InputDecoration(
                      labelText: 'اختر الكورس / المجموعة *',
                      labelStyle: const TextStyle(
                          color: AppColors.textSecondary, fontFamily: 'Cairo'),
                      prefixIcon: const Icon(Icons.menu_book_outlined,
                          color: AppColors.gold),
                      filled: true,
                      fillColor: AppColors.surface,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: AppColors.divider)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: AppColors.divider)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                              color: AppColors.gold, width: 2)),
                    ),
                    items: cohorts.map((c) {
                      return DropdownMenuItem(
                        value: c['id'] as String,
                        child: Text(
                          '${c['course_name']} — ${c['name']}',
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontFamily: 'Cairo',
                              fontSize: 13),
                        ),
                      );
                    }).toList(),
                    onChanged: (v) {
                      setState(() {
                        _selectedCohortId = v;
                        final selected = cohorts.firstWhere((c) => c['id'] == v,
                            orElse: () => {});
                        if (selected.isNotEmpty) {
                          _priceCtrl.text =
                              (selected['price'] as double).toInt().toString();
                        }
                      });
                    },
                  );
                },
              ),

              SizedBox(height: Responsive.spacing(context, 12)),

              // Price + Currency
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _priceCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        labelText: 'السعر *',
                        labelStyle: const TextStyle(
                            color: AppColors.textSecondary,
                            fontFamily: 'Cairo'),
                        prefixIcon: const Icon(Icons.attach_money,
                            color: AppColors.gold),
                        filled: true,
                        fillColor: AppColors.surface,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: AppColors.divider)),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: AppColors.divider)),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                                color: AppColors.gold, width: 2)),
                      ),
                    ),
                  ),
                  SizedBox(width: Responsive.spacing(context, 12)),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _currency,
                      dropdownColor: AppColors.cardBg,
                      decoration: InputDecoration(
                        labelText: 'العملة',
                        labelStyle: const TextStyle(
                            color: AppColors.textSecondary,
                            fontFamily: 'Cairo'),
                        filled: true,
                        fillColor: AppColors.surface,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: AppColors.divider)),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: AppColors.divider)),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                                color: AppColors.gold, width: 2)),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'SYP',
                          child: Text('ل.س',
                              style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontFamily: 'Cairo')),
                        ),
                        DropdownMenuItem(
                          value: 'USD',
                          child: Text('\$',
                              style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontFamily: 'Cairo')),
                        ),
                      ],
                      onChanged: (v) => setState(() => _currency = v ?? 'SYP'),
                    ),
                  ),
                ],
              ),

              SizedBox(height: Responsive.spacing(context, 12)),

              // Discount
              TextField(
                controller: _discountCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  labelText: 'الخصم (اختياري)',
                  labelStyle: const TextStyle(
                      color: AppColors.textSecondary, fontFamily: 'Cairo'),
                  prefixIcon: const Icon(Icons.discount_outlined,
                      color: AppColors.gold),
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.divider)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.divider)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: AppColors.gold, width: 2)),
                ),
              ),

              SizedBox(height: Responsive.spacing(context, 24)),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                        side: const BorderSide(color: AppColors.divider),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('إلغاء',
                          style: TextStyle(fontFamily: 'Cairo')),
                    ),
                  ),
                  SizedBox(width: Responsive.spacing(context, 12)),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _loading ? null : _submit,
                      child: _loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.black, strokeWidth: 2))
                          : const Text('تسجيل',
                              style: TextStyle(fontFamily: 'Cairo')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
