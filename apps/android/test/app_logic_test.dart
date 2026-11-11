import 'package:flutter_test/flutter_test.dart';
import 'package:taskpulse_android/app.dart';
import 'package:taskpulse_android/task_form_validation.dart';
import 'package:taskpulse_android/screens/common.dart';

void main() {
  group('authentication routing', () {
    test('routes signed-out users to login', () {
      expect(authRedirectForPath(configured: true, signedIn: false, emailVerified: false, path: '/tasks'), '/login');
      expect(authRedirectForPath(configured: true, signedIn: false, emailVerified: false, path: '/login'), isNull);
    });
    test('requires email verification and returns verified users to the app', () {
      expect(authRedirectForPath(configured: true, signedIn: true, emailVerified: false, path: '/tasks'), '/verify');
      expect(authRedirectForPath(configured: true, signedIn: true, emailVerified: true, path: '/login'), '/home');
    });
    test('does not pretend auth works when Firebase is unconfigured', () {
      expect(authRedirectForPath(configured: false, signedIn: false, emailVerified: false, path: '/home'), '/login');
    });
  });

  group('task form validation', () {
    test('requires a title and checks custom durations', () {
      expect(validateTaskTitle('   '), 'اكتب عنوان المهمة');
      expect(validateTaskTitle('Review proposal'), isNull);
      expect(parseDurationMinutes('240'), 240);
      expect(parseDurationMinutes('0'), isNull);
      expect(parseDurationMinutes('525601'), isNull);
      expect(parseDurationMinutes('abc'), isNull);
    });
  });

  group('countdown formatting', () {
    test('formats days, hours, minutes, and expired values', () {
      expect(countdownText(const Duration(days: 1, hours: 2, minutes: 10)), '1d 2h');
      expect(countdownText(const Duration(hours: 3, minutes: 8)), '3h 8m');
      expect(countdownText(const Duration(minutes: 42)), '42m');
      expect(countdownText(const Duration(seconds: -10)), '0m');
    });
  });
}
