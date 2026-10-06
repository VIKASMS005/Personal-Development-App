import 'package:flutter_test/flutter_test.dart';
import 'package:grow_personal_dev/screens/habit_screen.dart';

void main() {
  group('matchesHabitSearch', () {
    test('empty or blank query matches everything', () {
      expect(matchesHabitSearch('Drink water', 'daily', ''), isTrue);
      expect(matchesHabitSearch('Drink water', 'daily', '   '), isTrue);
    });

    test('is case-insensitive and matches part of the title', () {
      expect(matchesHabitSearch('Morning Meditation', 'daily', 'medit'), isTrue);
      expect(matchesHabitSearch('Morning Meditation', 'daily', 'MORNING'), isTrue);
      expect(matchesHabitSearch('Morning Meditation', 'daily', 'run'), isFalse);
    });

    test('every word must match, in any order', () {
      expect(matchesHabitSearch('Read 20 pages', 'daily', 'pages read'), isTrue);
      expect(matchesHabitSearch('Read 20 pages', 'daily', 'read book'), isFalse);
    });

    test('matches the frequency too', () {
      expect(matchesHabitSearch('Long run', 'weekly', 'weekly'), isTrue);
      expect(matchesHabitSearch('Long run', 'weekly', 'run weekly'), isTrue);
      expect(matchesHabitSearch('Long run', 'weekly', 'daily'), isFalse);
    });
  });
}
