import 'package:admin_dashboard/features/users/data/users_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UsersRepository.resetUserPassword (#40.1)', () {
    test('invokes manage-user with reset_password payload', () async {
      String? functionName;
      Map<String, dynamic>? body;

      final repo = UsersRepository(invoke: (name, payload) async {
        functionName = name;
        body = payload;
        return {'success': true};
      });

      await repo.resetUserPassword('user-1', 'Taj@123456');

      expect(functionName, 'manage-user');
      expect(body, {
        'action': 'reset_password',
        'user_id': 'user-1',
        'new_password': 'Taj@123456',
      });
    });

    test('surfaces the Edge Function Arabic error', () async {
      final repo = UsersRepository(
        invoke: (_, __) async => {'error': 'يمكن للاستقبال إعادة تعيين كلمات مرور المتدربين فقط'},
      );

      expect(
        () => repo.resetUserPassword('user-1', 'Taj@123456'),
        throwsA(predicate(
            (e) => e.toString().contains('يمكن للاستقبال إعادة تعيين'))),
      );
    });
  });
}
