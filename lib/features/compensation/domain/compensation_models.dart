class CohortTrainerRate {
  final String cohortId;
  final String cohortName;
  final DateTime? startsAt;
  final String trainerId;
  final String trainerName;
  final String courseId;
  final String courseName;
  final double? ratePercent;
  final DateTime? lockedOn;
  final DateTime? lockedAt;
  final String? agreementId;
  final DateTime? agreementFrom;
  final DateTime? agreementTo;

  const CohortTrainerRate({
    required this.cohortId,
    required this.cohortName,
    this.startsAt,
    required this.trainerId,
    required this.trainerName,
    required this.courseId,
    required this.courseName,
    this.ratePercent,
    this.lockedOn,
    this.lockedAt,
    this.agreementId,
    this.agreementFrom,
    this.agreementTo,
  });

  bool get isLocked => ratePercent != null;
  bool get isFrozen => isLocked;
  DateTime? get rateLockedAt => lockedAt ?? lockedOn;

  factory CohortTrainerRate.fromMap(Map<String, dynamic> map) {
    return CohortTrainerRate(
      cohortId: map['cohort_id']?.toString() ?? '',
      cohortName: map['cohort_name']?.toString() ?? '',
      startsAt: dateOnlyFrom(map['starts_at']),
      trainerId: map['trainer_id']?.toString() ?? '',
      trainerName: map['trainer_name']?.toString() ?? '',
      courseId: map['course_id']?.toString() ?? '',
      courseName: map['course_name']?.toString() ?? '',
      ratePercent: asDouble(map['rate_percent']),
      lockedOn: dateOnlyFrom(map['locked_on']),
      lockedAt: dateTimeFrom(map['locked_at'] ?? map['rate_locked_at']),
      agreementId: map['agreement_id']?.toString(),
      agreementFrom: dateOnlyFrom(map['agreement_from']),
      agreementTo: dateOnlyFrom(map['agreement_to']),
    );
  }
}

class TrainerAgreement {
  final String id;
  final String trainerId;
  final String trainerName;
  final String courseId;
  final String courseName;
  final double ratePercent;
  final DateTime effectiveFrom;
  final DateTime? effectiveTo;
  final String? notes;
  final DateTime? createdAt;

  const TrainerAgreement({
    required this.id,
    required this.trainerId,
    required this.trainerName,
    required this.courseId,
    required this.courseName,
    required this.ratePercent,
    required this.effectiveFrom,
    this.effectiveTo,
    this.notes,
    this.createdAt,
  });

  bool get isOpenEnded => effectiveTo == null;

  factory TrainerAgreement.fromMap(Map<String, dynamic> map) {
    final trainer = embeddedMap(map['users']);
    final course = embeddedMap(map['courses']);
    return TrainerAgreement(
      id: map['id']?.toString() ?? '',
      trainerId: map['trainer_id']?.toString() ?? '',
      trainerName: trainer?['full_name']?.toString() ?? '',
      courseId: map['course_id']?.toString() ?? '',
      courseName: course?['name']?.toString() ?? '',
      ratePercent: asDouble(map['rate_percent']) ?? 0,
      effectiveFrom: dateOnlyFrom(map['effective_from']) ?? DateTime(2000),
      effectiveTo: dateOnlyFrom(map['effective_to']),
      notes: map['notes']?.toString(),
      createdAt: dateTimeFrom(map['created_at']),
    );
  }
}

class TrainerDue {
  final String id;
  final String trainerId;
  final String trainerName;
  final String cohortId;
  final String cohortName;
  final DateTime periodStart;
  final DateTime periodEnd;
  final String currency;
  final double basisAmount;
  final double ratePercent;
  final double amount;
  final String status; // pending, paid, cancelled
  final double paidTotal;
  final double remaining;
  final DateTime? createdAt;

