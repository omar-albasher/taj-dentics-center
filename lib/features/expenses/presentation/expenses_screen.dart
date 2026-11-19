import '../../../core/utils/app_error_handler.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/app_formatters.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/responsive.dart';
import '../data/expenses_repository.dart';
import '../domain/expense_model.dart';
import '../../accounts/data/accounts_repository.dart';

class ExpensesScreen extends ConsumerWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expensesAsync = ref.watch(expensesProvider);
    final fmt = AppFormatters.amount;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Padding(
        padding: EdgeInsets.all(Responsive.spacing(context, 24)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'المصاريف',
                  style: TextStyle(
                    fontSize: Responsive.fontSize(context, 28),
                    fontWeight: FontWeight.w900,
                    color: AppColors.gold,
                    fontFamily: 'Cairo',
                  ),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: () => _showAddExpenseDialog(context, ref),
                  icon: const Icon(Icons.add),
                  label: const Text('إضافة مصروف',
                      style: TextStyle(fontFamily: 'Cairo')),
                ),
              ],
            ),
            SizedBox(height: Responsive.spacing(context, 24)),
            Expanded(
              child: expensesAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(color: AppColors.gold),
                ),
                error: (e, _) => Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline,
                          color: AppColors.error, size: 48),
                      const SizedBox(height: 16),
                      Text(AppErrorHandler.friendlyMessage(e),
                          style: const TextStyle(
                              color: AppColors.error, fontFamily: 'Cairo')),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: () => ref.invalidate(expensesProvider),
                        child: const Text('إعادة المحاولة',
                            style: TextStyle(fontFamily: 'Cairo')),
                      ),
                    ],
                  ),
                ),
                data: (expenses) {
                  if (expenses.isEmpty) {
                    return Center(
                      child: Text('لا توجد مصاريف مسجّلة',
                          style: TextStyle(
                              color: AppColors.textSecondary,
                              fontFamily: 'Cairo',
                              fontSize: Responsive.fontSize(context, 16))),
                    );
                  }

                  return ListView.separated(
                    itemCount: expenses.length,
                    separatorBuilder: (_, __) =>
                        SizedBox(height: Responsive.spacing(context, 8)),
                    itemBuilder: (context, index) {
                      final e = expenses[index];
                      return Container(
                        padding:
                            EdgeInsets.all(Responsive.spacing(context, 16)),
                        decoration: BoxDecoration(
                          color: AppColors.cardBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.divider),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: AppColors.error.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                _categoryIcon(e.category),
                                color: AppColors.error,
                              ),
                            ),
                            SizedBox(width: Responsive.spacing(context, 12)),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(e.categoryAr,
                                      style: TextStyle(
                                          fontSize:
                                              Responsive.fontSize(context, 15),
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.textPrimary,
                                          fontFamily: 'Cairo')),
                                  if (e.description != null)
                                    Text(e.description!,
                                        style: TextStyle(
                                            fontSize: Responsive.fontSize(
                                                context, 12),
                                            color: AppColors.textSecondary,
                                            fontFamily: 'Cairo')),
                                  Text(
                                    AppFormatters.dateOnly
                                        .format(e.expenseDate),
                                    style: TextStyle(
                                        fontSize:
                                            Responsive.fontSize(context, 11),
                                        color: AppColors.textSecondary,
                                        fontFamily: 'Cairo'),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '${fmt.format(e.amount.toInt())} ${e.currency == 'USD' ? '\$' : 'ل.س'}',
                              style: TextStyle(
                                  fontSize: Responsive.fontSize(context, 16),
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.error,
                                  fontFamily: 'Cairo'),
                            ),
                            SizedBox(width: Responsive.spacing(context, 8)),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 20),
                              color: AppColors.textSecondary,
                              tooltip: 'تعديل',
                              onPressed: () =>
                                  _showEditExpenseDialog(context, ref, e),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20),
                              color: AppColors.error,
                              tooltip: 'حذف',
                              onPressed: () =>
                                  _confirmDeleteExpense(context, ref, e),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _categoryIcon(String category) {
    switch (category) {
      case 'rent':
        return Icons.home_outlined;
      case 'utilities':
        return Icons.bolt_outlined;
      case 'salary':
        return Icons.people_outlined;
      case 'supplies':
        return Icons.shopping_bag_outlined;
      default:
        return Icons.receipt_outlined;
    }
  }

  void _showAddExpenseDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => _ExpenseFormDialog(
        onSaved: () => ref.invalidate(expensesProvider),
      ),
    );
  }

  void _showEditExpenseDialog(
      BuildContext context, WidgetRef ref, ExpenseModel expense) {
    showDialog(
      context: context,
      builder: (_) => _ExpenseFormDialog(
        expense: expense,
        onSaved: () => ref.invalidate(expensesProvider),
      ),
    );
  }

  void _confirmDeleteExpense(
      BuildContext context, WidgetRef ref, ExpenseModel expense) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('تأكيد الحذف',
            style: TextStyle(
                fontFamily: 'Cairo',
                color: AppColors.gold,
                fontWeight: FontWeight.bold)),
        content: Text(
          'هل أنت متأكد من حذف مصروف "${expense.categoryAr}" بمبلغ ${AppFormatters.amount.format(expense.amount.toInt())} ${expense.currency == 'USD' ? '\$' : 'ل.س'}؟',
          style:
              const TextStyle(fontFamily: 'Cairo', color: AppColors.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء',
                style: TextStyle(
                    fontFamily: 'Cairo', color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ref
                    .read(expensesRepositoryProvider)
                    .deleteExpense(expense.id);
                ref.invalidate(expensesProvider);
                ref.invalidate(accountBalancesProvider);
                ref.invalidate(accountLedgerProvider);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('تم حذف المصروف بنجاح ✓'),
                        backgroundColor: AppColors.success),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(AppErrorHandler.friendlyMessage(e)),
                        backgroundColor: AppColors.error),
                  );
                }
              }
            },
            child: const Text('حذف',
                style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

class _ExpenseFormDialog extends ConsumerStatefulWidget {
  final ExpenseModel? expense;
  final VoidCallback onSaved;
  const _ExpenseFormDialog({this.expense, required this.onSaved});

  @override
  ConsumerState<_ExpenseFormDialog> createState() => _ExpenseFormDialogState();
}

class _ExpenseFormDialogState extends ConsumerState<_ExpenseFormDialog> {
  late final TextEditingController _amountCtrl;
  late final TextEditingController _descriptionCtrl;
  late String _category;
  late String _currency;
  late DateTime _date;
  String? _selectedAccountId;
  bool _loading = false;

  bool get _isEditing => widget.expense != null;

  @override
  void initState() {
    super.initState();
    final exp = widget.expense;
    _amountCtrl = TextEditingController(
      text: exp != null
          ? (exp.amount % 1 == 0
              ? exp.amount.toInt().toString()
              : exp.amount.toString())
          : '',
    );
    _descriptionCtrl = TextEditingController(text: exp?.description ?? '');
    _category = exp?.category ?? 'rent';
    _currency = exp?.currency ?? 'SYP';
    _date = exp?.expenseDate ?? DateTime.now();
    _selectedAccountId = exp?.accountId;
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_amountCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى إدخال المبلغ'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final parsedAmount = double.tryParse(_amountCtrl.text);
    if (parsedAmount == null || parsedAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى إدخال مبلغ صحيح أكبر من الصفر'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      if (_isEditing) {
        await ref.read(expensesRepositoryProvider).updateExpense(
              id: widget.expense!.id,
              category: _category,
              amount: parsedAmount,
              currency: _currency,
              expenseDate: _date,
              description:
                  _descriptionCtrl.text.isEmpty ? null : _descriptionCtrl.text,
              accountId: _selectedAccountId,
            );
      } else {
        await ref.read(expensesRepositoryProvider).addExpense(
              category: _category,
              amount: parsedAmount,
              currency: _currency,
              expenseDate: _date,
              description:
                  _descriptionCtrl.text.isEmpty ? null : _descriptionCtrl.text,
              accountId: _selectedAccountId,
            );
      }

      ref.invalidate(accountBalancesProvider);
      ref.invalidate(accountLedgerProvider);

      if (!mounted) return;
      Navigator.pop(context);
      widget.onSaved();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isEditing
              ? 'تم تعديل المصروف بنجاح ✓'
              : 'تم تسجيل المصروف بنجاح ✓'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(AppErrorHandler.friendlyMessage(e)),
            backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(accountBalancesProvider);
    return Dialog(
      backgroundColor: AppColors.cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: EdgeInsets.all(Responsive.spacing(context, 24)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_isEditing ? Icons.edit_note : Icons.money_off,
                      color: AppColors.gold),
                  SizedBox(width: Responsive.spacing(context, 8)),
                  Text(_isEditing ? 'تعديل المصروف' : 'إضافة مصروف جديد',
                      style: TextStyle(
                          fontSize: Responsive.fontSize(context, 18),
                          fontWeight: FontWeight.w700,
                          color: AppColors.gold,
                          fontFamily: 'Cairo')),
                  const Spacer(),
                  IconButton(
                    icon:
                        const Icon(Icons.close, color: AppColors.textSecondary),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(color: AppColors.divider),
              SizedBox(height: Responsive.spacing(context, 16)),

              // Category
              DropdownButtonFormField<String>(
                initialValue: _category,
                dropdownColor: AppColors.cardBg,
                decoration: _inputDecoration('الفئة', Icons.category_outlined),
                items: const [
                  DropdownMenuItem(
                      value: 'rent',
                      child: Text('إيجار',
                          style: TextStyle(
                              color: AppColors.textPrimary,
                              fontFamily: 'Cairo'))),
                  DropdownMenuItem(
                      value: 'utilities',
                      child: Text('فواتير',
                          style: TextStyle(
                              color: AppColors.textPrimary,
                              fontFamily: 'Cairo'))),
                  DropdownMenuItem(
                      value: 'salary',
                      child: Text('رواتب',
                          style: TextStyle(
                              color: AppColors.textPrimary,
                              fontFamily: 'Cairo'))),
                  DropdownMenuItem(
                      value: 'supplies',
                      child: Text('مستلزمات',
                          style: TextStyle(
                              color: AppColors.textPrimary,
                              fontFamily: 'Cairo'))),
                  DropdownMenuItem(
                      value: 'other',
                      child: Text('أخرى',
                          style: TextStyle(
                              color: AppColors.textPrimary,
                              fontFamily: 'Cairo'))),
                ],
                onChanged: (v) => setState(() => _category = v ?? 'rent'),
              ),

              SizedBox(height: Responsive.spacing(context, 12)),

              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _amountCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration:
                          _inputDecoration('المبلغ *', Icons.attach_money),
                    ),
                  ),
                  SizedBox(width: Responsive.spacing(context, 12)),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _currency,
                      dropdownColor: AppColors.cardBg,
                      decoration:
                          _inputDecoration('العملة', Icons.currency_exchange),
                      items: const [
                        DropdownMenuItem(
                            value: 'SYP',
                            child: Text('ل.س',
                                style: TextStyle(
                                    color: AppColors.textPrimary,
                                    fontFamily: 'Cairo'))),
                        DropdownMenuItem(
                            value: 'USD',
                            child: Text('\$',
                                style: TextStyle(
                                    color: AppColors.textPrimary,
                                    fontFamily: 'Cairo'))),
                      ],
                      onChanged: (v) => setState(() {
                        _currency = v ?? 'SYP';
                        _selectedAccountId = null;
                      }),
                    ),
                  ),
                ],
              ),

              SizedBox(height: Responsive.spacing(context, 12)),

              // Account Selector (Optional - defaults to cash box)
              accountsAsync.maybeWhen(
                data: (accounts) {
                  final matchingAccounts = accounts
                      .where((a) => a.currency == _currency && a.isActive)
                      .toList();
                  return DropdownButtonFormField<String?>(
                    key: ValueKey('exp_acc_${_currency}_$_selectedAccountId'),
                    initialValue: _selectedAccountId,
                    dropdownColor: AppColors.cardBg,
                    decoration: _inputDecoration(
                        'خصم من حساب (اختياري)', Icons.account_balance_wallet_outlined),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('تلقائي (صندوق المركز للعملة)',
                            style: TextStyle(
                                color: AppColors.textSecondary,
                                fontFamily: 'Cairo')),
                      ),
                      ...matchingAccounts.map((a) => DropdownMenuItem<String?>(
                            value: a.accountId,
                            child: Text(
                              '${a.nameAr} (${a.currency}) — رصيد: ${AppFormatters.amount.format(a.balance.toInt())}',
                              style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontFamily: 'Cairo'),
                            ),
                          )),
                    ],
                    onChanged: (v) => setState(() => _selectedAccountId = v),
                  );
                },
                orElse: () => const SizedBox.shrink(),
              ),

              SizedBox(height: Responsive.spacing(context, 12)),

              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(2024),
                    lastDate: DateTime(2030),
                  );
                  if (picked != null) setState(() => _date = picked);
                },
                child: Container(
                  padding: EdgeInsets.all(Responsive.spacing(context, 14)),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today,
                          color: AppColors.gold, size: 20),
                      SizedBox(width: Responsive.spacing(context, 8)),
                      Text(
                        AppFormatters.dateOnly.format(_date),
                        style: const TextStyle(
                            color: AppColors.textPrimary, fontFamily: 'Cairo'),
                      ),
                    ],
                  ),
                ),
              ),

              SizedBox(height: Responsive.spacing(context, 12)),

              TextField(
                controller: _descriptionCtrl,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: _inputDecoration(
                    'الوصف (اختياري)', Icons.description_outlined),
              ),

              SizedBox(height: Responsive.spacing(context, 24)),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                        side: const BorderSide(color: AppColors.divider),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('إلغاء',
                          style: TextStyle(fontFamily: 'Cairo')),
                    ),
                  ),
                  SizedBox(width: Responsive.spacing(context, 12)),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _loading ? null : _submit,
                      child: _loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.black, strokeWidth: 2))
                          : Text(_isEditing ? 'حفظ التعديل' : 'إضافة',
                              style: const TextStyle(fontFamily: 'Cairo')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle:
          const TextStyle(color: AppColors.textSecondary, fontFamily: 'Cairo'),
      prefixIcon: Icon(icon, color: AppColors.gold),
      filled: true,
      fillColor: AppColors.surface,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.divider)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.divider)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.gold, width: 2)),
    );
  }
}
