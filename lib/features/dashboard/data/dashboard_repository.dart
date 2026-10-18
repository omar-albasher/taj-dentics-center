import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DashboardRepository {
  final _client = Supabase.instance.client;

  Future<Map<String, dynamic>> getKpis() async {
    final response = await _client.from('dashboard_kpis').select().single();
    return Map<String, dynamic>.from(response);
  }

  Future<List<Map<String, dynamic>>> getMonthlyRevenue() async {
    final response = await _client.from('profit_loss_report').select();
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> getOverduePayments() async {
    final response = await _client
        .from('overdue_payments')
        .select()
        .order('balance_due', ascending: false)
        .limit(5);
    return List<Map<String, dynamic>>.from(response);
  }
}

final dashboardRepositoryProvider = Provider((_) => DashboardRepository());

final kpisProvider = FutureProvider<Map<String, dynamic>>((ref) {
  return ref.watch(dashboardRepositoryProvider).getKpis();
});

final overdueProvider = FutureProvider<List<Map<String, dynamic>>>((ref) {
  return ref.watch(dashboardRepositoryProvider).getOverduePayments();
});
