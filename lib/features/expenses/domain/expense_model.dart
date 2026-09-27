class ExpenseModel {
  final String id;
  final String category;
  final double amount;
  final String currency;
  final String? description;
  final DateTime expenseDate;
  final DateTime createdAt;

  const ExpenseModel({
    required this.id,
    required this.category,
    required this.amount,
    required this.currency,
    this.description,
    required this.expenseDate,
    required this.createdAt,
  });

  factory ExpenseModel.fromMap(Map<String, dynamic> map) {
    return ExpenseModel(
      id: map['id'] ?? '',
      category: map['category'] ?? '',
      amount: (map['amount'] as num?)?.toDouble() ?? 0,
      currency: map['currency'] ?? 'SYP',
      description: map['description'],
      expenseDate:
          DateTime.tryParse(map['expense_date'] ?? '') ?? DateTime.now(),
      createdAt: DateTime.tryParse(map['created_at'] ?? '') ?? DateTime.now(),
    );
  }

  String get categoryAr {
    switch (category) {
      case 'rent':
        return 'إيجار';
      case 'utilities':
        return 'فواتير';
      case 'salary':
        return 'رواتب';
      case 'supplies':
        return 'مستلزمات';
      default:
        return 'أخرى';
    }
  }
}
