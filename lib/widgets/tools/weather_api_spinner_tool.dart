/// Weather API Spinner Tool for WeatherFlow
/// Displays a circular forecast spinner showing hourly weather data
/// Adapted from ZedDisplay architecture

import 'package:flutter/material.dart';
import '../../models/tool_config.dart';
import '../../models/tool_definition.dart';
import '../../services/tool_registry.dart';
import '../../services/weatherflow_service.dart';
import '../../utils/sun_calc.dart';
import '../forecast_spinner.dart';
import '../forecast_models.dart';

/// Builder for Weather API Spinner tool
class WeatherApiSpinnerToolBuilder implements ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return const ToolDefinition(
      id: 'weather_api_spinner',
      name: 'Forecast Spinner',
      description: 'Circular forecast wheel showing hourly weather conditions',
      category: ToolCategory.weather,
      configSchema: ConfigSchema(
        allowsMinMax: false,
        allowsColorCustomization: true,
        allowsMultiplePaths: false,
        minPaths: 0,
        maxPaths: 0,
        styleOptions: ['showAnimation', 'tempUnit', 'windUnit'],
      ),
      defaultWidth: 3,
      defaultHeight: 3,
    );
  }

  @override
  Widget build(ToolConfig config, WeatherFlowService weatherFlowService, {bool isEditMode = false}) {
    return WeatherApiSpinnerTool(
      config: config,
      weatherFlowService: weatherFlowService,
      isEditMode: isEditMode,
    );
  }

  @override
  ToolConfig? getDefaultConfig() {
    return const ToolConfig(
      dataSources: [
        DataSource(path: 'forecast', label: 'Forecast'),
      ],
      style: StyleConfig(
        showLabel: true,
        showValue: true,
        customProperties: {
          'showAnimation': true,
          'tempUnit': 'F',
          'windUnit': 'mph',
          'forecastDays': 3, // 1-10 days of forecast (default 3 = 72 hours)
        },
      ),
    );
  }
}

/// Weather API Spinner Widget
class WeatherApiSpinnerTool extends StatefulWidget {
  final ToolConfig config;
  final WeatherFlowService weatherFlowService;
  final bool isEditMode;

  const WeatherApiSpinnerTool({
    super.key,
    required this.config,
    required this.weatherFlowService,
    this.isEditMode = false,
  });

  @override
  State<WeatherApiSpinnerTool> createState() => _WeatherApiSpinnerToolState();
}

class _WeatherApiSpinnerToolState extends State<WeatherApiSpinnerTool> {
  List<HourlyForecast> _hourlyForecasts = [];
  SunMoonTimes? _sunMoonTimes;
  bool _isLoading = true;
  String? _error;

  // Refresh state
  bool _isRefreshing = false;
  _RefreshStatus? _refreshStatus;

  @override
  void initState() {
    super.initState();
    _loadForecast();
  }

  @override
  void didUpdateWidget(WeatherApiSpinnerTool oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.weatherFlowService.selectedStation?.stationId !=
        widget.weatherFlowService.selectedStation?.stationId) {
      _loadForecast();
    }
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

  Future<void> _loadForecast() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final forecast = widget.weatherFlowService.currentForecast;
      if (forecast == null) {
        // Try to fetch forecast
        await widget.weatherFlowService.fetchForecast();
      }

      final fetchedForecast = widget.weatherFlowService.currentForecast;
      if (fetchedForecast != null) {
        _parseForecasts(fetchedForecast);
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
    final List<DaySunTimes> sunTimeDays = [];

    // Get forecastDays from config (default 3 days = 72 hours)
    final forecastDays = widget.config.style.customProperties?['forecastDays'] as int? ?? 3;
    final maxHours = forecastDays * 24;

    // Get station coordinates for astronomical calculations
    final station = widget.weatherFlowService.selectedStation;
    final lat = station?.latitude ?? 0.0;
    final lng = station?.longitude ?? 0.0;

    try {
      // Parse hourly forecasts from WeatherFlow ForecastResponse
      // ForecastResponse has hourlyForecasts and dailyForecasts properties
      final hourlyList = forecast.hourlyForecasts;
      if (hourlyList != null && hourlyList.isNotEmpty) {
        for (int i = 0; i < hourlyList.length && i < maxHours; i++) {
          final hour = hourlyList[i];
          // Convert from Kelvin to display units later
          // Temperature is stored in Kelvin, humidity as 0-1 ratio
          hourlyForecasts.add(HourlyForecast(
            hour: i,
            temperature: hour.temperature != null ? hour.temperature - 273.15 : null, // K to C
            feelsLike: hour.feelsLike != null ? hour.feelsLike - 273.15 : null, // K to C
            conditions: hour.conditions,
            longDescription: hour.conditions,
            icon: hour.icon,
            precipProbability: hour.precipProbability != null ? hour.precipProbability * 100 : null, // 0-1 to %
            humidity: hour.humidity != null ? hour.humidity * 100 : null, // 0-1 to %
            pressure: hour.pressure != null ? hour.pressure / 100 : null, // Pa to hPa
            windSpeed: hour.windAvg,
            windDirection: hour.windDirection,
          ));
        }
      }

      // Calculate sun/moon times astronomically for each day
      final now = DateTime.now();
      for (int dayIndex = 0; dayIndex < forecastDays; dayIndex++) {
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
    final showAnimation = customProps['showAnimation'] as bool? ?? true;
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

    if (_hourlyForecasts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 8),
            Text(
              'No forecast data',
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadForecast,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
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

    return Stack(
      children: [
        // Main spinner widget
        ForecastSpinner(
          hourlyForecasts: convertedHourly,
          sunMoonTimes: _sunMoonTimes,
          tempUnit: tempUnit == 'C' ? '°C' : '°F',
          windUnit: windUnit,
          pressureUnit: 'hPa',
          primaryColor: Theme.of(context).colorScheme.primary,
          providerName: 'WeatherFlow',
          showWeatherAnimation: showAnimation,
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
