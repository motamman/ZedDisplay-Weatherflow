/// Tool Configuration Screen for WeatherFlow
/// Allows editing tool appearance and settings
/// Adapted from ZedDisplay architecture

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../models/tool.dart';
import '../models/tool_config.dart';
import '../models/tool_definition.dart';
import '../services/tool_service.dart';
import '../services/tool_registry.dart';
import '../services/storage_service.dart';
import '../services/weatherflow_service.dart';

/// Screen for configuring a tool's appearance and settings
class ToolConfigScreen extends StatefulWidget {
  final Tool tool;
  final int? currentWidth;
  final int? currentHeight;

  const ToolConfigScreen({
    super.key,
    required this.tool,
    this.currentWidth,
    this.currentHeight,
  });

  @override
  State<ToolConfigScreen> createState() => _ToolConfigScreenState();
}

class _ToolConfigScreenState extends State<ToolConfigScreen> {
  late String _name;
  late String? _primaryColor;
  late bool _showLabel;
  late bool _showValue;
  late bool _showUnit;
  late int _toolWidth;
  late int _toolHeight;
  late Map<String, dynamic> _customProperties;

  @override
  void initState() {
    super.initState();
    _loadTool();
  }

  /// Device source property keys that should be stored per-station
  static const _deviceSourceKeys = [
    'tempSource', 'humiditySource', 'pressureSource',
    'windSource', 'lightSource', 'rainSource', 'lightningSource',
  ];

  void _loadTool() {
    final tool = widget.tool;
    _name = tool.name;
    _primaryColor = tool.config.style.primaryColor;
    _showLabel = tool.config.style.showLabel;
    _showValue = tool.config.style.showValue;
    _showUnit = tool.config.style.showUnit;
    _toolWidth = widget.currentWidth ?? tool.defaultWidth;
    _toolHeight = widget.currentHeight ?? tool.defaultHeight;

    // Start with base custom properties
    _customProperties = Map<String, dynamic>.from(tool.config.style.customProperties ?? {});

    // Merge in station-specific device source overrides
    final weatherFlow = context.read<WeatherFlowService>();
    final storage = context.read<StorageService>();
    final stationId = weatherFlow.selectedStation?.stationId;

    if (stationId != null) {
      final stationOverrides = storage.getToolConfigForStation(stationId, tool.id);
      if (stationOverrides != null) {
        // Only merge device source keys
        for (final key in _deviceSourceKeys) {
          if (stationOverrides.containsKey(key)) {
            _customProperties[key] = stationOverrides[key];
          }
        }
      } else {
        // No station-specific config - reset device sources to 'auto'
        for (final key in _deviceSourceKeys) {
          if (_customProperties.containsKey(key)) {
            _customProperties[key] = 'auto';
          }
        }
      }
    }
  }

