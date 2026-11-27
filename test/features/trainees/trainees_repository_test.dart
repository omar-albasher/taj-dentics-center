import 'package:admin_dashboard/features/trainees/data/trainees_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TraineesRepository.resetTraineePassword (#40.1)', () {
    test('invokes manage-user with the users.id (user_id)', () async {
      String? functionName;
      Map<String, dynamic>? body;

      final repo = TraineesRepository(invoke: (name, payload) async {
        functionName = name;
        body = payload;
        return {'success': true};
      });

      await repo.resetTraineePassword('auth-user-uuid', 'Taj@654321');

      expect(functionName, 'manage-user');
      expect(body, {
        'action': 'reset_password',
        'user_id': 'auth-user-uuid',
        'new_password': 'Taj@654321',
      });
    });

    test('surfaces the Edge Function Arabic error', () async {
      final repo = TraineesRepository(
        invoke: (_, __) async => {'error': 'لا يمكن إعادة تعيين كلمة مرور حساب غير نشط'},
      );

      expect(
        () => repo.resetTraineePassword('auth-user-uuid', 'Taj@654321'),
        throwsA(predicate(
            (e) => e.toString().contains('حساب غير نشط'))),
      );
    });
  });
}
