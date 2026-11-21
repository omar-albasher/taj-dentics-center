import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/app_error_handler.dart';
import '../../../../core/utils/app_formatters.dart';
import '../../data/compensation_repository.dart';
import '../../domain/compensation_models.dart';

class AddTrainerAgreementDialog extends ConsumerStatefulWidget {
  const AddTrainerAgreementDialog({super.key});

  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AddTrainerAgreementDialog(),
    );
  }

  @override
  ConsumerState<AddTrainerAgreementDialog> createState() =>
      _AddTrainerAgreementDialogState();
}

class _AddTrainerAgreementDialogState
    extends ConsumerState<AddTrainerAgreementDialog> {
  final _formKey = GlobalKey<FormState>();
  final _rateController = TextEditingController();
  final _notesController = TextEditingController();

  CompensationUser? _selectedTrainer;
  CourseOption? _selectedCourse;
  DateTime _effectiveFrom = DateTime.now();
  DateTime? _effectiveTo;

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _rateController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedTrainer == null) {
      setState(() => _errorMessage = 'يرجى اختيار المدرب');
      return;
    }
    if (_selectedCourse == null) {
      setState(() => _errorMessage = 'يرجى اختيار الكورس');
      return;
    }

    final rate = double.tryParse(_rateController.text.trim());
    if (rate == null || rate <= 0 || rate > 100) {
      setState(() => _errorMessage = 'النسبة يجب أن تكون بين 0.01% و 100%');
      return;
    }

    if (_effectiveTo != null && _effectiveTo!.isBefore(_effectiveFrom)) {
      setState(
          () => _errorMessage = 'تاريخ نهاية الاتفاقية يجب أن يلي تاريخ بدئها');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await ref.read(compensationRepositoryProvider).addAgreement(
            trainerId: _selectedTrainer!.id,
            courseId: _selectedCourse!.id,
            ratePercent: rate,
            effectiveFrom: _effectiveFrom,
            effectiveTo: _effectiveTo,
            notes: _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
          );
      ref.invalidate(agreementsProvider);
      ref.invalidate(cohortRatesProvider);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = AppErrorHandler.friendlyMessage(e);
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = isFrom ? _effectiveFrom : (_effectiveTo ?? _effectiveFrom);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
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
      setState(() {
        if (isFrom) {
          _effectiveFrom = picked;
          if (_effectiveTo != null && _effectiveTo!.isBefore(_effectiveFrom)) {
            _effectiveTo = null;
          }
        } else {
          _effectiveTo = picked;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final trainersAsync = ref.watch(compensationTrainersProvider);
    final coursesAsync = ref.watch(courseOptionsProvider);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        backgroundColor: AppColors.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: SingleChildScrollView(
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
                          child: const Icon(Icons.handshake_outlined,
                              color: AppColors.gold, size: 24),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'إضافة اتفاقية أتعاب مدرب',
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                              Text(
                                'تحديد النسبة المئوية الافتراضية للمدرب لكورس محدد وفترة زمنية',
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
                    // Trainer selector
                    const Text(
                      'المدرب',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    trainersAsync.when(
                      data: (trainers) =>
                          DropdownButtonFormField<CompensationUser>(
                        initialValue: _selectedTrainer,
                        dropdownColor: AppColors.surface,
                        items: trainers.map((t) {
                          return DropdownMenuItem(
                            value: t,
                            child: Text(
                              t.fullName,
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
                            : (val) => setState(() => _selectedTrainer = val),
                        decoration: _inputDecoration(
                          hintText: 'اختر المدرب',
                          prefixIcon: Icons.person_outline,
                        ),
                        validator: (v) =>
                            v == null ? 'يرجى اختيار المدرب' : null,
                      ),
                      loading: () => const LinearProgressIndicator(
                          color: AppColors.gold, minHeight: 2),
                      error: (e, _) => Text(
                        'خطأ في تحميل المدربين: $e',
                        style: const TextStyle(
                            color: AppColors.error, fontSize: 12),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Course selector
                    const Text(
                      'الكورس التدريبي',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    coursesAsync.when(
                      data: (courses) => DropdownButtonFormField<CourseOption>(
                        initialValue: _selectedCourse,
                        dropdownColor: AppColors.surface,
                        items: courses.map((c) {
                          return DropdownMenuItem(
                            value: c,
                            child: Text(
                              c.name,
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
                            : (val) => setState(() => _selectedCourse = val),
                        decoration: _inputDecoration(
                          hintText: 'اختر الكورس',
                          prefixIcon: Icons.school_outlined,
                        ),
                        validator: (v) =>
                            v == null ? 'يرجى اختيار الكورس' : null,
                      ),
                      loading: () => const LinearProgressIndicator(
                          color: AppColors.gold, minHeight: 2),
                      error: (e, _) => Text(
                        'خطأ في تحميل الكورسات: $e',
                        style: const TextStyle(
                            color: AppColors.error, fontSize: 12),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Rate percent
                    const Text(
                      'نسبة الأتعاب المئوية (%)',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _rateController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d*')),
                      ],
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                      ),
                      decoration: _inputDecoration(
                        hintText: 'مثال: 35 أو 25',
                        prefixIcon: Icons.percent,
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'يرجى إدخال النسبة المئوية';
                        }
                        final val = double.tryParse(v.trim());
                        if (val == null || val <= 0 || val > 100) {
                          return 'قيمة النسبة يجب أن تكون بين 0.01 و 100';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    // Effective dates
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'تاريخ البدء (سارية من)',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              InkWell(
                                onTap: _isLoading
                                    ? null
                                    : () => _pickDate(isFrom: true),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: AppColors.surface,
                                    borderRadius: BorderRadius.circular(8),
                                    border:
                                        Border.all(color: AppColors.divider),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.calendar_today,
                                          size: 16, color: AppColors.gold),
                                      const SizedBox(width: 8),
                                      Text(
                                        AppFormatters.dateOnly
                                            .format(_effectiveFrom),
                                        style: const TextStyle(
                                          color: AppColors.textPrimary,
                                          fontFamily: 'Cairo',
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'تاريخ الانتهاء (اختياري)',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                  if (_effectiveTo != null)
                                    GestureDetector(
                                      onTap: () =>
                                          setState(() => _effectiveTo = null),
                                      child: const Text(
                                        'إلغاء',
                                        style: TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 11,
                                          color: AppColors.warning,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              InkWell(
                                onTap: _isLoading
                                    ? null
                                    : () => _pickDate(isFrom: false),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: AppColors.surface,
                                    borderRadius: BorderRadius.circular(8),
                                    border:
                                        Border.all(color: AppColors.divider),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.event,
                                          size: 16,
                                          color: AppColors.textSecondary),
                                      const SizedBox(width: 8),
                                      Text(
                                        _effectiveTo == null
                                            ? 'مفتوحة (مستمرة)'
                                            : AppFormatters.dateOnly
                                                .format(_effectiveTo!),
                                        style: TextStyle(
                                          color: _effectiveTo == null
                                              ? AppColors.textSecondary
                                              : AppColors.textPrimary,
                                          fontFamily: 'Cairo',
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Notes
                    const Text(
                      'ملاحظات (اختياري)',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _notesController,
                      maxLines: 2,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontFamily: 'Cairo',
                        fontSize: 13,
                      ),
                      decoration: _inputDecoration(
                        hintText: 'مثال: تم الاتفاق على خفض النسبة من الدفعة 4',
                        prefixIcon: Icons.notes_outlined,
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
                            'إلغاء',
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
                                  'حفظ الاتفاقية',
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
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hintText,
    required IconData prefixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(color: Colors.white30, fontFamily: 'Cairo'),
      prefixIcon: Icon(prefixIcon, color: AppColors.gold, size: 20),
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
        borderSide: const BorderSide(color: AppColors.gold, width: 1.5),
      ),
    );
  }
}