  Future<void> _selectColor() async {
    Color currentColor = Colors.blue;
    if (_primaryColor != null && _primaryColor!.isNotEmpty) {
      try {
        final hexColor = _primaryColor!.replaceAll('#', '');
        currentColor = Color(int.parse('FF$hexColor', radix: 16));
      } catch (e) {
        // Invalid color, use default
      }
    }

    Color? pickedColor;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pick a color'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: currentColor,
            onColorChanged: (color) {
              pickedColor = color;
            },
            pickerAreaHeightPercent: 0.8,
            enableAlpha: false,
            displayThumbColor: true,
            labelTypes: const [],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (pickedColor != null) {
                setState(() {
                  _primaryColor = '#${pickedColor!.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
                });
              }
              Navigator.of(context).pop();
            },
            child: const Text('Select'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveTool() async {
    final toolService = context.read<ToolService>();
    final storage = context.read<StorageService>();
    final weatherFlow = context.read<WeatherFlowService>();
    final stationId = weatherFlow.selectedStation?.stationId;

    // Separate device source properties from other custom properties
    final deviceSources = <String, dynamic>{};
    final otherCustomProps = <String, dynamic>{};

    for (final entry in _customProperties.entries) {
      if (_deviceSourceKeys.contains(entry.key)) {
        deviceSources[entry.key] = entry.value;
      } else {
        otherCustomProps[entry.key] = entry.value;
      }
    }

    // Save device sources to station-specific storage
    if (stationId != null && deviceSources.isNotEmpty) {
      await storage.setToolConfigForStation(stationId, widget.tool.id, deviceSources);
    }

    // Save other custom properties to the base tool config (without device sources)
    final updatedStyle = StyleConfig(
      minValue: widget.tool.config.style.minValue,
      maxValue: widget.tool.config.style.maxValue,
      unit: widget.tool.config.style.unit,
      primaryColor: _primaryColor,
      fontSize: widget.tool.config.style.fontSize,
      showLabel: _showLabel,
      showValue: _showValue,
      showUnit: _showUnit,
      customProperties: otherCustomProps.isNotEmpty ? otherCustomProps : null,
    );

    final updatedConfig = ToolConfig(
      dataSources: widget.tool.config.dataSources,
      style: updatedStyle,
    );

    final updatedTool = widget.tool.copyWith(
      name: _name,
      config: updatedConfig,
      defaultWidth: _toolWidth,
      defaultHeight: _toolHeight,
      updatedAt: DateTime.now(),
    );

    await toolService.updateTool(updatedTool);

    if (mounted) {
      Navigator.of(context).pop({
        'tool': updatedTool,
        'width': _toolWidth,
        'height': _toolHeight,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final registry = ToolRegistry();
    final definition = registry.getDefinition(widget.tool.toolTypeId);
    final weatherFlow = context.watch<WeatherFlowService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Configure Tool'),
        actions: [
          TextButton.icon(
            onPressed: _saveTool,
            icon: const Icon(Icons.check),
            label: const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Tool Info Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _getCategoryIcon(widget.tool.category),
                        color: _getCategoryColor(widget.tool.category),
                        size: 32,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              definition?.name ?? widget.tool.toolTypeId,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            Text(
                              definition?.description ?? '',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Name
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Display Name',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    initialValue: _name,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Tool name',
                    ),
                    onChanged: (value) => _name = value,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Style Configuration - only show for tools that use these options
          // Complex widgets like weatherflow_forecast have their own section toggles
          if (!_isComplexWidget(widget.tool.toolTypeId)) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Appearance',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),

                    // Color picker
                    if (definition?.configSchema.allowsColorCustomization ?? true)
                      ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: _primaryColor != null && _primaryColor!.isNotEmpty
                                ? () {
                                    try {
                                      final hexColor = _primaryColor!.replaceAll('#', '');
                                      return Color(int.parse('FF$hexColor', radix: 16));
                                    } catch (e) {
                                      return Colors.blue;
                                    }
                                  }()
                                : Colors.blue,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade400, width: 2),
                          ),
                        ),
                        title: const Text('Primary Color'),
                        subtitle: Text(_primaryColor ?? 'Default (Blue)'),
                        trailing: const Icon(Icons.edit),
                        onTap: _selectColor,
                      ),
                    const SizedBox(height: 8),

                    // Show/Hide Options
                    SwitchListTile(
                      title: const Text('Show Label'),
                      value: _showLabel,
                      onChanged: (value) => setState(() => _showLabel = value),
                    ),
                    SwitchListTile(
                      title: const Text('Show Value'),
                      value: _showValue,
                      onChanged: (value) => setState(() => _showValue = value),
                    ),
                    SwitchListTile(
                      title: const Text('Show Unit'),
                      value: _showUnit,
                      onChanged: (value) => setState(() => _showUnit = value),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Tool-specific settings
          _buildToolSpecificSettings(definition),
          const SizedBox(height: 16),

          // Preview
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Preview',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  Container(
                    height: 200,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: SizedBox(
                        width: 300,
                        height: 180,
                        child: registry.buildTool(
                          widget.tool.toolTypeId,
                          ToolConfig(
                            dataSources: widget.tool.config.dataSources,
                            style: StyleConfig(
                              minValue: widget.tool.config.style.minValue,
                              maxValue: widget.tool.config.style.maxValue,
                              unit: widget.tool.config.style.unit,
                              primaryColor: _primaryColor,
                              fontSize: widget.tool.config.style.fontSize,
                              showLabel: _showLabel,
                              showValue: _showValue,
                              showUnit: _showUnit,
                              customProperties: _customProperties,
                            ),
                          ),
                          weatherFlow,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Check if this tool type is a complex widget that doesn't use simple
  /// label/value/unit display options - it has its own section controls instead
  bool _isComplexWidget(String toolTypeId) {
    return const [
      'weatherflow_forecast',
      'weather_alerts',
      'weather_api_spinner',
      'forecast_chart',
      'solar_radiation',
      'sun_moon_arc',
      'history_chart',
      'conditions_dashboard',
    ].contains(toolTypeId);
  }

  Widget _buildToolSpecificSettings(ToolDefinition? definition) {
    final toolTypeId = widget.tool.toolTypeId;

    // Add tool-specific settings based on tool type
    switch (toolTypeId) {
      case 'weather_api_spinner':
        return _buildSpinnerSettings();
      case 'current_conditions':
        return _buildCurrentConditionsSettings();
      case 'wind':
        return _buildWindSettings();
      case 'weatherflow_forecast':
        return _buildForecastSettings();
      case 'weather_alerts':
        return _buildWeatherAlertsSettings();
      case 'forecast_chart':
        return _buildForecastChartSettings();
      case 'solar_radiation':
        return _buildSolarRadiationSettings();
      case 'sun_moon_arc':
        return _buildSunMoonArcSettings();
      case 'history_chart':
        return const SizedBox.shrink(); // Stub - no settings
      case 'conditions_dashboard':
        return _buildConditionsDashboardSettings();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildSpinnerSettings() {
    final showTitle = _customProperties['showTitle'] as bool? ?? true;
    final showAnimation = _customProperties['showAnimation'] as bool? ?? true;
    final forecastDays = _customProperties['forecastDays'] as int? ?? 3;
    final showDateRing = _customProperties['showDateRing'] as bool? ?? true;
    final dateRingMode = _customProperties['dateRingMode'] as String? ?? 'range';
    final showPrimaryIcons = _customProperties['showPrimaryIcons'] as bool? ?? true;
    final showSecondaryIcons = _customProperties['showSecondaryIcons'] as bool? ?? true;
    final showWindCenter = _customProperties['showWindCenter'] as bool? ?? true;
    final showSeaCenter = _customProperties['showSeaCenter'] as bool? ?? true;
    final showSolarCenter = _customProperties['showSolarCenter'] as bool? ?? true;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Forecast Spinner Settings',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('Show Title'),
              subtitle: Text('Display "$_name" in the spinner'),
              secondary: const Icon(Icons.title_outlined),
              value: showTitle,
              onChanged: (value) {
                setState(() => _customProperties['showTitle'] = value);
              },
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              decoration: const InputDecoration(
                labelText: 'Forecast Length',
                border: OutlineInputBorder(),
                helperText: 'Number of days to show in spinner',
              ),
              value: forecastDays,
              items: const [
                DropdownMenuItem(value: 1, child: Text('1 day (24 hours)')),
                DropdownMenuItem(value: 2, child: Text('2 days (48 hours)')),
                DropdownMenuItem(value: 3, child: Text('3 days (72 hours)')),
                DropdownMenuItem(value: 5, child: Text('5 days (120 hours)')),
                DropdownMenuItem(value: 7, child: Text('7 days (168 hours)')),
                DropdownMenuItem(value: 10, child: Text('10 days (240 hours)')),
              ],
              onChanged: (value) {
                setState(() {
                  _customProperties['forecastDays'] = value;
                });
              },
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('Show Weather Animation'),
              subtitle: const Text('Rain, snow, wind effects'),
              value: showAnimation,
              onChanged: (value) {
                setState(() {
                  _customProperties['showAnimation'] = value;
                });
              },
            ),
            const Divider(height: 24),
            Text(
              'Display Options',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('Show Date Ring'),
              subtitle: const Text('Outer ring showing days'),
              value: showDateRing,
              onChanged: (value) {
                setState(() => _customProperties['showDateRing'] = value);
              },
            ),
            if (showDateRing) ...[
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Date Ring Mode',
                    border: OutlineInputBorder(),
                  ),
                  value: dateRingMode,
                  items: const [
                    DropdownMenuItem(value: 'range', child: Text('Forecast Range')),
                    DropdownMenuItem(value: 'year', child: Text('Full Year')),
                  ],
                  onChanged: (value) {
                    setState(() => _customProperties['dateRingMode'] = value);
                  },
                ),
              ),
            ],
            SwitchListTile(
              title: const Text('Show Primary Icons'),
              subtitle: const Text('Sunrise, sunset, moonrise, moonset'),
              value: showPrimaryIcons,
              onChanged: (value) {
                setState(() => _customProperties['showPrimaryIcons'] = value);
              },
            ),
            SwitchListTile(
              title: const Text('Show Secondary Icons'),
              subtitle: const Text('Dawn, dusk, golden hours'),
              value: showSecondaryIcons,
              onChanged: (value) {
                setState(() => _customProperties['showSecondaryIcons'] = value);
              },
            ),
            const Divider(height: 24),
            Text(
              'Center Display Modes',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('Wind Center'),
              subtitle: const Text('Show wind compass display'),
              value: showWindCenter,
              onChanged: (value) {
                setState(() => _customProperties['showWindCenter'] = value);
              },
            ),
            SwitchListTile(
              title: const Text('Sea State Center'),
              subtitle: const Text('Show wave height/period (N/A for WeatherFlow)'),
              value: showSeaCenter,
              onChanged: (value) {
                setState(() => _customProperties['showSeaCenter'] = value);
              },
            ),
            SwitchListTile(
              title: const Text('Solar Center'),
              subtitle: const Text('Show solar radiation display'),
              value: showSolarCenter,
              onChanged: (value) {
                setState(() => _customProperties['showSolarCenter'] = value);
              },
            ),
            const Divider(height: 24),
            // Note about units
            Text(
              'Units are configured globally in Settings',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentConditionsSettings() {
    final tempUnit = _customProperties['tempUnit'] as String? ?? 'F';
    final pressureUnit = _customProperties['pressureUnit'] as String? ?? 'mb';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Current Conditions Settings',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                labelText: 'Temperature Unit',
                border: OutlineInputBorder(),
              ),
              value: tempUnit,
              items: const [
                DropdownMenuItem(value: 'F', child: Text('Fahrenheit (°F)')),
                DropdownMenuItem(value: 'C', child: Text('Celsius (°C)')),
              ],
              onChanged: (value) {
                setState(() {
                  _customProperties['tempUnit'] = value;
                });
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                labelText: 'Pressure Unit',
                border: OutlineInputBorder(),
              ),
              value: pressureUnit,
              items: const [
                DropdownMenuItem(value: 'mb', child: Text('Millibars (mb)')),
                DropdownMenuItem(value: 'hPa', child: Text('Hectopascals (hPa)')),
                DropdownMenuItem(value: 'inHg', child: Text('Inches of mercury (inHg)')),
              ],
              onChanged: (value) {
                setState(() {
                  _customProperties['pressureUnit'] = value;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWindSettings() {
    final windUnit = _customProperties['windUnit'] as String? ?? 'mph';
    final showDirection = _customProperties['showDirection'] as bool? ?? true;
    final showGust = _customProperties['showGust'] as bool? ?? true;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Wind Tool Settings',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                labelText: 'Wind Unit',
                border: OutlineInputBorder(),
              ),
              value: windUnit,
              items: const [
                DropdownMenuItem(value: 'mph', child: Text('Miles per hour (mph)')),
                DropdownMenuItem(value: 'kn', child: Text('Knots (kn)')),
                DropdownMenuItem(value: 'm/s', child: Text('Meters per second (m/s)')),
                DropdownMenuItem(value: 'km/h', child: Text('Kilometers per hour (km/h)')),
              ],
              onChanged: (value) {
                setState(() {
                  _customProperties['windUnit'] = value;
                });
              },
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('Show Wind Direction'),
              value: showDirection,
              onChanged: (value) {
                setState(() {
                  _customProperties['showDirection'] = value;
                });
              },
            ),
            SwitchListTile(
              title: const Text('Show Wind Gust'),
              value: showGust,
              onChanged: (value) {
                setState(() {
                  _customProperties['showGust'] = value;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeatherAlertsSettings() {
    // Current settings
    final showTitle = _customProperties['showTitle'] as bool? ?? true;
    final compact = _customProperties['compact'] as bool? ?? false;
    final locationSource = _customProperties['locationSource'] as String? ?? 'both';
    final refreshInterval = _customProperties['refreshInterval'] as int? ?? 5;
    final showDescription = _customProperties['showDescription'] as bool? ?? true;
    final showInstruction = _customProperties['showInstruction'] as bool? ?? true;
    final showAreaDesc = _customProperties['showAreaDesc'] as bool? ?? false;
    final showSenderName = _customProperties['showSenderName'] as bool? ?? false;
    final showTimeRange = _customProperties['showTimeRange'] as bool? ?? true;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Weather Alerts Settings',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('Show Title'),
              subtitle: Text('Display "${_name}" as header'),
              secondary: const Icon(Icons.title_outlined),
              value: showTitle,
              onChanged: (value) {
                setState(() => _customProperties['showTitle'] = value);
              },
            ),
            const Divider(),
            const SizedBox(height: 8),

            // Location Source
            Text(
              'Location Source',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
                helperText: 'Where to check for alerts',
              ),
              value: locationSource,
              items: const [
                DropdownMenuItem(
                  value: 'phone',
                  child: Text('Phone Location (GPS)'),
                ),
                DropdownMenuItem(
                  value: 'station',
                  child: Text('Station Location'),
                ),
                DropdownMenuItem(
                  value: 'both',
                  child: Text('Both (deduplicated)'),
                ),
              ],
              onChanged: (value) {
                setState(() => _customProperties['locationSource'] = value);
              },
            ),

            const SizedBox(height: 16),

            // Refresh Interval
            DropdownButtonFormField<int>(
              decoration: const InputDecoration(
                labelText: 'Refresh Interval',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              value: refreshInterval,
              items: const [
                DropdownMenuItem(value: 1, child: Text('1 minute')),
                DropdownMenuItem(value: 5, child: Text('5 minutes')),
                DropdownMenuItem(value: 10, child: Text('10 minutes')),
                DropdownMenuItem(value: 15, child: Text('15 minutes')),
                DropdownMenuItem(value: 30, child: Text('30 minutes')),
              ],
              onChanged: (value) {
                setState(() => _customProperties['refreshInterval'] = value);
              },
            ),

            const Divider(height: 24),

            // Display Options
            Text(
              'Display Options',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),

            SwitchListTile(
              title: const Text('Compact Mode'),
              subtitle: const Text('Show condensed view with tap to expand'),
              value: compact,
              onChanged: (value) {
                setState(() => _customProperties['compact'] = value);
              },
            ),

            const Divider(height: 16),

            // Component visibility
            Text(
              'Show Components',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),

            SwitchListTile(
              title: const Text('Time Range'),
              subtitle: const Text('Show onset and end times'),
              value: showTimeRange,
              onChanged: (value) {
                setState(() => _customProperties['showTimeRange'] = value);
              },
            ),

            SwitchListTile(
              title: const Text('Description'),
              subtitle: const Text('Full alert description text'),
              value: showDescription,
              onChanged: (value) {
                setState(() => _customProperties['showDescription'] = value);
              },
            ),

            SwitchListTile(
              title: const Text('Instructions'),
              subtitle: const Text('Safety instructions from NWS'),
              value: showInstruction,
              onChanged: (value) {
                setState(() => _customProperties['showInstruction'] = value);
              },
            ),

            SwitchListTile(
              title: const Text('Affected Areas'),
              subtitle: const Text('List of counties/regions'),
              value: showAreaDesc,
              onChanged: (value) {
                setState(() => _customProperties['showAreaDesc'] = value);
              },
            ),

            SwitchListTile(
              title: const Text('Source'),
              subtitle: const Text('NWS office name'),
              value: showSenderName,
              onChanged: (value) {
                setState(() => _customProperties['showSenderName'] = value);
              },
            ),

            const Divider(height: 16),

            // Severity legend
            Text(
              'Alert Severity Levels',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),

            _buildSeverityLegend(),
          ],
        ),
      ),
    );
  }

  Widget _buildSeverityLegend() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            _severityRow('Extreme', Colors.purple.shade700, 'Tornado, Hurricane'),
            _severityRow('Severe', Colors.red.shade700, 'Severe Thunderstorm, Blizzard'),
            _severityRow('Moderate', Colors.orange.shade700, 'Winter Storm, Wind Advisory'),
            _severityRow('Minor', Colors.yellow.shade700, 'Frost, Freeze'),
          ],
        ),
      ),
    );
  }

  Widget _severityRow(String level, Color color, String examples) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 70,
            child: Text(
              level,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: color,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              examples,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForecastSettings() {
    final weatherFlow = context.watch<WeatherFlowService>();
    final station = weatherFlow.selectedStation;
    final sensorDevices = station?.sensorDevices ?? [];

    // Section visibility
    final showTitle = _customProperties['showTitle'] as bool? ?? true;
    final showSunMoonArc = _customProperties['showSunMoonArc'] as bool? ?? true;
    final showCurrentConditions = _customProperties['showCurrentConditions'] as bool? ?? true;
    final showDailyForecast = _customProperties['showDailyForecast'] as bool? ?? true;

    // Display options
    final use24HourFormat = _customProperties['use24HourFormat'] as bool? ?? false;

    // Current device source selections
    final tempSource = _customProperties['tempSource'] as String? ?? 'auto';
    final humiditySource = _customProperties['humiditySource'] as String? ?? 'auto';
    final pressureSource = _customProperties['pressureSource'] as String? ?? 'auto';
    final windSource = _customProperties['windSource'] as String? ?? 'auto';
    final lightSource = _customProperties['lightSource'] as String? ?? 'auto';
    final rainSource = _customProperties['rainSource'] as String? ?? 'auto';
    final lightningSource = _customProperties['lightningSource'] as String? ?? 'auto';

    // Filter options by device capability
    // ST (Tempest): all measurements
    // AR (Air): temp, humidity, pressure, lightning
    // SK (Sky): wind, light, rain
    final atmosphericDevices = sensorDevices.where(
      (d) => d.deviceType == 'ST' || d.deviceType == 'AR',
    ).toList();
    final windDevices = sensorDevices.where(
      (d) => d.deviceType == 'ST' || d.deviceType == 'SK',
    ).toList();

    List<DropdownMenuItem<String>> buildOptionsFor(List<dynamic> devices) {
      return [
        const DropdownMenuItem(
          value: 'auto',
          child: Text('Auto (best available)'),
        ),
        ...devices.map((device) => DropdownMenuItem(
          value: device.serialNumber,
          child: Text('${device.deviceTypeName} (${device.serialNumber})'),
        )),
      ];
    }

    final atmosphericOptions = buildOptionsFor(atmosphericDevices);
    final windOptions = buildOptionsFor(windDevices);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section Visibility
            Text(
              'Sections',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Choose which sections to display in the widget',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('Title'),
              subtitle: Text('Show "${_name}" as widget header'),
              secondary: const Icon(Icons.title_outlined),
              value: showTitle,
              onChanged: (value) {
                setState(() => _customProperties['showTitle'] = value);
              },
            ),
            SwitchListTile(
              title: const Text('Sun/Moon Arc'),
              subtitle: const Text('Show day/night arc with sunrise/sunset'),
              secondary: const Icon(Icons.wb_sunny_outlined),
              value: showSunMoonArc,
              onChanged: (value) {
                setState(() => _customProperties['showSunMoonArc'] = value);
              },
            ),
            SwitchListTile(
              title: const Text('Current Conditions'),
              subtitle: const Text('Show live temperature, humidity, wind, etc.'),
              secondary: const Icon(Icons.thermostat_outlined),
              value: showCurrentConditions,
              onChanged: (value) {
                setState(() => _customProperties['showCurrentConditions'] = value);
              },
            ),
            SwitchListTile(
              title: const Text('Daily Forecast'),
              subtitle: const Text('Show multi-day weather forecast'),
              secondary: const Icon(Icons.calendar_today_outlined),
              value: showDailyForecast,
              onChanged: (value) {
                setState(() => _customProperties['showDailyForecast'] = value);
              },
            ),
            const SizedBox(height: 8),
            const Divider(),
            const SizedBox(height: 16),

            // Time Format Option
            Text(
              'Display Options',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Time Format',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment<bool>(
                      value: false,
                      label: Text('12h'),
                      icon: Icon(Icons.schedule, size: 16),
                    ),
                    ButtonSegment<bool>(
                      value: true,
                      label: Text('24h'),
                      icon: Icon(Icons.access_time, size: 16),
                    ),
                  ],
                  selected: {use24HourFormat},
                  onSelectionChanged: (selected) {
                    setState(() => _customProperties['use24HourFormat'] = selected.first);
                  },
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              use24HourFormat ? 'Using 24-hour (military) format: 14:30' : 'Using 12-hour format: 2:30 PM',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),

            Text(
              'Device Sources',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Select which device to use for each measurement type. '
              'Air devices provide atmospheric data (temp, humidity, pressure, lightning). '
              'Sky devices provide wind, light, and rain data. '
              'Tempest provides all measurements.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),

            if (sensorDevices.isEmpty) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning, color: Colors.orange),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'No devices found. Select a station first.',
                        style: TextStyle(color: Colors.orange.shade700),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // Show available devices
              Text(
                'Available Devices:',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              ...sensorDevices.map((device) => Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 4),
                child: Row(
                  children: [
                    Icon(
                      device.deviceType == 'ST' ? Icons.all_inclusive :
                      device.deviceType == 'AR' ? Icons.thermostat :
                      Icons.air,
                      size: 16,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${device.deviceTypeName}: ${device.serialNumber}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      device.deviceType == 'ST' ? '(all data)' :
                      device.deviceType == 'AR' ? '(atmospheric)' :
                      '(wind/light/rain)',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              )),
              const Divider(height: 24),

              // Atmospheric measurements (temp, humidity, pressure, lightning)
              Text(
                'Atmospheric Data (Air/Tempest)',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: 'Temperature Source',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                value: atmosphericOptions.any((o) => o.value == tempSource) ? tempSource : 'auto',
                items: atmosphericOptions,
                onChanged: (value) {
                  setState(() => _customProperties['tempSource'] = value);
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: 'Humidity Source',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                value: atmosphericOptions.any((o) => o.value == humiditySource) ? humiditySource : 'auto',
                items: atmosphericOptions,
                onChanged: (value) {
                  setState(() => _customProperties['humiditySource'] = value);
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: 'Pressure Source',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                value: atmosphericOptions.any((o) => o.value == pressureSource) ? pressureSource : 'auto',
                items: atmosphericOptions,
                onChanged: (value) {
                  setState(() => _customProperties['pressureSource'] = value);
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: 'Lightning Source',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                value: atmosphericOptions.any((o) => o.value == lightningSource) ? lightningSource : 'auto',
                items: atmosphericOptions,
                onChanged: (value) {
                  setState(() => _customProperties['lightningSource'] = value);
                },
              ),

              const Divider(height: 24),

              // Wind/Light/Rain measurements (Sky/Tempest)
              Text(
                'Wind & Precipitation Data (Sky/Tempest)',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: 'Wind Source',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                value: windOptions.any((o) => o.value == windSource) ? windSource : 'auto',
                items: windOptions,
                onChanged: (value) {
                  setState(() => _customProperties['windSource'] = value);
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: 'Light/UV Source',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                value: windOptions.any((o) => o.value == lightSource) ? lightSource : 'auto',
                items: windOptions,
                onChanged: (value) {
                  setState(() => _customProperties['lightSource'] = value);
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: 'Rain Source',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                value: windOptions.any((o) => o.value == rainSource) ? rainSource : 'auto',
                items: windOptions,
                onChanged: (value) {
                  setState(() => _customProperties['rainSource'] = value);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildForecastChartSettings() {
    final dataElement = _customProperties['dataElement'] as String? ?? 'temperature';
    final chartMode = _customProperties['chartMode'] as String? ?? 'combo';
    final chartStyle = _customProperties['chartStyle'] as String? ?? 'spline';
    final forecastDays = _customProperties['forecastDays'] as int? ?? 3;
    final showGrid = _customProperties['showGrid'] as bool? ?? true;
    final showLegend = _customProperties['showLegend'] as bool? ?? true;
    final showDataPoints = _customProperties['showDataPoints'] as bool? ?? false;

    // Data elements depend on chart mode
    final isHourly = chartMode == 'hourly';
    final isCombo = chartMode == 'combo';

    final hourlyElements = {
      'temperature': 'Temperature',
      'feels_like': 'Feels Like',
      'precipitation_probability': 'Precip Probability',
      'humidity': 'Humidity',
      'pressure': 'Pressure',
      'wind_speed': 'Wind Speed',
    };

    final dailyElements = {
      'temperature_high': 'Temperature (High)',
      'temperature_low': 'Temperature (Low)',
      'temperature_range': 'Temperature Range',
      'precipitation_probability': 'Precip Probability',
    };

    final dataElements = (isHourly || isCombo) ? hourlyElements : dailyElements;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Forecast Chart Settings',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),

            // Chart Mode
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                labelText: 'Chart Mode',
                border: OutlineInputBorder(),
              ),
              value: chartMode,
              items: const [
                DropdownMenuItem(value: 'combo', child: Text('Combo (Daily + Range)')),
                DropdownMenuItem(value: 'hourly', child: Text('Hourly')),
                DropdownMenuItem(value: 'daily', child: Text('Daily')),
              ],
              onChanged: (value) {
                setState(() {
                  _customProperties['chartMode'] = value;
                  // Reset data element if switching modes
                  if (value == 'daily' && !dailyElements.containsKey(dataElement)) {
                    _customProperties['dataElement'] = 'temperature_high';
                  } else if ((value == 'hourly' || value == 'combo') && !hourlyElements.containsKey(dataElement)) {
                    _customProperties['dataElement'] = 'temperature';
                  }
                });
              },
            ),
            const SizedBox(height: 12),

            // Data Element
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                labelText: 'Data Element',
                border: OutlineInputBorder(),
              ),
              value: dataElements.containsKey(dataElement) ? dataElement : dataElements.keys.first,
              items: dataElements.entries
                  .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: (value) {
                setState(() => _customProperties['dataElement'] = value);
              },
            ),
            const SizedBox(height: 12),

            // Chart Style (only for non-combo modes)
            if (chartMode != 'combo')
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: 'Chart Style',
                  border: OutlineInputBorder(),
                ),
                value: chartStyle,
                items: const [
                  DropdownMenuItem(value: 'spline', child: Text('Line')),
                  DropdownMenuItem(value: 'splineFilled', child: Text('Filled Line')),
                  DropdownMenuItem(value: 'bar', child: Text('Bar Chart')),
                ],
                onChanged: (value) {
                  setState(() => _customProperties['chartStyle'] = value);
                },
              ),
            if (chartMode != 'combo') const SizedBox(height: 12),

            // Forecast Days
            DropdownButtonFormField<int>(
              decoration: const InputDecoration(
                labelText: 'Forecast Days',
                border: OutlineInputBorder(),
              ),
              value: forecastDays,
              items: const [
                DropdownMenuItem(value: 1, child: Text('1 day')),
                DropdownMenuItem(value: 2, child: Text('2 days')),
                DropdownMenuItem(value: 3, child: Text('3 days')),
                DropdownMenuItem(value: 5, child: Text('5 days')),
                DropdownMenuItem(value: 7, child: Text('7 days')),
                DropdownMenuItem(value: 10, child: Text('10 days')),
              ],
              onChanged: (value) {
                setState(() => _customProperties['forecastDays'] = value);
              },
            ),

            const Divider(height: 24),

            // Display Options
            SwitchListTile(
              title: const Text('Show Grid'),
              value: showGrid,
              onChanged: (value) {
                setState(() => _customProperties['showGrid'] = value);
              },
            ),
            SwitchListTile(
              title: const Text('Show Legend'),
              value: showLegend,
              onChanged: (value) {
                setState(() => _customProperties['showLegend'] = value);
              },
            ),
            SwitchListTile(
              title: const Text('Show Data Points'),
              value: showDataPoints,
              onChanged: (value) {
                setState(() => _customProperties['showDataPoints'] = value);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSolarRadiationSettings() {
    final showBarChart = _customProperties['showBarChart'] as bool? ?? true;
    final showDailyTotal = _customProperties['showDailyTotal'] as bool? ?? true;
    final showCurrentPower = _customProperties['showCurrentPower'] as bool? ?? true;
    final showDailyView = _customProperties['showDailyView'] as bool? ?? true;
    final dailyViewMode = _customProperties['dailyViewMode'] as String? ?? 'cards';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Solar Radiation Settings',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Shows estimated solar panel output based on forecast irradiance data.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),

            // Display Sections
            SwitchListTile(
              title: const Text('Show Hourly Chart'),
              subtitle: const Text('Power output throughout the day'),
              value: showBarChart,
              onChanged: (value) {
                setState(() => _customProperties['showBarChart'] = value);
              },
            ),
            SwitchListTile(
              title: const Text('Show Daily Total'),
              subtitle: const Text('Estimated kWh in header'),
              value: showDailyTotal,
              onChanged: (value) {
                setState(() => _customProperties['showDailyTotal'] = value);
              },
            ),
            SwitchListTile(
              title: const Text('Show Current Power'),
              subtitle: const Text('Real-time output when viewing today'),
              value: showCurrentPower,
              onChanged: (value) {
                setState(() => _customProperties['showCurrentPower'] = value);
              },
            ),
            SwitchListTile(
              title: const Text('Show Daily View'),
              subtitle: const Text('Multi-day forecast section'),
              value: showDailyView,
              onChanged: (value) {
                setState(() => _customProperties['showDailyView'] = value);
              },
            ),

            if (showDailyView) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: 'Daily View Style',
                  border: OutlineInputBorder(),
                ),
                value: dailyViewMode,
                items: const [
                  DropdownMenuItem(value: 'cards', child: Text('Scrollable Cards')),
                  DropdownMenuItem(value: 'chart', child: Text('Bar Chart')),
                ],
                onChanged: (value) {
                  setState(() => _customProperties['dailyViewMode'] = value);
                },
              ),
            ],

            const Divider(height: 24),

            // Note about panel config
            Text(
              'Panel capacity is configured in Settings → Solar Panel.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSunMoonArcSettings() {
    final showTitle = _customProperties['showTitle'] as bool? ?? false;
    final arcStyle = _customProperties['arcStyle'] as String? ?? 'half';
    final use24HourFormat = _customProperties['use24HourFormat'] as bool? ?? false;
    final showTimeLabels = _customProperties['showTimeLabels'] as bool? ?? true;
    final showSunMarkers = _customProperties['showSunMarkers'] as bool? ?? true;
    final showMoonMarkers = _customProperties['showMoonMarkers'] as bool? ?? true;
    final showTwilightSegments = _customProperties['showTwilightSegments'] as bool? ?? true;
    final showCenterIndicator = _customProperties['showCenterIndicator'] as bool? ?? true;
    final showSecondaryIcons = _customProperties['showSecondaryIcons'] as bool? ?? true;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sun/Moon Arc Settings',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),

            // Arc Style
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                labelText: 'Arc Style',
                border: OutlineInputBorder(),
              ),
              value: arcStyle,
              items: const [
                DropdownMenuItem(value: 'half', child: Text('Half Circle (180°)')),
                DropdownMenuItem(value: 'threeQuarter', child: Text('Three Quarter (270°)')),
                DropdownMenuItem(value: 'wide', child: Text('Wide Arc (240°)')),
                DropdownMenuItem(value: 'full', child: Text('Full Circle (360°)')),
              ],
              onChanged: (value) {
                setState(() => _customProperties['arcStyle'] = value);
              },
            ),

            const Divider(height: 24),

            // Display Options
            SwitchListTile(
              title: const Text('Show Title'),
              subtitle: Text('Display "${_name}" as header'),
              value: showTitle,
              onChanged: (value) {
                setState(() => _customProperties['showTitle'] = value);
              },
            ),
            SwitchListTile(
              title: const Text('24-Hour Format'),
              subtitle: const Text('Use 14:30 instead of 2:30 PM'),
              value: use24HourFormat,
              onChanged: (value) {
                setState(() => _customProperties['use24HourFormat'] = value);
              },
            ),
            SwitchListTile(
              title: const Text('Show Time Labels'),
              subtitle: const Text('Sunrise/sunset times on arc'),
              value: showTimeLabels,
              onChanged: (value) {
                setState(() => _customProperties['showTimeLabels'] = value);
              },
            ),

            const Divider(height: 16),
            Text(
              'Markers & Indicators',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),

            SwitchListTile(
              title: const Text('Sun Markers'),
              subtitle: const Text('Sunrise and sunset icons'),
              value: showSunMarkers,
              onChanged: (value) {
                setState(() => _customProperties['showSunMarkers'] = value);
              },
            ),
            SwitchListTile(
              title: const Text('Moon Markers'),
              subtitle: const Text('Moonrise and moonset icons'),
              value: showMoonMarkers,
              onChanged: (value) {
                setState(() => _customProperties['showMoonMarkers'] = value);
              },
            ),
            SwitchListTile(
              title: const Text('Twilight Segments'),
              subtitle: const Text('Color-coded dawn/dusk regions'),
              value: showTwilightSegments,
              onChanged: (value) {
                setState(() => _customProperties['showTwilightSegments'] = value);
              },
            ),
            SwitchListTile(
              title: const Text('Center Indicator'),
              subtitle: const Text('Current sun position marker'),
              value: showCenterIndicator,
              onChanged: (value) {
                setState(() => _customProperties['showCenterIndicator'] = value);
              },
            ),
            SwitchListTile(
              title: const Text('Secondary Icons'),
              subtitle: const Text('Dawn, dusk, golden hour markers'),
              value: showSecondaryIcons,
              onChanged: (value) {
                setState(() => _customProperties['showSecondaryIcons'] = value);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConditionsDashboardSettings() {
    final showTitle = _customProperties['showTitle'] as bool? ?? true;
    final cardSize = _customProperties['cardSize'] as String? ?? 'normal';
    final showIndicators = _customProperties['showIndicators'] as bool? ?? true;
    final columns = _customProperties['columns'] as int? ?? 4;

    // Variable visibility
    final showTemperature = _customProperties['showTemperature'] as bool? ?? true;
    final showFeelsLike = _customProperties['showFeelsLike'] as bool? ?? true;
    final showHumidity = _customProperties['showHumidity'] as bool? ?? true;
    final showPressure = _customProperties['showPressure'] as bool? ?? true;
    final showWindSpeed = _customProperties['showWindSpeed'] as bool? ?? true;
    final showWindGust = _customProperties['showWindGust'] as bool? ?? true;
    final showRainRate = _customProperties['showRainRate'] as bool? ?? true;
    final showRainAccumulated = _customProperties['showRainAccumulated'] as bool? ?? true;
    final showUvIndex = _customProperties['showUvIndex'] as bool? ?? true;
    final showSolarRadiation = _customProperties['showSolarRadiation'] as bool? ?? true;
    final showPrecipType = _customProperties['showPrecipType'] as bool? ?? true;
    final showLightning = _customProperties['showLightning'] as bool? ?? true;
    final showBattery = _customProperties['showBattery'] as bool? ?? true;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Conditions Dashboard Settings',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Tap any card to view historical charts and forecast.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),

            // Display Options
            SwitchListTile(
              title: const Text('Show Title'),
              subtitle: Text('Display "${_name}" as header'),
              value: showTitle,
              onChanged: (value) {
                setState(() => _customProperties['showTitle'] = value);
              },
            ),
            SwitchListTile(
              title: const Text('Show Indicators'),
              subtitle: const Text('Progress bars on cards'),
              value: showIndicators,
              onChanged: (value) {
                setState(() => _customProperties['showIndicators'] = value);
              },
            ),

            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                labelText: 'Card Size',
                border: OutlineInputBorder(),
              ),
              value: cardSize,
              items: const [
                DropdownMenuItem(value: 'compact', child: Text('Compact')),
                DropdownMenuItem(value: 'normal', child: Text('Normal')),
              ],
              onChanged: (value) {
                setState(() => _customProperties['cardSize'] = value);
              },
            ),

            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              decoration: const InputDecoration(
                labelText: 'Columns',
                border: OutlineInputBorder(),
              ),
              value: columns,
              items: const [
                DropdownMenuItem(value: 2, child: Text('2 columns')),
                DropdownMenuItem(value: 3, child: Text('3 columns')),
                DropdownMenuItem(value: 4, child: Text('4 columns')),
                DropdownMenuItem(value: 5, child: Text('5 columns')),
                DropdownMenuItem(value: 6, child: Text('6 columns')),
              ],
              onChanged: (value) {
                setState(() => _customProperties['columns'] = value);
              },
            ),

            const Divider(height: 24),

            // Variable Visibility
            Text(
              'Variables to Display',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),

            SwitchListTile(
              title: const Text('Temperature'),
              dense: true,
              value: showTemperature,
              onChanged: (value) {
                setState(() => _customProperties['showTemperature'] = value);
              },
            ),
            SwitchListTile(
              title: const Text('Feels Like'),
              dense: true,
              value: showFeelsLike,
              onChanged: (value) {
                setState(() => _customProperties['showFeelsLike'] = value);
              },
            ),
            SwitchListTile(
              title: const Text('Humidity'),
              dense: true,
              value: showHumidity,
              onChanged: (value) {
                setState(() => _customProperties['showHumidity'] = value);
              },
            ),
            SwitchListTile(
              title: const Text('Pressure'),
              dense: true,
              value: showPressure,
              onChanged: (value) {
                setState(() => _customProperties['showPressure'] = value);
              },
            ),
            SwitchListTile(
              title: const Text('Wind Speed'),
              dense: true,
              value: showWindSpeed,
              onChanged: (value) {
                setState(() => _customProperties['showWindSpeed'] = value);
              },
            ),
            SwitchListTile(
              title: const Text('Wind Gust'),
              dense: true,
              value: showWindGust,
              onChanged: (value) {
                setState(() => _customProperties['showWindGust'] = value);
              },
            ),
            SwitchListTile(
              title: const Text('Rain Rate'),
              dense: true,
              value: showRainRate,
              onChanged: (value) {
                setState(() => _customProperties['showRainRate'] = value);
              },
            ),
            SwitchListTile(
              title: const Text('Rain Accumulated'),
              dense: true,
              value: showRainAccumulated,
              onChanged: (value) {
                setState(() => _customProperties['showRainAccumulated'] = value);
              },
            ),
            SwitchListTile(
              title: const Text('UV Index'),
              dense: true,
              value: showUvIndex,
              onChanged: (value) {
                setState(() => _customProperties['showUvIndex'] = value);
              },
            ),
            SwitchListTile(
              title: const Text('Solar Radiation'),
              dense: true,
              value: showSolarRadiation,
              onChanged: (value) {
                setState(() => _customProperties['showSolarRadiation'] = value);
              },
            ),
            SwitchListTile(
              title: const Text('Precip Type'),
              subtitle: const Text('Rain, snow, hail, etc.'),
              dense: true,
              value: showPrecipType,
              onChanged: (value) {
                setState(() => _customProperties['showPrecipType'] = value);
              },
            ),
            SwitchListTile(
              title: const Text('Lightning'),
              dense: true,
              value: showLightning,
              onChanged: (value) {
                setState(() => _customProperties['showLightning'] = value);
              },
            ),
            SwitchListTile(
              title: const Text('Battery'),
              dense: true,
              value: showBattery,
              onChanged: (value) {
                setState(() => _customProperties['showBattery'] = value);
              },
            ),

            const Divider(height: 16),

            // Note about units
            Text(
              'Units are configured globally in Settings',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getCategoryIcon(ToolCategory category) {
    switch (category) {
      case ToolCategory.weather:
        return Icons.cloud;
      case ToolCategory.instruments:
        return Icons.speed;
      case ToolCategory.charts:
        return Icons.show_chart;
      case ToolCategory.controls:
        return Icons.toggle_on;
      case ToolCategory.system:
        return Icons.settings;
    }
  }

  Color _getCategoryColor(ToolCategory category) {
    switch (category) {
      case ToolCategory.weather:
        return Colors.orange;
      case ToolCategory.instruments:
        return Colors.teal;
      case ToolCategory.charts:
        return Colors.green;
      case ToolCategory.controls:
        return Colors.purple;
      case ToolCategory.system:
        return Colors.red.shade700;
    }
  }
}
