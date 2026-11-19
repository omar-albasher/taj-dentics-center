import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/expense_model.dart';

class ExpensesRepository {
  final _client = Supabase.instance.client;

  Future<List<ExpenseModel>> getExpenses() async {
    final response = await _client
        .from('expenses')
        .select()
        .order('expense_date', ascending: false);
    return (response as List).map((e) => ExpenseModel.fromMap(e)).toList();
  }

  Future<void> addExpense({
    required String category,
    required double amount,
    required String currency,
    required DateTime expenseDate,
    String? description,
    String? accountId,
  }) async {
    final payload = <String, dynamic>{
      'category': category,
      'amount': amount,
      'currency': currency,
      'expense_date': expenseDate.toIso8601String().split('T')[0],
      'description': description,
      'performed_by': _client.auth.currentUser!.id,
    };
    if (accountId != null && accountId.isNotEmpty) {
      payload['account_id'] = accountId;
    }
    await _client.from('expenses').insert(payload);
  }

  Future<void> updateExpense({
    required String id,
    required String category,
    required double amount,
    required String currency,
    required DateTime expenseDate,
    String? description,
    String? accountId,
  }) async {
    await _client.from('expenses').update({
      'category': category,
      'amount': amount,
      'currency': currency,
      'expense_date': expenseDate.toIso8601String().split('T')[0],
      'description': description,
      // يُرسَل دائماً (حتى null) حتى يستطيع المدير إرجاع المصروف
      // إلى الربط التلقائي بدل إبقاء حساب قديم مخفي.
      'account_id': accountId,
    }).eq('id', id);
  }

  Future<void> deleteExpense(String id) async {
    await _client.from('expenses').delete().eq('id', id);
  }
}

final expensesRepositoryProvider = Provider((_) => ExpensesRepository());

final expensesProvider = FutureProvider<List<ExpenseModel>>((ref) {
  return ref.watch(expensesRepositoryProvider).getExpenses();
});
