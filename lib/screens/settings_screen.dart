import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:weatherflow_core/weatherflow_core.dart';
import '../services/storage_service.dart';
import '../services/weatherflow_service.dart';
import 'setup_wizard_screen.dart';
import 'activity_list_screen.dart';

/// Settings screen for app configuration
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          // Unit Preferences
          _buildSectionHeader(context, 'Units'),
          _buildUnitTile(
            context,
            'Temperature',
            storage.unitPreferences.temperature,
            ['°C', '°F', 'K'],
            (value) => _updateUnitPreference(context, temperature: value),
          ),
          _buildUnitTile(
            context,
            'Wind Speed',
            storage.unitPreferences.windSpeed,
            ['kn', 'm/s', 'km/h', 'mph'],
            (value) => _updateUnitPreference(context, windSpeed: value),
          ),
          _buildUnitTile(
            context,
            'Pressure',
            storage.unitPreferences.pressure,
            ['hPa', 'mbar', 'inHg', 'mmHg'],
            (value) => _updateUnitPreference(context, pressure: value),
          ),
          _buildUnitTile(
            context,
            'Rainfall',
            storage.unitPreferences.rainfall,
            ['mm', 'in', 'cm'],
            (value) => _updateUnitPreference(context, rainfall: value),
          ),
          _buildUnitTile(
            context,
            'Distance',
            storage.unitPreferences.distance,
            ['km', 'mi', 'nm'],
            (value) => _updateUnitPreference(context, distance: value),
          ),
          const Divider(),

          // Unit Presets
          _buildSectionHeader(context, 'Unit Presets'),
          ListTile(
            title: const Text('Metric'),
            subtitle: const Text('°C, hPa, m/s, mm, km'),
            leading: const Icon(Icons.straighten),
            onTap: () => _applyPreset(context, UnitPreferences.metric),
          ),
          ListTile(
            title: const Text('Imperial (US)'),
            subtitle: const Text('°F, inHg, mph, in, mi'),
            leading: const Icon(Icons.flag),
            onTap: () => _applyPreset(context, UnitPreferences.imperialUS),
          ),
          ListTile(
            title: const Text('Nautical'),
            subtitle: const Text('°C, hPa, kn, mm, nm'),
            leading: const Icon(Icons.sailing),
            onTap: () => _applyPreset(context, UnitPreferences.nautical),
          ),
          const Divider(),

          // Theme
          _buildSectionHeader(context, 'Appearance'),
          ListTile(
            title: const Text('Theme'),
            subtitle: Text(_getThemeLabel(storage.themeMode)),
            leading: const Icon(Icons.palette),
            trailing: DropdownButton<String>(
              value: storage.themeMode,
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: 'system', child: Text('System')),
                DropdownMenuItem(value: 'light', child: Text('Light')),
                DropdownMenuItem(value: 'dark', child: Text('Dark')),
              ],
              onChanged: (value) {
                if (value != null) {
                  storage.setThemeMode(value);
                }
              },
            ),
          ),
          const Divider(),

          // Data Refresh
          _buildSectionHeader(context, 'Data'),
          ListTile(
            title: const Text('Auto-refresh Interval'),
            subtitle: Text('${storage.refreshInterval} minutes'),
            leading: const Icon(Icons.timer),
            trailing: DropdownButton<int>(
              value: storage.refreshInterval,
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: 5, child: Text('5 min')),
                DropdownMenuItem(value: 10, child: Text('10 min')),
                DropdownMenuItem(value: 15, child: Text('15 min')),
                DropdownMenuItem(value: 30, child: Text('30 min')),
                DropdownMenuItem(value: 60, child: Text('60 min')),
              ],
              onChanged: (value) {
                if (value != null) {
                  storage.setRefreshInterval(value);
                }
              },
            ),
          ),
          _UdpSettingsSection(),
          const Divider(),

          // Activity Forecaster
          _buildSectionHeader(context, 'Activity Forecaster'),
          ListTile(
            title: const Text('Configure Activities'),
            subtitle: Text('${storage.enabledActivities.length}/5 activities enabled'),
            leading: const Icon(Icons.directions_run),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ActivityListScreen(),
                ),
              );
            },
          ),
          const Divider(),

          // Account
          _buildSectionHeader(context, 'Account'),
          ListTile(
            title: const Text('Change API Token'),
            subtitle: const Text('Reconfigure WeatherFlow connection'),
            leading: const Icon(Icons.key),
            onTap: () => _showChangeTokenDialog(context),
          ),
          ListTile(
            title: const Text('Clear Cache'),
            subtitle: const Text('Remove cached weather data'),
            leading: const Icon(Icons.delete_outline),
            onTap: () => _showClearCacheDialog(context),
          ),
          ListTile(
            title: Text(
              'Sign Out',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            subtitle: const Text('Clear all data and sign out'),
            leading: Icon(Icons.logout, color: Theme.of(context).colorScheme.error),
            onTap: () => _showSignOutDialog(context),
          ),
          const SizedBox(height: 32),

          // Version info
          Center(
            child: Text(
              'ZedDisplay WeatherFlow v1.0.0',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }

  Widget _buildUnitTile(
    BuildContext context,
    String title,
    String currentValue,
    List<String> options,
    ValueChanged<String> onChanged,
  ) {
    return ListTile(
      title: Text(title),
      trailing: DropdownButton<String>(
        value: currentValue,
        underline: const SizedBox(),
        items: options
            .map((opt) => DropdownMenuItem(value: opt, child: Text(opt)))
            .toList(),
        onChanged: (value) {
          if (value != null) {
            onChanged(value);
          }
        },
      ),
    );
  }

  void _updateUnitPreference(
    BuildContext context, {
    String? temperature,
    String? windSpeed,
    String? pressure,
    String? rainfall,
    String? distance,
  }) {
    final storage = context.read<StorageService>();
    final weatherFlow = context.read<WeatherFlowService>();

    final newPrefs = storage.unitPreferences.copyWith(
      temperature: temperature,
      windSpeed: windSpeed,
      pressure: pressure,
      rainfall: rainfall,
      distance: distance,
    );

    storage.setUnitPreferences(newPrefs);
    weatherFlow.conversions.setPreferences(newPrefs);
  }

  void _applyPreset(BuildContext context, UnitPreferences preset) {
    final storage = context.read<StorageService>();
    final weatherFlow = context.read<WeatherFlowService>();

    storage.setUnitPreferences(preset);
    weatherFlow.conversions.setPreferences(preset);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Unit preset applied')),
    );
  }

  String _getThemeLabel(String mode) {
    switch (mode) {
      case 'light':
        return 'Light';
      case 'dark':
        return 'Dark';
      default:
        return 'System';
    }
  }

  void _showChangeTokenDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change API Token'),
        content: const Text(
          'This will disconnect from your current station and require re-authentication.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              final storage = context.read<StorageService>();
              await storage.clearApiToken();
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const SetupWizardScreen()),
                  (route) => false,
                );
              }
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  void _showClearCacheDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Cache'),
        content: const Text(
          'This will remove all cached weather data. Your settings will be preserved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              final storage = context.read<StorageService>();
              await storage.clearCache();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Cache cleared')),
                );
              }
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  void _showSignOutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text(
          'This will clear all data and return to the setup screen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () async {
              Navigator.pop(context);
              final storage = context.read<StorageService>();
              final weatherFlow = context.read<WeatherFlowService>();
              weatherFlow.disconnect();
              await storage.clearAll();
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const SetupWizardScreen()),
                  (route) => false,
                );
              }
            },
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }
}