  const TrainerDue({
    required this.id,
    required this.trainerId,
    required this.trainerName,
    required this.cohortId,
    required this.cohortName,
    required this.periodStart,
    required this.periodEnd,
    required this.currency,
    required this.basisAmount,
    required this.ratePercent,
    required this.amount,
    required this.status,
    required this.paidTotal,
    required this.remaining,
    this.createdAt,
  });

  bool get isPending => status == 'pending';
  bool get isPaid => status == 'paid';
  bool get isPartiallyPaid => remaining > 0 && remaining < amount;
  bool get isUnpaid => remaining >= amount && amount > 0;

  double get calculatedDue => amount;
  double get totalCollected => basisAmount;
  double get appliedRatePercent => ratePercent;
  String get courseName => cohortName;

  String get statusLabel {
    switch (status) {
      case 'pending':
        return 'مستحق';
      case 'paid':
        return 'مدفوع';
      case 'cancelled':
        return 'ملغى';
      default:
        return status;
    }
  }

  factory TrainerDue.fromMap(Map<String, dynamic> map) {
    final amount = asDouble(map['amount'] ?? map['calculated_due']) ?? 0;
    final paidTotal = asDouble(map['paid_total']) ?? 0;
    final remaining = asDouble(map['remaining']) ?? (amount - paidTotal);
    return TrainerDue(
      id: map['id']?.toString() ?? '',
      trainerId: map['trainer_id']?.toString() ?? '',
      trainerName: map['trainer_name']?.toString() ?? '',
      cohortId: map['cohort_id']?.toString() ?? '',
      cohortName: map['cohort_name']?.toString() ?? '',
      periodStart: dateOnlyFrom(map['period_start']) ?? DateTime(2000),
      periodEnd: dateOnlyFrom(map['period_end']) ?? DateTime(2000),
      currency: map['currency']?.toString() ?? 'SYP',
      basisAmount: asDouble(map['basis_amount'] ?? map['total_collected']) ?? 0,
      ratePercent: asDouble(map['rate_percent'] ?? map['applied_rate_percent']) ?? 0,
      amount: amount,
      status: map['status']?.toString() ?? 'pending',
      paidTotal: paidTotal,
      remaining: remaining,
      createdAt: dateTimeFrom(map['created_at']),
    );
  }
}

class TrainerPayment {
  final String id;
  final String dueId;
  final String trainerName;
  final String cohortName;
  final DateTime periodStart;
  final DateTime periodEnd;
  final double amount;
  final String currency;
  final String accountId;
  final String accountName;
  final String? expenseId;
  final DateTime paidAt;

  const TrainerPayment({
    required this.id,
    required this.dueId,
    required this.trainerName,
    required this.cohortName,
    required this.periodStart,
    required this.periodEnd,
    required this.amount,
    required this.currency,
    required this.accountId,
    required this.accountName,
    this.expenseId,
    required this.paidAt,
  });

  factory TrainerPayment.fromMap(Map<String, dynamic> map) {
    return TrainerPayment(
      id: map['id']?.toString() ?? '',
      dueId: map['due_id']?.toString() ?? '',
      trainerName: map['trainer_name']?.toString() ?? '',
      cohortName: map['cohort_name']?.toString() ?? '',
      periodStart: dateOnlyFrom(map['period_start']) ?? DateTime(2000),
      periodEnd: dateOnlyFrom(map['period_end']) ?? DateTime(2000),
      amount: asDouble(map['amount']) ?? 0,
      currency: map['currency']?.toString() ?? 'SYP',
      accountId: map['account_id']?.toString() ?? '',
      accountName: map['account_name']?.toString() ?? '',
      expenseId: map['expense_id']?.toString(),
      paidAt: dateTimeFrom(map['paid_at']) ?? DateTime.now(),
    );
  }
}

class StaffCompensationRow {
  final String id;
  final String userId;
  final String fullName;
  final String role;
  final bool isActive;
  final double monthlySalary;
  final String currency;
  final double commissionRatePercent;
  final DateTime effectiveFrom;
  final DateTime? effectiveTo;
  final String? notes;
  final DateTime? createdAt;

