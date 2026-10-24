import 'package:flutter/material.dart';

enum CourseMaterialType {
  file,
  link,
}

class CourseMaterial {
  final String id;
  final String courseId;
  final String title;
  final String? description;
  final CourseMaterialType materialType;
  final String? filePath;
  final int? fileSizeBytes;
  final String? mimeType;
  final String? externalUrl;
  final bool isPublished;
  final DateTime createdAt;
  final String? createdBy;

  const CourseMaterial({
    required this.id,
    required this.courseId,
    required this.title,
    this.description,
    required this.materialType,
    this.filePath,
    this.fileSizeBytes,
    this.mimeType,
    this.externalUrl,
    required this.isPublished,
    required this.createdAt,
    this.createdBy,
  });

  bool get isFile => materialType == CourseMaterialType.file;
  bool get isLink => materialType == CourseMaterialType.link;

  String get fileSizeDisplay {
    if (fileSizeBytes == null || fileSizeBytes == 0) return '';
    final kb = fileSizeBytes! / 1024;
    if (kb < 1024) {
      return '${kb.toStringAsFixed(1)} KB';
    }
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(1)} MB';
  }

  IconData get icon {
    if (isLink) {
      final url = (externalUrl ?? '').toLowerCase();
      if (url.contains('youtube.com') || url.contains('youtu.be')) {
        return Icons.video_library_outlined;
      }
      if (url.contains('drive.google.com')) {
        return Icons.cloud_outlined;
      }
      return Icons.link_rounded;
    }

    final mime = (mimeType ?? '').toLowerCase();
    final path = (filePath ?? '').toLowerCase();

    if (mime.contains('pdf') || path.endsWith('.pdf')) {
      return Icons.picture_as_pdf_outlined;
    }
    if (mime.contains('image') || path.endsWith('.png') || path.endsWith('.jpg') || path.endsWith('.jpeg')) {
      return Icons.image_outlined;
    }
    if (mime.contains('presentation') || mime.contains('powerpoint') || path.endsWith('.ppt') || path.endsWith('.pptx')) {
      return Icons.slideshow_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  Color get iconColor {
    if (isLink) {
      final url = (externalUrl ?? '').toLowerCase();
      if (url.contains('youtube') || url.contains('youtu.be')) {
        return const Color(0xFFFF0000);
      }
      if (url.contains('drive.google')) {
        return const Color(0xFF4285F4);
      }
      return const Color(0xFF00B4D8);
    }
    final path = (filePath ?? '').toLowerCase();
    if (path.endsWith('.pdf')) return const Color(0xFFE63946);
    if (path.endsWith('.ppt') || path.endsWith('.pptx')) return const Color(0xFFF77F00);
    return const Color(0xFF2A9D8F);
  }

  factory CourseMaterial.fromMap(Map<String, dynamic> map) {
    return CourseMaterial(
      id: map['id'] as String,
      courseId: map['course_id'] as String,
      title: map['title'] as String? ?? '',
      description: map['description'] as String?,
      materialType: (map['material_type'] == 'link')
          ? CourseMaterialType.link
          : CourseMaterialType.file,
      filePath: map['file_path'] as String?,
      fileSizeBytes: (map['file_size_bytes'] as num?)?.toInt(),
      mimeType: map['mime_type'] as String?,
      externalUrl: map['external_url'] as String?,
      isPublished: map['is_published'] as bool? ?? true,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String).toLocal()
          : DateTime.now(),
      createdBy: map['created_by'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'course_id': courseId,
      'title': title,
      'description': description,
      'material_type': isFile ? 'file' : 'link',
      'file_path': filePath,
      'file_size_bytes': fileSizeBytes,
      'mime_type': mimeType,
      'external_url': externalUrl,
      'is_published': isPublished,
    };
  }
}
