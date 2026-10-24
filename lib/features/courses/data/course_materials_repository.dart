import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/course_material_model.dart';

final courseMaterialsRepositoryProvider = Provider<CourseMaterialsRepository>((ref) {
  return CourseMaterialsRepository();
});

final courseMaterialsProvider = FutureProvider.family<List<CourseMaterial>, String>((ref, courseId) {
  return ref.watch(courseMaterialsRepositoryProvider).fetchMaterials(courseId);
});

class CourseMaterialsRepository {
  final SupabaseClient _client = Supabase.instance.client;
  static const String _bucket = 'course-materials';

  Future<List<CourseMaterial>> fetchMaterials(String courseId) async {
    final response = await _client
        .from('course_materials')
        .select()
        .eq('course_id', courseId)
        .order('created_at', ascending: false);

    return (response as List)
        .map((m) => CourseMaterial.fromMap(m as Map<String, dynamic>))
        .toList();
  }

  Future<CourseMaterial> uploadFile({
    required String courseId,
    required String title,
    String? description,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    bool isPublished = true,
  }) async {
    final sanitizedFileName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final storagePath = '$courseId/${DateTime.now().millisecondsSinceEpoch}_$sanitizedFileName';

    // 1. Upload to Supabase Storage
    await _client.storage.from(_bucket).uploadBinary(
      storagePath,
      bytes,
      fileOptions: FileOptions(
        contentType: mimeType,
        upsert: false,
      ),
    );

    // 2. Insert record in course_materials (with cleanup of orphaned storage file on failure)
    try {
      final currentUserId = _client.auth.currentUser?.id;
      final row = await _client.from('course_materials').insert({
        'course_id': courseId,
        'title': title,
        'description': description?.trim().isEmpty == true ? null : description?.trim(),
        'material_type': 'file',
        'file_path': storagePath,
        'file_size_bytes': bytes.length,
        'mime_type': mimeType,
        'is_published': isPublished,
        'created_by': currentUserId,
      }).select().single();

      return CourseMaterial.fromMap(row);
    } catch (e) {
      // Prevent orphaned storage objects if database insertion fails
      try {
        await _client.storage.from(_bucket).remove([storagePath]);
      } catch (_) {}
      rethrow;
    }
  }

  Future<CourseMaterial> addExternalLink({
    required String courseId,
    required String title,
    String? description,
    required String url,
    bool isPublished = true,
  }) async {
    final currentUserId = _client.auth.currentUser?.id;
    final row = await _client.from('course_materials').insert({
      'course_id': courseId,
      'title': title,
      'description': description?.trim().isEmpty == true ? null : description?.trim(),
      'material_type': 'link',
      'external_url': url.trim(),
      'is_published': isPublished,
      'created_by': currentUserId,
    }).select().single();

    return CourseMaterial.fromMap(row);
  }

  Future<void> togglePublish(String materialId, bool isPublished) async {
    await _client
        .from('course_materials')
        .update({'is_published': isPublished})
        .eq('id', materialId);
  }

  Future<void> deleteMaterial(CourseMaterial material) async {
    // 1. Delete file from storage if it is a file
    if (material.isFile && material.filePath != null) {
      try {
        await _client.storage.from(_bucket).remove([material.filePath!]);
      } catch (_) {
        // Storage error shouldn't block row deletion if already removed
      }
    }

    // 2. Delete row from database
    await _client.from('course_materials').delete().eq('id', material.id);
  }

  Future<String> getSignedUrl(String filePath, {int expiresInSeconds = 3600}) async {
    return await _client.storage.from(_bucket).createSignedUrl(filePath, expiresInSeconds);
  }
}
