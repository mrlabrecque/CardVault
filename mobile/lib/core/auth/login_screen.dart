import 'dart:math' show pi;
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import '../theme/app_theme.dart';
import 'auth_service.dart';

// ── Segment indices ───────────────────────────────────────────────────────────
enum _AuthMode { login, createAccount }

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _emailCtrl           = TextEditingController();
  final _passwordCtrl        = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();

  _AuthMode _mode         = _AuthMode.login;
  bool      _loading      = false;
  bool      _socialLoading = false;
  String?   _message;
  bool      _isError      = false;

  late AnimationController _glowCtrl;
  late Animation<double>   _glowAnim;

  @override
  void initState() {
    super.initState();
    _glowCtrl = AnimationController(
      duration: const Duration(milliseconds: 1800),
      vsync: this,
    )..repeat(reverse: true);
    _glowAnim = CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _glowCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  void _switchMode(_AuthMode mode) {
    if (mode == _mode) return;
    HapticFeedback.selectionClick();
    setState(() {
      _mode    = mode;
      _message = null;
      _passwordCtrl.clear();
      _confirmPasswordCtrl.clear();
    });
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
      if (mounted) setState(() => _socialLoading = false);
    }
  }

  Future<void> _submitPassword() async {
    setState(() { _loading = true; _message = null; });
    try {
      final auth = ref.read(authServiceProvider);
      if (_mode == _AuthMode.createAccount) {
        if (_passwordCtrl.text != _confirmPasswordCtrl.text) {
          setState(() { _message = 'Passwords do not match.'; _isError = true; });
          return;
        }
        await auth.signUp(_emailCtrl.text.trim(), _passwordCtrl.text);
        setState(() { _message = 'Account created! Check your email to confirm.'; _isError = false; });
      } else {
        await auth.signInWithPassword(_emailCtrl.text.trim(), _passwordCtrl.text);
      }
    } catch (e) {
      setState(() { _message = e.toString(); _isError = true; });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submitMagicLink() async {
    setState(() { _loading = true; _message = null; });
    try {
      await ref.read(authServiceProvider).signInWithEmail(_emailCtrl.text.trim());
      setState(() { _message = 'Magic link sent! Check your email.'; _isError = false; });
    } catch (e) {
      setState(() { _message = e.toString(); _isError = true; });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  InputDecoration _fieldDeco(String label, {IconData? icon}) => InputDecoration(
    labelText: label,
    labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 13),
    prefixIcon: icon != null
        ? Icon(icon, size: 18, color: Colors.white.withValues(alpha: 0.35))
        : null,
    filled: true,
    fillColor: Colors.white.withValues(alpha: 0.05),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
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
                _Branding(),
                const SizedBox(height: 32),
                _SegmentedControl(
                  selected: _mode,
                  onChanged: busy ? null : _switchMode,
                ),
                const SizedBox(height: 24),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.04),
                        end: Offset.zero,
                      ).animate(anim),
                      child: child,
                    ),
                  ),
                  child: _mode == _AuthMode.login
                      ? _LoginForm(
                          key: const ValueKey('login'),
                          emailCtrl: _emailCtrl,
                          passwordCtrl: _passwordCtrl,
                          busy: busy,
                          loading: _loading,
                          fieldDeco: _fieldDeco,
                          glowAnim: _glowAnim,
                          onSignIn: _submitPassword,
                          onMagicLink: _submitMagicLink,
                        )
                      : _CreateAccountForm(
                          key: const ValueKey('create'),
                          emailCtrl: _emailCtrl,
                          passwordCtrl: _passwordCtrl,
                          confirmCtrl: _confirmPasswordCtrl,
                          busy: busy,
                          loading: _loading,
                          fieldDeco: _fieldDeco,
                          glowAnim: _glowAnim,
                          onSubmit: _submitPassword,
                        ),
                ),
                const SizedBox(height: 28),
                _Divider(),
                const SizedBox(height: 20),
                // Apple first per iOS HIG
                Semantics(
                  label: 'Sign in with Apple',
                  button: true,
                  child: SizedBox(
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
                  const SizedBox(height: 20),
                  _MessageBanner(message: _message!, isError: _isError),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Branding ──────────────────────────────────────────────────────────────────

class _Branding extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Logo mark
        Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                AppTheme.primary.withValues(alpha: 0.85),
                AppTheme.primaryDark.withValues(alpha: 0.5),
              ],
              center: Alignment.topLeft,
              radius: 1.4,
            ),
            border: Border.all(
              color: AppTheme.primary.withValues(alpha: 0.4),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withValues(alpha: 0.35),
                blurRadius: 24,
                spreadRadius: 2,
              ),
            ],
          ),
          child: const Icon(Icons.style_rounded, color: Colors.white, size: 32),
        ),
        const SizedBox(height: 16),
        Text(
          'CARD LOCKER',
          style: GoogleFonts.oswald(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.w700,
            letterSpacing: 3,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Your collection. Your value.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.38),
            fontSize: 12,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

// ── Segmented control ─────────────────────────────────────────────────────────

class _SegmentedControl extends StatelessWidget {
  const _SegmentedControl({required this.selected, this.onChanged});
  final _AuthMode selected;
  final void Function(_AuthMode)? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final segW = (constraints.maxWidth - 6) / 2;
          final offset = selected == _AuthMode.login ? 0.0 : segW;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOut,
                left: offset,
                top: 0,
                bottom: 0,
                width: segW,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primary.withValues(alpha: 0.45),
                        blurRadius: 10,
                        spreadRadius: 0,
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  _Segment(
                    label: 'Login',
                    active: selected == _AuthMode.login,
                    onTap: () => onChanged?.call(_AuthMode.login),
                  ),
                  _Segment(
                    label: 'Create Account',
                    active: selected == _AuthMode.createAccount,
                    onTap: () => onChanged?.call(_AuthMode.createAccount),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({required this.label, required this.active, required this.onTap});
  final String   label;
  final bool     active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: GoogleFonts.oswald(
              fontSize: 13,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              color: active ? Colors.white : Colors.white.withValues(alpha: 0.45),
              letterSpacing: 0.4,
            ),
            child: Text(label),
          ),
        ),
      ),
    );
  }
}

