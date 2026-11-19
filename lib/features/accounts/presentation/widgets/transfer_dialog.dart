import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../../../core/constants/app_colors.dart';
import '../../data/accounts_repository.dart';
import '../../domain/account_models.dart';

class TransferDialog extends ConsumerStatefulWidget {
  final List<FinancialAccountBalance> accounts;
  final String? initialFromAccountId;

  const TransferDialog({
    super.key,
    required this.accounts,
    this.initialFromAccountId,
  });

  static Future<bool?> show(
    BuildContext context, {
    required List<FinancialAccountBalance> accounts,
    String? initialFromAccountId,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => TransferDialog(
        accounts: accounts,
        initialFromAccountId: initialFromAccountId,
      ),
    );
  }

  @override
  ConsumerState<TransferDialog> createState() => _TransferDialogState();
}

class _TransferDialogState extends ConsumerState<TransferDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();

  FinancialAccountBalance? _fromAccount;
  FinancialAccountBalance? _toAccount;
  bool _isLoading = false;
  bool _allowNegativeConfirmed = false;
  String? _errorMessage;

  final _currencyFormat = NumberFormat('#,##0.##');

  @override
  void initState() {
    super.initState();
    if (widget.accounts.isNotEmpty) {
      if (widget.initialFromAccountId != null) {
        _fromAccount = widget.accounts.firstWhere(
          (a) => a.accountId == widget.initialFromAccountId,
          orElse: () => widget.accounts.first,
        );
      } else {
        _fromAccount = widget.accounts.first;
      }
      _updateAvailableToAccounts();
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _updateAvailableToAccounts() {
    if (_fromAccount == null) {
      _toAccount = null;
      return;
    }
    final validTargets = widget.accounts.where(
      (a) =>
          a.accountId != _fromAccount!.accountId &&
          a.currency == _fromAccount!.currency &&
          a.isActive,
    );
    if (_toAccount == null ||
        _toAccount!.accountId == _fromAccount!.accountId ||
        _toAccount!.currency != _fromAccount!.currency) {
      _toAccount = validTargets.isNotEmpty ? validTargets.first : null;
    }
  }

  double get _enteredAmount =>
      double.tryParse(_amountController.text.trim()) ?? 0.0;

  bool get _isExceedingBalance {
    if (_fromAccount == null || _enteredAmount <= 0) return false;
    return _enteredAmount > _fromAccount!.balance;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_fromAccount == null || _toAccount == null) return;

    if (_isExceedingBalance && !_allowNegativeConfirmed) {
      setState(() {
        _errorMessage = 'يرجى تأكيد الموافقة على التحويل برصيد مكشوف.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await ref.read(accountsRepositoryProvider).transferBetweenAccounts(
            fromAccountId: _fromAccount!.accountId,
            toAccountId: _toAccount!.accountId,
            amount: _enteredAmount,
            notes: _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
          );

      ref.invalidate(accountBalancesProvider);
      ref.invalidate(accountLedgerProvider);

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'تم التحويل الداخلي بنجاح وتم تسجيل الحركتين بالدفتر',
              style: TextStyle(fontFamily: 'Cairo'),
            ),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final validTargets = _fromAccount == null
        ? <FinancialAccountBalance>[]
        : widget.accounts
            .where((a) =>
                a.accountId != _fromAccount!.accountId &&
                a.currency == _fromAccount!.currency &&
                a.isActive)
            .toList();

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
                          child: const Icon(Icons.swap_horiz,
                              color: AppColors.gold, size: 28),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'تحويل مالي داخلي بين الحسابات',
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                              Text(
                                'التحويل متاح بين الحسابات التي تحمل نفس العملة فقط',
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
                    const SizedBox(height: 20),
                    const Divider(color: AppColors.divider),
                    const SizedBox(height: 16),

                    // Error Message Banner
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
                                color: AppColors.error, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(
                                  color: AppColors.error,
                                  fontSize: 13,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // From Account Dropdown
                    const Text(
                      'من حساب (المصدر):',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Cairo',
                      ),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<FinancialAccountBalance>(
                      key: ValueKey('from_${_fromAccount?.accountId}'),
                      initialValue: _fromAccount,
                      isExpanded: true,
                      dropdownColor: AppColors.surface,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.outbox, color: AppColors.gold),
                      ),
                      items: widget.accounts.where((a) => a.isActive).map((acc) {
                        return DropdownMenuItem(
                          value: acc,
                          child: Text(
                            '${acc.nameAr} (${acc.currency}) — الرصيد: ${_currencyFormat.format(acc.balance)}',
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 13,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        );
                      }).toList(),
                      onChanged: _isLoading
                          ? null
                          : (val) {
                              setState(() {
                                _fromAccount = val;
                                _updateAvailableToAccounts();
                              });
                            },
                    ),
                    const SizedBox(height: 16),

                    // To Account Dropdown
                    const Text(
                      'إلى حساب (الوجهة):',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Cairo',
                      ),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<FinancialAccountBalance>(
                      key: ValueKey('to_${_toAccount?.accountId}'),
                      initialValue: _toAccount,
                      isExpanded: true,
                      dropdownColor: AppColors.surface,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.move_to_inbox, color: AppColors.gold),
                      ),
                      items: validTargets.map((acc) {
                        return DropdownMenuItem(
                          value: acc,
                          child: Text(
                            '${acc.nameAr} (${acc.currency}) — الرصيد: ${_currencyFormat.format(acc.balance)}',
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 13,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        );
                      }).toList(),
                      onChanged: _isLoading
                          ? null
                          : (val) {
                              setState(() {
                                _toAccount = val;
                              });
                            },
                      validator: (val) {
                        if (val == null) {
                          return 'يرجى تحديد حساب الوجهة';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Amount Field
                    Text(
                      'المبلغ المطلوب تحويله (${_fromAccount?.currency ?? ""}):',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Cairo',
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _amountController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.attach_money,
                            color: AppColors.gold),
                        suffixText: _fromAccount?.currency,
                        hintText: '0.00',
                      ),
                      onChanged: (_) => setState(() {}),
                      validator: (val) {
                        final v = double.tryParse(val?.trim() ?? '');
                        if (v == null || v <= 0) {
                          return 'يرجى إدخال مبلغ صحيح أكبر من صفر';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Overdraft Warning Banner
                    if (_isExceedingBalance) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withAlpha(25),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.warning),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.warning_amber_rounded,
                                    color: AppColors.warning, size: 22),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'تنبيه: المبلغ يتجاوز الرصيد المتوفر (${_currencyFormat.format(_fromAccount!.balance)} ${_fromAccount!.currency})',
                                    style: const TextStyle(
                                      color: AppColors.warning,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      fontFamily: 'Cairo',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'سيصبح رصيد حساب "${_fromAccount!.nameAr}" بعد التحويل: ${_currencyFormat.format(_fromAccount!.balance - _enteredAmount)} ${_fromAccount!.currency} (رصيد مكشوف).',
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 12,
                                fontFamily: 'Cairo',
                              ),
                            ),
                            const SizedBox(height: 8),
                            CheckboxListTile(
                              value: _allowNegativeConfirmed,
                              onChanged: (val) {
                                setState(() {
                                  _allowNegativeConfirmed = val == true;
                                });
                              },
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              activeColor: AppColors.warning,
                              title: const Text(
                                'أؤكد إجراء التحويل والسماح برصيد مكشوف مؤقتاً',
                                style: TextStyle(
                                  color: AppColors.textPrimary,
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

                    // Notes Field
                    const Text(
                      'ملاحظات / سبب التحويل (اختياري):',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Cairo',
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _notesController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        hintText: 'مثال: سحب رصيد Sham Cash وإيداعه بالصندوق النقدي',
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Actions
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed:
                              _isLoading ? null : () => Navigator.pop(context),
                          child: const Text(
                            'إلغاء',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontFamily: 'Cairo',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: _isLoading ? null : _submit,
                          icon: _isLoading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.black,
                                  ),
                                )
                              : const Icon(Icons.check, size: 20),
                          label: Text(
                            _isLoading ? 'جارٍ التحويل...' : 'تأكيد التحويل',
                            style: const TextStyle(fontFamily: 'Cairo'),
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
}
