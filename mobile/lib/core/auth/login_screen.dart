import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import 'auth_service.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading    = false;
  bool _usePassword = false;
  String? _message;
  bool _isError = false;

  Future<void> _signIn() async {
    setState(() { _loading = true; _message = null; });
    try {
      final auth = ref.read(authServiceProvider);
      if (_usePassword) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.primary,
      body: SafeArea(
        child: Column(
          children: [
            // Brand header
            Expanded(
              flex: 2,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Center(
                        child: Text('CV', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, fontFamily: 'Inter')),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('Card Vault', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700, fontFamily: 'Inter')),
                    const SizedBox(height: 6),
                    Text('Collection Manager', style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 14, fontFamily: 'Inter')),
                  ],
                ),
              ),
            ),

            // Form card
            Container(
              decoration: const BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _usePassword ? 'Sign In' : 'Magic Link',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppTheme.textMain, fontFamily: 'Inter'),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _usePassword ? 'Enter your email and password.' : "We'll email you a sign-in link.",
                    style: const TextStyle(fontSize: 13, color: AppTheme.textMuted, fontFamily: 'Inter'),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: const InputDecoration(labelText: 'Email address'),
                  ),
                  if (_usePassword) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passwordCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Password'),
                    ),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 48,
                    child: FilledButton(
                      onPressed: _loading ? null : _signIn,
                      child: _loading
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(_usePassword ? 'Sign In' : 'Send Magic Link'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => setState(() { _usePassword = !_usePassword; _message = null; }),
                    child: Text(
                      _usePassword ? 'Use magic link instead' : 'Sign in with password instead',
                      style: const TextStyle(color: AppTheme.primary, fontSize: 13),
                    ),
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _message!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _isError ? Colors.red : AppTheme.primary, fontSize: 13),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
