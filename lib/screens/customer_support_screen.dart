import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

const String _supportEmail = 'techinfy.ti+support@gmail.com';
const String _supportDisplayName = 'PennyLedger Support';

class CustomerSupportScreen extends StatelessWidget {
  const CustomerSupportScreen({super.key});

  Future<void> _emailSupport(BuildContext context) async {
    final uri = Uri(
      scheme: 'mailto',
      path: '"$_supportDisplayName" <$_supportEmail>',
      queryParameters: {'subject': 'PennyLedger Support Request'},
    );
    final launched = await launchUrl(uri);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No email app found on this device')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Customer Support')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(color: scheme.primary.withOpacity(0.15), shape: BoxShape.circle),
                child: Icon(Icons.support_agent, size: 40, color: scheme.primary),
              ),
              const SizedBox(height: 20),
              const Text('Need help?', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                'Reach out and we\'ll get back to you as soon as we can.',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton.icon(
                  onPressed: () => _emailSupport(context),
                  icon: const Icon(Icons.email_outlined),
                  label: const Text('Email Support'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
