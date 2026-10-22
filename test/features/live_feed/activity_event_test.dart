import 'package:flutter_test/flutter_test.dart';
import 'package:admin_dashboard/features/live_feed/domain/activity_event.dart';

void main() {
  group('ActivityEvent Tests (Phase B2)', () {
    test('instantiates correctly and provides labels and timeAgo', () {
      final now = DateTime.now().subtract(const Duration(seconds: 10));
      final event = ActivityEvent(
        id: 'evt-1',
        type: ActivityEventType.centerPayment,
        title: 'دفعة تدريب جديدة',
        subtitle: 'سارة أحمد',
        detail: '150,000 ل.س',
        timestamp: now,
      );

      expect(event.id, 'evt-1');
      expect(event.type, ActivityEventType.centerPayment);
      expect(event.title, 'دفعة تدريب جديدة');
      expect(event.subtitle, 'سارة أحمد');
      expect(event.detail, '150,000 ل.س');
      expect(event.typeLabel, 'دفعة تدريب');
      expect(event.timeAgo, 'الآن');
    });

    test('ActivityEventType has correct Arabic labels across all types', () {
      final p1 = ActivityEvent(
        id: '1',
        type: ActivityEventType.centerPayment,
        title: 'p',
        subtitle: 's',
        timestamp: DateTime.now(),
      );
      final p2 = ActivityEvent(
        id: '2',
        type: ActivityEventType.sessionAttendance,
        title: 'p',
        subtitle: 's',
        timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
      );
      final p3 = ActivityEvent(
        id: '3',
        type: ActivityEventType.labPayment,
        title: 'p',
        subtitle: 's',
        timestamp: DateTime.now().subtract(const Duration(hours: 3)),
      );

      expect(p1.typeLabel, 'دفعة تدريب');
      expect(p2.typeLabel, 'تسجيل حضور');
      expect(p3.typeLabel, 'دفعة مخبر');

      expect(p2.timeAgo, 'منذ 5 دقائق');
      expect(p3.timeAgo, 'منذ 3 ساعات');
    });
  });
}
