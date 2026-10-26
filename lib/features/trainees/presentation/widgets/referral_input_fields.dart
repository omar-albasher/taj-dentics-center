import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/app_error_handler.dart';
import '../../../../core/utils/responsive.dart';
import '../../data/trainees_repository.dart';
import '../../domain/referral_models.dart';

class ReferralSelection {
  final String? code;
  final double amount;
  final bool isVerified;

  const ReferralSelection({
    this.code,
    this.amount = 0,
    this.isVerified = false,
  });

  bool get hasCode => code != null;
}

class ReferralInputFields extends ConsumerStatefulWidget {
  final ValueChanged<ReferralSelection> onChanged;
  final String currency;

  const ReferralInputFields({
    super.key,
    required this.onChanged,
    this.currency = 'SYP',
  });

  @override
  ReferralInputFieldsState createState() => ReferralInputFieldsState();
}

class ReferralInputFieldsState extends ConsumerState<ReferralInputFields> {
  final _codeCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  ReferralPreview? _preview;
  String? _verifiedCode;
  String? _error;
  bool _checking = false;

  @override
  void dispose() {
    _codeCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  ReferralSelection _selection() {
    final code = _codeCtrl.text.trim().toUpperCase();
    final amount = double.tryParse(_amountCtrl.text.trim()) ?? 0;
    return ReferralSelection(
      code: code.isEmpty ? null : code,
      amount: amount,
      isVerified:
          code.isNotEmpty && _verifiedCode == code && _preview?.valid == true,
    );
  }

  void _notify() => widget.onChanged(_selection());

  Future<ReferralPreview?> verify() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.isEmpty) {
      if (mounted) {
        setState(() {
          _preview = null;
          _verifiedCode = null;
          _error = null;
        });
      }
      _notify();
      return null;
    }

    setState(() {
      _checking = true;
      _error = null;
    });

    try {
      final preview =
          await ref.read(traineesRepositoryProvider).previewReferralCode(code);
      if (!mounted) return null;
      setState(() {
        _preview = preview.valid ? preview : null;
        _verifiedCode = preview.valid ? code : null;
        _error = preview.valid
            ? null
            : AppErrorHandler.friendlyMessage(
                PostgrestException(
                  message: preview.error ?? 'REFERRAL_CODE_INVALID',
                  code: 'P0001',
                ),
              );
      });
      _notify();
      return preview;
    } catch (e) {
      if (!mounted) return null;
      setState(() {
        _preview = null;
        _verifiedCode = null;
        _error = AppErrorHandler.friendlyMessage(e);
      });
      _notify();
      return null;
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  void _onCodeChanged(String _) {
    setState(() {
      _preview = null;
      _verifiedCode = null;
      _error = null;
    });
    _notify();
  }

  void _onAmountChanged(String _) => _notify();

  @override
  Widget build(BuildContext context) {
    final hasCode = _codeCtrl.text.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _codeCtrl,
          textCapitalization: TextCapitalization.characters,
          style: const TextStyle(color: AppColors.textPrimary),
          onChanged: _onCodeChanged,
          decoration: InputDecoration(
            labelText: 'كود الإحالة (كود الطالب) — اختياري',
            hintText: 'T10042',
            labelStyle: const TextStyle(
                color: AppColors.textSecondary, fontFamily: 'Cairo'),
            prefixIcon: const Icon(Icons.card_giftcard, color: AppColors.gold),
            suffixIcon: _checking
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.gold),
                    ),
                  )
                : IconButton(
                    tooltip: 'تحقق من الكود',
                    onPressed: hasCode ? verify : null,
                    icon: const Icon(Icons.verified_outlined,
                        color: AppColors.gold),
                  ),
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
        if (_error != null) ...[
          SizedBox(height: Responsive.spacing(context, 6)),
          Text(
            _error!,
            style: TextStyle(
              color: AppColors.error,
              fontFamily: 'Cairo',
              fontSize: Responsive.fontSize(context, 12),
            ),
          ),
        ],
        if (_preview != null) ...[
          SizedBox(height: Responsive.spacing(context, 6)),
          Row(
            children: [
              const Icon(Icons.check_circle,
                  color: AppColors.success, size: 16),
              SizedBox(width: Responsive.spacing(context, 6)),
              Expanded(
                child: Text(
                  'إحالة من: ${_preview!.referrerName ?? ''}',
                  style: TextStyle(
                    color: AppColors.success,
                    fontFamily: 'Cairo',
                    fontSize: Responsive.fontSize(context, 12),
                  ),
                ),
              ),
            ],
          ),
        ],
        if (hasCode) ...[
          SizedBox(height: Responsive.spacing(context, 12)),
          TextField(
            controller: _amountCtrl,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: AppColors.textPrimary),
            onChanged: _onAmountChanged,
            decoration: InputDecoration(
              labelText:
                  'خصم الإحالة — يُخصم من هذا التسجيل (${widget.currency}) *',
              labelStyle: const TextStyle(
                  color: AppColors.textSecondary, fontFamily: 'Cairo'),
              prefixIcon: const Icon(Icons.redeem, color: AppColors.gold),
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
        ],
      ],
    );
  }
}
