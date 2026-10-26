import '../../../core/utils/app_error_handler.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/responsive.dart';
import '../../courses/data/courses_repository.dart';
import 'widgets/referral_input_fields.dart';

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
  final _referralKey = GlobalKey<ReferralInputFieldsState>();
  ReferralSelection _referral = const ReferralSelection();
  String _currency = 'SYP';
  bool _loading = false;

  @override
  void dispose() {
    _priceCtrl.dispose();
    _discountCtrl.dispose();
    super.dispose();
  }

  bool _isCapacityReached(Object error) {
    return error is PostgrestException &&
        (error.message.contains('COHORT_CAPACITY_REACHED') ||
            (error.details?.toString().contains('COHORT_CAPACITY_REACHED') ??
                false));
  }

  Future<bool> _confirmJoinWaitlist() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.cardBg,
        title: const Text(
          'المجموعة ممتلئة',
          style: TextStyle(color: AppColors.gold, fontFamily: 'Cairo'),
        ),
        content: const Text(
          'لا توجد مقاعد متاحة في هذه المجموعة. هل تريد إضافة المتدرب إلى قائمة الانتظار؟',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontFamily: 'Cairo',
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text(
              'إلغاء',
              style: TextStyle(
                fontFamily: 'Cairo',
                color: AppColors.textSecondary,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'إضافة للانتظار',
              style: TextStyle(fontFamily: 'Cairo'),
            ),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _joinWaitlistAndClose(String cohortId) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await ref.read(coursesRepositoryProvider).joinWaitlist(
            cohortId: cohortId,
            traineeId: widget.traineeId,
          );
      if (!mounted) return;
      ref.invalidate(cohortSeatStatusProvider);
      ref.invalidate(waitlistProvider(cohortId));
      final position = result['queue_position'];
      final message = position != null
          ? 'المجموعة ممتلئة — تمت إضافة المتدرب إلى الانتظار (الترتيب $position)'
          : 'المجموعة ممتلئة — تمت إضافة المتدرب إلى الانتظار';
      Navigator.pop(context);
      widget.onEnrolled();
      messenger.showSnackBar(
        SnackBar(
          content: Text(message, style: const TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppColors.warning,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            AppErrorHandler.friendlyMessage(e),
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: AppColors.error,
        ),
      );
    }
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

    final cohortId = _selectedCohortId!;
    final totalDue = double.tryParse(_priceCtrl.text) ?? 0;
    final discountAmount = double.tryParse(_discountCtrl.text) ?? 0;
    final referralCode = _referral.code;
    final referralAmount = _referral.amount;
    String? existingWaitlistId;

    if (referralCode != null) {
      if (!_referral.isVerified) {
        final preview = await _referralKey.currentState?.verify();
        if (!mounted) return;
        if (preview == null || !preview.valid || !_referral.isVerified) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'تحقق من كود الإحالة أولاً',
                style: TextStyle(fontFamily: 'Cairo'),
              ),
              backgroundColor: AppColors.error,
            ),
          );
          return;
        }
      }

      if (referralAmount <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'أدخل قيمة خصم الإحالة (أكبر من صفر)',
              style: TextStyle(fontFamily: 'Cairo'),
            ),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }

      if (referralAmount > totalDue - discountAmount) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'خصم الإحالة أكبر من المبلغ المتبقي بعد الخصم اليدوي',
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
      final repo = ref.read(coursesRepositoryProvider);

      // المتدرب الموجود في الانتظار تُرقّى طلبه بدل إنشاء تسجيل مباشر
      final activeWaitlist = await repo.getActiveWaitlist(cohortId);
      for (final entry in activeWaitlist) {
        if (entry.traineeId == widget.traineeId) {
          existingWaitlistId = entry.id;
          break;
        }
      }

      if (existingWaitlistId != null) {
        await repo.promoteWaitlist(
          waitlistId: existingWaitlistId,
          totalDue: totalDue,
          discountAmount: discountAmount,
          currency: _currency,
          referralCode: referralCode,
          referralDiscountAmount: referralAmount,
        );
      } else {
        await repo.enrollTrainee(
          traineeId: widget.traineeId,
          cohortId: cohortId,
          totalDue: totalDue,
          discountAmount: discountAmount,
          currency: _currency,
          referralCode: referralCode,
          referralDiscountAmount: referralAmount,
        );
      }

      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      ref.invalidate(cohortSeatStatusProvider);
      ref.invalidate(waitlistProvider(cohortId));
      final promoted = existingWaitlistId != null;
      Navigator.pop(context);
      widget.onEnrolled();

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            promoted
                ? 'تمت ترقية المتدرب وتسجيله بنجاح ✓'
                : 'تم تسجيل المتدرب بنجاح ✓',
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      if (_isCapacityReached(e) && existingWaitlistId == null) {
        setState(() => _loading = false);
        final join = await _confirmJoinWaitlist();
        if (!mounted || !join) return;
        setState(() => _loading = true);
        await _joinWaitlistAndClose(cohortId);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(AppErrorHandler.friendlyMessage(e)),
            backgroundColor: AppColors.error),
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
        child: SingleChildScrollView(
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
                      icon: const Icon(Icons.close,
                          color: AppColors.textSecondary),
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
                  error: (e, _) => Text(AppErrorHandler.friendlyMessage(e),
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
                      initialValue: _selectedCohortId,
                      dropdownColor: AppColors.cardBg,
                      decoration: InputDecoration(
                        labelText: 'اختر الكورس / المجموعة *',
                        labelStyle: const TextStyle(
                            color: AppColors.textSecondary,
                            fontFamily: 'Cairo'),
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
                          final selected = cohorts.firstWhere(
                              (c) => c['id'] == v,
                              orElse: () => {});
                          if (selected.isNotEmpty) {
                            _priceCtrl.text = (selected['price'] as double)
                                .toInt()
                                .toString();
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
                        initialValue: _currency,
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
                        onChanged: (v) =>
                            setState(() => _currency = v ?? 'SYP'),
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

                SizedBox(height: Responsive.spacing(context, 12)),

                ReferralInputFields(
                  key: _referralKey,
                  currency: _currency,
                  onChanged: (selection) {
                    if (mounted) setState(() => _referral = selection);
                  },
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
      ),
    );
  }
}
