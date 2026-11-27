import 'package:admin_dashboard/core/widgets/reset_password_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('ResetPasswordDialog (#40.1)', () {
    testWidgets('blocks submit until the password reaches 8 characters',
        (tester) async {
      String? submitted;
      await tester.pumpWidget(_wrap(ResetPasswordDialog(
        targetName: 'متدرب تجريبي',
        onSubmit: (password) async => submitted = password,
      )));

      expect(find.text('إعادة تعيين كلمة المرور'), findsOneWidget);
      expect(find.textContaining('سيُجبر صاحب الحساب'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '1234567');
      await tester.pump();
      await tester.tap(find.text('إعادة التعيين'));
      await tester.pump();
      expect(submitted, isNull);

      await tester.enterText(find.byType(TextField), '12345678');
      await tester.pump();
      await tester.tap(find.text('إعادة التعيين'));
      await tester.pumpAndSettle();

      expect(submitted, '12345678');
      expect(find.text('تمت إعادة التعيين'), findsOneWidget);
      expect(find.text('12345678'), findsOneWidget);
    });

    testWidgets('generate fills a valid temporary password', (tester) async {
      await tester.pumpWidget(_wrap(ResetPasswordDialog(
        targetName: 'متدرب تجريبي',
        onSubmit: (_) async {},
      )));

      await tester.tap(find.text('توليد كلمة مؤقتة'));
      await tester.pump();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, matches(RegExp(r'^Taj@\d{6}$')));
    });

    testWidgets('shows the password once with a copy action after success',
        (tester) async {
      await tester.pumpWidget(_wrap(ResetPasswordDialog(
        targetName: 'متدرب تجريبي',
        whatsappNumber: '0912345678',
        onSubmit: (_) async {},
      )));

      await tester.enterText(find.byType(TextField), 'Taj@112233');
      await tester.pump();
      await tester.tap(find.text('إعادة التعيين'));
      await tester.pumpAndSettle();

      expect(find.text('تم تحديث كلمة المرور وفرض تغييرها عند أول دخول.'),
          findsOneWidget);
      expect(find.text('Taj@112233'), findsOneWidget);
      expect(find.text('نسخ كلمة المرور'), findsOneWidget);
      expect(find.text('إشعار واتساب (بدون كلمة المرور)'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('hides the WhatsApp notice when no number is available',
        (tester) async {
      await tester.pumpWidget(_wrap(ResetPasswordDialog(
        targetName: 'متدرب تجريبي',
        onSubmit: (_) async {},
      )));

      await tester.enterText(find.byType(TextField), 'Taj@445566');
      await tester.pump();
      await tester.tap(find.text('إعادة التعيين'));
      await tester.pumpAndSettle();

      expect(find.text('إشعار واتساب (بدون كلمة المرور)'), findsNothing);
    });

    testWidgets('keeps the form and shows the Arabic error on failure',
        (tester) async {
      await tester.pumpWidget(_wrap(ResetPasswordDialog(
        targetName: 'متدرب تجريبي',
        onSubmit: (_) async => throw Exception('تعذر إعادة التعيين للاختبار'),
      )));

      await tester.enterText(find.byType(TextField), 'Taj@778899');
      await tester.pump();
      await tester.tap(find.text('إعادة التعيين'));
      await tester.pumpAndSettle();

      expect(find.text('تعذر إعادة التعيين للاختبار'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('تمت إعادة التعيين'), findsNothing);
    });
  });
}
