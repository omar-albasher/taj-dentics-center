import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../data/dental_lab_repository.dart';

class CreateLabExpenseDialog extends ConsumerStatefulWidget {
  const CreateLabExpenseDialog({super.key});

  @override
  ConsumerState<CreateLabExpenseDialog> createState() => _CreateLabExpenseDialogState();
}

class _CreateLabExpenseDialogState extends ConsumerState<CreateLabExpenseDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();

  String _category = 'materials';
  String _currency = 'SYP';
  String _paymentMethod = 'cash';
  final DateTime _expenseDate = DateTime.now();
  bool _isLoading = false;

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final amt = double.tryParse(_amountController.text) ?? 0.0;
    if (amt <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('المبلغ يجب أن يكون أكبر من صفر', style: TextStyle(fontFamily: 'Cairo'))),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final repo = ref.read(dentalLabRepositoryProvider);
      await repo.addExpense(
        title: _titleController.text,
        category: _category,
        amount: amt,
        currency: _currency,
        expenseDate: _expenseDate,
        paymentMethod: _paymentMethod,
        notes: _notesController.text.isEmpty ? null : _notesController.text,
      );

      ref.invalidate(labExpensesProvider);
      ref.invalidate(labFinancialSummaryProvider);

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تسجيل مصروف المخبر بنجاح', style: TextStyle(fontFamily: 'Cairo')),
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
                const Row(
                  children: [
                    Icon(Icons.receipt_long_outlined, color: AppColors.gold, size: 24),
                    SizedBox(width: 8),
                    Text(
                      'تسجيل مصروف خاص بالمخبر',
                      style: TextStyle(
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
                  controller: _titleController,
                  style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                  decoration: const InputDecoration(
                    labelText: 'بيان المصروف (مثلاً: شراء أقراص زيركون) *',
                    labelStyle: TextStyle(color: AppColors.textSecondary, fontFamily: 'Cairo'),
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'البيان مطلوب' : null,
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _amountController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                        decoration: const InputDecoration(
                          labelText: 'المبلغ *',
                          labelStyle: TextStyle(color: AppColors.textSecondary, fontFamily: 'Cairo'),
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'المبلغ مطلوب';
                          if (double.tryParse(v) == null) return 'رقم غير صحيح';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 1,
                      child: DropdownButtonFormField<String>(
                        initialValue: _currency,
                        dropdownColor: AppColors.surface,
                        style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                        decoration: const InputDecoration(
                          labelText: 'العملة',
                          labelStyle: TextStyle(color: AppColors.textSecondary, fontFamily: 'Cairo'),
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'SYP', child: Text('ل.س')),
                          DropdownMenuItem(value: 'USD', child: Text('\$ USD')),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => _currency = v);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _category,
                  dropdownColor: AppColors.surface,
                  style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                  decoration: const InputDecoration(
                    labelText: 'تصنيف المصروف *',
                    labelStyle: TextStyle(color: AppColors.textSecondary, fontFamily: 'Cairo'),
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'materials', child: Text('شراء مواد وخامات (زيركون/خزف)')),
                    DropdownMenuItem(value: 'equipment_maintenance', child: Text('صيانة أجهزة ومعدات')),
                    DropdownMenuItem(value: 'utilities', child: Text('فواتير ومرافق (كهرباء/غاز)')),
                    DropdownMenuItem(value: 'salaries', child: Text('رواتب وأجور فنيين')),
                    DropdownMenuItem(value: 'other', child: Text('مصاريف أخرى')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _category = v);
                  },
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _paymentMethod,
                  dropdownColor: AppColors.surface,
                  style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                  decoration: const InputDecoration(
                    labelText: 'طريقة الدفع *',
                    labelStyle: TextStyle(color: AppColors.textSecondary, fontFamily: 'Cairo'),
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'cash', child: Text('نقداً (كاش)')),
                    DropdownMenuItem(value: 'sham_cash', child: Text('شام كاش')),
                    DropdownMenuItem(value: 'hawala', child: Text('حوالة هرم')),
                    DropdownMenuItem(value: 'bank_transfer', child: Text('تحويل مصرفي')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _paymentMethod = v);
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _notesController,
                  style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                  decoration: const InputDecoration(
                    labelText: 'ملاحظات المصروف',
                    labelStyle: TextStyle(color: AppColors.textSecondary, fontFamily: 'Cairo'),
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
                          : const Text(
                              'تسجيل المصروف',
                              style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
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
