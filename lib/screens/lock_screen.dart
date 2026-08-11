import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_lock_service.dart';

class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  bool _authenticating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryUnlock());
  }

  Future<void> _tryUnlock() async {
    final service = context.read<AppLockService>();
    setState(() {
      _authenticating = true;
      _error = null;
    });
    final ok = await service.unlock();
    if (mounted) {
      setState(() {
        _authenticating = false;
        if (!ok) _error = 'Authentication failed. Try again.';
      });
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
              Icon(Icons.lock_outline, size: 64, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 16),
              const Text(
                'PennyLedger is locked',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              if (_authenticating)
                const CircularProgressIndicator()
              else
                ElevatedButton.icon(
                  onPressed: _tryUnlock,
                  icon: const Icon(Icons.fingerprint),
                  label: const Text('Unlock'),
                ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
