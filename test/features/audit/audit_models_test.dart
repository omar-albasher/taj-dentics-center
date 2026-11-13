import 'package:admin_dashboard/features/audit/data/audit_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuditFilterParams Tests (Phase D4.4)', () {
    test('default parameters are set properly', () {
      const params = AuditFilterParams();
      expect(params.page, 1);
      expect(params.pageSize, 25);
      expect(params.tableName, isNull);
      expect(params.operation, isNull);
      expect(params.fromDate, isNull);
      expect(params.toDate, isNull);
    });

    test('copyWith updates fields and clears dates correctly', () {
      final now = DateTime(2026, 11, 15);
      const params = AuditFilterParams();

      final updated = params.copyWith(
        page: 2,
        pageSize: 50,
        tableName: 'payment_refunds',
        operation: 'INSERT',
        fromDate: now,
        toDate: now.add(const Duration(days: 7)),
      );

      expect(updated.page, 2);
      expect(updated.pageSize, 50);
      expect(updated.tableName, 'payment_refunds');
      expect(updated.operation, 'INSERT');
      expect(updated.fromDate, now);
      expect(updated.toDate, now.add(const Duration(days: 7)));

      final cleared = updated.copyWith(
        clearFromDate: true,
        clearToDate: true,
      );
      expect(cleared.fromDate, isNull);
      expect(cleared.toDate, isNull);
      expect(cleared.tableName, 'payment_refunds');
    });

    test('equality and hashCode work as expected', () {
      const p1 = AuditFilterParams(page: 1, tableName: 'payments');
      const p2 = AuditFilterParams(page: 1, tableName: 'payments');
      const p3 = AuditFilterParams(page: 2, tableName: 'payments');

      expect(p1, equals(p2));
      expect(p1.hashCode, equals(p2.hashCode));
      expect(p1, isNot(equals(p3)));
    });
  });

  group('AuditQueryResult Pagination Tests (Phase D4.4)', () {
    test('calculates totalPages and navigation flags correctly', () {
      const resultPage1 = AuditQueryResult(
        logs: [{'id': 1}, {'id': 2}],
        totalCount: 50,
        currentPage: 1,
        pageSize: 25,
      );

      expect(resultPage1.totalPages, 2);
      expect(resultPage1.hasNextPage, isTrue);
      expect(resultPage1.hasPrevPage, isFalse);

      const resultPage2 = AuditQueryResult(
        logs: [{'id': 3}],
        totalCount: 50,
        currentPage: 2,
        pageSize: 25,
      );

      expect(resultPage2.totalPages, 2);
      expect(resultPage2.hasNextPage, isFalse);
      expect(resultPage2.hasPrevPage, isTrue);
    });

    test('handles empty results and exact page sizes', () {
      const emptyResult = AuditQueryResult(
        logs: [],
        totalCount: 0,
        currentPage: 1,
        pageSize: 25,
      );

      expect(emptyResult.totalPages, 0);
      expect(emptyResult.hasNextPage, isFalse);
      expect(emptyResult.hasPrevPage, isFalse);

      const exactResult = AuditQueryResult(
        logs: [],
        totalCount: 50,
        currentPage: 1,
        pageSize: 10,
      );
      expect(exactResult.totalPages, 5);
    });
  });
}

