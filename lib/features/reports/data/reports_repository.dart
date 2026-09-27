import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ReportsRepository {
  final _client = Supabase.instance.client;

  Future<List<Map<String, dynamic>>> getProfitLossReport() async {
    final response = await _client
        .from('profit_loss_report')
        .select()
        .order('month', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> getOverdueReport() async {
    final response = await _client
        .from('overdue_payments')
        .select()
        .order('balance_due', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> getCourseRevenueReport() async {
    final response = await _client.from('enrollment_financial_summary').select(
        'course_name, total_due, total_paid, balance, payment_status, currency');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> getAttendanceReport() async {
    final response = await _client
        .from('trainee_academic_progress')
        .select()
        .order('attendance_percentage', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }
}

final reportsRepositoryProvider = Provider((_) => ReportsRepository());

final profitLossProvider = FutureProvider<List<Map<String, dynamic>>>((ref) {
  return ref.watch(reportsRepositoryProvider).getProfitLossReport();
});

final overdueReportProvider = FutureProvider<List<Map<String, dynamic>>>((ref) {
  return ref.watch(reportsRepositoryProvider).getOverdueReport();
});

final courseRevenueProvider = FutureProvider<List<Map<String, dynamic>>>((ref) {
  return ref.watch(reportsRepositoryProvider).getCourseRevenueReport();
});

final attendanceReportProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) {
  return ref.watch(reportsRepositoryProvider).getAttendanceReport();
});
