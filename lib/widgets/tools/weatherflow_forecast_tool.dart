// WeatherFlow Forecast Tool
// Displays hourly and daily forecast with current conditions
// Adapted from ZedDisplay architecture
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
import 'package:weatherflow_core/weatherflow_core.dart' show ObservationSource;
import '../../models/tool_config.dart';
import '../../models/tool_definition.dart';
import '../../services/tool_registry.dart';
import '../../services/weatherflow_service.dart';
import '../../utils/sun_calc.dart';
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
  Widget build(ToolConfig config, WeatherFlowService weatherFlowService, {bool isEditMode = false}) {
    return WeatherFlowForecastTool(
      config: config,
      weatherFlowService: weatherFlowService,
      isEditMode: isEditMode,
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
          'showCurrentConditions': true,
          'showSunMoonArc': true,
          // Device source preferences ('auto' or device serial number)
          // Measurement types: temp, humidity, pressure, wind, light, rain, lightning
          'tempSource': 'auto',
          'humiditySource': 'auto',
          'pressureSource': 'auto',
          'windSource': 'auto',
          'lightSource': 'auto',
          'rainSource': 'auto',
          'lightningSource': 'auto',
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

  const WeatherFlowForecastTool({
    super.key,
    required this.config,
    required this.weatherFlowService,
    this.isEditMode = false,
  });

  @override
  State<WeatherFlowForecastTool> createState() => _WeatherFlowForecastToolState();
}

class _WeatherFlowForecastToolState extends State<WeatherFlowForecastTool> {
  List<HourlyForecast> _hourlyForecasts = [];
  List<DailyForecast> _dailyForecasts = [];
  SunMoonTimes? _sunMoonTimes;
  bool _isLoading = true;
  String? _error;

  // Refresh state
  bool _isRefreshing = false;
  _RefreshStatus? _refreshStatus;

  // Current conditions - ALL VALUES IN SI BASE UNITS
  double? _currentTemp;           // Kelvin
  double? _currentHumidity;       // ratio 0-1
  double? _currentPressure;       // Pascals
  double? _currentWindSpeed;      // m/s
  double? _currentWindGust;       // m/s
  double? _currentWindDirection;  // degrees (0-360)
  double? _rainLastHour;          // meters
  double? _rainToday;             // meters

  // Data sources for each condition
  ConditionDataSource _tempSource = ConditionDataSource.none;
  ConditionDataSource _humiditySource = ConditionDataSource.none;
  ConditionDataSource _pressureSource = ConditionDataSource.none;
  ConditionDataSource _windSource = ConditionDataSource.none;
  ConditionDataSource _rainSource = ConditionDataSource.none;

  @override
  void initState() {
    super.initState();
    _loadForecast();
  }

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
      // Force fetch from API (bypasses cache)
      await widget.weatherFlowService.fetchForecast();
      final forecast = widget.weatherFlowService.currentForecast;

      if (forecast != null) {
        _parseForecasts(forecast);
        setState(() {
          _isRefreshing = false;
          _refreshStatus = _RefreshStatus.success;
        });

        // Clear status after 2 seconds
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            setState(() => _refreshStatus = null);
          }
        });
      } else {
        setState(() {
          _isRefreshing = false;
          _refreshStatus = _RefreshStatus.failure;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
          _refreshStatus = _RefreshStatus.failure;
          _error = 'Refresh failed: $e';
        });
      }
    }
  }

  @override
  void didUpdateWidget(WeatherFlowForecastTool oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.weatherFlowService.selectedStation?.stationId !=
        widget.weatherFlowService.selectedStation?.stationId) {
      _loadForecast();
    }
  }

  Future<void> _loadForecast() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Load forecast first to get current hour data
      var forecast = widget.weatherFlowService.currentForecast;
      if (forecast == null) {
        await widget.weatherFlowService.fetchForecast();
        forecast = widget.weatherFlowService.currentForecast;
      }

      // Initialize from forecast data (lowest priority)
      // All values kept in SI base units (K, Pa, m/s, ratio, m)
      if (forecast != null && forecast.hourlyForecasts.isNotEmpty) {
        final currentHour = forecast.hourlyForecasts.first;
        if (currentHour.temperature != null) {
          _currentTemp = currentHour.temperature; // Already in Kelvin
          _tempSource = ConditionDataSource.forecast;
        }
        if (currentHour.humidity != null) {
          _currentHumidity = currentHour.humidity; // ratio 0-1
          _humiditySource = ConditionDataSource.forecast;
        }
        if (currentHour.pressure != null) {
          _currentPressure = currentHour.pressure; // Pascals
          _pressureSource = ConditionDataSource.forecast;
        }
        if (currentHour.windAvg != null) {
          _currentWindSpeed = currentHour.windAvg; // m/s
          _currentWindDirection = currentHour.windDirection;
          _windSource = ConditionDataSource.forecast;
        }
        if (currentHour.precipProbability != null) {
          // Forecast only has probability, not actual rain
          _rainSource = ConditionDataSource.forecast;
        }
      }

      // Get device source preferences from config
      final customProps = widget.config.style.customProperties ?? {};
      final tempSource = customProps['tempSource'] as String? ?? 'auto';
      final humiditySource = customProps['humiditySource'] as String? ?? 'auto';
      final pressureSource = customProps['pressureSource'] as String? ?? 'auto';
      final windSource = customProps['windSource'] as String? ?? 'auto';
      final lightSource = customProps['lightSource'] as String? ?? 'auto';
      final rainSource = customProps['rainSource'] as String? ?? 'auto';
      final lightningSource = customProps['lightningSource'] as String? ?? 'auto';

      // Get merged observation using configured device sources
      // This merges data from multiple devices (Air, Sky, Tempest) based on preferences
      final observation = widget.weatherFlowService.getMergedObservation(
        tempSource: tempSource,
        humiditySource: humiditySource,
        pressureSource: pressureSource,
        windSource: windSource,
        lightSource: lightSource,
        rainSource: rainSource,
        lightningSource: lightningSource,
      ) ?? widget.weatherFlowService.currentObservation;

      if (observation != null) {
        // Determine observation source from the observation itself
        final obsSource = switch (observation.source) {
          ObservationSource.udp => ConditionDataSource.udp,
          ObservationSource.websocket => ConditionDataSource.observation,
          ObservationSource.rest => ConditionDataSource.observation,
        };

        if (observation.temperature != null) {
          _currentTemp = observation.temperature; // Already in Kelvin
          _tempSource = obsSource;
        }
        if (observation.humidity != null) {
          _currentHumidity = observation.humidity; // ratio 0-1
          _humiditySource = obsSource;
        }
        if (observation.seaLevelPressure != null || observation.stationPressure != null) {
          _currentPressure = observation.seaLevelPressure ?? observation.stationPressure; // Pascals
          _pressureSource = obsSource;
        }
        if (observation.windAvg != null) {
          _currentWindSpeed = observation.windAvg; // m/s
          _currentWindGust = observation.windGust; // m/s
          _currentWindDirection = observation.windDirection;
          _windSource = obsSource;
        }
        if (observation.rainRate != null || observation.rainAccumulated != null) {
          _rainLastHour = observation.rainRate; // meters
          _rainToday = observation.rainAccumulated; // meters
          _rainSource = obsSource;
        }
      }

      if (forecast != null) {
        _parseForecasts(forecast);
      } else {
        setState(() {
          _error = 'No forecast data available';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error loading forecast: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _parseForecasts(dynamic forecast) {
    final hourlyForecasts = <HourlyForecast>[];
    final dailyForecasts = <DailyForecast>[];
    final List<DaySunTimes> sunTimeDays = [];

    // Get station coordinates for astronomical calculations
    final station = widget.weatherFlowService.selectedStation;
    final lat = station?.latitude ?? 0.0;
    final lng = station?.longitude ?? 0.0;

    // Debug: Check what the API returned
    debugPrint('WeatherFlowForecast: Parsing forecast data');
    debugPrint('  - Hourly forecasts from API: ${forecast.hourlyForecasts?.length ?? 0}');
    debugPrint('  - Daily forecasts from API: ${forecast.dailyForecasts?.length ?? 0}');

    try {
      // Parse hourly forecasts - keep all values in SI base units
      // Temperature: Kelvin, Pressure: Pascals, Wind: m/s, Humidity/Precip: ratio 0-1
      final hourlyList = forecast.hourlyForecasts;
      if (hourlyList != null && hourlyList.isNotEmpty) {
        for (int i = 0; i < hourlyList.length && i < 72; i++) {
          final hour = hourlyList[i];
          hourlyForecasts.add(HourlyForecast(
            hour: i,
            temperature: hour.temperature,      // Kelvin
            feelsLike: hour.feelsLike,          // Kelvin
            conditions: hour.conditions,
            longDescription: hour.conditions,
            icon: hour.icon,
            precipProbability: hour.precipProbability, // ratio 0-1
            humidity: hour.humidity,            // ratio 0-1
            pressure: hour.pressure,            // Pascals
            windSpeed: hour.windAvg,            // m/s
            windDirection: hour.windDirection,
          ));
        }
      }

      // Parse daily forecasts - keep all values in SI base units
      final dailyList = forecast.dailyForecasts;
      if (dailyList != null && dailyList.isNotEmpty) {
        for (int i = 0; i < dailyList.length; i++) {
          final day = dailyList[i];
          dailyForecasts.add(DailyForecast(
            dayIndex: i,
            tempHigh: day.tempHigh,             // Kelvin
            tempLow: day.tempLow,               // Kelvin
            conditions: day.conditions,
            icon: day.icon,
            precipProbability: day.precipProbability, // ratio 0-1
            precipIcon: day.precipIcon,
            sunrise: day.sunrise,
            sunset: day.sunset,
          ));
        }
      }

      // Calculate sun/moon times astronomically for each day
      final now = DateTime.now();
      final daysToCalculate = dailyForecasts.isNotEmpty ? dailyForecasts.length : 7;
      for (int dayIndex = 0; dayIndex < daysToCalculate; dayIndex++) {
        final date = now.add(Duration(days: dayIndex));

        // Use SunCalc for accurate astronomical calculations
        final sunTimes = SunCalc.getTimes(date, lat, lng);
        final moonTimes = MoonCalc.getTimes(date, lat, lng);

        sunTimeDays.add(DaySunTimes(
          sunrise: sunTimes.sunrise,
          sunset: sunTimes.sunset,
          dawn: sunTimes.dawn,
          dusk: sunTimes.dusk,
          nauticalDawn: sunTimes.nauticalDawn,
          nauticalDusk: sunTimes.nauticalDusk,
          solarNoon: sunTimes.solarNoon,
          goldenHour: sunTimes.goldenHour,
          goldenHourEnd: sunTimes.goldenHourEnd,
          night: sunTimes.night,
          nightEnd: sunTimes.nightEnd,
          moonrise: moonTimes.rise,
          moonset: moonTimes.set,
        ));
      }

      // Get current moon phase
      final moonIllum = MoonCalc.getIllumination(now);

      setState(() {
        _hourlyForecasts = hourlyForecasts;
        _dailyForecasts = dailyForecasts;
        _sunMoonTimes = SunMoonTimes(
          days: sunTimeDays,
          moonPhase: moonIllum.phase,
          moonFraction: moonIllum.fraction,
          moonAngle: moonIllum.angle,
        );
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Error parsing forecast: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final customProps = widget.config.style.customProperties ?? {};
    final hoursToShow = customProps['hoursToShow'] as int? ?? 12;
    final daysToShow = customProps['daysToShow'] as int? ?? 7;
    final showCurrentConditions = customProps['showCurrentConditions'] as bool? ?? true;
    final showSunMoonArc = customProps['showSunMoonArc'] as bool? ?? true;

    // Get the ConversionService from WeatherFlowService - respects user preferences
    final conversions = widget.weatherFlowService.conversions;

    if (_isLoading) {
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

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Colors.red[300]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadForecast,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    // Convert all SI values to user's preferred units using ConversionService
    // Temperature: K -> user pref (°C, °F, K)
    // Pressure: Pa -> user pref (hPa, mbar, inHg, mmHg)
    // Wind: m/s -> user pref (kn, m/s, km/h, mph, Bft)
    // Rainfall: m -> user pref (mm, in, cm)
    // Humidity: ratio -> % (always)

    // Convert hourly forecast values
    final convertedHourly = _hourlyForecasts.map((h) => HourlyForecast(
      hour: h.hour,
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

    // Convert daily forecast values
    final convertedDaily = _dailyForecasts.map((d) => DailyForecast(
      dayIndex: d.dayIndex,
      tempHigh: d.tempHigh != null ? conversions.convertTemperature(d.tempHigh!) : null,
      tempLow: d.tempLow != null ? conversions.convertTemperature(d.tempLow!) : null,
      conditions: d.conditions,
      icon: d.icon,
      precipProbability: d.precipProbability != null ? conversions.convertProbability(d.precipProbability!) : null,
      precipIcon: d.precipIcon,
      sunrise: d.sunrise,
      sunset: d.sunset,
    )).toList();

    return Stack(
      children: [
        // Main forecast widget with converted values and unit symbols from preferences
        WeatherFlowForecast(
          currentTemp: _currentTemp != null ? conversions.convertTemperature(_currentTemp!) : null,
          currentHumidity: _currentHumidity != null ? conversions.convertHumidity(_currentHumidity!) : null,
          currentPressure: _currentPressure != null ? conversions.convertPressure(_currentPressure!) : null,
          currentWindSpeed: _currentWindSpeed != null ? conversions.convertWindSpeed(_currentWindSpeed!) : null,
          currentWindGust: _currentWindGust != null ? conversions.convertWindSpeed(_currentWindGust!) : null,
          currentWindDirection: _currentWindDirection,
          rainLastHour: _rainLastHour != null ? conversions.convertRainfall(_rainLastHour!) : null,
          rainToday: _rainToday != null ? conversions.convertRainfall(_rainToday!) : null,
          tempSource: _tempSource,
          humiditySource: _humiditySource,
          pressureSource: _pressureSource,
          windSource: _windSource,
          rainSource: _rainSource,
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
          sunMoonTimes: _sunMoonTimes,
          showSunMoonArc: showSunMoonArc,
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
