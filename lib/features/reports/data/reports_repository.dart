import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/financial_statement_models.dart';

class ReportsRepository {
  final _client = Supabase.instance.client;

  // ─── Phase C4 Financial Statements (v3 RPCs) ───
  Future<ProfitLossStatement> getProfitLoss(FinancialStatementPeriod period) async {
    final response = await _client.rpc(
      'get_profit_loss',
      params: {
        'p_from': period.fromIso,
        'p_to': period.toIso,
      },
    );
    final rows = List<Map<String, dynamic>>.from(response as List);
    return ProfitLossStatement.fromRows(rows);
  }

  Future<List<ExpenseBreakdownItem>> getExpenseBreakdown(FinancialStatementPeriod period) async {
    final response = await _client.rpc(
      'get_expense_breakdown',
      params: {
        'p_from': period.fromIso,
        'p_to': period.toIso,
      },
    );
    final rows = List<Map<String, dynamic>>.from(response as List);
    return rows.map(ExpenseBreakdownItem.fromMap).toList();
  }

  Future<CashFlowStatement> getCashFlowStatement(FinancialStatementPeriod period) async {
    final response = await _client.rpc(
      'get_cash_flow_statement',
      params: {
        'p_from': period.fromIso,
        'p_to': period.toIso,
      },
    );
    final rows = List<Map<String, dynamic>>.from(response as List);
    return CashFlowStatement.fromRows(rows);
  }

  Future<FinancialIntegrityReport> getFinancialIntegrity() async {
    final response = await _client.rpc('get_financial_integrity');
    final rows = List<Map<String, dynamic>>.from(response as List);
    return FinancialIntegrityReport.fromRows(rows);
  }

  // ─── Legacy / Existing Reports ───
  Future<List<Map<String, dynamic>>> getProfitLossReport() async {
    final response = await _client
        .from('profit_loss_report_v2')
        .select()
        .order('month', ascending: false)
        .order('currency', ascending: true);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> getOverdueReport() async {
    final response = await _client
        .from('overdue_payments')
        .select()
        .order('balance_due', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  // Pre-aggregated SQL view for fast course revenue (v2)
  Future<List<Map<String, dynamic>>> getCourseRevenueReport() async {
    final response = await _client
        .from('course_revenue_sql_summary_v2')
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

  // ─── Phase D4.4 Reports (v2) ───
  Future<List<Map<String, dynamic>>> getRevenueByMethod() async {
    final response = await _client
        .from('revenue_by_method_report_v2')
        .select()
        .order('gross_collected', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> getDiscountsReport() async {
    final response = await _client
        .from('discounts_report_v2')
        .select()
        .order('total_discounts', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> getDebtAgingReport() async {
    final response = await _client
        .from('debt_aging_report_v2')
        .select()
        .order('currency', ascending: true);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> getExpensesByCategory() async {
    final response = await _client
        .from('expenses_by_category_report_v2')
        .select()
        .order('total_spent', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> getCashVsAccrual() async {
    final response = await _client.from('cash_vs_accrual_kpis_v2').select();
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

// ─── Phase C4 Providers ───
class FinancialStatementPeriodNotifier extends Notifier<FinancialStatementPeriod> {
  @override
  FinancialStatementPeriod build() {
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    return FinancialStatementPeriod(from: startOfMonth, to: now);
  }

  void setPeriod(FinancialStatementPeriod period) {
    state = period;
  }
}

final financialStatementPeriodProvider =
    NotifierProvider<FinancialStatementPeriodNotifier, FinancialStatementPeriod>(
  FinancialStatementPeriodNotifier.new,
);

final c4ProfitLossProvider = FutureProvider<ProfitLossStatement>((ref) {
  final period = ref.watch(financialStatementPeriodProvider);
  return ref.watch(reportsRepositoryProvider).getProfitLoss(period);
});

final c4ExpenseBreakdownProvider =
    FutureProvider<List<ExpenseBreakdownItem>>((ref) {
  final period = ref.watch(financialStatementPeriodProvider);
  return ref.watch(reportsRepositoryProvider).getExpenseBreakdown(period);
});

final c4CashFlowProvider = FutureProvider<CashFlowStatement>((ref) {
  final period = ref.watch(financialStatementPeriodProvider);
  return ref.watch(reportsRepositoryProvider).getCashFlowStatement(period);
});

final c4FinancialIntegrityProvider =
    FutureProvider<FinancialIntegrityReport>((ref) {
  return ref.watch(reportsRepositoryProvider).getFinancialIntegrity();
});
