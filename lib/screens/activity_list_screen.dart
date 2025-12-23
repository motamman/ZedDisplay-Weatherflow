/// Activity List Screen
///
/// Displays all activities with enable toggles and navigation to config.
/// Max 5 activities can be enabled at once.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/activity_definition.dart';
import '../models/activity_tolerances.dart';
import '../services/storage_service.dart';
import '../services/weatherflow_service.dart';
import 'activity_config_screen.dart';

class ActivityListScreen extends StatelessWidget {
  const ActivityListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final weatherService = context.watch<WeatherFlowService>();
    final tolerances = storage.activityTolerances;
    final enabledCount = tolerances.values.where((t) => t.enabled).length;
    // WeatherFlow doesn't provide marine data
    const hasMarineData = false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity Forecaster'),
      ),
      body: ListView(
        children: [
          // Info card
          Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'About Activity Scoring',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Enable up to 5 activities to see suitability scores on the forecast spinner. '
                      'Tap an activity to customize your ideal conditions.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$enabledCount/5 activities enabled',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Land Activities
          _buildSectionHeader(context, 'Land Activities'),
          ...landActivities.map((activity) => _buildActivityTile(
                context,
                storage,
                tolerances[activity] ?? DefaultTolerances.forActivity(activity),
                enabledCount,
                hasMarineData,
              )),

          const Divider(),

          // Marine Activities
          _buildSectionHeader(context, 'Marine Activities'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: Theme.of(context).colorScheme.secondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Marine data not available from WeatherFlow',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                  ),
                ),
              ],
            ),
          ),
          ...marineActivities.map((activity) => _buildActivityTile(
                context,
                storage,
                tolerances[activity] ?? DefaultTolerances.forActivity(activity),
                enabledCount,
                hasMarineData,
              )),

          const SizedBox(height: 32),
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

  Widget _buildActivityTile(
    BuildContext context,
    StorageService storage,
    ActivityTolerances tolerance,
    int enabledCount,
    bool hasMarineData,
  ) {
    final activity = tolerance.activity;
    final isMarine = activity.requiresMarineData;
    final canEnable = tolerance.enabled || enabledCount < 5;
    final isDisabled = isMarine && !hasMarineData;

    return ListTile(
      leading: Icon(
        activity.icon,
        color: isDisabled
            ? Theme.of(context).disabledColor
            : tolerance.enabled
                ? Theme.of(context).colorScheme.primary
                : null,
      ),
      title: Text(
        activity.displayName,
        style: isDisabled
            ? TextStyle(color: Theme.of(context).disabledColor)
            : null,
      ),
      subtitle: isMarine
          ? Text(
              isDisabled ? 'Requires marine data' : 'Marine activity',
              style: Theme.of(context).textTheme.bodySmall,
            )
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(
            value: tolerance.enabled,
            onChanged: isDisabled
                ? null
                : (value) async {
                    if (value && !canEnable) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Maximum 5 activities can be enabled'),
                        ),
                      );
                      return;
                    }
                    await storage.toggleActivity(activity);
                  },
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.chevron_right,
            color: isDisabled ? Theme.of(context).disabledColor : null,
          ),
        ],
      ),
      onTap: isDisabled
          ? null
          : () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ActivityConfigScreen(activity: activity),
                ),
              );
            },
    );
  }
}
