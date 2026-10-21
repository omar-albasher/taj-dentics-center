import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/pin_repository.dart';

class PinLockState {
  final bool isLocked;
  final bool hasConfiguredPin;
  final int failedAttempts;
  final DateTime? lockedUntil;
  final bool isVerifying;
  final String? errorMessage;

  const PinLockState({
    this.isLocked = false,
    this.hasConfiguredPin = false,
    this.failedAttempts = 0,
    this.lockedUntil,
    this.isVerifying = false,
    this.errorMessage,
  });

  bool get isCoolingDown =>
      lockedUntil != null && DateTime.now().isBefore(lockedUntil!);

  int get remainingCooldownSeconds {
    if (lockedUntil == null) return 0;
    final diff = lockedUntil!.difference(DateTime.now()).inSeconds;
    return diff > 0 ? diff : 0;
  }

  PinLockState copyWith({
    bool? isLocked,
    bool? hasConfiguredPin,
    int? failedAttempts,
    DateTime? lockedUntil,
    bool clearLockedUntil = false,
    bool? isVerifying,
    String? errorMessage,
    bool clearError = false,
  }) {
    return PinLockState(
      isLocked: isLocked ?? this.isLocked,
      hasConfiguredPin: hasConfiguredPin ?? this.hasConfiguredPin,
      failedAttempts: failedAttempts ?? this.failedAttempts,
      lockedUntil:
          clearLockedUntil ? null : (lockedUntil ?? this.lockedUntil),
      isVerifying: isVerifying ?? this.isVerifying,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class PinLockNotifier extends Notifier<PinLockState> {
  Timer? _inactivityTimer;
  static const _inactivityDuration = Duration(minutes: 2);

  PinRepository get _repo => ref.read(pinRepositoryProvider);

  @override
  PinLockState build() {
    ref.onDispose(() {
      _inactivityTimer?.cancel();
    });

    // فحص ما إذا كان المستخدم يمتلك رمز PIN حالياً
    Future.microtask(() => checkPinStatus());
    _startTimer();

    return const PinLockState();
  }

  Future<void> checkPinStatus() async {
    final has = await _repo.hasPin();
    state = state.copyWith(hasConfiguredPin: has);
  }

  void _startTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(_inactivityDuration, () {
      if (state.hasConfiguredPin && !state.isLocked) {
        state = state.copyWith(
          isLocked: true,
          clearError: true,
        );
      }
    });
  }

  /// يرصد أي نشاط للمستخدم (حركة ماوس أو كيبورد) ويعيد ضبط المؤقت
  void resetInactivityTimer() {
    if (state.isLocked) return;
    _startTimer();
  }

  /// قفل الشاشة فوراً يدوياً بنقرة زر
  void lockManually() {
    _inactivityTimer?.cancel();
    state = state.copyWith(isLocked: true, clearError: true);
  }

  /// محاولة فك القفل برمز PIN
  Future<bool> unlockWithPin(String pin) async {
    if (state.isCoolingDown) {
      state = state.copyWith(
        errorMessage:
            'تم تجميد المحاولات مؤقتاً بسبب تكرار الخطأ. انتظر ${state.remainingCooldownSeconds} ثانية',
      );
      return false;
    }

    state = state.copyWith(isVerifying: true, clearError: true);

    try {
      final isValid = await _repo.verifyPin(pin);
      if (isValid) {
        state = state.copyWith(
          isLocked: false,
          isVerifying: false,
          failedAttempts: 0,
          clearLockedUntil: true,
          clearError: true,
        );
        resetInactivityTimer();
        return true;
      } else {
        final newAttempts = state.failedAttempts + 1;
        DateTime? coolDown;
        String err = 'رمز الـ PIN غير صحيح';

        if (newAttempts >= 5) {
          coolDown = DateTime.now().add(const Duration(seconds: 60));
          err = 'تم استنفاد 5 محاولات خاطئة. تم قفل المحاولات لمدة 60 ثانية';
        }

        state = state.copyWith(
          isVerifying: false,
          failedAttempts: newAttempts,
          lockedUntil: coolDown,
          errorMessage: err,
        );
        return false;
      }
    } catch (_) {
      state = state.copyWith(
        isVerifying: false,
        errorMessage: 'تعذر التحقق من الرمز، يرجى المحاولة لاحقاً',
      );
      return false;
    }
  }

  Future<bool> setPin(String newPin) async {
    try {
      await _repo.setPin(newPin);
      state = state.copyWith(hasConfiguredPin: true);
      return true;
    } catch (_) {
      return false;
    }
  }
}

final pinLockProvider =
    NotifierProvider<PinLockNotifier, PinLockState>(PinLockNotifier.new);
