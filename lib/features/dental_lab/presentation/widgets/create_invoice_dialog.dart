import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../data/dental_lab_repository.dart';

class _DraftItem {
  String serviceName;
  String toothNumber;
  String shade;
  int quantity;
  double unitPrice;

  _DraftItem({
    this.serviceName = 'زركونيا تشريحي (Anatomic Zirconia)',
    this.quantity = 1,
    this.unitPrice = 0.0,
  }) : toothNumber = '', shade = 'A2';

  double get total => quantity * unitPrice;
}

class CreateInvoiceDialog extends ConsumerStatefulWidget {
  const CreateInvoiceDialog({super.key});

  @override
  ConsumerState<CreateInvoiceDialog> createState() => _CreateInvoiceDialogState();
}

class _CreateInvoiceDialogState extends ConsumerState<CreateInvoiceDialog> {
  final _formKey = GlobalKey<FormState>();
  final _patientController = TextEditingController();
  final _discountController = TextEditingController(text: '0');
  final _notesController = TextEditingController();

  String? _selectedClientId;
  String _currency = 'SYP';
  final DateTime _issueDate = DateTime.now();
  DateTime? _dueDate;
  bool _isLoading = false;

  final List<_DraftItem> _items = [
    _DraftItem(serviceName: 'زركونيا تشريحي (Anatomic Zirconia)', quantity: 1, unitPrice: 0),
  ];

  static const _commonServices = [
    'زركونيا تشريحي (Anatomic Zirconia)',
    'زركون متعدد الطبقات (Multilayer Zirconia)',
    'تاج إيماكس (E-Max Crown)',
    'فينير إيماكس (E-Max Veneer)',
    'خزف على معدن (PFM Crown)',
    'تاج مؤقت PMMA',
    'طابع فردي (Custom Tray)',
    'صفيحة عضة ليلية (Night Guard)',
    'صب وقاعدة موديل',
    'إصلاح / تلميع تعويض سنّي',
  ];

  double get _subtotal => _items.fold(0.0, (acc, item) => acc + item.total);
  double get _discount => double.tryParse(_discountController.text) ?? 0.0;
  double get _total => (_subtotal - _discount).clamp(0.0, double.infinity);

