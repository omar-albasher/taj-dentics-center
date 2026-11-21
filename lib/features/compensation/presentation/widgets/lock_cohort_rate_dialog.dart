import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/app_error_handler.dart';
import '../../data/compensation_repository.dart';
import '../../domain/compensation_models.dart';

class LockCohortRateDialog extends ConsumerStatefulWidget {
  final CohortTrainerRate? presetCohort;
  final List<CohortTrainerRate> availableCohorts;

  const LockCohortRateDialog({
    super.key,
    this.presetCohort,
    this.availableCohorts = const [],
  });

  static Future<bool?> show(
    BuildContext context, {
    CohortTrainerRate? presetCohort,
    List<CohortTrainerRate> availableCohorts = const [],
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => LockCohortRateDialog(
        presetCohort: presetCohort,
        availableCohorts: availableCohorts,
      ),
    );
  }

  @override
  ConsumerState<LockCohortRateDialog> createState() =>
      _LockCohortRateDialogState();
}

class _LockCohortRateDialogState extends ConsumerState<LockCohortRateDialog> {
  final _formKey = GlobalKey<FormState>();
  final _rateController = TextEditingController();

  CohortTrainerRate? _selectedCohort;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _selectedCohort = widget.presetCohort ??
        (widget.availableCohorts.isNotEmpty
            ? widget.availableCohorts.first
            : null);
    if (_selectedCohort?.ratePercent != null) {
      _rateController.text = _selectedCohort!.ratePercent!.toStringAsFixed(1);
    }
  }

  @override
  void dispose() {
    _rateController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCohort == null) {
      setState(() => _errorMessage = 'يرجى اختيار الدفعة التدريبية');
      return;
    }

    final rate = double.tryParse(_rateController.text.trim());
    if (rate == null || rate <= 0 || rate > 100) {
      setState(() => _errorMessage = 'النسبة يجب أن تكون بين 0.01% و 100%');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await ref.read(compensationRepositoryProvider).lockCohortRate(
            _selectedCohort!.cohortId,
            rate,
          );
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
            child: Form(
              key: _formKey,
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
                        child: const Icon(Icons.lock_clock_outlined,
                            color: AppColors.gold, size: 24),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'تثبيت نسبة أتعاب الدفعة',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Cairo',
                              ),
                            ),
                            Text(
                              'تجميد النسبة المئوية للمدرب الخاصة بهذه الدفعة تاريخياً',
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
                  if (widget.presetCohort != null) ...[
                    _buildCohortInfoCard(widget.presetCohort!),
                    const SizedBox(height: 16),
                  ] else ...[
                    const Text(
                      'الدفعة والكورس',
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
                      items: widget.availableCohorts.map((c) {
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
                          : (val) {
                              setState(() {
                                _selectedCohort = val;
                                if (val?.ratePercent != null) {
                                  _rateController.text =
                                      val!.ratePercent!.toStringAsFixed(1);
                                }
                              });
                            },
                      decoration: _inputDecoration(
                        hintText: 'اختر الدفعة',
                        prefixIcon: Icons.group_work_outlined,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
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
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
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
                        Icon(Icons.info_outline,
                            size: 16, color: AppColors.gold),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'تثبيت النسبة يضمن استقرار حسابات الأتعاب للدفعة حتى لو تغيرت اتفاقية المدرب لاحقاً لكورسات أخرى.',
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
                                'تثبيت النسبة',
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
    );
  }

  Widget _buildCohortInfoCard(CohortTrainerRate cohort) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            cohort.courseName,
            style: const TextStyle(
              color: AppColors.gold,
              fontWeight: FontWeight.bold,
              fontFamily: 'Cairo',
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'الدفعة: ${cohort.cohortName} • المدرب: ${cohort.trainerName.isEmpty ? "غير محدد" : cohort.trainerName}',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontFamily: 'Cairo',
              fontSize: 12,
            ),
          ),
        ],
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
