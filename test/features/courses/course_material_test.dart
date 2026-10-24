import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:admin_dashboard/features/courses/domain/course_material_model.dart';

void main() {
  group('CourseMaterial domain model tests', () {
    test('parses file material correctly from map', () {
      final map = {
        'id': 'mat-1',
        'course_id': 'crs-1',
        'title': 'Lecture 1 Slides',
        'description': 'Introduction slides',
        'material_type': 'file',
        'file_path': 'crs-1/slides.pdf',
        'file_size_bytes': 1048576, // 1 MB
        'mime_type': 'application/pdf',
        'external_url': null,
        'is_published': true,
        'created_at': '2026-10-24T12:00:00Z',
        'created_by': 'user-1',
      };

      final mat = CourseMaterial.fromMap(map);

      expect(mat.id, 'mat-1');
      expect(mat.courseId, 'crs-1');
      expect(mat.title, 'Lecture 1 Slides');
      expect(mat.isFile, true);
      expect(mat.isLink, false);
      expect(mat.fileSizeDisplay, '1.0 MB');
      expect(mat.icon, Icons.picture_as_pdf_outlined);
      expect(mat.isPublished, true);
    });

    test('parses link material correctly from map', () {
      final map = {
        'id': 'mat-2',
        'course_id': 'crs-1',
        'title': 'YouTube Recording',
        'description': 'Demo recording',
        'material_type': 'link',
        'file_path': null,
        'file_size_bytes': null,
        'mime_type': null,
        'external_url': 'https://youtube.com/watch?v=123',
        'is_published': false,
        'created_at': '2026-10-24T12:00:00Z',
      };

      final mat = CourseMaterial.fromMap(map);

      expect(mat.id, 'mat-2');
      expect(mat.isFile, false);
      expect(mat.isLink, true);
      expect(mat.fileSizeDisplay, '');
      expect(mat.icon, Icons.video_library_outlined);
      expect(mat.isPublished, false);
    });
  });
}
