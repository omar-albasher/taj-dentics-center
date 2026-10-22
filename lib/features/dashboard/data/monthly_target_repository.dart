import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MonthlyTargetRepository {
  final _client = Supabase.instance.client;

  Future<Map<String, dynamic>> getMonthlyTargetProgress({String? monthKey}) async {
    final response = await _client.rpc(
      'get_monthly_target_progress',
      params: {
        if (monthKey != null && monthKey.isNotEmpty) 'p_month_key': monthKey,
      },
    );
    return Map<String, dynamic>.from(response);
  }

  Future<void> setMonthlyTarget({
    required double targetSyp,
    required double targetUsd,
    String? monthKey,
  }) async {
    await _client.rpc(
      'set_monthly_target',
      params: {
        'p_target_syp': targetSyp,
        'p_target_usd': targetUsd,
        if (monthKey != null && monthKey.isNotEmpty) 'p_month_key': monthKey,
      },
    );
  }
}

final monthlyTargetRepositoryProvider = Provider((_) => MonthlyTargetRepository());

final monthlyTargetProgressProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return ref.watch(monthlyTargetRepositoryProvider).getMonthlyTargetProgress();
});
