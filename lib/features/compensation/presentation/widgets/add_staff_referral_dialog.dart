import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/app_error_handler.dart';
import '../../data/compensation_repository.dart';
import '../../domain/compensation_models.dart';

class AddStaffReferralDialog extends ConsumerStatefulWidget {
  const AddStaffReferralDialog({super.key});

  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AddStaffReferralDialog(),
    );
  }

  @override
  ConsumerState<AddStaffReferralDialog> createState() =>
      _AddStaffReferralDialogState();
}

class _AddStaffReferralDialogState
    extends ConsumerState<AddStaffReferralDialog> {
  final _formKey = GlobalKey<FormState>();
  final _rateController = TextEditingController(text: '2.5');
  final _searchController = TextEditingController();

  CompensationUser? _selectedStaff;
  EnrollmentOption? _selectedEnrollment;
  List<EnrollmentOption> _enrollments = [];
  bool _isLoading = false;
  bool _isSearching = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadEnrollments();
  }

  @override
  void dispose() {
    _rateController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadEnrollments([String search = '']) async {
    setState(() => _isSearching = true);
    try {
      final list = await ref
          .read(compensationRepositoryProvider)
          .getEnrollmentOptions(search: search);
      if (mounted) {
        setState(() {
          _enrollments = list;
          _isSearching = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedStaff == null) {
      setState(() => _errorMessage = 'يرجى اختيار الموظف صاحب الإحالة');
      return;
    }
    if (_selectedEnrollment == null) {
      setState(() => _errorMessage = 'يرجى اختيار تسجيل الطالب');
      return;
    }

    final rate = double.tryParse(_rateController.text.trim()) ?? 2.5;
    if (rate <= 0 || rate > 100) {
      setState(() => _errorMessage = 'نسبة العمولة بين 0.01% و 100%');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await ref.read(compensationRepositoryProvider).addReferral(
            enrollmentId: _selectedEnrollment!.id,
            staffId: _selectedStaff!.id,
            ratePercent: rate,
          );
      ref.invalidate(referralsProvider);
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
    final staffAsync = ref.watch(compensationStaffProvider);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        backgroundColor: AppColors.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: SingleChildScrollView(
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
                            color: AppColors.gold.withAlpha(30),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.person_add_alt_1_outlined,
                              color: AppColors.gold, size: 24),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'تسجيل إحالة طالب (عمولة 2.5%)',
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                              Text(
                                'ربط تسجيل متدرب بموظف لاحتساب عمولة على مقبوضاته',
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

                    // Staff selector
                    const Text(
                      'الموظف صاحب الإحالة',
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
                          prefixIcon: Icons.badge_outlined,
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

                    // Enrollment picker with search
                    const Text(
                      'تسجيل الطالب غير المحال سابقاً',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _searchController,
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontFamily: 'Cairo',
                          fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'بحث باسم المتدرب، كوده، أو الكورس...',
                        hintStyle: const TextStyle(
                            color: Colors.white30, fontFamily: 'Cairo'),
                        prefixIcon: const Icon(Icons.search,
                            color: AppColors.gold, size: 20),
                        suffixIcon: _isSearching
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: AppColors.gold),
                                ),
                              )
                            : null,
                        filled: true,
                        fillColor: AppColors.surface,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: AppColors.divider),
                        ),
                      ),
                      onChanged: (val) => _loadEnrollments(val),
                    ),
                    const SizedBox(height: 8),

                    Container(
                      height: 160,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: _enrollments.isEmpty
                          ? const Center(
                              child: Text(
                                'لا توجد تسجيلات مطابقة أو كلها محالة مسبقاً',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                ),
                              ),
                            )
                          : ListView.separated(
                              itemCount: _enrollments.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(color: AppColors.divider, height: 1),
                              itemBuilder: (context, index) {
                                final opt = _enrollments[index];
                                final isSelected =
                                    _selectedEnrollment?.id == opt.id;
                                return ListTile(
                                  dense: true,
                                  selected: isSelected,
                                  selectedTileColor:
                                      AppColors.gold.withAlpha(30),
                                  leading: Icon(
                                    isSelected
                                        ? Icons.check_circle
                                        : Icons.radio_button_unchecked,
                                    color: isSelected
                                        ? AppColors.gold
                                        : AppColors.textSecondary,
                                    size: 18,
                                  ),
                                  title: Text(
                                    '${opt.traineeName} [${opt.traineeCode}]',
                                    style: TextStyle(
                                      color: isSelected
                                          ? AppColors.gold
                                          : AppColors.textPrimary,
                                      fontFamily: 'Cairo',
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      fontSize: 13,
                                    ),
                                  ),
                                  subtitle: Text(
                                    opt.courseName,
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontFamily: 'Cairo',
                                      fontSize: 11,
                                    ),
                                  ),
                                  onTap: () => setState(
                                      () => _selectedEnrollment = opt),
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 16),

                    // Commission rate percent
                    const Text(
                      'نسبة العمولة المئوية (%)',
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
                        hintText: 'افتراضي: 2.5',
                        prefixIcon: Icons.percent,
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'يرجى إدخال نسبة العمولة';
                        }
                        final val = double.tryParse(v.trim());
                        if (val == null || val <= 0 || val > 100) {
                          return 'النسبة بين 0.01 و 100';
                        }
                        return null;
                      },
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
                                  'تسجيل الإحالة',
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
