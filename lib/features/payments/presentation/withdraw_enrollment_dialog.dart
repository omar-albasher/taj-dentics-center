import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/app_error_handler.dart';
import '../../../core/utils/app_formatters.dart';
import '../../../core/utils/responsive.dart';
import '../data/payments_repository.dart';

/// حوار انسحاب إداري: معاينة pro-rata من الخادم ثم تنفيذ التسوية والاسترداد.
class WithdrawEnrollmentDialog extends ConsumerStatefulWidget {
  final String enrollmentId;
  final String traineeName;
  final String courseName;

  const WithdrawEnrollmentDialog({
    super.key,
    required this.enrollmentId,
    required this.traineeName,
    required this.courseName,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String enrollmentId,
    required String traineeName,
    required String courseName,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => WithdrawEnrollmentDialog(
        enrollmentId: enrollmentId,
        traineeName: traineeName,
        courseName: courseName,
      ),
    );
  }

  @override
  ConsumerState<WithdrawEnrollmentDialog> createState() =>
      _WithdrawEnrollmentDialogState();
}

class _WithdrawEnrollmentDialogState
    extends ConsumerState<WithdrawEnrollmentDialog> {
  final _reasonCtrl = TextEditingController();
  final _sessionsCtrl = TextEditingController();

  Map<String, dynamic>? _preview;
  Map<String, dynamic>? _result;
  Object? _previewError;
  bool _loadingPreview = true;
  bool _submitting = false;
  bool _advancedOpen = false;
  bool _writeOff = false;
  int _previewSeq = 0;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _reasonCtrl.dispose();
    _sessionsCtrl.dispose();
    super.dispose();
  }

  int? get _sessionsOverride {
    final text = _sessionsCtrl.text.trim();
    if (text.isEmpty) return null;
    return int.tryParse(text);
  }

  String? get _sessionsError {
    final text = _sessionsCtrl.text.trim();
    if (text.isEmpty) return null;

    final value = int.tryParse(text);
    if (value == null) return 'أدخل عدداً صحيحاً';
    if (value < 0) return 'لا يمكن أن يكون عدد الجلسات سالباً';

    final total = (_preview?['total_sessions'] as num?)?.toInt();
    if (total != null && value > total) {
      return 'لا يمكن تجاوز إجمالي جلسات الكورس ($total)';
    }
    return null;
  }

  bool get _canSubmit =>
      !_submitting &&
      !_loadingPreview &&
      _preview != null &&
      _preview!['can_withdraw'] == true &&
      _reasonCtrl.text.trim().isNotEmpty &&
      _sessionsError == null;

  Future<void> _loadPreview() async {
    if (_sessionsError != null) {
      setState(() {});
      return;
    }

    final seq = ++_previewSeq;
    setState(() {
      _loadingPreview = true;
      _previewError = null;
    });

    try {
      final data = await ref
          .read(paymentsRepositoryProvider)
          .getWithdrawalPreview(
            enrollmentId: widget.enrollmentId,
            sessionsOverride: _sessionsOverride,
          );
      if (!mounted || seq != _previewSeq) return;
      setState(() {
        _preview = data;
        _loadingPreview = false;
        if (((data['debt_amount'] as num?)?.toDouble() ?? 0) <= 0) {
          _writeOff = false;
        }
      });
    } catch (e) {
      if (!mounted || seq != _previewSeq) return;
      setState(() {
        _previewError = e;
        _loadingPreview = false;
      });
    }
  }

  void _onSessionsChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      if (_sessionsError != null) {
        setState(() {});
        return;
      }
      _loadPreview();
    });
  }

  Future<void> _submit() async {
    final reason = _reasonCtrl.text.trim();
    if (reason.isEmpty) {
      _snack('سبب الانسحاب إلزامي', AppColors.error);
      return;
    }
    if (_sessionsError != null) {
      _snack(_sessionsError!, AppColors.error);
      return;
    }

    setState(() => _submitting = true);
    try {
      final result = await ref.read(paymentsRepositoryProvider).withdrawEnrollment(
            enrollmentId: widget.enrollmentId,
            reason: reason,
            writeOffDebt: _writeOff,
            sessionsOverride: _sessionsOverride,
          );
      if (!mounted) return;
      setState(() {
        _result = result;
        _submitting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _snack(AppErrorHandler.friendlyMessage(e), AppColors.error);
    }
  }

  void _snack(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontFamily: 'Cairo')),
        backgroundColor: color,
      ),
    );
  }

  String _money(num? value, String? currency) {
    final amount = (value ?? 0).toInt();
    return '${AppFormatters.amount.format(amount)} ${_currencySymbol(currency)}';
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final result = _result;
    final currency = (result?['currency'] ?? preview?['currency']) as String?;
    final debt = (preview?['debt_amount'] as num?)?.toDouble() ?? 0;

    return Dialog(
      backgroundColor: AppColors.cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(Responsive.spacing(context, 24)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.person_remove_outlined,
                      color: AppColors.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      result == null
                          ? 'تسجيل انسحاب — ${widget.traineeName}'
                          : 'تم تسجيل الانسحاب — ${widget.traineeName}',
                      style: TextStyle(
                        fontSize: Responsive.fontSize(context, 17),
                        fontWeight: FontWeight.w700,
                        color: result == null
                            ? AppColors.warning
                            : AppColors.success,
                        fontFamily: 'Cairo',
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close,
                        color: AppColors.textSecondary),
                    onPressed: _submitting
                        ? null
                        : () => Navigator.pop(context, result != null),
                  ),
                ],
              ),
              Text(
                widget.courseName,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontFamily: 'Cairo',
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              const Divider(color: AppColors.divider),
              if (result != null)
                _buildResult(context, result, currency)
              else if (_loadingPreview)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.gold),
                  ),
                )
              else if (_previewError != null)
                _buildPreviewError()
              else if (preview != null && preview['can_withdraw'] != true)
                _buildNotWithdrawable(preview)
              else if (preview != null)
                _buildPreviewForm(context, preview, currency, debt),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewError() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppErrorHandler.friendlyMessage(_previewError),
          style: const TextStyle(color: AppColors.error, fontFamily: 'Cairo'),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _loadingPreview ? null : _loadPreview,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('إعادة المحاولة',
              style: TextStyle(fontFamily: 'Cairo')),
        ),
      ],
    );
  }

  Widget _buildNotWithdrawable(Map<String, dynamic> preview) {
    final lifecycle = (preview['lifecycle_status'] ?? '').toString();
    final reason = (preview['reason'] ?? '').toString();
    final message = reason == 'ENROLLMENT_NOT_ACTIVE'
        ? 'لا يمكن الانسحاب: حالة التسجيل الحالية «${_lifecycleLabel(lifecycle)}»'
        : 'لا يمكن الانسحاب من هذا التسجيل حالياً';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.error.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border:
                Border.all(color: AppColors.error.withValues(alpha: 0.35)),
          ),
          child: Text(
            message,
            style: const TextStyle(
                color: AppColors.error, fontFamily: 'Cairo'),
          ),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: OutlinedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق',
                style: TextStyle(fontFamily: 'Cairo')),
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewForm(
    BuildContext context,
    Map<String, dynamic> preview,
    String? currency,
    double debt,
  ) {
    final total = (preview['total_sessions'] as num?)?.toInt() ?? 0;
    final charged = (preview['sessions_charged'] as num?)?.toInt() ?? 0;
    final outcome = (preview['outcome'] ?? 'settled').toString();
    final outcomeColor = _outcomeColor(outcome);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            _SummaryChip(
                label: 'الجلسات المستحقة',
                value: '$charged / $total',
                color: AppColors.gold),
            _SummaryChip(
                label: 'إجمالي الرسوم',
                value: _money(preview['net_due_before'] as num?, currency)),
            _SummaryChip(
                label: 'المسدد',
                value: _money(preview['net_paid'] as num?, currency),
                color: AppColors.success),
            _SummaryChip(
                label: 'المستحق بعد التسوية',
                value: _money(preview['due_amount'] as num?, currency),
                color: AppColors.warning),
            if ((preview['discount_revoked'] as num?)?.toDouble() != null &&
                (preview['discount_revoked'] as num).toDouble() > 0)
              _SummaryChip(
                label: 'خصم مُلغى (إحالة)',
                value: _money(preview['discount_revoked'] as num?, currency),
                color: AppColors.error),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: outcomeColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: outcomeColor.withValues(alpha: 0.35)),
          ),
          child: Text(
            _outcomeDescription(outcome, preview, currency),
            style: TextStyle(color: outcomeColor, fontFamily: 'Cairo'),
          ),
        ),
        SizedBox(height: Responsive.spacing(context, 16)),
        TextField(
          controller: _reasonCtrl,
          maxLines: 2,
          onChanged: (_) => setState(() {}),
          style: const TextStyle(
              color: AppColors.textPrimary, fontFamily: 'Cairo'),
          decoration: InputDecoration(
            labelText: 'سبب الانسحاب *',
            labelStyle: const TextStyle(
                color: AppColors.textSecondary, fontFamily: 'Cairo'),
            prefixIcon: const Icon(Icons.notes, color: AppColors.gold),
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
          ),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () => setState(() => _advancedOpen = !_advancedOpen),
          icon: Icon(
            _advancedOpen ? Icons.expand_less : Icons.expand_more,
            size: 18,
            color: AppColors.textSecondary,
          ),
          label: const Text(
            'خيارات متقدمة / تعديل الجلسات يدوياً (اختياري)',
            style: TextStyle(
                color: AppColors.textSecondary,
                fontFamily: 'Cairo',
                fontSize: 12),
          ),
        ),
        if (_advancedOpen) ...[
          TextField(
            controller: _sessionsCtrl,
            keyboardType: TextInputType.number,
            onChanged: _onSessionsChanged,
            style: const TextStyle(
                color: AppColors.textPrimary, fontFamily: 'Cairo'),
            decoration: InputDecoration(
              labelText: 'عدد الجلسات المحتسبة يدوياً',
              helperText:
                  'اتركه فارغاً لاحتساب الجلسات المنفذة فعلياً قبل تاريخ الانسحاب',
              helperMaxLines: 2,
              errorText: _sessionsError,
              labelStyle: const TextStyle(
                  color: AppColors.textSecondary, fontFamily: 'Cairo'),
              prefixIcon: const Icon(Icons.tune, color: AppColors.gold),
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
                  borderSide:
                      const BorderSide(color: AppColors.gold, width: 2)),
            ),
          ),
          if (_loadingPreview)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(color: AppColors.gold),
            ),
          const SizedBox(height: 4),
        ],
        if (debt > 0) ...[
          const SizedBox(height: 8),
          SwitchListTile(
            value: _writeOff,
            onChanged: (value) => setState(() => _writeOff = value),
            contentPadding: EdgeInsets.zero,
            activeThumbColor: AppColors.gold,
            title: const Text(
              'شطب الدين المتبقي بقرار الإدارة',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontFamily: 'Cairo',
                  fontSize: 13),
            ),
            subtitle: Text(
              'الدين المتبقي: ${_money(debt, currency)} — الشطب نهائي ويُسجل في التدقيق',
              style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontFamily: 'Cairo',
                  fontSize: 11),
            ),
          ),
        ],
        const SizedBox(height: 8),
        const Text(
          'الانسحاب متاح لمدير المركز فقط، ويحرر المقعد ويشعر قائمة '
          'الانتظار دون ترقية تلقائية.',
          style: TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
              fontFamily: 'Cairo'),
        ),
        SizedBox(height: Responsive.spacing(context, 20)),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed:
                    _submitting ? null : () => Navigator.pop(context, false),
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
                onPressed: _canSubmit ? _submit : null,
                child: _submitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            color: Colors.black, strokeWidth: 2))
                    : const Text('تأكيد الانسحاب',
                        style: TextStyle(fontFamily: 'Cairo')),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildResult(
    BuildContext context,
    Map<String, dynamic> result,
    String? currency,
  ) {
    final outcome = (result['outcome'] ?? 'settled').toString();
    final color = _outcomeColor(outcome);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Text(
            _outcomeResultLabel(outcome),
            style: TextStyle(
                color: color, fontFamily: 'Cairo', fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            _SummaryChip(
                label: 'جلسات محتسبة',
                value:
                    '${result['sessions_charged'] ?? 0} / ${result['total_sessions'] ?? 0}'),
            _SummaryChip(
                label: 'المستحق النهائي',
                value: _money(result['net_due_after'] as num?, currency)),
            _SummaryChip(
                label: 'المسدد النهائي',
                value: _money(result['net_paid_after'] as num?, currency),
                color: AppColors.success),
            if ((result['refund_amount'] as num?)?.toDouble() != null &&
                (result['refund_amount'] as num).toDouble() > 0)
              _SummaryChip(
                  label: 'مبلغ الاسترداد',
                  value: _money(result['refund_amount'] as num?, currency),
                  color: AppColors.gold),
            if ((result['writeoff_amount'] as num?)?.toDouble() != null &&
                (result['writeoff_amount'] as num).toDouble() > 0)
              _SummaryChip(
                  label: 'مبلغ الشطب',
                  value: _money(result['writeoff_amount'] as num?, currency),
                  color: AppColors.warning),
            if ((result['debt_amount'] as num?)?.toDouble() != null &&
                (result['debt_amount'] as num).toDouble() > 0)
              _SummaryChip(
                  label: 'دين متبقٍ',
                  value: _money(result['debt_amount'] as num?, currency),
                  color: AppColors.error),
          ],
        ),
        const SizedBox(height: 16),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('إغلاق', style: TextStyle(fontFamily: 'Cairo')),
          ),
        ),
      ],
    );
  }

  static String _lifecycleLabel(String lifecycle) {
    switch (lifecycle) {
      case 'withdrawn':
        return 'منسحب';
      case 'completed':
        return 'مكتمل';
      default:
        return 'نشط';
    }
  }

  static Color _outcomeColor(String outcome) {
    switch (outcome) {
      case 'refund':
        return AppColors.gold;
      case 'debt':
        return AppColors.error;
      case 'writeoff':
        return AppColors.success;
      default:
        return AppColors.success;
    }
  }

  static String _outcomeResultLabel(String outcome) {
    switch (outcome) {
      case 'refund':
        return 'تم الانسحاب وسيُعاد للمتدرب فائض الدفع';
      case 'debt':
        return 'تم الانسحاب مع بقاء دين على المتدرب';
      case 'writeoff':
        return 'تم الانسحاب وشطب الدين المتبقي';
      default:
        return 'تم الانسحاب وتسوية الالتزام بالكامل';
    }
  }

  String _outcomeDescription(
    String outcome,
    Map<String, dynamic> preview,
    String? currency,
  ) {
    switch (outcome) {
      case 'refund':
        return 'سيُسترد فائض قدره '
            '${_money(preview['refundable'] as num?, currency)} '
            'من أحدث الدفعات أولاً (LIFO).';
      case 'debt':
        return 'سيبقى دين على المتدرب قدره '
            '${_money(preview['debt_amount'] as num?, currency)} '
            'إلا إذا اخترت شطبه.';
      default:
        return 'المدفوع يطابق المستحق بعد احتساب الجلسات المقدمة — لا استرداد ولا دين.';
    }
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _SummaryChip({
    required this.label,
    required this.value,
    this.color = AppColors.textPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ',
              style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  fontFamily: 'Cairo')),
          Text(value,
              style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Cairo')),
        ],
      ),
    );
  }
}

String _currencySymbol(String? currency) =>
    currency == 'USD' ? r'$' : 'ل.س';
