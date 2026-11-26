import 'package:admin_dashboard/core/utils/app_error_handler.dart';
import 'package:admin_dashboard/features/reports/data/reports_repository.dart';
import 'package:admin_dashboard/features/reports/domain/accounting_period_models.dart';
import 'package:admin_dashboard/features/reports/presentation/accounting_periods_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('Accounting Period Domain Models Tests (Phase C7)', () {
    test('AccountingPeriod.fromMap parses open period correctly', () {
      final map = {
        'id': 'p-1',
        'period_month': '2026-10-01',
        'status': 'open',
        'closed_at': null,
        'closed_by': null,
        'reopened_at': '2026-10-15T10:00:00Z',
        'reopened_by': 'u-admin',
        'reopen_reason': 'تصحيح قيد مصروف أتعاب مدرب سابق',
        'reopen_count': 1,
        'created_at': '2026-10-01T00:00:00Z',
        'created_by': 'u-admin',
      };

      final period = AccountingPeriod.fromMap(map);

      expect(period.id, 'p-1');
      expect(period.periodMonth, DateTime.parse('2026-10-01'));
      expect(period.status, 'open');
      expect(period.isOpen, isTrue);
      expect(period.isClosed, isFalse);
      expect(period.monthKey, '2026-10');
      expect(period.formattedArabic, contains('تشرين الأول 2026'));
      expect(period.reopenCount, 1);
      expect(period.reopenReason, 'تصحيح قيد مصروف أتعاب مدرب سابق');
      expect(period.closedAt, isNull);
    });

    test('AccountingPeriod.fromMap parses closed period correctly', () {
      final map = {
        'id': 'p-2',
        'period_month': '2026-09-01',
        'status': 'closed',
        'closed_at': '2026-10-02T12:00:00Z',
        'closed_by': 'u-admin',
        'reopened_at': null,
        'reopened_by': null,
        'reopen_reason': null,
        'reopen_count': 0,
        'created_at': '2026-09-01T00:00:00Z',
        'created_by': 'u-admin',
      };

      final period = AccountingPeriod.fromMap(map);

      expect(period.id, 'p-2');
      expect(period.status, 'closed');
      expect(period.isClosed, isTrue);
      expect(period.isOpen, isFalse);
      expect(period.monthKey, '2026-09');
      expect(period.formattedArabic, contains('أيلول 2026'));
      expect(period.closedAt, isNotNull);
      expect(period.reopenCount, 0);
    });

    test('ClosePeriodResult.fromMap parses status and flags', () {
      final map = {
        'status': 'closed',
        'period_month': '2026-09',
        'forced': true,
        'has_collections': true,
        'dues_rows': 5,
        'draft_runs': 0,
        'open_sessions': 0,
      };

      final res = ClosePeriodResult.fromMap(map);

      expect(res.status, 'closed');
      expect(res.periodMonth, '2026-09');
      expect(res.forced, isTrue);
      expect(res.hasCollections, isTrue);
      expect(res.duesRows, 5);
      expect(res.draftRuns, 0);
      expect(res.isClosed, isTrue);
      expect(res.isAlreadyClosed, isFalse);
    });

    test('ReopenPeriodResult.fromMap parses reopening confirmation', () {
      final map = {
        'status': 'reopened',
        'period_month': '2026-09',
        'reopen_count': 2,
        'reason': 'تعديل سلفة قديمة بموافقة الإدارة المالية',
      };

      final res = ReopenPeriodResult.fromMap(map);

      expect(res.status, 'reopened');
      expect(res.periodMonth, '2026-09');
      expect(res.reopenCount, 2);
      expect(res.reason, contains('تعديل سلفة'));
    });
  });

  group('AppErrorHandler P0005 and P0006 Tests (Phase C7)', () {
    test('maps P0005 with default Arabic message', () {
      final exc = PostgrestException(
        message: 'period closed',
        code: 'P0005',
      );
      final msg = AppErrorHandler.friendlyMessage(exc);
      expect(msg, contains('فترة محاسبية مغلقة'));
    });

    test('passes through specific Arabic P0005 trigger message', () {
      final exc = PostgrestException(
        message:
            'لا يمكن إضافة أو تعديل أو حذف حركة مالية تقع ضمن فترة محاسبية مغلقة [2026-09]',
        code: 'P0005',
      );
      final msg = AppErrorHandler.friendlyMessage(exc);
      expect(msg, contains('لا يمكن إضافة أو تعديل'));
      expect(msg, contains('2026-09'));
    });

    test('maps P0006 with friendly message or passes Arabic text', () {
      final exc = PostgrestException(
        message:
            'لا يمكن إقفال الشهر الجاري [2026-11] أو شهر مستقبلي بلا p_force=true',
        code: 'P0006',
      );
      final msg = AppErrorHandler.friendlyMessage(exc);
      expect(msg, contains('لا يمكن إقفال الشهر الجاري'));
    });
  });

  group('AccountingPeriodsScreen Widget Tests (Phase C7)', () {
    final mockPeriods = [
      AccountingPeriod(
        id: '1',
        periodMonth: DateTime(2026, 9, 1),
        status: 'closed',
        closedAt: DateTime(2026, 10, 1, 12, 0),
        closedBy: 'admin',
        reopenCount: 0,
      ),
      AccountingPeriod(
        id: '2',
        periodMonth: DateTime(2026, 10, 1),
        status: 'open',
        reopenedAt: DateTime(2026, 10, 15, 9, 30),
        reopenReason: 'تعديل حركة دفع خاطئة',
        reopenCount: 1,
      ),
    ];

    testWidgets('renders screen title, info banner, and period cards',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            accountingPeriodsProvider.overrideWith((ref) => mockPeriods),
          ],
          child: const MaterialApp(
            home: AccountingPeriodsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Screen title and banner
      expect(find.text('إقفال الفترات المحاسبية (C7)'), findsOneWidget);
      expect(find.text('الحماية المحاسبية للفترات المغلقة'), findsOneWidget);

      // Period cards
      expect(find.textContaining('أيلول 2026'), findsOneWidget);
      expect(find.textContaining('تشرين الأول 2026'), findsOneWidget);

      // Badges
      expect(find.text('مغلقة'), findsOneWidget);
      expect(find.text('مفتوحة'), findsOneWidget);
      expect(find.text('أعيد فتحها 1 مرة'), findsOneWidget);

      // Action buttons
      expect(find.text('إعادة فتح'), findsOneWidget);
      expect(find.text('إعادة إقفال'), findsOneWidget);
      expect(find.text('إقفال فترة جديدة'), findsOneWidget);
    });

    testWidgets('renders empty state when periods list is empty', (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            accountingPeriodsProvider.overrideWith((ref) => []),
          ],
          child: const MaterialApp(
            home: AccountingPeriodsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('لا توجد فترات محاسبية مسجلة حتى الآن'), findsOneWidget);
    });

    testWidgets('clicking reopen opens dialog requiring at least 10 chars',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            accountingPeriodsProvider.overrideWith((ref) => mockPeriods),
          ],
          child: const MaterialApp(
            home: AccountingPeriodsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Click "إعادة فتح"
      await tester.tap(find.text('إعادة فتح'));
      await tester.pumpAndSettle();

      expect(find.textContaining('إعادة فتح الفترة 2026-09'), findsOneWidget);
      expect(find.text('تأكيد إعادة الفتح'), findsOneWidget);

      // Button is disabled when reason is empty (< 10 chars)
      final confirmBtn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'تأكيد إعادة الفتح'),
      );
      expect(confirmBtn.onPressed, isNull);

      // Type 9 chars -> still disabled
      await tester.enterText(find.byType(TextField), '123456789');
      await tester.pumpAndSettle();
      final confirmBtn9 = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'تأكيد إعادة الفتح'),
      );
      expect(confirmBtn9.onPressed, isNull);

      // Type 10+ chars -> becomes enabled
      await tester.enterText(
          find.byType(TextField), 'تصحيح قيد مصروف خطأ معتمد من الإدارة');
      await tester.pumpAndSettle();
      final confirmBtnValid = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'تأكيد إعادة الفتح'),
      );
      expect(confirmBtnValid.onPressed, isNotNull);
    });

    testWidgets('clicking new period button opens close period dialog',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            accountingPeriodsProvider.overrideWith((ref) => mockPeriods),
          ],
          child: const MaterialApp(
            home: AccountingPeriodsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Click "إقفال فترة جديدة"
      await tester.tap(find.text('إقفال فترة جديدة'));
      await tester.pumpAndSettle();

      expect(find.text('إقفال فترة محاسبية'), findsOneWidget);
      expect(find.text('إقفال إجباري (Force Override)'), findsOneWidget);
      expect(find.text('تأكيد الإقفال'), findsOneWidget);
    });

    testWidgets('clicking re-close opens close period dialog with period month',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            accountingPeriodsProvider.overrideWith((ref) => mockPeriods),
          ],
          child: const MaterialApp(
            home: AccountingPeriodsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Click "إعادة إقفال" on open period (2026-10)
      await tester.tap(find.text('إعادة إقفال'));
      await tester.pumpAndSettle();

      expect(find.text('إقفال فترة محاسبية'), findsOneWidget);
      expect(find.text('الشهر المحدد: 2026-10'), findsOneWidget);
      expect(find.text('إقفال إجباري (Force Override)'), findsOneWidget);
    });
  });
}
