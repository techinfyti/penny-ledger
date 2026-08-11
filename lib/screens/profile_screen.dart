import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = context.read<AuthService>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('My Profile')),
      body: SafeArea(
        child: StreamBuilder<User?>(
          stream: authService.userChanges,
          initialData: authService.currentUser,
          builder: (context, snapshot) {
            final user = snapshot.data;
            final photoUrl = user?.photoURL;
            final name = user?.displayName ?? 'PennyLedger User';
            final email = user?.email ?? '';
            final createdAt = user?.metadata.creationTime;

            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 48,
                    backgroundColor: scheme.primary.withOpacity(0.15),
                    backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
                    child: photoUrl == null
                        ? Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: scheme.primary),
                          )
                        : null,
                  ),
                  const SizedBox(height: 16),
                  Text(name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  if (email.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(email, style: TextStyle(color: scheme.onSurfaceVariant)),
                  ],
                  const SizedBox(height: 28),
                  Card(
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.mail_outline),
                          title: const Text('Email'),
                          subtitle: Text(email.isNotEmpty ? email : 'Not available'),
                        ),
                        const Divider(height: 1),
                        const ListTile(
                          leading: Icon(Icons.verified_user_outlined),
                          title: Text('Signed in with'),
                          subtitle: Text('Google'),
                        ),
                        if (createdAt != null) ...[
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.calendar_today_outlined),
                            title: const Text('Member since'),
                            subtitle: Text(DateFormat('MMM d, yyyy').format(createdAt)),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
