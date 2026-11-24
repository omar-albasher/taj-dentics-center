import 'package:admin_dashboard/features/reports/data/reports_repository.dart';
import 'package:admin_dashboard/features/reports/domain/accrual_models.dart';
import 'package:admin_dashboard/features/reports/presentation/widgets/accrual_reports_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final revenueRows = [
    AccrualRevenueReportRow(
      cohortId: 'c-1',
      cohortName: 'فوج التقويم الأول',
      courseName: 'دبلوم تقويم الأسنان',
      totalCourseSessions: 10,
      enrollmentId: 'e-1',
      traineeId: 't-1',
      traineeName: 'د. سامر العلي',
      currency: 'SYP',
      lifecycleStatus: 'active',
      enrolledAt: DateTime(2026, 10, 1),
      netDue: 100000.0,
      netPaid: 80000.0,
      sessionsPrior: 0,
      plannedRemaining: 10,
      deliveredSinceEnrolled: 4,
      completionRatio: 0.4,
      earnedRevenue: 40000.0,
      unearnedRevenue: 40000.0,
      accruedReceivables: 0.0,
    ),
    AccrualRevenueReportRow(
      cohortId: 'c-2',
      cohortName: 'فوج الزراعة المتقدم',
      courseName: 'دبلوم زراعة الأسنان',
      totalCourseSessions: 5,
      enrollmentId: 'e-2',
      traineeId: 't-2',
      traineeName: 'Dr. John Doe',
      currency: 'USD',
      lifecycleStatus: 'active',
      enrolledAt: DateTime(2026, 10, 5),
      netDue: 500.0,
      netPaid: 500.0,
      sessionsPrior: 0,
      plannedRemaining: 5,
      deliveredSinceEnrolled: 1,
      completionRatio: 0.2,
      earnedRevenue: 100.0,
      unearnedRevenue: 400.0,
      accruedReceivables: 0.0,
    ),
  ];

  final reconRows = [
    AccrualReconciliationReportRow(
      currency: 'SYP',
      openingUnearned: 20000.0,
      openingAccrued: 0.0,
      openingEarnedCumulative: 50000.0,
      closingUnearned: 40000.0,
      closingAccrued: 0.0,
      closingEarnedCumulative: 90000.0,
      deltaUnearned: 20000.0,
      deltaAccrued: 0.0,
      periodEarnedRevenue: 40000.0,
      periodCashPayments: 60000.0,
      periodCashRefunds: 0.0,
      periodCashNet: 60000.0,
      reconciliationDiff: 0.0,
      isReconciled: true,
    ),
  ];

  Future<void> pumpTab(
    WidgetTester tester, {
    String currencyFilter = 'الكل',
  }) async {
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accrualRevenueReportProvider.overrideWith((ref) async => revenueRows),
          accrualReconciliationProvider.overrideWith((ref) async => reconRows),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: AccrualReportsTab(
              currencyFilter: currencyFilter,
              onExport: (_, __) async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
      'builds without layout errors and separates currencies cleanly without mixing under "الكل"',
      (tester) async {
    await pumpTab(tester, currencyFilter: 'الكل');

    expect(tester.takeException(), isNull);
    expect(find.textContaining('تقرير الاستحقاق التراكمي'), findsOneWidget);

    // Verify both currency headers are rendered distinctly
    expect(find.text('الليرة السورية (SYP)'), findsOneWidget);
    expect(find.text('الدولار الأمريكي (USD)'), findsOneWidget);

    // Verify SYP amount is rendered as SYP
    expect(find.text('40,000 ل.س'), findsWidgets);

    // Verify USD amount is rendered as USD
    expect(find.text('\$100'), findsWidgets);

    // Crucial check: verify that SYP and USD amounts are NOT mixed or added into 40,100 ل.س
    expect(find.text('40,100 ل.س'), findsNothing);
  });

  testWidgets('can toggle to reconciliation bridge and shows balanced status',
      (tester) async {
    await pumpTab(tester);

    final reconSegment = find.textContaining('جسر تسوية الإيرادات');
    expect(reconSegment, findsOneWidget);

    await tester.tap(reconSegment);
    await tester.pumpAndSettle();

    expect(find.textContaining('تسوية العملة: SYP'), findsOneWidget);
    expect(find.textContaining('المعادلة متطابقة ومتوازنة'), findsOneWidget);
  });

  testWidgets('can open complete cohort dialog with force toggle and cancel',
      (tester) async {
    await pumpTab(tester);

    final completeBtn = find.text('إقفال فوج إدارياً');
    expect(completeBtn, findsOneWidget);

    await tester.tap(completeBtn);
    await tester.pumpAndSettle();

    expect(find.text('إقفال فوج دراسي (Complete Cohort)'), findsOneWidget);
    expect(find.text('تجاوز إداري (p_force)'), findsOneWidget);

    // Toggle force checkbox
    final checkbox = find.byType(Checkbox);
    expect(checkbox, findsOneWidget);
    await tester.tap(checkbox);
    await tester.pumpAndSettle();

    expect(
      find.textContaining('تنبيه: سيتم إقفال الفوج حتى مع وجود جلسات مجدولة'),
      findsOneWidget,
    );

    // Cancel dialog
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();

    expect(find.text('إقفال فوج دراسي (Complete Cohort)'), findsNothing);
  });
}
