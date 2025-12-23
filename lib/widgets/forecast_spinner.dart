/// Circular forecast spinner widget
/// Adapted from ZedDisplay for WeatherFlow
///
/// Displays a spinnable dial showing 24+ hours of forecast data
/// Center shows detailed conditions for selected time

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:weatherflow_core/weatherflow_core.dart' hide HourlyForecast;
import '../models/marine_data.dart';
import '../utils/conversion_extensions.dart';
import 'forecast_models.dart';
import '../utils/sun_calc.dart';
import '../utils/date_time_formatter.dart';
import '../services/activity_scorer.dart';
import '../services/daylight_service.dart';
import '../services/solar_calculation_service.dart';
import '../models/activity_definition.dart';

/// Center display modes for the forecast spinner
enum CenterDisplayMode { weather, wind, sea, solar }

/// Circular forecast spinner widget
class ForecastSpinner extends StatefulWidget {
  /// Hourly forecasts (up to 72 hours)
  final List<HourlyForecast> hourlyForecasts;

  /// Sun/Moon times for color calculations
  final SunMoonTimes? sunMoonTimes;

  /// Unit labels
  final String tempUnit;
  final String windUnit;
  final String pressureUnit;

  /// Primary accent color
  final Color primaryColor;

  /// Provider name to display
  final String? providerName;

  /// Weather model name to display below provider
  final String? modelName;

  /// Callback when selected hour changes
  final void Function(int hourOffset)? onHourChanged;

  /// Whether to show animated weather effects
  final bool showWeatherAnimation;

  /// Whether user is right-handed (affects button placement)
  final bool isRightHanded;

  /// Whether to show the outer date ring
  final bool showDateRing;

  /// Date ring display mode: 'year' for full year, 'range' for forecast range
  final String dateRingMode;

  /// Total forecast hours available (for range mode)
  final int forecastHours;

  /// Whether to show primary icons (sun/moon rise and set)
  final bool showPrimaryIcons;

  /// Whether to show secondary icons (dusk, dawn, golden hours)
  final bool showSecondaryIcons;

  /// Alert badge builder - receives scale factor to match Now button sizing
  final Widget Function(double scale)? alertBadgeBuilder;

  /// Whether to show wind state as a center display option
  final bool showWindCenter;

  /// Whether to show sea state as a center display option
  final bool showSeaCenter;

  /// Marine data for sea state display
  final MarineData? marineData;

  /// Conversion service for unit formatting
  final ConversionService? conversions;

  /// Activity scores for the current hour
  final List<ActivityScore>? activityScores;

  /// Whether to show solar state as a center display option
  final bool showSolarCenter;

  /// Solar panel max wattage (for power calculation in solar center)
  final double? panelMaxWatts;

  /// System derate factor (0.0-1.0, accounts for inverter, wiring, dirt, temp losses)
  final double? systemDerate;

  const ForecastSpinner({
    super.key,
    required this.hourlyForecasts,
    this.sunMoonTimes,
    this.tempUnit = '°F',
    this.windUnit = 'kn',
    this.pressureUnit = 'hPa',
    this.primaryColor = Colors.blue,
    this.providerName,
    this.modelName,
    this.onHourChanged,
    this.showWeatherAnimation = true,
    this.isRightHanded = true,
    this.showDateRing = true,
    this.dateRingMode = 'range',
    this.forecastHours = 72,
    this.showPrimaryIcons = true,
    this.showSecondaryIcons = true,
    this.alertBadgeBuilder,
    this.showWindCenter = true,
    this.showSeaCenter = true,
    this.marineData,
    this.conversions,
    this.activityScores,
    this.showSolarCenter = true,
    this.panelMaxWatts,
    this.systemDerate,
  });

  @override
  State<ForecastSpinner> createState() => _ForecastSpinnerState();
}