// ── Login form ────────────────────────────────────────────────────────────────

class _LoginForm extends StatelessWidget {
  const _LoginForm({
    super.key,
    required this.emailCtrl,
    required this.passwordCtrl,
    required this.busy,
    required this.loading,
    required this.fieldDeco,
    required this.glowAnim,
    required this.onSignIn,
    required this.onMagicLink,
  });

  final TextEditingController emailCtrl;
  final TextEditingController passwordCtrl;
  final bool busy;
  final bool loading;
  final InputDecoration Function(String, {IconData? icon}) fieldDeco;
  final Animation<double> glowAnim;
  final VoidCallback onSignIn;
  final VoidCallback onMagicLink;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdaptiveTextField(
          controller: emailCtrl,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autocorrect: false,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          placeholder: 'Email address',
          prefixIcon: const Icon(Icons.mail_outline_rounded),
          style: const TextStyle(color: Colors.white, fontSize: 15),
          decoration: fieldDeco('Email address', icon: Icons.mail_outline_rounded),
        ),
        const SizedBox(height: 12),
        AdaptiveTextField(
          controller: passwordCtrl,
          obscureText: true,
          textInputAction: TextInputAction.done,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          placeholder: 'Password',
          prefixIcon: const Icon(Icons.lock_outline_rounded),
          style: const TextStyle(color: Colors.white, fontSize: 15),
          decoration: fieldDeco('Password', icon: Icons.lock_outline_rounded),
          onSubmitted: (_) { if (!busy) onSignIn(); },
        ),
        const SizedBox(height: 20),
        // Primary: Sign In
        _GlowButton(
          label: 'Sign In',
          loading: loading,
          enabled: !busy,
          glowAnim: glowAnim,
          onPressed: onSignIn,
        ),
        const SizedBox(height: 10),
        // Secondary: Magic Link
        _MagicLinkButton(enabled: !busy, onPressed: onMagicLink),
      ],
    );
  }
}

// ── Create account form ───────────────────────────────────────────────────────

class _CreateAccountForm extends StatelessWidget {
  const _CreateAccountForm({
    super.key,
    required this.emailCtrl,
    required this.passwordCtrl,
    required this.confirmCtrl,
    required this.busy,
    required this.loading,
    required this.fieldDeco,
    required this.glowAnim,
    required this.onSubmit,
  });

