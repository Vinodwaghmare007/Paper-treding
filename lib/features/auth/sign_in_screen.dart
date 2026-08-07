import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/auth_repository.dart';
import '../puzzle/daily_puzzle_screen.dart';
import 'auth_providers.dart';

enum _Mode { signIn, signUp }

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  _Mode _mode = _Mode.signIn;
  bool _submitting = false;
  String? _errorText;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submitEmailForm() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _errorText = null;
    });
    final repo = ref.read(authRepositoryProvider);
    try {
      if (_mode == _Mode.signIn) {
        await repo.signInWithEmail(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      } else {
        await repo.signUpWithEmail(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      }
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _errorText = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _submitGoogle() async {
    setState(() {
      _submitting = true;
      _errorText = null;
    });
    try {
      await ref.read(authRepositoryProvider).signInWithGoogle();
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _errorText = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSignUp = _mode == _Mode.signUp;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.candlestick_chart,
                      size: 56, color: Color(0xFF26A69A)),
                  const SizedBox(height: 12),
                  Text(
                    'Crypto Paper Trader',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Educational simulator — no real funds involved.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || !value.contains('@')) {
                        return 'Enter a valid email';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.length < 6) {
                        return 'At least 6 characters';
                      }
                      return null;
                    },
                    onFieldSubmitted: (_) => _submitEmailForm(),
                  ),
                  if (_errorText != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _errorText!,
                      style: const TextStyle(color: Color(0xFFEF5350)),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _submitting ? null : _submitEmailForm,
                    child: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(isSignUp ? 'Create account' : 'Sign in'),
                  ),
                  TextButton(
                    onPressed: _submitting
                        ? null
                        : () => setState(() {
                              _mode =
                                  isSignUp ? _Mode.signIn : _Mode.signUp;
                              _errorText = null;
                            }),
                    child: Text(
                      isSignUp
                          ? 'Already have an account? Sign in'
                          : "Don't have an account? Create one",
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Row(children: [
                    Expanded(child: Divider()),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('OR', style: TextStyle(color: Colors.white38)),
                    ),
                    Expanded(child: Divider()),
                  ]),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _submitting ? null : _submitGoogle,
                    icon: const Icon(Icons.g_mobiledata, size: 28),
                    label: const Text('Continue with Google'),
                  ),
                  const SizedBox(height: 20),
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const DailyPuzzleScreen(),
                      ),
                    ),
                    icon: const Icon(Icons.extension, size: 18),
                    label: const Text("Just want to try today's puzzle?"),
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