class _ForecastSpinnerState extends State<ForecastSpinner>
    with TickerProviderStateMixin {
  final ValueNotifier<double> _rotationNotifier = ValueNotifier<double>(0.0);
  double _previousAngle = 0.0;
  int _lastSelectedHourOffset = 0;
  late AnimationController _controller;
  Animation<double>? _snapAnimation;
  List<Color>? _cachedSegmentColors;
  DateTime _cachedNow = DateTime.now();

  /// Current center display mode
  CenterDisplayMode _currentCenterMode = CenterDisplayMode.weather;

  /// Wind animation controller (speed based on wind speed)
  late AnimationController _windAnimController;

  /// Wave animation controller (speed based on wave period)
  late AnimationController _waveAnimController;

  double get _rotationAngle => _rotationNotifier.value;
  set _rotationAngle(double value) => _rotationNotifier.value = value;

  int get _selectedMinuteOffset {
    final minutes = (-_rotationAngle / (math.pi / 72) * 10).round();
    final maxMinutes = (widget.hourlyForecasts.length - 1) * 60;
    return minutes.clamp(0, maxMinutes);
  }

  int get _selectedHourOffset {
    if (widget.hourlyForecasts.isEmpty) return 0;
    return (_selectedMinuteOffset ~/ 60).clamp(0, widget.hourlyForecasts.length - 1);
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    // Wind animation - default 2 seconds, will be adjusted based on wind speed
    _windAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();

    // Wave animation - default 4 seconds, will be adjusted based on wave period
    _waveAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    )..repeat();

    _updateSegmentColors();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _controller.addListener(_onAnimationTick);
      }
    });
  }

  @override
  void didUpdateWidget(ForecastSpinner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sunMoonTimes != oldWidget.sunMoonTimes) {
      _updateSegmentColors();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onAnimationTick);
    _controller.dispose();
    _windAnimController.dispose();
    _waveAnimController.dispose();
    _rotationNotifier.dispose();
    super.dispose();
  }

  void _updateSegmentColors() {
    _cachedNow = DateTime.now();
    final segmentCount = widget.hourlyForecasts.length.clamp(24, 240);
    const minutesPerSegment = 60;

    _cachedSegmentColors = List<Color>.generate(segmentCount, (i) {
      final segmentTime = _cachedNow.add(Duration(minutes: i * minutesPerSegment));
      return _computeSegmentColor(segmentTime, widget.sunMoonTimes);
    });
  }

  /// Compute the color for a segment based on time of day and sun data
  /// Uses DaylightService for unified, hemisphere-aware calculations
  Color _computeSegmentColor(DateTime time, SunMoonTimes? times) {
    return DaylightService.getSegmentColor(
      time,
      times,
      useLocationTimezone: true,
    );
  }

  void _onAnimationTick() {
    if (!mounted) return;
    final newAngle = _snapAnimation?.value ?? _controller.value;
    if (newAngle.isFinite) {
      _rotationAngle = newAngle;
      _checkHourOffsetChanged();
    }
  }

  void _checkHourOffsetChanged() {
    final newOffset = _selectedHourOffset;
    if (newOffset != _lastSelectedHourOffset) {
      _lastSelectedHourOffset = newOffset;
      if (mounted) setState(() {});
      // Notify parent immediately during spin, not just at end
      widget.onHourChanged?.call(newOffset);
    }
  }

  void _onPanStart(DragStartDetails details) {
    _controller.stop();
    _snapAnimation = null;
    _previousAngle = _getAngleFromPosition(details.localPosition);
  }

  void _onPanUpdate(DragUpdateDetails details, Size size) {
    final currentAngle = _getAngleFromPosition(details.localPosition);
    var delta = currentAngle - _previousAngle;

    if (delta > math.pi) delta -= 2 * math.pi;
    if (delta < -math.pi) delta += 2 * math.pi;

    var newRotation = _rotationAngle + delta;
    _previousAngle = currentAngle;

    if (widget.hourlyForecasts.isNotEmpty) {
      final maxHours = widget.hourlyForecasts.length - 1;
      final maxRotation = 0.0;
      final minRotation = -maxHours * (math.pi / 12);
      newRotation = newRotation.clamp(minRotation, maxRotation);
    }

    _rotationAngle = newRotation;
    _checkHourOffsetChanged();
  }

  void _onPanEnd(DragEndDetails details) {
    if (!_rotationAngle.isFinite) {
      _rotationAngle = 0.0;
    }
    _snapToNearestHour();
  }

  void _snapToNearestHour() {
    if (widget.hourlyForecasts.isEmpty) return;
    if (!_rotationAngle.isFinite) {
      _rotationAngle = 0.0;
      return;
    }

    final tenMinuteStep = math.pi / 72;
    final maxHours = widget.hourlyForecasts.length - 1;
    final maxAngle = maxHours * math.pi / 12;
    final targetAngle = ((_rotationAngle / tenMinuteStep).round() * tenMinuteStep)
        .clamp(-maxAngle, 0.0);

    _snapAnimation = Tween<double>(
      begin: _rotationAngle,
      end: targetAngle,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));

    _controller.duration = const Duration(milliseconds: 200);
    _controller.forward(from: 0).then((_) {
      if (!mounted) return;
      _controller.stop();
      setState(() {
        _rotationAngle = targetAngle;
        _snapAnimation = null;
      });
      widget.onHourChanged?.call(_selectedHourOffset);
    });
  }

  Size _currentSize = const Size(300, 300);

  double _getAngleFromPosition(Offset position) {
    final centerX = _currentSize.width / 2;
    final centerY = _currentSize.height / 2;
    return math.atan2(position.dy - centerY, position.dx - centerX);
  }

  void _returnToNow() {
    _controller.stop();
    _snapAnimation = Tween<double>(
      begin: _rotationAngle,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));

    _controller.duration = const Duration(milliseconds: 400);
    _controller.forward(from: 0).then((_) {
      if (!mounted) return;
      _controller.stop();
      setState(() {
        _rotationAngle = 0.0;
        _snapAnimation = null;
      });
      widget.onHourChanged?.call(0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Reserve space for label if present
        final hasLabel = widget.providerName != null || widget.modelName != null;
        final labelHeight = hasLabel ? 18.0 : 0.0;
        final availableHeight = constraints.maxHeight - labelHeight;
        final size = math.min(constraints.maxWidth, availableHeight);
        _currentSize = Size(size, size);
        final scale = (size / 300).clamp(0.5, 1.5);

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Label above spinner (left-aligned)
            if (hasLabel)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 2),
                  child: Text.rich(
                  TextSpan(
                    children: [
                      if (widget.providerName != null && widget.providerName!.isNotEmpty)
                        TextSpan(
                          text: widget.providerName!,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      if (widget.providerName != null && widget.modelName != null)
                        TextSpan(
                          text: ' · ',
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark ? Colors.white38 : Colors.black26,
                          ),
                        ),
                      if (widget.modelName != null && widget.modelName!.isNotEmpty)
                        TextSpan(
                          text: widget.modelName!,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w400,
                            color: widget.primaryColor.withValues(alpha: 0.7),
                          ),
                        ),
                    ],
                  ),
                ),
                ),
              ),
            // Spinner
            RepaintBoundary(
              child: SizedBox(
                width: size,
                height: size,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                // Selection indicator at top - rendered first so it's behind everything
                Positioned(
                  top: 20 * scale,
                  child: IgnorePointer(
                    child: Container(
                      width: 20 * scale,
                      height: 23 * scale,
                      decoration: BoxDecoration(
                        color: widget.primaryColor,
                        borderRadius: BorderRadius.only(
                          bottomLeft: Radius.circular(10 * scale),
                          bottomRight: Radius.circular(10 * scale),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black38,
                            blurRadius: 4 * scale,
                            offset: Offset(0, 2 * scale),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.arrow_drop_down,
                        color: Colors.white,
                        size: 20 * scale,
                      ),
                    ),
                  ),
                ),

                // Gesture detector for spinning
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onPanStart: _onPanStart,
                    onPanUpdate: (details) => _onPanUpdate(details, Size(size, size)),
                    onPanEnd: _onPanEnd,
                    child: ValueListenableBuilder<double>(
                      valueListenable: _rotationNotifier,
                      builder: (context, rotationAngle, child) {
                        return CustomPaint(
                          size: Size(size, size),
                          painter: _ForecastRimPainter(
                            times: widget.sunMoonTimes,
                            rotationAngle: rotationAngle,
                            isDark: isDark,
                            selectedHourOffset: _selectedHourOffset,
                            cachedSegmentColors: _cachedSegmentColors,
                            cachedNow: _cachedNow,
                            maxForecastHours: widget.hourlyForecasts.length,
                            showPrimaryIcons: widget.showPrimaryIcons,
                            showSecondaryIcons: widget.showSecondaryIcons,
                          ),
                        );
                      },
                    ),
                  ),
                ),

                // Fixed date ring (doesn't rotate) - shows full year or forecast range
                if (widget.showDateRing)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        size: Size(size, size),
                        painter: _DateRingPainter(
                          selectedDate: DateTime.now().add(Duration(minutes: _selectedMinuteOffset)),
                          isDark: isDark,
                          primaryColor: widget.primaryColor,
                          mode: widget.dateRingMode,
                          forecastHours: widget.forecastHours,
                          currentHourOffset: _selectedHourOffset,
                        ),
                      ),
                    ),
                  ),

                // Return to Now button - explicit positioning (no full-width hit area)
                if (_selectedHourOffset > 0)
                  Positioned(
                    bottom: -4 * scale,
                    right: widget.isRightHanded ? 4 * scale : null,
                    left: widget.isRightHanded ? null : 4 * scale,
                    child: TextButton.icon(
                      onPressed: _returnToNow,
                      icon: Icon(Icons.gps_fixed, size: 14 * scale),
                      label: Text('Now', style: TextStyle(fontSize: 11 * scale)),
                      style: TextButton.styleFrom(
                        foregroundColor: widget.primaryColor,
                        backgroundColor: isDark ? Colors.black54 : Colors.white70,
                        padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 4 * scale),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),

                // Alert badge - mirrored position, explicit positioning (no full-width hit area)
                if (widget.alertBadgeBuilder != null)
                  Positioned(
                    bottom: -4 * scale,
                    left: widget.isRightHanded ? 4 * scale : null,
                    right: widget.isRightHanded ? null : 4 * scale,
                    child: widget.alertBadgeBuilder!(scale),
                  ),

                // Center content - on top (tap to cycle center modes)
                _buildCenterContent(size, isDark),

              ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Build activity score indicators as horizontal row (top right)
  Widget _buildActivityIndicatorsHorizontal(
    List<ActivityScore> scores,
    double scale,
    bool isDark,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: scores.take(5).map((score) {
        // Determine if we need an X overlay for bad/dangerous levels
        final isBad = score.level == ScoreLevel.bad;
        final isDangerous = score.level == ScoreLevel.dangerous;
        final showXOverlay = isBad || isDangerous;
        final xColor = isDangerous ? Colors.red : Colors.orange;

        return Tooltip(
          message: '${score.activity.displayName}: ${score.score.toStringAsFixed(0)}% (${score.label})',
          child: Container(
            margin: EdgeInsets.symmetric(horizontal: 2 * scale),
            width: 22 * scale,
            height: 22 * scale,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Activity icon circle
                Container(
                  width: 22 * scale,
                  height: 22 * scale,
                  decoration: BoxDecoration(
                    color: score.color.withValues(alpha: isDark ? 0.9 : 0.85),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDark ? Colors.white24 : Colors.black12,
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 2 * scale,
                        offset: Offset(0, 1 * scale),
                      ),
                    ],
                  ),
                  child: Icon(
                    score.icon,
                    size: 12 * scale,
                    color: _getContrastColor(score.color),
                  ),
                ),
                // X overlay centered over the icon
                if (showXOverlay)
                  Positioned(
                    left: -4 * scale,
                    top: -4 * scale,
                    right: -4 * scale,
                    bottom: -4 * scale,
                    child: Icon(
                      Icons.close,
                      size: 30 * scale,
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
        );
      }).toList(),
    );
  }

  /// Get contrasting text color for a background color
  Color _getContrastColor(Color background) {
    // Calculate luminance and choose white or black
    final luminance = background.computeLuminance();
    return luminance > 0.5 ? Colors.black87 : Colors.white;
  }

  Widget _buildCenterContent(double size, bool isDark) {
    final scale = (size / 300).clamp(0.5, 1.5);
    final outerMargin = 43.0 * scale;
    final outerRadius = size / 2 - outerMargin;
    final innerRadius = outerRadius * 0.72;
    final centerSize = innerRadius * 2;

    // Calculate device time for daylight color (works with UTC comparison)
    final deviceTime = DateTime.now().add(Duration(minutes: _selectedMinuteOffset));
    final bgColor = _getTimeOfDayColor(deviceTime);
    // Convert to location time for display and forecast matching
    final selectedTime = widget.sunMoonTimes?.toLocationTime(deviceTime) ?? deviceTime;

    // Get forecast for selected hour by matching time (not array index)
    // API times are in location timezone, so match against selectedTime
    final HourlyForecast? forecast;
    if (widget.hourlyForecasts.isEmpty) {
      forecast = null;
    } else {
      forecast = widget.hourlyForecasts.cast<HourlyForecast?>().firstWhere(
        (f) => f?.time != null &&
               f!.time!.hour == selectedTime.hour &&
               f.time!.day == selectedTime.day,
        orElse: () => null,
      ) ?? widget.hourlyForecasts.last;
    }
    final availableModes = _getAvailableModes();

    // Ensure current mode is valid (e.g., if marine data becomes unavailable)
    if (!availableModes.contains(_currentCenterMode)) {
      _currentCenterMode = CenterDisplayMode.weather;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: availableModes.length > 1 ? _cycleCenterMode : null,
      child: Container(
        width: centerSize,
        height: centerSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              bgColor.withValues(alpha: 0.6),
              bgColor.withValues(alpha: 0.3),
            ],
          ),
          border: Border.all(
            color: isDark ? Colors.white24 : Colors.black12,
            width: 2,
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Main content based on mode
            if (forecast == null)
              const Center(child: Text('No data'))
            else
              _buildCenterModeContent(forecast, selectedTime, deviceTime, isDark, centerSize),
            // Mode indicator dots at bottom
            if (availableModes.length > 1)
              Positioned(
                bottom: centerSize * 0.08,
                child: _buildModeIndicator(availableModes, isDark),
              ),
          ],
        ),
      ),
    );
  }

  /// Build content based on current center display mode
  /// Falls back to weather mode if selected mode returns null (no data)
  Widget _buildCenterModeContent(
    HourlyForecast forecast,
    DateTime time,
    DateTime deviceTime,
    bool isDark,
    double centerSize,
  ) {
    switch (_currentCenterMode) {
      case CenterDisplayMode.weather:
        return _buildWeatherCenter(forecast, time, isDark, centerSize);
      case CenterDisplayMode.wind:
        return _buildWindStateCenter(forecast, time, isDark, centerSize);
      case CenterDisplayMode.sea:
        // Fall back to weather if sea center has no data
        return _buildSeaStateCenter(time, isDark, centerSize) ??
            _buildWeatherCenter(forecast, time, isDark, centerSize);
      case CenterDisplayMode.solar:
        return _buildSolarCenter(forecast, time, deviceTime, isDark, centerSize);
    }
  }

  /// Build mode indicator dots
  Widget _buildModeIndicator(List<CenterDisplayMode> modes, bool isDark) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: modes.map((mode) {
        final isActive = mode == _currentCenterMode;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: isActive ? 8 : 6,
          height: isActive ? 8 : 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive
                ? (isDark ? Colors.white : Colors.black87)
                : (isDark ? Colors.white38 : Colors.black26),
          ),
        );
      }).toList(),
    );
  }

  /// Original weather center display (renamed from _buildForecastContent)
  Widget _buildWeatherCenter(HourlyForecast forecast, DateTime time, bool isDark, double centerSize) {
    return _buildForecastContent(forecast, time, isDark, centerSize);
  }

  /// Wind state center display with animation
  Widget _buildWindStateCenter(HourlyForecast forecast, DateTime time, bool isDark, double centerSize) {
    final scale = (centerSize / 200).clamp(0.6, 1.2);
    final windSpeed = forecast.windSpeed ?? 0.0;
    final windDirection = forecast.windDirection;

    // Use pre-calculated Beaufort scale from forecast data
    final beaufort = forecast.beaufort ?? 0;
    final beaufortDesc = _getBeaufortDescription(beaufort);

    // Wind speed is already converted to user's preferred units
    final formattedSpeed = '${windSpeed.toStringAsFixed(0)} ${widget.windUnit}';

    // Get compass direction
    final compassDir = windDirection != null
        ? _getWindDirectionLabel(windDirection)
        : '--';

    // Adjust wind animation speed based on wind speed (faster wind = faster animation)
    // At 0 km/h: 4 seconds per cycle, at 100 km/h: 0.5 seconds per cycle
    final animDuration = (4000 - (windSpeed.clamp(0, 100) * 35)).round().clamp(500, 4000);
    if (_windAnimController.duration?.inMilliseconds != animDuration) {
      _windAnimController.duration = Duration(milliseconds: animDuration);
      if (!_windAnimController.isAnimating) {
        _windAnimController.repeat();
      }
    }

    return Stack(
      children: [
        // Wind icons animation layer (matching weather center style)
        if (windSpeed > 0)
          Positioned.fill(
            child: ClipOval(
              child: AnimatedBuilder(
                animation: _windAnimController,
                builder: (context, _) {
                  return _buildWindParticles(
                    _windAnimController.value,
                    windDirection ?? 0,
                    windSpeed,
                    beaufort,
                    centerSize,
                    isDark,
                  );
                },
              ),
            ),
          ),

        // Content overlay
        Padding(
          padding: EdgeInsets.all(12 * scale),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Time label (shows only day name when date ring is visible)
              Text(
                _formatSelectedTime(time, showDateRing: widget.showDateRing),
                style: TextStyle(
                  fontSize: 14 * scale,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
              SizedBox(height: 2 * scale),

              // Beaufort description
              Text(
                beaufortDesc.toUpperCase(),
                style: TextStyle(
                  fontSize: 12 * scale,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white70 : Colors.black54,
                  letterSpacing: 1.2,
                  shadows: isDark ? null : [
                    Shadow(color: Colors.white, blurRadius: 2),
                  ],
                ),
              ),
              SizedBox(height: 2 * scale),

              // Beaufort number
              Text(
                'BF $beaufort',
                style: TextStyle(
                  fontSize: 22 * scale,
                  fontWeight: FontWeight.bold,
                  color: _getBeaufortColor(beaufort),
                  shadows: [
                    Shadow(
                      color: isDark ? Colors.black54 : Colors.white,
                      blurRadius: 3,
                    ),
                  ],
                ),
              ),
              SizedBox(height: 8 * scale),

              // Wind speed with direction arrow
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (windDirection != null)
                    Transform.rotate(
                      angle: (windDirection + 180) * math.pi / 180,
                      child: Icon(
                        Icons.navigation,
                        size: 24 * scale,
                        color: Colors.teal.shade300,
                        shadows: [
                          Shadow(
                            color: isDark ? Colors.black54 : Colors.white,
                            blurRadius: 3,
                          ),
                        ],
                      ),
                    ),
                  SizedBox(width: 6 * scale),
                  Text(
                    formattedSpeed,
                    style: TextStyle(
                      fontSize: 20 * scale,
                      fontWeight: FontWeight.w600,
                      color: Colors.teal.shade300,
                      shadows: [
                        Shadow(
                          color: isDark ? Colors.black54 : Colors.white,
                          blurRadius: 3,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 4 * scale),

              // Compass direction
              Text(
                'from $compassDir',
                style: TextStyle(
                  fontSize: 14 * scale,
                  color: isDark ? Colors.white60 : Colors.black45,
                  shadows: isDark ? null : [
                    Shadow(color: Colors.white, blurRadius: 2),
                  ],
                ),
              ),

              SizedBox(height: 20 * scale), // Space for dots
            ],
          ),
        ),
      ],
    );
  }

  /// Build wind particle icons (leaves blowing in the wind)
  Widget _buildWindParticles(
    double progress,
    double windDirection,
    double windSpeed,
    int beaufort,
    double size,
    bool isDark,
  ) {
    final center = size / 2;
    final radius = size / 2;

    // Number of leaves (more for stronger wind)
    final leafCount = (4 + beaufort.clamp(0, 8)).clamp(4, 12);

    // Wind direction in radians - convert from meteorological (0=N, clockwise)
    // to canvas coordinates where north is UP
    final windAngle = (windDirection + 90) * math.pi / 180;

    // Fixed icon size
    const iconSize = 22.0;

    // Movement speed multiplier based on wind speed
    final speedMultiplier = 1.0 + (windSpeed.clamp(0, 60) / 30);

    // Oscillation amplitude DECREASES with wind speed (faster = straighter path)
    final oscillationAmp = radius * (0.12 - beaufort * 0.008).clamp(0.02, 0.12);

    final particles = <Widget>[];

    for (int i = 0; i < leafCount; i++) {
      // Each leaf has its own phase offset (use golden ratio for better distribution)
      final delay = (i * 0.618033988749895) % 1.0;
      final t = (progress * speedMultiplier + delay) % 1.0;

      // Horizontal position: move across the circle
      final startX = -radius * 0.3;
      final endX = radius * 1.3;
      final currentProgress = startX + t * (endX - startX);

      // Vertical position: sine wave oscillation
      final baseY = (i - leafCount / 2) * (radius * 1.6 / leafCount);
      final oscillation = math.sin((t + delay) * math.pi * (3 + beaufort * 0.5)) * oscillationAmp;
      final currentY = baseY + oscillation;

      // Transform position based on wind direction
      final rotatedX = center + currentProgress * math.cos(windAngle) - currentY * math.sin(windAngle);
      final rotatedY = center + currentProgress * math.sin(windAngle) + currentY * math.cos(windAngle);

      // Only show if within the circle
      final distFromCenter = math.sqrt(math.pow(rotatedX - center, 2) + math.pow(rotatedY - center, 2));
      if (distFromCenter > radius * 0.85) continue;

      // Fade near edges
      final edgeFade = (1 - distFromCenter / radius).clamp(0.5, 1.0);
      final alpha = (isDark ? 0.95 : 0.9) * edgeFade;

      // Random-looking rotation based on leaf index and progress
      // Each leaf tumbles at its own rate, MUCH faster in stronger wind
      final tumbleSpeed = (1 + beaufort * 1.2) * math.pi;
      final leafRotation = (t * tumbleSpeed + i * 1.7) + math.sin(t * math.pi * 4 + i) * (0.3 + beaufort * 0.15);

      // Vary leaf colors slightly for natural look - brighter shades
      final leafColors = [
        Colors.green.shade300,
        Colors.green.shade400,
        Colors.lightGreen.shade300,
        Colors.teal.shade300,
      ];
      final leafColor = leafColors[i % leafColors.length];

      particles.add(
        Positioned(
          left: rotatedX - iconSize / 2,
          top: rotatedY - iconSize / 2,
          child: Transform.rotate(
            angle: leafRotation,
            child: Icon(
              PhosphorIcons.leaf(),
              size: iconSize,
              color: leafColor.withValues(alpha: alpha),
            ),
          ),
        ),
      );
    }

    return Stack(children: particles);
  }

  /// Get color for Beaufort scale
  Color _getBeaufortColor(int bf) {
    if (bf <= 2) return Colors.green;
    if (bf <= 4) return Colors.teal;
    if (bf <= 6) return Colors.orange;
    if (bf <= 8) return Colors.deepOrange;
    if (bf <= 10) return Colors.red;
    return Colors.purple;
  }

  /// Sea state center display
  /// Returns null if no marine data available (caller should fall back to weather)
  Widget? _buildSeaStateCenter(DateTime selectedTime, bool isDark, double centerSize) {
    final scale = (centerSize / 200).clamp(0.6, 1.2);
    final marine = widget.marineData;

    // Return null to signal fallback to weather mode
    if (marine == null || marine.hourly.isEmpty) {
      return null;
    }

    // Find marine data for the selected time from hourly list
    // Match by finding the closest hour (handles timezone differences)
    HourlyMarine? selectedMarine;
    int? smallestDiff;
    for (final h in marine.hourly) {
      final diff = (h.time.difference(selectedTime).inMinutes).abs();
      if (diff < 60 && (smallestDiff == null || diff < smallestDiff)) {
        smallestDiff = diff;
        selectedMarine = h;
      }
    }
    // Fallback: try matching just by hour of day for today
    if (selectedMarine == null) {
      for (final h in marine.hourly) {
        if (h.time.hour == selectedTime.hour &&
            h.time.day == selectedTime.day) {
          selectedMarine = h;
          break;
        }
      }
    }

    // Return null to signal fallback to weather mode
    if (selectedMarine == null) {
      return null;
    }

    // Get marine conditions from hourly data
    final waveHeight = selectedMarine.waveHeight ?? 0.0;
    final wavePeriod = selectedMarine.wavePeriod;
    final waveDirection = selectedMarine.waveDirection;
    final swellHeight = selectedMarine.swellWaveHeight;
    final swellDirection = selectedMarine.swellWaveDirection;

    // Get sea state info - use pre-calculated Douglas scale
    final seaStateLabel = _getSeaStateLabel(waveHeight);
    final douglas = selectedMarine.douglas ?? 0;

    // Format wave height using conversions if available
    final formattedHeight = widget.conversions != null
        ? widget.conversions!.formatWaveHeight(waveHeight)
        : '${waveHeight.toStringAsFixed(1)} m';

    // Format swell height
    final formattedSwell = swellHeight != null && widget.conversions != null
        ? widget.conversions!.formatWaveHeight(swellHeight)
        : (swellHeight != null ? '${swellHeight.toStringAsFixed(1)} m' : null);

    // Adjust wave animation speed based on wave period (longer period = slower animation)
    // Default 6 second period = 4 second animation cycle
    final periodMs = ((wavePeriod ?? 6) * 667).round().clamp(2000, 8000);
    if (_waveAnimController.duration?.inMilliseconds != periodMs) {
      _waveAnimController.duration = Duration(milliseconds: periodMs);
      if (!_waveAnimController.isAnimating) {
        _waveAnimController.repeat();
      }
    }

    return Stack(
      children: [
        // Wave animation layer
        Positioned.fill(
          child: ClipOval(
            child: AnimatedBuilder(
              animation: _waveAnimController,
              builder: (context, _) {
                return CustomPaint(
                  painter: _WavesPainter(
                    progress: _waveAnimController.value,
                    waveHeight: waveHeight,
                    wavePeriod: wavePeriod,
                    isDark: isDark,
                    beaufort: douglas,  // Using Douglas scale for wave animation intensity
                  ),
                );
              },
            ),
          ),
        ),

        // Content overlay
        Padding(
          padding: EdgeInsets.all(12 * scale),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Time label (shows only day name when date ring is visible)
              Text(
                _formatSelectedTime(selectedTime, showDateRing: widget.showDateRing),
                style: TextStyle(
                  fontSize: 14 * scale,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
              SizedBox(height: 2 * scale),

              // Sea state label
              Text(
                seaStateLabel.toUpperCase(),
                style: TextStyle(
                  fontSize: 11 * scale,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white70 : Colors.black54,
                  letterSpacing: 1.0,
                  shadows: [
                    Shadow(
                      color: isDark ? Colors.black54 : Colors.white,
                      blurRadius: 3,
                    ),
                  ],
                ),
              ),
              SizedBox(height: 2 * scale),

              // Douglas sea state number
              Text(
                'SS $douglas',
                style: TextStyle(
                  fontSize: 20 * scale,
                  fontWeight: FontWeight.bold,
                  color: _getSeaStateColor(waveHeight),
                  shadows: [
                    Shadow(
                      color: isDark ? Colors.black54 : Colors.white,
                      blurRadius: 3,
                    ),
                  ],
                ),
              ),
              SizedBox(height: 6 * scale),

              // Wave height @ period
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    PhosphorIcons.waves(PhosphorIconsStyle.fill),
                    size: 20 * scale,
                    color: Colors.blue.shade300,
                    shadows: [
                      Shadow(
                        color: isDark ? Colors.black54 : Colors.white,
                        blurRadius: 3,
                      ),
                    ],
                  ),
                  SizedBox(width: 4 * scale),
                  Text(
                    formattedHeight,
                    style: TextStyle(
                      fontSize: 18 * scale,
                      fontWeight: FontWeight.w600,
                      color: Colors.blue.shade300,
                      shadows: [
                        Shadow(
                          color: isDark ? Colors.black54 : Colors.white,
                          blurRadius: 3,
                        ),
                      ],
                    ),
                  ),
                  if (wavePeriod != null) ...[
                    SizedBox(width: 6 * scale),
                    Text(
                      '@ ${wavePeriod.toStringAsFixed(0)}s',
                      style: TextStyle(
                        fontSize: 14 * scale,
                        color: Colors.blue.shade200,
                        shadows: [
                          Shadow(
                            color: isDark ? Colors.black54 : Colors.white,
                            blurRadius: 3,
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              SizedBox(height: 4 * scale),

              // Wave direction
              if (waveDirection != null)
                Text(
                  'from ${_getWindDirectionLabel(waveDirection)}',
                  style: TextStyle(
                    fontSize: 13 * scale,
                    color: isDark ? Colors.white60 : Colors.black45,
                    shadows: [
                      Shadow(
                        color: isDark ? Colors.black54 : Colors.white,
                        blurRadius: 2,
                      ),
                    ],
                  ),
                ),
              SizedBox(height: 4 * scale),

              // Swell info
              if (formattedSwell != null)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 2 * scale),
                  decoration: BoxDecoration(
                    color: Colors.indigo.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Swell: $formattedSwell${swellDirection != null ? ' ${_getWindDirectionLabel(swellDirection)}' : ''}',
                    style: TextStyle(
                      fontSize: 11 * scale,
                      color: Colors.indigo.shade200,
                    ),
                  ),
                ),

              SizedBox(height: 16 * scale), // Space for dots
            ],
          ),
        ),
      ],
    );
  }

  /// Get color for sea state based on wave height
  Color _getSeaStateColor(double meters) {
    if (meters < 0.5) return Colors.teal;
    if (meters < 1.25) return Colors.cyan;
    if (meters < 2.5) return Colors.blue;
    if (meters < 4.0) return Colors.indigo;
    if (meters < 6.0) return Colors.orange;
    return Colors.red;
  }

  /// Solar center display - shows hourly solar data for selected hour
  Widget _buildSolarCenter(HourlyForecast forecast, DateTime time, DateTime deviceTime, bool isDark, double centerSize) {
    final scale = (centerSize / 200).clamp(0.6, 1.2);

    // Get irradiance - prefer tilted if available
    final irradiance = forecast.globalTiltedIrradiance ??
        forecast.shortwaveRadiation ??
        0.0;

    // Show night display if no irradiance (night hours have 0 irradiance from API)
    if (irradiance <= 0) {
      return _buildNightSolarDisplay(time, isDark, centerSize, scale);
    }

    // Get panel config
    final maxWatts = widget.panelMaxWatts ?? 0;
    final derate = widget.systemDerate ?? 0.85;
    final hasPanelConfig = maxWatts > 0;

    // Get radiation label and color
    final label = SolarCalculationService.getRadiationLabel(irradiance);
    final color = SolarCalculationService.getRadiationColor(irradiance);

    // Calculate power output for this hour if panel is configured
    double? watts;
    if (hasPanelConfig) {
      watts = SolarCalculationService.calculateInstantPower(
        irradiance: irradiance,
        maxWatts: maxWatts,
        systemDerate: derate,
      );
    }

    return Stack(
      children: [
        // Sun rays animation in background
        if (irradiance > 50)
          Positioned.fill(
            child: ClipOval(
              child: _SunRaysAnimation(
                intensity: (irradiance / 1000).clamp(0.1, 1.0),
                isDark: isDark,
              ),
            ),
          ),

        // Content overlay
        Padding(
          padding: EdgeInsets.all(12 * scale),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Time label
              Text(
                _formatSelectedTime(time, showDateRing: widget.showDateRing),
                style: TextStyle(
                  fontSize: 14 * scale,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
              SizedBox(height: 2 * scale),

              // Radiation label
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontSize: 12 * scale,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white70 : Colors.black54,
                  letterSpacing: 1.2,
                  shadows: isDark ? null : [
                    Shadow(color: Colors.white, blurRadius: 2),
                  ],
                ),
              ),
              SizedBox(height: 2 * scale),

              // Irradiance value
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.wb_sunny,
                    size: 20 * scale,
                    color: color,
                    shadows: [
                      Shadow(
                        color: isDark ? Colors.black54 : Colors.white,
                        blurRadius: 3,
                      ),
                    ],
                  ),
                  SizedBox(width: 4 * scale),
                  Text(
                    '${irradiance.toStringAsFixed(0)} W/m²',
                    style: TextStyle(
                      fontSize: 18 * scale,
                      fontWeight: FontWeight.bold,
                      color: color,
                      shadows: [
                        Shadow(
                          color: isDark ? Colors.black54 : Colors.white,
                          blurRadius: 3,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 8 * scale),

              // Power output (if panel configured)
              if (hasPanelConfig && watts != null) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.electric_bolt,
                      size: 18 * scale,
                      color: Colors.amber,
                      shadows: [
                        Shadow(
                          color: isDark ? Colors.black54 : Colors.white,
                          blurRadius: 3,
                        ),
                      ],
                    ),
                    SizedBox(width: 4 * scale),
                    Text(
                      _formatWatts(watts),
                      style: TextStyle(
                        fontSize: 20 * scale,
                        fontWeight: FontWeight.w600,
                        color: Colors.amber,
                        shadows: [
                          Shadow(
                            color: isDark ? Colors.black54 : Colors.white,
                            blurRadius: 3,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ] else if (!hasPanelConfig) ...[
                // No panel configured message
                Text(
                  'No panel configured',
                  style: TextStyle(
                    fontSize: 12 * scale,
                    color: isDark ? Colors.white38 : Colors.black26,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],

              SizedBox(height: 20 * scale), // Space for dots
            ],
          ),
        ),
      ],
    );
  }

  /// Build night-time solar display
  Widget _buildNightSolarDisplay(DateTime selectedTime, bool isDark, double centerSize, double scale) {
    return Padding(
      padding: EdgeInsets.all(12 * scale),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _formatSelectedTime(selectedTime, showDateRing: widget.showDateRing),
            style: TextStyle(
              fontSize: 14 * scale,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
          SizedBox(height: 8 * scale),
          Icon(
            Icons.nightlight_round,
            size: 32 * scale,
            color: Colors.indigo.shade300,
          ),
          SizedBox(height: 8 * scale),
          Text(
            'NIGHT',
            style: TextStyle(
              fontSize: 14 * scale,
              fontWeight: FontWeight.bold,
              color: Colors.indigo.shade300,
              letterSpacing: 1.2,
            ),
          ),
          SizedBox(height: 4 * scale),
          Text(
            'No solar output',
            style: TextStyle(
              fontSize: 12 * scale,
              color: isDark ? Colors.white38 : Colors.black26,
            ),
          ),
          SizedBox(height: 20 * scale),
        ],
      ),
    );
  }

  String _formatWatts(double watts) {
    if (watts < 1) return '0W';
    if (watts >= 1000) {
      return '${(watts / 1000).toStringAsFixed(1)}kW';
    }
    return '${watts.toStringAsFixed(0)}W';
  }

  Widget _buildForecastContent(HourlyForecast forecast, DateTime time, bool isDark, double centerSize) {
    final scale = (centerSize / 200).clamp(0.6, 1.2);
    final weatherEffect = _getWeatherEffect(forecast);

    return Stack(
      alignment: Alignment.center,
      children: [
        // Weather icon as background - fills the middle area
        Positioned.fill(
          child: Padding(
            padding: EdgeInsets.all(centerSize * 0.15),
            child: Opacity(
              opacity: 0.40,
              child: SvgPicture.asset(
                forecast.weatherIconAsset,
                fit: BoxFit.contain,
                placeholderBuilder: (context) => Icon(
                  forecast.fallbackIcon,
                  size: centerSize * 0.5,
                  color: _getWeatherIconColor(forecast.icon),
                ),
              ),
            ),
          ),
        ),
        // Animated weather effect overlay
        if (widget.showWeatherAnimation && weatherEffect.type != WeatherEffectType.none)
          Positioned.fill(
            child: _WeatherEffectOverlay(
              effectType: weatherEffect.type,
              intensity: weatherEffect.intensity,
              size: centerSize,
            ),
          ),
        // Data content on top
        Padding(
          padding: EdgeInsets.all(8 * scale),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Time label (shows only day name when date ring is visible)
              Text(
                _formatSelectedTime(time, showDateRing: widget.showDateRing),
                style: TextStyle(
                  fontSize: 14 * scale,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
              SizedBox(height: 2 * scale),

              // Conditions text
              Text(
                forecast.longDescription ?? forecast.conditions ?? '',
                style: TextStyle(
                  fontSize: 11 * scale,
                  color: isDark ? Colors.white60 : Colors.black45,
                ),
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 4 * scale),

              // Temperature (large)
              Text(
                forecast.temperature != null
                    ? '${forecast.temperature!.toStringAsFixed(0)}${widget.tempUnit}'
                    : '--',
                style: TextStyle(
                  fontSize: 28 * scale,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              SizedBox(height: 4 * scale),

              // Wind speed and direction
              if (forecast.windSpeed != null)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (forecast.windDirection != null)
                      Transform.rotate(
                        angle: (forecast.windDirection! + 180) * math.pi / 180,
                        child: Icon(
                          Icons.navigation,
                          size: 18 * scale,
                          color: Colors.teal.shade300,
                        ),
                      ),
                    SizedBox(width: 3 * scale),
                    Text(
                      '${forecast.windSpeed!.toStringAsFixed(0)} ${widget.windUnit}',
                      style: TextStyle(
                        fontSize: 16 * scale,
                        color: Colors.teal.shade300,
                      ),
                    ),
                    if (forecast.windDirection != null) ...[
                      SizedBox(width: 3 * scale),
                      Text(
                        _getWindDirectionLabel(forecast.windDirection!),
                        style: TextStyle(
                          fontSize: 13 * scale,
                          color: Colors.teal.shade300,
                        ),
                      ),
                    ],
                  ],
                ),
              SizedBox(height: 2 * scale),

              // Humidity and Rain probability row
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (forecast.humidity != null) ...[
                    Icon(Icons.water_drop, size: 16 * scale, color: Colors.cyan.shade300),
                    Text(
                      ' ${forecast.humidity!.toStringAsFixed(0)}%',
                      style: TextStyle(fontSize: 14 * scale, color: Colors.cyan.shade300),
                    ),
                  ],
                  if (forecast.humidity != null && forecast.precipProbability != null)
                    SizedBox(width: 10 * scale),
                  if (forecast.precipProbability != null) ...[
                    Icon(Icons.umbrella, size: 16 * scale, color: Colors.blue.shade300),
                    Text(
                      ' ${forecast.precipProbability!.toStringAsFixed(0)}%',
                      style: TextStyle(fontSize: 14 * scale, color: Colors.blue.shade300),
                    ),
                  ],
                ],
              ),
              SizedBox(height: 2 * scale),

              // Pressure
              if (forecast.pressure != null)
                Text(
                  '${forecast.pressure!.toStringAsFixed(0)} ${widget.pressureUnit}',
                  style: TextStyle(
                    fontSize: 13 * scale,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),

              SizedBox(height: 16 * scale), // Space for button area
            ],
          ),
        ),
      ],
    );
  }

  /// Detect weather effect type and intensity from forecast
  ///
  /// Returns a record with effect type and intensity (0.0-1.0)
  /// Some effects are composite (thunder includes rain, sleet includes snow+rain)
  ///
  /// FUTURE: For even more complex combinations, could return List<WeatherEffectType>
  /// and render multiple independent overlays with distributed particle counts.
  ({WeatherEffectType type, double intensity}) _getWeatherEffect(HourlyForecast forecast) {
    final conditions = forecast.conditions?.toLowerCase() ?? '';
    final icon = forecast.icon?.toLowerCase() ?? '';
    final combined = '$conditions $icon';

    // Determine rain intensity from conditions
    double rainIntensity = 0.5; // default moderate
    if (combined.contains('drizzle') || combined.contains('light')) {
      rainIntensity = 0.3;
    } else if (combined.contains('heavy') || combined.contains('violent') || combined.contains('torrential')) {
      rainIntensity = 1.0;
    } else if (combined.contains('moderate')) {
      rainIntensity = 0.6;
    }

    // Check for thunder first - includes rain effect
    if (combined.contains('thunder') || combined.contains('lightning')) {
      return (type: WeatherEffectType.thunder, intensity: rainIntensity);
    }

    // Check for sleet - composite of snow + rain
    if (combined.contains('sleet') || combined.contains('ice pellet') || combined.contains('freezing rain')) {
      return (type: WeatherEffectType.sleet, intensity: 0.5);
    }

    // Check for hail
    if (combined.contains('hail')) {
      return (type: WeatherEffectType.hail, intensity: 0.7);
    }

    // Check for snow
    if (combined.contains('snow') || combined.contains('flurr')) {
      double snowIntensity = 0.5;
      if (combined.contains('light') || combined.contains('flurr')) {
        snowIntensity = 0.3;
      } else if (combined.contains('heavy') || combined.contains('blizzard')) {
        snowIntensity = 1.0;
      }
      return (type: WeatherEffectType.snow, intensity: snowIntensity);
    }

    // Check for rain
    if (combined.contains('rain') || combined.contains('drizzle') || combined.contains('shower')) {
      return (type: WeatherEffectType.rain, intensity: rainIntensity);
    }

    // Check for wind (high wind speed or wind in conditions)
    final windSpeed = forecast.windSpeed ?? 0;
    if (combined.contains('wind') || windSpeed > 25) {
      double windIntensity = (windSpeed / 50).clamp(0.3, 1.0);
      return (type: WeatherEffectType.wind, intensity: windIntensity);
    }

    return (type: WeatherEffectType.none, intensity: 0.0);
  }

  /// Format selected time for display
  /// When showDateRing is true, only show day name (date/time is on the ring)
  /// When showDateRing is false, show full date and time
  /// Note: time parameter should already be in location time
  String _formatSelectedTime(DateTime time, {bool showDateRing = false}) {
    // Get location's "now" for Today/Tomorrow comparison
    final deviceNow = DateTime.now();
    final locationNow = widget.sunMoonTimes?.toLocationTime(deviceNow) ?? deviceNow;

    final isToday = time.day == locationNow.day && time.month == locationNow.month && time.year == locationNow.year;
    final locationTomorrow = locationNow.add(const Duration(days: 1));
    final isTomorrow = time.day == locationTomorrow.day && time.month == locationTomorrow.month && time.year == locationTomorrow.year;

    // When date ring is shown, only display day name (time is on the ring)
    if (showDateRing) {
      if (isToday) {
        return 'Today';
      } else if (isTomorrow) {
        return 'Tomorrow';
      } else {
        final dayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
        return dayNames[time.weekday - 1];
      }
    }

    // Full date and time when date ring is not shown
    final hour = time.hour;
    final minute = time.minute;
    final minuteStr = minute.toString().padLeft(2, '0');
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final ampm = hour < 12 ? 'AM' : 'PM';
    final hourStr = '$displayHour:$minuteStr $ampm';

    if (isToday) {
      return hourStr;
    } else if (isTomorrow) {
      return 'Tomorrow $hourStr';
    } else {
      final dayName = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][time.weekday - 1];
      return '$dayName $hourStr';
    }
  }

  Color _getTimeOfDayColor(DateTime time) {
    // Use DaylightService for unified, hemisphere-aware calculations
    return DaylightService.getSegmentColor(
      time,
      widget.sunMoonTimes,
      useLocationTimezone: true,
    );
  }

  String _getWindDirectionLabel(double degrees) {
    const directions = ['N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE',
                        'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW'];
    final index = ((degrees + 11.25) % 360 / 22.5).floor();
    return directions[index];
  }

  // ============ Center Mode Helpers ============

  /// Get list of available center display modes based on config and data
  List<CenterDisplayMode> _getAvailableModes() {
    final modes = <CenterDisplayMode>[CenterDisplayMode.weather];
    if (widget.showWindCenter) {
      modes.add(CenterDisplayMode.wind);
    }
    if (widget.showSeaCenter && widget.marineData != null) {
      modes.add(CenterDisplayMode.sea);
    }
    if (widget.showSolarCenter) {
      modes.add(CenterDisplayMode.solar);
    }
    return modes;
  }

  /// Cycle to next available center display mode
  void _cycleCenterMode() {
    final modes = _getAvailableModes();
    if (modes.length <= 1) return;

    final currentIndex = modes.indexOf(_currentCenterMode);
    final nextIndex = (currentIndex + 1) % modes.length;
    setState(() {
      _currentCenterMode = modes[nextIndex];
    });
  }

  // ============ Beaufort/Douglas Scale Helpers ============

  /// Get Beaufort description from scale number (0-12)
  String _getBeaufortDescription(int bf) {
    const descriptions = [
      'Calm',
      'Light air',
      'Light breeze',
      'Gentle breeze',
      'Moderate breeze',
      'Fresh breeze',
      'Strong breeze',
      'Near gale',
      'Gale',
      'Strong gale',
      'Storm',
      'Violent storm',
      'Hurricane',
    ];
    return descriptions[bf.clamp(0, 12)];
  }

  /// Get sea state label from wave height in meters
  String _getSeaStateLabel(double meters) {
    if (meters < 0.1) return 'Calm (glassy)';
    if (meters < 0.5) return 'Calm (rippled)';
    if (meters < 1.25) return 'Smooth';
    if (meters < 2.5) return 'Slight';
    if (meters < 4.0) return 'Moderate';
    if (meters < 6.0) return 'Rough';
    if (meters < 9.0) return 'Very rough';
    if (meters < 14.0) return 'High';
    return 'Phenomenal';
  }

  Color _getWeatherIconColor(String? iconCode) {
    final code = iconCode?.toLowerCase() ?? '';
    if (code.contains('clear')) return Colors.amber;
    if (code.contains('partly-cloudy')) return Colors.blueGrey;
    if (code.contains('cloudy')) return Colors.grey;
    if (code.contains('rainy') || code.contains('rain')) return Colors.blue;
    if (code.contains('thunder')) return Colors.deepPurple;
    if (code.contains('snow')) return Colors.lightBlue.shade100;
    if (code.contains('sleet')) return Colors.cyan;
    if (code.contains('foggy')) return Colors.blueGrey;
    if (code.contains('windy')) return Colors.teal;
    return Colors.grey;
  }
}

/// Custom painter for the spinnable rim
class _ForecastRimPainter extends CustomPainter {
  final SunMoonTimes? times;
  final double rotationAngle;
  final bool isDark;
  final int selectedHourOffset;
  final List<Color>? cachedSegmentColors;
  final DateTime cachedNow;
  final int maxForecastHours;
  final bool showPrimaryIcons;
  final bool showSecondaryIcons;

  _ForecastRimPainter({
    required this.times,
    required this.rotationAngle,
    required this.isDark,
    required this.selectedHourOffset,
    this.cachedSegmentColors,
    required this.cachedNow,
    required this.maxForecastHours,
    this.showPrimaryIcons = true,
    this.showSecondaryIcons = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    try {
      _paintInternal(canvas, size);
    } catch (e) {
      debugPrint('ForecastRimPainter error: $e');
    }
  }

  void _paintInternal(Canvas canvas, Size size) {
    if (size.isEmpty || !rotationAngle.isFinite) return;

    final center = Offset(size.width / 2, size.height / 2);
    final scale = (size.width / 300).clamp(0.5, 1.5);

    final outerMargin = 43.0 * scale;
    final outerRadius = size.width / 2 - outerMargin;
    final innerRadius = outerRadius * 0.72;
    final rimWidth = outerRadius - innerRadius;

    if (outerRadius <= 0 || innerRadius <= 0 || rimWidth <= 0) return;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotationAngle);
    canvas.translate(-center.dx, -center.dy);

    final currentViewHour = (-rotationAngle / (math.pi / 12)).round().clamp(0, maxForecastHours);

    const radiansPerSegment = (2 * math.pi) / 24;

    final arcRect = Rect.fromCircle(center: center, radius: (outerRadius + innerRadius) / 2);
    final segmentPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = rimWidth
      ..strokeCap = StrokeCap.butt;

    final startHour = currentViewHour - 14;
    final endHour = currentViewHour + 14;

    for (int hourIndex = startHour; hourIndex < endHour; hourIndex++) {
      final startAngle = -math.pi / 2 + (hourIndex * math.pi / 12);
      const sweepAngle = radiansPerSegment + 0.01;

      Color color = Colors.transparent;
      bool shouldDraw = true;

      if (hourIndex >= 0 && hourIndex < maxForecastHours) {
        color = cachedSegmentColors != null && hourIndex < cachedSegmentColors!.length
            ? cachedSegmentColors![hourIndex]
            : _getFallbackColor(hourIndex * 60);
      } else if (hourIndex < 0) {
        final overlappingHour = hourIndex + 24;
        if (overlappingHour >= 0 && overlappingHour < maxForecastHours) {
          shouldDraw = false;
        } else {
          color = _muteColor(_getFallbackColor(0));
        }
      } else {
        final overlappingHour = hourIndex - 24;
        if (overlappingHour >= 0 && overlappingHour < maxForecastHours) {
          shouldDraw = false;
        } else {
          color = _muteColor(_getFallbackColor((maxForecastHours - 1) * 60));
        }
      }

      if (shouldDraw) {
        segmentPaint.color = color;
        canvas.drawArc(arcRect, startAngle, sweepAngle, false, segmentPaint);
      }
    }

    // Draw hour tick marks
    final tickPaint = Paint()
      ..color = isDark ? Colors.white54 : Colors.black38
      ..strokeWidth = 2 * scale;

    for (int i = 0; i < 24; i++) {
      final angle = -math.pi / 2 + (i * math.pi / 12);
      final outerPoint = Offset(
        center.dx + outerRadius * math.cos(angle),
        center.dy + outerRadius * math.sin(angle),
      );
      final innerPoint = Offset(
        center.dx + (outerRadius - 8 * scale) * math.cos(angle),
        center.dy + (outerRadius - 8 * scale) * math.sin(angle),
      );
      canvas.drawLine(innerPoint, outerPoint, tickPaint);
    }

    // Draw hour labels (in location time, not device time)
    final textStyle = TextStyle(
      fontSize: 9 * scale,
      color: isDark ? Colors.white70 : Colors.black54,
      fontWeight: FontWeight.w500,
    );

    // Convert cachedNow to location time
    final locationNow = times?.toLocationTime(cachedNow) ?? cachedNow;

    for (int i = 0; i < 24; i += 6) {
      final angle = -math.pi / 2 + (i * math.pi / 12);
      final labelRadius = innerRadius - 12 * scale;
      final labelCenter = Offset(
        center.dx + labelRadius * math.cos(angle),
        center.dy + labelRadius * math.sin(angle),
      );

      String labelText;
      if (i == 0) {
        final hour = locationNow.hour;
        final minute = locationNow.minute;
        final ampm = hour < 12 ? 'AM' : 'PM';
        final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
        labelText = '$displayHour:${minute.toString().padLeft(2, '0')} $ampm';
      } else {
        final futureTime = locationNow.add(Duration(hours: i));
        final hour = futureTime.hour;
        final ampm = hour < 12 ? 'AM' : 'PM';
        final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
        labelText = '$displayHour $ampm';
      }

      final textSpan = TextSpan(text: labelText, style: textStyle);
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      canvas.save();
      canvas.translate(labelCenter.dx, labelCenter.dy);
      canvas.rotate(-rotationAngle);
      canvas.translate(-textPainter.width / 2, -textPainter.height / 2);
      textPainter.paint(canvas, Offset.zero);
      canvas.restore();
    }

    // Draw sun/moon icons on the rim
    _drawSunMoonIcons(canvas, center, outerRadius, innerRadius, cachedNow, scale);

    canvas.restore();

    // Draw outer border (doesn't rotate)
    final borderPaint = Paint()
      ..color = isDark ? Colors.white24 : Colors.black12
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * scale;
    canvas.drawCircle(center, outerRadius, borderPaint);
  }

  void _drawSunMoonIcons(Canvas canvas, Offset center, double outerRadius, double innerRadius, DateTime now, double scale) {
    if (times == null) return;

    final iconRadius = (outerRadius + innerRadius) / 2;
    final iconSize = 27.0 * scale;

    // Helper to get angle for a specific time
    double? getAngleForTime(DateTime? eventTime) {
      if (eventTime == null) return null;
      if (!rotationAngle.isFinite) return null;

      final hoursFromNow = eventTime.difference(now).inMinutes / 60.0;
      if (!hoursFromNow.isFinite) return null;

      final centerHour = -rotationAngle / (math.pi / 12);
      final minVisibleHour = centerHour - 12;
      final maxVisibleHour = centerHour + 12;

      if (hoursFromNow < minVisibleHour || hoursFromNow > maxVisibleHour) return null;
      if (hoursFromNow < -2 || hoursFromNow > maxForecastHours) return null;

      return -math.pi / 2 + (hoursFromNow * math.pi / 12);
    }

    // Draw sun icon (circle with rays)
    void drawSunIcon(Offset iconCenter, double angle, DateTime eventTime, bool isRise) {
      canvas.save();
      canvas.translate(iconCenter.dx, iconCenter.dy);
      canvas.rotate(-rotationAngle);

      final sunRadius = iconSize / 2 - 2 * scale;

      // Draw sun glow
      final glowPaint = Paint()
        ..color = (isRise ? Colors.orange.shade300 : Colors.deepOrange.shade400).withValues(alpha: 0.5)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset.zero, sunRadius + 4 * scale, glowPaint);

      // Draw sun body
      final sunPaint = Paint()
        ..color = isRise ? Colors.orange.shade400 : Colors.deepOrange.shade500
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset.zero, sunRadius, sunPaint);

      // Draw rays
      final rayPaint = Paint()
        ..color = isRise ? Colors.orange.shade300 : Colors.deepOrange.shade400
        ..strokeWidth = 2 * scale
        ..style = PaintingStyle.stroke;

      for (int i = 0; i < 8; i++) {
        final rayAngle = i * math.pi / 4;
        final start = Offset(
          (sunRadius + 2 * scale) * math.cos(rayAngle),
          (sunRadius + 2 * scale) * math.sin(rayAngle),
        );
        final end = Offset(
          (sunRadius + 5 * scale) * math.cos(rayAngle),
          (sunRadius + 5 * scale) * math.sin(rayAngle),
        );
        canvas.drawLine(start, end, rayPaint);
      }

      // Draw arrow indicator
      final arrowPaint = Paint()
        ..color = Colors.white
        ..strokeWidth = 3 * scale
        ..style = PaintingStyle.stroke;
      if (isRise) {
        canvas.drawLine(Offset(0, 5 * scale), Offset(0, -7 * scale), arrowPaint);
        canvas.drawLine(Offset(-5 * scale, 0), Offset(0, -7 * scale), arrowPaint);
        canvas.drawLine(Offset(5 * scale, 0), Offset(0, -7 * scale), arrowPaint);
      } else {
        canvas.drawLine(Offset(0, -5 * scale), Offset(0, 7 * scale), arrowPaint);
        canvas.drawLine(Offset(-5 * scale, 0), Offset(0, 7 * scale), arrowPaint);
        canvas.drawLine(Offset(5 * scale, 0), Offset(0, 7 * scale), arrowPaint);
      }

      canvas.restore();

      // Draw time label outside the rim
      final labelRadius = outerRadius + 14 * scale;
      final labelCenter = Offset(
        center.dx + labelRadius * math.cos(angle),
        center.dy + labelRadius * math.sin(angle),
      );

      final timeText = DateTimeFormatter.formatTime(times!.toLocationTime(eventTime));
      final textSpan = TextSpan(
        text: timeText,
        style: TextStyle(
          fontSize: 10 * scale,
          fontWeight: FontWeight.w600,
          color: isRise ? Colors.orange.shade400 : Colors.deepOrange.shade500,
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      canvas.save();
      canvas.translate(labelCenter.dx, labelCenter.dy);
      canvas.rotate(-rotationAngle);
      canvas.translate(-textPainter.width / 2, -textPainter.height / 2);
      textPainter.paint(canvas, Offset.zero);
      canvas.restore();
    }

    // Draw moon icon with phase calculated dynamically for the event time
    void drawMoonIcon(Offset iconCenter, double angle, DateTime eventTime, bool isRise) {
      canvas.save();
      canvas.translate(iconCenter.dx, iconCenter.dy);
      canvas.rotate(-rotationAngle);

      final moonRadius = iconSize / 2 - 1 * scale;
      // Calculate moon illumination for the specific event time
      final moonIllum = MoonCalc.getIllumination(eventTime);
      var phase = moonIllum.phase;
      var fraction = moonIllum.fraction;
      if (!phase.isFinite) phase = 0.5;
      if (!fraction.isFinite) fraction = 0.5;
      fraction = fraction.clamp(0.0, 1.0);

      // Draw moon background (dark side)
      final darkPaint = Paint()
        ..color = Colors.grey.shade800
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset.zero, moonRadius, darkPaint);

      // Draw illuminated side
      final lightPaint = Paint()
        ..color = Colors.grey.shade200
        ..style = PaintingStyle.fill;

      if (fraction > 0.01 && fraction < 0.99) {
        // In Southern Hemisphere, moon appears flipped left-to-right
        final bool isNorthernHemisphere = !(times?.isSouthernHemisphere ?? false);
        final bool isWaxing = isNorthernHemisphere ? (phase < 0.5) : (phase >= 0.5);
        final termWidth = moonRadius * (2.0 * fraction - 1.0);
        final isGibbous = fraction > 0.5;
        // Ensure minimum visible crescent width (at least 20% of radius)
        final minVisibleWidth = moonRadius * 0.20;
        final ellipseX = termWidth.abs().clamp(minVisibleWidth, moonRadius - 0.1);

        if (!ellipseX.isFinite || !moonRadius.isFinite) {
          canvas.drawArc(
            Rect.fromCircle(center: Offset.zero, radius: moonRadius),
            isWaxing ? -math.pi / 2 : math.pi / 2,
            math.pi,
            true,
            lightPaint,
          );
        } else {
          final path = Path();
          if (isWaxing) {
            path.moveTo(0, -moonRadius);
            path.arcToPoint(Offset(0, moonRadius), radius: Radius.circular(moonRadius), clockwise: true);
            path.arcToPoint(Offset(0, -moonRadius), radius: Radius.elliptical(ellipseX, moonRadius), clockwise: isGibbous);
          } else {
            path.moveTo(0, -moonRadius);
            path.arcToPoint(Offset(0, moonRadius), radius: Radius.circular(moonRadius), clockwise: false);
            path.arcToPoint(Offset(0, -moonRadius), radius: Radius.elliptical(ellipseX, moonRadius), clockwise: !isGibbous);
          }
          path.close();
          canvas.drawPath(path, lightPaint);

          // Add subtle glow around illuminated edge for visibility
          final glowPaint = Paint()
            ..color = Colors.grey.shade400.withValues(alpha: 0.4)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5 * scale;
          canvas.drawPath(path, glowPaint);
        }
      } else if (fraction >= 0.99) {
        canvas.drawCircle(Offset.zero, moonRadius, lightPaint);
      }

      // Draw arrow indicator OUTSIDE the moon circle
      final arrowPaint = Paint()
        ..color = isRise ? Colors.cyan.shade300 : Colors.blueGrey.shade400
        ..strokeWidth = 2.5 * scale
        ..style = PaintingStyle.stroke;
      final arrowOffset = moonRadius + 4 * scale; // Position arrow outside moon
      if (isRise) {
        // Arrow pointing up, positioned below the moon
        canvas.drawLine(Offset(0, arrowOffset + 5 * scale), Offset(0, arrowOffset - 3 * scale), arrowPaint);
        canvas.drawLine(Offset(-4 * scale, arrowOffset + 1 * scale), Offset(0, arrowOffset - 3 * scale), arrowPaint);
        canvas.drawLine(Offset(4 * scale, arrowOffset + 1 * scale), Offset(0, arrowOffset - 3 * scale), arrowPaint);
      } else {
        // Arrow pointing down, positioned above the moon
        canvas.drawLine(Offset(0, -arrowOffset - 5 * scale), Offset(0, -arrowOffset + 3 * scale), arrowPaint);
        canvas.drawLine(Offset(-4 * scale, -arrowOffset - 1 * scale), Offset(0, -arrowOffset + 3 * scale), arrowPaint);
        canvas.drawLine(Offset(4 * scale, -arrowOffset - 1 * scale), Offset(0, -arrowOffset + 3 * scale), arrowPaint);
      }

      canvas.restore();

      // Draw time label
      final labelRadius = outerRadius + 14 * scale;
      final labelCenter = Offset(
        center.dx + labelRadius * math.cos(angle),
        center.dy + labelRadius * math.sin(angle),
      );

      final timeText = DateTimeFormatter.formatTime(times!.toLocationTime(eventTime));
      final textSpan = TextSpan(
        text: timeText,
        style: TextStyle(
          fontSize: 10 * scale,
          fontWeight: FontWeight.w600,
          color: isRise ? Colors.cyan.shade300 : Colors.blueGrey.shade400,
        ),
      );
      final textPainter = TextPainter(text: textSpan, textDirection: TextDirection.ltr);
      textPainter.layout();

      canvas.save();
      canvas.translate(labelCenter.dx, labelCenter.dy);
      canvas.rotate(-rotationAngle);
      canvas.translate(-textPainter.width / 2, -textPainter.height / 2);
      textPainter.paint(canvas, Offset.zero);
      canvas.restore();
    }

    // Secondary icon size and radius (smaller, outside the rim)
    final secondaryIconSize = iconSize * 0.5;
    final secondaryIconRadius = outerRadius + 8 * scale;

    // Draw twilight icon (sun with horizon line)
    void drawTwilightIcon(Offset iconCenter, double angle, DateTime eventTime, bool isDawn, bool isNautical) {
      canvas.save();
      canvas.translate(iconCenter.dx, iconCenter.dy);
      canvas.rotate(-rotationAngle);

      final tinyRadius = secondaryIconSize / 3;
      final color = isNautical
          ? (isDawn ? Colors.indigo.shade300 : Colors.indigo.shade400)
          : (isDawn ? Colors.purple.shade300 : Colors.deepPurple.shade300);

      // Draw horizon line
      final horizonPaint = Paint()
        ..color = color
        ..strokeWidth = 1.5 * scale
        ..style = PaintingStyle.stroke;
      canvas.drawLine(Offset(-tinyRadius - 2 * scale, 0), Offset(tinyRadius + 2 * scale, 0), horizonPaint);

      // Draw half sun
      final sunPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;

      final rect = Rect.fromCircle(center: Offset.zero, radius: tinyRadius);
      if (isDawn) {
        canvas.drawArc(rect, 0, math.pi, true, sunPaint);
      } else {
        canvas.drawArc(rect, -math.pi, math.pi, true, sunPaint);
      }

      // Draw tiny stars for nautical twilight
      if (isNautical) {
        final starPaint = Paint()
          ..color = Colors.white70
          ..style = PaintingStyle.fill;
        canvas.drawCircle(Offset(-tinyRadius - 1 * scale, -tinyRadius), 1.5 * scale, starPaint);
        canvas.drawCircle(Offset(tinyRadius + 1 * scale, -tinyRadius + 1 * scale), 1 * scale, starPaint);
      }

      canvas.restore();
    }

    // Draw golden hour icon (half sun with warm glow)
    void drawGoldenHourIcon(Offset iconCenter, double angle, DateTime eventTime, bool isMorning) {
      canvas.save();
      canvas.translate(iconCenter.dx, iconCenter.dy);
      canvas.rotate(-rotationAngle);

      final tinyRadius = secondaryIconSize / 2.5;

      // Draw warm golden glow
      final glowPaint = Paint()
        ..color = Colors.orange.shade300.withValues(alpha: 0.5)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(0, isMorning ? 2 * scale : -2 * scale), tinyRadius + 3 * scale, glowPaint);

      // Draw horizon line
      final horizonPaint = Paint()
        ..color = Colors.orange.shade400
        ..strokeWidth = 2 * scale
        ..style = PaintingStyle.stroke;
      canvas.drawLine(Offset(-tinyRadius - 4 * scale, 0), Offset(tinyRadius + 4 * scale, 0), horizonPaint);

      // Draw half sun
      final sunPaint = Paint()
        ..color = Colors.orange.shade500
        ..style = PaintingStyle.fill;

      final rect = Rect.fromCircle(center: Offset.zero, radius: tinyRadius);
      if (isMorning) {
        canvas.drawArc(rect, math.pi, math.pi, true, sunPaint);
      } else {
        canvas.drawArc(rect, 0, math.pi, true, sunPaint);
      }

      // Draw rays on visible half
      final rayPaint = Paint()
        ..color = Colors.amber.shade400
        ..strokeWidth = 1.5 * scale
        ..style = PaintingStyle.stroke;

      for (int i = 0; i < 3; i++) {
        final rayAngle = (isMorning ? -math.pi / 2 : math.pi / 2) + (i - 1) * math.pi / 6;
        final start = Offset(
          (tinyRadius + 1 * scale) * math.cos(rayAngle),
          (tinyRadius + 1 * scale) * math.sin(rayAngle),
        );
        final end = Offset(
          (tinyRadius + 4 * scale) * math.cos(rayAngle),
          (tinyRadius + 4 * scale) * math.sin(rayAngle),
        );
        canvas.drawLine(start, end, rayPaint);
      }

      canvas.restore();
    }

    // Draw solar noon icon (sun at peak)
    void drawSolarNoonIcon(Offset iconCenter, double angle, DateTime eventTime) {
      canvas.save();
      canvas.translate(iconCenter.dx, iconCenter.dy);
      canvas.rotate(-rotationAngle);

      final tinyRadius = secondaryIconSize / 3;

      // Draw bright glow
      final glowPaint = Paint()
        ..color = Colors.yellow.shade100.withValues(alpha: 0.5)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset.zero, tinyRadius + 3 * scale, glowPaint);

      // Draw sun
      final sunPaint = Paint()
        ..color = Colors.yellow.shade600
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset.zero, tinyRadius, sunPaint);

      // Draw rays
      final rayPaint = Paint()
        ..color = Colors.yellow.shade400
        ..strokeWidth = 1 * scale
        ..style = PaintingStyle.stroke;

      for (int i = 0; i < 8; i++) {
        final rayAngle = i * math.pi / 4;
        final start = Offset(
          (tinyRadius + 1 * scale) * math.cos(rayAngle),
          (tinyRadius + 1 * scale) * math.sin(rayAngle),
        );
        final end = Offset(
          (tinyRadius + 3 * scale) * math.cos(rayAngle),
          (tinyRadius + 3 * scale) * math.sin(rayAngle),
        );
        canvas.drawLine(start, end, rayPaint);
      }

      canvas.restore();
    }

    // Draw icons for all available days
    for (int dayIndex = 0; dayIndex < times!.days.length; dayIndex++) {
      final dayTimes = times!.days[dayIndex];

      // Secondary icons (dusk, dawn, golden hours, etc.)
      if (showSecondaryIcons) {
        // Nautical Dawn
        if (dayTimes.nauticalDawn != null) {
          final angle = getAngleForTime(dayTimes.nauticalDawn);
          if (angle != null) {
            final pos = Offset(center.dx + secondaryIconRadius * math.cos(angle),
                               center.dy + secondaryIconRadius * math.sin(angle));
            drawTwilightIcon(pos, angle, dayTimes.nauticalDawn!, true, true);
          }
        }

        // Dawn (civil twilight)
        if (dayTimes.dawn != null) {
          final angle = getAngleForTime(dayTimes.dawn);
          if (angle != null) {
            final pos = Offset(center.dx + secondaryIconRadius * math.cos(angle),
                               center.dy + secondaryIconRadius * math.sin(angle));
            drawTwilightIcon(pos, angle, dayTimes.dawn!, true, false);
          }
        }
      }

      // Sunrise - primary, on rim
      if (showPrimaryIcons && dayTimes.sunrise != null) {
        final angle = getAngleForTime(dayTimes.sunrise);
        if (angle != null) {
          final pos = Offset(center.dx + iconRadius * math.cos(angle),
                             center.dy + iconRadius * math.sin(angle));
          drawSunIcon(pos, angle, dayTimes.sunrise!, true);
        }
      }

      if (showSecondaryIcons) {
        // Golden Hour End (morning)
        if (dayTimes.goldenHourEnd != null) {
          final angle = getAngleForTime(dayTimes.goldenHourEnd);
          if (angle != null) {
            final pos = Offset(center.dx + secondaryIconRadius * math.cos(angle),
                               center.dy + secondaryIconRadius * math.sin(angle));
            drawGoldenHourIcon(pos, angle, dayTimes.goldenHourEnd!, true);
          }
        }

        // Solar Noon
        if (dayTimes.solarNoon != null) {
          final angle = getAngleForTime(dayTimes.solarNoon);
          if (angle != null) {
            final pos = Offset(center.dx + secondaryIconRadius * math.cos(angle),
                               center.dy + secondaryIconRadius * math.sin(angle));
            drawSolarNoonIcon(pos, angle, dayTimes.solarNoon!);
          }
        }

        // Golden Hour (evening)
        if (dayTimes.goldenHour != null) {
          final angle = getAngleForTime(dayTimes.goldenHour);
          if (angle != null) {
            final pos = Offset(center.dx + secondaryIconRadius * math.cos(angle),
                               center.dy + secondaryIconRadius * math.sin(angle));
            drawGoldenHourIcon(pos, angle, dayTimes.goldenHour!, false);
          }
        }
      }

      // Sunset - primary, on rim
      if (showPrimaryIcons && dayTimes.sunset != null) {
        final angle = getAngleForTime(dayTimes.sunset);
        if (angle != null) {
          final pos = Offset(center.dx + iconRadius * math.cos(angle),
                             center.dy + iconRadius * math.sin(angle));
          drawSunIcon(pos, angle, dayTimes.sunset!, false);
        }
      }

      if (showSecondaryIcons) {
        // Dusk (civil twilight)
        if (dayTimes.dusk != null) {
          final angle = getAngleForTime(dayTimes.dusk);
          if (angle != null) {
            final pos = Offset(center.dx + secondaryIconRadius * math.cos(angle),
                               center.dy + secondaryIconRadius * math.sin(angle));
            drawTwilightIcon(pos, angle, dayTimes.dusk!, false, false);
          }
        }

        // Nautical Dusk
        if (dayTimes.nauticalDusk != null) {
          final angle = getAngleForTime(dayTimes.nauticalDusk);
          if (angle != null) {
            final pos = Offset(center.dx + secondaryIconRadius * math.cos(angle),
                               center.dy + secondaryIconRadius * math.sin(angle));
            drawTwilightIcon(pos, angle, dayTimes.nauticalDusk!, false, true);
          }
        }
      }

      // Moonrise - primary, on rim
      if (showPrimaryIcons && dayTimes.moonrise != null) {
        final angle = getAngleForTime(dayTimes.moonrise);
        if (angle != null) {
          final pos = Offset(center.dx + iconRadius * math.cos(angle),
                             center.dy + iconRadius * math.sin(angle));
          drawMoonIcon(pos, angle, dayTimes.moonrise!, true);
        }
      }

      // Moonset - primary, on rim
      if (showPrimaryIcons && dayTimes.moonset != null) {
        final angle = getAngleForTime(dayTimes.moonset);
        if (angle != null) {
          final pos = Offset(center.dx + iconRadius * math.cos(angle),
                             center.dy + iconRadius * math.sin(angle));
          drawMoonIcon(pos, angle, dayTimes.moonset!, false);
        }
      }
    }
  }

  Color _getFallbackColor(int minutesFromNow) {
    final segmentTime = cachedNow.add(Duration(minutes: minutesFromNow));
    final hour = segmentTime.hour;
    if (hour >= 5 && hour < 6) return Colors.indigo.shade700;
    if (hour >= 6 && hour < 7) return Colors.indigo.shade400;
    if (hour >= 7 && hour < 8) return Colors.orange.shade300;
    if (hour >= 8 && hour < 16) return Colors.amber.shade200;
    if (hour >= 16 && hour < 17) return Colors.orange.shade400;
    if (hour >= 17 && hour < 18) return Colors.deepOrange.shade400;
    if (hour >= 18 && hour < 19) return Colors.indigo.shade700;
    return Colors.indigo.shade900;
  }

  Color _muteColor(Color color) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withSaturation((hsl.saturation * 0.3).clamp(0.0, 1.0))
        .withLightness((hsl.lightness * 0.7).clamp(0.0, 1.0))
        .toColor()
        .withValues(alpha: 0.4);
  }

  @override
  bool shouldRepaint(covariant _ForecastRimPainter oldDelegate) {
    return oldDelegate.rotationAngle != rotationAngle ||
           oldDelegate.isDark != isDark ||
           !identical(oldDelegate.cachedSegmentColors, cachedSegmentColors);
  }
}

