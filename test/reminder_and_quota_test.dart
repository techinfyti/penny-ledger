import 'package:flutter_test/flutter_test.dart';
import 'package:penny_ledger/services/import_quota_service.dart';
import 'package:penny_ledger/services/reminder_service.dart';

void main() {
  group('daily reminder times', () {
    final morning = DateTime(2026, 11, 10, 8, 30);
    final late = DateTime(2026, 11, 10, 22, 0);

    test('plans a reminder for today and the next six days when the time is still ahead', () {
      final times = ReminderService.upcomingTimes(now: morning, hour: 21, minute: 0, addedToday: false);
      expect(times.length, 7);
      expect(times.first, DateTime(2026, 11, 10, 21, 0));
      expect(times.last, DateTime(2026, 11, 16, 21, 0));
    });

    test('skips today when the time has already passed', () {
      final times = ReminderService.upcomingTimes(now: late, hour: 21, minute: 0, addedToday: false);
      expect(times.length, 6);
      expect(times.first, DateTime(2026, 11, 11, 21, 0));
    });

    test('skips today when a transaction was already added today', () {
      final times = ReminderService.upcomingTimes(now: morning, hour: 21, minute: 0, addedToday: true);
      expect(times.first, DateTime(2026, 11, 11, 21, 0));
      expect(times.length, 6);
    });

    test('rolls over month ends', () {
      final times = ReminderService.upcomingTimes(now: DateTime(2026, 11, 29, 8), hour: 9, minute: 15, addedToday: false);
      expect(times[1], DateTime(2026, 11, 30, 9, 15));
      expect(times[2], DateTime(2026, 12, 1, 9, 15));
    });
  });

  group('free import allowance', () {
    test('is 25 transactions a month', () {
      expect(ImportQuotaService.freeMonthlyLimit, 25);
    });

    test('counts down and never goes below zero', () {
      expect(ImportQuotaService.remaining(0), 25);
      expect(ImportQuotaService.remaining(10), 15);
      expect(ImportQuotaService.remaining(25), 0);
      expect(ImportQuotaService.remaining(80), 0);
    });

    test('a new month starts a new allowance', () {
      expect(ImportQuotaService.monthKey(DateTime(2026, 11, 30)), '2026-11');
      expect(ImportQuotaService.monthKey(DateTime(2026, 12, 1)), '2026-12');
    });
  });
}
