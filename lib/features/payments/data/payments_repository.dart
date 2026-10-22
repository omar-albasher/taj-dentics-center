import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PaymentsRepository {
  final _client = Supabase.instance.client;

  Future<Map<String, dynamic>?> getEnrollmentFinancialSummary(
      String enrollmentId) async {
    final response = await _client
        .from('enrollment_financial_summary')
        .select()
        .eq('enrollment_id', enrollmentId)
        .maybeSingle();
    return response != null ? Map<String, dynamic>.from(response) : null;
  }

  Future<List<Map<String, dynamic>>> getEnrollmentsByTrainee(
      String traineeId) async {
    final response = await _client
        .from('enrollment_financial_summary')
        .select()
        .eq('trainee_id', traineeId);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> getAllEnrollments({
    String? search,
    String? status,
  }) async {
    var query = _client.from('enrollment_financial_summary').select();

    if (status != null && status.isNotEmpty && status != 'all') {
      query = query.eq('payment_status', status);
    } else {
      query = query.neq('payment_status', 'complete');
    }

    if (search != null && search.trim().isNotEmpty) {
      final s = search.trim();
      query = query.or('trainee_name.ilike.%$s%,course_name.ilike.%$s%');
    }

    final response = await query.order('balance', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> getRecentPayments({
    String? search,
    String? method,
  }) async {
    var query = _client.from('payments').select('''
        id, amount, currency, method, paid_at, notes, receipt_number, external_reference,
        enrollments!payments_enrollment_id_fkey(
          id,
          trainees!enrollments_trainee_id_fkey(
            trainee_code,
            users!trainees_user_id_fkey(full_name)
          ),
          cohorts!enrollments_cohort_id_fkey(
            courses!cohorts_course_id_fkey(name)
          )
        )
      ''');

    if (method != null && method.isNotEmpty && method != 'all') {
      query = query.eq('method', method);
    }

    final limit = (search != null && search.trim().isNotEmpty) ? 1000 : 100;
    final response = await query.order('paid_at', ascending: false).limit(limit);
    final list = List<Map<String, dynamic>>.from(response);

    if (search != null && search.trim().isNotEmpty) {
      final s = search.trim().toLowerCase();
      return list.where((p) {
        final enrollment = p['enrollments'] as Map<String, dynamic>? ?? {};
        final trainee = enrollment['trainees'] as Map<String, dynamic>? ?? {};
        final user = trainee['users'] as Map<String, dynamic>? ?? {};
        final cohort = enrollment['cohorts'] as Map<String, dynamic>? ?? {};
        final course = cohort['courses'] as Map<String, dynamic>? ?? {};

        final name = (user['full_name'] ?? '').toString().toLowerCase();
        final code = (trainee['trainee_code'] ?? '').toString().toLowerCase();
        final cName = (course['name'] ?? '').toString().toLowerCase();
        final receipt = (p['receipt_number'] ?? '').toString().toLowerCase();
        final extRef = (p['external_reference'] ?? '').toString().toLowerCase();

        return name.contains(s) ||
            code.contains(s) ||
            cName.contains(s) ||
            receipt.contains(s) ||
            extRef.contains(s);
      }).toList();
    }

    return list;
  }

  Future<void> addPayment({
    required String enrollmentId,
    required double amount,
    required String currency,
    required String method,
    String? notes,
    String? receiptNumber,
    String? externalReference,
    DateTime? paidAt,
  }) async {
    await _client.from('payments').insert({
      'enrollment_id': enrollmentId,
      'amount': amount,
      'currency': currency,
      'method': method,
      'notes': notes,
      'receipt_number': receiptNumber,
      'external_reference': externalReference,
      'performed_by': _client.auth.currentUser!.id,
      'paid_at': (paidAt ?? DateTime.now()).toUtc().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getOverduePayments({
    String? search,
  }) async {
    var query = _client.from('overdue_payments').select();

    if (search != null && search.trim().isNotEmpty) {
      final s = search.trim();
      query = query.or('trainee_name.ilike.%$s%,trainee_code.ilike.%$s%,course_name.ilike.%$s%');
    }

    final response = await query.order('balance_due', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }
}

final paymentsRepositoryProvider = Provider((_) => PaymentsRepository());

class PaymentFilterParams {
  final String? search;
  final String? method;
  final String? status;

  const PaymentFilterParams({this.search, this.method, this.status});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PaymentFilterParams &&
          runtimeType == other.runtimeType &&
          search == other.search &&
          method == other.method &&
          status == other.status;

  @override
  int get hashCode => Object.hash(search, method, status);
}

final allEnrollmentsProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, PaymentFilterParams>((ref, params) {
  return ref.watch(paymentsRepositoryProvider).getAllEnrollments(
        search: params.search,
        status: params.status,
      );
});

final recentPaymentsProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, PaymentFilterParams>((ref, params) {
  return ref.watch(paymentsRepositoryProvider).getRecentPayments(
        search: params.search,
        method: params.method,
      );
});

final overduePaymentsProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String?>((ref, search) {
  return ref.watch(paymentsRepositoryProvider).getOverduePayments(search: search);
});
