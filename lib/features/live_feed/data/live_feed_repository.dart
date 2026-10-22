import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/activity_event.dart';

final liveFeedRepositoryProvider = Provider<LiveFeedRepository>((ref) {
  return LiveFeedRepository();
});

class LiveFeedRepository {
  final SupabaseClient _client = Supabase.instance.client;

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
      final response = await _client.from('payments').select('''
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
      ''').order('paid_at', ascending: false).limit(limit);

      final list = <ActivityEvent>[];
      for (final map in (response as List)) {
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

        list.add(ActivityEvent(
          id: 'pay_${map['id']}',
          type: ActivityEventType.centerPayment,
          title: 'تسديد دفعة كورس',
          subtitle: '$traineeName ${code != null ? "($code)" : ""}',
          detail: courseName.isNotEmpty ? 'الدورة: $courseName' : null,
          timestamp: paidAt,
          amountDisplay: '${amt.toStringAsFixed(0)} $currSymbol',
          traineeCode: code,
        ));
      }
      return list;
    } catch (_) {
      return [];
    }
  }

  Future<List<ActivityEvent>> _fetchRecentAttendance(int limit) async {
    try {
      final response = await _client.from('attendance').select('''
        session_id, trainee_id, created_at,
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
      ''').order('created_at', ascending: false).limit(limit);

      final list = <ActivityEvent>[];
      for (final map in (response as List)) {
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

        final createdAt = map['created_at'] != null
            ? (DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()).toLocal()
            : DateTime.now();

        list.add(ActivityEvent(
          id: 'att_${map['session_id']}_${map['trainee_id']}',
          type: ActivityEventType.sessionAttendance,
          title: 'تسجيل حضور جلسة',
          subtitle: '$traineeName ${code != null ? "($code)" : ""}',
          detail: sessionTitle.isNotEmpty ? sessionTitle : null,
          timestamp: createdAt,
          traineeCode: code,
        ));
      }
      return list;
    } catch (_) {
      return [];
    }
  }

  Future<List<ActivityEvent>> _fetchRecentLabPayments(int limit) async {
    try {
      final response = await _client.from('lab_payments').select('''
        id, amount, currency, paid_at,
        lab_invoices!lab_payments_invoice_id_fkey(
          invoice_number, patient_name,
          lab_clients!lab_invoices_client_id_fkey(name)
        )
      ''').order('paid_at', ascending: false).limit(limit);

      final list = <ActivityEvent>[];
      for (final map in (response as List)) {
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

        list.add(ActivityEvent(
          id: 'labpay_${map['id']}',
          type: ActivityEventType.labPayment,
          title: 'دفعة فاتورة مخبر #$invNumber',
          subtitle: clientName,
          detail: patient != null && patient.isNotEmpty ? 'المريض: $patient' : null,
          timestamp: paidAt,
          amountDisplay: '${amt.toStringAsFixed(0)} $currSymbol',
        ));
      }
      return list;
    } catch (_) {
      return [];
    }
  }

  Future<ActivityEvent?> fetchSinglePayment(String id) async {
    final list = await _fetchRecentPayments(5);
    try {
      return list.firstWhere((e) => e.id == 'pay_$id');
    } catch (_) {
      return null;
    }
  }

  Future<ActivityEvent?> fetchSingleAttendance(String sessionId, String traineeId) async {
    final list = await _fetchRecentAttendance(5);
    try {
      return list.firstWhere((e) => e.id == 'att_${sessionId}_$traineeId');
    } catch (_) {
      return null;
    }
  }

  Future<ActivityEvent?> fetchSingleLabPayment(String id) async {
    final list = await _fetchRecentLabPayments(5);
    try {
      return list.firstWhere((e) => e.id == 'labpay_$id');
    } catch (_) {
      return null;
    }
  }
}
