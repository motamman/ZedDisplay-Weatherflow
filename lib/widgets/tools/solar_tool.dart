/// Solar Radiation Tool
/// Wrapper tool for the SolarRadiationWidget
/// Ported from ZedDisplay-OpenMeteo

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../services/tool_registry.dart';
import '../../services/weatherflow_service.dart';
import '../../services/solar_calculation_service.dart';
import '../solar_radiation.dart';

/// Builder for Solar Radiation tool
class SolarToolBuilder implements ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return const ToolDefinition(
      id: 'solar_radiation',
      name: 'Solar Radiation',
      description: 'Solar energy potential and panel output forecast',
      category: ToolCategory.weather,
      configSchema: ConfigSchema(
        allowsMinMax: false,
        allowsColorCustomization: true,
        allowsMultiplePaths: false,
        minPaths: 0,
        maxPaths: 0,
        styleOptions: ['showBarChart', 'showDailyTotal', 'showCurrentPower', 'showDailyView', 'dailyViewMode'],
      ),
      defaultWidth: 8,
      defaultHeight: 5,
    );
  }

  @override
  Widget build(
    ToolConfig config,
    WeatherFlowService weatherFlowService, {
    bool isEditMode = false,
    String? name,
  }) {
    return SolarTool(
      config: config,
      weatherFlowService: weatherFlowService,
    );
  }

  @override
  ToolConfig? getDefaultConfig() {
    return const ToolConfig(
      dataSources: [],
      style: StyleConfig(
        primaryColor: '#FF9800', // Orange
        customProperties: {
          'showBarChart': true,
          'showDailyTotal': true,
          'showCurrentPower': true,
          'showDailyView': true,
          'dailyViewMode': 'cards',
        },
      ),
    );
  }
}

/// Tool widget that wraps SolarRadiationWidget
class SolarTool extends StatelessWidget {
  final ToolConfig config;
  final WeatherFlowService weatherFlowService;

  const SolarTool({
    super.key,
    required this.config,
    required this.weatherFlowService,
  });

  /// Build widget config from tool config
  SolarRadiationConfig _buildWidgetConfig() {
    final props = config.style.customProperties ?? {};
    final primaryColorHex = config.style.primaryColor;
    Color? primaryColor;

    if (primaryColorHex != null && primaryColorHex.isNotEmpty) {
      try {
        final hex = primaryColorHex.replaceFirst('#', '');
        primaryColor = Color(int.parse('FF$hex', radix: 16));
      } catch (_) {
        primaryColor = null;
      }
    }

    return SolarRadiationConfig(
      showBarChart: props['showBarChart'] as bool? ?? true,
      showDailyTotal: props['showDailyTotal'] as bool? ?? true,
      showCurrentPower: props['showCurrentPower'] as bool? ?? true,
      showDailyView: props['showDailyView'] as bool? ?? true,
      dailyViewMode: props['dailyViewMode'] as String? ?? 'cards',
      primaryColor: primaryColor,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Get system-wide solar config
    final solarService = context.watch<SolarCalculationService>();

    // ListenableBuilder rebuilds when weather data changes
    return ListenableBuilder(
      listenable: weatherFlowService,
      builder: (context, _) {
        final hourlyForecasts = weatherFlowService.displayHourlyForecasts;
        final dailyForecasts = weatherFlowService.displayDailyForecasts;

        if (hourlyForecasts.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.wb_sunny_outlined, size: 32, color: Colors.orange),
                SizedBox(height: 8),
                Text('Loading solar data...'),
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.all(4.0),
          child: SolarRadiationWidget(
            hourlyForecasts: hourlyForecasts,
            dailyForecasts: dailyForecasts,
            sunMoonTimes: weatherFlowService.sunMoonTimes,
            panelMaxWatts: solarService.panelMaxWatts,
            systemDerate: solarService.systemDerate,
            config: _buildWidgetConfig(),
            conversions: weatherFlowService.conversions,
          ),
        );
      },
    );
  }
}
