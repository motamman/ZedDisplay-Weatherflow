/// Weather API Spinner Tool for WeatherFlow
/// Displays a circular forecast spinner showing hourly weather data
/// Adapted from ZedDisplay architecture

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../models/tool_config.dart';
import '../../models/tool_definition.dart';
import '../../services/tool_registry.dart';
import '../../services/storage_service.dart';
import '../../services/weatherflow_service.dart';
import '../../services/nws_alert_service.dart';
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
        styleOptions: ['showAnimation'],
      ),
      defaultWidth: 3,
      defaultHeight: 3,
    );
  }

  @override
  Widget build(ToolConfig config, WeatherFlowService weatherFlowService, {bool isEditMode = false, String? name}) {
    return WeatherApiSpinnerTool(
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
        customProperties: {
          'showTitle': true,
          'showAnimation': true,
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
  final String? name;

  const WeatherApiSpinnerTool({
    super.key,
    required this.config,
    required this.weatherFlowService,
    this.isEditMode = false,
    this.name,
  });

  @override
  State<WeatherApiSpinnerTool> createState() => _WeatherApiSpinnerToolState();
}

class _WeatherApiSpinnerToolState extends State<WeatherApiSpinnerTool>
    with SingleTickerProviderStateMixin {
  List<HourlyForecast> _hourlyForecasts = [];
  SunMoonTimes? _sunMoonTimes;
  bool _isLoading = true;
  String? _error;

  // Refresh state
  bool _isRefreshing = false;
  _RefreshStatus? _refreshStatus;

  // Alert animation state
  late AnimationController _alertFlashController;
  NWSAlertService? _alertService;
  Set<String> _acknowledgedAlertIds = {};

  @override
  void initState() {
    super.initState();
    _alertFlashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);
    _loadForecast();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_alertService == null) {
      _alertService = context.read<NWSAlertService>();
      _alertService!.addListener(_onAlertsChanged);
    }
  }

  void _onAlertsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _alertFlashController.dispose();
    _alertService?.removeListener(_onAlertsChanged);
    super.dispose();
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
    final showTitle = customProps['showTitle'] as bool? ?? true;
    final showAnimation = customProps['showAnimation'] as bool? ?? true;

    // Get global unit preferences from StorageService
    final storage = context.watch<StorageService>();
    final unitPrefs = storage.unitPreferences;
    final tempUnit = unitPrefs.temperature; // '°C' or '°F'
    final windUnit = unitPrefs.windSpeed; // 'kn', 'm/s', 'mph', 'km/h'

    // Use tool name if showTitle enabled, otherwise default provider name
    final displayName = showTitle && widget.name != null && widget.name!.isNotEmpty
        ? widget.name!
        : 'WeatherFlow';

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

    // Convert temperatures for display (data is stored in Celsius)
    double? convertTemp(double? celsius) {
      if (celsius == null) return null;
      if (tempUnit == '°F') return celsius * 9 / 5 + 32;
      return celsius; // Already Celsius
    }

    // Convert wind speed for display (data is stored in m/s)
    double? convertWind(double? metersPerSecond) {
      if (metersPerSecond == null) return null;
      switch (windUnit) {
        case 'kn':
          return metersPerSecond * 1.94384; // m/s to knots
        case 'mph':
          return metersPerSecond * 2.23694; // m/s to mph
        case 'km/h':
          return metersPerSecond * 3.6; // m/s to km/h
        default:
          return metersPerSecond; // m/s
      }
    }

    // Convert hourly forecast values to display units
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
      windSpeed: convertWind(h.windSpeed),
      windDirection: h.windDirection,
    )).toList();

    // Check for active alerts and filter to only those currently in effect
    final alertService = _alertService;
    final activeAlerts = alertService?.activeAlerts ?? [];
    final now = DateTime.now();
    final currentlyActiveAlerts = activeAlerts.where((alert) {
      // Check if alert is currently in effect
      final effective = alert.effective ?? now.subtract(const Duration(days: 1));
      final expires = alert.expires ?? alert.ends ?? now.add(const Duration(days: 1));
      return now.isAfter(effective) && now.isBefore(expires);
    }).toList();
    final hasCurrentAlerts = currentlyActiveAlerts.isNotEmpty;
    final currentHighestAlert = hasCurrentAlerts ? currentlyActiveAlerts.first : null;
    final hasUnacknowledgedCurrentAlerts = hasCurrentAlerts &&
        currentlyActiveAlerts.any((alert) => !_acknowledgedAlertIds.contains(alert.id));

    return Stack(
      children: [
        // Main spinner widget
        ForecastSpinner(
          hourlyForecasts: convertedHourly,
          sunMoonTimes: _sunMoonTimes,
          tempUnit: tempUnit, // Already formatted: '°C' or '°F'
          windUnit: windUnit, // Already formatted: 'kn', 'm/s', 'mph', 'km/h'
          pressureUnit: unitPrefs.pressure, // 'hPa', 'mbar', 'inHg', etc.
          primaryColor: _getPrimaryColor(context),
          providerName: showTitle ? displayName : null,
          showWeatherAnimation: showAnimation,
        ),
        // Alert badge on top (muted styling, tappable)
        if (hasCurrentAlerts)
          _buildAlertBadge(
            currentHighestAlert!,
            hasUnacknowledgedCurrentAlerts,
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

  /// Build a small alert badge positioned in the top-right of the inner circle
  Widget _buildAlertBadge(NWSAlert alert, bool shouldFlash) {
    final alertColor = _getAlertColor(alert.severity);

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.maxWidth < constraints.maxHeight
            ? constraints.maxWidth
            : constraints.maxHeight;
        final scale = (size / 300).clamp(0.5, 1.5);
        final outerMargin = 27.0 * scale;
        final outerRadius = size / 2 - outerMargin;
        final innerRadius = outerRadius * 0.72;

        // Position badge at top-right of inner circle
        // The inner circle center is at (size/2, size/2)
        // Badge should be at roughly 45 degrees, almost touching the inner circle edge
        final badgeSize = 36.0 * scale;
        // Position so badge edge is ~2px inside inner circle edge
        final badgeOffset = innerRadius - (badgeSize / 2) - (2 * scale);
        final badgeX = size / 2 + badgeOffset * 0.707; // cos(45°)
        final badgeY = size / 2 - badgeOffset * 0.707; // -sin(45°) for top

        return Stack(
          children: [
            Positioned(
              left: badgeX - badgeSize / 2,
              top: badgeY - badgeSize / 2,
              child: GestureDetector(
                onTap: () {
                  // Acknowledge all active alerts (stop flashing)
                  setState(() {
                    for (final a in _alertService?.activeAlerts ?? []) {
                      _acknowledgedAlertIds.add(a.id);
                    }
                  });
                },
                child: AnimatedBuilder(
                  animation: _alertFlashController,
                  builder: (context, child) {
                    // Flash between muted alert color and muted white if unacknowledged
                    final flashValue = shouldFlash ? _alertFlashController.value : 0.0;
                    // Muted colors - lower opacity for subtlety
                    final bgColor = Color.lerp(
                      alertColor.withValues(alpha: 0.5),
                      Colors.white.withValues(alpha: 0.6),
                      flashValue,
                    )!;
                    final iconColor = Color.lerp(
                      Colors.white.withValues(alpha: 0.8),
                      alertColor.withValues(alpha: 0.8),
                      flashValue,
                    )!;

                    return Container(
                      width: badgeSize,
                      height: badgeSize,
                      decoration: BoxDecoration(
                        color: bgColor,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.5),
                          width: 1.5 * scale,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '!',
                            style: TextStyle(
                              fontSize: 14 * scale,
                              fontWeight: FontWeight.bold,
                              color: iconColor,
                            ),
                          ),
                          SizedBox(width: 1 * scale),
                          Icon(
                            _getAlertIcon(alert.severity),
                            size: 14 * scale,
                            color: iconColor,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Get color for alert severity
  Color _getAlertColor(AlertSeverity severity) {
    switch (severity) {
      case AlertSeverity.extreme:
        return Colors.purple.shade700;
      case AlertSeverity.severe:
        return Colors.red.shade700;
      case AlertSeverity.moderate:
        return Colors.orange.shade700;
      case AlertSeverity.minor:
        return Colors.yellow.shade700;
      case AlertSeverity.unknown:
        return Colors.grey.shade600;
    }
  }

  /// Get icon for alert severity
  IconData _getAlertIcon(AlertSeverity severity) {
    switch (severity) {
      case AlertSeverity.extreme:
        return PhosphorIcons.warning();
      case AlertSeverity.severe:
        return PhosphorIcons.warningCircle();
      case AlertSeverity.moderate:
        return PhosphorIcons.info();
      case AlertSeverity.minor:
        return PhosphorIcons.bellRinging();
      case AlertSeverity.unknown:
        return PhosphorIcons.question();
    }
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
