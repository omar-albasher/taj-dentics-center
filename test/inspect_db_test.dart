import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:admin_dashboard/core/constants/app_constants.dart';

void main() {
  const runDbInspection = bool.fromEnvironment('RUN_DB_INSPECTION');

  test('inspect database tables', () async {
    // Create SupabaseClient directly without Supabase.initialize to avoid SharedPreferences dependency
    final client = SupabaseClient(
      AppConstants.supabaseUrl,
      AppConstants.supabaseAnonKey,
    );

    final tables = [
      'courses',
      'sessions',
      'payments',
      'expenses',
      'survey_responses',
      'users',
      'trainees',
      'enrollments',
      'dashboard_kpis',
      'enrollment_financial_summary',
      'profit_loss_report',
      'overdue_payments',
      'trainee_academic_progress'
    ];

    for (final table in tables) {
      try {
        final res = await client.from(table).select().limit(1);
        debugPrint('--- TABLE/VIEW: $table ---');
        if (res.isNotEmpty) {
          debugPrint('COLUMNS: ${res.first.keys.toList()}');
          debugPrint('SAMPLE: ${res.first}');
        } else {
          debugPrint('STATUS: (empty table/view, but exists)');
        }
      } catch (e) {
        debugPrint('ERROR for $table: $e');
      }
    }
  }, skip: runDbInspection ? false : 'Set RUN_DB_INSPECTION=true to run');
}
