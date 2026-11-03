import 'package:flutter_test/flutter_test.dart';
import 'package:penny_ledger/services/rating_prompt.dart';

void main() {
  final now = DateTime(2026, 11, 20);

  bool due({int actions = 10, int? lastPromptMs, int shown = 0}) =>
      RatingPrompt.shouldPrompt(actions: actions, lastPromptMs: lastPromptMs, promptsShown: shown, now: now);

  test('does not ask before enough transactions have been added', () {
    expect(due(actions: 9), isFalse);
  });

  test('asks once the threshold is reached and it has never asked', () {
    expect(due(actions: 10), isTrue);
    expect(due(actions: 85), isTrue);
  });

  test('waits 30 days after asking', () {
    final tenDaysAgo = now.subtract(const Duration(days: 10)).millisecondsSinceEpoch;
    final thirtyDaysAgo = now.subtract(const Duration(days: 30)).millisecondsSinceEpoch;
    expect(due(lastPromptMs: tenDaysAgo, shown: 1), isFalse);
    expect(due(lastPromptMs: thirtyDaysAgo, shown: 1), isTrue);
  });

  test('stops asking after three times', () {
    final longAgo = now.subtract(const Duration(days: 400)).millisecondsSinceEpoch;
    expect(due(lastPromptMs: longAgo, shown: 3), isFalse);
    expect(due(lastPromptMs: longAgo, shown: 2), isTrue);
  });
}
