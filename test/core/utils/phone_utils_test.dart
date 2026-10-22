import 'package:flutter_test/flutter_test.dart';
import 'package:admin_dashboard/core/utils/phone_utils.dart';

void main() {
  group('PhoneUtils.sanitizePhone', () {
    test('converts 09XXXXXXXX to 9639XXXXXXXX', () {
      expect(PhoneUtils.sanitizePhone('0912345678'), equals('963912345678'));
    });

    test('converts 9XXXXXXXX to 9639XXXXXXXX', () {
      expect(PhoneUtils.sanitizePhone('912345678'), equals('963912345678'));
    });

    test('handles international 00963 prefix', () {
      expect(PhoneUtils.sanitizePhone('00963912345678'), equals('963912345678'));
    });

    test('handles plus prefix +963', () {
      expect(PhoneUtils.sanitizePhone('+963912345678'), equals('963912345678'));
      expect(PhoneUtils.sanitizePhone('+963-912-345-678'), equals('963912345678'));
    });

    test('handles accidental 0 after country code 96309...', () {
      expect(PhoneUtils.sanitizePhone('+963 0912345678'), equals('963912345678'));
    });

    test('accepts valid international numbers', () {
      expect(PhoneUtils.sanitizePhone('+971501234567'), equals('971501234567'));
    });

    test('returns null for empty, short or invalid values', () {
      expect(PhoneUtils.sanitizePhone(null), isNull);
      expect(PhoneUtils.sanitizePhone(''), isNull);
      expect(PhoneUtils.sanitizePhone('   '), isNull);
      expect(PhoneUtils.sanitizePhone('12345'), isNull);
      expect(PhoneUtils.sanitizePhone('abcd'), isNull);
    });
  });

  group('PhoneUtils.toWaMeUri', () {
    test('builds uri with proper host and path', () {
      final uri = PhoneUtils.toWaMeUri(phone: '0912345678');
      expect(uri, isNotNull);
      expect(uri!.scheme, equals('https'));
      expect(uri.host, equals('wa.me'));
      expect(uri.path, equals('/963912345678'));
      expect(uri.queryParameters, isEmpty);
    });

    test('encodes Arabic message and emojis in queryParameters', () {
      const msg = 'مرحباً دكتور أحمد 🌸 تذكير بدفعة مستحقة';
      final uri = PhoneUtils.toWaMeUri(phone: '0912345678', message: msg);
      expect(uri, isNotNull);
      expect(uri!.queryParameters['text'], equals(msg));
      expect(uri.toString(), contains('wa.me/963912345678?text='));
    });

    test('returns null for invalid phone', () {
      final uri = PhoneUtils.toWaMeUri(phone: 'invalid');
      expect(uri, isNull);
    });
  });
}
