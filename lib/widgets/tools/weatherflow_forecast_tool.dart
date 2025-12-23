// WeatherFlow Forecast Tool
// Displays hourly and daily forecast with current conditions
// Simplified pattern - uses service pre-parsed data
//
// UNITS: All internal values are stored in SI base units:
// - Temperature: Kelvin (K)
// - Pressure: Pascals (Pa)
// - Wind: meters/second (m/s)
// - Humidity: ratio (0-1)
// - Rainfall: meters (m)
// - Distance: meters (m)
//
// Conversions to user preferences are done via ConversionService at display time.

import 'package:flutter/material.dart';
import 'package:weatherflow_core/weatherflow_core.dart' hide HourlyForecast, DailyForecast;
import '../../models/tool_config.dart';
import '../../models/tool_definition.dart';
import '../../services/tool_registry.dart';
import '../../services/weatherflow_service.dart';
import '../../utils/conversion_extensions.dart';
import '../weatherflow_forecast.dart';
import '../forecast_models.dart';

/// Builder for WeatherFlow Forecast tool
class WeatherFlowForecastToolBuilder implements ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return const ToolDefinition(
      id: 'weatherflow_forecast',
      name: 'Weather Forecast',
      description: 'Hourly and daily forecast with current conditions',
      category: ToolCategory.weather,
      configSchema: ConfigSchema(
        allowsMinMax: false,
        allowsColorCustomization: true,
        allowsMultiplePaths: false,
        minPaths: 0,
        maxPaths: 0,
        styleOptions: ['hoursToShow', 'daysToShow', 'showCurrentConditions', 'showSunMoonArc'],
      ),
      defaultWidth: 4,
      defaultHeight: 4,
    );
  }

  @override
  Widget build(ToolConfig config, WeatherFlowService weatherFlowService, {bool isEditMode = false, String? name, void Function(ToolConfig)? onConfigChanged}) {
    return WeatherFlowForecastTool(
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
        showLabel: true,
        showValue: true,
        customProperties: {
          'hoursToShow': 12,
          'daysToShow': 7,
          'showTitle': true,
          'showSunMoonArc': true,
          'showCurrentConditions': true,
          'showDailyForecast': true,
          'use24HourFormat': false,
        },
      ),
    );
  }
}

/// WeatherFlow Forecast Widget
class WeatherFlowForecastTool extends StatefulWidget {
  final ToolConfig config;
  final WeatherFlowService weatherFlowService;
  final bool isEditMode;
  final String? name;

  const WeatherFlowForecastTool({
    super.key,
    required this.config,
    required this.weatherFlowService,
    this.isEditMode = false,
    this.name,
  });

  @override
  State<WeatherFlowForecastTool> createState() => _WeatherFlowForecastToolState();
}

class _WeatherFlowForecastToolState extends State<WeatherFlowForecastTool> {
  // Refresh state
  bool _isRefreshing = false;
  _RefreshStatus? _refreshStatus;

  /// Get configured primary color or fall back to theme color
  Color _getPrimaryColor(BuildContext context) {
    final colorString = widget.config.style.primaryColor;
    if (colorString != null && colorString.isNotEmpty) {
      try {
        final hexColor = colorString.replaceAll('#', '');
        return Color(int.parse('FF$hexColor', radix: 16));
      } catch (e) {
        // Invalid color format, fall back to theme
      }
    }
    return Theme.of(context).colorScheme.primary;
  }

  /// Force refresh forecast data from API
  Future<void> _forceRefresh() async {
    if (_isRefreshing) return;

    setState(() {
      _isRefreshing = true;
      _refreshStatus = null;
    });

    try {
      await widget.weatherFlowService.refreshForecast();

      if (mounted) {
        setState(() {
          _isRefreshing = false;
          _refreshStatus = widget.weatherFlowService.hasData
              ? _RefreshStatus.success
              : _RefreshStatus.failure;
        });

        // Clear status after 2 seconds
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            setState(() => _refreshStatus = null);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
          _refreshStatus = _RefreshStatus.failure;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final customProps = widget.config.style.customProperties ?? {};
    final hoursToShow = customProps['hoursToShow'] as int? ?? 12;
    final daysToShow = customProps['daysToShow'] as int? ?? 7;
    final showTitle = customProps['showTitle'] as bool? ?? true;
    final showSunMoonArc = customProps['showSunMoonArc'] as bool? ?? true;
    final showCurrentConditions = customProps['showCurrentConditions'] as bool? ?? true;
    final showDailyForecast = customProps['showDailyForecast'] as bool? ?? true;
    final use24HourFormat = customProps['use24HourFormat'] as bool? ?? false;

    // Get data from service
    final service = widget.weatherFlowService;
    final conversions = service.conversions;

    // Get pre-parsed display data from service
    final hourlyForecasts = service.displayHourlyForecasts;
    final dailyForecasts = service.displayDailyForecasts;
    final sunMoonTimes = service.sunMoonTimes;

    // Get current conditions from observation
    final observation = service.currentObservation;

    if (service.isLoading && hourlyForecasts.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading forecast...'),
          ],
        ),
      );
    }

