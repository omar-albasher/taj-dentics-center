import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/app_error_handler.dart';
import '../../../../core/utils/app_formatters.dart';
import '../../../accounts/data/accounts_repository.dart';
import '../../../accounts/domain/account_models.dart';
import '../../data/compensation_repository.dart';
import '../../domain/compensation_models.dart';

class PayTrainerDueDialog extends ConsumerStatefulWidget {
  final TrainerDue due;

  const PayTrainerDueDialog({
    super.key,
    required this.due,
  });

  static Future<bool?> show(
    BuildContext context, {
    required TrainerDue due,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PayTrainerDueDialog(due: due),
    );
  }

  @override
  ConsumerState<PayTrainerDueDialog> createState() =>
      _PayTrainerDueDialogState();
}

class _PayTrainerDueDialogState extends ConsumerState<PayTrainerDueDialog> {
  FinancialAccountBalance? _selectedAccount;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
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
                      child: const Icon(Icons.payments_outlined,
                          color: AppColors.gold, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'صرف أتعاب مدرب',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo',
                            ),
                          ),
                          Text(
                            'تسجيل دفعة أتعاب وخصمها من الخزينة تلقائياً (${widget.due.currency})',
                            style: const TextStyle(
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

                // Due details card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Column(
                    children: [
                      _detailRow('المدرب:', widget.due.trainerName),
                      const SizedBox(height: 8),
                      _detailRow(
                          'الكورس / الدفعة:',
                          '${widget.due.courseName} - ${widget.due.cohortName}'),
                      const SizedBox(height: 8),
                      _detailRow(
                          'فترة الاستحقاق:',
                          AppFormatters.monthYearAr
                              .format(widget.due.periodStart)),
                      const SizedBox(height: 8),
                      _detailRow(
                          'النسبة المطبقة:',
                          '${widget.due.appliedRatePercent.toStringAsFixed(1)}%'),
                      const Divider(color: AppColors.divider, height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'المستحق المحسوب',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontFamily: 'Cairo',
                                  fontSize: 11,
                                ),
                              ),
                              Text(
                                '${AppFormatters.amount.format(widget.due.calculatedDue)} ${widget.due.currency}',
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo',
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const Text(
                                'المصروف سابقاً',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontFamily: 'Cairo',
                                  fontSize: 11,
                                ),
                              ),
                              Text(
                                '${AppFormatters.amount.format(widget.due.paidTotal)} ${widget.due.currency}',
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontFamily: 'Cairo',
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text(
                                'المتبقي للصرف',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontFamily: 'Cairo',
                                  fontSize: 11,
                                ),
                              ),
                              Text(
                                '${AppFormatters.amount.format(widget.due.remaining)} ${widget.due.currency}',
                                style: const TextStyle(
                                  color: AppColors.gold,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo',
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Account Selector
                const Text(
                  'حساب الخزينة / الصندوق للصرف',
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
                            a.currency == widget.due.currency && a.isActive)
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
                          'لا يوجد حساب نشط بعملة ${widget.due.currency}!',
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
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                a.nameAr,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontFamily: 'Cairo',
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(width: 20),
                              Text(
                                'الرصيد: ${AppFormatters.amount.format(a.balance)} ${a.currency}',
                                style: TextStyle(
                                  color: a.balance >= widget.due.remaining
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
                          : (val) => setState(() => _selectedAccount = val),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: AppColors.surface,
                        prefixIcon: const Icon(
                            Icons.account_balance_wallet_outlined,
                            color: AppColors.gold,
                            size: 20),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: AppColors.divider),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: AppColors.divider),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                              color: AppColors.gold, width: 1.5),
                        ),
                      ),
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

                if (_selectedAccount != null &&
                    _selectedAccount!.balance < widget.due.remaining) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withAlpha(20),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.warning),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            color: AppColors.warning, size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'تنبيه: رصيد الحساب المختار أقل من المبلغ المطلوب صرفه.',
                            style: TextStyle(
                              color: AppColors.warning,
                              fontFamily: 'Cairo',
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

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
                      onPressed: _isLoading || _selectedAccount == null
                          ? null
                          : _submit,
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
                          : Text(
                              'تأكيد صرف ${AppFormatters.amount.format(widget.due.remaining)} ${widget.due.currency}',
                              style: const TextStyle(
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
    );
  }

  Widget _detailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontFamily: 'Cairo',
            fontSize: 12,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
            fontFamily: 'Cairo',
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (_selectedAccount == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await ref.read(compensationRepositoryProvider).payTrainerDue(
            widget.due.id,
            _selectedAccount!.accountId,
          );
      ref.invalidate(trainerDuesProvider(widget.due.periodStart));
      ref.invalidate(trainerPaymentsProvider(widget.due.id));
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
}
