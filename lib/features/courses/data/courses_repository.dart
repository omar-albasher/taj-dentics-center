import 'package:admin_dashboard/features/courses/domain/cohort_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/course_model.dart';

class CoursesRepository {
  final _client = Supabase.instance.client;

  Future<List<CourseModel>> getCourses() async {
    final response = await _client
        .from('courses')
        .select()
        .order('created_at', ascending: false);
    return (response as List).map((e) => CourseModel.fromMap(e)).toList();
  }

  Future<void> addCourse({
    required String name,
    required int totalSessions,
    required double price,
    String? description,
  }) async {
    await _client.from('courses').insert({
      'name': name,
      'total_sessions': totalSessions,
      'price': price,
      'description': description,
      'created_by': _client.auth.currentUser!.id,
    });
  }

  Future<List<CohortModel>> getCohortsByCourse(String courseId) async {
    final response = await _client
        .from('cohorts')
        .select('*, courses(name)')
        .eq('course_id', courseId)
        .order('created_at', ascending: false);
    return (response as List).map((e) => CohortModel.fromMap(e)).toList();
  }

  Future<List<Map<String, dynamic>>> getAllActiveCohorts() async {
    final response = await _client
        .from('cohorts')
        .select(
            'id, name, course_id, courses!cohorts_course_id_fkey(id, name, price)')
        .eq('is_active', true)
        .order('created_at', ascending: false);

    return (response as List).map((c) {
      final course = c['courses'] as Map<String, dynamic>? ?? {};
      return {
        'id': c['id'],
        'name': c['name'],
        'course_id': c['course_id'],
        'course_name': course['name'] ?? '',
        'price': (course['price'] as num?)?.toDouble() ?? 0,
      };
    }).toList();
  }

  Future<void> addCohort({
    required String courseId,
    required String name,
    required String trainerId,
    DateTime? startsAt,
  }) async {
    await _client.from('cohorts').insert({
      'course_id': courseId,
      'name': name,
      'trainer_id': trainerId,
      'starts_at': startsAt?.toIso8601String(),
      'created_by': _client.auth.currentUser!.id,
    });
  }

  Future<void> enrollTrainee({
    required String traineeId,
    required String cohortId,
    required double totalDue,
    required double discountAmount,
    required String currency,
  }) async {
    await _client.from('enrollments').insert({
      'trainee_id': traineeId,
      'cohort_id': cohortId,
      'total_due': totalDue,
      'discount_amount': discountAmount,
      'currency': currency,
      'created_by': _client.auth.currentUser!.id,
    });
  }

  Future<List<Map<String, dynamic>>> getCohortEnrollments(
      String cohortId) async {
    final response = await _client
        .from('enrollment_financial_summary')
        .select()
        .eq('cohort_id', cohortId);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> updateCourse({
    required String id,
    required String name,
    required int totalSessions,
    required double price,
    String? description,
    required bool isActive,
  }) async {
    await _client.from('courses').update({
      'name': name,
      'total_sessions': totalSessions,
      'price': price,
      'description': description,
      'is_active': isActive,
    }).eq('id', id);
  }
}

final coursesRepositoryProvider = Provider((_) => CoursesRepository());

final coursesProvider = FutureProvider<List<CourseModel>>((ref) {
  return ref.watch(coursesRepositoryProvider).getCourses();
});

final allActiveCohortsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) {
  return ref.watch(coursesRepositoryProvider).getAllActiveCohorts();
});

final cohortsByCourseProvider =
    FutureProvider.family<List<CohortModel>, String>((ref, courseId) {
  return ref.watch(coursesRepositoryProvider).getCohortsByCourse(courseId);
});
