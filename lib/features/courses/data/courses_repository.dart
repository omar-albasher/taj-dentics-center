import 'package:admin_dashboard/features/courses/domain/cohort_model.dart';
import 'package:admin_dashboard/features/courses/domain/cohort_seat_status.dart';
import 'package:admin_dashboard/features/courses/domain/waitlist_entry_model.dart';
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
    int? capacity,
  }) async {
    await _client.from('cohorts').insert({
      'course_id': courseId,
      'name': name,
      'trainer_id': trainerId,
      'starts_at': startsAt?.toUtc().toIso8601String(),
      if (capacity != null) 'capacity': capacity,
      'created_by': _client.auth.currentUser!.id,
    });
  }

  Future<void> updateCohortCapacity({
    required String cohortId,
    required int? capacity,
  }) async {
    await _client
        .from('cohorts')
        .update({'capacity': capacity}).eq('id', cohortId);
  }

  Future<List<CohortSeatStatus>> getCohortSeatStatus({String? courseId}) async {
    final response = await _client.rpc(
      'get_cohorts_seat_status',
      params: {'p_course_id': courseId},
    );

    return (response as List)
        .map((e) =>
            CohortSeatStatus.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<List<WaitlistEntryModel>> getActiveWaitlist(String cohortId) async {
    final response = await _client
        .from('course_waitlist')
        .select('''
*,
trainees!course_waitlist_trainee_id_fkey(
  id,
  trainee_code,
  full_name,
  full_name_ar,
  full_name_en,
  phone,
  users!trainees_user_id_fkey(
    id,
    full_name,
    phone,
    is_active
  )
)
''')
        .eq('cohort_id', cohortId)
        .inFilter('status', ['waiting', 'notified'])
        .order('joined_at', ascending: true);

    return (response as List)
        .map((e) =>
            WaitlistEntryModel.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<Map<String, dynamic>> joinWaitlist({
    required String cohortId,
    String? traineeId,
  }) async {
    final response = await _client.rpc(
      'join_course_waitlist',
      params: {
        'p_cohort_id': cohortId,
        if (traineeId != null) 'p_trainee_id': traineeId,
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> cancelWaitlist(String waitlistId) async {
    final response = await _client.rpc(
      'cancel_course_waitlist',
      params: {'p_waitlist_id': waitlistId},
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> promoteWaitlist({
    required String waitlistId,
    required double totalDue,
    double discountAmount = 0,
    String currency = 'SYP',
    String? referralCode,
    double referralDiscountAmount = 0,
  }) async {
    final hasReferral = referralCode != null && referralCode.trim().isNotEmpty;

    final response = await _client.rpc(
      'promote_waitlist_trainee',
      params: {
        'p_waitlist_id': waitlistId,
        'p_total_due': totalDue,
        'p_discount_amount': discountAmount,
        'p_currency': currency,
        if (hasReferral) ...{
          'p_referral_code': referralCode.trim().toUpperCase(),
          'p_referral_discount_amount': referralDiscountAmount,
        },
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<void> enrollTrainee({
    required String traineeId,
    required String cohortId,
    required double totalDue,
    required double discountAmount,
    required String currency,
    String? referralCode,
    double referralDiscountAmount = 0,
  }) async {
    final hasReferral = referralCode != null && referralCode.trim().isNotEmpty;

    await _client.from('enrollments').insert({
      'trainee_id': traineeId,
      'cohort_id': cohortId,
      'total_due': totalDue,
      'discount_amount': discountAmount,
      'currency': currency,
      'created_by': _client.auth.currentUser!.id,
      if (hasReferral) ...{
        'referral_code': referralCode.trim().toUpperCase(),
        'referral_discount_amount': referralDiscountAmount,
      },
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

  Future<Map<String, dynamic>> shiftCohortSessions({
    required String cohortId,
    required DateTime newStartDate,
  }) async {
    final response = await _client.rpc(
      'shift_cohort_sessions',
      params: {
        'p_cohort_id': cohortId,
        'p_new_start_date': newStartDate.toUtc().toIso8601String(),
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<CourseModel?> getCourseById(String id) async {
    final response =
        await _client.from('courses').select().eq('id', id).maybeSingle();
    if (response == null) return null;
    return CourseModel.fromMap(response);
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

final cohortSeatStatusProvider =
    FutureProvider.family<List<CohortSeatStatus>, String?>((ref, courseId) {
  return ref
      .watch(coursesRepositoryProvider)
      .getCohortSeatStatus(courseId: courseId);
});

final waitlistProvider =
    FutureProvider.family<List<WaitlistEntryModel>, String>((ref, cohortId) {
  return ref.watch(coursesRepositoryProvider).getActiveWaitlist(cohortId);
});

final courseByIdProvider =
    FutureProvider.family<CourseModel?, String>((ref, id) {
  return ref.watch(coursesRepositoryProvider).getCourseById(id);
});
