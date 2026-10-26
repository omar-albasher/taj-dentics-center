import 'package:admin_dashboard/core/utils/app_error_handler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('AppErrorHandler A5 referral codes', () {
    String map(String code) => AppErrorHandler.friendlyMessage(
          PostgrestException(message: code, code: 'P0001'),
        );

    test('maps code validation errors', () {
      expect(map('REFERRAL_CODE_INVALID'), contains('كود الإحالة'));
      expect(map('REFERRAL_REFERRER_INACTIVE'), contains('غير مفعّل'));
      expect(map('REFERRAL_SELF'), contains('المتدرب نفسه'));
      expect(map('REFERRAL_DISCOUNT_INVALID'), contains('غير صالحة'));
    });

    test('maps eligibility and amount errors', () {
      expect(map('REFERRAL_REFEREE_ENROLLED'), contains('نفس نوع'));
      expect(map('REFERRAL_ALREADY_REFERRED'), contains('مسبقاً'));
      expect(map('REFERRAL_MUTUAL'), contains('تبادل'));
      expect(map('REFERRAL_DISCOUNT_TOO_HIGH'), contains('المبلغ المتبقي'));
      expect(map('REFERRAL_NOTHING_DUE'), contains('مستحق'));
    });

    test('maps a duplicate trainee code', () {
      expect(
        AppErrorHandler.friendlyMessage(
          PostgrestException(
            message: 'duplicate key value violates unique constraint '
                '"uq_trainees_trainee_code"',
            code: '23505',
          ),
        ),
        contains('مستخدم لمتدرب آخر'),
      );
    });
  });

  group('AppErrorHandler B4 domain codes', () {
    test('maps COHORT_CAPACITY_REACHED from message', () {
      final result = AppErrorHandler.friendlyMessage(
        PostgrestException(
          message: 'COHORT_CAPACITY_REACHED',
          code: 'P0001',
          details: 'cohort=x active=10 capacity=10',
        ),
      );

      expect(result, contains('ممتلئة'));
      expect(result, contains('قائمة الانتظار'));
    });

    test('maps domain code found only in details', () {
      final result = AppErrorHandler.friendlyMessage(
        PostgrestException(
          message: 'some wrapped message',
          code: 'P0001',
          details: 'COHORT_CAPACITY_BELOW_ENROLLED from=12 to=10',
        ),
      );

      expect(result, contains('تقليل السعة'));
    });

    test('maps waitlist and financial codes', () {
      expect(
        AppErrorHandler.friendlyMessage(
          PostgrestException(
            message: 'ALREADY_ON_WAITLIST',
            code: 'P0001',
          ),
        ),
        contains('قائمة الانتظار'),
      );
      expect(
        AppErrorHandler.friendlyMessage(
          PostgrestException(message: 'INVALID_CURRENCY', code: 'P0001'),
        ),
        contains('العملة'),
      );
      expect(
        AppErrorHandler.friendlyMessage(
          PostgrestException(message: 'AUTH_REQUIRED', code: 'P0001'),
        ),
        contains('الجلسة'),
      );
    });

    test('falls back to generic database message for unknown P0001', () {
      final result = AppErrorHandler.friendlyMessage(
        PostgrestException(message: 'SOMETHING_ELSE', code: 'P0001'),
      );

      expect(result, contains('قاعدة البيانات'));
      expect(result, contains('P0001'));
    });
  });
}
