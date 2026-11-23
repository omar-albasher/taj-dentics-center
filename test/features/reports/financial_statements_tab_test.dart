import 'package:admin_dashboard/features/reports/data/reports_repository.dart';
import 'package:admin_dashboard/features/reports/domain/financial_statement_models.dart';
import 'package:admin_dashboard/features/reports/presentation/widgets/financial_statements_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final pnl = ProfitLossStatement.fromRows([
    {
      'currency': 'SYP',
      'section': 'academy',
      'income': 1000000.0,
      'refunds': 50000.0,
      'expenses': 200000.0,
      'net': 750000.0,
      'memorandum_uncollected': 0.0,
    },
    {
      'currency': 'SYP',
      'section': 'lab',
      'income': 300000.0,
      'refunds': 0.0,
      'expenses': 120000.0,
      'net': 180000.0,
      'memorandum_uncollected': 250000.0,
    },
  ]);

  final cashFlow = CashFlowStatement.fromRows([
    {
      'account_id': 'box-syp',
      'account_name_ar': 'صندوق المركز',
      'account_type': 'cash',
      'currency': 'SYP',
      'opening_balance': 500000.0,
      'inflows': 1300000.0,
      'outflows': 320000.0,
      'closing_balance': 1480000.0,
      'payment_in': 1300000.0,
      'expense_out': 320000.0,
      'refund_out': 0.0,
      'transfer_in': 0.0,
      'transfer_out': 0.0,
      'adjustment_in': 0.0,
      'adjustment_out': 0.0,
      'tx_count': 12,
    },
  ]);

  final expenses = [
    ExpenseBreakdownItem.fromMap({
      'section': 'academy',
      'currency': 'SYP',
      'account_id': 'box-syp',
      'account_name_ar': 'صندوق المركز',
      'category': 'رواتب',
      'amount': 200000.0,
      'expense_count': 2,
    }),
    ExpenseBreakdownItem.fromMap({
      'section': 'lab',
      'currency': 'SYP',
      'account_id': null,
      'account_name_ar': null,
      'category': 'materials',
      'amount': 120000.0,
      'expense_count': 1,
    }),
  ];

  final integrity = FinancialIntegrityReport.fromRows([
    {
      'source_type': 'payment',
      'currency': 'SYP',
      'events_total': 1300000.0,
      'ledger_total': 1300000.0,
      'diff': 0.0,
      'is_balanced': true,
    },
  ]);

  Future<void> pumpTab(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          c4ProfitLossProvider.overrideWith((ref) async => pnl),
          c4CashFlowProvider.overrideWith((ref) async => cashFlow),
          c4ExpenseBreakdownProvider.overrideWith((ref) async => expenses),
          c4FinancialIntegrityProvider.overrideWith((ref) async => integrity),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: FinancialStatementsTab(
              currencyFilter: 'الكل',
              onExport: (_, __) async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('builds without layout errors and shows integrity banner',
      (tester) async {
    await pumpTab(tester);

    expect(tester.takeException(), isNull);
    expect(find.textContaining('سلامة التكامل المحاسبي'), findsOneWidget);
    expect(find.textContaining('قائمة الدخل'), findsWidgets);
  });

  testWidgets('keeps academy and lab sections separate in the P&L',
      (tester) async {
    await pumpTab(tester);

    expect(find.text('الأكاديمية التدريبية'), findsOneWidget);
    expect(find.text('المخبر الطبي'), findsOneWidget);
    expect(find.text('غير مرتبط بالخزينة'), findsOneWidget);
    expect(
      find.textContaining('المستحق غير المحصّل من الفواتير'),
      findsOneWidget,
    );
  });

  testWidgets('headline KPI reports academy net and shows lab net separately',
      (tester) async {
    await pumpTab(tester);

    expect(find.textContaining('صافي أرباح الأكاديمية (SYP)'), findsOneWidget);
    expect(find.textContaining('المخبر (قسم منفصل)'), findsOneWidget);
    expect(find.textContaining('750,000'), findsWidgets);
  });

  testWidgets('cash flow table renders the custody account and balance check',
      (tester) async {
    await pumpTab(tester);

    expect(find.text('صندوق المركز'), findsWidgets);
    expect(find.textContaining('قائمة التدفق النقدي'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
  });

  testWidgets('expense breakdown expands and labels lab categories',
      (tester) async {
    await pumpTab(tester);

    final tile = find.textContaining('تفصيل بنود المصاريف');
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();

    expect(find.text('مواد'), findsOneWidget);
    expect(find.text('رواتب'), findsOneWidget);
  });
}
