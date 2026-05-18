import 'package:flutter/material.dart';
import 'login_screen.dart';

// The router maps /signup → LoginScreen(startOnSignup: true) directly.
// This class exists as a named alias so any in-app push to SignupScreen
// resolves correctly without importing the router.
class SignupScreen extends StatelessWidget {
  const SignupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const LoginScreen(startOnSignup: true);
  }
}
