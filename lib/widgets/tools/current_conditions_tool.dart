/// Current Conditions Tool for WeatherFlow
/// Displays temperature, humidity, pressure summary

import 'package:flutter/material.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../services/tool_registry.dart';
import '../../services/weatherflow_service.dart';

/// Builder for Current Conditions tool
class CurrentConditionsToolBuilder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return const ToolDefinition(
      id: 'current_conditions',
      name: 'Current Conditions',
      description: 'Shows current temperature, humidity, and pressure',
      category: ToolCategory.weather,
      configSchema: ConfigSchema(
        allowsMinMax: false,
        allowsColorCustomization: true,
        allowsMultiplePaths: false,
        minPaths: 0,
        maxPaths: 0,
      ),
      defaultWidth: 2,
      defaultHeight: 2,
    );
  }

  @override
  Widget build(ToolConfig config, WeatherFlowService weatherFlowService, {bool isEditMode = false}) {
    return CurrentConditionsTool(
      config: config,
      weatherFlowService: weatherFlowService,
    );
  }

  @override
  ToolConfig? getDefaultConfig() {
    return const ToolConfig(
      dataSources: [],
      style: StyleConfig(),
    );
  }
}

/// Current Conditions display widget
class CurrentConditionsTool extends StatelessWidget {
  final ToolConfig config;
  final WeatherFlowService weatherFlowService;

  const CurrentConditionsTool({
    super.key,
    required this.config,
    required this.weatherFlowService,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: weatherFlowService,
      builder: (context, _) {
        final observation = weatherFlowService.currentObservation;
        final conversions = weatherFlowService.conversions;

        if (observation == null) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        final temp = observation.temperature;
        final humidity = observation.humidity;
        final pressure = observation.stationPressure;

        return Container(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Temperature (large)
              if (temp != null)
                Text(
                  conversions.formatTemperature(temp, format: '0'),
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                )
              else
                Text(
                  '--',
                  style: Theme.of(context).textTheme.displaySmall,
                ),

              const SizedBox(height: 8),

              // Humidity and Pressure row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Humidity
                  Column(
                    children: [
                      Icon(
                        Icons.water_drop,
                        size: 20,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        humidity != null
                            ? conversions.formatHumidity(humidity)
                            : '--',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ],
                  ),

                  // Pressure
                  Column(
                    children: [
                      Icon(
                        Icons.compress,
                        size: 20,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        pressure != null
                            ? conversions.formatPressure(pressure)
                            : '--',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
