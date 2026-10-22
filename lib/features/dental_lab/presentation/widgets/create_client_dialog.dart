import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../data/dental_lab_repository.dart';
import '../../domain/dental_lab_models.dart';

class CreateClientDialog extends ConsumerStatefulWidget {
  final LabClient? initialClient;

  const CreateClientDialog({super.key, this.initialClient});

  @override
  ConsumerState<CreateClientDialog> createState() => _CreateClientDialogState();
}

class _CreateClientDialogState extends ConsumerState<CreateClientDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _addressController;
  late TextEditingController _notesController;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialClient?.name ?? '');
    _phoneController = TextEditingController(text: widget.initialClient?.phone ?? '');
    _addressController = TextEditingController(text: widget.initialClient?.clinicAddress ?? '');
    _notesController = TextEditingController(text: widget.initialClient?.notes ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final repo = ref.read(dentalLabRepositoryProvider);
      if (widget.initialClient != null) {
        await repo.updateClient(
          id: widget.initialClient!.id,
          name: _nameController.text,
          phone: _phoneController.text.isEmpty ? null : _phoneController.text,
          clinicAddress: _addressController.text.isEmpty ? null : _addressController.text,
          notes: _notesController.text.isEmpty ? null : _notesController.text,
        );
      } else {
        await repo.createClient(
          name: _nameController.text,
          phone: _phoneController.text.isEmpty ? null : _phoneController.text,
          clinicAddress: _addressController.text.isEmpty ? null : _addressController.text,
          notes: _notesController.text.isEmpty ? null : _notesController.text,
        );
      }

      ref.invalidate(labClientsProvider);
      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.initialClient != null
                  ? 'تم تحديث بيانات العميل بنجاح'
                  : 'تمت إضافة العميل بنجاح',
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ: $e', style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initialClient != null;

    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.gold, width: 1),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.person_add_alt_1_outlined, color: AppColors.gold, size: 24),
                    const SizedBox(width: 8),
                    Text(
                      isEdit ? 'تعديل بيانات العميل / الطبيب' : 'إضافة عيادة أو طبيب جديد',
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.gold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                TextFormField(
                  controller: _nameController,
                  style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                  decoration: const InputDecoration(
                    labelText: 'اسم الطبيب / العيادة *',
                    labelStyle: TextStyle(color: AppColors.textSecondary, fontFamily: 'Cairo'),
                    prefixIcon: Icon(Icons.badge_outlined, color: AppColors.gold),
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'الاسم مطلوب' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                  decoration: const InputDecoration(
                    labelText: 'رقم الهاتف / الواتساب',
                    labelStyle: TextStyle(color: AppColors.textSecondary, fontFamily: 'Cairo'),
                    prefixIcon: Icon(Icons.phone_outlined, color: AppColors.gold),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _addressController,
                  style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                  decoration: const InputDecoration(
                    labelText: 'عنوان العيادة / المركز الطبي',
                    labelStyle: TextStyle(color: AppColors.textSecondary, fontFamily: 'Cairo'),
                    prefixIcon: Icon(Icons.location_on_outlined, color: AppColors.gold),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _notesController,
                  maxLines: 2,
                  style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                  decoration: const InputDecoration(
                    labelText: 'ملاحظات إضافية',
                    labelStyle: TextStyle(color: AppColors.textSecondary, fontFamily: 'Cairo'),
                    prefixIcon: Icon(Icons.note_alt_outlined, color: AppColors.gold),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo', color: Colors.white70)),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.gold,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _isLoading ? null : _submit,
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                            )
                          : Text(
                              isEdit ? 'حفظ التعديلات' : 'إضافة العميل',
                              style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
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
