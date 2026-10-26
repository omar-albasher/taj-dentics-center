class CohortSeatStatus {
  final String cohortId;
  final String courseId;
  final String cohortName;
  final String courseName;
  final DateTime? cohortStartsAt;
  final double coursePrice;
  final int courseTotalSessions;
  final int? capacity;
  final int enrolledCount;
  final int waitlistCount;
  final int? availableSeats;
  final bool isFull;

  const CohortSeatStatus({
    required this.cohortId,
    required this.courseId,
    required this.cohortName,
    required this.courseName,
    this.cohortStartsAt,
    required this.coursePrice,
    required this.courseTotalSessions,
    this.capacity,
    required this.enrolledCount,
    required this.waitlistCount,
    this.availableSeats,
    required this.isFull,
  });

  factory CohortSeatStatus.fromMap(Map<String, dynamic> map) {
    return CohortSeatStatus(
      cohortId: map['cohort_id'] as String? ?? '',
      courseId: map['course_id'] as String? ?? '',
      cohortName: map['cohort_name'] as String? ?? '',
      courseName: map['course_name'] as String? ?? '',
      cohortStartsAt: _parseDate(map['cohort_starts_at']),
      coursePrice: (map['course_price'] as num?)?.toDouble() ?? 0,
      courseTotalSessions:
          (map['course_total_sessions'] as num?)?.toInt() ?? 0,
      capacity: (map['capacity'] as num?)?.toInt(),
      enrolledCount: (map['enrolled_count'] as num?)?.toInt() ?? 0,
      waitlistCount: (map['waitlist_count'] as num?)?.toInt() ?? 0,
      availableSeats: (map['available_seats'] as num?)?.toInt(),
      isFull: map['is_full'] as bool? ?? false,
    );
  }

  bool get isUnlimited => capacity == null;

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString())?.toLocal();
  }
}
