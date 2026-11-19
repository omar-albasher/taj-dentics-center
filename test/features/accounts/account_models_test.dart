import 'package:admin_dashboard/features/accounts/domain/account_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FinancialAccountBalance Tests', () {
    test('fromMap parses all fields correctly', () {
      final map = {
        'account_id': 'acc-1',
        'name_ar': 'صندوق المركز',
        'name_en': 'Center Cash Box',
        'account_type': 'cash',
        'currency': 'SYP',
        'is_active': true,
        'balance': 198570900.0,
        'total_inflow': 198571000.0,
        'total_outflow': 100.0,
        'transaction_count': 149,
        'last_transaction_at': '2026-11-18T10:00:00Z',
      };

      final acc = FinancialAccountBalance.fromMap(map);

      expect(acc.accountId, 'acc-1');
      expect(acc.nameAr, 'صندوق المركز');
      expect(acc.nameEn, 'Center Cash Box');
      expect(acc.accountType, 'cash');
      expect(acc.currency, 'SYP');
      expect(acc.isActive, isTrue);
      expect(acc.balance, 198570900.0);
      expect(acc.totalInflow, 198571000.0);
      expect(acc.totalOutflow, 100.0);
      expect(acc.transactionCount, 149);
      expect(acc.accountTypeLabel, 'صندوق نقدي');
    });

    test('labels map correctly for bank and wallet', () {
      final bank = FinancialAccountBalance.fromMap({
        'account_id': 'acc-2',
        'name_ar': 'البنك',
        'account_type': 'bank',
        'currency': 'USD',
        'is_active': true,
        'balance': 500.0,
        'total_inflow': 500.0,
        'total_outflow': 0.0,
        'transaction_count': 1,
      });

      final wallet = FinancialAccountBalance.fromMap({
        'account_id': 'acc-3',
        'name_ar': 'شام كاش',
        'account_type': 'wallet',
        'currency': 'SYP',
        'is_active': true,
        'balance': 0.0,
        'total_inflow': 0.0,
        'total_outflow': 0.0,
        'transaction_count': 0,
      });

      expect(bank.accountTypeLabel, 'حساب بنكي');
      expect(wallet.accountTypeLabel, 'محفظة إلكترونية');
    });
  });

  group('AccountLedgerEntry Tests', () {
    test('fromMap parses ledger row correctly', () {
      final map = {
        'id': 'tx-1',
        'account_id': 'acc-1',
        'account_name_ar': 'صندوق المركز',
        'account_name_en': 'Center Cash Box',
        'account_type': 'cash',
        'currency': 'SYP',
        'direction': 'inflow',
        'amount': 500000.0,
        'source_type': 'payment',
        'source_id': 'pay-1',
        'transfer_group': null,
        'derivation': 'auto_method',
        'occurred_at': '2026-11-18T12:00:00Z',
        'notes': 'دفعة كورس ألماني',
        'created_by': 'usr-1',
        'performed_by_name': 'أحمد السعدي',
        'created_at': '2026-11-18T12:00:00Z',
      };

      final entry = AccountLedgerEntry.fromMap(map);

      expect(entry.id, 'tx-1');
      expect(entry.accountId, 'acc-1');
      expect(entry.accountNameAr, 'صندوق المركز');
      expect(entry.direction, 'inflow');
      expect(entry.amount, 500000.0);
      expect(entry.sourceType, 'payment');
      expect(entry.sourceTypeLabel, 'دفعة متدرب');
      expect(entry.derivation, 'auto_method');
      expect(entry.derivationLabel, 'تلقائي (طريقة الدفع)');
      expect(entry.performedByName, 'أحمد السعدي');
    });

    test('sourceType and derivation labels for transfer and backfill', () {
      final transfer = AccountLedgerEntry.fromMap({
        'id': 'tx-2',
        'account_id': 'acc-1',
        'account_name_ar': 'صندوق المركز',
        'account_type': 'cash',
        'currency': 'SYP',
        'direction': 'outflow',
        'amount': 100000.0,
        'source_type': 'transfer',
        'transfer_group': 'grp-1',
        'derivation': 'manual',
        'occurred_at': '2026-11-18T12:00:00Z',
        'created_at': '2026-11-18T12:00:00Z',
      });

      final backfill = AccountLedgerEntry.fromMap({
        'id': 'tx-3',
        'account_id': 'acc-1',
        'account_name_ar': 'صندوق المركز',
        'account_type': 'cash',
        'currency': 'USD',
        'direction': 'inflow',
        'amount': 100.0,
        'source_type': 'expense',
        'source_id': 'exp-1',
        'derivation': 'backfill',
        'occurred_at': '2026-11-18T12:00:00Z',
        'created_at': '2026-11-18T12:00:00Z',
      });

      expect(transfer.sourceTypeLabel, 'تحويل داخلي');
      expect(backfill.sourceTypeLabel, 'مصروف تشغيلي');
      expect(backfill.derivationLabel, 'ترحيل سابق');
    });
  });

  group('AccountFilterParams Tests', () {
    test('default parameters are set properly', () {
      const params = AccountFilterParams();
      expect(params.page, 1);
      expect(params.pageSize, 25);
      expect(params.accountId, isNull);
      expect(params.sourceType, isNull);
      expect(params.fromDate, isNull);
      expect(params.toDate, isNull);
    });

    test('copyWith updates fields and clears filters correctly', () {
      final now = DateTime(2026, 11, 18);
      const params = AccountFilterParams();

      final updated = params.copyWith(
        page: 2,
        pageSize: 50,
        accountId: 'acc-1',
        sourceType: 'payment',
        fromDate: now,
        toDate: now.add(const Duration(days: 30)),
      );

      expect(updated.page, 2);
      expect(updated.pageSize, 50);
      expect(updated.accountId, 'acc-1');
      expect(updated.sourceType, 'payment');
      expect(updated.fromDate, now);
      expect(updated.toDate, now.add(const Duration(days: 30)));

      final cleared = updated.copyWith(
        clearAccountId: true,
        clearSourceType: true,
        clearFromDate: true,
        clearToDate: true,
      );

      expect(cleared.accountId, isNull);
      expect(cleared.sourceType, isNull);
      expect(cleared.fromDate, isNull);
      expect(cleared.toDate, isNull);
      expect(cleared.page, 2);
    });

    test('equality and hashCode work as expected', () {
      const p1 = AccountFilterParams(page: 1, accountId: 'acc-1');
      const p2 = AccountFilterParams(page: 1, accountId: 'acc-1');
      const p3 = AccountFilterParams(page: 2, accountId: 'acc-1');

      expect(p1, equals(p2));
      expect(p1.hashCode, equals(p2.hashCode));
      expect(p1, isNot(equals(p3)));
    });
  });
}
