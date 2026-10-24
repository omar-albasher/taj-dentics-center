import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/activity_event.dart';

final liveFeedRepositoryProvider = Provider<LiveFeedRepository>((ref) {
  return LiveFeedRepository();
});

class LiveFeedRepository {
  final SupabaseClient _client = Supabase.instance.client;

  static const String _paymentSelect = '''
    id, amount, currency, paid_at,
    enrollments!payments_enrollment_id_fkey(
      trainees!enrollments_trainee_id_fkey(
        trainee_code,
        users!trainees_user_id_fkey(full_name)
      ),
      cohorts!enrollments_cohort_id_fkey(
        courses!cohorts_course_id_fkey(name)
      )
    )
  ''';

  static const String _attendanceSelect = '''
    session_id, trainee_id, recorded_at,
    trainees!attendance_trainee_id_fkey(
      trainee_code,
      users!trainees_user_id_fkey(full_name)
    ),
    sessions!attendance_session_id_fkey(
      title, session_number,
      cohorts!sessions_cohort_id_fkey(
        courses!cohorts_course_id_fkey(name)
      )
    )
  ''';

  static const String _labPaymentSelect = '''
    id, amount, currency, paid_at,
    lab_invoices!lab_payments_invoice_id_fkey(
      invoice_number, patient_name,
      lab_clients!lab_invoices_client_id_fkey(name)
    )
  ''';

  Future<List<ActivityEvent>> fetchRecentActivities({int limit = 20}) async {
    final results = await Future.wait([
      _fetchRecentPayments(limit),
      _fetchRecentAttendance(limit),
      _fetchRecentLabPayments(limit),
    ]);

    final all = <ActivityEvent>[
      ...results[0],
      ...results[1],
      ...results[2],
    ];

    all.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return all.take(limit).toList();
  }

