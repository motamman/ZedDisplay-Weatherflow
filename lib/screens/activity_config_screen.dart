/// Activity Configuration Screen
///
/// Configure tolerance ranges and weights for a specific activity.
/// Displays values in user-preferred units, stores in SI.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:weatherflow_core/weatherflow_core.dart' hide HourlyForecast;
import '../models/activity_definition.dart';
import '../models/activity_tolerances.dart';
import '../services/storage_service.dart';
import '../services/weatherflow_service.dart';
import '../utils/conversion_extensions.dart';

class ActivityConfigScreen extends StatefulWidget {
  final ActivityType activity;

  const ActivityConfigScreen({super.key, required this.activity});

  @override
  State<ActivityConfigScreen> createState() => _ActivityConfigScreenState();
}

class _ActivityConfigScreenState extends State<ActivityConfigScreen> {
  late ActivityTolerances _tolerances;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _loadTolerances();
  }

  void _loadTolerances() {
    final storage = context.read<StorageService>();
    _tolerances = storage.getActivityTolerance(widget.activity);
  }

  void _updateTolerance(ActivityTolerances newTolerance) {
    setState(() {
      _tolerances = newTolerance;
      _hasChanges = true;
    });
  }

  Future<void> _save() async {
    final storage = context.read<StorageService>();
    await storage.setActivityTolerance(_tolerances);
    setState(() => _hasChanges = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved')),
      );
    }
  }

  void _resetToDefaults() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset to Defaults'),
        content: Text(
          'Reset ${widget.activity.displayName} tolerances to default values?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _tolerances = DefaultTolerances.forActivity(widget.activity)
                    .copyWith(enabled: _tolerances.enabled);
                _hasChanges = true;
              });
            },
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final weatherService = context.watch<WeatherFlowService>();
    final conversions = weatherService.conversions;
    final isMarine = widget.activity.requiresMarineData;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.activity.displayName),
        actions: [
          IconButton(
            icon: const Icon(Icons.restore),
            tooltip: 'Reset to defaults',
            onPressed: _resetToDefaults,
          ),
          if (_hasChanges)
            IconButton(
              icon: const Icon(Icons.save),
              tooltip: 'Save changes',
              onPressed: _save,
            ),
        ],
      ),
      body: ListView(
        children: [
          // Enable toggle
          SwitchListTile(
            title: const Text('Enable Activity'),
            subtitle: const Text('Show on forecast spinner'),
            secondary: Icon(widget.activity.icon),
            value: _tolerances.enabled,
            onChanged: (value) async {
              final storage = context.read<StorageService>();
              if (value) {
                final enabledCount = storage.enabledActivities.length;
                if (enabledCount >= 5) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Maximum 5 activities can be enabled'),
                    ),
                  );
                  return;
                }
              }
              _updateTolerance(_tolerances.copyWith(enabled: value));
            },
          ),
          const Divider(),

          // Weather Parameters
          _buildSectionHeader(context, 'Weather Conditions'),

          // Temperature
          _TemperatureToleranceTile(
            tolerance: _tolerances.temperature,
            conversions: conversions,
            onChanged: (t) => _updateTolerance(_tolerances.copyWith(temperature: t)),
          ),

          // Wind Speed
          _WindToleranceTile(
            tolerance: _tolerances.windSpeed,
            conversions: conversions,
            onChanged: (t) => _updateTolerance(_tolerances.copyWith(windSpeed: t)),
          ),

          // Cloud Cover
          _PercentToleranceTile(
            title: 'Cloud Cover',
            icon: Icons.cloud,
            tolerance: _tolerances.cloudCover,
            onChanged: (t) => _updateTolerance(_tolerances.copyWith(cloudCover: t)),
          ),

          // Precipitation Probability
          _PercentToleranceTile(
            title: 'Precipitation Chance',
            icon: Icons.water_drop,
            tolerance: _tolerances.precipProbability,
            onChanged: (t) => _updateTolerance(_tolerances.copyWith(precipProbability: t)),
          ),

          // UV Index
          _UvToleranceTile(
            tolerance: _tolerances.uvIndex,
            onChanged: (t) => _updateTolerance(_tolerances.copyWith(uvIndex: t)),
          ),

          // Precipitation Types
          _PrecipTypeTile(
            tolerance: _tolerances.precipType,
            onChanged: (t) => _updateTolerance(_tolerances.copyWith(precipType: t)),
          ),

          // Marine Parameters (if applicable)
          if (isMarine) ...[
            const Divider(),
            _buildSectionHeader(context, 'Marine Conditions'),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Marine data is not available from WeatherFlow API. '
                'These settings will not affect scoring.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],

          const SizedBox(height: 32),

          // Save button
          if (_hasChanges)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save),
                label: const Text('Save Changes'),
              ),
            ),

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
}

