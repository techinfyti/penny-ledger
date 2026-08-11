import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/group.dart';
import '../services/group_service.dart';

class GroupFilterChips extends StatelessWidget {
  final String uid;
  final String? selectedGroupId;
  final ValueChanged<String?> onChanged;

  const GroupFilterChips({
    super.key,
    required this.uid,
    required this.selectedGroupId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ExpenseGroup>>(
      stream: context.read<GroupService>().groupsFor(uid),
      builder: (context, snapshot) {
        final groups = snapshot.data ?? [];
        if (groups.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: const Text('All groups'),
                    selected: selectedGroupId == null,
                    onSelected: (_) => onChanged(null),
                  ),
                ),
                for (final g in groups)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(g.name),
                      selected: selectedGroupId == g.id,
                      onSelected: (_) => onChanged(g.id),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
