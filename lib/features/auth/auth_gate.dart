import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_providers.dart';
import 'sign_in_screen.dart';

/// Shows [signedIn] once a user is authenticated, [SignInScreen] otherwise.
/// Every screen that reads [currentUidProvider] must live beneath this
/// widget so that provider is guaranteed non-null.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key, required this.signedIn});

  final WidgetBuilder signedIn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateChangesProvider);
    return authState.when(
      data: (user) =>
          user == null ? const SignInScreen() : signedIn(context),
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        body: Center(
          child: Text(
            'Auth error: $error',
            style: const TextStyle(color: Color(0xFFEF5350)),
          ),
        ),
      ),
    );
  }
}
