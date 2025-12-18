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

  void _loadTool() {
    final tool = widget.tool;
    _name = tool.name;
    _primaryColor = tool.config.style.primaryColor;
    _showLabel = tool.config.style.showLabel ?? true;
    _showValue = tool.config.style.showValue ?? true;
    _showUnit = tool.config.style.showUnit ?? true;
    _toolWidth = widget.currentWidth ?? tool.defaultWidth;
    _toolHeight = widget.currentHeight ?? tool.defaultHeight;
    _customProperties = Map<String, dynamic>.from(tool.config.style.customProperties ?? {});
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

    final updatedStyle = StyleConfig(
      minValue: widget.tool.config.style.minValue,
      maxValue: widget.tool.config.style.maxValue,
      unit: widget.tool.config.style.unit,
      primaryColor: _primaryColor,
      fontSize: widget.tool.config.style.fontSize,
      showLabel: _showLabel,
      showValue: _showValue,
      showUnit: _showUnit,
      customProperties: _customProperties,
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

          // Style Configuration
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
