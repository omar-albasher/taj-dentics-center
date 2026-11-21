import 'package:admin_dashboard/features/compensation/domain/compensation_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CohortTrainerRate Tests', () {
    test('parses frozen rate snapshot correctly', () {
      final map = {
        'cohort_id': 'coh-1',
        'cohort_name': 'الدفعة الأولى',
        'course_id': 'crs-1',
        'course_name': 'كورس التعويضات الثابتة',
        'trainer_id': 'tr-1',
        'trainer_name': 'د. أحمد',
        'starts_at': '2026-11-01T08:00:00Z',
        'cohort_is_active': true,
        'snapshot_id': 'snap-1',
        'rate_percent': 35.0,
        'rate_locked_at': '2026-11-01T10:00:00Z',
        'locked_by': 'usr-admin',
        'agreement_id': 'agr-1',
      };

      final rate = CohortTrainerRate.fromMap(map);

      expect(rate.cohortId, 'coh-1');
      expect(rate.courseName, 'كورس التعويضات الثابتة');
      expect(rate.cohortName, 'الدفعة الأولى');
      expect(rate.ratePercent, 35.0);
      expect(rate.isFrozen, isTrue);
      expect(rate.rateLockedAt, isNotNull);
    });

    test('handles unfrozen cohort correctly', () {
      final map = {
        'cohort_id': 'coh-2',
        'cohort_name': 'الدفعة الثانية',
        'course_id': 'crs-1',
        'course_name': 'كورس التعويضات الثابتة',
        'trainer_id': null,
        'trainer_name': null,
        'starts_at': null,
        'cohort_is_active': true,
        'snapshot_id': null,
        'rate_percent': null,
        'rate_locked_at': null,
        'locked_by': null,
        'agreement_id': null,
      };

      final rate = CohortTrainerRate.fromMap(map);

      expect(rate.cohortId, 'coh-2');
      expect(rate.ratePercent, isNull);
      expect(rate.isFrozen, isFalse);
    });
  });

  group('TrainerAgreement Tests', () {
    test('parses agreement with nested user and course', () {
      final map = {
        'id': 'agr-1',
        'trainer_id': 'tr-1',
        'course_id': 'crs-1',
        'rate_percent': 25.0,
        'effective_from': '2026-11-01',
        'effective_to': '2027-11-01',
        'notes': 'اتفاقية موسم الشتاء',
        'created_at': '2026-11-01T12:00:00Z',
        'users': {'full_name': 'د. خالد'},
        'courses': {'name': 'زراعة الأسنان'},
      };

      final agr = TrainerAgreement.fromMap(map);

      expect(agr.id, 'agr-1');
      expect(agr.trainerName, 'د. خالد');
      expect(agr.courseName, 'زراعة الأسنان');
      expect(agr.ratePercent, 25.0);
      expect(agr.notes, 'اتفاقية موسم الشتاء');
      expect(agr.effectiveTo, isNotNull);
    });
  });

  group('TrainerDue Tests', () {
    test('computes paidTotal, remaining, and status flags correctly', () {
      final map = {
        'id': 'due-1',
        'cohort_id': 'coh-1',
        'trainer_id': 'tr-1',
        'period_start': '2026-11-01',
        'period_end': '2026-11-30',
        'currency': 'SYP',
        'total_collected': 2000000.0,
        'applied_rate_percent': 25.0,
        'calculated_due': 500000.0,
        'status': 'partially_paid',
        'created_at': '2026-11-20T10:00:00Z',
        'trainer_name': 'د. أحمد',
        'course_name': 'تقويم الأسنان',
        'cohort_name': 'دفعة أ',
        'paid_total': 200000.0,
      };

      final due = TrainerDue.fromMap(map);

      expect(due.id, 'due-1');
      expect(due.totalCollected, 2000000.0);
      expect(due.calculatedDue, 500000.0);
      expect(due.paidTotal, 200000.0);
      expect(due.remaining, 300000.0);
      expect(due.isPartiallyPaid, isTrue);
      expect(due.isPaid, isFalse);
      expect(due.isUnpaid, isFalse);
    });

    test('paid in full due flags', () {
      final map = {
        'id': 'due-2',
        'cohort_id': 'coh-1',
        'trainer_id': 'tr-1',
        'period_start': '2026-11-01',
        'period_end': '2026-11-30',
        'currency': 'USD',
        'total_collected': 1000.0,
        'applied_rate_percent': 30.0,
        'calculated_due': 300.0,
        'status': 'paid',
        'paid_total': 300.0,
      };

      final due = TrainerDue.fromMap(map);

      expect(due.remaining, 0.0);
      expect(due.isPaid, isTrue);
      expect(due.isPartiallyPaid, isFalse);
      expect(due.isUnpaid, isFalse);
    });
  });

  group('StaffCompensationRow Tests', () {
    test('parses compensation and translates role correctly', () {
      final map = {
        'id': 'sc-1',
        'user_id': 'u-1',
        'monthly_salary': 1500000.0,
        'currency': 'SYP',
        'commission_rate_percent': 2.5,
        'effective_from': '2026-11-01',
        'effective_to': null,
        'notes': 'موظف استقبال رئيسي',
        'created_at': '2026-11-01T10:00:00Z',
        'full_name': 'سارة محمد',
        'role': 'reception',
        'is_active': true,
      };

      final row = StaffCompensationRow.fromMap(map);

      expect(row.fullName, 'سارة محمد');
      expect(row.monthlySalary, 1500000.0);
      expect(row.currency, 'SYP');
      expect(row.commissionRatePercent, 2.5);
      expect(row.roleAr, 'استقبال');
    });

    test('admin role translation', () {
      final map = {
        'id': 'sc-2',
        'user_id': 'u-2',
        'monthly_salary': 2500.0,
        'currency': 'USD',
        'commission_rate_percent': 3.0,
        'effective_from': '2026-11-01',
        'full_name': 'عمر علي',
        'role': 'admin',
        'is_active': true,
      };

      final row = StaffCompensationRow.fromMap(map);
      expect(row.roleAr, 'إدارة');
    });
  });

  group('StaffAdvance Tests', () {
    test('status getters evaluate correctly', () {
      final openMap = {
        'id': 'adv-1',
        'user_id': 'u-1',
        'amount': 250000.0,
        'currency': 'SYP',
        'advanced_at': '2026-11-10',
        'account_id': 'acc-1',
        'reason': 'سلفة مصاريف',
        'status': 'open',
        'payroll_line_id': null,
        'created_at': '2026-11-10T10:00:00Z',
        'users': {'full_name': 'أحمد حسن'},
        'financial_accounts': {'name_ar': 'صندوق المركز'},
      };

      final openAdv = StaffAdvance.fromMap(openMap);
      expect(openAdv.isOpen, isTrue);
      expect(openAdv.isDeducted, isFalse);
      expect(openAdv.isCancelled, isFalse);
      expect(openAdv.accountNameAr, 'صندوق المركز');

      final deductedMap = Map<String, dynamic>.from(openMap)
        ..['status'] = 'deducted'
        ..['payroll_line_id'] = 'line-1';
      final deductedAdv = StaffAdvance.fromMap(deductedMap);
      expect(deductedAdv.isOpen, isFalse);
      expect(deductedAdv.isDeducted, isTrue);

      final cancelledMap = Map<String, dynamic>.from(openMap)
        ..['status'] = 'cancelled';
      final cancelledAdv = StaffAdvance.fromMap(cancelledMap);
      expect(cancelledAdv.isCancelled, isTrue);
      expect(cancelledAdv.isOpen, isFalse);
    });
  });

  group('StaffBonus Tests', () {
    test('isDeducted is true only when payroll_line_id is set', () {
      final pendingMap = {
        'id': 'bon-1',
        'user_id': 'u-1',
        'amount': 50000.0,
        'currency': 'SYP',
        'bonus_month': '2026-11-01',
        'reason': 'مكافأة تميز',
        'payroll_line_id': null,
        'created_at': '2026-11-15T10:00:00Z',
        'users': {'full_name': 'مريم أحمد'},
      };

      final pending = StaffBonus.fromMap(pendingMap);
      expect(pending.isDeducted, isFalse);

      final deducted = StaffBonus.fromMap(
        Map<String, dynamic>.from(pendingMap)
          ..['payroll_line_id'] = 'pl-1',
      );
      expect(deducted.isDeducted, isTrue);
    });
  });

  group('StaffReferral Tests', () {
    test('extracts nested trainee and user correctly', () {
      final map = {
        'id': 'ref-1',
        'enrollment_id': 'enr-1',
        'staff_id': 'u-staff',
        'commission_rate_percent': 2.5,
        'created_at': '2026-11-12T10:00:00Z',
        'users': {'full_name': 'سارة الموظفة'},
        'enrollments': {
          'trainees': {
            'trainee_code': 'TR-2026-0042',
            'users': {'full_name': 'طارق الطالب'},
          },
        },
      };

      final referral = StaffReferral.fromMap(map);

      expect(referral.id, 'ref-1');
      expect(referral.staffName, 'سارة الموظفة');
      expect(referral.traineeName, 'طارق الطالب');
      expect(referral.traineeCode, 'TR-2026-0042');
      expect(referral.commissionRatePercent, 2.5);
    });
  });

  group('PayrollLine Tests', () {
    test('parses run status and netAmount correctly', () {
      final map = {
        'payroll_line_id': 'pl-1',
        'payroll_run_id': 'pr-1',
        'month': '2026-11-01',
        'run_status': 'draft',
        'user_id': 'u-1',
        'full_name': 'عمر الموظف',
        'role': 'reception',
        'currency': 'SYP',
        'base_salary': 1000000.0,
        'referral_commission': 25000.0,
        'bonus_amount': 50000.0,
        'advance_deduction': 200000.0,
        'net_amount': 875000.0,
        'line_status': 'pending',
        'expense_id': null,
      };

      final line = PayrollLine.fromMap(map);

      expect(line.payrollLineId, 'pl-1');
      expect(line.isDraft, isTrue);
      expect(line.isApproved, isFalse);
      expect(line.isPaid, isFalse);
      expect(line.roleAr, 'استقبال');

      // Formula: base (1,000,000) + comm (25,000) + bonus (50,000) - adv (200,000) = 875,000
      expect(
        line.baseSalary +
            line.referralCommission +
            line.bonusAmount -
            line.advanceDeduction,
        line.netAmount,
      );
    });

    test('run status approved and paid flags', () {
      final approved = PayrollLine.fromMap({
        'payroll_line_id': 'pl-2',
        'payroll_run_id': 'pr-2',
        'month': '2026-11-01',
        'run_status': 'approved',
        'user_id': 'u-2',
        'full_name': 'د. سامر',
        'role': 'admin',
        'currency': 'SYP',
        'base_salary': 2000000.0,
        'net_amount': 2000000.0,
      });

      expect(approved.isApproved, isTrue);
      expect(approved.isDraft, isFalse);
      expect(approved.isPaid, isFalse);

      final paid = PayrollLine.fromMap({
        'payroll_line_id': 'pl-3',
        'payroll_run_id': 'pr-3',
        'month': '2026-11-01',
        'run_status': 'paid',
        'user_id': 'u-3',
        'full_name': 'نور',
        'role': 'reception',
        'currency': 'SYP',
        'base_salary': 800000.0,
        'net_amount': 800000.0,
        'expense_id': 'exp-1',
      });

      expect(paid.isPaid, isTrue);
      expect(paid.isApproved, isFalse);
      expect(paid.isDraft, isFalse);
    });
  });

  group('Parsing and Date Helpers Tests', () {
    test('monthKey formats YYYY-MM-01 consistently', () {
      final d1 = DateTime(2026, 11, 20, 15, 30);
      expect(monthKey(d1), '2026-11-01');

      final d2 = DateTime(2026, 1, 5);
      expect(monthKey(d2), '2026-01-01');
    });

    test('firstOfMonth resets time and day to 1', () {
      final d = DateTime(2026, 11, 20, 18, 45, 12);
      final first = firstOfMonth(d);

      expect(first.year, 2026);
      expect(first.month, 11);
      expect(first.day, 1);
      expect(first.hour, 0);
      expect(first.minute, 0);
    });

    test('dateOnlyFrom parses String, DateTime, and null', () {
      expect(dateOnlyFrom('2026-11-05')?.year, 2026);
      expect(dateOnlyFrom(DateTime(2026, 11, 5))?.day, 5);
      expect(dateOnlyFrom(null), isNull);
      expect(dateOnlyFrom('invalid'), isNull);
    });

    test('asDouble converts num, string, and null safely', () {
      expect(asDouble(100), 100.0);
      expect(asDouble(100.5), 100.5);
      expect(asDouble('250.75'), 250.75);
      expect(asDouble(null), isNull);
      expect(asDouble('abc'), isNull);
    });
  });
}
