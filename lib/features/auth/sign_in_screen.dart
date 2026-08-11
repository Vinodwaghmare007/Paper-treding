import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/repositories/auth_repository.dart';
import '../../l10n/generated/app_localizations.dart';
import '../puzzle/daily_puzzle_screen.dart';
import 'auth_providers.dart';

enum _Mode { signIn, signUp }

/// Overridable at build time in case the GitHub Pages source/branch ever
/// changes: flutter build ... --dart-define=PRIVACY_POLICY_URL=https://...
/// Default assumes GitHub Pages is enabled for this repo with "Deploy
/// from a branch: main /docs" (see docs/RELEASE.md) — verify this
/// resolves before publishing; a broken privacy-policy link is a Play
/// Store rejection, not just a bad look.
const _privacyPolicyUrl = String.fromEnvironment(
  'PRIVACY_POLICY_URL',
  defaultValue: 'https://vinodwaghmare007.github.io/Paper-treding/privacy-policy.html',
);

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _inviteCodeController = TextEditingController();
  _Mode _mode = _Mode.signIn;
  bool _submitting = false;
  String? _errorText;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _inviteCodeController.dispose();
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
        final result = await repo.signUpWithEmail(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          inviteOrReferralCode: _inviteCodeController.text,
        );
        _showRedemptionSnackBar(result);
      }
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _errorText = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showRedemptionSnackBar(InviteCodeRedemptionResult? result) {
    if (result == null || !mounted) return;
    final l10n = AppLocalizations.of(context)!;
    final message = switch (result) {
      InviteCodeRedemptionResult(kind: RedeemedCodeKind.orgInvite) =>
        l10n.signInInviteCodeAppliedOrg,
      InviteCodeRedemptionResult(kind: RedeemedCodeKind.referral) =>
        l10n.signInInviteCodeAppliedReferral,
      InviteCodeRedemptionResult(errorMessage: final error?) =>
        l10n.signInInviteCodeFailed(error),
      _ => null,
    };
    if (message == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
    final l10n = AppLocalizations.of(context)!;
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
                    l10n.appTitle,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.disclaimerEducationalSimulator,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: InputDecoration(
                      labelText: l10n.signInEmailLabel,
                      border: const OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || !value.contains('@')) {
                        return l10n.signInEmailInvalid;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    decoration: InputDecoration(
                      labelText: l10n.signInPasswordLabel,
                      border: const OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.length < 6) {
                        return l10n.signInPasswordTooShort;
                      }
                      return null;
                    },
                    onFieldSubmitted: (_) => _submitEmailForm(),
                  ),
                  if (isSignUp) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _inviteCodeController,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        labelText: l10n.signInInviteCodeLabel,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ],
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
                        : Text(isSignUp
                            ? l10n.signInButtonCreateAccount
                            : l10n.signInButtonSignIn),
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
                          ? l10n.signInToggleToSignIn
                          : l10n.signInToggleToSignUp,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(l10n.signInOrDivider,
                          style: const TextStyle(color: Colors.white38)),
                    ),
                    const Expanded(child: Divider()),
                  ]),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _submitting ? null : _submitGoogle,
                    icon: const Icon(Icons.g_mobiledata, size: 28),
                    label: Text(l10n.signInContinueWithGoogle),
                  ),
                  const SizedBox(height: 20),
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const DailyPuzzleScreen(),
                      ),
                    ),
                    icon: const Icon(Icons.extension, size: 18),
                    label: Text(l10n.signInTryTodaysPuzzle),
                  ),
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: () => launchUrl(
                      Uri.parse(_privacyPolicyUrl),
                      mode: LaunchMode.inAppBrowserView,
                    ),
                    child: Text(
                      l10n.signInPrivacyPolicy,
                      // white70, not white38 — see the contrast note on
                      // SimulatedFooter; a link needs to actually be
                      // readable, not just technically present.
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
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
