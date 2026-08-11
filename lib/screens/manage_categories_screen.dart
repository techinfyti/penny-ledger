import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/expense.dart';
import '../services/category_service.dart';
import '../widgets/category_colors.dart';

class ManageCategoriesScreen extends StatefulWidget {
  final String uid;

  const ManageCategoriesScreen({super.key, required this.uid});

  @override
  State<ManageCategoriesScreen> createState() => _ManageCategoriesScreenState();
}

class _ManageCategoriesScreenState extends State<ManageCategoriesScreen> {
  TransactionType _type = TransactionType.expense;

  Future<void> _rename(String oldName, List<String> existing) async {
    final categoryService = context.read<CategoryService>();
    final controller = TextEditingController(text: oldName);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename category'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Category name'),
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || newName == oldName) return;
    if (existing.any((c) => c.toLowerCase() == newName.toLowerCase())) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"$newName" already exists')),
        );
      }
      return;
    }
    await categoryService.renameCategory(widget.uid, _type, oldName, newName);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Renamed to "$newName" — past transactions updated')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoryService = context.read<CategoryService>();

    return Scaffold(
      appBar: AppBar(title: const Text('Manage Categories')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SegmentedButton<TransactionType>(
              segments: const [
                ButtonSegment(value: TransactionType.expense, label: Text('Expense')),
                ButtonSegment(value: TransactionType.income, label: Text('Income')),
              ],
              selected: {_type},
              onSelectionChanged: (selection) => setState(() => _type = selection.first),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<String>>(
              stream: categoryService.customCategoriesFor(widget.uid, _type),
              builder: (context, snapshot) {
                final custom = snapshot.data ?? [];
                if (custom.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No custom categories yet.\nCategories you add via "Add missing category" will appear here for editing.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: custom.length,
                  itemBuilder: (context, index) {
                    final category = custom[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: colorForCategory(category).withOpacity(0.15),
                        child: Text(
                          category.isNotEmpty ? category[0].toUpperCase() : '?',
                          style: TextStyle(color: colorForCategory(category), fontWeight: FontWeight.bold),
                        ),
                      ),
                      title: Text(category),
                      trailing: IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _rename(category, custom),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
