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

  // Pre-aggregated SQL view for fast course revenue
  Future<List<Map<String, dynamic>>> getCourseRevenueReport() async {
    final response = await _client
        .from('course_revenue_sql_summary')
        .select()
        .order('total_paid', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> getAttendanceReport() async {
    final response = await _client
        .from('trainee_academic_progress')
        .select()
        .order('attendance_percentage', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  // ─── New Phase 4.5 Reports ───
  Future<List<Map<String, dynamic>>> getRevenueByMethod() async {
    final response = await _client
        .from('revenue_by_method_report')
        .select()
        .order('total_amount', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> getDiscountsReport() async {
    final response = await _client
        .from('discounts_report')
        .select()
        .order('total_discounts', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> getDebtAgingReport() async {
    final response = await _client
        .from('debt_aging_report')
        .select()
        .order('total_overdue_balance', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> getExpensesByCategory() async {
    final response = await _client
        .from('expenses_by_category_report')
        .select()
        .order('total_spent', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> getCashVsAccrual() async {
    final response = await _client.from('cash_vs_accrual_kpis').select();
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

final revenueByMethodProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) {
  return ref.watch(reportsRepositoryProvider).getRevenueByMethod();
});

final discountsReportProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) {
  return ref.watch(reportsRepositoryProvider).getDiscountsReport();
});

final debtAgingReportProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) {
  return ref.watch(reportsRepositoryProvider).getDebtAgingReport();
});

final expensesByCategoryProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) {
  return ref.watch(reportsRepositoryProvider).getExpensesByCategory();
});

final cashVsAccrualProvider = FutureProvider<List<Map<String, dynamic>>>((ref) {
  return ref.watch(reportsRepositoryProvider).getCashVsAccrual();
});
