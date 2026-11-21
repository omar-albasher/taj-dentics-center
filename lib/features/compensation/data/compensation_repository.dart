import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/compensation_models.dart';

class CompensationRepository {
  final SupabaseClient _client;

  CompensationRepository([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  String? get _uid => _client.auth.currentUser?.id;

  List<Map<String, dynamic>> _rows(dynamic response) =>
      List<Map<String, dynamic>>.from(response as List);

  // ---------------------------------------------------------------- trainers

  Future<List<CohortTrainerRate>> getCohortRates() async {
    final response = await _client
        .from('cohort_trainer_rates_v')
        .select()
        .order('starts_at', ascending: false);
    return _rows(response).map(CohortTrainerRate.fromMap).toList();
  }

  Future<List<TrainerAgreement>> getAgreements() async {
    final response = await _client
        .from('trainer_compensation_agreements')
        .select('''
          id, trainer_id, course_id, rate_percent, effective_from,
          effective_to, notes, created_at,
          users!trainer_compensation_agreements_trainer_id_fkey(full_name),
          courses!trainer_compensation_agreements_course_id_fkey(name)
        ''')
        .order('effective_from', ascending: false);
    return _rows(response).map(TrainerAgreement.fromMap).toList();
  }

  Future<void> addAgreement({
    required String trainerId,
    required String courseId,
    required double ratePercent,
    required DateTime effectiveFrom,
    DateTime? effectiveTo,
    String? notes,
  }) async {
    await _client.from('trainer_compensation_agreements').insert({
      'trainer_id': trainerId,
      'course_id': courseId,
      'rate_percent': ratePercent,
      'effective_from': _dateOnly(effectiveFrom),
      'effective_to': effectiveTo == null ? null : _dateOnly(effectiveTo),
      'notes': notes,
      'created_by': _uid,
    });
  }

  Future<void> deleteAgreement(String id) async {
    final used = await _client
        .from('cohort_trainer_rate_snapshots')
        .select('cohort_id')
        .eq('agreement_id', id)
        .limit(1);
    if ((used as List).isNotEmpty) {
      throw Exception(
          'لا يمكن حذف اتفاقية مرتبطة بنسبة مقفلة لدفعة؛ يبقى أثر التدقيق مطلوباً');
    }
    await _client.from('trainer_compensation_agreements').delete().eq('id', id);
  }

  Future<void> lockCohortRate(String cohortId, double ratePercent) async {
    await _client.rpc('lock_cohort_trainer_rate', params: {
      'p_cohort_id': cohortId,
      'p_rate_percent': ratePercent,
    });
  }

  Future<List<TrainerDue>> getTrainerDues(DateTime month) async {
    final response = await _client
        .from('trainer_dues_v')
        .select()
        .eq('period_start', monthKey(month))
        .order('trainer_name')
        .order('currency');
    return _rows(response).map(TrainerDue.fromMap).toList();
  }

  Future<int> generateTrainerDues(String cohortId, DateTime month) async {
    final result = await _client.rpc('generate_trainer_dues', params: {
      'p_cohort_id': cohortId,
      'p_month': monthKey(month),
    });
    return (result as num?)?.toInt() ?? 0;
  }

  Future<String> payTrainerDue(String dueId, String accountId) async {
    final result = await _client.rpc('pay_trainer_due', params: {
      'p_due_id': dueId,
      'p_account_id': accountId,
    });
    return result.toString();
  }

  Future<List<TrainerPayment>> getTrainerPayments({String? dueId}) async {
    var query = _client.from('trainer_payments_v').select();
    if (dueId != null && dueId.isNotEmpty) {
      query = query.eq('due_id', dueId);
    }
    final response = await query.order('paid_at', ascending: false).limit(100);
    return _rows(response).map(TrainerPayment.fromMap).toList();
  }

  // ------------------------------------------------------------------- staff

  Future<List<StaffCompensationRow>> getStaffCompensation() async {
    final response = await _client
        .from('staff_compensation_v')
        .select()
        .order('full_name')
        .order('effective_from', ascending: false);
    return _rows(response).map(StaffCompensationRow.fromMap).toList();
  }

  Future<void> addStaffCompensation({
    required String userId,
    required double monthlySalary,
    required String currency,
    required double commissionRatePercent,
    required DateTime effectiveFrom,
    DateTime? effectiveTo,
    String? notes,
  }) async {
    await _client.from('staff_compensation').insert({
      'user_id': userId,
      'monthly_salary': monthlySalary,
      'currency': currency,
      'commission_rate_percent': commissionRatePercent,
      'effective_from': _dateOnly(effectiveFrom),
      'effective_to': effectiveTo == null ? null : _dateOnly(effectiveTo),
      'notes': notes,
      'created_by': _uid,
    });
  }

  Future<void> deleteStaffCompensation(String id) async {
    await _client.from('staff_compensation').delete().eq('id', id);
  }

  Future<List<StaffAdvance>> getAdvances() async {
    final response = await _client
        .from('staff_advances')
        .select('''
          id, user_id, amount, currency, advanced_at, account_id, reason,
          status, payroll_line_id, created_at,
          users!staff_advances_user_id_fkey(full_name),
          financial_accounts!staff_advances_account_id_fkey(name_ar)
        ''')
        .order('advanced_at', ascending: false)
        .limit(200);
    return _rows(response).map(StaffAdvance.fromMap).toList();
  }

  Future<void> addAdvance({
    required String userId,
    required double amount,
    required String currency,
    required String accountId,
    DateTime? advancedAt,
    String? reason,
  }) async {
    await _client.from('staff_advances').insert({
      'user_id': userId,
      'amount': amount,
      'currency': currency,
      'advanced_at': _dateOnly(advancedAt ?? DateTime.now()),
      'account_id': accountId,
      'reason': reason,
      'created_by': _uid,
    });
  }

  Future<void> cancelAdvance(String id) async {
    await _client.rpc('cancel_staff_advance', params: {'p_advance_id': id});
  }

  Future<List<StaffBonus>> getBonuses() async {
    final response = await _client
        .from('staff_bonuses')
        .select('''
          id, user_id, amount, currency, bonus_month, reason, payroll_line_id,
          created_at,
          users!staff_bonuses_user_id_fkey(full_name)
        ''')
        .order('bonus_month', ascending: false)
        .order('created_at', ascending: false)
        .limit(200);
    return _rows(response).map(StaffBonus.fromMap).toList();
  }

  Future<void> addBonus({
    required String userId,
    required double amount,
    required String currency,
    required DateTime bonusMonth,
    required String reason,
  }) async {
    await _client.from('staff_bonuses').insert({
      'user_id': userId,
      'amount': amount,
      'currency': currency,
      'bonus_month': monthKey(bonusMonth),
      'reason': reason,
      'approved_by': _uid,
      'created_by': _uid,
    });
  }

  Future<void> deleteBonus(String id) async {
    final deleted = await _client
        .from('staff_bonuses')
        .delete()
        .eq('id', id)
        .isFilter('payroll_line_id', null)
        .select('id');
    if ((deleted as List).isEmpty) {
      throw Exception('لا يمكن حذف مكافأة دخلت في مسير رواتب');
    }
  }

  Future<List<StaffReferral>> getReferrals() async {
    final response = await _client
        .from('staff_referrals')
        .select('''
          id, enrollment_id, staff_id, commission_rate_percent, created_at,
          users!staff_referrals_staff_id_fkey(full_name),
          enrollments!staff_referrals_enrollment_id_fkey(
            trainees!enrollments_trainee_id_fkey(
              trainee_code,
              users!trainees_user_id_fkey(full_name)
            )
          )
        ''')
        .order('created_at', ascending: false)
        .limit(200);
    return _rows(response).map(StaffReferral.fromMap).toList();
  }

  Future<void> addReferral({
    required String enrollmentId,
    required String staffId,
    required double ratePercent,
  }) async {
    await _client.from('staff_referrals').insert({
      'enrollment_id': enrollmentId,
      'staff_id': staffId,
      'commission_rate_percent': ratePercent,
      'created_by': _uid,
    });
  }

  Future<void> deleteReferral(String id) async {
    await _client.from('staff_referrals').delete().eq('id', id);
  }

  /// Enrollments that do not have a referral yet; the unique constraint on
  /// staff_referrals.enrollment_id makes a second referral impossible.
  Future<List<EnrollmentOption>> getEnrollmentOptions({String search = ''}) async {
    final referred = await _client
        .from('staff_referrals')
        .select('enrollment_id')
        .limit(1000);
    final referredIds = {
      for (final row in _rows(referred)) row['enrollment_id'].toString()
    };

    final response = await _client
        .from('enrollments')
        .select('''
          id, created_at,
          trainees!enrollments_trainee_id_fkey(
            trainee_code,
            users!trainees_user_id_fkey(full_name)
          ),
          cohorts!enrollments_cohort_id_fkey(
            courses!cohorts_course_id_fkey(name)
          )
        ''')
        .order('created_at', ascending: false)
        .limit(search.trim().isEmpty ? 100 : 500);

    final needle = search.trim().toLowerCase();
    return _rows(response)
        .where((row) => !referredIds.contains(row['id'].toString()))
        .map(EnrollmentOption.fromMap)
        .where((option) =>
            needle.isEmpty ||
            option.traineeName.toLowerCase().contains(needle) ||
            option.traineeCode.toLowerCase().contains(needle) ||
            option.courseName.toLowerCase().contains(needle))
        .toList();
  }

  // ----------------------------------------------------------------- payroll

  Future<List<PayrollLine>> getPayroll(DateTime month) async {
    final response = await _client
        .from('payroll_v')
        .select()
        .eq('month', monthKey(month))
        .order('full_name');
    return _rows(response).map(PayrollLine.fromMap).toList();
  }

  Future<String> generatePayroll(DateTime month) async {
    final result = await _client.rpc('generate_payroll', params: {
      'p_month': monthKey(month),
    });
    return result.toString();
  }

  Future<void> approvePayroll(String runId) async {
    await _client.rpc('approve_payroll', params: {'p_run_id': runId});
  }

  Future<int> payPayroll(String runId, String accountId) async {
    final result = await _client.rpc('pay_payroll', params: {
      'p_run_id': runId,
      'p_account_id': accountId,
    });
    return (result as num?)?.toInt() ?? 0;
  }

  // ----------------------------------------------------------------- lookups

  Future<List<CompensationUser>> getTrainers() async {
    final response = await _client
        .from('users')
        .select('id, full_name, role, is_active')
        .eq('role', 'trainer')
        .eq('is_active', true)
        .order('full_name');
    return _rows(response).map(CompensationUser.fromMap).toList();
  }

  Future<List<CompensationUser>> getStaffUsers() async {
    final response = await _client
        .from('users')
        .select('id, full_name, role, is_active')
        .inFilter('role', ['admin', 'reception'])
        .eq('is_active', true)
        .order('full_name');
    return _rows(response).map(CompensationUser.fromMap).toList();
  }

  Future<List<CourseOption>> getCourses() async {
    final response =
        await _client.from('courses').select('id, name').order('name');
    return _rows(response).map(CourseOption.fromMap).toList();
  }
}

String _dateOnly(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year.toString().padLeft(4, '0')}-$month-$day';
}

final compensationRepositoryProvider =
    Provider<CompensationRepository>((ref) => CompensationRepository());

// ---------------------------------------------------------------------------
// Providers — screens invalidate the ones a mutation affects
// ---------------------------------------------------------------------------

final cohortRatesProvider =
    FutureProvider.autoDispose<List<CohortTrainerRate>>((ref) {
  return ref.watch(compensationRepositoryProvider).getCohortRates();
});

final agreementsProvider =
    FutureProvider.autoDispose<List<TrainerAgreement>>((ref) {
  return ref.watch(compensationRepositoryProvider).getAgreements();
});

final trainerDuesProvider =
    FutureProvider.autoDispose.family<List<TrainerDue>, DateTime>((ref, month) {
  return ref.watch(compensationRepositoryProvider).getTrainerDues(month);
});

final trainerPaymentsProvider = FutureProvider.autoDispose
    .family<List<TrainerPayment>, String?>((ref, dueId) {
  return ref.watch(compensationRepositoryProvider).getTrainerPayments(
        dueId: dueId,
      );
});

final staffCompensationProvider =
    FutureProvider.autoDispose<List<StaffCompensationRow>>((ref) {
  return ref.watch(compensationRepositoryProvider).getStaffCompensation();
});

final advancesProvider = FutureProvider.autoDispose<List<StaffAdvance>>((ref) {
  return ref.watch(compensationRepositoryProvider).getAdvances();
});

final bonusesProvider = FutureProvider.autoDispose<List<StaffBonus>>((ref) {
  return ref.watch(compensationRepositoryProvider).getBonuses();
});

final referralsProvider =
    FutureProvider.autoDispose<List<StaffReferral>>((ref) {
  return ref.watch(compensationRepositoryProvider).getReferrals();
});

final payrollProvider =
    FutureProvider.autoDispose.family<List<PayrollLine>, DateTime>((ref, month) {
  return ref.watch(compensationRepositoryProvider).getPayroll(month);
});

final compensationTrainersProvider =
    FutureProvider.autoDispose<List<CompensationUser>>((ref) {
  return ref.watch(compensationRepositoryProvider).getTrainers();
});

final compensationStaffProvider =
    FutureProvider.autoDispose<List<CompensationUser>>((ref) {
  return ref.watch(compensationRepositoryProvider).getStaffUsers();
});

final courseOptionsProvider =
    FutureProvider.autoDispose<List<CourseOption>>((ref) {
  return ref.watch(compensationRepositoryProvider).getCourses();
});