  const StaffCompensationRow({
    required this.id,
    required this.userId,
    required this.fullName,
    required this.role,
    required this.isActive,
    required this.monthlySalary,
    required this.currency,
    required this.commissionRatePercent,
    required this.effectiveFrom,
    this.effectiveTo,
    this.notes,
    this.createdAt,
  });

  bool get isOpenEnded => effectiveTo == null;

  String get roleAr {
    switch (role) {
      case 'admin':
        return 'إدارة';
      case 'reception':
        return 'استقبال';
      case 'trainer':
        return 'مدرب';
      default:
        return role;
    }
  }

  factory StaffCompensationRow.fromMap(Map<String, dynamic> map) {
    return StaffCompensationRow(
      id: map['id']?.toString() ?? '',
      userId: map['user_id']?.toString() ?? '',
      fullName: map['full_name']?.toString() ?? '',
      role: map['role']?.toString() ?? '',
      isActive: map['is_active'] == true,
      monthlySalary: asDouble(map['monthly_salary']) ?? 0,
      currency: map['currency']?.toString() ?? 'SYP',
      commissionRatePercent: asDouble(map['commission_rate_percent']) ?? 0,
      effectiveFrom: dateOnlyFrom(map['effective_from']) ?? DateTime(2000),
      effectiveTo: dateOnlyFrom(map['effective_to']),
      notes: map['notes']?.toString(),
      createdAt: dateTimeFrom(map['created_at']),
    );
  }
}

class StaffAdvance {
  final String id;
  final String userId;
  final String fullName;
  final double amount;
  final String currency;
  final DateTime advancedAt;
  final String accountId;
  final String accountName;
  final String? reason;
  final String status; // open, deducted, cancelled
  final String? payrollLineId;
  final DateTime? createdAt;

  const StaffAdvance({
    required this.id,
    required this.userId,
    required this.fullName,
    required this.amount,
    required this.currency,
    required this.advancedAt,
    required this.accountId,
    required this.accountName,
    this.reason,
    required this.status,
    this.payrollLineId,
    this.createdAt,
  });

  bool get isOpen => status == 'open';
  bool get isDeducted => status == 'deducted';
  bool get isCancelled => status == 'cancelled';
  String get userName => fullName;
  String get accountNameAr => accountName;

  String get statusLabel {
    switch (status) {
      case 'open':
        return 'مفتوحة';
      case 'deducted':
        return 'مخصومة';
      case 'cancelled':
        return 'ملغاة';
      default:
        return status;
    }
  }

  factory StaffAdvance.fromMap(Map<String, dynamic> map) {
    final user = embeddedMap(map['users']);
    final account = embeddedMap(map['financial_accounts']);
    return StaffAdvance(
      id: map['id']?.toString() ?? '',
      userId: map['user_id']?.toString() ?? '',
      fullName: user?['full_name']?.toString() ?? '',
      amount: asDouble(map['amount']) ?? 0,
      currency: map['currency']?.toString() ?? 'SYP',
      advancedAt: dateOnlyFrom(map['advanced_at']) ?? DateTime.now(),
      accountId: map['account_id']?.toString() ?? '',
      accountName: account?['name_ar']?.toString() ?? '',
      reason: map['reason']?.toString(),
      status: map['status']?.toString() ?? 'open',
      payrollLineId: map['payroll_line_id']?.toString(),
      createdAt: dateTimeFrom(map['created_at']),
    );
  }
}

class StaffBonus {
  final String id;
  final String userId;
  final String fullName;
  final double amount;
  final String currency;
  final DateTime bonusMonth;
  final String reason;
  final String? payrollLineId;
  final DateTime? createdAt;

  const StaffBonus({
    required this.id,
    required this.userId,
    required this.fullName,
    required this.amount,
    required this.currency,
    required this.bonusMonth,
    required this.reason,
    this.payrollLineId,
    this.createdAt,
  });

