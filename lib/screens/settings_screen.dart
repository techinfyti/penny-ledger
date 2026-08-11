import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../services/app_lock_service.dart';
import '../services/auth_service.dart';
import '../services/drive_backup_service.dart';
import '../services/premium_service.dart';
import '../services/theme_service.dart';
import 'accounts_screen.dart';
import 'customer_support_screen.dart';
import 'faq_screen.dart';
import 'groups_screen.dart';
import 'manage_categories_screen.dart';
import 'premium_screen.dart';
import 'profile_screen.dart';

class SettingsScreen extends StatefulWidget {
  final String uid;

  const SettingsScreen({super.key, required this.uid});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busy = false;
  bool _backingUp = false;
  bool _restoring = false;
  DateTime? _lastBackupAt;

  Future<void> _referApp() async {
    await Share.share(
      "Check out PennyLedger — a simple way to track your daily expenses and manage your budget!\n\n"
      'https://play.google.com/store/apps/details?id=com.techinfy.pennyledger',
      subject: 'Try PennyLedger',
    );
  }

  Future<void> _toggleAppLock(bool value) async {
    final lockService = context.read<AppLockService>();
    if (value) {
      setState(() => _busy = true);
      final available = await lockService.canUseAppLock();
      setState(() => _busy = false);
      if (!available) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Set up a screen lock (PIN, pattern, or fingerprint) on your phone first'),
            ),
          );
        }
        return;
      }
    }
    await lockService.setEnabled(value);
  }

  Future<void> _openThemePicker() async {
    final themeService = context.read<ThemeService>();
    final selected = await showModalBottomSheet<AppThemeColor>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Theme color', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            for (final color in supportedThemeColors)
              ListTile(
                leading: CircleAvatar(backgroundColor: color.seed),
                title: Text(color.label),
                trailing: themeService.color.id == color.id ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(context).pop(color),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (selected != null) {
      await themeService.setColor(selected);
    }
  }

  Future<void> _backup() async {
    final isPremium = context.read<PremiumService>().isPremium;
    if (!isPremium) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PremiumScreen(uid: widget.uid)),
      );
      return;
    }
    final driveService = context.read<DriveBackupService>();
    setState(() => _backingUp = true);
    try {
      final at = await driveService.backup(widget.uid);
      if (mounted) {
        setState(() => _lastBackupAt = at);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backed up to Google Drive')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backup failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _backingUp = false);
    }
  }

  Future<void> _restore() async {
    final isPremium = context.read<PremiumService>().isPremium;
    if (!isPremium) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PremiumScreen(uid: widget.uid)),
      );
      return;
    }
    final driveService = context.read<DriveBackupService>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore from Google Drive?'),
        content: const Text(
          'This will restore transactions, categories, budgets, and recurring items from your '
          'last Drive backup. Existing entries with the same ID will be overwritten; nothing else is deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _restoring = true);
    try {
      await driveService.restore(widget.uid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Restore complete')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Restore failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lockEnabled = context.watch<AppLockService>().enabled;
    final isPremium = context.watch<PremiumService>().isPremium;
    final themeColor = context.watch<ThemeService>().color;

    final authService = context.read<AuthService>();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: StreamBuilder<User?>(
              stream: authService.userChanges,
              initialData: authService.currentUser,
              builder: (context, snapshot) {
                final user = snapshot.data;
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      radius: 24,
                      backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.15),
                      backgroundImage: user?.photoURL != null ? NetworkImage(user!.photoURL!) : null,
                      child: user?.photoURL == null
                          ? Text(
                              (user?.displayName?.isNotEmpty ?? false) ? user!.displayName![0].toUpperCase() : '?',
                              style:
                                  TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary),
                            )
                          : null,
                    ),
                    title: Text(user?.displayName ?? 'PennyLedger User'),
                    subtitle: Text(user?.email ?? ''),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const ProfileScreen()),
                      );
                    },
                  ),
                );
              },
            ),
          ),
          if (!isPremium)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: ListTile(
                  leading: const Icon(Icons.workspace_premium),
                  title: const Text('Upgrade to Premium'),
                  subtitle: const Text('Multiple accounts · Cloud backup · Ad-free · CSV export'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => PremiumScreen(uid: widget.uid)),
                    );
                  },
                ),
              ),
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Accounts', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          ListTile(
            leading: const Icon(Icons.account_balance_wallet_outlined),
            title: const Text('Manage Accounts'),
            subtitle: const Text('Switch or add expense accounts'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => AccountsScreen(uid: widget.uid)),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.groups_outlined),
            title: const Text('Manage Groups'),
            subtitle: const Text('Tag transactions by family, friends, or team'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => GroupsScreen(uid: widget.uid)),
              );
            },
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('Appearance', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          ListTile(
            leading: CircleAvatar(backgroundColor: themeColor.seed, radius: 12),
            title: const Text('Theme Color'),
            subtitle: Text(themeColor.label),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openThemePicker,
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('Security', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.lock_outline),
            title: const Text('App Lock'),
            subtitle: const Text('Require fingerprint, face, or device PIN to open the app'),
            value: lockEnabled,
            onChanged: _busy ? null : _toggleAppLock,
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('Categories', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          ListTile(
            leading: const Icon(Icons.category_outlined),
            title: const Text('Manage Categories'),
            subtitle: const Text('Rename categories you\'ve added'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => ManageCategoriesScreen(uid: widget.uid)),
              );
            },
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                const Text('Backup', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                if (!isPremium) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.workspace_premium, size: 14, color: Theme.of(context).colorScheme.primary),
                ],
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.backup_outlined),
            title: const Text('Backup to Google Drive'),
            subtitle: Text(
              _lastBackupAt != null
                  ? 'Last backup: ${DateFormat('MMM d, yyyy h:mm a').format(_lastBackupAt!)}'
                  : (isPremium ? 'Save all your data to your Google Drive' : 'Premium feature — tap to unlock'),
            ),
            trailing: _backingUp
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : null,
            onTap: _backingUp || _restoring ? null : _backup,
          ),
          ListTile(
            leading: const Icon(Icons.restore_outlined),
            title: const Text('Restore from Google Drive'),
            subtitle: Text(isPremium ? 'Bring back data from your last Drive backup' : 'Premium feature — tap to unlock'),
            trailing: _restoring
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : null,
            onTap: _backingUp || _restoring ? null : _restore,
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('Share', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          ListTile(
            leading: const Icon(Icons.share_outlined),
            title: const Text('Refer to Friends'),
            subtitle: const Text('Share PennyLedger with friends and family'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _referApp,
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('Help', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('FAQ'),
            subtitle: const Text('Common questions about PennyLedger'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const FaqScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.support_agent_outlined),
            title: const Text('Customer Support'),
            subtitle: const Text('Get help from our team'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CustomerSupportScreen()),
              );
            },
          ),
        ],
      ),
    );
  }
}
