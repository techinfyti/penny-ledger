import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Asks for a Play Store rating with Google's own in-app dialog, but only after the
/// user has really used the app, and rarely: every transaction added or imported
/// counts towards a threshold, and after each ask the app waits before asking again.
class RatingPrompt {
  static const int minActions = 10;
  static const Duration minGap = Duration(days: 30);
  static const int maxPrompts = 3;

  static const _actionsKey = 'rating_actions';
  static const _lastKey = 'rating_last_prompt_ms';
  static const _shownKey = 'rating_prompts_shown';

  /// Whether it is time to ask. Pure, so it can be tested.
  static bool shouldPrompt({
    required int actions,
    required int? lastPromptMs,
    required int promptsShown,
    required DateTime now,
  }) {
    if (actions < minActions) return false;
    if (promptsShown >= maxPrompts) return false;
    if (lastPromptMs == null) return true;
    final last = DateTime.fromMillisecondsSinceEpoch(lastPromptMs);
    return now.difference(last) >= minGap;
  }

  /// Call after transactions were added or imported.
  static Future<void> recordActions(int count) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_actionsKey, (prefs.getInt(_actionsKey) ?? 0) + count);
    } catch (_) {
      // Rating is optional; never let it get in the way.
    }
  }

  /// How many transactions have been added or imported so far (used to time other prompts too).
  static Future<int> actions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_actionsKey) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Call when the user has finished a task and is back on a main screen.
  static Future<void> maybeAsk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final due = shouldPrompt(
        actions: prefs.getInt(_actionsKey) ?? 0,
        lastPromptMs: prefs.getInt(_lastKey),
        promptsShown: prefs.getInt(_shownKey) ?? 0,
        now: DateTime.now(),
      );
      if (!due) return;
      final review = InAppReview.instance;
      // Only available for installs from Google Play; otherwise nothing is asked or recorded.
      if (!await review.isAvailable()) return;
      await prefs.setInt(_lastKey, DateTime.now().millisecondsSinceEpoch);
      await prefs.setInt(_shownKey, (prefs.getInt(_shownKey) ?? 0) + 1);
      await review.requestReview();
    } catch (_) {
      // Ignore: failing to show a rating box must not affect the app.
    }
  }

  /// Opens the app's Play Store page, for the Rate item in Settings.
  static Future<void> openStorePage() async {
    try {
      await InAppReview.instance.openStoreListing();
    } catch (_) {}
  }
}
