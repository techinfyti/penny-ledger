import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/reminder_service.dart';

/// Settings rows for the daily reminder: a switch and, when it is on, the time.
class ReminderTile extends StatefulWidget {
  const ReminderTile({super.key});

  @override
  State<ReminderTile> createState() => _ReminderTileState();
}

class _ReminderTileState extends State<ReminderTile> {
  bool _enabled = false;
  TimeOfDay _time = const TimeOfDay(hour: ReminderService.defaultHour, minute: ReminderService.defaultMinute);
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final saved = await context.read<ReminderService>().load();
    if (!mounted) return;
    setState(() {
      _enabled = saved.enabled;
      _time = saved.time;
      _loaded = true;
    });
  }

  Future<void> _save(bool enabled, TimeOfDay time) async {
    setState(() {
      _enabled = enabled;
      _time = time;
    });
    await context.read<ReminderService>().save(enabled: enabled, time: time);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) await _save(_enabled, picked);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.notifications_active_outlined),
          title: const Text('Daily reminder'),
          subtitle: const Text('A gentle nudge to add your expenses. Skipped on days you already added one.'),
          value: _enabled,
          onChanged: _loaded ? (value) => _save(value, _time) : null,
        ),
        if (_enabled)
          ListTile(
            leading: const Icon(Icons.schedule),
            title: const Text('Reminder time'),
            subtitle: Text(_time.format(context)),
            trailing: const Icon(Icons.chevron_right),
            onTap: _pickTime,
          ),
      ],
    );
  }
}
