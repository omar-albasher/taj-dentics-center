import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/trainee_model.dart';

class TraineesRepository {
  final _client = Supabase.instance.client;

  Future<List<TraineeModel>> getTrainees({String? search}) async {
    var query = _client.from('trainees').select('''
*,
users!trainees_user_id_fkey(
  id,
  full_name,
  email,
  phone,
  is_active
)
''');

    if (search != null && search.trim().isNotEmpty) {
      final s = search.trim();
      query = query.or('trainee_code.ilike.%$s%,full_name_ar.ilike.%$s%,full_name_en.ilike.%$s%,users.full_name.ilike.%$s%');
    }

    final response = await query.order('created_at', ascending: false);
    return (response as List).map((e) => TraineeModel.fromMap(e)).toList();
  }

  Future<TraineeModel?> getTraineeById(String traineeId) async {
    try {
      final response = await _client.from('trainees').select('''
*,
users!trainees_user_id_fkey(
  id,
  full_name,
  email,
  phone,
  is_active
)
''').eq('id', traineeId).maybeSingle();

      if (response == null) return null;
      return TraineeModel.fromMap(response);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> getTraineeProfile(String traineeId) async {
    final results = await Future.wait([
      _client
          .from('enrollment_financial_summary')
          .select()
          .eq('trainee_id', traineeId),
      _client
          .from('trainee_academic_progress')
          .select()
          .eq('trainee_id', traineeId),
      _client
          .from('payments')
          .select('*, enrollments!inner(trainee_id)')
          .eq('enrollments.trainee_id', traineeId)
          .order('paid_at', ascending: false),
    ]);

    return {
      'financial': List<Map<String, dynamic>>.from(results[0]),
      'progress': List<Map<String, dynamic>>.from(results[1]),
      'payments': List<Map<String, dynamic>>.from(results[2]),
    };
  }

  Future<void> addTrainee({
    String? traineeCode,
    required String fullName,
    String? fullNameEn,
    required String email,
    required String phone,
    String? whatsapp,
    String? province,
    String? address,
    String? university,
    String? academicYear,
    String? behavioralNotes,
    String? academicNotes,
    String? notes,
    DateTime? batchDate,
    required String password,
  }) async {
    // 1. Invoke quick-endpoint to create auth user and base trainee row
    final response = await _client.functions.invoke(
      'quick-endpoint',
      body: {
        'full_name': fullName,
        'email': email,
        'phone': phone,
        'password': password,
      },
    );

    final data = response.data;
    if (data is Map && data['error'] != null) {
      throw Exception(data['error']);
    }

    // 2. Direct secure update for trainee extra profile fields
    try {
      String? traineeId = data is Map ? (data['trainee_id'] as String?) : null;
      if (traineeId == null) {
        final u = await _client.from('users').select('id').eq('email', email).maybeSingle();
        if (u != null) {
          final t = await _client.from('trainees').select('id').eq('user_id', u['id']).maybeSingle();
          traineeId = t?['id'] as String?;
        }
      }

      if (traineeId != null) {
        final updateData = <String, dynamic>{
          if (traineeCode != null && traineeCode.trim().isNotEmpty)
            'trainee_code': traineeCode.trim().toUpperCase(),
          'full_name_ar': fullName.trim(),
          if (fullNameEn != null && fullNameEn.trim().isNotEmpty)
            'full_name_en': fullNameEn.trim(),
          if (whatsapp != null && whatsapp.trim().isNotEmpty)
            'whatsapp_number': whatsapp.trim(),
          if (university != null && university.trim().isNotEmpty) ...{
            'university_name': university.trim(),
            'university': university.trim(),
          },
          if (academicYear != null && academicYear.trim().isNotEmpty)
            'academic_year': academicYear.trim(),
          if (province != null && province.trim().isNotEmpty)
            'province': province.trim(),
          if (address != null && address.trim().isNotEmpty)
            'address': address.trim(),
          if (behavioralNotes != null && behavioralNotes.trim().isNotEmpty)
            'behavioral_notes': behavioralNotes.trim(),
          if (academicNotes != null && academicNotes.trim().isNotEmpty)
            'academic_notes': academicNotes.trim(),
          if (notes != null && notes.trim().isNotEmpty)
            'notes': notes.trim(),
          if (batchDate != null)
            'batch_date': batchDate.toIso8601String().split('T')[0],
        };

        if (updateData.isNotEmpty) {
          await _client.from('trainees').update(updateData).eq('id', traineeId);
        }
      }
    } catch (e) {
      debugPrint('Error saving extra trainee details: $e');
    }
  }

  Future<void> updateTraineeDetails({
    required String traineeId,
    String? traineeCode,
    String? fullNameAr,
    String? fullNameEn,
    String? university,
    String? academicYear,
    String? whatsapp,
    String? province,
    String? address,
    String? behavioralNotes,
    String? academicNotes,
    String? notes,
    DateTime? batchDate,
  }) async {
    final updateData = <String, dynamic>{
      if (traineeCode != null && traineeCode.trim().isNotEmpty)
        'trainee_code': traineeCode.trim().toUpperCase(),
      if (fullNameAr != null && fullNameAr.trim().isNotEmpty)
        'full_name_ar': fullNameAr.trim(),
      if (fullNameEn != null) 'full_name_en': fullNameEn.trim(),
      if (university != null) ...{
        'university_name': university.trim(),
        'university': university.trim(),
      },
      if (academicYear != null) 'academic_year': academicYear.trim(),
      if (whatsapp != null) 'whatsapp_number': whatsapp.trim(),
      if (province != null) 'province': province.trim(),
      if (address != null) 'address': address.trim(),
      if (behavioralNotes != null) 'behavioral_notes': behavioralNotes.trim(),
      if (academicNotes != null) 'academic_notes': academicNotes.trim(),
      if (notes != null) 'notes': notes.trim(),
      if (batchDate != null)
        'batch_date': batchDate.toIso8601String().split('T')[0],
    };

    if (updateData.isNotEmpty) {
      await _client.from('trainees').update(updateData).eq('id', traineeId);
    }
  }
}

/// Repository
final traineesRepositoryProvider =
    Provider<TraineesRepository>((ref) => TraineesRepository());

/// جميع المتدربين (مع البحث بكود المتدرب أو الاسم)
final traineesProvider =
    FutureProvider.family<List<TraineeModel>, String?>((ref, search) async {
  final repo = ref.watch(traineesRepositoryProvider);
  return repo.getTrainees(search: search);
});

/// الملف الشخصي
final traineeProfileProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, traineeId) {
  return ref.watch(traineesRepositoryProvider).getTraineeProfile(traineeId);
});

/// بيانات متدرب حسب المعرف
final traineeByIdProvider =
    FutureProvider.family<TraineeModel?, String>((ref, id) {
  return ref.watch(traineesRepositoryProvider).getTraineeById(id);
});