    if (service.error != null && hourlyForecasts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
            const SizedBox(height: 8),
            Text(
              service.error!,
              style: TextStyle(color: Colors.red[300]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _forceRefresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    // Convert hourly forecast values from SI base units to user's preferred units
    // SI base: Kelvin, Pascals, m/s, meters, ratio 0-1
    final convertedHourly = hourlyForecasts.map((h) => HourlyForecast(
      hour: h.hour,
      time: h.time,
      temperature: h.temperature != null ? conversions.convertTemperature(h.temperature!) : null,
      feelsLike: h.feelsLike != null ? conversions.convertTemperature(h.feelsLike!) : null,
      conditions: h.conditions,
      longDescription: h.longDescription,
      icon: h.icon,
      precipProbability: h.precipProbability != null ? conversions.convertProbability(h.precipProbability!) : null,
      humidity: h.humidity != null ? conversions.convertHumidity(h.humidity!) : null,
      pressure: h.pressure != null ? conversions.convertPressure(h.pressure!) : null,
      windSpeed: h.windSpeed != null ? conversions.convertWindSpeed(h.windSpeed!) : null,
      windDirection: h.windDirection,
    )).toList();

    // Convert daily forecast values from SI base units
    final convertedDaily = dailyForecasts.map((d) => DailyForecast(
      dayIndex: d.dayIndex,
      date: d.date,
      tempHigh: d.tempHigh != null ? conversions.convertTemperature(d.tempHigh!) : null,
      tempLow: d.tempLow != null ? conversions.convertTemperature(d.tempLow!) : null,
      conditions: d.conditions,
      icon: d.icon,
      precipProbability: d.precipProbability != null ? conversions.convertProbability(d.precipProbability!) : null,
      precipIcon: d.precipIcon,
      sunrise: d.sunrise,
      sunset: d.sunset,
    )).toList();

    // Convert current conditions from observation (SI units)
    final currentTemp = observation?.temperature != null
        ? conversions.convertTemperature(observation!.temperature!)
        : null;
    final currentHumidity = observation?.humidity != null
        ? conversions.convertHumidity(observation!.humidity!)
        : null;
    final currentPressure = observation?.seaLevelPressure != null
        ? conversions.convertPressure(observation!.seaLevelPressure!)
        : (observation?.stationPressure != null
            ? conversions.convertPressure(observation!.stationPressure!)
            : null);
    final currentWindSpeed = observation?.windAvg != null
        ? conversions.convertWindSpeed(observation!.windAvg!)
        : null;
    final currentWindGust = observation?.windGust != null
        ? conversions.convertWindSpeed(observation!.windGust!)
        : null;
    final currentWindDirection = observation?.windDirection;
    final rainLastHour = observation?.rainRate != null
        ? conversions.convertRainfall(observation!.rainRate!)
        : null;
    final rainToday = observation?.rainAccumulated != null
        ? conversions.convertRainfall(observation!.rainAccumulated!)
        : null;

    return Stack(
      children: [
        // Main forecast widget with converted values and unit symbols from preferences
        WeatherFlowForecast(
          currentTemp: currentTemp,
          currentHumidity: currentHumidity,
          currentPressure: currentPressure,
          currentWindSpeed: currentWindSpeed,
          currentWindGust: currentWindGust,
          currentWindDirection: currentWindDirection,
          rainLastHour: rainLastHour,
          rainToday: rainToday,
          tempSource: observation?.temperature != null ? ConditionDataSource.observation : ConditionDataSource.none,
          humiditySource: observation?.humidity != null ? ConditionDataSource.observation : ConditionDataSource.none,
          pressureSource: observation?.seaLevelPressure != null || observation?.stationPressure != null ? ConditionDataSource.observation : ConditionDataSource.none,
          windSource: observation?.windAvg != null ? ConditionDataSource.observation : ConditionDataSource.none,
          rainSource: observation?.rainRate != null || observation?.rainAccumulated != null ? ConditionDataSource.observation : ConditionDataSource.none,
          // Unit symbols from user preferences
          tempUnit: conversions.temperatureSymbol,
          pressureUnit: conversions.pressureSymbol,
          windUnit: conversions.windSpeedSymbol,
          rainUnit: conversions.rainfallSymbol,
          hourlyForecasts: convertedHourly,
          dailyForecasts: convertedDaily,
          hoursToShow: hoursToShow,
          daysToShow: daysToShow,
          primaryColor: _getPrimaryColor(context),
          showCurrentConditions: showCurrentConditions,
          sunMoonTimes: sunMoonTimes,
          showSunMoonArc: showSunMoonArc,
          showDailyForecast: showDailyForecast,
          use24HourFormat: use24HourFormat,
          title: widget.name,
          showTitle: showTitle,
        ),
        // Refresh button in top right corner (hidden in edit mode so dashboard controls are visible)
        if (!widget.isEditMode)
          Positioned(
            top: 4,
            right: 4,
            child: _buildRefreshButton(),
          ),
      ],
    );
  }

  Widget _buildRefreshButton() {
    // Show status indicator
    if (_refreshStatus != null) {
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: _refreshStatus == _RefreshStatus.success
              ? Colors.green.withValues(alpha: 0.8)
              : Colors.red.withValues(alpha: 0.8),
          shape: BoxShape.circle,
        ),
        child: Icon(
          _refreshStatus == _RefreshStatus.success
              ? Icons.check
              : Icons.error_outline,
          color: Colors.white,
          size: 20,
        ),
      );
    }

    // Show loading indicator
    if (_isRefreshing) {
      return Container(
        padding: const EdgeInsets.all(8),
        child: const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
          ),
        ),
      );
    }

    // Show refresh button
    return Material(
      color: Colors.black54,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: _forceRefresh,
        customBorder: const CircleBorder(),
        child: const Padding(
          padding: EdgeInsets.all(8),
          child: Icon(
            Icons.refresh,
            color: Colors.white,
            size: 20,
          ),
        ),
      ),
    );
  }
}

/// Refresh status indicator
enum _RefreshStatus { success, failure }
