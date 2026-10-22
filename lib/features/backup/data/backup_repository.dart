import 'dart:convert';
import 'dart:typed_data';
import 'package:file_saver/file_saver.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:supabase_flutter/supabase_flutter.dart';

class BackupRepository {
  final SupabaseClient _client;

  BackupRepository(this._client);

  /// استدعاء دالة التصدير السيرفرية لجلب نسخة JSON كاملة من بيانات النظام
  Future<Map<String, dynamic>> exportSystemData() async {
    final response = await _client.rpc('export_system_data');
    if (response is Map<String, dynamic>) {
      return response;
    }
    return Map<String, dynamic>.from(response as Map);
  }

  /// حفظ كائن الـ JSON كملف قابل للتحميل على جهاز المدير
  Future<String> saveExportToFile(Map<String, dynamic> data) async {
    final timestamp = DateFormat('yyyy-MM-dd_HH-mm').format(DateTime.now());
    final fileName = 'taj_dentics_export_$timestamp';

    // تهيئة الـ JSON بتنسيق مرتب وسهل القراءة
    final jsonString = const JsonEncoder.withIndent('  ').convert(data);
    final bytes = utf8.encode(jsonString);

    final path = await FileSaver.instance.saveFile(
      name: fileName,
      bytes: Uint8List.fromList(bytes),
      ext: 'json',
      mimeType: MimeType.json,
    );

    return path;
  }
}

final backupRepositoryProvider = Provider<BackupRepository>((ref) {
  return BackupRepository(Supabase.instance.client);
});
