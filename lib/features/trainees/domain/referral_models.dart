class ReferralPreview {
  final bool valid;
  final String? referrerTraineeId;
  final String? referrerName;
  final String? error;

  const ReferralPreview({
    required this.valid,
    this.referrerTraineeId,
    this.referrerName,
    this.error,
  });

  factory ReferralPreview.fromMap(Map<String, dynamic> map) {
    return ReferralPreview(
      valid: map['valid'] == true,
      referrerTraineeId: map['referrer_trainee_id'] as String?,
      referrerName: (map['referrer_name'] as String?)?.trim(),
      error: map['error'] as String?,
    );
  }
}

class ReferralCredit {
  final String currency;
  final double amount;
  final int count;

  const ReferralCredit({
    required this.currency,
    required this.amount,
    required this.count,
  });

  factory ReferralCredit.fromMap(Map<String, dynamic> map) {
    return ReferralCredit(
      currency: (map['currency'] as String?)?.trim().toUpperCase() ?? '',
      amount: (map['amount'] as num?)?.toDouble() ?? 0,
      count: (map['count'] as num?)?.toInt() ?? 0,
    );
  }
}

class ReferralEntry {
  final String id;
  final String refereeName;
  final String courseName;
  final double amount;
  final String currency;
  final String status;
  final DateTime? createdAt;
  final DateTime? appliedAt;

  const ReferralEntry({
    required this.id,
    required this.refereeName,
    required this.courseName,
    required this.amount,
    required this.currency,
    required this.status,
    this.createdAt,
    this.appliedAt,
  });

  bool get isAvailable => status == 'available';
  bool get isApplied => status == 'applied';
  bool get isCancelled => status == 'cancelled';

  factory ReferralEntry.fromMap(Map<String, dynamic> map) {
    return ReferralEntry(
      id: map['id'] as String? ?? '',
      refereeName: (map['referee_name'] as String?)?.trim() ?? '',
      courseName: (map['course_name'] as String?)?.trim() ?? '',
      amount: (map['amount'] as num?)?.toDouble() ?? 0,
      currency: (map['currency'] as String?)?.trim().toUpperCase() ?? '',
      status: map['status'] as String? ?? 'available',
      createdAt:
          DateTime.tryParse(map['created_at'] as String? ?? '')?.toLocal(),
      appliedAt:
          DateTime.tryParse(map['applied_at'] as String? ?? '')?.toLocal(),
    );
  }
}

class ReferralSummary {
  final String? traineeId;
  final String? traineeName;
  final String referralCode;
  final List<ReferralCredit> availableCredits;
  final List<ReferralEntry> referrals;

  const ReferralSummary({
    this.traineeId,
    this.traineeName,
    required this.referralCode,
    required this.availableCredits,
    required this.referrals,
  });

  double totalAvailableFor(String currency) {
    final target = currency.trim().toUpperCase();
    return availableCredits
        .where((c) => c.currency == target)
        .fold(0, (sum, c) => sum + c.amount);
  }

  bool get hasAvailableCredits => availableCredits.any((c) => c.amount > 0);

  factory ReferralSummary.fromMap(Map<String, dynamic> map) {
    final credits = (map['available_credits'] as List?) ?? const [];
    final referrals = (map['referrals'] as List?) ?? const [];

    return ReferralSummary(
      traineeId: map['trainee_id'] as String?,
      traineeName: (map['trainee_name'] as String?)?.trim(),
      referralCode:
          (map['referral_code'] as String?)?.trim().toUpperCase() ?? '',
      availableCredits: credits
          .map((e) =>
              ReferralCredit.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(),
      referrals: referrals
          .map(
              (e) => ReferralEntry.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }
}
