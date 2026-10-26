import 'package:admin_dashboard/features/trainees/domain/referral_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReferralPreview', () {
    test('parses a valid referrer', () {
      final preview = ReferralPreview.fromMap({
        'valid': true,
        'referrer_trainee_id': 't-1',
        'referrer_name': '  Omar  ',
      });

      expect(preview.valid, true);
      expect(preview.referrerTraineeId, 't-1');
      expect(preview.referrerName, 'Omar');
      expect(preview.error, isNull);
    });

    test('parses an invalid code payload', () {
      final preview = ReferralPreview.fromMap({
        'valid': false,
        'error': 'REFERRAL_REFERRER_INACTIVE',
      });

      expect(preview.valid, false);
      expect(preview.error, 'REFERRAL_REFERRER_INACTIVE');
    });
  });

  group('ReferralSummary', () {
    test('parses credits, entries and totals per currency', () {
      final summary = ReferralSummary.fromMap({
        'trainee_id': 't-1',
        'trainee_name': 'سارة',
        'referral_code': ' t10042 ',
        'available_credits': [
          {'currency': 'syp', 'amount': 50000, 'count': 2},
          {'currency': 'USD', 'amount': 25, 'count': 1},
        ],
        'referrals': [
          {
            'id': 'r-1',
            'referee_name': 'عمر',
            'course_name': 'أساسيات طب الأسنان',
            'amount': 25000,
            'currency': 'syp',
            'status': 'applied',
            'created_at': '2026-10-01T10:00:00Z',
            'applied_at': '2026-10-05T10:00:00Z',
          },
          {
            'id': 'r-2',
            'referee_name': 'ليلى',
            'course_name': 'تجميل',
            'amount': 25,
            'currency': 'USD',
            'status': 'available',
            'created_at': '2026-10-10T10:00:00Z',
          },
        ],
      });

      expect(summary.referralCode, 'T10042');
      expect(summary.traineeName, 'سارة');
      expect(summary.availableCredits.length, 2);
      expect(summary.totalAvailableFor('syp'), 50000);
      expect(summary.totalAvailableFor('usd'), 25);
      expect(summary.totalAvailableFor('eur'), 0);
      expect(summary.hasAvailableCredits, true);

      expect(summary.referrals.length, 2);
      expect(summary.referrals.first.isApplied, true);
      expect(summary.referrals.first.appliedAt, isNotNull);
      expect(summary.referrals.last.isAvailable, true);
      expect(summary.referrals.last.appliedAt, isNull);
    });

    test('handles empty ledgers', () {
      final summary = ReferralSummary.fromMap({
        'referral_code': 'T10000',
      });

      expect(summary.referralCode, 'T10000');
      expect(summary.availableCredits, isEmpty);
      expect(summary.referrals, isEmpty);
      expect(summary.hasAvailableCredits, false);
    });

    test('flags cancelled referral entries', () {
      final entry = ReferralEntry.fromMap({
        'id': 'r-3',
        'status': 'cancelled',
      });

      expect(entry.isCancelled, true);
      expect(entry.isAvailable, false);
      expect(entry.isApplied, false);
      expect(entry.amount, 0);
    });
  });
}
