import 'package:flutter/foundation.dart';

@immutable
class AccountingPeriod {
  final String id;
  final DateTime periodMonth;
  final String status; // 'open' | 'closed'
  final DateTime? closedAt;
  final String? closedBy;
  final DateTime? reopenedAt;
  final String? reopenedBy;
  final String? reopenReason;
  final int reopenCount;
  final DateTime? createdAt;
  final String? createdBy;

  const AccountingPeriod({
    required this.id,
    required this.periodMonth,
    required this.status,
    this.closedAt,
    this.closedBy,
    this.reopenedAt,
    this.reopenedBy,
    this.reopenReason,
    this.reopenCount = 0,
    this.createdAt,
    this.createdBy,
  });

  bool get isClosed => status == 'closed';
  bool get isOpen => status == 'open';

  String get monthKey {
    final y = periodMonth.year.toString().padLeft(4, '0');
    final m = periodMonth.month.toString().padLeft(2, '0');
    return '$y-$m';
  }

  static const _arabicMonths = [
    'كانون الثاني',
    'شباط',
    'آذار',
    'نيسان',
    'أيار',
    'حزيران',
    'تموز',
    'آب',
    'أيلول',
    'تشرين الأول',
    'تشرين الثاني',
    'كانون الأول',
  ];

  String get formattedArabic {
    final monthName = _arabicMonths[periodMonth.month - 1];
    return '$monthName ${periodMonth.year} ($monthKey)';
  }

  factory AccountingPeriod.fromMap(Map<String, dynamic> map) {
    DateTime parseDate(dynamic v) {
      if (v is DateTime) return v;
      return DateTime.parse(v.toString());
    }

    return AccountingPeriod(
      id: map['id']?.toString() ?? '',
      periodMonth: parseDate(map['period_month']),
      status: map['status']?.toString() ?? 'open',
      closedAt: map['closed_at'] != null ? parseDate(map['closed_at']) : null,
      closedBy: map['closed_by']?.toString(),
      reopenedAt: map['reopened_at'] != null ? parseDate(map['reopened_at']) : null,
      reopenedBy: map['reopened_by']?.toString(),
      reopenReason: map['reopen_reason']?.toString(),
      reopenCount: (map['reopen_count'] as num?)?.toInt() ?? 0,
      createdAt: map['created_at'] != null ? parseDate(map['created_at']) : null,
      createdBy: map['created_by']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'period_month': '$monthKey-01',
      'status': status,
      'closed_at': closedAt?.toIso8601String(),
      'closed_by': closedBy,
      'reopened_at': reopenedAt?.toIso8601String(),
      'reopened_by': reopenedBy,
      'reopen_reason': reopenReason,
      'reopen_count': reopenCount,
      'created_at': createdAt?.toIso8601String(),
      'created_by': createdBy,
    };
  }
}

@immutable
class ClosePeriodResult {
  final String status;
  final String periodMonth;
  final bool forced;
  final bool hasCollections;
  final int duesRows;
  final int draftRuns;
  final int openSessions;

  const ClosePeriodResult({
    required this.status,
    required this.periodMonth,
    required this.forced,
    required this.hasCollections,
    required this.duesRows,
    required this.draftRuns,
    required this.openSessions,
  });

  bool get isAlreadyClosed => status == 'already_closed';
  bool get isClosed => status == 'closed' || status == 'reclosed';

  factory ClosePeriodResult.fromMap(Map<String, dynamic> map) {
    return ClosePeriodResult(
      status: map['status']?.toString() ?? '',
      periodMonth: map['period_month']?.toString() ?? '',
      forced: map['forced'] == true,
      hasCollections: map['has_collections'] == true,
      duesRows: (map['dues_rows'] as num?)?.toInt() ?? 0,
      draftRuns: (map['draft_runs'] as num?)?.toInt() ?? 0,
      openSessions: (map['open_sessions'] as num?)?.toInt() ?? 0,
    );
  }
}

@immutable
class ReopenPeriodResult {
  final String status;
  final String periodMonth;
  final int reopenCount;
  final String reason;

  const ReopenPeriodResult({
    required this.status,
    required this.periodMonth,
    required this.reopenCount,
    required this.reason,
  });

  factory ReopenPeriodResult.fromMap(Map<String, dynamic> map) {
    return ReopenPeriodResult(
      status: map['status']?.toString() ?? '',
      periodMonth: map['period_month']?.toString() ?? '',
      reopenCount: (map['reopen_count'] as num?)?.toInt() ?? 0,
      reason: map['reason']?.toString() ?? '',
    );
  }
}
