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

          // Size Configuration
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Default Size',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Width (columns)'),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              children: [1, 2, 3, 4, 5, 6, 7, 8].map((width) {
                                return ChoiceChip(
                                  label: Text('$width'),
                                  selected: _toolWidth == width,
                                  onSelected: (_) => setState(() => _toolWidth = width),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Height (rows)'),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              children: [1, 2, 3, 4, 5, 6, 7, 8].map((height) {
                                return ChoiceChip(
                                  label: Text('$height'),
                                  selected: _toolHeight == height,
                                  onSelected: (_) => setState(() => _toolHeight = height),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Size: $_toolWidth × $_toolHeight cells',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
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
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildSpinnerSettings() {
    final tempUnit = _customProperties['tempUnit'] as String? ?? 'F';
    final windUnit = _customProperties['windUnit'] as String? ?? 'mph';
    final showAnimation = _customProperties['showAnimation'] as bool? ?? true;
    final forecastDays = _customProperties['forecastDays'] as int? ?? 3;

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
            const SizedBox(height: 16),
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
              title: const Text('Show Weather Animation'),
              value: showAnimation,
              onChanged: (value) {
                setState(() {
                  _customProperties['showAnimation'] = value;
                });
              },
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
            Text(
              'Displays NWS weather alerts for your location',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),

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
