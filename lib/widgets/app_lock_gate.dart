import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_lock_service.dart';
import '../screens/lock_screen.dart';

class AppLockGate extends StatefulWidget {
  final Widget child;

  const AppLockGate({super.key, required this.child});

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      context.read<AppLockService>().lock();
    }
  }

  @override
  Widget build(BuildContext context) {
    final lockService = context.watch<AppLockService>();
    if (lockService.enabled && !lockService.unlocked) {
      return const LockScreen();
    }
    return widget.child;
  }
}
