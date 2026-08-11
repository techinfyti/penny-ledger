import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/group.dart';
import '../services/group_service.dart';

class GroupsScreen extends StatelessWidget {
  final String uid;

  const GroupsScreen({super.key, required this.uid});

  Future<void> _addGroup(BuildContext context) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add group'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Group name (e.g. Family, Friends, Team Trip)'),
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    if (context.mounted) {
      await context.read<GroupService>().addGroup(uid, name);
    }
  }

  Future<void> _renameGroup(BuildContext context, ExpenseGroup group) async {
    final controller = TextEditingController(text: group.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename group'),
        content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: 'Group name')),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == group.name) return;
    if (context.mounted) {
      await context.read<GroupService>().renameGroup(uid, group.id, name);
    }
  }

  Future<void> _deleteGroup(BuildContext context, ExpenseGroup group) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete group?'),
        content: Text('"${group.name}" will be removed. Past transactions tagged with it keep their amounts, just without the group label.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await context.read<GroupService>().deleteGroup(uid, group.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final groupService = context.read<GroupService>();

    return Scaffold(
      appBar: AppBar(title: const Text('Groups')),
      body: StreamBuilder<List<ExpenseGroup>>(
        stream: groupService.groupsFor(uid),
        builder: (context, snapshot) {
          final groups = snapshot.data ?? [];
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Tag transactions by family, friends, or team to see amounts grouped together.',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
              ),
              const SizedBox(height: 16),
              if (groups.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('No groups yet')),
                ),
              ...groups.map((group) {
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.15),
                      child: Text(group.name.isNotEmpty ? group.name[0].toUpperCase() : '?'),
                    ),
                    title: Text(group.name),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _renameGroup(context, group),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _deleteGroup(context, group),
                        ),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _addGroup(context),
                icon: const Icon(Icons.add),
                label: const Text('Add group'),
              ),
            ],
          );
        },
      ),
    );
  }
}