  bool get isPaid => payrollLineId != null;
  bool get isDeducted => payrollLineId != null;
  String get userName => fullName;

  factory StaffBonus.fromMap(Map<String, dynamic> map) {
    final user = embeddedMap(map['users']);
    return StaffBonus(
      id: map['id']?.toString() ?? '',
      userId: map['user_id']?.toString() ?? '',
      fullName: user?['full_name']?.toString() ?? '',
      amount: asDouble(map['amount']) ?? 0,
      currency: map['currency']?.toString() ?? 'SYP',
      bonusMonth: dateOnlyFrom(map['bonus_month']) ?? DateTime(2000),
      reason: map['reason']?.toString() ?? '',
      payrollLineId: map['payroll_line_id']?.toString(),
      createdAt: dateTimeFrom(map['created_at']),
    );
  }
}

class StaffReferral {
  final String id;
  final String enrollmentId;
  final String staffId;
  final String staffName;
  final String traineeName;
  final String traineeCode;
  final double commissionRatePercent;
  final DateTime? createdAt;

  const StaffReferral({
    required this.id,
    required this.enrollmentId,
    required this.staffId,
    required this.staffName,
    required this.traineeName,
    required this.traineeCode,
    required this.commissionRatePercent,
    this.createdAt,
  });

  factory StaffReferral.fromMap(Map<String, dynamic> map) {
    final staff = embeddedMap(map['users']);
    final enrollment = embeddedMap(map['enrollments']);
    final trainee = enrollment != null
        ? embeddedMap(enrollment['trainees'])
        : null;
    final traineeUser = trainee != null
        ? embeddedMap(trainee['users'])
        : null;
    return StaffReferral(
      id: map['id']?.toString() ?? '',
      enrollmentId: map['enrollment_id']?.toString() ?? '',
      staffId: map['staff_id']?.toString() ?? '',
      staffName: staff?['full_name']?.toString() ?? '',
      traineeName: traineeUser?['full_name']?.toString() ?? '',
      traineeCode: trainee?['trainee_code']?.toString() ?? '',
      commissionRatePercent:
          asDouble(map['commission_rate_percent']) ?? 0,
      createdAt: dateTimeFrom(map['created_at']),
    );
  }
}

class PayrollLine {
  final String lineId;
  final String runId;
  final DateTime month;
  final String runStatus; // draft, approved, paid
  final String userId;
  final String fullName;
  final String role;
  final String currency;
  final double baseSalary;
  final double commissionAmount;
  final double bonusAmount;
  final double advancesDeducted;
  final double netAmount;
  final String? expenseId;
  final DateTime? runCreatedAt;
  final String? approvedBy;
  final DateTime? approvedAt;

  const PayrollLine({
    required this.lineId,
    required this.runId,
    required this.month,
    required this.runStatus,
    required this.userId,
    required this.fullName,
    this.role = '',
    required this.currency,
    required this.baseSalary,
    required this.commissionAmount,
    required this.bonusAmount,
    required this.advancesDeducted,
    required this.netAmount,
    this.expenseId,
    this.runCreatedAt,
    this.approvedBy,
    this.approvedAt,
  });

  bool get isDraft => runStatus == 'draft';
  bool get isApproved => runStatus == 'approved';
  bool get isPaid => runStatus == 'paid';

  String get roleAr {
    switch (role) {
      case 'admin':
        return 'إدارة';
      case 'reception':
        return 'استقبال';
      default:
        return role;
    }
  }

  String get payrollRunId => runId;
  String get payrollLineId => lineId;
  double get referralCommission => commissionAmount;
  double get advanceDeduction => advancesDeducted;

  String get runStatusLabel {
    switch (runStatus) {
      case 'draft':
        return 'مسودة';
      case 'approved':
        return 'معتمد';
      case 'paid':
        return 'مدفوع';
      default:
        return runStatus;
    }
  }

