class CohortModel {
  final String id;
  final String courseId;
  final String courseName;
  final String trainerId;
  final String name;
  final DateTime? startsAt;
  final int? capacity;
  final bool isActive;

  const CohortModel({
    required this.id,
    required this.courseId,
    required this.courseName,
    required this.trainerId,
    required this.name,
    this.startsAt,
    this.capacity,
    required this.isActive,
  });

  factory CohortModel.fromMap(Map<String, dynamic> map) {
    return CohortModel(
      id: map['id'] ?? '',
      courseId: map['course_id'] ?? '',
      courseName: map['courses']?['name'] ?? '',
      trainerId: map['trainer_id'] ?? '',
      name: map['name'] ?? '',
      startsAt:
          map['starts_at'] != null ? DateTime.tryParse(map['starts_at'])?.toLocal() : null,
      capacity: (map['capacity'] as num?)?.toInt(),
      isActive: map['is_active'] ?? true,
    );
  }

  bool get hasLimitedCapacity => capacity != null;
}
