import 'package:flutter/material.dart';
import '../screens/settings_screen.dart';

class SettingsButton extends StatelessWidget {
  final String uid;

  const SettingsButton({super.key, required this.uid});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.settings_outlined),
      tooltip: 'Settings',
      onPressed: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => SettingsScreen(uid: uid)),
        );
      },
    );
  }
}
