import 'package:admin_dashboard/features/reports/data/reports_repository.dart';
import 'package:admin_dashboard/features/reports/domain/cohort_contribution_models.dart';
import 'package:admin_dashboard/features/reports/presentation/widgets/cohort_contribution_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Weighted SYP ratio must be Σmargin/Σearned = 40,000/50,000 = 80.0%,
  // not the average of per-cohort ratios (75% and 100% → 87.5%).
  final contributionRows = [
    const CohortContributionRow(
      cohortId: 'c-1',
      cohortName: 'فوج التقويم الأول',
      courseName: 'دبلوم تقويم الأسنان',
      currency: 'SYP',
      earnedRevenue: 40000.0,
      trainerCost: 10000.0,
      contributionMargin: 30000.0,
      marginRatio: 0.75,
      traineesCount: 8,
      hasTrainerCost: true,
    ),
    const CohortContributionRow(
      cohortId: 'c-2',
      cohortName: 'فوج الزراعة الثاني',
      courseName: 'دبلوم زراعة الأسنان',
      currency: 'SYP',
      earnedRevenue: 10000.0,
      trainerCost: 0.0,
      contributionMargin: 10000.0,
      marginRatio: 1.0,
      traineesCount: 5,
      hasTrainerCost: false,
    ),
    const CohortContributionRow(
      cohortId: 'c-3',
      cohortName: 'Advanced Implant Cohort',
      courseName: 'Implant Diploma',
      currency: 'USD',
      earnedRevenue: 500.0,
      trainerCost: 250.0,
      contributionMargin: 250.0,
      marginRatio: 0.5,
      traineesCount: 3,
      hasTrainerCost: true,
    ),
  ];

  Future<List<List<dynamic>>?> Function() pumpTab(
    WidgetTester tester, {
    String currencyFilter = 'الكل',
    void Function(String filename, List<List<dynamic>> rows)? onExportCapture,
  }) {
    List<List<dynamic>>? capturedRows;
    return () async {
      tester.view.physicalSize = const Size(1600, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            cohortContributionReportProvider
                .overrideWith((ref) async => contributionRows),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: CohortContributionTab(
                currencyFilter: currencyFilter,
                onExport: (rows, filename) async {
                  capturedRows = rows;
                  onExportCapture?.call(filename, rows);
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return capturedRows;
    };
  }

  group('CohortContributionRow.fromMap', () {
    test('parses numeric and boolean fields, including NULL margin_ratio', () {
      final row = CohortContributionRow.fromMap({
        'cohort_id': '8f3a5b6e-0000-0000-0000-000000000001',
        'cohort_name': 'فوج أ',
        'course_name': 'دورة ب',
        'currency': 'SYP',
        'earned_revenue': '125000.50',
        'trainer_cost': 25000,
        'contribution_margin': 100000.5,
        'margin_ratio': null,
        'trainees_count': 12,
        'has_trainer_cost': false,
      });

      expect(row.cohortName, 'فوج أ');
      expect(row.courseName, 'دورة ب');
      expect(row.earnedRevenue, 125000.5);
      expect(row.trainerCost, 25000.0);
      expect(row.contributionMargin, 100000.5);
      expect(row.marginRatio, isNull);
      expect(row.traineesCount, 12);
      expect(row.hasTrainerCost, isFalse);
    });

    test('keeps a non-null margin_ratio as double', () {
      final row = CohortContributionRow.fromMap({
        'earned_revenue': 1000,
        'trainer_cost': 400,
        'contribution_margin': 600,
        'margin_ratio': 0.6,
        'trainees_count': 2,
        'has_trainer_cost': true,
      });

      expect(row.marginRatio, 0.6);
    });
  });

  group('CohortContributionSummary', () {
    test('weights ratio by earned revenue within one currency', () {
      final rows = contributionRows.where((r) => r.currency == 'SYP').toList();
      final summary = CohortContributionSummary.fromRows('SYP', rows);

      expect(summary.cohortsCount, 2);
      expect(summary.earnedRevenue, 50000.0);
      expect(summary.trainerCost, 10000.0);
      expect(summary.contributionMargin, 40000.0);
      expect(summary.cohortsWithoutTrainerCost, 1);
      expect(summary.weightedMarginRatio, closeTo(0.8, 1e-9));
    });

    test('returns null weighted ratio when no earned revenue exists', () {
      const rows = [
        CohortContributionRow(
          cohortId: 'c-x',
          cohortName: 'فوج صفري',
          courseName: 'دورة',
          currency: 'SYP',
          earnedRevenue: 0.0,
          trainerCost: 5000.0,
          contributionMargin: -5000.0,
          marginRatio: null,
          traineesCount: 0,
          hasTrainerCost: true,
        ),
      ];
      final summary = CohortContributionSummary.fromRows('SYP', rows);

      expect(summary.weightedMarginRatio, isNull);
      expect(summary.contributionMargin, -5000.0);
    });
  });

  testWidgets('renders per-currency summaries without mixing currencies',
      (tester) async {
    await pumpTab(tester)();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('هامش مساهمة قبل المصاريف المشتركة'),
        findsOneWidget);
    expect(find.text('الليرة السورية (SYP)'), findsOneWidget);
    expect(find.text('الدولار الأمريكي (USD)'), findsOneWidget);

    // SYP totals: earned 50,000 and margin 40,000 (SYP only).
    expect(find.text('50,000 ل.س'), findsWidgets);
    expect(find.text('40,000 ل.س'), findsWidgets);
    // USD totals stay in USD.
    expect(find.text('\$500'), findsWidgets);
    // Never summed across currencies (50,000 SYP + 500 USD would be 50,500).
    expect(find.text('50,500 ل.س'), findsNothing);

    // Weighted ratio, not the average of 75% and 100%.
    expect(find.text('80.0%'), findsWidgets);
    expect(find.text('87.5%'), findsNothing);
  });

  testWidgets('flags cohorts without registered trainer dues', (tester) async {
    await pumpTab(tester)();

    // Only the SYP cohort with has_trainer_cost = false gets the badge.
    expect(find.text('لا توجد أتعاب مسجّلة'), findsOneWidget);
    expect(find.text('(1 بلا أتعاب مسجّلة)'), findsOneWidget);
  });

  testWidgets('currency filter shows only the selected currency',
      (tester) async {
    await pumpTab(tester, currencyFilter: 'USD')();

    expect(find.text('Advanced Implant Cohort'), findsOneWidget);
    expect(find.text('فوج التقويم الأول'), findsNothing);
    expect(find.text('الليرة السورية (SYP)'), findsNothing);
    expect(find.text('50.0%'), findsWidgets);
  });

  testWidgets('CSV export carries headers and all filtered rows',
      (tester) async {
    String? filename;
    List<List<dynamic>>? exported;
    await pumpTab(
      tester,
      onExportCapture: (name, rows) {
        filename = name;
        exported = rows;
      },
    )();

    await tester.tap(find.text('تصدير CSV'));
    await tester.pumpAndSettle();

    expect(filename, startsWith('cohort_contribution_report_'));
    expect(exported, isNotNull);
    expect(exported!.length, contributionRows.length + 1);
    expect(exported!.first.first, 'الفوج');
    expect(exported!.last[8], 'نعم');
    expect(exported![2][8], 'لا');
  });
}
