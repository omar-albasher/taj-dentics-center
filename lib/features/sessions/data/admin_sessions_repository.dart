import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/session_model.dart';

class AdminSessionsRepository {
  final _client = Supabase.instance.client;
  final _random = Random.secure();

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
  }) async {
    await _client.from('sessions').insert({
      'cohort_id': cohortId,
      'session_number': sessionNumber,
      'scheduled_at': scheduledAt.toIso8601String(),
    });
  }

  Future<void> openSession(String sessionId) async {
    final qrToken = _generateUuid();
    await _client
        .from('sessions')
        .update({
          'status': 'open',
          'qr_token': qrToken,
          'opened_at': DateTime.now().toIso8601String(),
          'opened_by': _client.auth.currentUser!.id,
        })
        .eq('id', sessionId)
        .eq('status', 'scheduled');
  }

  Future<void> closeSession(String sessionId) async {
    await _client
        .from('sessions')
        .update({
          'status': 'closed',
          'qr_token': null,
          'closed_at': DateTime.now().toIso8601String(),
        })
        .eq('id', sessionId)
        .eq('status', 'open');
  }

  Future<List<Map<String, dynamic>>> getSessionAttendance(
      String sessionId) async {
    final response = await _client
        .rpc('get_session_attendance', params: {'p_session_id': sessionId});
    return List<Map<String, dynamic>>.from(response);
  }

  String _generateUuid() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}

final adminSessionsRepositoryProvider =
    Provider((_) => AdminSessionsRepository());

final adminSessionsProvider = FutureProvider<List<AdminSessionModel>>((ref) {
  return ref.watch(adminSessionsRepositoryProvider).getSessions();
});

final sessionAttendanceProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, sessionId) {
  return ref
      .watch(adminSessionsRepositoryProvider)
      .getSessionAttendance(sessionId);
});