  factory PayrollLine.fromMap(Map<String, dynamic> map) {
    return PayrollLine(
      lineId: (map['line_id'] ?? map['payroll_line_id'])?.toString() ?? '',
      runId: (map['run_id'] ?? map['payroll_run_id'])?.toString() ?? '',
      month: dateOnlyFrom(map['month']) ?? DateTime(2000),
      runStatus: map['run_status']?.toString() ?? 'draft',
      userId: map['user_id']?.toString() ?? '',
      fullName: map['full_name']?.toString() ?? '',
      role: map['role']?.toString() ?? '',
      currency: map['currency']?.toString() ?? 'SYP',
      baseSalary: asDouble(map['base_salary']) ?? 0,
      commissionAmount: asDouble(map['commission_amount'] ?? map['referral_commission']) ?? 0,
      bonusAmount: asDouble(map['bonus_amount']) ?? 0,
      advancesDeducted: asDouble(map['advances_deducted'] ?? map['advance_deduction']) ?? 0,
      netAmount: asDouble(map['net_amount']) ?? 0,
      expenseId: map['expense_id']?.toString(),
      runCreatedAt: dateTimeFrom(map['run_created_at']),
      approvedBy: map['approved_by']?.toString(),
      approvedAt: dateTimeFrom(map['approved_at']),
    );
  }
}

class CompensationUser {
  final String id;
  final String fullName;
  final String? role;
  final bool isActive;

  const CompensationUser({
    required this.id,
    required this.fullName,
    this.role,
    this.isActive = true,
  });

  String get roleAr {
    switch (role) {
      case 'admin':
        return 'إدارة';
      case 'reception':
        return 'استقبال';
      case 'trainer':
        return 'مدرب';
      default:
        return role ?? '';
    }
  }

  factory CompensationUser.fromMap(Map<String, dynamic> map) {
    return CompensationUser(
      id: map['id']?.toString() ?? '',
      fullName: map['full_name']?.toString() ?? '',
      role: map['role']?.toString(),
      isActive: map['is_active'] != false,
    );
  }
}

class CourseOption {
  final String id;
  final String name;

  const CourseOption({required this.id, required this.name});

  factory CourseOption.fromMap(Map<String, dynamic> map) {
    return CourseOption(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
    );
  }
}

class EnrollmentOption {
  final String id;
  final String traineeName;
  final String traineeCode;
  final String courseName;
  final DateTime? createdAt;

  const EnrollmentOption({
    required this.id,
    required this.traineeName,
    required this.traineeCode,
    required this.courseName,
    this.createdAt,
  });

  factory EnrollmentOption.fromMap(Map<String, dynamic> map) {
    final trainee = embeddedMap(map['trainees']);
    final traineeUser =
        trainee != null ? embeddedMap(trainee['users']) : null;
    final cohort = embeddedMap(map['cohorts']);
    final course = cohort != null ? embeddedMap(cohort['courses']) : null;
    return EnrollmentOption(
      id: map['id']?.toString() ?? '',
      traineeName: traineeUser?['full_name']?.toString() ?? '',
      traineeCode: trainee?['trainee_code']?.toString() ?? '',
      courseName: course?['name']?.toString() ?? '',
      createdAt: dateTimeFrom(map['created_at']),
    );
  }
}

// ---------------------------------------------------------------------------
// Map helpers shared by every compensation model
// ---------------------------------------------------------------------------
Map<String, dynamic>? embeddedMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  if (value is List && value.isNotEmpty) return embeddedMap(value.first);
  return null;
}

double? asDouble(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

DateTime? dateOnlyFrom(dynamic value) {
  if (value == null) return null;
  final raw = value.toString();
  if (raw.isEmpty) return null;
  return DateTime.tryParse(raw);
}

DateTime? dateTimeFrom(dynamic value) {
  if (value == null) return null;
  final raw = value.toString();
  if (raw.isEmpty) return null;
  return DateTime.tryParse(raw)?.toLocal();
}

DateTime firstOfMonth(DateTime value) => DateTime(value.year, value.month);

String monthKey(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  return '${value.year}-$month-01';
}