  final TextEditingController emailCtrl;
  final TextEditingController passwordCtrl;
  final TextEditingController confirmCtrl;
  final bool busy;
  final bool loading;
  final InputDecoration Function(String, {IconData? icon}) fieldDeco;
  final Animation<double> glowAnim;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdaptiveTextField(
          controller: emailCtrl,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autocorrect: false,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          placeholder: 'Email address',
          prefixIcon: const Icon(Icons.mail_outline_rounded),
          style: const TextStyle(color: Colors.white, fontSize: 15),
          decoration: fieldDeco('Email address', icon: Icons.mail_outline_rounded),
        ),
        const SizedBox(height: 12),
        AdaptiveTextField(
          controller: passwordCtrl,
          obscureText: true,
          textInputAction: TextInputAction.next,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          placeholder: 'Password',
          prefixIcon: const Icon(Icons.lock_outline_rounded),
          style: const TextStyle(color: Colors.white, fontSize: 15),
          decoration: fieldDeco('Password', icon: Icons.lock_outline_rounded),
        ),
        const SizedBox(height: 12),
        AdaptiveTextField(
          controller: confirmCtrl,
          obscureText: true,
          textInputAction: TextInputAction.done,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          placeholder: 'Confirm password',
          prefixIcon: const Icon(Icons.lock_outline_rounded),
          style: const TextStyle(color: Colors.white, fontSize: 15),
          decoration: fieldDeco('Confirm password', icon: Icons.lock_outline_rounded),
          onSubmitted: (_) { if (!busy) onSubmit(); },
        ),
        const SizedBox(height: 20),
        _GlowButton(
          label: 'Create Account',
          loading: loading,
          enabled: !busy,
          glowAnim: glowAnim,
          onPressed: onSubmit,
        ),
      ],
    );
  }
}

// ── Shared button widgets ─────────────────────────────────────────────────────

class _GlowButton extends StatelessWidget {
  const _GlowButton({
    required this.label,
    required this.loading,
    required this.enabled,
    required this.glowAnim,
    required this.onPressed,
  });
  final String label;
  final bool loading;
  final bool enabled;
  final Animation<double> glowAnim;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: glowAnim,
      builder: (context, child) {
        final pulse = 0.2 + 0.25 * glowAnim.value;
        return Container(
          height: 50,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: AppTheme.primary.withValues(alpha: pulse),
                      blurRadius: 14 + 8 * glowAnim.value,
                      spreadRadius: 0,
                    ),
                  ]
                : null,
          ),
          child: child,
        );
      },
      child: SizedBox(
        height: 50,
        child: AdaptiveButton.child(
          onPressed: enabled ? onPressed : null,
          style: AdaptiveButtonStyle.filled,
          color: AppTheme.primary,
          child: loading
              ? const SizedBox(
                  height: 20, width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(
                  label,
                  style: GoogleFonts.oswald(fontWeight: FontWeight.w600, fontSize: 15, letterSpacing: 0.5),
                ),
        ),
      ),
    );
  }
}

class _MagicLinkButton extends StatelessWidget {
  const _MagicLinkButton({required this.enabled, required this.onPressed});
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: AdaptiveButton.child(
        onPressed: enabled ? () { HapticFeedback.lightImpact(); onPressed(); } : null,
        style: AdaptiveButtonStyle.bordered,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.auto_awesome_rounded, size: 16, color: Colors.white.withValues(alpha: 0.7)),
            const SizedBox(width: 8),
            Text(
              'Send Magic Link',
              style: GoogleFonts.oswald(
                fontWeight: FontWeight.w500,
                fontSize: 14,
                letterSpacing: 0.3,
                color: Colors.white.withValues(alpha: enabled ? 0.85 : 0.35),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Divider ───────────────────────────────────────────────────────────────────

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.1), thickness: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            'or continue with',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.32),
              fontSize: 11,
              letterSpacing: 0.3,
            ),
          ),
        ),
        Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.1), thickness: 1)),
      ],
    );
  }
}

// ── Message banner ────────────────────────────────────────────────────────────

class _MessageBanner extends StatelessWidget {
  const _MessageBanner({required this.message, required this.isError});
  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color = isError ? Colors.red : AppTheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Icon(
            isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
            size: 16,
            color: isError ? Colors.red.shade300 : AppTheme.primaryLight,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: isError ? Colors.red.shade300 : AppTheme.primaryLight,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Google Sign-In button ─────────────────────────────────────────────────────

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
                  color: Colors.white.withValues(alpha: enabled ? 0.22 : 0.08),
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

// ── Google "G" painter ────────────────────────────────────────────────────────

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
