import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/app_error_handler.dart';
import '../../../../core/utils/app_formatters.dart';
import '../../data/compensation_repository.dart';
import '../../domain/compensation_models.dart';

class AddStaffCompensationDialog extends ConsumerStatefulWidget {
  const AddStaffCompensationDialog({super.key});

  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AddStaffCompensationDialog(),
    );
  }

  @override
  ConsumerState<AddStaffCompensationDialog> createState() =>
      _AddStaffCompensationDialogState();
}

class _AddStaffCompensationDialogState
    extends ConsumerState<AddStaffCompensationDialog> {
  final _formKey = GlobalKey<FormState>();
  final _salaryController = TextEditingController();
  final _commissionController = TextEditingController(text: '2.5');
  final _notesController = TextEditingController();

  CompensationUser? _selectedStaff;
  String _selectedCurrency = 'SYP';
  DateTime _effectiveFrom = DateTime.now();
  DateTime? _effectiveTo;

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _salaryController.dispose();
    _commissionController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedStaff == null) {
      setState(() => _errorMessage = 'يرجى اختيار الموظف');
      return;
    }

    final salary = double.tryParse(_salaryController.text.trim());
    if (salary == null || salary < 0) {
      setState(() => _errorMessage = 'يرجى إدخال راتب صحيح (0 أو أكبر)');
      return;
    }

    final comm = double.tryParse(_commissionController.text.trim()) ?? 0.0;
    if (comm < 0 || comm > 100) {
      setState(
          () => _errorMessage = 'نسبة العمولة يجب أن تكون بين 0% و 100%');
      return;
    }

    if (_effectiveTo != null && _effectiveTo!.isBefore(_effectiveFrom)) {
      setState(() =>
          _errorMessage = 'تاريخ نهاية الصلاحية يجب أن يلي تاريخ البدء');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await ref.read(compensationRepositoryProvider).addStaffCompensation(
            userId: _selectedStaff!.id,
            monthlySalary: salary,
            currency: _selectedCurrency,
            commissionRatePercent: comm,
            effectiveFrom: _effectiveFrom,
            effectiveTo: _effectiveTo,
            notes: _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
          );
      ref.invalidate(staffCompensationProvider);
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
    final staffAsync = ref.watch(compensationStaffProvider);

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
                          child: const Icon(Icons.badge_outlined,
                              color: AppColors.gold, size: 24),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'تحديد راتب وعمولة موظف',
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                              Text(
                                'تحديد الراتب الشهري الثابت ونسبة عمولة إحالة الطلاب',
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

                    // Staff user selector
                    const Text(
                      'الموظف (إدارة / استقبال)',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    staffAsync.when(
                      data: (users) => DropdownButtonFormField<CompensationUser>(
                        initialValue: _selectedStaff,
                        dropdownColor: AppColors.surface,
                        items: users.map((u) {
                          return DropdownMenuItem(
                            value: u,
                            child: Text(
                              '${u.fullName} (${u.roleAr})',
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
                            : (val) => setState(() => _selectedStaff = val),
                        decoration: _inputDecoration(
                          hintText: 'اختر الموظف',
                          prefixIcon: Icons.person_outline,
                        ),
                        validator: (v) =>
                            v == null ? 'يرجى اختيار الموظف' : null,
                      ),
                      loading: () => const LinearProgressIndicator(
                          color: AppColors.gold, minHeight: 2),
                      error: (e, _) => Text(
                        'خطأ في تحميل الموظفين: $e',
                        style: const TextStyle(
                            color: AppColors.error, fontSize: 12),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Monthly salary and currency
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'الراتب الشهري الأساسي',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: _salaryController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
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
                                  hintText: 'مثال: 1200000',
                                  prefixIcon: Icons.attach_money,
                                ),
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) {
                                    return 'يرجى إدخال الراتب';
                                  }
                                  final val = double.tryParse(v.trim());
                                  if (val == null || val < 0) {
                                    return 'قيمة غير صالحة';
                                  }
                                  return null;
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'العملة',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              DropdownButtonFormField<String>(
                                initialValue: _selectedCurrency,
                                dropdownColor: AppColors.surface,
                                items: const [
                                  DropdownMenuItem(
                                    value: 'SYP',
                                    child: Text(
                                      'ليرة سورية (SYP)',
                                      style: TextStyle(
                                          color: AppColors.textPrimary,
                                          fontFamily: 'Cairo',
                                          fontSize: 13),
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: 'USD',
                                    child: Text(
                                      'دولار (USD)',
                                      style: TextStyle(
                                          color: AppColors.textPrimary,
                                          fontFamily: 'Cairo',
                                          fontSize: 13),
                                    ),
                                  ),
                                ],
                                onChanged: _isLoading
                                    ? null
                                    : (val) => setState(() =>
                                        _selectedCurrency = val ?? 'SYP'),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: AppColors.surface,
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 12),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(
                                        color: AppColors.divider),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(
                                        color: AppColors.divider),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(
                                        color: AppColors.gold, width: 1.5),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Commission percent
                    const Text(
                      'نسبة عمولة إحالة الطلاب (%)',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _commissionController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d*')),
                      ],
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontFamily: 'Cairo',
                      ),
                      decoration: _inputDecoration(
                        hintText: 'افتراضي: 2.5',
                        prefixIcon: Icons.percent,
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return null;
                        final val = double.tryParse(v.trim());
                        if (val == null || val < 0 || val > 100) {
                          return 'النسبة بين 0 و 100';
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
                                'تاريخ البدء',
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
                                            ? 'مستمر'
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
                        hintText: 'أي تفاصيل أو بنود خاصة بالراتب',
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
                                  'حفظ الراتب',
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
