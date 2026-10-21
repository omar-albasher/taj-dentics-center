import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/responsive.dart';
import 'pin_lock_controller.dart';

class SetPinDialog extends ConsumerStatefulWidget {
  const SetPinDialog({super.key});

  @override
  ConsumerState<SetPinDialog> createState() => _SetPinDialogState();
}

class _SetPinDialogState extends ConsumerState<SetPinDialog> {
  final _pinCtrl = TextEditingController();
  final _confirmPinCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _pinCtrl.dispose();
    _confirmPinCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pin = _pinCtrl.text.trim();
    final confirm = _confirmPinCtrl.text.trim();

    if (pin.length < 4 || pin.length > 6) {
      setState(() => _error = 'يجب أن يتكون رمز الـ PIN من 4 إلى 6 أرقام');
      return;
    }

    if (pin != confirm) {
      setState(() => _error = 'الرمزان غير متطابقين، يرجى إعادة التأكيد');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final success = await ref.read(pinLockProvider.notifier).setPin(pin);

    if (!mounted) return;
    setState(() => _loading = false);

    if (success) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تعيين رمز PIN لقفل الشاشة بنجاح ✓'),
          backgroundColor: AppColors.success,
        ),
      );
    } else {
      setState(() => _error = 'فشل تعيين الرمز، يرجى المحاولة لاحقاً');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: EdgeInsets.all(Responsive.spacing(context, 24)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.lock_outline, color: AppColors.gold, size: 24),
                  SizedBox(width: Responsive.spacing(context, 8)),
                  Text(
                    'تعيين رمز قفل الشاشة (PIN)',
                    style: TextStyle(
                      fontSize: Responsive.fontSize(context, 17),
                      fontWeight: FontWeight.w700,
                      color: AppColors.gold,
                      fontFamily: 'Cairo',
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppColors.textSecondary),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(color: AppColors.divider, height: 24),
              const Text(
                'رمز الـ PIN يُستخدم لقفل وفتح شاشة الاستقبال بعد دقيقتين من الخمول لحماية خصوصية بيانات المتدربين والمركز.',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  fontFamily: 'Cairo',
                  height: 1.5,
                ),
              ),
              SizedBox(height: Responsive.spacing(context, 16)),
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: AppColors.error, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
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
                SizedBox(height: Responsive.spacing(context, 12)),
              ],
              TextField(
                controller: _pinCtrl,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(color: AppColors.textPrimary, letterSpacing: 8),
                decoration: InputDecoration(
                  labelText: 'رمز PIN الجديد (4-6 أرقام) *',
                  labelStyle: const TextStyle(fontFamily: 'Cairo', letterSpacing: 0),
                  filled: true,
                  fillColor: AppColors.surface,
                  prefixIcon: const Icon(Icons.pin, color: AppColors.gold),
                  counterText: '',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.divider),
                  ),
                ),
              ),
              SizedBox(height: Responsive.spacing(context, 12)),
              TextField(
                controller: _confirmPinCtrl,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(color: AppColors.textPrimary, letterSpacing: 8),
                decoration: InputDecoration(
                  labelText: 'تأكيد رمز PIN *',
                  labelStyle: const TextStyle(fontFamily: 'Cairo', letterSpacing: 0),
                  filled: true,
                  fillColor: AppColors.surface,
                  prefixIcon: const Icon(Icons.lock_clock, color: AppColors.gold),
                  counterText: '',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.divider),
                  ),
                ),
              ),
              SizedBox(height: Responsive.spacing(context, 20)),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                        side: const BorderSide(color: AppColors.divider),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('إلغاء',
                          style: TextStyle(fontFamily: 'Cairo')),
                    ),
                  ),
                  SizedBox(width: Responsive.spacing(context, 12)),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _loading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.gold,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: _loading
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.black),
                            )
                          : const Text('حفظ الرمز',
                              style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontWeight: FontWeight.bold)),
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
}
