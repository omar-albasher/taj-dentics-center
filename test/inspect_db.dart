import 'package:supabase/supabase.dart';
import 'package:admin_dashboard/core/constants/app_constants.dart';

void main() async {
  print('Starting authenticated schema inspection...');
  final client = SupabaseClient(
    AppConstants.supabaseUrl,
    AppConstants.supabaseAnonKey,
  );

  final email = 'temp_probe_user@taj.com';
  final password = 'TempPassword123!';

  try {
    print('Attempting to sign in or sign up...');
    try {
      await client.auth.signUp(email: email, password: password);
      print('Signed up successfully!');
    } catch (e) {
      print('Sign up failed or user exists: $e');
    }

    final authRes = await client.auth.signInWithPassword(email: email, password: password);
    print('Signed in successfully! User ID: ${authRes.user?.id}');

    final tables = [
      'courses',
      'sessions',
      'payments',
      'expenses',
      'survey_responses',
      'users',
      'trainees',
      'enrollments'
    ];
    
    for (final table in tables) {
      try {
        final res = await client.from(table).select().limit(5);
        print('\n--- TABLE: $table ---');
        print('Number of rows returned: ${res.length}');
        if (res.isNotEmpty) {
          print('COLUMNS: ${res.first.keys.toList()}');
          print('SAMPLE ROW: ${res.first}');
        } else {
          print('STATUS: (empty or no select permission)');
        }
      } catch (e) {
        print('ERROR for $table: $e');
      }
    }
  } catch (e) {
    print('Global error: $e');
  }
}
