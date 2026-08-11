import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppLockService extends ChangeNotifier {
  static const _prefsKey = 'app_lock_enabled';

  final LocalAuthentication _auth = LocalAuthentication();
  bool _enabled = false;
  bool _unlocked = false;

  bool get enabled => _enabled;
  bool get unlocked => _unlocked;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_prefsKey) ?? false;
    notifyListeners();
  }

  Future<bool> canUseAppLock() async {
    final canCheck = await _auth.canCheckBiometrics;
    final isSupported = await _auth.isDeviceSupported();
    return canCheck || isSupported;
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    if (!value) _unlocked = true;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, value);
  }

  void lock() {
    if (!_enabled) return;
    _unlocked = false;
    notifyListeners();
  }

  Future<bool> unlock() async {
    try {
      final result = await _auth.authenticate(
        localizedReason: 'Unlock PennyLedger',
        options: const AuthenticationOptions(biometricOnly: false, stickyAuth: true),
      );
      if (result) {
        _unlocked = true;
        notifyListeners();
      }
      return result;
    } catch (_) {
      return false;
    }
  }
}