/// UDP Settings section with enable toggle and port configuration
class _UdpSettingsSection extends StatefulWidget {
  @override
  State<_UdpSettingsSection> createState() => _UdpSettingsSectionState();
}

class _UdpSettingsSectionState extends State<_UdpSettingsSection> {
  late TextEditingController _portController;
  bool _isEditingPort = false;

  @override
  void initState() {
    super.initState();
    _portController = TextEditingController();
  }

  @override
  void dispose() {
    _portController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final weatherFlow = context.watch<WeatherFlowService>();

    // Update controller text if not editing
    if (!_isEditingPort) {
      _portController.text = storage.udpPort.toString();
    }

    final udpService = weatherFlow.udpService;
    final isListening = udpService?.isListening ?? false;
    final lastMessage = udpService?.lastMessageAt;
    final hubSerial = udpService?.hubSerialNumber;

    String statusText;
    Color statusColor;

    if (!storage.udpEnabled) {
      statusText = 'Disabled';
      statusColor = Colors.grey;
    } else if (isListening) {
      if (lastMessage != null) {
        final ago = DateTime.now().difference(lastMessage);
        if (ago.inSeconds < 60) {
          statusText = 'Receiving data';
          statusColor = Colors.green;
        } else {
          statusText = 'Listening (no recent data)';
          statusColor = Colors.orange;
        }
      } else {
        statusText = 'Listening on port ${storage.udpPort}';
        statusColor = Colors.blue;
      }
    } else {
      statusText = 'Not listening';
      statusColor = Colors.red;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          title: const Text('UDP (Local Network)'),
          subtitle: Text(
            statusText,
            style: TextStyle(color: statusColor),
          ),
          secondary: Icon(
            isListening ? Icons.wifi : Icons.wifi_off,
            color: statusColor,
          ),
          value: storage.udpEnabled,
          onChanged: (value) async {
            await storage.setUdpEnabled(value);
            if (value) {
              await weatherFlow.startUdp();
            } else {
              await weatherFlow.stopUdp();
            }
          },
        ),

        // Port setting (only visible when UDP is enabled)
        if (storage.udpEnabled)
          ListTile(
            title: const Text('UDP Port'),
            subtitle: hubSerial != null
                ? Text('Hub: $hubSerial')
                : const Text('Tempest hub broadcasts on this port'),
            leading: const Icon(Icons.settings_ethernet),
            trailing: SizedBox(
              width: 100,
              child: TextField(
                controller: _portController,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  border: OutlineInputBorder(),
                ),
                onTap: () {
                  setState(() => _isEditingPort = true);
                },
                onSubmitted: (value) async {
                  setState(() => _isEditingPort = false);
                  final port = int.tryParse(value);
                  if (port != null && port > 0 && port < 65536) {
                    await storage.setUdpPort(port);
                    await weatherFlow.restartUdp();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('UDP port changed to $port')),
                      );
                    }
                  } else {
                    // Reset to current port
                    _portController.text = storage.udpPort.toString();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Invalid port number'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
                onEditingComplete: () {
                  setState(() => _isEditingPort = false);
                },
              ),
            ),
          ),

        // Show last message time if receiving
        if (storage.udpEnabled && lastMessage != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Last update: ${_formatTime(lastMessage)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey,
                  ),
            ),
          ),
      ],
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inSeconds < 5) {
      return 'just now';
    } else if (diff.inSeconds < 60) {
      return '${diff.inSeconds}s ago';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else {
      return '${diff.inHours}h ago';
    }
  }
}
