import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/currency_service.dart';

class CurrencySelectorButton extends StatelessWidget {
  const CurrencySelectorButton({super.key});

  Future<void> _openPicker(BuildContext context) async {
    final currencyService = context.read<CurrencyService>();
    final selected = await showModalBottomSheet<Currency>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _CurrencyPickerSheet(current: currencyService.currency),
    );
    if (selected != null) {
      currencyService.setCurrency(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencyService = context.watch<CurrencyService>();
    return TextButton.icon(
      onPressed: () => _openPicker(context),
      icon: Text(currencyService.currency.symbol, style: const TextStyle(fontSize: 16)),
      label: Text(currencyService.currency.code),
      style: TextButton.styleFrom(foregroundColor: Colors.white),
    );
  }
}

class _CurrencyPickerSheet extends StatefulWidget {
  final Currency current;

  const _CurrencyPickerSheet({required this.current});

  @override
  State<_CurrencyPickerSheet> createState() => _CurrencyPickerSheetState();
}

class _CurrencyPickerSheetState extends State<_CurrencyPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.toLowerCase();
    final filtered = supportedCurrencies.where((c) {
      return c.code.toLowerCase().contains(query) || c.name.toLowerCase().contains(query);
    }).toList();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: TextField(
                  autofocus: false,
                  decoration: const InputDecoration(
                    hintText: 'Search currency',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final currency = filtered[index];
                    final isSelected = currency.code == widget.current.code;
                    return ListTile(
                      leading: SizedBox(
                        width: 32,
                        child: Text(currency.symbol, style: const TextStyle(fontSize: 18)),
                      ),
                      title: Text(currency.code),
                      subtitle: Text(currency.name),
                      trailing: isSelected ? const Icon(Icons.check) : null,
                      selected: isSelected,
                      onTap: () => Navigator.of(context).pop(currency),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
