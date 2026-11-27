import 'dart:math';

import 'package:admin_dashboard/core/utils/password_generator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('generateTemporaryPassword (#40.1)', () {
    test('produces Taj@ + 6 digits with minimum server length', () {
      final password = generateTemporaryPassword();
      expect(password, matches(RegExp(r'^Taj@\d{6}$')));
      expect(password.length, greaterThanOrEqualTo(8));
    });

    test('different calls produce different values', () {
      final values = {
        for (var i = 0; i < 50; i++) generateTemporaryPassword(),
      };
      expect(values.length, greaterThan(1));
    });

    test('honours the injected random source', () {
      final a = generateTemporaryPassword(random: Random(7));
      final b = generateTemporaryPassword(random: Random(7));
      expect(a, b);
      expect(a, matches(RegExp(r'^Taj@\d{6}$')));
    });
  });
}
