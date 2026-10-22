import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../data/dental_lab_repository.dart';
import '../../domain/dental_lab_models.dart';

class RecordLabPaymentDialog extends ConsumerStatefulWidget {
  final LabInvoice invoice;

  const RecordLabPaymentDialog({super.key, required this.invoice});

  @override
  ConsumerState<RecordLabPaymentDialog> createState() => _RecordLabPaymentDialogState();
}

class _RecordLabPaymentDialogState extends ConsumerState<RecordLabPaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _amountController;
  final _receiptNumberController = TextEditingController();
  final _refController = TextEditingController();
  final _notesController = TextEditingController();

  String _method = 'cash';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Default amount to the remaining balance
    _amountController = TextEditingController(
      text: widget.invoice.remainingAmount.toStringAsFixed(0),
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    _receiptNumberController.dispose();
    _refController.dispose();
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
      await repo.recordPayment(
        invoiceId: widget.invoice.id,
        amount: amt,
        currency: widget.invoice.currency,
        method: _method,
        receiptNumber: _receiptNumberController.text.isEmpty ? null : _receiptNumberController.text,
        externalReference: _refController.text.isEmpty ? null : _refController.text,
        notes: _notesController.text.isEmpty ? null : _notesController.text,
      );

      ref.invalidate(labInvoicesProvider);
      ref.invalidate(labFinancialSummaryProvider);

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم تسجيل دفعة بقيمة ${amt.toStringAsFixed(0)} ${widget.invoice.currencySymbol} بنجاح',
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
                    const Icon(Icons.payments_outlined, color: AppColors.gold, size: 24),
                    const SizedBox(width: 8),
                    Text(
                      'تسجيل دفعة على الفاتورة #${widget.invoice.invoiceNumber}',
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.gold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.cardBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'العميل: ${widget.invoice.clientName ?? "غير محدد"}',
                        style: const TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 13),
                      ),
                      Text(
                        'المتبقي: ${widget.invoice.remainingAmount.toStringAsFixed(0)} ${widget.invoice.currencySymbol}',
                        style: const TextStyle(
                          color: AppColors.gold,
                          fontFamily: 'Cairo',
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    labelText: 'مبلغ الدفعة (${widget.invoice.currencySymbol}) *',
                    labelStyle: const TextStyle(color: AppColors.textSecondary, fontFamily: 'Cairo'),
                    prefixIcon: const Icon(Icons.attach_money, color: AppColors.gold),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'المبلغ مطلوب';
                    final num = double.tryParse(v);
                    if (num == null || num <= 0) return 'أدخل رقماً صحيحاً أكبر من صفر';
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _method,
                  dropdownColor: AppColors.surface,
                  style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                  decoration: const InputDecoration(
                    labelText: 'طريقة الدفع *',
                    labelStyle: TextStyle(color: AppColors.textSecondary, fontFamily: 'Cairo'),
                    prefixIcon: Icon(Icons.account_balance_wallet_outlined, color: AppColors.gold),
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'cash', child: Text('نقداً (كاش)')),
                    DropdownMenuItem(value: 'sham_cash', child: Text('شام كاش (Sham Cash)')),
                    DropdownMenuItem(value: 'hawala', child: Text('حوالة هرم')),
                    DropdownMenuItem(value: 'bank_transfer', child: Text('تحويل مصرفي')),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _method = val);
                  },
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _receiptNumberController,
                        style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                        decoration: const InputDecoration(
                          labelText: 'رقم الإيصال اليدوي',
                          labelStyle: TextStyle(color: AppColors.textSecondary, fontFamily: 'Cairo'),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _refController,
                        style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                        decoration: const InputDecoration(
                          labelText: 'رقم الحوالة / العملية',
                          labelStyle: TextStyle(color: AppColors.textSecondary, fontFamily: 'Cairo'),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _notesController,
                  style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                  decoration: const InputDecoration(
                    labelText: 'ملاحظات الدفعة',
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
                              'تسجيل الدفعة',
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
