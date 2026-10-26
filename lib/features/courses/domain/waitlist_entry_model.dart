class WaitlistEntryModel {
  final String id;
  final String cohortId;
  final String traineeId;
  final String status;
  final DateTime? joinedAt;
  final DateTime? notifiedAt;
  final DateTime? expiresAt;
  final DateTime? promotedAt;
  final String traineeName;
  final String traineeCode;
  final String traineePhone;
  final bool traineeUserActive;

  const WaitlistEntryModel({
    required this.id,
    required this.cohortId,
    required this.traineeId,
    required this.status,
    this.joinedAt,
    this.notifiedAt,
    this.expiresAt,
    this.promotedAt,
    required this.traineeName,
    required this.traineeCode,
    required this.traineePhone,
    required this.traineeUserActive,
  });

  factory WaitlistEntryModel.fromMap(Map<String, dynamic> map) {
    final trainee = map['trainees'] as Map<String, dynamic>?;
    final user = trainee?['users'] as Map<String, dynamic>?;

    final name = user?['full_name'] ??
        trainee?['full_name_ar'] ??
        trainee?['full_name'] ??
        '';
    final phone = user?['phone'] ?? trainee?['phone'] ?? '';

    return WaitlistEntryModel(
      id: map['id'] as String? ?? '',
      cohortId: map['cohort_id'] as String? ?? '',
      traineeId: map['trainee_id'] as String? ?? '',
      status: map['status'] as String? ?? 'waiting',
      joinedAt: _parseDate(map['joined_at']),
      notifiedAt: _parseDate(map['notified_at']),
      expiresAt: _parseDate(map['expires_at']),
      promotedAt: _parseDate(map['promoted_at']),
      traineeName: name.toString(),
      traineeCode: trainee?['trainee_code']?.toString() ?? '',
      traineePhone: phone.toString(),
      traineeUserActive: user?['is_active'] as bool? ?? true,
    );
  }

  bool get isWaiting => status == 'waiting';

  bool get isNotified => status == 'notified';

  bool get isActive => isWaiting || isNotified;

  bool get isOfferExpired {
    final expiry = expiresAt;
    return expiry != null && DateTime.now().isAfter(expiry);
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString())?.toLocal();
  }
}
