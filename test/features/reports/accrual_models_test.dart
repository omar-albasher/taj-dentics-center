import 'package:flutter_test/flutter_test.dart';
import 'package:admin_dashboard/features/reports/domain/accrual_models.dart';

void main() {
  group('AccrualRevenueReportRow', () {
    test('parses accurately from 19-column database map', () {
      final map = {
        'cohort_id': '596a281a-64ab-4909-a321-d437efa7ca9b',
        'cohort_name': 'C5 Main Cohort',
        'course_name': 'C5 Accrual Course',
        'total_course_sessions': 10,
        'enrollment_id': '908c1e64-ae6a-4ef1-8c26-c74563f8d5ba',
        'trainee_id': '413d13ac-e2b7-4fa9-8692-db56f4579f64',
        'trainee_name': 'متدرب تجريبي C5',
        'currency': 'SYP',
        'lifecycle_status': 'active',
        'enrolled_at': '2026-11-08T00:00:00.000Z',
        'net_due': 80000.00,
        'net_paid': 80000.00,
        'sessions_prior': 2,
        'planned_remaining': 8,
        'delivered_since_enrolled': 2,
        'completion_ratio': 0.25,
        'earned_revenue': 20000.00,
        'unearned_revenue': 60000.00,
        'accrued_receivables': 0.00,
      };

      final row = AccrualRevenueReportRow.fromMap(map);

      expect(row.cohortId, '596a281a-64ab-4909-a321-d437efa7ca9b');
      expect(row.cohortName, 'C5 Main Cohort');
      expect(row.courseName, 'C5 Accrual Course');
      expect(row.totalCourseSessions, 10);
      expect(row.enrollmentId, '908c1e64-ae6a-4ef1-8c26-c74563f8d5ba');
      expect(row.traineeId, '413d13ac-e2b7-4fa9-8692-db56f4579f64');
      expect(row.traineeName, 'متدرب تجريبي C5');
      expect(row.currency, 'SYP');
      expect(row.lifecycleStatus, 'active');
      expect(row.isActive, isTrue);
      expect(row.isCompleted, isFalse);
      expect(row.isWithdrawn, isFalse);
      expect(row.netDue, 80000.00);
      expect(row.netPaid, 80000.00);
      expect(row.sessionsPrior, 2);
      expect(row.plannedRemaining, 8);
      expect(row.deliveredSinceEnrolled, 2);
      expect(row.completionRatio, 0.25);
      expect(row.earnedRevenue, 20000.00);
      expect(row.unearnedRevenue, 60000.00);
      expect(row.accruedReceivables, 0.00);
    });

    test('handles null and numeric coercion safely', () {
      final row = AccrualRevenueReportRow.fromMap({});

      expect(row.cohortId, '');
      expect(row.totalCourseSessions, 0);
      expect(row.netDue, 0.0);
      expect(row.completionRatio, 0.0);
      expect(row.isActive, isFalse);
    });
  });

  group('AccrualReconciliationReportRow', () {
    test('parses accurately from 15-column database map', () {
      final map = {
        'currency': 'SYP',
        'opening_unearned': 10000.00,
        'opening_accrued': 5000.00,
        'opening_earned_cumulative': 50000.00,
        'closing_unearned': 60000.00,
        'closing_accrued': 0.00,
        'closing_earned_cumulative': 70000.00,
        'delta_unearned': 50000.00,
        'delta_accrued': -5000.00,
        'period_earned_revenue': 20000.00,
        'period_cash_payments': 80000.00,
        'period_cash_refunds': 10000.00,
        'period_cash_net': 70000.00,
        'reconciliation_diff': 0.00,
        'is_reconciled': true,
      };

      final row = AccrualReconciliationReportRow.fromMap(map);

      expect(row.currency, 'SYP');
      expect(row.openingUnearned, 10000.00);
      expect(row.openingAccrued, 5000.00);
      expect(row.openingEarnedCumulative, 50000.00);
      expect(row.closingUnearned, 60000.00);
      expect(row.closingAccrued, 0.00);
      expect(row.closingEarnedCumulative, 70000.00);
      expect(row.deltaUnearned, 50000.00);
      expect(row.deltaAccrued, -5000.00);
      expect(row.periodEarnedRevenue, 20000.00);
      expect(row.periodCashPayments, 80000.00);
      expect(row.periodCashRefunds, 10000.00);
      expect(row.periodCashNet, 70000.00);
      expect(row.reconciliationDiff, 0.00);
      expect(row.isReconciled, isTrue);
    });
  });

  group('CompleteCohortResult', () {
    test('parses normal completion result', () {
      final map = {
        'cohort_id': 'c-1',
        'cohort_name': 'Cohort 1',
        'status': 'completed',
        'is_active': false,
        'closed_enrollments': 3,
        'message': 'تم إقفال الفوج والتسجيلات بنجاح',
      };

      final res = CompleteCohortResult.fromMap(map);

      expect(res.cohortId, 'c-1');
      expect(res.cohortName, 'Cohort 1');
      expect(res.status, 'completed');
      expect(res.isActive, isFalse);
      expect(res.closedEnrollments, 3);
      expect(res.isAlreadyCompleted, isFalse);
      expect(res.message, 'تم إقفال الفوج والتسجيلات بنجاح');
    });

    test('parses already_completed idempotent result', () {
      final map = {
        'cohort_id': 'c-2',
        'cohort_name': 'Cohort 2',
        'status': 'already_completed',
        'is_active': false,
        'closed_enrollments': 0,
        'message': 'الفوج مقفل مسبقاً',
      };

      final res = CompleteCohortResult.fromMap(map);

      expect(res.cohortId, 'c-2');
      expect(res.status, 'already_completed');
      expect(res.isAlreadyCompleted, isTrue);
      expect(res.closedEnrollments, 0);
    });
  });
}
