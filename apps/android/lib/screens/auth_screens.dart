import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app.dart';
import '../config.dart';
import '../state.dart';
import '../theme.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override ConsumerState<LoginScreen> createState() => _LoginScreenState();
}
class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _showPassword = false;
  String? _error;
  @override void dispose() { _email.dispose(); _password.dispose(); super.dispose(); }
  Future<void> _login() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() { _busy = true; _error = null; });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(email: _email.text.trim(), password: _password.text);
      if (mounted) context.go('/home');
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _authError(context, e.code));
    } catch (_) { setState(() => _error = tr(context, 'تعذر تسجيل الدخول. جرّب مرة تانية.', 'Could not sign in. Please try again.')); }
    if (mounted) setState(() => _busy = false);
  }
  @override Widget build(BuildContext context) {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    return _AuthPage(title: tr(context, 'أهلاً بيك تاني', 'Welcome back'), subtitle: tr(context, 'رتّب شغلك وخلي فريقك على نفس الصفحة.', 'Keep your work moving with your team.'), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!AppConfig.firebaseConfigured || !AppConfig.apiConfigured) const _SetupCard(),
      Form(key: _form, child: Column(children: [
        TextFormField(controller: _email, keyboardType: TextInputType.emailAddress, autofillHints: const [AutofillHints.email], decoration: InputDecoration(labelText: tr(context, 'البريد الإلكتروني', 'Email address'), prefixIcon: const Icon(Icons.alternate_email)), validator: (v) => (v == null || !v.contains('@')) ? tr(context, 'اكتب بريد إلكتروني صحيح', 'Enter a valid email') : null),
        const SizedBox(height: 14),
        TextFormField(controller: _password, obscureText: !_showPassword, autofillHints: const [AutofillHints.password], decoration: InputDecoration(labelText: tr(context, 'كلمة المرور', 'Password'), prefixIcon: const Icon(Icons.lock_outline), suffixIcon: IconButton(onPressed: () => setState(() => _showPassword = !_showPassword), icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility))), validator: (v) => (v == null || v.length < 6) ? tr(context, 'كلمة المرور لازم تكون 6 أحرف على الأقل', 'Password must be at least 6 characters') : null),
      ])),
      Align(alignment: AlignmentDirectional.centerEnd, child: TextButton(onPressed: () => context.push('/forgot'), child: Text(tr(context, 'نسيت كلمة المرور؟', 'Forgot password?'))),),
      if (_error != null) _ErrorBanner(message: _error!),
      const SizedBox(height: 10),
      FilledButton(onPressed: _busy || !AppConfig.firebaseConfigured || !AppConfig.apiConfigured ? null : _login, child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(tr(context, 'تسجيل الدخول', 'Sign in'))),
      const SizedBox(height: 10),
      TextButton(onPressed: () => context.push('/register'), child: Text(tr(context, 'لسه جديد؟ اعمل حساب', 'New to Taskaty? Create an account'))),
      const SizedBox(height: 14),
      OutlinedButton.icon(onPressed: () => ref.read(localeProvider.notifier).toggle(), icon: const Icon(Icons.translate), label: Text(ar ? 'English' : 'العربية')),
    ]));
  }
}

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});
  @override ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}
