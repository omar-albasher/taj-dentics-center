double _asDouble(dynamic value) {
  if (value == null) return 0.0;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0.0;
}

int _asInt(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString()) ?? 0;
}

DateTime _asDateTime(dynamic value) {
  if (value == null) return DateTime.now();
  if (value is DateTime) return value;
  return DateTime.tryParse(value.toString()) ?? DateTime.now();
}

/// Represents one enrollment row in the As-Of Accrual Revenue Report (19 columns)
class AccrualRevenueReportRow {
  final String cohortId;
  final String cohortName;
  final String courseName;
  final int totalCourseSessions;
  final String enrollmentId;
  final String traineeId;
  final String traineeName;
  final String currency;
  final String lifecycleStatus;
  final DateTime enrolledAt;
  final double netDue;
  final double netPaid;
  final int sessionsPrior;
  final int plannedRemaining;
  final int deliveredSinceEnrolled;
  final double completionRatio;
  final double earnedRevenue;
  final double unearnedRevenue;
  final double accruedReceivables;

  const AccrualRevenueReportRow({
    required this.cohortId,
    required this.cohortName,
    required this.courseName,
    required this.totalCourseSessions,
    required this.enrollmentId,
    required this.traineeId,
    required this.traineeName,
    required this.currency,
    required this.lifecycleStatus,
    required this.enrolledAt,
    required this.netDue,
    required this.netPaid,
    required this.sessionsPrior,
    required this.plannedRemaining,
    required this.deliveredSinceEnrolled,
    required this.completionRatio,
    required this.earnedRevenue,
    required this.unearnedRevenue,
    required this.accruedReceivables,
  });

  factory AccrualRevenueReportRow.fromMap(Map<String, dynamic> map) {
    return AccrualRevenueReportRow(
      cohortId: (map['cohort_id'] ?? '').toString(),
      cohortName: (map['cohort_name'] ?? '').toString(),
      courseName: (map['course_name'] ?? '').toString(),
      totalCourseSessions: _asInt(map['total_course_sessions']),
      enrollmentId: (map['enrollment_id'] ?? '').toString(),
      traineeId: (map['trainee_id'] ?? '').toString(),
      traineeName: (map['trainee_name'] ?? '').toString(),
      currency: (map['currency'] ?? '').toString(),
      lifecycleStatus: (map['lifecycle_status'] ?? '').toString(),
      enrolledAt: _asDateTime(map['enrolled_at']),
      netDue: _asDouble(map['net_due']),
      netPaid: _asDouble(map['net_paid']),
      sessionsPrior: _asInt(map['sessions_prior']),
      plannedRemaining: _asInt(map['planned_remaining']),
      deliveredSinceEnrolled: _asInt(map['delivered_since_enrolled']),
      completionRatio: _asDouble(map['completion_ratio']),
      earnedRevenue: _asDouble(map['earned_revenue']),
      unearnedRevenue: _asDouble(map['unearned_revenue']),
      accruedReceivables: _asDouble(map['accrued_receivables']),
    );
  }

  bool get isCompleted => lifecycleStatus == 'completed';
  bool get isWithdrawn => lifecycleStatus == 'withdrawn';
  bool get isActive => lifecycleStatus == 'active';
}

/// Represents one currency row in the Accrual Reconciliation Bridge (15 columns)
class AccrualReconciliationReportRow {
  final String currency;
  final double openingUnearned;
  final double openingAccrued;
  final double openingEarnedCumulative;
  final double closingUnearned;
  final double closingAccrued;
  final double closingEarnedCumulative;
  final double deltaUnearned;
  final double deltaAccrued;
  final double periodEarnedRevenue;
  final double periodCashPayments;
  final double periodCashRefunds;
  final double periodCashNet;
  final double reconciliationDiff;
  final bool isReconciled;

  const AccrualReconciliationReportRow({
    required this.currency,
    required this.openingUnearned,
    required this.openingAccrued,
    required this.openingEarnedCumulative,
    required this.closingUnearned,
    required this.closingAccrued,
    required this.closingEarnedCumulative,
    required this.deltaUnearned,
    required this.deltaAccrued,
    required this.periodEarnedRevenue,
    required this.periodCashPayments,
    required this.periodCashRefunds,
    required this.periodCashNet,
    required this.reconciliationDiff,
    required this.isReconciled,
  });

  factory AccrualReconciliationReportRow.fromMap(Map<String, dynamic> map) {
    return AccrualReconciliationReportRow(
      currency: (map['currency'] ?? '').toString(),
      openingUnearned: _asDouble(map['opening_unearned']),
      openingAccrued: _asDouble(map['opening_accrued']),
      openingEarnedCumulative: _asDouble(map['opening_earned_cumulative']),
      closingUnearned: _asDouble(map['closing_unearned']),
      closingAccrued: _asDouble(map['closing_accrued']),
      closingEarnedCumulative: _asDouble(map['closing_earned_cumulative']),
      deltaUnearned: _asDouble(map['delta_unearned']),
      deltaAccrued: _asDouble(map['delta_accrued']),
      periodEarnedRevenue: _asDouble(map['period_earned_revenue']),
      periodCashPayments: _asDouble(map['period_cash_payments']),
      periodCashRefunds: _asDouble(map['period_cash_refunds']),
      periodCashNet: _asDouble(map['period_cash_net']),
      reconciliationDiff: _asDouble(map['reconciliation_diff']),
      isReconciled: map['is_reconciled'] == true,
    );
  }
}

/// Represents the response object from complete_cohort RPC
class CompleteCohortResult {
  final String cohortId;
  final String cohortName;
  final String status;
  final bool isActive;
  final int closedEnrollments;
  final String message;

  const CompleteCohortResult({
    required this.cohortId,
    required this.cohortName,
    required this.status,
    required this.isActive,
    required this.closedEnrollments,
    required this.message,
  });

  factory CompleteCohortResult.fromMap(Map<String, dynamic> map) {
    return CompleteCohortResult(
      cohortId: (map['cohort_id'] ?? '').toString(),
      cohortName: (map['cohort_name'] ?? '').toString(),
      status: (map['status'] ?? '').toString(),
      isActive: map['is_active'] == true,
      closedEnrollments: _asInt(map['closed_enrollments']),
      message: (map['message'] ?? '').toString(),
    );
  }

  bool get isAlreadyCompleted => status == 'already_completed';
}
