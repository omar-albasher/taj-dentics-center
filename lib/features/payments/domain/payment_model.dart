class PaymentModel {
  final String id;
  final String enrollmentId;
  final String traineeName;
  final String courseName;
  final double amount;
  final String currency;
  final String method;
  final DateTime paidAt;
  final String? notes;

  const PaymentModel({
    required this.id,
    required this.enrollmentId,
    required this.traineeName,
    required this.courseName,
    required this.amount,
    required this.currency,
    required this.method,
    required this.paidAt,
    this.notes,
  });

  factory PaymentModel.fromMap(Map<String, dynamic> map) {
    return PaymentModel(
      id: map['id'] ?? '',
      enrollmentId: map['enrollment_id'] ?? '',
      traineeName: map['trainee_name'] ?? '',
      courseName: map['course_name'] ?? '',
      amount: (map['amount'] as num?)?.toDouble() ?? 0,
      currency: map['currency'] ?? 'SYP',
      method: map['method'] ?? 'cash',
      paidAt: DateTime.tryParse(map['paid_at'] ?? '') ?? DateTime.now(),
      notes: map['notes'],
    );
  }
}
