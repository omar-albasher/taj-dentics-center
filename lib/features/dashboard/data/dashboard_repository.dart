import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DashboardRepository {
  final _client = Supabase.instance.client;

  Future<Map<String, dynamic>> getKpis() async {
    final response = await _client.from('dashboard_kpis').select().single();

    final totals = await Future.wait([
      _client.from('payments').select('amount').eq('currency', 'SYP'),
      _client.from('payments').select('amount').eq('currency', 'USD'),
      _client.from('expenses').select('amount').eq('currency', 'SYP'),
      _client.from('expenses').select('amount').eq('currency', 'USD'),
      _client.from('enrollment_financial_summary').select('balance, currency'),
    ]);

    final totalPaidSYP = _sumField(totals[0], 'amount');
    final totalPaidUSD = _sumField(totals[1], 'amount');
    final totalExpSYP = _sumField(totals[2], 'amount');
    final totalExpUSD = _sumField(totals[3], 'amount');
    final totalBalanceSYP = _sumField(totals[4], 'balance', currency: 'SYP');
    final totalBalanceUSD = _sumField(totals[4], 'balance', currency: 'USD');

    return {
      ...Map<String, dynamic>.from(response),
      'total_paid_syp': totalPaidSYP,
      'total_paid_usd': totalPaidUSD,
      'total_exp_syp': totalExpSYP,
      'total_exp_usd': totalExpUSD,
      'net_profit_syp': totalPaidSYP - totalExpSYP,
      'net_profit_usd': totalPaidUSD - totalExpUSD,
      'total_balance_syp': totalBalanceSYP,
      'total_balance_usd': totalBalanceUSD,
    };
  }

  double _sumField(
    Iterable<dynamic> rows,
    String field, {
    String? currency,
  }) {
    return rows.fold(0.0, (sum, row) {
      if (row is! Map<String, dynamic>) return sum;
      if (currency != null && row['currency'] != currency) return sum;
      return sum + ((row[field] as num?)?.toDouble() ?? 0);
    });
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
