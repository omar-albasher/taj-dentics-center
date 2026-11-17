import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/responsive.dart';
import 'pin_lock_controller.dart';

class PinLockOverlay extends ConsumerStatefulWidget {
  const PinLockOverlay({super.key});

  @override
  ConsumerState<PinLockOverlay> createState() => _PinLockOverlayState();
}

class _PinLockOverlayState extends ConsumerState<PinLockOverlay> {
  String _enteredPin = '';
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _onDigitPressed(String digit) {
    final pinState = ref.read(pinLockProvider);
    if (pinState.isCoolingDown || pinState.isVerifying) return;

    if (_enteredPin.length < 6) {
      final updatedPin = _enteredPin + digit;
      setState(() => _enteredPin = updatedPin);
      if (updatedPin.length == 6) {
        _attemptUnlock(updatedPin);
      }
    }
  }

  void _onBackspace() {
    final pinState = ref.read(pinLockProvider);
    if (pinState.isCoolingDown || pinState.isVerifying) return;

    if (_enteredPin.isNotEmpty) {
      setState(() => _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1));
    }
  }

  void _onClear() {
    final pinState = ref.read(pinLockProvider);
    if (pinState.isCoolingDown || pinState.isVerifying) return;

    setState(() => _enteredPin = '');
  }

  Future<void> _attemptUnlock([String? pinToVerify]) async {
    final pin = pinToVerify ?? _enteredPin;
    final pinState = ref.read(pinLockProvider);
    if (pinState.isVerifying || pinState.isCoolingDown) return;
    if (pin.length < 4) return;

    final success =
        await ref.read(pinLockProvider.notifier).unlockWithPin(pin);
    if (!success && mounted) {
      setState(() => _enteredPin = '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final pinState = ref.watch(pinLockProvider);

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (event) {
        if (event is KeyDownEvent) {
          final pinState = ref.read(pinLockProvider);
          if (pinState.isCoolingDown || pinState.isVerifying) return;

          final label = event.logicalKey.keyLabel;
          String? digit;
          if (RegExp(r'^[0-9]$').hasMatch(label)) {
            digit = label;
          } else if (event.character != null &&
              RegExp(r'^[0-9]$').hasMatch(event.character!)) {
            digit = event.character;
          }

          if (digit != null) {
            _onDigitPressed(digit);
          } else if (event.logicalKey == LogicalKeyboardKey.backspace) {
            _onBackspace();
          } else if (event.logicalKey == LogicalKeyboardKey.escape) {
            _onClear();
          } else if (event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.numpadEnter) {
            if (_enteredPin.length >= 4) {
              _attemptUnlock();
            }
          }
        }
      },
      child: Container(
        color: AppColors.background.withValues(alpha: 0.96),
        width: double.infinity,
        height: double.infinity,
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Padding(
                padding: EdgeInsets.all(Responsive.spacing(context, 24)),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Center Logo
                    Image.asset('assets/images/Untitled-1.png', height: 72),
                    SizedBox(height: Responsive.spacing(context, 16)),

                    Text(
                      'مركز تاج للتعويضات السنية',
                      style: TextStyle(
                        fontSize: Responsive.fontSize(context, 20),
                        fontWeight: FontWeight.w900,
                        color: AppColors.gold,
                        fontFamily: 'Cairo',
                      ),
                    ),
                    SizedBox(height: Responsive.spacing(context, 4)),
                    Text(
                      'الشاشة مقفلة لحماية خصوصية بيانات المركز',
                      style: TextStyle(
                        fontSize: Responsive.fontSize(context, 13),
                        color: AppColors.textSecondary,
                        fontFamily: 'Cairo',
                      ),
                    ),
                    SizedBox(height: Responsive.spacing(context, 24)),

                    // PIN Dots Indicator
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(6, (index) {
                        final isFilled = index < _enteredPin.length;
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isFilled
                                ? AppColors.gold
                                : AppColors.surface,
                            border: Border.all(
                              color: isFilled
                                  ? AppColors.gold
                                  : AppColors.divider,
                              width: 1.5,
                            ),
                          ),
                        );
                      }),
                    ),
                    SizedBox(height: Responsive.spacing(context, 16)),

                    // Error or cooling down message
                    if (pinState.errorMessage != null)
                      Text(
                        pinState.errorMessage!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.error,
                          fontSize: Responsive.fontSize(context, 12),
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    else if (pinState.isVerifying)
                      const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.gold,
                        ),
                      )
                    else
                      Text(
                        'أدخل رمز الـ PIN المكون من 6 أرقام (أو اضغط تأكيد / Enter)',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: Responsive.fontSize(context, 11),
                          fontFamily: 'Cairo',
                        ),
                      ),

                    SizedBox(height: Responsive.spacing(context, 20)),

                    // Numeric Keypad
                    _buildKeypad(),

                    SizedBox(height: Responsive.spacing(context, 16)),

                    // Submit / Unlock button
                    SizedBox(
                      width: 250,
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: (_enteredPin.length >= 4 &&
                                !pinState.isVerifying &&
                                !pinState.isCoolingDown)
                            ? () => _attemptUnlock()
                            : null,
                        icon: pinState.isVerifying
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.black,
                                ),
                              )
                            : const Icon(Icons.lock_open, size: 20),
                        label: Text(
                          pinState.isVerifying
                              ? 'جاري التحقق...'
                              : 'تأكيد وفتح القفل',
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.gold,
                          foregroundColor: Colors.black,
                          disabledBackgroundColor:
                              AppColors.surface.withValues(alpha: 0.6),
                          disabledForegroundColor:
                              AppColors.textSecondary.withValues(alpha: 0.4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: _enteredPin.length >= 4 ? 2 : 0,
                        ),
                      ),
                    ),

                    SizedBox(height: Responsive.spacing(context, 20)),

                    // Forgot PIN / Sign Out option
                    TextButton.icon(
                      onPressed: () async {
                        await Supabase.instance.client.auth.signOut();
                      },
                      icon: const Icon(Icons.logout, size: 16, color: AppColors.textSecondary),
                      label: const Text(
                        'نسيت رمز PIN؟ تسجيل الخروج من الحساب',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontFamily: 'Cairo',
                          decoration: TextDecoration.underline,
                        ),
                      ),
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

  Widget _buildKeypad() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _keypadBtn('1'),
            _keypadBtn('2'),
            _keypadBtn('3'),
          ],
        ),
        SizedBox(height: Responsive.spacing(context, 12)),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _keypadBtn('4'),
            _keypadBtn('5'),
            _keypadBtn('6'),
          ],
        ),
        SizedBox(height: Responsive.spacing(context, 12)),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _keypadBtn('7'),
            _keypadBtn('8'),
            _keypadBtn('9'),
          ],
        ),
        SizedBox(height: Responsive.spacing(context, 12)),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _actionBtn(
              icon: Icons.clear,
              tooltip: 'مسح الكل',
              onPressed: _onClear,
            ),
            _keypadBtn('0'),
            _actionBtn(
              icon: Icons.backspace_outlined,
              tooltip: 'حذف رقم',
              onPressed: _onBackspace,
            ),
          ],
        ),
      ],
    );
  }

  Widget _keypadBtn(String digit) {
    final pinState = ref.watch(pinLockProvider);
    final disabled = pinState.isCoolingDown || pinState.isVerifying;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10),
      child: Material(
        color: disabled ? AppColors.surface : AppColors.cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: disabled
                ? AppColors.divider.withValues(alpha: 0.4)
                : AppColors.divider,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: disabled ? null : () => _onDigitPressed(digit),
          child: Container(
            width: 68,
            height: 60,
            alignment: Alignment.center,
            child: Text(
              digit,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: disabled
                    ? AppColors.textSecondary.withValues(alpha: 0.4)
                    : AppColors.textPrimary,
                fontFamily: 'Cairo',
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _actionBtn({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    final pinState = ref.watch(pinLockProvider);
    final disabled = pinState.isCoolingDown || pinState.isVerifying;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10),
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.divider),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: disabled ? null : onPressed,
          child: Container(
            width: 68,
            height: 60,
            alignment: Alignment.center,
            child: Icon(
              icon,
              color: disabled
                  ? AppColors.textSecondary.withValues(alpha: 0.4)
                  : AppColors.gold,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}