  Future<List<ActivityEvent>> _fetchRecentPayments(int limit) async {
    try {
      final response = await _client
          .from('payments')
          .select(_paymentSelect)
          .order('paid_at', ascending: false)
          .limit(limit);

      return (response as List)
          .map((map) => _parsePayment(map as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<ActivityEvent>> _fetchRecentAttendance(int limit) async {
    try {
      final response = await _client
          .from('attendance')
          .select(_attendanceSelect)
          .order('recorded_at', ascending: false)
          .limit(limit);

      return (response as List)
          .map((map) => _parseAttendance(map as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<ActivityEvent>> _fetchRecentLabPayments(int limit) async {
    try {
      final response = await _client
          .from('lab_payments')
          .select(_labPaymentSelect)
          .order('paid_at', ascending: false)
          .limit(limit);

      return (response as List)
          .map((map) => _parseLabPayment(map as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<ActivityEvent?> fetchSinglePayment(String id) async {
    try {
      final response = await _client
          .from('payments')
          .select(_paymentSelect)
          .eq('id', id)
          .maybeSingle();

      if (response == null) return null;
      return _parsePayment(response);
    } catch (_) {
      return null;
    }
  }

  Future<ActivityEvent?> fetchSingleAttendance(
    String sessionId,
    String traineeId,
  ) async {
    try {
      final response = await _client
          .from('attendance')
          .select(_attendanceSelect)
          .eq('session_id', sessionId)
          .eq('trainee_id', traineeId)
          .maybeSingle();

      if (response == null) return null;
      return _parseAttendance(response);
    } catch (_) {
      return null;
    }
  }

  Future<ActivityEvent?> fetchSingleLabPayment(String id) async {
    try {
      final response = await _client
          .from('lab_payments')
          .select(_labPaymentSelect)
          .eq('id', id)
          .maybeSingle();

      if (response == null) return null;
      return _parseLabPayment(response);
    } catch (_) {
      return null;
    }
  }

  ActivityEvent _parsePayment(Map<String, dynamic> map) {
    final amt = (map['amount'] as num?)?.toDouble() ?? 0.0;
    final curr = map['currency']?.toString() ?? 'SYP';
    final currSymbol = curr == 'USD' ? '\$' : 'ل.س';

    String traineeName = 'متدرب';
    String? code;
    String courseName = '';

    if (map['enrollments'] is Map) {
      final enr = map['enrollments'] as Map;
      if (enr['trainees'] is Map) {
        final tr = enr['trainees'] as Map;
        code = tr['trainee_code']?.toString();
        if (tr['users'] is Map) {
          traineeName = tr['users']['full_name']?.toString() ?? traineeName;
        }
      }
      if (enr['cohorts'] is Map && enr['cohorts']['courses'] is Map) {
        courseName = enr['cohorts']['courses']['name']?.toString() ?? '';
      }
    }

    final paidAt = map['paid_at'] != null
        ? (DateTime.tryParse(map['paid_at'].toString()) ?? DateTime.now()).toLocal()
        : DateTime.now();

    return ActivityEvent(
      id: 'pay_${map['id']}',
      type: ActivityEventType.centerPayment,
      title: 'تسديد دفعة كورس',
      subtitle: '$traineeName ${code != null ? "($code)" : ""}',
      detail: courseName.isNotEmpty ? 'الدورة: $courseName' : null,
      timestamp: paidAt,
      amountDisplay: '${amt.toStringAsFixed(0)} $currSymbol',
      traineeCode: code,
    );
  }

  ActivityEvent _parseAttendance(Map<String, dynamic> map) {
    String traineeName = 'متدرب';
    String? code;
    String sessionTitle = '';

    if (map['trainees'] is Map) {
      final tr = map['trainees'] as Map;
      code = tr['trainee_code']?.toString();
      if (tr['users'] is Map) {
        traineeName = tr['users']['full_name']?.toString() ?? traineeName;
      }
    }

    if (map['sessions'] is Map) {
      final s = map['sessions'] as Map;
      final title = s['title']?.toString();
      final num = s['session_number']?.toString();
      String course = '';
      if (s['cohorts'] is Map && s['cohorts']['courses'] is Map) {
        course = s['cohorts']['courses']['name']?.toString() ?? '';
      }
      sessionTitle = title != null && title.isNotEmpty
          ? '$title (${course.isNotEmpty ? course : "جلسة $num"})'
          : (course.isNotEmpty ? '$course - جلسة $num' : 'جلسة رقم $num');
    }

    final timeVal = map['recorded_at'] ?? map['created_at'];
    final timestamp = timeVal != null
        ? (DateTime.tryParse(timeVal.toString()) ?? DateTime.now()).toLocal()
        : DateTime.now();

    return ActivityEvent(
      id: 'att_${map['session_id']}_${map['trainee_id']}',
      type: ActivityEventType.sessionAttendance,
      title: 'تسجيل حضور جلسة',
      subtitle: '$traineeName ${code != null ? "($code)" : ""}',
      detail: sessionTitle.isNotEmpty ? sessionTitle : null,
      timestamp: timestamp,
      traineeCode: code,
    );
  }

  ActivityEvent _parseLabPayment(Map<String, dynamic> map) {
    final amt = (map['amount'] as num?)?.toDouble() ?? 0.0;
    final curr = map['currency']?.toString() ?? 'SYP';
    final currSymbol = curr == 'USD' ? '\$' : 'ل.س';

    String clientName = 'طبيب/عيادة';
    int invNumber = 0;
    String? patient;

    if (map['lab_invoices'] is Map) {
      final inv = map['lab_invoices'] as Map;
      invNumber = (inv['invoice_number'] as num?)?.toInt() ?? 0;
      patient = inv['patient_name']?.toString();
      if (inv['lab_clients'] is Map) {
        clientName = inv['lab_clients']['name']?.toString() ?? clientName;
      }
    }

    final paidAt = map['paid_at'] != null
        ? (DateTime.tryParse(map['paid_at'].toString()) ?? DateTime.now()).toLocal()
        : DateTime.now();

    return ActivityEvent(
      id: 'labpay_${map['id']}',
      type: ActivityEventType.labPayment,
      title: 'دفعة فاتورة مخبر #$invNumber',
      subtitle: clientName,
      detail: patient != null && patient.isNotEmpty ? 'المريض: $patient' : null,
      timestamp: paidAt,
      amountDisplay: '${amt.toStringAsFixed(0)} $currSymbol',
    );
  }
}
