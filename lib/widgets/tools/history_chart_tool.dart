/// History Chart Tool
/// Stub implementation - WeatherFlow API does not provide historical weather data
/// This placeholder shows a message directing users to use forecast data instead

import 'package:flutter/material.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../services/tool_registry.dart';
import '../../services/weatherflow_service.dart';

/// Builder for History Chart tool (stub)
class HistoryChartToolBuilder implements ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return const ToolDefinition(
      id: 'history_chart',
      name: 'History Chart',
      description: 'Historical weather data (not available with WeatherFlow)',
      category: ToolCategory.charts,
      configSchema: ConfigSchema(
        allowsMinMax: false,
        allowsColorCustomization: true,
        allowsMultiplePaths: false,
        minPaths: 0,
        maxPaths: 0,
        styleOptions: [],
      ),
      defaultWidth: 4,
      defaultHeight: 3,
    );
  }

  @override
  Widget build(ToolConfig config, WeatherFlowService weatherFlowService, {bool isEditMode = false, String? name}) {
    return HistoryChartTool(
      config: config,
      weatherFlowService: weatherFlowService,
      isEditMode: isEditMode,
      name: name,
    );
  }

  @override
  ToolConfig? getDefaultConfig() {
    return const ToolConfig(
      dataSources: [],
      style: StyleConfig(
        primaryColor: '#4A90D9',
        customProperties: {},
      ),
    );
  }
}

/// History Chart display widget (stub)
class HistoryChartTool extends StatelessWidget {
  final ToolConfig config;
  final WeatherFlowService weatherFlowService;
  final bool isEditMode;
  final String? name;

  const HistoryChartTool({
    super.key,
    required this.config,
    required this.weatherFlowService,
    this.isEditMode = false,
    this.name,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.history,
              size: 48,
              color: isDark ? Colors.white38 : Colors.black26,
            ),
            const SizedBox(height: 16),
            Text(
              'Historical Data',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Historical weather data is not available through the WeatherFlow API.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? Colors.white54 : Colors.black45,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Use the Forecast Chart tool for weather trends.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white38 : Colors.black26,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
