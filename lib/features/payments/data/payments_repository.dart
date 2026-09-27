import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PaymentsRepository {
  final _client = Supabase.instance.client;

  Future<List<Map<String, dynamic>>> getEnrollmentsByTrainee(
      String traineeId) async {
    final response = await _client
        .from('enrollment_financial_summary')
        .select()
        .eq('trainee_id', traineeId);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> getAllEnrollments() async {
    final response = await _client
        .from('enrollment_financial_summary')
        .select()
        .neq('payment_status', 'complete')
        .order('balance', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> getRecentPayments() async {
    final response = await _client.from('payments').select('''
        id, amount, currency, method, paid_at, notes, receipt_number,
        enrollments!payments_enrollment_id_fkey(
          id,
          trainees!enrollments_trainee_id_fkey(
            users!trainees_user_id_fkey(full_name)
          ),
          cohorts!enrollments_cohort_id_fkey(
            courses!cohorts_course_id_fkey(name)
          )
        )
      ''').order('paid_at', ascending: false).limit(50);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> addPayment({
    required String enrollmentId,
    required double amount,
    required String currency,
    required String method,
    String? notes,
    String? receiptNumber,
    DateTime? paidAt,
  }) async {
    await _client.from('payments').insert({
      'enrollment_id': enrollmentId,
      'amount': amount,
      'currency': currency,
      'method': method,
      'notes': notes,
      'receipt_number': receiptNumber,
      'performed_by': _client.auth.currentUser!.id,
      'paid_at': (paidAt ?? DateTime.now()).toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getOverduePayments() async {
    final response = await _client
        .from('overdue_payments')
        .select()
        .order('balance_due', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }
}

final paymentsRepositoryProvider = Provider((_) => PaymentsRepository());

final allEnrollmentsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) {
  return ref.watch(paymentsRepositoryProvider).getAllEnrollments();
});

final recentPaymentsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) {
  return ref.watch(paymentsRepositoryProvider).getRecentPayments();
});

final overduePaymentsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) {
  return ref.watch(paymentsRepositoryProvider).getOverduePayments();
});
