class SurveyTemplate {
  final String id;
  final String title;
  final List<Map<String, dynamic>> questions;
  final int triggerAfterSessions;
  final bool isActive;
  final DateTime createdAt;

  const SurveyTemplate({
    required this.id,
    required this.title,
    required this.questions,
    required this.triggerAfterSessions,
    required this.isActive,
    required this.createdAt,
  });

  factory SurveyTemplate.fromMap(Map<String, dynamic> map) {
    return SurveyTemplate(
      id: map['id'] ?? '',
      title: map['title'] ?? '',
      questions: List<Map<String, dynamic>>.from(map['questions'] ?? []),
      triggerAfterSessions:
          (map['trigger_after_sessions'] as num?)?.toInt() ?? 3,
      isActive: map['is_active'] ?? true,
      createdAt: DateTime.tryParse(map['created_at'] ?? '') ?? DateTime.now(),
    );
  }
}

class SurveyDispatch {
  final String id;
  final String enrollmentId;
  final String templateId;
  final String templateTitle;
  final String traineeName;
  final String courseName;
  final String status;
  final DateTime dispatchedAt;
  final Map<String, dynamic>? answers;

  const SurveyDispatch({
    required this.id,
    required this.enrollmentId,
    required this.templateId,
    required this.templateTitle,
    required this.traineeName,
    required this.courseName,
    required this.status,
    required this.dispatchedAt,
    this.answers,
  });

  factory SurveyDispatch.fromMap(Map<String, dynamic> map) {
    final enrollment = map['enrollments'] as Map<String, dynamic>? ?? {};
    final trainee = enrollment['trainees'] as Map<String, dynamic>? ?? {};
    final user = trainee['users'] as Map<String, dynamic>? ?? {};
    final cohort = enrollment['cohorts'] as Map<String, dynamic>? ?? {};
    final course = cohort['courses'] as Map<String, dynamic>? ?? {};
    final template = map['survey_templates'] as Map<String, dynamic>? ?? {};
    final response = map['survey_responses'] as Map<String, dynamic>?;

    return SurveyDispatch(
      id: map['id'] ?? '',
      enrollmentId: map['enrollment_id'] ?? '',
      templateId: map['template_id'] ?? '',
      templateTitle: template['title'] ?? '',
      traineeName: user['full_name'] ?? '',
      courseName: course['name'] ?? '',
      status: map['status'] ?? 'pending',
      dispatchedAt:
          DateTime.tryParse(map['dispatched_at'] ?? '') ?? DateTime.now(),
      answers: response?['answers'] as Map<String, dynamic>?,
    );
  }
}
