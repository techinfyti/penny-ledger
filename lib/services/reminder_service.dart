import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'notification_service.dart';
import 'rating_prompt.dart';

/// A gentle daily reminder to add the day's expenses. It is scheduled as one notification
/// per day for the next week and re-planned whenever the app opens or a transaction is
/// added, so a day that already has a transaction gets no reminder.
class ReminderService {
  static const int defaultHour = 21;
  static const int defaultMinute = 0;
  static const int daysAhead = 7;
  static const int _baseId = 9100;
  static const int askAfterActions = 3;

  static const _enabledKey = 'reminder_enabled';
  static const _hourKey = 'reminder_hour';
  static const _minuteKey = 'reminder_minute';
  static const _lastAddedKey = 'reminder_last_added_day';
  static const _askedKey = 'reminder_asked';

  final NotificationService _notifications;

  ReminderService(this._notifications);

  /// The moments to remind at: today (if the time has not passed and nothing was added
  /// today) and the following days. Pure, so it can be tested.
  static List<DateTime> upcomingTimes({
    required DateTime now,
    required int hour,
    required int minute,
    required bool addedToday,
    int days = daysAhead,
  }) {
    final times = <DateTime>[];
    for (var i = 0; i < days; i++) {
      final when = DateTime(now.year, now.month, now.day + i, hour, minute);
      if (!when.isAfter(now)) continue;
      if (i == 0 && addedToday) continue;
      times.add(when);
    }
    return times;
  }

  static String dayKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

  Future<({bool enabled, TimeOfDay time})> load() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      enabled: prefs.getBool(_enabledKey) ?? false,
      time: TimeOfDay(hour: prefs.getInt(_hourKey) ?? defaultHour, minute: prefs.getInt(_minuteKey) ?? defaultMinute),
    );
  }

  Future<void> save({required bool enabled, required TimeOfDay time}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
    await prefs.setInt(_hourKey, time.hour);
    await prefs.setInt(_minuteKey, time.minute);
    await reschedule();
  }

  /// Plans the next week of reminders from the saved settings.
  Future<void> reschedule() async {
    try {
      for (var i = 0; i < daysAhead; i++) {
        await _notifications.cancelReminder(_baseId + i);
      }
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool(_enabledKey) ?? false)) return;
      final now = DateTime.now();
      final times = upcomingTimes(
        now: now,
        hour: prefs.getInt(_hourKey) ?? defaultHour,
        minute: prefs.getInt(_minuteKey) ?? defaultMinute,
        addedToday: prefs.getString(_lastAddedKey) == dayKey(now),
      );
      for (var i = 0; i < times.length; i++) {
        await _notifications.scheduleReminder(
          id: _baseId + times[i].difference(DateTime(now.year, now.month, now.day)).inDays.clamp(0, daysAhead - 1),
          when: times[i],
          title: 'PennyLedger',
          body: 'Added today\'s expenses? It only takes a few seconds.',
        );
      }
    } catch (_) {
      // A reminder that cannot be scheduled must never get in the way of the app.
    }
  }

  /// Call after a transaction was added: today's reminder is no longer needed.
  Future<void> markAddedToday() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastAddedKey, dayKey(DateTime.now()));
      if (prefs.getBool(_enabledKey) ?? false) await reschedule();
    } catch (_) {}
  }

  /// Once, after the user has added a few transactions, offers to switch the reminder on.
  Future<void> maybeAsk(BuildContext context) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_askedKey) ?? false) return;
      if (prefs.getBool(_enabledKey) ?? false) return;
      if (await RatingPrompt.actions() < askAfterActions) return;
      if (!context.mounted) return;
      await prefs.setBool(_askedKey, true);
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Daily reminder?'),
          content: const Text(
            'Want a gentle reminder each evening at 9:00 PM to add your expenses? '
            'You can change the time or switch it off any time in Settings.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('No thanks')),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Yes, remind me')),
          ],
        ),
      );
      if (yes == true) {
        await save(enabled: true, time: const TimeOfDay(hour: defaultHour, minute: defaultMinute));
      }
    } catch (_) {}
  }
}
