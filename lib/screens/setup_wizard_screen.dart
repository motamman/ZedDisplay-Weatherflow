import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/weatherflow_service.dart';
import 'station_list_screen.dart';

/// Setup wizard for initial API token configuration
class SetupWizardScreen extends StatefulWidget {
  const SetupWizardScreen({super.key});

  @override
  State<SetupWizardScreen> createState() => _SetupWizardScreenState();
}

class _SetupWizardScreenState extends State<SetupWizardScreen> {
  final _tokenController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _submitToken() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final weatherFlow = context.read<WeatherFlowService>();
    final success = await weatherFlow.setApiToken(_tokenController.text.trim());

    if (!mounted) return;

    if (success) {
      // Fetch stations
      await weatherFlow.fetchStations();
      if (!mounted) return;

      // Navigate to station list
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const StationListScreen(isInitialSetup: true),
        ),
      );
    } else {
      setState(() {
        _isLoading = false;
        _error = weatherFlow.error ?? 'Invalid API token';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 48),

                // Header
                Icon(
                  Icons.cloud,
                  size: 80,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  'Welcome to ZedDisplay',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'WeatherFlow Edition',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),

                // Instructions
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.key,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'API Token Required',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'To connect to your Tempest weather station, you need a Personal Access Token from WeatherFlow.',
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Get your token at:',
                          style: TextStyle(fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 4),
                        SelectableText(
                          'tempestwx.com/settings/tokens',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Token input
                TextFormField(
                  controller: _tokenController,
                  decoration: const InputDecoration(
                    labelText: 'Personal Access Token',
                    hintText: 'Enter your WeatherFlow API token',
                    prefixIcon: Icon(Icons.vpn_key),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter your API token';
                    }
                    // Basic format check (UUID-like)
                    if (value.trim().length < 20) {
                      return 'Token appears to be too short';
                    }
                    return null;
                  },
                  enabled: !_isLoading,
                  autocorrect: false,
                  enableSuggestions: false,
                ),
                const SizedBox(height: 16),

                // Error message
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                // Submit button
                FilledButton.icon(
                  onPressed: _isLoading ? null : _submitToken,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.arrow_forward),
                  label: Text(_isLoading ? 'Connecting...' : 'Connect'),
                ),
                const SizedBox(height: 48),

                // Help text
                Text(
                  'Your token is stored locally and never shared.',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