class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(), _email = TextEditingController(), _password = TextEditingController();
  bool _busy = false, _accepted = true;
  String? _error;
  @override void dispose() { _name.dispose(); _email.dispose(); _password.dispose(); super.dispose(); }
  Future<void> _register() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() { _busy = true; _error = null; });
    try {
      final credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: _email.text.trim(), password: _password.text);
      await credential.user?.updateDisplayName(_name.text.trim());
      await credential.user?.sendEmailVerification();
      if (mounted) context.go('/verify');
    } on FirebaseAuthException catch (e) { setState(() => _error = _authError(context, e.code)); }
    catch (_) { setState(() => _error = tr(context, 'تعذر إنشاء الحساب. حاول تاني.', 'Account creation failed. Please try again.')); }
    if (mounted) setState(() => _busy = false);
  }
  @override Widget build(BuildContext context) => _AuthPage(title: tr(context, 'حساب جديد', 'Create your account'), subtitle: tr(context, 'ابدأ فريقك في Taskaty في دقايق.', 'Set up your Taskaty account in a minute.'), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    if (!AppConfig.firebaseConfigured || !AppConfig.apiConfigured) const _SetupCard(),
    Form(key: _form, child: Column(children: [
      TextFormField(controller: _name, textCapitalization: TextCapitalization.words, decoration: InputDecoration(labelText: tr(context, 'الاسم', 'Name'), prefixIcon: const Icon(Icons.person_outline)), validator: (v) => (v == null || v.trim().length < 2) ? tr(context, 'اكتب اسمك', 'Enter your name') : null),
      const SizedBox(height: 12),
      TextFormField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(labelText: tr(context, 'البريد الإلكتروني', 'Email address'), prefixIcon: const Icon(Icons.alternate_email)), validator: (v) => (v == null || !v.contains('@')) ? tr(context, 'اكتب بريد إلكتروني صحيح', 'Enter a valid email') : null),
      const SizedBox(height: 12),
      TextFormField(controller: _password, obscureText: true, decoration: InputDecoration(labelText: tr(context, 'كلمة المرور', 'Password'), prefixIcon: const Icon(Icons.lock_outline)), validator: (v) => (v == null || v.length < 8) ? tr(context, 'استخدم 8 أحرف أو أكثر', 'Use at least 8 characters') : null),
    ])),
    const SizedBox(height: 14),
    CheckboxListTile(value: _accepted, onChanged: (v) => setState(() => _accepted = v ?? false), contentPadding: EdgeInsets.zero, title: Text(tr(context, 'أوافق على استخدام البريد لتسجيل الدخول والتنبيهات.', 'Use my email for sign-in and task updates.'), style: Theme.of(context).textTheme.bodySmall)),
    if (_error != null) _ErrorBanner(message: _error!),
    FilledButton(onPressed: _busy || !_accepted || !AppConfig.firebaseConfigured || !AppConfig.apiConfigured ? null : _register, child: _busy ? const CircularProgressIndicator() : Text(tr(context, 'إنشاء الحساب', 'Create account'))),
    TextButton(onPressed: () => context.go('/login'), child: Text(tr(context, 'عندك حساب؟ سجل دخول', 'Already have an account? Sign in'))),
  ]));
}

class ForgotPasswordScreen extends StatefulWidget { const ForgotPasswordScreen({super.key}); @override State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState(); }
class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _email = TextEditingController(); bool _sent = false, _busy = false; String? _error;
  @override void dispose() { _email.dispose(); super.dispose(); }
  Future<void> _send() async {
    if (!_email.text.contains('@')) { setState(() => _error = tr(context, 'اكتب بريد إلكتروني صحيح', 'Enter a valid email')); return; }
    setState(() { _busy = true; _error = null; });
    try { await FirebaseAuth.instance.sendPasswordResetEmail(email: _email.text.trim()); setState(() => _sent = true); }
    on FirebaseAuthException catch (e) { setState(() => _error = _authError(context, e.code)); }
    catch (_) { setState(() => _error = tr(context, 'تعذر إرسال الرابط. حاول تاني.', 'Could not send the reset link.')); }
    if (mounted) setState(() => _busy = false);
  }
  @override Widget build(BuildContext context) => _AuthPage(title: tr(context, 'استعادة كلمة المرور', 'Reset password'), subtitle: tr(context, 'هنبعتلك رابط على بريدك الإلكتروني.', 'We will email you a password reset link.'), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(labelText: tr(context, 'البريد الإلكتروني', 'Email address'), prefixIcon: const Icon(Icons.alternate_email))),
    if (_sent) Padding(padding: const EdgeInsets.only(top: 12), child: Text(tr(context, 'لو الحساب موجود، هيوصلك رابط الاستعادة.', 'If the account exists, a reset link is on its way.'))),
    if (_error != null) _ErrorBanner(message: _error!),
    const SizedBox(height: 16), FilledButton(onPressed: _busy || !AppConfig.firebaseConfigured ? null : _send, child: _busy ? const CircularProgressIndicator() : Text(tr(context, 'إرسال الرابط', 'Send reset link'))),
    TextButton(onPressed: () => context.go('/login'), child: Text(tr(context, 'رجوع لتسجيل الدخول', 'Back to sign in'))),
  ]));
}

