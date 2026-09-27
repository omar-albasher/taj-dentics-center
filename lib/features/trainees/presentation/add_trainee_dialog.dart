import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../data/trainees_repository.dart';

class AddTraineeDialog extends ConsumerStatefulWidget {
  final VoidCallback onAdded;
  const AddTraineeDialog({super.key, required this.onAdded});

  @override
  ConsumerState<AddTraineeDialog> createState() => _AddTraineeDialogState();
}

class _AddTraineeDialogState extends ConsumerState<AddTraineeDialog> {
  final _codeCtrl = TextEditingController();
  final _nameArCtrl = TextEditingController();
  final _nameEnCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _whatsappCtrl = TextEditingController();
  final _universityCtrl = TextEditingController();
  final _academicYearCtrl = TextEditingController();
  final _provinceCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _behavioralNotesCtrl = TextEditingController();
  final _academicNotesCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _codeCtrl.dispose();
    _nameArCtrl.dispose();
    _nameEnCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _whatsappCtrl.dispose();
    _universityCtrl.dispose();
    _academicYearCtrl.dispose();
    _provinceCtrl.dispose();
    _addressCtrl.dispose();
    _behavioralNotesCtrl.dispose();
    _academicNotesCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_nameArCtrl.text.isEmpty ||
        _emailCtrl.text.isEmpty ||
        _phoneCtrl.text.isEmpty ||
        _passwordCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى تعبئة الحقول الإلزامية (*)'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final repo = ref.read(traineesRepositoryProvider);
      await repo.addTrainee(
        traineeCode: _codeCtrl.text.trim().isNotEmpty ? _codeCtrl.text.trim() : null,
        fullName: _nameArCtrl.text.trim(),
        fullNameEn: _nameEnCtrl.text.trim().isNotEmpty ? _nameEnCtrl.text.trim() : null,
        email: _emailCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        whatsapp: _whatsappCtrl.text.trim().isNotEmpty ? _whatsappCtrl.text.trim() : null,
        university: _universityCtrl.text.trim().isNotEmpty ? _universityCtrl.text.trim() : null,
        academicYear: _academicYearCtrl.text.trim().isNotEmpty ? _academicYearCtrl.text.trim() : null,
        province: _provinceCtrl.text.trim().isNotEmpty ? _provinceCtrl.text.trim() : null,
        address: _addressCtrl.text.trim().isNotEmpty ? _addressCtrl.text.trim() : null,
        behavioralNotes: _behavioralNotesCtrl.text.trim().isNotEmpty ? _behavioralNotesCtrl.text.trim() : null,
        academicNotes: _academicNotesCtrl.text.trim().isNotEmpty ? _academicNotesCtrl.text.trim() : null,
        password: _passwordCtrl.text,
      );

      if (!mounted) return;
      Navigator.pop(context);
      widget.onAdded();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم إضافة المتدرب بنجاح 🎉'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ: ${e.toString()}'),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 620,
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 1. Fixed Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.person_add_alt_1, color: AppColors.gold, size: 22),
                      SizedBox(width: 8),
                      Text(
                        'إضافة متدرب جديد',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.gold,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppColors.textSecondary),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(color: AppColors.divider, height: 1),

            // 2. Scrollable Middle Fields
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Trainee Code (Phase 2)
                    _buildField(
                      controller: _codeCtrl,
                      label: 'كود المتدرب (مثال: T10001 — اتركه فارغاً للتوليد التلقائي)',
                      icon: Icons.qr_code,
                      isLtr: true,
                    ),
                    const SizedBox(height: 12),

                    // Names: Arabic & English
                    Row(
                      children: [
                        Expanded(
                          child: _buildField(
                            controller: _nameArCtrl,
                            label: 'الاسم بالعربي (جواز السفر) *',
                            icon: Icons.person_outline,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildField(
                            controller: _nameEnCtrl,
                            label: 'الاسم بالإنكليزي (جواز السفر)',
                            icon: Icons.badge_outlined,
                            isLtr: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Phone & WhatsApp
                    Row(
                      children: [
                        Expanded(
                          child: _buildField(
                            controller: _phoneCtrl,
                            label: 'رقم الجوال *',
                            icon: Icons.phone_outlined,
                            inputType: TextInputType.phone,
                            isLtr: true,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildField(
                            controller: _whatsappCtrl,
                            label: 'رقم الواتساب',
                            icon: Icons.chat_outlined,
                            inputType: TextInputType.phone,
                            isLtr: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // University & Academic Year
                    Row(
                      children: [
                        Expanded(
                          child: _buildField(
                            controller: _universityCtrl,
                            label: 'اسم الجامعة أو المعهد',
                            icon: Icons.account_balance_outlined,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildField(
                            controller: _academicYearCtrl,
                            label: 'السنة الدراسية (سنة 3 / خريج)',
                            icon: Icons.school_outlined,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Province & Address
                    Row(
                      children: [
                        Expanded(
                          child: _buildField(
                            controller: _provinceCtrl,
                            label: 'المحافظة',
                            icon: Icons.location_city_outlined,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildField(
                            controller: _addressCtrl,
                            label: 'عنوان السكن',
                            icon: Icons.home_outlined,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Behavioral & Academic Notes
                    Row(
                      children: [
                        Expanded(
                          child: _buildField(
                            controller: _behavioralNotesCtrl,
                            label: 'ملاحظات سلوكية (اختياري)',
                            icon: Icons.psychology_outlined,
                            maxLines: 2,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildField(
                            controller: _academicNotesCtrl,
                            label: 'ملاحظات أكاديمية (اختياري)',
                            icon: Icons.auto_stories_outlined,
                            maxLines: 2,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Email
                    _buildField(
                      controller: _emailCtrl,
                      label: 'البريد الإلكتروني *',
                      icon: Icons.email_outlined,
                      inputType: TextInputType.emailAddress,
                      isLtr: true,
                    ),
                    const SizedBox(height: 12),

                    // Password
                    TextField(
                      controller: _passwordCtrl,
                      obscureText: _obscure,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        labelText: 'كلمة المرور (لتطبيق المتدرب) *',
                        labelStyle: const TextStyle(
                            color: AppColors.textSecondary, fontFamily: 'Cairo'),
                        prefixIcon:
                            const Icon(Icons.lock_outlined, color: AppColors.gold),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscure ? Icons.visibility_off : Icons.visibility,
                            color: AppColors.textSecondary,
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
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
                          borderSide:
                              const BorderSide(color: AppColors.gold, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 3. Fixed Footer with Actions
            const Divider(color: AppColors.divider, height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
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
                  const SizedBox(width: 12),
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
                              'إضافة متدرب',
                              style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType inputType = TextInputType.text,
    bool isLtr = false,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      keyboardType: inputType,
      maxLines: maxLines,
      textDirection: isLtr ? TextDirection.ltr : TextDirection.rtl,
      style: const TextStyle(color: AppColors.textPrimary, fontFamily: 'Cairo'),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          color: AppColors.textSecondary,
          fontFamily: 'Cairo',
          fontSize: 13,
        ),
        prefixIcon: Icon(icon, color: AppColors.gold, size: 20),
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
    );
  }
}
