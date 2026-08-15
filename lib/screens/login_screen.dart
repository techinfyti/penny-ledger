import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _signingIn = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() {
      _signingIn = true;
      _error = null;
    });
    try {
      final auth = context.read<AuthService>();
      final result = await _signInWithRetry(auth);
      if (result == null && mounted) {
        setState(() => _error = 'Sign-in was cancelled.');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Sign-in failed: $e');
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  /// Google Play Services can throw a transient "main thread deadlock"
  /// PlatformException on the very first sign-in for a Google account that
  /// was only just added to the device, before it's fully synced locally.
  /// Retrying once after a brief pause resolves it without surfacing the
  /// error to the user.
  Future<dynamic> _signInWithRetry(AuthService auth) async {
    try {
      return await auth.signInWithGoogle();
    } catch (e) {
      if (e.toString().contains('deadlock')) {
        await Future.delayed(const Duration(milliseconds: 800));
        return auth.signInWithGoogle();
      }
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.asset(
                  'assets/logo.png',
                  width: 120,
                  height: 120,
                  fit: BoxFit.cover,
                  // Decode at the size it's actually displayed, not the source's
                  // full 1254x1254 resolution — cuts memory use substantially.
                  cacheWidth: 360,
                  cacheHeight: 360,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'PennyLedger',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Track your daily, monthly & yearly spending',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 32),
              if (_signingIn)
                const CircularProgressIndicator()
              else
                ElevatedButton.icon(
                  onPressed: _signIn,
                  icon: const Icon(Icons.login),
                  label: const Text('Sign in with Google'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  ),
                ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
