import 'package:admin_dashboard/features/reports/domain/financial_statement_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FinancialStatementPeriod', () {
    test('is valid when from is on or before to', () {
      expect(
        FinancialStatementPeriod(
          from: DateTime(2026, 11, 1),
          to: DateTime(2026, 11, 30),
        ).isValid,
        isTrue,
      );
      expect(
        FinancialStatementPeriod(
          from: DateTime(2026, 11, 10),
          to: DateTime(2026, 11, 10),
        ).isValid,
        isTrue,
      );
    });

    test('is invalid when the range is reversed', () {
      expect(
        FinancialStatementPeriod(
          from: DateTime(2026, 11, 30),
          to: DateTime(2026, 11, 1),
        ).isValid,
        isFalse,
      );
    });

    test('iso getters pad to postgres date format', () {
      final period = FinancialStatementPeriod(
        from: DateTime(2026, 1, 5),
        to: DateTime(2026, 12, 31),
      );
      expect(period.fromIso, '2026-01-05');
      expect(period.toIso, '2026-12-31');
    });
  });

  group('ProfitLossStatement', () {
    final rows = <Map<String, dynamic>>[
      {
        'currency': 'SYP',
        'section': 'academy',
        'income': 1000.0,
        'refunds': 100.0,
        'expenses': 200.0,
        'net': 700.0,
        'memorandum_uncollected': 0.0,
      },
      {
        'currency': 'SYP',
        'section': 'lab',
        'income': 300.0,
        'refunds': 0.0,
        'expenses': 120.0,
        'net': 180.0,
        'memorandum_uncollected': 500.0,
      },
      {
        'currency': 'USD',
        'section': 'academy',
        'income': 50.0,
        'refunds': 0.0,
        'expenses': 10.0,
        'net': 40.0,
        'memorandum_uncollected': 0.0,
      },
    ];

    test('fromRows parses every contract column', () {
      final statement = ProfitLossStatement.fromRows(rows);
      expect(statement.lines, hasLength(3));

      final syp = statement.lineFor(financialSectionAcademy, 'SYP')!;
      expect(syp.income, 1000.0);
      expect(syp.refunds, 100.0);
      expect(syp.expenses, 200.0);
      expect(syp.net, 700.0);
      expect(syp.memorandumUncollected, 0.0);
      expect(syp.sectionLabel, 'الأكاديمية');
    });

    test('splits academy and lab rows without leaking memorandum', () {
      final statement = ProfitLossStatement.fromRows(rows);

      expect(statement.academy, hasLength(2));
      expect(statement.lab, hasLength(1));
      expect(statement.academy.every((line) => line.isAcademy), isTrue);

      final labSyp = statement.lineFor(financialSectionLab, 'SYP')!;
      expect(labSyp.computedNet, 180.0);
      expect(labSyp.memorandumUncollected, 500.0);
      expect(labSyp.net, labSyp.income - labSyp.expenses);
      expect(labSyp.reconciles, isTrue);
    });

    test('currencies preserve server order and are deduplicated', () {
      final statement = ProfitLossStatement.fromRows(rows);
      expect(statement.currencies, ['SYP', 'USD']);
    });

    test('memorandumFor returns the lab memorandum per currency', () {
      final statement = ProfitLossStatement.fromRows(rows);
      expect(statement.memorandumFor('SYP'), 500.0);
      expect(statement.memorandumFor('USD'), 0.0);
    });

    test('reconciles catches a server net that does not add up', () {
      final tampered = ProfitLossStatement.fromRows([
        {
          'currency': 'SYP',
          'section': 'academy',
          'income': 1000.0,
          'refunds': 100.0,
          'expenses': 200.0,
          'net': 700.01,
        },
      ]);
      expect(tampered.lines.single.reconciles, isFalse);
      expect(tampered.allReconcile, isFalse);
    });

    test('missing and string-encoded numerics default safely', () {
      final statement = ProfitLossStatement.fromRows([
        {
          'currency': 'USD',
          'section': 'lab',
          'income': '300.50',
          'expenses': null,
          'net': '300.50',
        },
      ]);
      final line = statement.lines.single;
      expect(line.income, 300.5);
      expect(line.expenses, 0.0);
      expect(line.memorandumUncollected, 0.0);
      expect(line.reconciles, isTrue);
    });

    test('memorandum-only lab row is not treated as lab activity', () {
      final statement = ProfitLossStatement.fromRows([
        {
          'currency': 'SYP',
          'section': 'lab',
          'income': 0.0,
          'expenses': 0.0,
          'net': 0.0,
          'memorandum_uncollected': 250.0,
        },
      ]);
      expect(statement.hasLabActivity, isFalse);
      expect(statement.hasMemorandum, isTrue);
    });
  });

  group('ExpenseBreakdownItem', () {
    test('parses academy rows with account details', () {
      final item = ExpenseBreakdownItem.fromMap({
        'section': 'academy',
        'currency': 'SYP',
        'account_id': 'acc-1',
        'account_name_ar': 'صندوق المركز',
        'category': 'رواتب',
        'amount': 25000.0,
        'expense_count': 3,
      });

      expect(item.sectionLabel, 'الأكاديمية');
      expect(item.accountId, 'acc-1');
      expect(item.accountNameAr, 'صندوق المركز');
      expect(item.categoryLabel, 'رواتب');
      expect(item.amount, 25000.0);
      expect(item.expenseCount, 3);
    });

    test('parses lab rows with null account and translates category', () {
      final item = ExpenseBreakdownItem.fromMap({
        'section': 'lab',
        'currency': 'USD',
        'account_id': null,
        'account_name_ar': null,
        'category': 'equipment_maintenance',
        'amount': '42.75',
        'expense_count': '2',
      });

      expect(item.sectionLabel, 'المخبر');
      expect(item.accountId, isNull);
      expect(item.accountNameAr, isNull);
      expect(item.categoryLabel, 'صيانة أجهزة');
      expect(item.amount, 42.75);
      expect(item.expenseCount, 2);
    });

    test('unknown lab category falls back to its raw value', () {
      final item = ExpenseBreakdownItem.fromMap({
        'section': 'lab',
        'currency': 'SYP',
        'category': 'transport',
        'amount': 10.0,
        'expense_count': 1,
      });
      expect(item.categoryLabel, 'transport');
    });
  });

  group('CashFlowStatement', () {
    final rows = <Map<String, dynamic>>[
      {
        'account_id': 'box-syp',
        'account_name_ar': 'صندوق المركز',
        'account_type': 'cash',
        'currency': 'SYP',
        'opening_balance': 10000.0,
        'inflows': 5000.0,
        'outflows': 2000.0,
        'closing_balance': 13000.0,
        'payment_in': 5000.0,
        'expense_out': 2000.0,
        'refund_out': 0.0,
        'transfer_in': 0.0,
        'transfer_out': 0.0,
        'adjustment_in': 0.0,
        'adjustment_out': 0.0,
        'tx_count': 7,
      },
      {
        'account_id': 'bank-syp',
        'account_name_ar': 'الحساب البنكي',
        'account_type': 'bank',
        'currency': 'SYP',
        'opening_balance': 20000.0,
        'inflows': 1000.0,
        'outflows': 500.0,
        'closing_balance': 20500.0,
        'payment_in': 0.0,
        'expense_out': 0.0,
        'refund_out': 0.0,
        'transfer_in': 1000.0,
        'transfer_out': 0.0,
        'adjustment_in': 0.0,
        'adjustment_out': 0.0,
        'tx_count': 1,
      },
      {
        'account_id': 'box-usd',
        'account_name_ar': 'صندوق المركز',
        'account_type': 'wallet',
        'currency': 'USD',
        'opening_balance': 0.0,
        'inflows': 0.0,
        'outflows': 0.0,
        'closing_balance': 0.0,
        'payment_in': 0.0,
        'expense_out': 0.0,
        'refund_out': 0.0,
        'transfer_in': 0.0,
        'transfer_out': 0.0,
        'adjustment_in': 0.0,
        'adjustment_out': 0.0,
        'tx_count': 0,
      },
    ];

    test('parses a full row and computes net flow', () {
      final account = CashFlowStatement.fromRows(rows).accounts.first;
      expect(account.accountTypeLabel, 'صندوق نقدي');
      expect(account.netFlow, 3000.0);
      expect(account.identityHolds, isTrue);
      expect(account.txCount, 7);
    });

    test('identityHolds rejects a closing balance that breaks the identity',
        () {
      final broken = CashFlowAccountStatement.fromMap({
        ...rows.first,
        'closing_balance': 13001.0,
      });
      expect(broken.identityHolds, isFalse);
    });

    test('aggregates opening, in, out and closing per currency', () {
      final statement = CashFlowStatement.fromRows(rows);
      expect(statement.accountsFor('SYP'), hasLength(2));
      expect(statement.accountsFor('USD'), hasLength(1));
      expect(statement.openingFor('SYP'), 30000.0);
      expect(statement.inflowsFor('SYP'), 6000.0);
      expect(statement.outflowsFor('SYP'), 2500.0);
      expect(statement.closingFor('SYP'), 33500.0);
      expect(statement.closingFor('USD'), 0.0);
    });

    test('allIdentitiesHold is true only when every account reconciles', () {
      expect(CashFlowStatement.fromRows(rows).allIdentitiesHold, isTrue);

      final broken = CashFlowStatement.fromRows([
        rows.first,
        {...rows[1], 'closing_balance': 20499.0},
      ]);
      expect(broken.allIdentitiesHold, isFalse);
    });
  });

  group('FinancialIntegrityReport', () {
    test('parses rows and exposes unbalanced entries', () {
      final report = FinancialIntegrityReport.fromRows([
        {
          'source_type': 'payment',
          'currency': 'SYP',
          'events_total': 5000.0,
          'ledger_total': 5000.0,
          'diff': 0.0,
          'is_balanced': true,
        },
        {
          'source_type': 'expense',
          'currency': 'SYP',
          'events_total': 2000.0,
          'ledger_total': 1900.0,
          'diff': 100.0,
          'is_balanced': false,
        },
      ]);

      expect(report.lines.first.sourceTypeLabel, 'الدفعات');
      expect(report.lines.last.sourceTypeLabel, 'المصاريف');
      expect(report.isBalanced, isFalse);
      expect(report.unbalanced, hasLength(1));
      expect(report.unbalanced.single.currency, 'SYP');
    });

    test('derives balance from diff when the flag is absent', () {
      final report = FinancialIntegrityReport.fromRows([
        {
          'source_type': 'refund',
          'currency': 'USD',
          'events_total': 50.0,
          'ledger_total': 50.0,
          'diff': 0.0,
        },
      ]);
      expect(report.isBalanced, isTrue);
      expect(report.lines.single.sourceTypeLabel, 'الاستردادات');
    });

    test('empty report is considered balanced', () {
      expect(const FinancialIntegrityReport([]).isBalanced, isTrue);
    });
  });
}
