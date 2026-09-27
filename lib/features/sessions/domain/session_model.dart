class AdminSessionModel {
  final String id;
  final String cohortId;
  final String cohortName;
  final String courseName;
  final int sessionNumber;
  final DateTime scheduledAt;
  final String status;
  final String? qrToken;
  final DateTime? openedAt;
  final DateTime? closedAt;

  const AdminSessionModel({
    required this.id,
    required this.cohortId,
    required this.cohortName,
    required this.courseName,
    required this.sessionNumber,
    required this.scheduledAt,
    required this.status,
    this.qrToken,
    this.openedAt,
    this.closedAt,
  });

  factory AdminSessionModel.fromMap(Map<String, dynamic> map) {
    final cohort = map['cohorts'] as Map<String, dynamic>? ?? {};
    final course = cohort['courses'] as Map<String, dynamic>? ?? {};
    return AdminSessionModel(
      id: map['id'] ?? '',
      cohortId: map['cohort_id'] ?? '',
      cohortName: cohort['name'] ?? '',
      courseName: course['name'] ?? '',
      sessionNumber: (map['session_number'] as num?)?.toInt() ?? 0,
      scheduledAt:
          DateTime.tryParse(map['scheduled_at'] ?? '') ?? DateTime.now(),
      status: map['status'] ?? 'scheduled',
      qrToken: map['qr_token'],
      openedAt:
          map['opened_at'] != null ? DateTime.tryParse(map['opened_at']) : null,
      closedAt:
          map['closed_at'] != null ? DateTime.tryParse(map['closed_at']) : null,
    );
  }

  bool get isOpen => status == 'open';
  bool get isScheduled => status == 'scheduled';
  bool get isClosed => status == 'closed';
}
