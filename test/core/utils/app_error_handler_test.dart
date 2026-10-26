import 'package:admin_dashboard/core/utils/app_error_handler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
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
