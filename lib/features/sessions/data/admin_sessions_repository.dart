import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/session_model.dart';

class AdminSessionsRepository {
  final _client = Supabase.instance.client;

  Future<List<AdminSessionModel>> getSessions() async {
    final response = await _client.from('sessions').select('''
          *,
          cohorts!sessions_cohort_id_fkey(
            name,
            courses!cohorts_course_id_fkey(name)
          )
        ''').order('scheduled_at', ascending: false);
    return (response as List).map((e) => AdminSessionModel.fromMap(e)).toList();
  }

  Future<void> createSession({
    required String cohortId,
    required int sessionNumber,
    required DateTime scheduledAt,
    bool isExtra = false,
    String? title,
    String? description,
    int durationMinutes = 120,
  }) async {
    // Atomic server-side insert: validates staff role, cohort, numbering and
    // duration before touching RLS-protected sessions (reception has SELECT only).
    await _client.rpc('create_session', params: {
      'p_cohort_id': cohortId,
      'p_session_number': sessionNumber,
      'p_scheduled_at': scheduledAt.toUtc().toIso8601String(),
      'p_duration_minutes': durationMinutes,
      'p_is_extra': isExtra,
      'p_title': (title != null && title.trim().isNotEmpty) ? title.trim() : null,
      'p_description':
          (description != null && description.trim().isNotEmpty) ? description.trim() : null,
    });
  }

  Future<void> openSession(String sessionId) async {
    // Atomic server-side open: generates UUID qr_token, marks open, and
    // records opener; callable by admin and reception.
    await _client.rpc('open_session', params: {'p_session_id': sessionId});
  }

  Future<void> closeSession(String sessionId) async {
    // Atomic server-side close: refuses non-open sessions instead of silently
    // succeeding on zero updated rows; qr_token is preserved for sync grace.
    await _client.rpc('close_session', params: {'p_session_id': sessionId});
  }

  Future<Map<String, dynamic>> bulkScheduleSessions({
    required String cohortId,
    required DateTime startDate,
    required String startTime,
    required List<int> daysOfWeek,
    required int sessionCount,
    int durationMinutes = 120,
  }) async {
    final response = await _client.rpc('bulk_schedule_sessions', params: {
      'p_cohort_id': cohortId,
      'p_start_date': startDate.toIso8601String().split('T')[0],
      'p_start_time': startTime,
      'p_days_of_week': daysOfWeek,
      'p_session_count': sessionCount,
      'p_duration_minutes': durationMinutes,
    });
    return Map<String, dynamic>.from(response);
  }

  Future<Map<String, dynamic>?> getLatestCronLog() async {
    final response = await _client
        .from('cron_job_log')
        .select()
        .order('executed_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return response;
  }

  Future<List<Map<String, dynamic>>> getSessionAttendance(
      String sessionId) async {
    final response = await _client
        .rpc('get_session_attendance', params: {'p_session_id': sessionId});
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> getCohortTrainees(
      String cohortId) async {
    final response = await _client.from('enrollments').select('''
          id,
          status,
          trainees!enrollments_trainee_id_fkey(
            id,
            trainee_code,
            whatsapp_number,
            users!trainees_user_id_fkey(
              full_name,
              phone
            )
          )
        ''').eq('cohort_id', cohortId);
    return List<Map<String, dynamic>>.from(response);
  }
}

final adminSessionsRepositoryProvider =
    Provider((_) => AdminSessionsRepository());

final adminSessionsProvider = FutureProvider<List<AdminSessionModel>>((ref) {
  return ref.watch(adminSessionsRepositoryProvider).getSessions();
});

final latestCronLogProvider = FutureProvider<Map<String, dynamic>?>((ref) {
  return ref.watch(adminSessionsRepositoryProvider).getLatestCronLog();
});

final sessionAttendanceProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, sessionId) {
  return ref
      .watch(adminSessionsRepositoryProvider)
      .getSessionAttendance(sessionId);
});

final cohortTraineesProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, cohortId) {
  return ref
      .watch(adminSessionsRepositoryProvider)
      .getCohortTrainees(cohortId);
});
