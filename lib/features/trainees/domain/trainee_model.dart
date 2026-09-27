import 'dart:convert';

class TraineeModel {
  final String id;
  final String userId;
  final String? traineeCode;
  final String fullName;
  final String? fullNameAr;
  final String? fullNameEn;
  final String email;
  final String phone;
  final String whatsapp;
  final String? whatsappNumber;
  final String address;
  final String province;
  final String? university;
  final String? universityName;
  final String? academicYear;
  final String? notes;
  final String? behavioralNotes;
  final String? academicNotes;
  final DateTime? batchDate;
  final bool isActive;
  final DateTime createdAt;

  const TraineeModel({
    required this.id,
    required this.userId,
    this.traineeCode,
    required this.fullName,
    this.fullNameAr,
    this.fullNameEn,
    required this.email,
    required this.phone,
    required this.whatsapp,
    this.whatsappNumber,
    required this.address,
    required this.province,
    this.university,
    this.universityName,
    this.academicYear,
    this.notes,
    this.behavioralNotes,
    this.academicNotes,
    this.batchDate,
    required this.isActive,
    required this.createdAt,
  });

  factory TraineeModel.fromMap(Map<String, dynamic> map) {
    final user = map['users'] as Map<String, dynamic>? ?? {};

    Map<String, dynamic> notesMeta = {};
    final rawNotes = map['notes'] as String?;
    if (rawNotes != null && rawNotes.trim().startsWith('{')) {
      try {
        final decoded = jsonDecode(rawNotes);
        if (decoded is Map<String, dynamic>) {
          notesMeta = decoded;
        }
      } catch (_) {}
    }

    final code = map['trainee_code'] as String?;
    final nameAr = map['full_name_ar'] as String?;
    final resolvedFullName = nameAr ?? user['full_name'] ?? map['full_name'] ?? '';
    final rawWhatsapp = map['whatsapp_number'] ?? map['whatsapp'] ?? notesMeta['whatsapp'] ?? '';
    final rawUni = map['university_name'] ?? map['university'] ?? notesMeta['university'];

    return TraineeModel(
      id: map['id'] ?? '',
      userId: map['user_id'] ?? '',
      traineeCode: code != null && code.trim().isNotEmpty ? code.trim() : null,
      fullName: resolvedFullName,
      fullNameAr: nameAr,
      fullNameEn: map['full_name_en'] ?? notesMeta['full_name_en'],
      email: user['email'] ?? '',
      phone: user['phone'] ?? map['phone'] ?? '',
      whatsapp: rawWhatsapp.toString().trim(),
      whatsappNumber: map['whatsapp_number'] as String?,
      address: (map['address'] ?? notesMeta['address'] ?? '').toString(),
      province: (map['province'] ?? notesMeta['province'] ?? '').toString(),
      university: rawUni as String?,
      universityName: map['university_name'] as String?,
      academicYear: (map['academic_year'] ?? notesMeta['academic_year']) as String?,
      notes: notesMeta.isNotEmpty ? (notesMeta['general_notes'] ?? '') : rawNotes,
      behavioralNotes: (map['behavioral_notes'] ?? notesMeta['behavioral_notes']) as String?,
      academicNotes: (map['academic_notes'] ?? notesMeta['academic_notes']) as String?,
      batchDate: DateTime.tryParse(map['batch_date'] ?? ''),
      isActive: user['is_active'] ?? true,
      createdAt: DateTime.tryParse(map['created_at'] ?? '') ?? DateTime.now(),
    );
  }
}
