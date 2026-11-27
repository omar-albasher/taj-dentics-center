import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_colors.dart';
import '../utils/app_error_handler.dart';
import '../utils/password_generator.dart';
import '../utils/phone_utils.dart';
import '../utils/responsive.dart';

/// حوار إعادة تعيين كلمة مرور حساب (متدرب أو موظف).
///
/// السياسة: الكلمة المؤقتة تُعرض مرة واحدة داخل الحوار مع زر نسخ،
/// ولا تُرسل نصاً عبر واتساب؛ رسالة واتساب إشعار فقط.
class ResetPasswordDialog extends StatefulWidget {
  const ResetPasswordDialog({
    super.key,
    required this.targetName,
    required this.onSubmit,
    this.whatsappNumber,
  });

  final String targetName;
  final Future<void> Function(String password) onSubmit;
  final String? whatsappNumber;

  @override
  State<ResetPasswordDialog> createState() => _ResetPasswordDialogState();
}

class _ResetPasswordDialogState extends State<ResetPasswordDialog> {
  final _controller = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  bool _done = false;

  static const _minLength = 8;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      !_loading && _controller.text.length >= _minLength;

  void _generate() {
    setState(() {
      _controller.text = generateTemporaryPassword();
      _obscure = false;
    });
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _controller.text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم نسخ كلمة المرور'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _loading = true);
    try {
      await widget.onSubmit(_controller.text);
      if (!mounted) return;
      setState(() => _done = true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppErrorHandler.friendlyMessage(e)),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _notifyWhatsApp() async {
    final opened = await PhoneUtils.launchWhatsApp(
      phone: widget.whatsappNumber,
      message:
          'مرحباً ${widget.targetName}، تمت إعادة تعيين كلمة المرور الخاصة بحسابك في مركز تاج دنتكس. يرجى مراجعة إدارة المركز للحصول على بيانات الدخول المؤقتة.',
    );
    if (!mounted || opened) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تعذر فتح واتساب'),
        backgroundColor: AppColors.error,
      ),
    );
  }

  TextStyle get _bodyStyle => TextStyle(
        color: AppColors.textPrimary,
        fontFamily: 'Cairo',
        fontSize: Responsive.fontSize(context, 13),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.cardBg,
      title: Text(
        _done ? 'تمت إعادة التعيين' : 'إعادة تعيين كلمة المرور',
        style: const TextStyle(
          color: AppColors.gold,
          fontFamily: 'Cairo',
          fontWeight: FontWeight.bold,
        ),
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _done ? _buildDone() : _buildForm(),
          ),
        ),
      ),
      actions: _done
          ? [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('إغلاق',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontFamily: 'Cairo')),
              ),
            ]
          : [
              TextButton(
                onPressed:
                    _loading ? null : () => Navigator.of(context).pop(),
                child: const Text('إلغاء',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontFamily: 'Cairo')),
              ),
              ElevatedButton.icon(
                onPressed: _canSubmit ? _submit : null,
                icon: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black),
                      )
                    : const Icon(Icons.lock_reset),
                label: const Text('إعادة التعيين',
                    style: TextStyle(fontFamily: 'Cairo')),
              ),
            ],
    );
  }

  List<Widget> _buildForm() {
    return [
      Text('الحساب: ${widget.targetName}', style: _bodyStyle),
      SizedBox(height: Responsive.spacing(context, 8)),
      Text(
        'سيُجبر صاحب الحساب على تغيير كلمة المرور هذه عند أول دخول لتطبيق المتدرب.',
        style: _bodyStyle.copyWith(color: AppColors.textSecondary),
      ),
      SizedBox(height: Responsive.spacing(context, 16)),
      TextField(
        controller: _controller,
        obscureText: _obscure,
        style: TextStyle(
          color: AppColors.textPrimary,
          fontFamily: 'Cairo',
          fontSize: Responsive.fontSize(context, 14),
        ),
        decoration: InputDecoration(
          labelText: 'كلمة المرور المؤقتة',
          helperText: '$_minLength أحرف على الأقل',
          prefixIcon: const Icon(Icons.key_outlined),
          suffixIcon: IconButton(
            icon: Icon(
              _obscure ? Icons.visibility_off : Icons.visibility,
              color: AppColors.textSecondary,
            ),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ),
        onChanged: (_) => setState(() {}),
      ),
      SizedBox(height: Responsive.spacing(context, 12)),
      Wrap(
        spacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: _loading ? null : _generate,
            icon: const Icon(Icons.autorenew, size: 18),
            label: const Text('توليد كلمة مؤقتة',
                style: TextStyle(fontFamily: 'Cairo')),
          ),
          TextButton.icon(
            onPressed: _controller.text.isEmpty ? null : _copy,
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('نسخ',
                style: TextStyle(fontFamily: 'Cairo')),
          ),
        ],
      ),
    ];
  }

  List<Widget> _buildDone() {
    return [
      Row(
        children: [
          const Icon(Icons.check_circle, color: AppColors.success, size: 28),
          SizedBox(width: Responsive.spacing(context, 8)),
          Expanded(
            child: Text(
              'تم تحديث كلمة المرور وفرض تغييرها عند أول دخول.',
              style: _bodyStyle,
            ),
          ),
        ],
      ),
      SizedBox(height: Responsive.spacing(context, 16)),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
        ),
        child: SelectableText(
          _controller.text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.gold,
            fontFamily: 'monospace',
            fontSize: 18,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
      ),
      SizedBox(height: Responsive.spacing(context, 8)),
      Text(
        'تظهر هذه الكلمة مرة واحدة فقط. انسخها الآن وسلّمها لصاحب الحساب شخصياً؛ لن تُرسل نصاً عبر واتساب.',
        style: _bodyStyle.copyWith(color: AppColors.textSecondary),
      ),
      SizedBox(height: Responsive.spacing(context, 12)),
      Wrap(
        spacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: _copy,
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('نسخ كلمة المرور',
                style: TextStyle(fontFamily: 'Cairo')),
          ),
          if (widget.whatsappNumber != null)
            TextButton.icon(
              onPressed: _notifyWhatsApp,
              icon: const Icon(Icons.chat_outlined,
                  color: Color(0xFF25D366), size: 18),
              label: const Text('إشعار واتساب (بدون كلمة المرور)',
                  style: TextStyle(fontFamily: 'Cairo')),
            ),
        ],
      ),
    ];
  }
}
