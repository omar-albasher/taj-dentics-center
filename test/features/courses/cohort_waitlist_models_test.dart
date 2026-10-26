import 'package:flutter_test/flutter_test.dart';
import 'package:admin_dashboard/features/courses/domain/cohort_model.dart';
import 'package:admin_dashboard/features/courses/domain/cohort_seat_status.dart';
import 'package:admin_dashboard/features/courses/domain/waitlist_entry_model.dart';

void main() {
  group('CohortModel capacity', () {
    test('parses limited capacity', () {
      final cohort = CohortModel.fromMap({
        'id': 'cohort-1',
        'course_id': 'course-1',
        'courses': {'name': 'Dental Basics'},
        'trainer_id': 'trainer-1',
        'name': 'Morning Cohort',
        'starts_at': '2026-11-01T08:00:00Z',
        'capacity': 20,
        'is_active': true,
      });

      expect(cohort.capacity, 20);
      expect(cohort.hasLimitedCapacity, true);
      expect(cohort.courseName, 'Dental Basics');
    });

    test('keeps capacity null when unlimited', () {
      final cohort = CohortModel.fromMap({
        'id': 'cohort-2',
        'course_id': 'course-1',
        'courses': {'name': 'Dental Basics'},
        'trainer_id': 'trainer-1',
        'name': 'Evening Cohort',
        'capacity': null,
        'is_active': true,
      });

      expect(cohort.capacity, isNull);
      expect(cohort.hasLimitedCapacity, false);
    });
  });

  group('CohortSeatStatus', () {
    test('parses unlimited cohort with null available seats', () {
      final status = CohortSeatStatus.fromMap({
        'cohort_id': 'cohort-1',
        'course_id': 'course-1',
        'cohort_name': 'Morning Cohort',
        'course_name': 'Dental Basics',
        'cohort_starts_at': '2026-11-01T08:00:00Z',
        'course_price': 150000,
        'course_total_sessions': 10,
        'capacity': null,
        'enrolled_count': 12,
        'waitlist_count': 0,
        'available_seats': null,
        'is_full': false,
      });

      expect(status.isUnlimited, true);
      expect(status.availableSeats, isNull);
      expect(status.enrolledCount, 12);
      expect(status.isFull, false);
      expect(status.coursePrice, 150000);
      expect(status.cohortStartsAt, isNotNull);
    });

    test('parses full cohort with zero available seats', () {
      final status = CohortSeatStatus.fromMap({
        'cohort_id': 'cohort-2',
        'course_id': 'course-1',
        'cohort_name': 'Evening Cohort',
        'course_name': 'Dental Basics',
        'course_price': 150000,
        'course_total_sessions': 10,
        'capacity': 10,
        'enrolled_count': 10,
        'waitlist_count': 3,
        'available_seats': 0,
        'is_full': true,
      });

      expect(status.isUnlimited, false);
      expect(status.availableSeats, 0);
      expect(status.waitlistCount, 3);
      expect(status.isFull, true);
    });
  });

  group('WaitlistEntryModel', () {
    test('parses nested trainee and user data', () {
      final entry = WaitlistEntryModel.fromMap({
        'id': 'wait-1',
        'cohort_id': 'cohort-1',
        'trainee_id': 'trainee-1',
        'status': 'notified',
        'joined_at': '2026-10-25T09:00:00Z',
        'notified_at': '2026-10-25T10:00:00Z',
        'expires_at': '2099-10-26T10:00:00Z',
        'promoted_at': null,
        'trainees': {
          'id': 'trainee-1',
          'trainee_code': 'T-100',
          'full_name_ar': 'أحمد نور',
          'phone': '0912345678',
          'users': {
            'id': 'user-1',
            'full_name': 'أحمد نور',
            'phone': '0999999999',
            'is_active': true,
          },
        },
      });

      expect(entry.id, 'wait-1');
      expect(entry.traineeName, 'أحمد نور');
      expect(entry.traineeCode, 'T-100');
      expect(entry.traineePhone, '0999999999');
      expect(entry.isNotified, true);
      expect(entry.isWaiting, false);
      expect(entry.isActive, true);
      expect(entry.isOfferExpired, false);
      expect(entry.joinedAt, isNotNull);
    });

    test('falls back safely when relations are absent', () {
      final entry = WaitlistEntryModel.fromMap({
        'id': 'wait-2',
        'cohort_id': 'cohort-1',
        'trainee_id': 'trainee-2',
        'status': 'waiting',
        'joined_at': '2026-10-25T09:00:00Z',
      });

      expect(entry.traineeName, '');
      expect(entry.traineeCode, '');
      expect(entry.traineePhone, '');
      expect(entry.traineeUserActive, true);
      expect(entry.isWaiting, true);
      expect(entry.isActive, true);
    });

    test('detects an expired offer', () {
      final entry = WaitlistEntryModel.fromMap({
        'id': 'wait-3',
        'cohort_id': 'cohort-1',
        'trainee_id': 'trainee-3',
        'status': 'notified',
        'joined_at': '2026-10-20T09:00:00Z',
        'notified_at': '2026-10-20T10:00:00Z',
        'expires_at': '2026-10-21T10:00:00Z',
      });

      expect(entry.isOfferExpired, true);
    });
  });
}
