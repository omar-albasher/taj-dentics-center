class CourseModel {
  final String id;
  final String name;
  final int totalSessions;
  final double price;
  final String? description;
  final bool isActive;
  final DateTime createdAt;

  const CourseModel({
    required this.id,
    required this.name,
    required this.totalSessions,
    required this.price,
    this.description,
    required this.isActive,
    required this.createdAt,
  });

  factory CourseModel.fromMap(Map<String, dynamic> map) {
    return CourseModel(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      totalSessions: (map['total_sessions'] as num?)?.toInt() ?? 0,
      price: (map['price'] as num?)?.toDouble() ?? 0,
      description: map['description'],
      isActive: map['is_active'] ?? true,
      createdAt: DateTime.tryParse(map['created_at'] ?? '') ?? DateTime.now(),
    );
  }
}
