import 'dart:math' show pi;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import '../theme/app_theme.dart';
import 'auth_service.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> with SingleTickerProviderStateMixin {
  final _emailCtrl           = TextEditingController();
  final _passwordCtrl        = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  bool _loading       = false;
  bool _socialLoading = false;
  bool _usePassword   = false;
  bool _isSignUp      = false;
  String? _message;
  bool _isError = false;

  late AnimationController _buttonController;
  late Animation<double> _buttonGlow;

  @override
  void initState() {
    super.initState();
    _buttonController = AnimationController(duration: const Duration(milliseconds: 1500), vsync: this)..repeat();
    _buttonGlow = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _buttonController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _buttonController.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _signInWithSocial(Future<void> Function() signIn) async {
    setState(() { _socialLoading = true; _message = null; });
    try {
      await signIn();
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code != AuthorizationErrorCode.canceled) {
        setState(() { _message = e.message; _isError = true; });
      }
    } catch (e) {
      final msg = e.toString();
      if (!msg.contains('cancel') && !msg.contains('Cancel')) {
        setState(() { _message = msg; _isError = true; });
      }
    } finally {
      setState(() => _socialLoading = false);
    }
  }

  Future<void> _submit() async {
    setState(() { _loading = true; _message = null; });
    try {
      final auth = ref.read(authServiceProvider);
      if (_isSignUp) {
        if (_passwordCtrl.text != _confirmPasswordCtrl.text) {
          setState(() { _message = 'Passwords do not match.'; _isError = true; });
          return;
        }
        await auth.signUp(_emailCtrl.text.trim(), _passwordCtrl.text);
        setState(() { _message = 'Account created! Check your email to confirm.'; _isError = false; });
      } else if (_usePassword) {
        await auth.signInWithPassword(_emailCtrl.text.trim(), _passwordCtrl.text);
      } else {
        await auth.signInWithEmail(_emailCtrl.text.trim());
        setState(() { _message = 'Check your email for a magic link.'; _isError = false; });
      }
    } catch (e) {
      setState(() { _message = e.toString(); _isError = true; });
    } finally {
      setState(() => _loading = false);
    }
  }

  InputDecoration _fieldDecoration(String label) => InputDecoration(
    labelText: label,
    labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13),
    filled: false,
    fillColor: Colors.transparent,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: AppTheme.primary, width: 1.5),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  );

  @override
  Widget build(BuildContext context) {
    final busy = _loading || _socialLoading;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0E),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Email
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  autocorrect: false,
                  style: const TextStyle(color: Colors.white),
                  decoration: _fieldDecoration('Email address'),
                ),

                // Password
                if (_usePassword || _isSignUp) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordCtrl,
                    obscureText: true,
                    autofillHints: _isSignUp
                        ? const [AutofillHints.newPassword]
                        : const [AutofillHints.password],
                    style: const TextStyle(color: Colors.white),
                    decoration: _fieldDecoration('Password'),
                  ),
                ],

                // Confirm password (signup only)
                if (_isSignUp) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _confirmPasswordCtrl,
                    obscureText: true,
                    autofillHints: const [AutofillHints.newPassword],
                    style: const TextStyle(color: Colors.white),
                    decoration: _fieldDecoration('Confirm password'),
                  ),
                ],

                const SizedBox(height: 20),

                // Primary action button
                AnimatedBuilder(
                  animation: _buttonGlow,
                  builder: (context, child) {
                    final glowAlpha = (0.3 * (0.5 + 0.5 * (_buttonGlow.value - 0.5).abs() * 2)).clamp(0.1, 0.5);
                    return Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primary.withValues(alpha: glowAlpha),
                            blurRadius: 12 + (8 * _buttonGlow.value),
                            spreadRadius: 1 + (2 * _buttonGlow.value),
                          ),
                        ],
                      ),
                      child: child,
                    );
                  },
                  child: SizedBox(
                    height: 50,
                    child: FilledButton(
                      onPressed: busy ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _loading
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(
                              _isSignUp ? 'Create Account' : (_usePassword ? 'Sign In' : 'Send Magic Link'),
                              style: GoogleFonts.oswald(fontWeight: FontWeight.w600, fontSize: 15),
                            ),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Mode toggles
                if (!_isSignUp)
                  TextButton(
                    onPressed: () => setState(() { _usePassword = !_usePassword; _message = null; }),
                    child: Text(
                      _usePassword ? 'Use magic link instead' : 'Sign in with password instead',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ),
                TextButton(
                  onPressed: () => setState(() {
                    _isSignUp = !_isSignUp;
                    _message = null;
                    _passwordCtrl.clear();
                    _confirmPasswordCtrl.clear();
                  }),
                  child: Text(
                    _isSignUp ? 'Already have an account? Sign in' : 'Create a new account',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ),

                // Social auth
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Row(
                    children: [
                      Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.12), thickness: 1)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'or continue with',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.38), fontSize: 11, letterSpacing: 0.3),
                        ),
                      ),
                      Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.12), thickness: 1)),
                    ],
                  ),
                ),

                // Apple first — iOS HIG
                Semantics(
                  label: 'Sign in with Apple',
                  button: true,
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: SignInWithAppleButton(
                      onPressed: busy
                          ? () {}
                          : () {
                              HapticFeedback.lightImpact();
                              _signInWithSocial(ref.read(authServiceProvider).signInWithApple);
                            },
                      style: SignInWithAppleButtonStyle.whiteOutlined,
                      borderRadius: const BorderRadius.all(Radius.circular(12)),
                      text: 'Continue with Apple',
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                _GoogleSignInButton(
                  enabled: !busy,
                  onPressed: () => _signInWithSocial(ref.read(authServiceProvider).signInWithGoogle),
                ),

                if (_message != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: (_isError ? Colors.red : AppTheme.primary).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: (_isError ? Colors.red : AppTheme.primary).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      _message!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _isError ? Colors.red.shade300 : AppTheme.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Google Sign-In button ─────────────────────────────────────────────────

class _GoogleSignInButton extends StatelessWidget {
  const _GoogleSignInButton({required this.onPressed, required this.enabled});
  final VoidCallback onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Sign in with Google',
      button: true,
      child: SizedBox(
        height: 50,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: enabled
                ? () {
                    HapticFeedback.lightImpact();
                    onPressed();
                  }
                : null,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withValues(alpha: enabled ? 0.25 : 0.1),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(width: 22, height: 22, child: CustomPaint(painter: _GoogleGPainter())),
                  const SizedBox(width: 10),
                  Text(
                    'Continue with Google',
                    style: GoogleFonts.oswald(
                      color: Colors.white.withValues(alpha: enabled ? 1.0 : 0.4),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GoogleGPainter extends CustomPainter {
  const _GoogleGPainter();

  static const _blue   = Color(0xFF4285F4);
  static const _red    = Color(0xFFEA4335);
  static const _yellow = Color(0xFFFBBC05);
  static const _green  = Color(0xFF34A853);

  @override
  void paint(Canvas canvas, Size size) {
    final s  = size.width;
    final sw = s * 0.18;
    final r  = (s - sw) / 2;
    final c  = Offset(s / 2, s / 2);

    void arc(Color color, double startDeg, double sweepDeg) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        startDeg * pi / 180,
        sweepDeg * pi / 180,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = sw
          ..strokeCap = StrokeCap.butt,
      );
    }

    arc(_blue,   -20,  50);
    arc(_green,   30,  70);
    arc(_yellow, 100,  80);
    arc(_red,    180, 160);

    canvas.drawLine(
      Offset(c.dx, c.dy),
      Offset(s - sw * 0.55, c.dy),
      Paint()
        ..color = _blue
        ..strokeWidth = sw * 0.85
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_GoogleGPainter old) => false;
}
