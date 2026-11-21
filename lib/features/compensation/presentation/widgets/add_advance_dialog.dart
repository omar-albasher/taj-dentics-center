import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/app_error_handler.dart';
import '../../../../core/utils/app_formatters.dart';
import '../../../accounts/data/accounts_repository.dart';
import '../../../accounts/domain/account_models.dart';
import '../../data/compensation_repository.dart';
import '../../domain/compensation_models.dart';

class AddAdvanceDialog extends ConsumerStatefulWidget {
  const AddAdvanceDialog({super.key});

  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AddAdvanceDialog(),
    );
  }

  @override
  ConsumerState<AddAdvanceDialog> createState() => _AddAdvanceDialogState();
}

class _AddAdvanceDialogState extends ConsumerState<AddAdvanceDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _reasonController = TextEditingController();

  CompensationUser? _selectedStaff;
  String _selectedCurrency = 'SYP';
  FinancialAccountBalance? _selectedAccount;
  DateTime _advancedAt = DateTime.now();

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _amountController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  double get _enteredAmount =>
      double.tryParse(_amountController.text.trim()) ?? 0.0;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedStaff == null) {
      setState(() => _errorMessage = 'يرجى اختيار الموظف');
      return;
    }
    if (_selectedAccount == null) {
      setState(() => _errorMessage = 'يرجى اختيار حساب الخزينة لصرف السلفة');
      return;
    }

    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _errorMessage = 'يرجى إدخال مبلغ سلفة صالح');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await ref.read(compensationRepositoryProvider).addAdvance(
            userId: _selectedStaff!.id,
            amount: amount,
            currency: _selectedCurrency,
            accountId: _selectedAccount!.accountId,
            advancedAt: _advancedAt,
            reason: _reasonController.text.trim().isEmpty
                ? null
                : _reasonController.text.trim(),
          );
      ref.invalidate(advancesProvider);
      ref.invalidate(accountBalancesProvider);
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

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _advancedAt,
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
      setState(() => _advancedAt = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final staffAsync = ref.watch(compensationStaffProvider);
    final accountsAsync = ref.watch(accountBalancesProvider);

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
                    // Header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.gold.withAlpha(30),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.money_off,
                              color: AppColors.gold, size: 24),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'صرف سلفة لموظف',
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                              Text(
                                'خصم المبلغ من الخزينة فوراً وتنزيله من المسير القادم',
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
                      'الموظف المستفيد',
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

                    // Amount & Currency
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'مبلغ السلفة',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: _amountController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                      RegExp(r'^\d*\.?\d*')),
                                ],
                                onChanged: (_) => setState(() {}),
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontFamily: 'Cairo',
                                  fontWeight: FontWeight.bold,
                                ),
                                decoration: _inputDecoration(
                                  hintText: 'مثال: 200000',
                                  prefixIcon: Icons.attach_money,
                                ),
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) {
                                    return 'يرجى إدخال المبلغ';
                                  }
                                  final val = double.tryParse(v.trim());
                                  if (val == null || val <= 0) {
                                    return 'مبلغ غير صالح';
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
                                    child: Text('ليرة سورية',
                                        style: TextStyle(
                                            color: AppColors.textPrimary,
                                            fontFamily: 'Cairo',
                                            fontSize: 13)),
                                  ),
                                  DropdownMenuItem(
                                    value: 'USD',
                                    child: Text('دولار أمريكي',
                                        style: TextStyle(
                                            color: AppColors.textPrimary,
                                            fontFamily: 'Cairo',
                                            fontSize: 13)),
                                  ),
                                ],
                                onChanged: _isLoading
                                    ? null
                                    : (val) {
                                        setState(() {
                                          _selectedCurrency = val ?? 'SYP';
                                          _selectedAccount = null;
                                        });
                                      },
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

                    // Account selector (matches currency)
                    const Text(
                      'حساب الخزينة المسحوب منه',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    accountsAsync.when(
                      data: (accounts) {
                        final matching = accounts
                            .where((a) =>
                                a.currency == _selectedCurrency && a.isActive)
                            .toList();

                        if (matching.isEmpty) {
                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.error.withAlpha(20),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.error),
                            ),
                            child: Text(
                              'لا يوجد حساب خزينة نشط بعملة $_selectedCurrency',
                              style: const TextStyle(
                                color: AppColors.error,
                                fontFamily: 'Cairo',
                                fontSize: 12,
                              ),
                            ),
                          );
                        }

                        if (_selectedAccount == null && matching.isNotEmpty) {
                          _selectedAccount = matching.first;
                        }

                        return DropdownButtonFormField<FinancialAccountBalance>(
                          initialValue: _selectedAccount,
                          dropdownColor: AppColors.surface,
                          items: matching.map((a) {
                            return DropdownMenuItem(
                              value: a,
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    a.nameAr,
                                    style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontFamily: 'Cairo',
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Text(
                                    'الرصيد: ${AppFormatters.amount.format(a.balance)} ${a.currency}',
                                    style: TextStyle(
                                      color: a.balance >= _enteredAmount
                                          ? AppColors.success
                                          : AppColors.warning,
                                      fontFamily: 'Cairo',
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: _isLoading
                              ? null
                              : (val) =>
                                  setState(() => _selectedAccount = val),
                          decoration: _inputDecoration(
                            hintText: 'اختر الحساب',
                            prefixIcon: Icons.account_balance_wallet_outlined,
                          ),
                          validator: (v) =>
                              v == null ? 'يرجى اختيار الحساب' : null,
                        );
                      },
                      loading: () => const LinearProgressIndicator(
                          color: AppColors.gold, minHeight: 2),
                      error: (e, _) => Text(
                        'خطأ في تحميل الحسابات: $e',
                        style: const TextStyle(
                            color: AppColors.error, fontSize: 12),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Date of advance
                    const Text(
                      'تاريخ منح السلفة',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: _isLoading ? null : _pickDate,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.divider),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today,
                                size: 18, color: AppColors.gold),
                            const SizedBox(width: 10),
                            Text(
                              AppFormatters.dateOnly.format(_advancedAt),
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontFamily: 'Cairo',
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Reason
                    const Text(
                      'سبب السلفة / ملاحظات',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _reasonController,
                      maxLines: 2,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontFamily: 'Cairo',
                        fontSize: 13,
                      ),
                      decoration: _inputDecoration(
                        hintText: 'مثال: سلفة طارئة على حساب راتب الشهر القادم',
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
                                  'صرف السلفة',
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
