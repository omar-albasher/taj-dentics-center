import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

enum ActivityEventType {
  centerPayment,
  sessionAttendance,
  labPayment,
}

class ActivityEvent {
  final String id;
  final ActivityEventType type;
  final String title;
  final String subtitle;
  final String? detail;
  final DateTime timestamp;
  final String? amountDisplay;
  final String? traineeCode;

  const ActivityEvent({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    this.detail,
    required this.timestamp,
    this.amountDisplay,
    this.traineeCode,
  });

  IconData get icon {
    switch (type) {
      case ActivityEventType.centerPayment:
        return Icons.payments_outlined;
      case ActivityEventType.sessionAttendance:
        return Icons.how_to_reg_outlined;
      case ActivityEventType.labPayment:
        return Icons.biotech_outlined;
    }
  }

  Color get accentColor {
    switch (type) {
      case ActivityEventType.centerPayment:
        return AppColors.success;
      case ActivityEventType.sessionAttendance:
        return const Color(0xFF3498DB);
      case ActivityEventType.labPayment:
        return AppColors.gold;
    }
  }

  String get typeLabel {
    switch (type) {
      case ActivityEventType.centerPayment:
        return 'دفعة تدريب';
      case ActivityEventType.sessionAttendance:
        return 'تسجيل حضور';
      case ActivityEventType.labPayment:
        return 'دفعة مخبر';
    }
  }

  String get timeAgo {
    final now = DateTime.now();
    final diff = now.difference(timestamp);

    if (diff.inSeconds < 45) {
      return 'الآن';
    } else if (diff.inMinutes < 60) {
      final m = diff.inMinutes;
      if (m == 1) return 'منذ دقيقة';
      if (m == 2) return 'منذ دقيقتين';
      if (m <= 10) return 'منذ $m دقائق';
      return 'منذ $m دقيقة';
    } else if (diff.inHours < 24) {
      final h = diff.inHours;
      if (h == 1) return 'منذ ساعة';
      if (h == 2) return 'منذ ساعتين';
      if (h <= 10) return 'منذ $h ساعات';
      return 'منذ $h ساعة';
    } else {
      final d = diff.inDays;
      if (d == 1) return 'أمس';
      if (d == 2) return 'منذ يومين';
      return 'منذ $d أيام';
    }
  }
}
