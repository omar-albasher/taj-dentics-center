import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PinRepository {
  final _client = Supabase.instance.client;

  /// فحص ما إذا كان المستخدم الحالي قد عيّن رمز PIN مسبقاً
  Future<bool> hasPin() async {
    try {
      final response = await _client.rpc('has_user_pin');
      return response == true;
    } catch (_) {
      return false;
    }
  }

  /// التحقق من صحة رمز الـ PIN المدخل بمقارنة الـ bcrypt hash على السيرفر
  Future<bool> verifyPin(String pin) async {
    try {
      final response = await _client.rpc('verify_user_pin', params: {
        'p_pin': pin,
      });
      return response == true;
    } catch (_) {
      return false;
    }
  }

  /// تعيين أو تحديث رمز الـ PIN الخاص بالمستخدم الحالي
  Future<void> setPin(String pin) async {
    await _client.rpc('set_user_pin', params: {
      'p_pin': pin,
    });
  }
}

final pinRepositoryProvider = Provider((_) => PinRepository());
