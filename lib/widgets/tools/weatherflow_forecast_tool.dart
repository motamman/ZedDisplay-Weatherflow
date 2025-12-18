/// WeatherFlow Forecast Tool
/// Displays hourly and daily forecast with current conditions
/// Adapted from ZedDisplay architecture

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
          'tempUnit': 'F',
          'windUnit': 'mph',
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

  // Current conditions
  double? _currentTemp;
  double? _currentHumidity;
  double? _currentPressure;
  double? _currentWindSpeed;
  double? _currentWindGust;
  double? _currentWindDirection;
  double? _rainLastHour;
  double? _rainToday;

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
      if (forecast != null && forecast.hourlyForecasts.isNotEmpty) {
        final currentHour = forecast.hourlyForecasts.first;
        // Temperature is in Kelvin from API
        if (currentHour.temperature != null) {
          _currentTemp = currentHour.temperature; // Will be converted in _parseForecasts
          _tempSource = ConditionDataSource.forecast;
        }
        if (currentHour.humidity != null) {
          _currentHumidity = currentHour.humidity; // Already 0-1 ratio
          _humiditySource = ConditionDataSource.forecast;
        }
        if (currentHour.pressure != null) {
          _currentPressure = currentHour.pressure; // In Pa
          _pressureSource = ConditionDataSource.forecast;
        }
        if (currentHour.windAvg != null) {
          _currentWindSpeed = currentHour.windAvg;
          _currentWindDirection = currentHour.windDirection;
          _windSource = ConditionDataSource.forecast;
        }
        if (currentHour.precipProbability != null) {
          // Forecast only has probability, not actual rain
          _rainSource = ConditionDataSource.forecast;
        }
      }

      // Override with observation data (higher priority)
      // Use observation data if available, regardless of staleness
      // The dot color indicates the source, not freshness
      final observation = widget.weatherFlowService.currentObservation;
      if (observation != null) {
        // Determine observation source from the observation itself
        final obsSource = switch (observation.source) {
          ObservationSource.udp => ConditionDataSource.udp,
          ObservationSource.websocket => ConditionDataSource.observation,
          ObservationSource.rest => ConditionDataSource.observation,
        };

        if (observation.temperature != null) {
          _currentTemp = observation.temperature;
          _tempSource = obsSource;
        }
        if (observation.humidity != null) {
          _currentHumidity = observation.humidity;
          _humiditySource = obsSource;
        }
        if (observation.seaLevelPressure != null || observation.stationPressure != null) {
          _currentPressure = observation.seaLevelPressure ?? observation.stationPressure;
          _pressureSource = obsSource;
        }
        if (observation.windAvg != null) {
          _currentWindSpeed = observation.windAvg;
          _currentWindGust = observation.windGust;
          _currentWindDirection = observation.windDirection;
          _windSource = obsSource;
        }
        if (observation.rainRate != null || observation.rainAccumulated != null) {
          _rainLastHour = observation.rainRate;
          _rainToday = observation.rainAccumulated;
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
      // Parse hourly forecasts
      final hourlyList = forecast.hourlyForecasts;
      if (hourlyList != null && hourlyList.isNotEmpty) {
        for (int i = 0; i < hourlyList.length && i < 72; i++) {
          final hour = hourlyList[i];
          hourlyForecasts.add(HourlyForecast(
            hour: i,
            temperature: hour.temperature != null ? hour.temperature - 273.15 : null,
            feelsLike: hour.feelsLike != null ? hour.feelsLike - 273.15 : null,
            conditions: hour.conditions,
            longDescription: hour.conditions,
            icon: hour.icon,
            precipProbability: hour.precipProbability != null ? hour.precipProbability * 100 : null,
            humidity: hour.humidity != null ? hour.humidity * 100 : null,
            pressure: hour.pressure != null ? hour.pressure / 100 : null,
            windSpeed: hour.windAvg,
            windDirection: hour.windDirection,
          ));
        }
      }

      // Parse daily forecasts
      final dailyList = forecast.dailyForecasts;
      if (dailyList != null && dailyList.isNotEmpty) {
        for (int i = 0; i < dailyList.length; i++) {
          final day = dailyList[i];
          dailyForecasts.add(DailyForecast(
            dayIndex: i,
            tempHigh: day.tempHigh != null ? day.tempHigh - 273.15 : null,
            tempLow: day.tempLow != null ? day.tempLow - 273.15 : null,
            conditions: day.conditions,
            icon: day.icon,
            precipProbability: day.precipProbability != null ? day.precipProbability * 100 : null,
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
    final tempUnit = customProps['tempUnit'] as String? ?? 'F';
    final windUnit = customProps['windUnit'] as String? ?? 'mph';

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

    // Convert temperatures for display
    double? convertTemp(double? celsius) {
      if (celsius == null) return null;
      if (tempUnit == 'F') return celsius * 9 / 5 + 32;
      return celsius;
    }

    // Convert hourly forecast temperatures
    final convertedHourly = _hourlyForecasts.map((h) => HourlyForecast(
      hour: h.hour,
      temperature: convertTemp(h.temperature),
      feelsLike: convertTemp(h.feelsLike),
      conditions: h.conditions,
      longDescription: h.longDescription,
      icon: h.icon,
      precipProbability: h.precipProbability,
      humidity: h.humidity,
      pressure: h.pressure,
      windSpeed: h.windSpeed,
      windDirection: h.windDirection,
    )).toList();

    // Convert daily forecast temperatures
    final convertedDaily = _dailyForecasts.map((d) => DailyForecast(
      dayIndex: d.dayIndex,
      tempHigh: convertTemp(d.tempHigh),
      tempLow: convertTemp(d.tempLow),
      conditions: d.conditions,
      icon: d.icon,
      precipProbability: d.precipProbability,
      precipIcon: d.precipIcon,
      sunrise: d.sunrise,
      sunset: d.sunset,
    )).toList();

    return Stack(
      children: [
        // Main forecast widget
        WeatherFlowForecast(
          currentTemp: convertTemp(_currentTemp),
          currentHumidity: _currentHumidity,
          currentPressure: _currentPressure != null ? _currentPressure! / 100 : null, // Pa to hPa
          currentWindSpeed: _currentWindSpeed,
          currentWindGust: _currentWindGust,
          currentWindDirection: _currentWindDirection,
          rainLastHour: _rainLastHour,
          rainToday: _rainToday,
          tempSource: _tempSource,
          humiditySource: _humiditySource,
          pressureSource: _pressureSource,
          windSource: _windSource,
          rainSource: _rainSource,
          tempUnit: tempUnit == 'F' ? '°F' : '°C',
          pressureUnit: 'hPa',
          windUnit: windUnit,
          rainUnit: 'mm',
          hourlyForecasts: convertedHourly,
          dailyForecasts: convertedDaily,
          hoursToShow: hoursToShow,
          daysToShow: daysToShow,
          primaryColor: Theme.of(context).colorScheme.primary,
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
