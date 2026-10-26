import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/app_error_handler.dart';
import '../../../../core/utils/responsive.dart';
import '../../data/courses_repository.dart';
import '../../domain/cohort_model.dart';

class CohortCapacityDialog extends ConsumerStatefulWidget {
  final CohortModel cohort;

  const CohortCapacityDialog({super.key, required this.cohort});

  @override
  ConsumerState<CohortCapacityDialog> createState() =>
      _CohortCapacityDialogState();
}

class _CohortCapacityDialogState extends ConsumerState<CohortCapacityDialog> {
  late final TextEditingController _capacityCtrl;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _capacityCtrl =
        TextEditingController(text: widget.cohort.capacity?.toString() ?? '');
  }

  @override
  void dispose() {
    _capacityCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final raw = _capacityCtrl.text.trim();
    int? capacity;

    if (raw.isNotEmpty) {
      capacity = int.tryParse(raw);
      if (capacity == null || capacity <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'السعة يجب أن تكون رقماً أكبر من صفر',
              style: TextStyle(fontFamily: 'Cairo'),
            ),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }
    }

    setState(() => _loading = true);
    try {
      await ref.read(coursesRepositoryProvider).updateCohortCapacity(
            cohortId: widget.cohort.id,
            capacity: capacity,
          );

      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      ref.invalidate(cohortsByCourseProvider(widget.cohort.courseId));
      ref.invalidate(cohortSeatStatusProvider(widget.cohort.courseId));
      ref.invalidate(waitlistProvider(widget.cohort.id));

      Navigator.pop(context);
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'تم تحديث سعة المجموعة بنجاح',
            style: TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppErrorHandler.friendlyMessage(e),
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: EdgeInsets.all(Responsive.spacing(context, 24)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.tune, color: AppColors.gold),
                  SizedBox(width: Responsive.spacing(context, 8)),
                  Expanded(
                    child: Text(
                      'سعة المجموعة — ${widget.cohort.name}',
                      style: TextStyle(
                        fontSize: Responsive.fontSize(context, 16),
                        fontWeight: FontWeight.w700,
                        color: AppColors.gold,
                        fontFamily: 'Cairo',
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppColors.textSecondary),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(color: AppColors.divider),
              SizedBox(height: Responsive.spacing(context, 12)),
              Text(
                'اترك الحقل فارغاً لجعل المجموعة غير محدودة. '
                'لا يمكن تقليل السعة إلى أقل من عدد المتدربين المسجلين حالياً.',
                style: TextStyle(
                  fontSize: Responsive.fontSize(context, 12),
                  color: AppColors.textSecondary,
                  fontFamily: 'Cairo',
                  height: 1.5,
                ),
              ),
              SizedBox(height: Responsive.spacing(context, 16)),
              TextField(
                controller: _capacityCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  labelText: 'السعة',
                  hintText: 'فارغ = غير محدود',
                  labelStyle: const TextStyle(
                    color: AppColors.textSecondary,
                    fontFamily: 'Cairo',
                  ),
                  hintStyle: const TextStyle(
                    color: AppColors.textSecondary,
                    fontFamily: 'Cairo',
                  ),
                  prefixIcon:
                      const Icon(Icons.groups_2_outlined, color: AppColors.gold),
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.divider),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.divider),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.gold, width: 2),
                  ),
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
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text(
                        'إلغاء',
                        style: TextStyle(fontFamily: 'Cairo'),
                      ),
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
                                color: Colors.black,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              'حفظ السعة',
                              style: TextStyle(fontFamily: 'Cairo'),
                            ),
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