class VerifyEmailScreen extends StatefulWidget { const VerifyEmailScreen({super.key}); @override State<VerifyEmailScreen> createState() => _VerifyEmailScreenState(); }
class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  bool _busy = false; String? _notice;
  Future<void> _check() async { setState(() => _busy = true); await FirebaseAuth.instance.currentUser?.reload(); if (mounted) { setState(() { _busy = false; _notice = FirebaseAuth.instance.currentUser?.emailVerified == true ? tr(context, 'تم التحقق، جاري فتح التطبيق.', 'Verified. Opening Taskaty.') : tr(context, 'لسه ماوصلناش تأكيد البريد.', 'Email verification is not confirmed yet.'); }); if (FirebaseAuth.instance.currentUser?.emailVerified == true) context.go('/home'); } }
  Future<void> _resend() async { try { await FirebaseAuth.instance.currentUser?.sendEmailVerification(); setState(() => _notice = tr(context, 'بعتنا رابط تحقق جديد.', 'A new verification link has been sent.')); } catch (_) { setState(() => _notice = tr(context, 'تعذر إرسال الرابط دلوقتي.', 'Could not resend the link right now.')); } }
  @override Widget build(BuildContext context) => _AuthPage(title: tr(context, 'أكد بريدك الإلكتروني', 'Verify your email'), subtitle: tr(context, 'افتح رسالة التحقق قبل استخدام مهام الفريق.', 'Open the verification email before using team tasks.'), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    const Icon(Icons.mark_email_read_outlined, size: 50, color: TaskatyColors.cyan),
    const SizedBox(height: 12), Text(FirebaseAuth.instance.currentUser?.email ?? '', textAlign: TextAlign.center),
    if (_notice != null) Padding(padding: const EdgeInsets.all(12), child: Text(_notice!, textAlign: TextAlign.center)),
    const SizedBox(height: 18), FilledButton(onPressed: _busy ? null : _check, child: _busy ? const CircularProgressIndicator() : Text(tr(context, 'تم التحقق', 'I have verified'))),
    TextButton(onPressed: _resend, child: Text(tr(context, 'إعادة إرسال رسالة التحقق', 'Resend verification email'))),
    TextButton(onPressed: () async { await FirebaseAuth.instance.signOut(); if (context.mounted) context.go('/login'); }, child: Text(tr(context, 'تسجيل الخروج', 'Sign out'))),
  ]));
}

class _AuthPage extends StatelessWidget {
  const _AuthPage({required this.title, required this.subtitle, required this.child});
  final String title, subtitle; final Widget child;
  @override Widget build(BuildContext context) => Scaffold(body: SafeArea(child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 460), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Container(width: 64, height: 64, alignment: Alignment.center, decoration: BoxDecoration(color: TaskatyColors.cyan.withValues(alpha: .12), borderRadius: BorderRadius.circular(20)), child: const Icon(Icons.bolt, size: 36, color: TaskatyColors.cyan)),
    const SizedBox(height: 26), Text(title, style: Theme.of(context).textTheme.headlineMedium), const SizedBox(height: 8), Text(subtitle, style: Theme.of(context).textTheme.bodyMedium), const SizedBox(height: 26), child,
  ]))))));
}

class _SetupCard extends StatelessWidget { const _SetupCard(); @override Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
  Text(tr(context, 'الإعداد محتاج تهيئة', 'Setup required'), style: Theme.of(context).textTheme.titleMedium),
  const SizedBox(height: 6), Text(tr(context, 'التطبيق متوصلش بخدمات Firebase والـ API لسه. أضف مفاتيح Firebase وTASKPULSE_API_URL حسب DEPLOYMENT.md قبل تفعيل الحسابات.', 'Firebase and the TaskPulse API are not configured yet. Add Firebase options and TASKPULSE_API_URL as described in DEPLOYMENT.md.'), style: Theme.of(context).textTheme.bodySmall),
  if (AppConfig.firebaseInitError != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(AppConfig.firebaseInitError!, style: const TextStyle(color: TaskatyColors.amber))),
  const SizedBox(height: 8), Text('Firebase: ${AppConfig.firebaseConfigured ? '✓' : '—'}   API: ${AppConfig.apiConfigured ? '✓' : '—'}', style: const TextStyle(color: TaskatyColors.amber)),
]))); }

class _ErrorBanner extends StatelessWidget { const _ErrorBanner({required this.message}); final String message; @override Widget build(BuildContext context) => Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFF4A222B), borderRadius: BorderRadius.circular(12)), child: Text(message, style: const TextStyle(color: Color(0xFFFFB6B6)))); }

String _authError(BuildContext context, String code) => switch (code) {
  'email-already-in-use' => tr(context, 'البريد ده مستخدم بالفعل.', 'That email is already in use.'),
  'invalid-email' => tr(context, 'البريد الإلكتروني غير صحيح.', 'The email address is invalid.'),
  'weak-password' => tr(context, 'اختار كلمة مرور أقوى.', 'Choose a stronger password.'),
  'user-not-found' || 'wrong-password' || 'invalid-credential' => tr(context, 'البريد أو كلمة المرور غير صحيحة.', 'Email or password is incorrect.'),
  'too-many-requests' => tr(context, 'محاولات كتير. استنى شوية وجرب تاني.', 'Too many attempts. Wait a bit and try again.'),
  'network-request-failed' => tr(context, 'مفيش اتصال بالإنترنت.', 'No internet connection.'),
  _ => tr(context, 'حصلت مشكلة في الحساب. حاول تاني.', 'There was a problem with your account.'),
};
