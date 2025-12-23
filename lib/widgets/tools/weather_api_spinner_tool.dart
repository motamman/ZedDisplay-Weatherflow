/// Weather API Spinner Tool for WeatherFlow
/// Displays a circular forecast spinner showing hourly weather data
/// Adapted from ZedDisplay architecture

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:weatherflow_core/weatherflow_core.dart' hide HourlyForecast;
import '../../models/tool_config.dart';
import '../../models/tool_definition.dart';
import '../../models/marine_data.dart';
import '../../services/tool_registry.dart';
import '../../services/weatherflow_service.dart';
import '../../services/nws_alert_service.dart';
import '../../services/storage_service.dart';
import '../../services/activity_scorer.dart';
import '../../services/activity_score_service.dart';
import '../../services/solar_calculation_service.dart';
import '../../models/activity_definition.dart';
import '../../utils/conversion_extensions.dart';
import '../forecast_spinner.dart';
import '../forecast_models.dart';
import '../nws_alerts_dialog.dart';
import '../activity_score_summary_sheet.dart';

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
          'showDateRing': true, // Toggle outer date rim
          'dateRingMode': 'range', // 'year' = full year view, 'range' = forecast range only
          'showPrimaryIcons': true, // Toggle sun/moon rise and set icons
          'showSecondaryIcons': true, // Toggle dusk, dawn, golden hours icons
          'showWindCenter': true, // Enable wind state center display
          'showSeaCenter': true, // Enable sea state center display (requires marine data)
          'showSolarCenter': true, // Enable solar center display
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
  // Refresh state
  bool _isRefreshing = false;
  _RefreshStatus? _refreshStatus;

  // Alert animation state
  late AnimationController _alertFlashController;
  NWSAlertService? _alertService;
  final Set<String> _acknowledgedAlertIds = {};

  // Track spinner's selected time for alert filtering
  int _selectedHourOffset = 0;

  @override
  void initState() {
    super.initState();
    _alertFlashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);
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

  /// Force refresh forecast data from API (including marine data)
  Future<void> _forceRefresh() async {
    if (_isRefreshing) return;

    setState(() {
      _isRefreshing = true;
      _refreshStatus = null;
    });

    try {
      // Use forceRefresh to refresh both weather and marine data
      await widget.weatherFlowService.forceRefresh();

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
    final showTitle = customProps['showTitle'] as bool? ?? true;
    final showAnimation = customProps['showAnimation'] as bool? ?? true;
    final showDateRing = customProps['showDateRing'] as bool? ?? true;
    final dateRingMode = customProps['dateRingMode'] as String? ?? 'range';
    final showPrimaryIcons = customProps['showPrimaryIcons'] as bool? ?? true;
    final showSecondaryIcons = customProps['showSecondaryIcons'] as bool? ?? true;
    final showWindCenter = customProps['showWindCenter'] as bool? ?? true;
    final showSeaCenter = customProps['showSeaCenter'] as bool? ?? true;
    final showSolarCenter = customProps['showSolarCenter'] as bool? ?? true;
    final forecastDays = customProps['forecastDays'] as int? ?? 3;
    final maxHours = forecastDays * 24;

    // Get system-wide solar config from SolarCalculationService
    final solarService = context.watch<SolarCalculationService>();

    // Use ListenableBuilder to rebuild when service data changes (especially marine data)
    return ListenableBuilder(
      listenable: widget.weatherFlowService,
      builder: (context, _) => _buildSpinnerContent(
        context,
        showTitle: showTitle,
        showAnimation: showAnimation,
        showDateRing: showDateRing,
        dateRingMode: dateRingMode,
        showPrimaryIcons: showPrimaryIcons,
        showSecondaryIcons: showSecondaryIcons,
        showWindCenter: showWindCenter,
        showSeaCenter: showSeaCenter,
        showSolarCenter: showSolarCenter,
        maxHours: maxHours,
        solarService: solarService,
      ),
    );
  }

  Widget _buildSpinnerContent(
    BuildContext context, {
    required bool showTitle,
    required bool showAnimation,
    required bool showDateRing,
    required String dateRingMode,
    required bool showPrimaryIcons,
    required bool showSecondaryIcons,
    required bool showWindCenter,
    required bool showSeaCenter,
    required bool showSolarCenter,
    required int maxHours,
    required SolarCalculationService solarService,
  }) {
    // Get data from service
    final service = widget.weatherFlowService;
    final conversions = service.conversions;
    final tempUnit = conversions.temperatureSymbol;
    final windUnit = conversions.windSpeedSymbol;

    // Trigger marine fetch if sea state center is enabled
    // Fetch if: no data, or data is stale (> 30 min), and not currently loading
    final marineStaleAge = const Duration(minutes: 30);
    final marineNeedsRefresh = service.marineData == null ||
        service.marineData!.isStale(marineStaleAge);
    if (showSeaCenter && marineNeedsRefresh && !service.isLoadingMarine) {
      // Fetch marine data asynchronously
      WidgetsBinding.instance.addPostFrameCallback((_) {
        service.fetchMarineData();
      });
    }

    // Get pre-parsed display data from service, limit to configured hours
    final hourlyForecasts = service.displayHourlyForecasts.take(maxHours).toList();
    final sunMoonTimes = service.sunMoonTimes;
    final marineData = service.marineData;

    // Use tool name if showTitle enabled, otherwise default provider name
    final displayName = showTitle && widget.name != null && widget.name!.isNotEmpty
        ? widget.name!
        : 'OpenMeteo';

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

    if (hourlyForecasts.isEmpty) {
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
              onPressed: _forceRefresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
          ],
        ),
      );
    }

    // Convert hourly forecast values from SI base units to user's preferred units
    // SI base: Kelvin, Pascals, m/s, meters, ratio 0-1
    final convertedHourly = hourlyForecasts.map((h) => HourlyForecast(
      hour: h.hour,
      time: h.time,  // Pass through actual DateTime
      temperature: h.temperature != null ? conversions.convertTemperatureFromKelvin(h.temperature!) : null,
      feelsLike: h.feelsLike != null ? conversions.convertTemperatureFromKelvin(h.feelsLike!) : null,
      conditions: h.conditions,
      longDescription: h.longDescription,
      icon: h.icon,
      precipProbability: h.precipProbability != null ? conversions.convertProbabilityFromRatio(h.precipProbability!) : null,
      humidity: h.humidity != null ? conversions.convertHumidityFromRatio(h.humidity!) : null,
      pressure: h.pressure != null ? conversions.convertPressureFromPascals(h.pressure!) : null,
      windSpeed: h.windSpeed != null ? conversions.convertWindSpeedFromMps(h.windSpeed!) : null,
      windDirection: h.windDirection,
      beaufort: h.beaufort,  // Pass through pre-calculated Beaufort scale
      isDay: h.isDay,
      // Solar radiation fields (already in W/m², no conversion needed)
      shortwaveRadiation: h.shortwaveRadiation,
      directRadiation: h.directRadiation,
      diffuseRadiation: h.diffuseRadiation,
      directNormalIrradiance: h.directNormalIrradiance,
      globalTiltedIrradiance: h.globalTiltedIrradiance,
    )).toList();

    // Check for alerts active at the spinner's selected time (not current real time)
    // Use ALL alerts, not activeAlerts which pre-filters by current time
    final alertService = _alertService;
    final allAlerts = alertService?.alerts ?? [];
    // Use actual forecast time from API, not calculated time
    final selectedForecast = _selectedHourOffset < convertedHourly.length
        ? convertedHourly[_selectedHourOffset]
        : null;
    final selectedTime = selectedForecast?.time ?? DateTime.now().add(Duration(hours: _selectedHourOffset));
    final currentlyActiveAlerts = allAlerts.where((alert) {
      // Check if alert is in effect at the selected spinner time
      // Convert to local time for comparison
      final effective = alert.effective?.toLocal() ?? alert.onset?.toLocal() ?? selectedTime.subtract(const Duration(days: 1));
      final expires = (alert.expires ?? alert.ends)?.toLocal() ?? selectedTime.add(const Duration(days: 1));
      return !selectedTime.isBefore(effective) && selectedTime.isBefore(expires);
    }).toList();
    final hasCurrentAlerts = currentlyActiveAlerts.isNotEmpty;
    final currentHighestAlert = hasCurrentAlerts ? currentlyActiveAlerts.first : null;
    final hasUnacknowledgedCurrentAlerts = hasCurrentAlerts &&
        currentlyActiveAlerts.any((alert) => !_acknowledgedAlertIds.contains(alert.id));

    final storage = context.watch<StorageService>();
    final isRightHanded = storage.isRightHanded;

    // Get weather model name for display (WeatherFlow is a single provider)
    final modelDisplayName = 'WeatherFlow';

    return Stack(
      children: [
        // Main spinner widget with alert badge passed in
        ForecastSpinner(
          hourlyForecasts: convertedHourly,
          sunMoonTimes: sunMoonTimes,
          tempUnit: tempUnit, // Already formatted: '°C' or '°F'
          windUnit: windUnit, // Already formatted: 'kn', 'm/s', 'mph', 'km/h'
          pressureUnit: conversions.pressureSymbol,
          primaryColor: _getPrimaryColor(context),
          providerName: showTitle ? displayName : null,
          modelName: showTitle ? modelDisplayName : null,
          showWeatherAnimation: showAnimation,
          isRightHanded: isRightHanded,
          showDateRing: showDateRing,
          dateRingMode: dateRingMode,
          forecastHours: maxHours,
          showPrimaryIcons: showPrimaryIcons,
          showSecondaryIcons: showSecondaryIcons,
          showWindCenter: showWindCenter,
          showSeaCenter: showSeaCenter,
          showSolarCenter: showSolarCenter,
          panelMaxWatts: solarService.panelMaxWatts,
          systemDerate: solarService.systemDerate,
          marineData: marineData,
          conversions: conversions,
          alertBadgeBuilder: hasCurrentAlerts
              ? (scale) => _buildAlertBadge(currentHighestAlert!, hasUnacknowledgedCurrentAlerts, scale, currentlyActiveAlerts)
              : null,
          onHourChanged: (hourOffset) {
            if (_selectedHourOffset != hourOffset) {
              setState(() {
                _selectedHourOffset = hourOffset;
              });
              // Update the centralized activity score service
              context.read<ActivityScoreService>().updateSelectedHour(hourOffset);
            }
          },
          activityScores: context.watch<ActivityScoreService>().activityScores,
        ),
        // Activity score indicators - top right, to left of refresh button
        if (!widget.isEditMode)
          Positioned(
            top: 8,
            right: 48, // Leave room for refresh button
            child: _buildActivityIndicators(),
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

  /// Build a small alert badge (styled to match Now button)
  /// Tap to acknowledge, long press to show all alerts
  Widget _buildAlertBadge(NWSAlert alert, bool shouldFlash, double scale, List<NWSAlert> allAlerts) {
    final alertColor = _getAlertColor(alert.severity);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget buildButton(Color fgColor, Color bgColor) {
      return GestureDetector(
        onLongPress: () {
          // Show alerts dialog on long press
          NWSAlertsDialog.showAsSheet(context, allAlerts);
        },
        child: TextButton.icon(
          onPressed: () {
            // Acknowledge on tap
            setState(() {
              for (final a in _alertService?.activeAlerts ?? []) {
                _acknowledgedAlertIds.add(a.id);
              }
            });
          },
          icon: Icon(_getAlertIcon(alert.severity), size: 14 * scale),
          label: Text('Alert', style: TextStyle(fontSize: 11 * scale)),
          style: TextButton.styleFrom(
            foregroundColor: fgColor,
            backgroundColor: bgColor,
            padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 4 * scale),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      );
    }

    // Static button when not flashing - no AnimatedBuilder to avoid constant rebuilds
    if (!shouldFlash) {
      return buildButton(
        alertColor,
        isDark ? Colors.black54 : Colors.white70,
      );
    }

    // Animated button when flashing
    return AnimatedBuilder(
      animation: _alertFlashController,
      builder: (context, child) {
        final flashValue = _alertFlashController.value;
        return buildButton(
          Color.lerp(alertColor, Colors.white, flashValue)!,
          Color.lerp(
            isDark ? Colors.black54 : Colors.white70,
            alertColor.withValues(alpha: 0.3),
            flashValue,
          )!,
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

  /// Build activity score indicators as horizontal row
  /// Shows all enabled activities in fixed positions, with X overlay only for bad/dangerous scores
  /// Tap an activity to show detailed score breakdown
  Widget _buildActivityIndicators() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final storage = context.read<StorageService>();
    final activityScoreService = context.watch<ActivityScoreService>();
    final enabledActivityStrings = storage.enabledActivities;
    final activityScores = activityScoreService.activityScores;

    // Convert string keys to ActivityType objects
    final enabledActivities = enabledActivityStrings
        .map((key) => ActivityTypeExtension.fromKey(key))
        .where((a) => a != null)
        .cast<ActivityType>()
        .toList();

    if (enabledActivities.isEmpty) {
      return const SizedBox.shrink();
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: enabledActivities.take(5).map((activityType) {
        // Find the score for this activity (if any)
        final score = activityScores.cast<ActivityScore?>().firstWhere(
          (s) => s?.activity == activityType,
          orElse: () => null,
        );

        // Get tolerances for this activity
        final tolerances = activityScoreService.getActivityTolerance(activityType);

        // Determine if we need an X overlay for bad/dangerous levels
        final isBad = score?.level == ScoreLevel.bad;
        final isDangerous = score?.level == ScoreLevel.dangerous;
        final showXOverlay = isBad || isDangerous;
        final xColor = isDangerous ? Colors.red : Colors.orange;

        // Use score color if available, otherwise neutral gray
        final bgColor = score?.color ?? (isDark ? Colors.grey.shade700 : Colors.grey.shade400);
        final tooltipMessage = score != null
            ? '${activityType.displayName}: ${score.score.toStringAsFixed(0)}% (${score.label})'
            : '${activityType.displayName}: No data';

        return GestureDetector(
          onTap: score != null ? () {
            // Get the forecast time from the service
            final forecastTime = activityScoreService.currentWeather?.time ?? DateTime.now();
            // Show the activity score summary sheet
            ActivityScoreSummarySheet.showAsSheet(
              context,
              score: score,
              tolerances: tolerances,
              conversions: widget.weatherFlowService.conversions,
              forecastTime: forecastTime,
            );
          } : null,
          child: Tooltip(
            message: tooltipMessage,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              width: 24,
              height: 24,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Activity icon circle
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: bgColor.withValues(alpha: isDark ? 0.9 : 0.85),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isDark ? Colors.white24 : Colors.black12,
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 2,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Icon(
                      activityType.icon,
                      size: 14,
                      color: _getContrastColor(bgColor),
                    ),
                  ),
                  // X overlay centered over the icon
                  if (showXOverlay)
                    Positioned(
                      left: -4,
                      top: -4,
                      right: -4,
                      bottom: -4,
                      child: Icon(
                        Icons.close,
                        size: 32,
                        color: xColor,
                        shadows: [
                          Shadow(
                            color: Colors.black87,
                            blurRadius: 3,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  /// Get contrasting text color for a background color
  Color _getContrastColor(Color background) {
    final luminance = background.computeLuminance();
    return luminance > 0.5 ? Colors.black87 : Colors.white;
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