  @override
  void dispose() {
    _patientController.dispose();
    _discountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedClientId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى اختيار العيادة / الطبيب أولاً', style: TextStyle(fontFamily: 'Cairo'))),
      );
      return;
    }
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إضافة بند واحد على الأقل للفاتورة', style: TextStyle(fontFamily: 'Cairo'))),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final repo = ref.read(dentalLabRepositoryProvider);
      final itemsData = _items.map((item) {
        return {
          'service_name': item.serviceName,
          if (item.toothNumber.isNotEmpty) 'tooth_number': item.toothNumber,
          if (item.shade.isNotEmpty) 'shade': item.shade,
          'quantity': item.quantity,
          'unit_price': item.unitPrice,
        };
      }).toList();

      await repo.createInvoiceWithItems(
        clientId: _selectedClientId!,
        patientName: _patientController.text.isEmpty ? null : _patientController.text,
        currency: _currency,
        discount: _discount,
        issueDate: _issueDate,
        dueDate: _dueDate,
        notes: _notesController.text.isEmpty ? null : _notesController.text,
        items: itemsData,
      );

      ref.invalidate(labInvoicesProvider);
      ref.invalidate(labFinancialSummaryProvider);

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إصدار فاتورة المخبر بنجاح', style: TextStyle(fontFamily: 'Cairo')),
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
    final clientsAsync = ref.watch(labClientsProvider);

    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.gold, width: 1),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 750, maxHeight: 850),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Title
                Row(
                  children: [
                    const Icon(Icons.post_add_rounded, color: AppColors.gold, size: 28),
                    const SizedBox(width: 10),
                    const Text(
                      'إصدار فاتورة أعمال مخبرية جديدة',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: AppColors.gold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Main form content
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Client & Currency row
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: clientsAsync.when(
                                data: (clients) {
                                  return DropdownButtonFormField<String>(
                                    initialValue: _selectedClientId,
                                    dropdownColor: AppColors.surface,
                                    style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                                    decoration: const InputDecoration(
                                      labelText: 'العيادة / الطبيب *',
                                      labelStyle: TextStyle(color: AppColors.textSecondary, fontFamily: 'Cairo'),
                                      prefixIcon: Icon(Icons.medical_services_outlined, color: AppColors.gold),
                                      border: OutlineInputBorder(),
                                    ),
                                    items: clients.map((c) {
                                      return DropdownMenuItem(
                                        value: c.id,
                                        child: Text(c.name),
                                      );
                                    }).toList(),
                                    validator: (v) => v == null ? 'يرجى اختيار العميل' : null,
                                    onChanged: (v) => setState(() => _selectedClientId = v),
                                  );
                                },
                                loading: () => const LinearProgressIndicator(color: AppColors.gold),
                                error: (e, _) => Text('خطأ في تحميل العملاء: $e', style: const TextStyle(color: Colors.red)),
                              ),
                            ),
                            const SizedBox(width: 12),
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

                        // Patient/Case title
                        TextFormField(
                          controller: _patientController,
                          style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                          decoration: const InputDecoration(
                            labelText: 'اسم المريض / رقم الحالة (اختياري)',
                            labelStyle: TextStyle(color: AppColors.textSecondary, fontFamily: 'Cairo'),
                            prefixIcon: Icon(Icons.person_outline, color: AppColors.gold),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Section: Items
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'بنود وخدمات الفاتورة',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppColors.gold,
                              ),
                            ),
                            TextButton.icon(
                              icon: const Icon(Icons.add, color: AppColors.gold, size: 18),
                              label: const Text('إضافة بند', style: TextStyle(fontFamily: 'Cairo', color: AppColors.gold)),
                              onPressed: () {
                                setState(() {
                                  _items.add(_DraftItem());
                                });
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Items dynamic list
                        ..._items.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final item = entry.value;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.cardBg,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.divider),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: Autocomplete<String>(
                                        initialValue: TextEditingValue(text: item.serviceName),
                                        optionsBuilder: (textEditingValue) {
                                          if (textEditingValue.text.isEmpty) {
                                            return _commonServices;
                                          }
                                          return _commonServices.where((s) =>
                                              s.contains(textEditingValue.text));
                                        },
                                        onSelected: (val) {
                                          setState(() => item.serviceName = val);
                                        },
                                        fieldViewBuilder: (ctx, ctrl, focusNode, onFieldSubmitted) {
                                          return TextFormField(
                                            controller: ctrl,
                                            focusNode: focusNode,
                                            style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 13),
                                            decoration: const InputDecoration(
                                              labelText: 'اسم الخدمة / التعويض',
                                              labelStyle: TextStyle(color: AppColors.textSecondary, fontFamily: 'Cairo'),
                                              border: OutlineInputBorder(),
                                              isDense: true,
                                            ),
                                            onChanged: (v) => item.serviceName = v,
                                          );
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      flex: 1,
                                      child: TextFormField(
                                        initialValue: item.toothNumber,
                                        style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 13),
                                        decoration: const InputDecoration(
                                          labelText: 'رقم السن',
                                          labelStyle: TextStyle(color: AppColors.textSecondary, fontFamily: 'Cairo'),
                                          border: OutlineInputBorder(),
                                          isDense: true,
                                        ),
                                        onChanged: (v) => item.toothNumber = v,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      flex: 1,
                                      child: TextFormField(
                                        initialValue: item.shade,
                                        style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 13),
                                        decoration: const InputDecoration(
                                          labelText: 'اللون (Shade)',
                                          labelStyle: TextStyle(color: AppColors.textSecondary, fontFamily: 'Cairo'),
                                          border: OutlineInputBorder(),
                                          isDense: true,
                                        ),
                                        onChanged: (v) => item.shade = v,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      flex: 1,
                                      child: TextFormField(
                                        initialValue: item.quantity.toString(),
                                        keyboardType: TextInputType.number,
                                        style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 13),
                                        decoration: const InputDecoration(
                                          labelText: 'العدد',
                                          labelStyle: TextStyle(color: AppColors.textSecondary, fontFamily: 'Cairo'),
                                          border: OutlineInputBorder(),
                                          isDense: true,
                                        ),
                                        onChanged: (v) {
                                          setState(() {
                                            item.quantity = int.tryParse(v) ?? 1;
                                          });
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      flex: 2,
                                      child: TextFormField(
                                        initialValue: item.unitPrice == 0 ? '' : item.unitPrice.toString(),
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.bold),
                                        decoration: InputDecoration(
                                          labelText: 'سعر الوحدة (${_currency == "USD" ? "\$" : "ل.س"})',
                                          labelStyle: const TextStyle(color: AppColors.textSecondary, fontFamily: 'Cairo'),
                                          border: const OutlineInputBorder(),
                                          isDense: true,
                                        ),
                                        onChanged: (v) {
                                          setState(() {
                                            item.unitPrice = double.tryParse(v) ?? 0.0;
                                          });
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        'الإجمالي: ${item.total.toStringAsFixed(0)} ${_currency == "USD" ? "\$" : "ل.س"}',
                                        style: const TextStyle(
                                          color: AppColors.gold,
                                          fontWeight: FontWeight.bold,
                                          fontFamily: 'Cairo',
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                    if (_items.length > 1)
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                        onPressed: () {
                                          setState(() {
                                            _items.removeAt(idx);
                                          });
                                        },
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        }),

                        const SizedBox(height: 12),

                        // Discount & Notes
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _discountController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                                decoration: InputDecoration(
                                  labelText: 'الخصم (${_currency == "USD" ? "\$" : "ل.س"})',
                                  labelStyle: const TextStyle(color: AppColors.textSecondary, fontFamily: 'Cairo'),
                                  border: const OutlineInputBorder(),
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _notesController,
                                style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                                decoration: const InputDecoration(
                                  labelText: 'ملاحظات الفاتورة',
                                  labelStyle: TextStyle(color: AppColors.textSecondary, fontFamily: 'Cairo'),
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // Live summary card
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.gold.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'المجموع: ${_subtotal.toStringAsFixed(0)} ${_currency == "USD" ? "\$" : "ل.س"}',
                                style: const TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 13),
                              ),
                              Text(
                                'الخصم: ${_discount.toStringAsFixed(0)} ${_currency == "USD" ? "\$" : "ل.س"}',
                                style: const TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 13),
                              ),
                              Text(
                                'المبلغ النهائي: ${_total.toStringAsFixed(0)} ${_currency == "USD" ? "\$" : "ل.س"}',
                                style: const TextStyle(
                                  color: AppColors.gold,
                                  fontFamily: 'Cairo',
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),
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
                        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
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
                              'إصدار الفاتورة',
                              style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w900),
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