/// Expandable tile for feels like temperature tolerance
class _TemperatureToleranceTile extends StatelessWidget {
  final RangeTolerance tolerance;
  final ConversionService conversions;
  final ValueChanged<RangeTolerance> onChanged;

  const _TemperatureToleranceTile({
    required this.tolerance,
    required this.conversions,
    required this.onChanged,
  });

  String _formatTemp(double kelvin) {
    final converted = conversions.convertTemperatureFromKelvin(kelvin);
    return '${converted.toStringAsFixed(0)}${conversions.temperatureSymbol}';
  }

  void _onIdealChanged(double low, double high) {
    var accMin = tolerance.acceptableMin;
    var accMax = tolerance.acceptableMax;
    if (low < accMin) accMin = low;
    if (high > accMax) accMax = high;
    onChanged(tolerance.copyWith(
      idealMin: low,
      idealMax: high,
      acceptableMin: accMin,
      acceptableMax: accMax,
    ));
  }

  void _onAcceptableChanged(double low, double high) {
    final constrainedMin = low > tolerance.idealMin ? tolerance.idealMin : low;
    final constrainedMax = high < tolerance.idealMax ? tolerance.idealMax : high;
    onChanged(tolerance.copyWith(
      acceptableMin: constrainedMin,
      acceptableMax: constrainedMax,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      leading: const Icon(Icons.device_thermostat),
      title: const Text('Feels Like'),
      subtitle: Text(
        'Ideal: ${_formatTemp(tolerance.idealMin)} - ${_formatTemp(tolerance.idealMax)}',
      ),
      trailing: _WeightBadge(weight: tolerance.weight),
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ideal Range (Score: 100%)',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              _DualSlider(
                min: 233.15, // -40°C
                max: 323.15, // 50°C
                lowValue: tolerance.idealMin,
                highValue: tolerance.idealMax,
                formatValue: _formatTemp,
                onChanged: _onIdealChanged,
              ),
              const SizedBox(height: 16),
              Text(
                'Acceptable Range (Score: 0-100%)',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              _DualSlider(
                min: 223.15, // -50°C
                max: 333.15, // 60°C
                lowValue: tolerance.acceptableMin,
                highValue: tolerance.acceptableMax,
                formatValue: _formatTemp,
                onChanged: _onAcceptableChanged,
              ),
              const SizedBox(height: 16),
              _WeightSlider(
                weight: tolerance.weight,
                onChanged: (w) => onChanged(tolerance.copyWith(weight: w)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Expandable tile for wind speed tolerance
class _WindToleranceTile extends StatelessWidget {
  final RangeTolerance tolerance;
  final ConversionService conversions;
  final ValueChanged<RangeTolerance> onChanged;

  const _WindToleranceTile({
    required this.tolerance,
    required this.conversions,
    required this.onChanged,
  });

  String _formatWind(double mps) {
    final converted = conversions.convertWindSpeedFromMps(mps);
    return '${converted.toStringAsFixed(0)} ${conversions.windSpeedSymbol}';
  }

  void _onIdealChanged(double low, double high) {
    var accMin = tolerance.acceptableMin;
    var accMax = tolerance.acceptableMax;
    if (low < accMin) accMin = low;
    if (high > accMax) accMax = high;
    onChanged(tolerance.copyWith(
      idealMin: low,
      idealMax: high,
      acceptableMin: accMin,
      acceptableMax: accMax,
    ));
  }

  void _onAcceptableChanged(double low, double high) {
    final constrainedMin = low > tolerance.idealMin ? tolerance.idealMin : low;
    final constrainedMax = high < tolerance.idealMax ? tolerance.idealMax : high;
    onChanged(tolerance.copyWith(
      acceptableMin: constrainedMin,
      acceptableMax: constrainedMax,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      leading: const Icon(Icons.air),
      title: const Text('Wind Speed'),
      subtitle: Text(
        'Ideal: ${_formatWind(tolerance.idealMin)} - ${_formatWind(tolerance.idealMax)}',
      ),
      trailing: _WeightBadge(weight: tolerance.weight),
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ideal Range',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              _DualSlider(
                min: 0,
                max: 30,
                lowValue: tolerance.idealMin,
                highValue: tolerance.idealMax,
                formatValue: _formatWind,
                onChanged: _onIdealChanged,
              ),
              const SizedBox(height: 16),
              Text(
                'Acceptable Range',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              _DualSlider(
                min: 0,
                max: 40,
                lowValue: tolerance.acceptableMin,
                highValue: tolerance.acceptableMax,
                formatValue: _formatWind,
                onChanged: _onAcceptableChanged,
              ),
              const SizedBox(height: 16),
              _WeightSlider(
                weight: tolerance.weight,
                onChanged: (w) => onChanged(tolerance.copyWith(weight: w)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Expandable tile for percentage-based tolerances
class _PercentToleranceTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final RangeTolerance tolerance;
  final ValueChanged<RangeTolerance> onChanged;

  const _PercentToleranceTile({
    required this.title,
    required this.icon,
    required this.tolerance,
    required this.onChanged,
  });

  String _formatPercent(double ratio) => '${(ratio * 100).toStringAsFixed(0)}%';

  void _onIdealChanged(double low, double high) {
    var accMin = tolerance.acceptableMin;
    var accMax = tolerance.acceptableMax;
    if (low < accMin) accMin = low;
    if (high > accMax) accMax = high;
    onChanged(tolerance.copyWith(
      idealMin: low,
      idealMax: high,
      acceptableMin: accMin,
      acceptableMax: accMax,
    ));
  }

  void _onAcceptableChanged(double low, double high) {
    final constrainedMin = low > tolerance.idealMin ? tolerance.idealMin : low;
    final constrainedMax = high < tolerance.idealMax ? tolerance.idealMax : high;
    onChanged(tolerance.copyWith(
      acceptableMin: constrainedMin,
      acceptableMax: constrainedMax,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(
        'Ideal: ${_formatPercent(tolerance.idealMin)} - ${_formatPercent(tolerance.idealMax)}',
      ),
      trailing: _WeightBadge(weight: tolerance.weight),
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ideal Range',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              _DualSlider(
                min: 0,
                max: 1,
                lowValue: tolerance.idealMin,
                highValue: tolerance.idealMax,
                formatValue: _formatPercent,
                onChanged: _onIdealChanged,
              ),
              const SizedBox(height: 16),
              Text(
                'Acceptable Range',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              _DualSlider(
                min: 0,
                max: 1,
                lowValue: tolerance.acceptableMin,
                highValue: tolerance.acceptableMax,
                formatValue: _formatPercent,
                onChanged: _onAcceptableChanged,
              ),
              const SizedBox(height: 16),
              _WeightSlider(
                weight: tolerance.weight,
                onChanged: (w) => onChanged(tolerance.copyWith(weight: w)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Expandable tile for UV index tolerance
class _UvToleranceTile extends StatelessWidget {
  final RangeTolerance tolerance;
  final ValueChanged<RangeTolerance> onChanged;

  const _UvToleranceTile({
    required this.tolerance,
    required this.onChanged,
  });

  String _formatUv(double uv) => uv.toStringAsFixed(0);

  void _onIdealChanged(double low, double high) {
    var accMin = tolerance.acceptableMin;
    var accMax = tolerance.acceptableMax;
    if (low < accMin) accMin = low;
    if (high > accMax) accMax = high;
    onChanged(tolerance.copyWith(
      idealMin: low,
      idealMax: high,
      acceptableMin: accMin,
      acceptableMax: accMax,
    ));
  }

  void _onAcceptableChanged(double low, double high) {
    final constrainedMin = low > tolerance.idealMin ? tolerance.idealMin : low;
    final constrainedMax = high < tolerance.idealMax ? tolerance.idealMax : high;
    onChanged(tolerance.copyWith(
      acceptableMin: constrainedMin,
      acceptableMax: constrainedMax,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      leading: const Icon(Icons.wb_sunny),
      title: const Text('UV Index'),
      subtitle: Text(
        'Ideal: ${_formatUv(tolerance.idealMin)} - ${_formatUv(tolerance.idealMax)}',
      ),
      trailing: _WeightBadge(weight: tolerance.weight),
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ideal Range',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              _DualSlider(
                min: 0,
                max: 11,
                lowValue: tolerance.idealMin,
                highValue: tolerance.idealMax,
                formatValue: _formatUv,
                onChanged: _onIdealChanged,
              ),
              const SizedBox(height: 16),
              Text(
                'Acceptable Range',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              _DualSlider(
                min: 0,
                max: 15,
                lowValue: tolerance.acceptableMin,
                highValue: tolerance.acceptableMax,
                formatValue: _formatUv,
                onChanged: _onAcceptableChanged,
              ),
              const SizedBox(height: 16),
              _WeightSlider(
                weight: tolerance.weight,
                onChanged: (w) => onChanged(tolerance.copyWith(weight: w)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Tile for precipitation type checkboxes
class _PrecipTypeTile extends StatelessWidget {
  final PrecipitationTolerance tolerance;
  final ValueChanged<PrecipitationTolerance> onChanged;

  const _PrecipTypeTile({
    required this.tolerance,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      leading: const Icon(Icons.grain),
      title: const Text('Acceptable Weather'),
      subtitle: Text(_getAcceptedTypesText()),
      trailing: _WeightBadge(weight: tolerance.weight),
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _buildTypeCheckbox('Clear/Cloudy', PrecipitationTolerance.clearCodes),
              _buildTypeCheckbox('Fog/Mist', PrecipitationTolerance.fogCodes),
              _buildTypeCheckbox('Drizzle', PrecipitationTolerance.drizzleCodes),
              _buildTypeCheckbox('Rain', PrecipitationTolerance.rainCodes),
              _buildTypeCheckbox('Snow', PrecipitationTolerance.snowCodes),
              _buildTypeCheckbox('Thunderstorms', PrecipitationTolerance.thunderCodes),
              const SizedBox(height: 16),
              _WeightSlider(
                weight: tolerance.weight,
                onChanged: (w) => onChanged(tolerance.copyWith(weight: w)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _getAcceptedTypesText() {
    final types = <String>[];
    if (_hasAllCodes(PrecipitationTolerance.clearCodes)) types.add('Clear');
    if (_hasAllCodes(PrecipitationTolerance.fogCodes)) types.add('Fog');
    if (_hasAllCodes(PrecipitationTolerance.drizzleCodes)) types.add('Drizzle');
    if (_hasAllCodes(PrecipitationTolerance.rainCodes)) types.add('Rain');
    if (_hasAllCodes(PrecipitationTolerance.snowCodes)) types.add('Snow');
    if (_hasAllCodes(PrecipitationTolerance.thunderCodes)) types.add('Thunder');
    return types.isEmpty ? 'None selected' : types.join(', ');
  }

  bool _hasAllCodes(Set<int> codes) {
    return codes.every((c) => tolerance.acceptableCodes.contains(c));
  }

  Widget _buildTypeCheckbox(String label, Set<int> codes) {
    final hasAll = _hasAllCodes(codes);
    return CheckboxListTile(
      title: Text(label),
      value: hasAll,
      onChanged: (value) {
        final newCodes = Set<int>.from(tolerance.acceptableCodes);
        if (value == true) {
          newCodes.addAll(codes);
        } else {
          newCodes.removeAll(codes);
        }
        onChanged(tolerance.copyWith(acceptableCodes: newCodes));
      },
    );
  }
}

/// Dual-thumb range slider
class _DualSlider extends StatelessWidget {
  final double min;
  final double max;
  final double lowValue;
  final double highValue;
  final String Function(double) formatValue;
  final void Function(double low, double high) onChanged;

  const _DualSlider({
    required this.min,
    required this.max,
    required this.lowValue,
    required this.highValue,
    required this.formatValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        RangeSlider(
          values: RangeValues(
            lowValue.clamp(min, max),
            highValue.clamp(min, max),
          ),
          min: min,
          max: max,
          onChanged: (values) => onChanged(values.start, values.end),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(formatValue(lowValue)),
            Text(formatValue(highValue)),
          ],
        ),
      ],
    );
  }
}

/// Weight slider (0-10)
class _WeightSlider extends StatelessWidget {
  final int weight;
  final ValueChanged<int> onChanged;

  const _WeightSlider({
    required this.weight,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Importance: ',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              _getWeightLabel(weight),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
        Slider(
          value: weight.toDouble(),
          min: 0,
          max: 10,
          divisions: 10,
          label: weight.toString(),
          onChanged: (value) => onChanged(value.round()),
        ),
      ],
    );
  }

  String _getWeightLabel(int weight) {
    if (weight == 0) return 'Ignored';
    if (weight <= 2) return 'Low';
    if (weight <= 4) return 'Medium-Low';
    if (weight <= 6) return 'Medium';
    if (weight <= 8) return 'High';
    return 'Critical';
  }
}

/// Small badge showing weight value
class _WeightBadge extends StatelessWidget {
  final int weight;

  const _WeightBadge({required this.weight});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        weight.toString(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}
