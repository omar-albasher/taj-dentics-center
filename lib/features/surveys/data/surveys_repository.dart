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

  /// يرسل استبياناً معيناً لكل المتدربين المسجَّلين حالياً.
  /// يستخدم at_session_count = 0 كمؤشر خاص بالإرسال اليدوي المباشر
  /// (مختلف عن العتبات التلقائية 3, 6, 9... التي يولّدها trigger الحضور).
  ///
  /// ملاحظة تصميمية: بما أن UNIQUE(enrollment_id, at_session_count)
  /// لا يشمل template_id، فإن إرسال استبيان يدوي ثانٍ لنفس المتدرب
  /// سيُتجاهَل بصمت طالما لم يُسحَب الاستبيان اليدوي الأول بعد —
  /// وهذا يتوافق مع تصميم النظام الحالي الذي يعتمد قالباً واحداً
  /// نشطاً (is_active) في كل وقت.
  Future<int> sendSurveyToAll(String templateId) async {
    final enrollments = await _client.from('enrollments').select('id');

    final enrollmentIds =
        (enrollments as List).map((e) => e['id'] as String).toList();

    if (enrollmentIds.isEmpty) return 0;

    final rows = enrollmentIds
        .map((id) => {
              'enrollment_id': id,
              'template_id': templateId,
              'at_session_count': 0,
            })
        .toList();

    await _client.from('survey_dispatches').upsert(
          rows,
          onConflict: 'enrollment_id,at_session_count',
          ignoreDuplicates: true,
        );

    return enrollmentIds.length;
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