/// Animated weather effect overlay for the center circle
class _WeatherEffectOverlay extends StatefulWidget {
  final WeatherEffectType effectType;
  final double intensity; // 0.0-1.0 affects particle count and appearance
  final double size;

  const _WeatherEffectOverlay({
    required this.effectType,
    required this.size,
    this.intensity = 0.5,
  });

  @override
  State<_WeatherEffectOverlay> createState() => _WeatherEffectOverlayState();
}

class _WeatherEffectOverlayState extends State<_WeatherEffectOverlay>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  final List<_WeatherParticle> _particles = [];
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _controller.addListener(_updateParticles);
    _initParticles();
  }

  @override
  void didUpdateWidget(_WeatherEffectOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.effectType != widget.effectType ||
        oldWidget.intensity != widget.intensity) {
      _initParticles();
    }
  }

  void _initParticles() {
    _particles.clear();
    if (widget.effectType == WeatherEffectType.none) return;

    // Base particle counts, scaled by intensity
    int count;
    switch (widget.effectType) {
      case WeatherEffectType.wind:
        count = 6;
        break;
      case WeatherEffectType.rain:
        // Rain: 8-20 particles based on intensity
        count = (8 + widget.intensity * 12).round();
        break;
      case WeatherEffectType.thunder:
        // Thunder: lightning flashes + rain particles
        count = (10 + widget.intensity * 10).round();
        break;
      case WeatherEffectType.sleet:
        // Sleet: mix of snow and rain
        count = 14;
        break;
      case WeatherEffectType.snow:
      case WeatherEffectType.hail:
        count = (8 + widget.intensity * 8).round();
        break;
      case WeatherEffectType.none:
        count = 0;
    }

    for (int i = 0; i < count; i++) {
      // Determine particle type for composite effects
      _ParticleType particleType;
      if (widget.effectType == WeatherEffectType.sleet) {
        // Sleet: alternate between snow and rain
        particleType = i % 2 == 0 ? _ParticleType.snow : _ParticleType.rain;
      } else if (widget.effectType == WeatherEffectType.thunder) {
        // Thunder: mostly rain with occasional lightning
        particleType = i < 2 ? _ParticleType.lightning : _ParticleType.rain;
      } else {
        particleType = _ParticleType.values.firstWhere(
          (t) => t.name == widget.effectType.name,
          orElse: () => _ParticleType.rain,
        );
      }

      _particles.add(_WeatherParticle(
        x: _random.nextDouble(),
        y: _random.nextDouble(),
        speed: 0.3 + _random.nextDouble() * 0.4,
        size: 0.8 + _random.nextDouble() * 0.4,
        delay: _random.nextDouble(),
        particleType: particleType,
      ));
    }
  }

  void _updateParticles() {
    if (!mounted) return;
    setState(() {
      for (final p in _particles) {
        final progress = (_controller.value + p.delay) % 1.0;

        switch (p.particleType) {
          case _ParticleType.wind:
            // Horizontal movement for wind
            p.currentX = (p.x + progress * p.speed * 2) % 1.0;
            p.currentY = p.y + math.sin(progress * math.pi * 4) * 0.05;
            break;
          case _ParticleType.rain:
            // Rain falls straight down
            p.currentX = p.x;
            p.currentY = (progress * p.speed * 1.5 + p.y) % 1.0;
            break;
          case _ParticleType.snow:
            // Snow drifts slightly side to side
            p.currentX = p.x + math.sin(progress * math.pi * 2) * 0.04;
            p.currentY = (progress * p.speed * 0.7 + p.y) % 1.0;
            break;
          case _ParticleType.hail:
            // Hail falls fast and straight
            p.currentX = p.x;
            p.currentY = (progress * p.speed * 1.8 + p.y) % 1.0;
            break;
          case _ParticleType.lightning:
            // Lightning flashes in place
            p.currentX = p.x;
            p.currentY = p.y;
            // Flicker effect handled in build
            break;
        }
      }
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_updateParticles);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.effectType == WeatherEffectType.none) {
      return const SizedBox.shrink();
    }

    return ClipOval(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: Stack(
          children: [
            // Draw lightning bolts first (behind rain)
            if (widget.effectType == WeatherEffectType.thunder)
              ..._buildLightningBolts(),
            // Draw particles (rain, snow, etc.)
            ..._particles
                .where((p) => p.particleType != _ParticleType.lightning)
                .map((p) {
              final iconSize = 14.0 * p.size;
              return Positioned(
                left: p.currentX * widget.size - iconSize / 2,
                top: p.currentY * widget.size - iconSize / 2,
                child: Opacity(
                  opacity: 0.6,
                  child: _buildParticleIcon(p.particleType, iconSize),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  /// Build branching lightning bolt widgets
  List<Widget> _buildLightningBolts() {
    final bolts = <Widget>[];

    // Get lightning particles for timing/position seeds
    final lightningParticles = _particles
        .where((p) => p.particleType == _ParticleType.lightning)
        .toList();

    for (int i = 0; i < lightningParticles.length; i++) {
      final p = lightningParticles[i];
      // Flicker effect - brief bright flash
      final flicker = ((_controller.value + p.delay) * 6) % 1.0;
      final isVisible = flicker < 0.12; // Very brief flash

      if (isVisible) {
        bolts.add(
          Positioned.fill(
            child: CustomPaint(
              painter: _LightningBoltPainter(
                seed: (p.x * 1000 + p.y * 100 + _controller.value * 10).toInt(),
                startX: 0.2 + p.x * 0.6, // Vary horizontal position
                color: Colors.yellow.shade200,
                glowColor: Colors.white,
              ),
            ),
          ),
        );
      }
    }

    return bolts;
  }

  Widget _buildParticleIcon(_ParticleType type, double size) {
    // Use filled drops for heavy rain (intensity > 0.7)
    final useFilledRain = widget.intensity > 0.7;

    switch (type) {
      case _ParticleType.rain:
        return Icon(
          useFilledRain ? PhosphorIconsFill.drop : PhosphorIcons.drop(),
          size: size,
          color: Colors.blue.shade300,
        );
      case _ParticleType.snow:
        return Icon(
          PhosphorIcons.snowflake(),
          size: size,
          color: Colors.white70,
        );
      case _ParticleType.wind:
        return Icon(
          PhosphorIcons.wind(),
          size: size,
          color: Colors.teal.shade300,
        );
      case _ParticleType.hail:
        return Icon(
          PhosphorIcons.cloudSnow(),
          size: size,
          color: Colors.cyan.shade200,
        );
      case _ParticleType.lightning:
        return Icon(
          PhosphorIconsFill.lightning,
          size: size * 1.5, // Lightning bolts are bigger
          color: Colors.yellow.shade300,
        );
    }
  }
}

/// Particle types for mixed weather effects
enum _ParticleType { rain, snow, wind, hail, lightning }

/// Single weather particle for animation
class _WeatherParticle {
  double x;
  double y;
  double speed;
  double size;
  double delay;
  double currentX = 0;
  double currentY = 0;
  final _ParticleType particleType;

  _WeatherParticle({
    required this.x,
    required this.y,
    required this.speed,
    required this.size,
    required this.delay,
    required this.particleType,
  }) {
    currentX = x;
    currentY = y;
  }
}

/// Custom painter for branching lightning bolts
class _LightningBoltPainter extends CustomPainter {
  final int seed;
  final double startX; // 0.0-1.0 horizontal position
  final Color color;
  final Color glowColor;

  _LightningBoltPainter({
    required this.seed,
    required this.startX,
    required this.color,
    required this.glowColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(seed);

    // Main bolt path
    final mainPath = _generateBoltPath(
      random,
      Offset(size.width * startX, size.height * 0.05),
      Offset(size.width * (startX + (random.nextDouble() - 0.5) * 0.3), size.height * 0.85),
      size,
      segments: 6,
      jitter: 0.15,
    );

    // Draw glow (thick, semi-transparent)
    final glowPaint = Paint()
      ..color = glowColor.withValues(alpha: 0.4)
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(mainPath, glowPaint);

    // Draw main bolt (medium thickness)
    final boltPaint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(mainPath, boltPaint);

    // Draw core (thin, bright white)
    final corePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(mainPath, corePaint);

    // Add 1-2 branches
    final branchCount = 1 + random.nextInt(2);
    for (int i = 0; i < branchCount; i++) {
      final branchStartRatio = 0.3 + random.nextDouble() * 0.4;
      final mainPoints = _getPathPoints(mainPath);
      if (mainPoints.length < 3) continue;

      final branchStartIndex = (mainPoints.length * branchStartRatio).floor();
      final branchStart = mainPoints[branchStartIndex];

      // Branch goes diagonally down
      final branchEndX = branchStart.dx + (random.nextDouble() - 0.5) * size.width * 0.4;
      final branchEndY = branchStart.dy + size.height * (0.15 + random.nextDouble() * 0.2);

      final branchPath = _generateBoltPath(
        random,
        branchStart,
        Offset(branchEndX.clamp(0, size.width), branchEndY.clamp(0, size.height)),
        size,
        segments: 3,
        jitter: 0.12,
      );

      // Draw branch with thinner strokes
      canvas.drawPath(branchPath, glowPaint..strokeWidth = 4);
      canvas.drawPath(branchPath, boltPaint..strokeWidth = 2);
      canvas.drawPath(branchPath, corePaint..strokeWidth = 1);
    }
  }

  Path _generateBoltPath(
    math.Random random,
    Offset start,
    Offset end,
    Size size, {
    required int segments,
    required double jitter,
  }) {
    final path = Path();
    path.moveTo(start.dx, start.dy);

    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;

    for (int i = 1; i <= segments; i++) {
      final progress = i / segments;
      var nextX = start.dx + dx * progress;
      final nextY = start.dy + dy * progress;

      // Add jitter (more in the middle, less at ends)
      if (i < segments) {
        final jitterAmount = jitter * size.width * math.sin(progress * math.pi);
        nextX += (random.nextDouble() - 0.5) * 2 * jitterAmount;
      }

      path.lineTo(nextX, nextY);
    }

    return path;
  }

  List<Offset> _getPathPoints(Path path) {
    final metrics = path.computeMetrics().first;
    final points = <Offset>[];
    final length = metrics.length;

    for (double d = 0; d <= length; d += length / 10) {
      final tangent = metrics.getTangentForOffset(d);
      if (tangent != null) {
        points.add(tangent.position);
      }
    }

    return points;
  }

  @override
  bool shouldRepaint(covariant _LightningBoltPainter oldDelegate) {
    return oldDelegate.seed != seed || oldDelegate.startX != startX;
  }
}

/// Fixed date ring painter showing either full year or forecast range
/// January 1 is at the top (12 o'clock position) in year mode
/// Current hour is at top in range mode
class _DateRingPainter extends CustomPainter {
  final DateTime selectedDate;
  final bool isDark;
  final Color primaryColor;
  final String mode; // 'year' or 'range'
  final int forecastHours;
  final int currentHourOffset;

  _DateRingPainter({
    required this.selectedDate,
    required this.isDark,
    required this.primaryColor,
    this.mode = 'range',
    this.forecastHours = 72,
    this.currentHourOffset = 0,
  });

  /// Get complementary/opposite color
  Color get _oppositeColor {
    // Calculate complementary color (opposite on color wheel)
    final hsl = HSLColor.fromColor(primaryColor);
    final complementaryHue = (hsl.hue + 180) % 360;
    return HSLColor.fromAHSL(1.0, complementaryHue, hsl.saturation.clamp(0.5, 1.0), hsl.lightness.clamp(0.3, 0.7)).toColor();
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (mode == 'range') {
      _paintRangeMode(canvas, size);
    } else {
      _paintYearMode(canvas, size);
    }
  }

  /// Paint the year mode - full 365/366 days with month labels
  void _paintYearMode(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final scale = (size.width / 300).clamp(0.5, 1.5);

    // Date ring with margin for 3-letter month labels
    final ringRadius = size.width / 2 - 16 * scale;
    final ringWidth = 8 * scale;

    // Calculate days in current year
    final year = selectedDate.year;
    final isLeapYear = (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0);
    final daysInYear = isLeapYear ? 366 : 365;

    // Calculate day of year for selected date (1-365/366)
    final startOfYear = DateTime(year, 1, 1);
    final dayOfYear = selectedDate.difference(startOfYear).inDays + 1;

    // Draw background ring
    final bgPaint = Paint()
      ..color = isDark ? Colors.grey.shade900 : Colors.grey.shade200
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringWidth;
    canvas.drawCircle(center, ringRadius, bgPaint);

    // Draw tick marks for each day
    final tickPaint = Paint()
      ..color = isDark ? Colors.grey.shade700 : Colors.grey.shade400
      ..strokeWidth = 0.5 * scale;

    for (int day = 1; day <= daysInYear; day++) {
      // Angle: Jan 1 at top (-π/2), going clockwise
      final angle = -math.pi / 2 + (day - 1) * 2 * math.pi / daysInYear;

      // Tick length varies: longer for first of month
      final dayDate = startOfYear.add(Duration(days: day - 1));
      final isFirstOfMonth = dayDate.day == 1;
      final tickLength = isFirstOfMonth ? 6 * scale : 2 * scale;

      final innerRadius = ringRadius - ringWidth / 2;
      final outerRadius = ringRadius - ringWidth / 2 + tickLength;

      final x1 = center.dx + innerRadius * math.cos(angle);
      final y1 = center.dy + innerRadius * math.sin(angle);
      final x2 = center.dx + outerRadius * math.cos(angle);
      final y2 = center.dy + outerRadius * math.sin(angle);

      // First of month gets thicker tick
      if (isFirstOfMonth) {
        tickPaint.strokeWidth = 1.5 * scale;
        tickPaint.color = isDark ? Colors.grey.shade500 : Colors.grey.shade600;
      } else {
        tickPaint.strokeWidth = 0.5 * scale;
        tickPaint.color = isDark ? Colors.grey.shade700 : Colors.grey.shade400;
      }

      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), tickPaint);
    }

    // Draw month labels
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final monthStarts = [1, 32, 60, 91, 121, 152, 182, 213, 244, 274, 305, 335];
    if (isLeapYear) {
      for (int i = 2; i < monthStarts.length; i++) {
        monthStarts[i]++;
      }
    }

    for (int m = 0; m < 12; m++) {
      final midDay = monthStarts[m] + 14; // Middle of month approximately
      final angle = -math.pi / 2 + (midDay - 1) * 2 * math.pi / daysInYear;
      final labelRadius = ringRadius + 10 * scale;

      final x = center.dx + labelRadius * math.cos(angle);
      final y = center.dy + labelRadius * math.sin(angle);

      final textPainter = TextPainter(
        text: TextSpan(
          text: months[m],
          style: TextStyle(
            fontSize: 8 * scale,
            color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      canvas.save();
      canvas.translate(x, y);
      canvas.translate(-textPainter.width / 2, -textPainter.height / 2);
      textPainter.paint(canvas, Offset.zero);
      canvas.restore();
    }

    // Highlight selected date with a chevron marker pointing inward
    final selectedAngle = -math.pi / 2 + (dayOfYear - 1) * 2 * math.pi / daysInYear;
    final markerColor = _oppositeColor;

    // Draw chevron pointing toward center
    final chevronOuterRadius = ringRadius + 6 * scale;
    final chevronInnerRadius = ringRadius - 2 * scale;
    final chevronWidth = 8 * scale;

    final chevronPaint = Paint()
      ..color = markerColor
      ..style = PaintingStyle.fill;

    // Calculate chevron points
    final tipX = center.dx + chevronInnerRadius * math.cos(selectedAngle);
    final tipY = center.dy + chevronInnerRadius * math.sin(selectedAngle);

    // Perpendicular angle for chevron wings
    final perpAngle = selectedAngle + math.pi / 2;
    final wingOffset = chevronWidth / 2;

    final leftWingX = center.dx + chevronOuterRadius * math.cos(selectedAngle) - wingOffset * math.cos(perpAngle);
    final leftWingY = center.dy + chevronOuterRadius * math.sin(selectedAngle) - wingOffset * math.sin(perpAngle);
    final rightWingX = center.dx + chevronOuterRadius * math.cos(selectedAngle) + wingOffset * math.cos(perpAngle);
    final rightWingY = center.dy + chevronOuterRadius * math.sin(selectedAngle) + wingOffset * math.sin(perpAngle);

    final chevronPath = Path()
      ..moveTo(tipX, tipY)
      ..lineTo(leftWingX, leftWingY)
      ..lineTo(rightWingX, rightWingY)
      ..close();

    canvas.drawPath(chevronPath, chevronPaint);

    // Draw date label near the marker
    final dateLabel = '${selectedDate.month}/${selectedDate.day}';
    final datePainter = TextPainter(
      text: TextSpan(
        text: dateLabel,
        style: TextStyle(
          fontSize: 9 * scale,
          color: markerColor,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    datePainter.layout();

    // Position label inside the ring
    final labelRadius2 = ringRadius - ringWidth - 8 * scale;
    final labelX = center.dx + labelRadius2 * math.cos(selectedAngle) - datePainter.width / 2;
    final labelY = center.dy + labelRadius2 * math.sin(selectedAngle) - datePainter.height / 2;
    datePainter.paint(canvas, Offset(labelX, labelY));
  }

  /// Paint the range mode - forecast hours with hourly ticks and date labels
  void _paintRangeMode(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final scale = (size.width / 300).clamp(0.5, 1.5);

    // Date ring with margin for date labels
    final ringRadius = size.width / 2 - 16 * scale;
    final ringWidth = 8 * scale;

    // Calculate the start time (now) for the forecast
    final now = DateTime.now();
    final forecastStart = DateTime(now.year, now.month, now.day, now.hour);

    // Draw background ring
    final bgPaint = Paint()
      ..color = isDark ? Colors.grey.shade900 : Colors.grey.shade200
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringWidth;
    canvas.drawCircle(center, ringRadius, bgPaint);

    // Draw tick marks for each hour
    final tickPaint = Paint()
      ..color = isDark ? Colors.grey.shade700 : Colors.grey.shade400
      ..strokeWidth = 0.5 * scale;

    // Track midnight positions for date labels
    final List<int> midnightHours = [];

    for (int hour = 0; hour < forecastHours; hour++) {
      // Angle: hour 0 at top (-π/2), going clockwise
      final angle = -math.pi / 2 + hour * 2 * math.pi / forecastHours;

      final hourTime = forecastStart.add(Duration(hours: hour));
      final isMidnight = hourTime.hour == 0;
      final isSixHour = hourTime.hour % 6 == 0;

      if (isMidnight && hour > 0) {
        midnightHours.add(hour);
      }

      // Tick length: midnight 6px, 6-hour 4px, regular 2px
      double tickLength;
      if (isMidnight) {
        tickLength = 6 * scale;
        tickPaint.strokeWidth = 1.5 * scale;
        tickPaint.color = isDark ? Colors.grey.shade400 : Colors.grey.shade700;
      } else if (isSixHour) {
        tickLength = 4 * scale;
        tickPaint.strokeWidth = 1.0 * scale;
        tickPaint.color = isDark ? Colors.grey.shade500 : Colors.grey.shade600;
      } else {
        tickLength = 2 * scale;
        tickPaint.strokeWidth = 0.5 * scale;
        tickPaint.color = isDark ? Colors.grey.shade700 : Colors.grey.shade400;
      }

      final innerRadius = ringRadius - ringWidth / 2;
      final outerRadius = ringRadius - ringWidth / 2 + tickLength;

      final x1 = center.dx + innerRadius * math.cos(angle);
      final y1 = center.dy + innerRadius * math.sin(angle);
      final x2 = center.dx + outerRadius * math.cos(angle);
      final y2 = center.dy + outerRadius * math.sin(angle);

      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), tickPaint);
    }

    // Draw date labels at midnight positions
    final forecastDays = (forecastHours / 24).ceil();
    final skipLabels = forecastDays > 7; // Skip labels for long forecasts

    for (final midnightHour in midnightHours) {
      // Skip every other label for 7+ day forecasts
      if (skipLabels && midnightHours.indexOf(midnightHour) % 2 == 1) continue;

      final angle = -math.pi / 2 + midnightHour * 2 * math.pi / forecastHours;
      final labelRadius = ringRadius + 10 * scale;

      final hourTime = forecastStart.add(Duration(hours: midnightHour));
      final dateLabel = '${hourTime.month}/${hourTime.day}';

      final x = center.dx + labelRadius * math.cos(angle);
      final y = center.dy + labelRadius * math.sin(angle);

      final textPainter = TextPainter(
        text: TextSpan(
          text: dateLabel,
          style: TextStyle(
            fontSize: 8 * scale,
            color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      canvas.save();
      canvas.translate(x, y);
      canvas.translate(-textPainter.width / 2, -textPainter.height / 2);
      textPainter.paint(canvas, Offset.zero);
      canvas.restore();
    }

    // Highlight current hour position with a chevron marker
    final selectedAngle = -math.pi / 2 + currentHourOffset * 2 * math.pi / forecastHours;
    final markerColor = _oppositeColor;

    // Draw chevron pointing toward center
    final chevronOuterRadius = ringRadius + 6 * scale;
    final chevronInnerRadius = ringRadius - 2 * scale;
    final chevronWidth = 8 * scale;

    final chevronPaint = Paint()
      ..color = markerColor
      ..style = PaintingStyle.fill;

    // Calculate chevron points
    final tipX = center.dx + chevronInnerRadius * math.cos(selectedAngle);
    final tipY = center.dy + chevronInnerRadius * math.sin(selectedAngle);

    // Perpendicular angle for chevron wings
    final perpAngle = selectedAngle + math.pi / 2;
    final wingOffset = chevronWidth / 2;

    final leftWingX = center.dx + chevronOuterRadius * math.cos(selectedAngle) - wingOffset * math.cos(perpAngle);
    final leftWingY = center.dy + chevronOuterRadius * math.sin(selectedAngle) - wingOffset * math.sin(perpAngle);
    final rightWingX = center.dx + chevronOuterRadius * math.cos(selectedAngle) + wingOffset * math.cos(perpAngle);
    final rightWingY = center.dy + chevronOuterRadius * math.sin(selectedAngle) + wingOffset * math.sin(perpAngle);

    final chevronPath = Path()
      ..moveTo(tipX, tipY)
      ..lineTo(leftWingX, leftWingY)
      ..lineTo(rightWingX, rightWingY)
      ..close();

    canvas.drawPath(chevronPath, chevronPaint);

    // Draw time label near the marker (showing hour:00)
    final timeLabel = '${selectedDate.hour}:00';
    final timePainter = TextPainter(
      text: TextSpan(
        text: timeLabel,
        style: TextStyle(
          fontSize: 9 * scale,
          color: markerColor,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    timePainter.layout();

    // Position label inside the ring
    final labelRadius2 = ringRadius - ringWidth - 8 * scale;
    final labelX = center.dx + labelRadius2 * math.cos(selectedAngle) - timePainter.width / 2;
    final labelY = center.dy + labelRadius2 * math.sin(selectedAngle) - timePainter.height / 2;
    timePainter.paint(canvas, Offset(labelX, labelY));
  }

  @override
  bool shouldRepaint(covariant _DateRingPainter oldDelegate) {
    return oldDelegate.selectedDate != selectedDate ||
           oldDelegate.isDark != isDark ||
           oldDelegate.primaryColor != primaryColor ||
           oldDelegate.mode != mode ||
           oldDelegate.forecastHours != forecastHours ||
           oldDelegate.currentHourOffset != currentHourOffset;
  }
}

/// Custom painter for wave animation in sea state center
class _WavesPainter extends CustomPainter {
  final double progress;
  final double waveHeight;
  final double? wavePeriod;
  final bool isDark;
  final int beaufort;

  _WavesPainter({
    required this.progress,
    required this.waveHeight,
    this.wavePeriod,
    required this.isDark,
    required this.beaufort,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Clip to circle
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: radius * 0.95)));

    // Wave parameters based on wave height and period
    final amplitude = (8 + waveHeight * 6).clamp(8.0, 35.0);
    final waveCount = ((wavePeriod ?? 6) / 2.5).clamp(2.0, 5.0);

    // Draw multiple wave layers for depth effect
    for (int layer = 2; layer >= 0; layer--) {
      final layerOffset = layer * 0.2;
      final layerAlpha = 0.12 + (2 - layer) * 0.06;
      final layerAmplitude = amplitude * (1 - layer * 0.15);
      final baseY = center.dy + radius * 0.15 + layer * 12;

      final paint = Paint()
        ..color = Colors.blue.shade400.withValues(alpha: layerAlpha)
        ..style = PaintingStyle.fill;

      final path = Path();

      // Start from left bottom
      path.moveTo(center.dx - radius, center.dy + radius);
      path.lineTo(center.dx - radius, baseY);

      // Draw wave curve
      final steps = 60;
      for (int i = 0; i <= steps; i++) {
        final x = center.dx - radius + (i / steps) * radius * 2;
        final wavePhase = (progress + layerOffset) * 2 * math.pi;
        final y = baseY + math.sin((i / steps) * waveCount * 2 * math.pi + wavePhase) * layerAmplitude;
        path.lineTo(x, y);
      }

      // Close path at bottom right
      path.lineTo(center.dx + radius, center.dy + radius);
      path.close();

      canvas.drawPath(path, paint);

      // Draw white foam/highlights on wave crests for top layer only
      if (layer == 0) {
        final foamPaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.25)
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;

        final foamPath = Path();
        bool started = false;

        for (int i = 0; i <= steps; i++) {
          final x = center.dx - radius * 0.9 + (i / steps) * radius * 1.8;
          final wavePhase = progress * 2 * math.pi;
          final y = baseY + math.sin((i / steps) * waveCount * 2 * math.pi + wavePhase) * layerAmplitude;

          // Only draw at wave peaks (where derivative is near zero and going down)
          final derivative = math.cos((i / steps) * waveCount * 2 * math.pi + wavePhase);
          if (derivative.abs() < 0.4 && math.sin((i / steps) * waveCount * 2 * math.pi + wavePhase) > 0.3) {
            if (!started) {
              foamPath.moveTo(x, y);
              started = true;
            } else {
              foamPath.lineTo(x, y);
            }
          } else {
            started = false;
          }
        }

        canvas.drawPath(foamPath, foamPaint);
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _WavesPainter oldDelegate) {
    return oldDelegate.progress != progress ||
           oldDelegate.waveHeight != waveHeight ||
           oldDelegate.wavePeriod != wavePeriod ||
           oldDelegate.isDark != isDark ||
           oldDelegate.beaufort != beaufort;
  }
}

/// Animated sun rays effect for solar center display
class _SunRaysAnimation extends StatefulWidget {
  final double intensity; // 0.0-1.0 affects opacity and ray count
  final bool isDark;

  const _SunRaysAnimation({
    required this.intensity,
    required this.isDark,
  });

  @override
  State<_SunRaysAnimation> createState() => _SunRaysAnimationState();
}

class _SunRaysAnimationState extends State<_SunRaysAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 20),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: _SunRaysPainter(
            progress: _controller.value,
            intensity: widget.intensity,
            isDark: widget.isDark,
          ),
        );
      },
    );
  }
}

/// Custom painter for animated sun rays
class _SunRaysPainter extends CustomPainter {
  final double progress;
  final double intensity;
  final bool isDark;

  _SunRaysPainter({
    required this.progress,
    required this.intensity,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = math.max(size.width, size.height);

    // Number of rays based on intensity
    final rayCount = (8 + (intensity * 8)).round();
    final baseAngle = progress * 2 * math.pi;

    // Draw rays
    for (int i = 0; i < rayCount; i++) {
      final angle = baseAngle + (i * 2 * math.pi / rayCount);

      // Vary ray properties
      final rayIntensity = 0.5 + 0.5 * math.sin(progress * 4 * math.pi + i);
      final rayLength = maxRadius * (0.3 + 0.3 * rayIntensity);
      final rayWidth = math.pi / 60 * (1 + rayIntensity);

      final rayPaint = Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 1.0,
          colors: [
            Colors.orange.withValues(alpha: intensity * 0.15 * rayIntensity),
            Colors.amber.withValues(alpha: intensity * 0.08 * rayIntensity),
            Colors.transparent,
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: rayLength))
        ..style = PaintingStyle.fill;

      // Draw ray as a narrow arc/wedge
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..arcTo(
          Rect.fromCircle(center: center, radius: rayLength),
          angle - rayWidth / 2,
          rayWidth,
          false,
        )
        ..close();

      canvas.drawPath(path, rayPaint);
    }

    // Draw central glow
    final glowPaint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 0.5,
        colors: [
          Colors.amber.withValues(alpha: intensity * 0.2),
          Colors.orange.withValues(alpha: intensity * 0.1),
          Colors.transparent,
        ],
        stops: const [0.0, 0.4, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: maxRadius * 0.5));

    canvas.drawCircle(center, maxRadius * 0.3, glowPaint);
  }

  @override
  bool shouldRepaint(covariant _SunRaysPainter oldDelegate) {
    return oldDelegate.progress != progress ||
           oldDelegate.intensity != intensity ||
           oldDelegate.isDark != isDark;
  }
}
