import 'package:flutter_test/flutter_test.dart';
import 'package:taskpulse_android/task_parser.dart';

void main() {
  group('Egyptian Arabic task parser', () {
    const members = [TeamName(id: 'ahmed-uid', name: 'أحمد'), TeamName(id: 'mohamed-uid', name: 'محمد'), TeamName(id: 'sara-uid', name: 'سارة')];

    test('parses spoken name, four-hour duration, title, and urgent priority', () {
      final task = TaskParser.parse('أحمد يخلص تصميم الموقع خلال أربع ساعات، مهمة جدًا', members, now: DateTime(2026, 11, 11, 10));
      expect(task.assignedTo, 'ahmed-uid');
      expect(task.durationMinutes, 240);
      expect(task.priority, 'urgent');
      expect(task.title, 'يخلص تصميم الموقع');
      expect(task.assignmentNeedsReview, isFalse);
    });

    test('parses Arabic and Western numerals plus Egyptian duration phrases', () {
      expect(TaskParser.parse('مهمة خلال 4 ساعات', members).durationMinutes, 240);
      expect(TaskParser.parse('مهمة خلال ٤ ساعات', members).durationMinutes, 240);
      expect(TaskParser.parse('مهمة بعد 30 دقيقة', members).durationMinutes, 30);
      expect(TaskParser.parse('مهمة خلال ساعتين', members).durationMinutes, 120);
      expect(TaskParser.parse('مهمة خلال نص ساعة', members).durationMinutes, 30);
      expect(TaskParser.parse('مهمة خلال يومين', members).durationMinutes, 2880);
    });

    test('assigns a confirmed matching member only and leaves unknown names unassigned', () {
      final matched = TaskParser.parse('اعمل تاسك لمحمد يخلص الفيديو خلال 6 ساعات', members);
      expect(matched.assignedTo, 'mohamed-uid');
      expect(matched.durationMinutes, 360);
      expect(matched.title, 'يخلص الفيديو');
      final unmatched = TaskParser.parse('كريم يراجع التقرير خلال ساعتين', members);
      expect(unmatched.assignedTo, isNull);
      expect(unmatched.assignmentNeedsReview, isFalse);
    });

    test('parses a tomorrow-at-five deadline for review', () {
      final now = DateTime(2026, 11, 11, 16);
      final parsed = TaskParser.parse('سارة تراجع الملفات بكرة الساعة ٥', members, now: now);
      expect(parsed.assignedTo, 'sara-uid');
      expect(parsed.dueAt, DateTime(2026, 11, 12, 5));
      expect(parsed.durationMinutes, 780);
      expect(parsed.title, 'تراجع الملفات');
      final spelled = TaskParser.parse('ياسين يخلص التقرير بكرة الساعة خمسة', members, now: now);
      expect(spelled.dueAt, DateTime(2026, 11, 12, 5));
      expect(spelled.title, 'يخلص التقرير');
    });

    test('detects spoken task completion and start updates for explicit review', () {
      final complete = TaskParser.parse('خلصت تصميم الموقع', members);
      expect(complete.intent, 'completed');
      expect(complete.title, 'تصميم الموقع');
      final start = TaskParser.parse('ابدأ تنفيذ التقرير', members);
      expect(start.intent, 'in_progress');
      expect(start.title, 'التقرير');
    });
  });
}
