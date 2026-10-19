import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/survey_model.dart';

class SurveysRepository {
  final _client = Supabase.instance.client;

  Future<List<SurveyTemplate>> getTemplates() async {
    final response = await _client
        .from('survey_templates')
        .select()
        .order('created_at', ascending: false);
    return (response as List).map((e) => SurveyTemplate.fromMap(e)).toList();
  }

  Future<void> addTemplate({
    required String title,
    required List<Map<String, dynamic>> questions,
    required int triggerAfterSessions,
  }) async {
    await _client.from('survey_templates').insert({
      'title': title,
      'questions': questions,
      'trigger_after_sessions': triggerAfterSessions,
      'created_by': _client.auth.currentUser!.id,
    });
  }

  Future<void> toggleTemplate(String id, bool isActive) async {
    await _client
        .from('survey_templates')
        .update({'is_active': isActive}).eq('id', id);
  }

  Future<List<SurveyDispatch>> getDispatches() async {
    final response = await _client.from('survey_dispatches').select('''
          *,
          survey_templates(title),
          enrollments!survey_dispatches_enrollment_id_fkey(
            trainees!enrollments_trainee_id_fkey(
              users!trainees_user_id_fkey(full_name)
            ),
            cohorts!enrollments_cohort_id_fkey(
              courses!cohorts_course_id_fkey(name)
            )
          ),
          survey_responses(answers)
        ''').order('dispatched_at', ascending: false);
    return (response as List).map((e) => SurveyDispatch.fromMap(e)).toList();
  }

  /// ÙŠØ±Ø³Ù„ Ø§Ø³ØªØ¨ÙŠØ§Ù†Ø§Ù‹ Ù…Ø¹ÙŠÙ†Ø§Ù‹ Ù„ÙƒÙ„ Ø§Ù„Ù…ØªØ¯Ø±Ø¨ÙŠÙ† Ø§Ù„Ù…Ø³Ø¬ÙŽÙ‘Ù„ÙŠÙ† Ø­Ø§Ù„ÙŠØ§Ù‹.
  /// ÙŠØ³ØªØ®Ø¯Ù… at_session_count = 0 ÙƒÙ…Ø¤Ø´Ø± Ø®Ø§Øµ Ø¨Ø§Ù„Ø¥Ø±Ø³Ø§Ù„ Ø§Ù„ÙŠØ¯ÙˆÙŠ Ø§Ù„Ù…Ø¨Ø§Ø´Ø±
  /// (Ù…Ø®ØªÙ„Ù Ø¹Ù† Ø§Ù„Ø¹ØªØ¨Ø§Øª Ø§Ù„ØªÙ„Ù‚Ø§Ø¦ÙŠØ© 3, 6, 9... Ø§Ù„ØªÙŠ ÙŠÙˆÙ„Ù‘Ø¯Ù‡Ø§ trigger Ø§Ù„Ø­Ø¶ÙˆØ±).
  ///
  /// Ù…Ù„Ø§Ø­Ø¸Ø© ØªØµÙ…ÙŠÙ…ÙŠØ©: Ø¨Ù…Ø§ Ø£Ù† UNIQUE(enrollment_id, at_session_count)
  /// Ù„Ø§ ÙŠØ´Ù…Ù„ template_idØŒ ÙØ¥Ù† Ø¥Ø±Ø³Ø§Ù„ Ø§Ø³ØªØ¨ÙŠØ§Ù† ÙŠØ¯ÙˆÙŠ Ø«Ø§Ù†Ù Ù„Ù†ÙØ³ Ø§Ù„Ù…ØªØ¯Ø±Ø¨
  /// Ø³ÙŠÙØªØ¬Ø§Ù‡ÙŽÙ„ Ø¨ØµÙ…Øª Ø·Ø§Ù„Ù…Ø§ Ù„Ù… ÙŠÙØ³Ø­ÙŽØ¨ Ø§Ù„Ø§Ø³ØªØ¨ÙŠØ§Ù† Ø§Ù„ÙŠØ¯ÙˆÙŠ Ø§Ù„Ø£ÙˆÙ„ Ø¨Ø¹Ø¯ â€”
  /// ÙˆÙ‡Ø°Ø§ ÙŠØªÙˆØ§ÙÙ‚ Ù…Ø¹ ØªØµÙ…ÙŠÙ… Ø§Ù„Ù†Ø¸Ø§Ù… Ø§Ù„Ø­Ø§Ù„ÙŠ Ø§Ù„Ø°ÙŠ ÙŠØ¹ØªÙ…Ø¯ Ù‚Ø§Ù„Ø¨Ø§Ù‹ ÙˆØ§Ø­Ø¯Ø§Ù‹
  /// Ù†Ø´Ø·Ø§Ù‹ (is_active) ÙÙŠ ÙƒÙ„ ÙˆÙ‚Øª.
  Future<int> sendSurveyToAll(String templateId) async {
    final response = await _client.rpc(
      'dispatch_survey_to_all',
      params: {'p_template_id': templateId},
    );
    return (response as num?)?.toInt() ?? 0;
  }

  Future<Map<String, dynamic>> getSurveyStats(String templateId) async {
    final response = await _client
        .from('survey_statistics')
        .select()
        .eq('survey_title', templateId)
        .maybeSingle();
    return response ?? {};
  }
}

final surveysRepositoryProvider = Provider((_) => SurveysRepository());

final surveyTemplatesProvider = FutureProvider<List<SurveyTemplate>>((ref) {
  return ref.watch(surveysRepositoryProvider).getTemplates();
});

final surveyDispatchesProvider = FutureProvider<List<SurveyDispatch>>((ref) {
  return ref.watch(surveysRepositoryProvider).getDispatches();
});
