import 'package:flutter_test/flutter_test.dart';
import 'package:taskpulse_android/app.dart';

void main() {
  test('unverified Firebase users are sent to verification', () {
    expect(authRedirectForPath(configured: true, signedIn: true, emailVerified: false, path: '/home'), '/verify');
    expect(authRedirectForPath(configured: true, signedIn: true, emailVerified: true, path: '/verify'), '/home');
  });
}
