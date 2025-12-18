/// Circular forecast spinner widget
/// Adapted from ZedDisplay for WeatherFlow
///
/// Displays a spinnable dial showing 24+ hours of forecast data
/// Center shows detailed conditions for selected time

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'forecast_models.dart';

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

  /// Callback when selected hour changes
  final void Function(int hourOffset)? onHourChanged;

  /// Whether to show animated weather effects
  final bool showWeatherAnimation;

  const ForecastSpinner({
    super.key,
    required this.hourlyForecasts,
    this.sunMoonTimes,
    this.tempUnit = '°F',
    this.windUnit = 'kn',
    this.pressureUnit = 'hPa',
    this.primaryColor = Colors.blue,
    this.providerName,
    this.onHourChanged,
    this.showWeatherAnimation = true,
  });

  @override
  State<ForecastSpinner> createState() => _ForecastSpinnerState();
}

class _ForecastSpinnerState extends State<ForecastSpinner>
    with SingleTickerProviderStateMixin {
  final ValueNotifier<double> _rotationNotifier = ValueNotifier<double>(0.0);
  double _previousAngle = 0.0;
  int _lastSelectedHourOffset = 0;
  late AnimationController _controller;
  Animation<double>? _snapAnimation;
  List<Color>? _cachedSegmentColors;
  DateTime _cachedNow = DateTime.now();

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
  Color _computeSegmentColor(DateTime time, SunMoonTimes? times) {
    if (times != null) {
      final todayStart = DateTime(_cachedNow.year, _cachedNow.month, _cachedNow.day);
      final dayIndex = time.difference(todayStart).inDays;
      final dayTimes = times.getDay(dayIndex);

      if (dayTimes != null) {
        final sunrise = dayTimes.sunrise;
        final sunset = dayTimes.sunset;
        final dawn = dayTimes.dawn;
        final dusk = dayTimes.dusk;
        final goldenHour = dayTimes.goldenHour;
        final goldenHourEnd = dayTimes.goldenHourEnd;
        final nauticalDawn = dayTimes.nauticalDawn;
        final nauticalDusk = dayTimes.nauticalDusk;

        if (sunrise != null && sunset != null) {
          final timeMinutes = time.hour * 60 + time.minute;
          final sunriseLocal = sunrise.toLocal();
          final sunsetLocal = sunset.toLocal();
          final sunriseMin = sunriseLocal.hour * 60 + sunriseLocal.minute;
          final sunsetMin = sunsetLocal.hour * 60 + sunsetLocal.minute;
          final dawnLocal = dawn?.toLocal();
          final duskLocal = dusk?.toLocal();
          final nauticalDawnLocal = nauticalDawn?.toLocal();
          final nauticalDuskLocal = nauticalDusk?.toLocal();
          final goldenHourLocal = goldenHour?.toLocal();
          final goldenHourEndLocal = goldenHourEnd?.toLocal();
          final dawnMin = dawnLocal != null ? dawnLocal.hour * 60 + dawnLocal.minute : sunriseMin - 30;
          final duskMin = duskLocal != null ? duskLocal.hour * 60 + duskLocal.minute : sunsetMin + 30;
          final nauticalDawnMin = nauticalDawnLocal != null ? nauticalDawnLocal.hour * 60 + nauticalDawnLocal.minute : dawnMin - 30;
          final nauticalDuskMin = nauticalDuskLocal != null ? nauticalDuskLocal.hour * 60 + nauticalDuskLocal.minute : duskMin + 30;
          final goldenHourEndMin = goldenHourEndLocal != null ? goldenHourEndLocal.hour * 60 + goldenHourEndLocal.minute : sunriseMin + 60;
          final goldenHourMin = goldenHourLocal != null ? goldenHourLocal.hour * 60 + goldenHourLocal.minute : sunsetMin - 60;

          if (timeMinutes < nauticalDawnMin) return Colors.indigo.shade900;
          if (timeMinutes >= nauticalDawnMin && timeMinutes < dawnMin) return Colors.indigo.shade700;
          if (timeMinutes >= dawnMin && timeMinutes < sunriseMin) return Colors.indigo.shade400;
          if (timeMinutes >= sunriseMin && timeMinutes < goldenHourEndMin) return Colors.orange.shade300;
          if (timeMinutes >= goldenHourEndMin && timeMinutes < goldenHourMin) return Colors.amber.shade200;
          if (timeMinutes >= goldenHourMin && timeMinutes < sunsetMin) return Colors.orange.shade300;
          if (timeMinutes >= sunsetMin && timeMinutes < duskMin) return Colors.deepOrange.shade400;
          if (timeMinutes >= duskMin && timeMinutes < nauticalDuskMin) return Colors.indigo.shade700;
          if (timeMinutes >= nauticalDuskMin) return Colors.indigo.shade900;
        }
      }
    }

    // Fallback: use simplified hour-based colors
    final hour = time.hour;
    if (hour >= 5 && hour < 6) return Colors.indigo.shade700;
    if (hour >= 6 && hour < 7) return Colors.indigo.shade400;
    if (hour >= 7 && hour < 8) return Colors.orange.shade300;
    if (hour >= 8 && hour < 16) return Colors.amber.shade200;
    if (hour >= 16 && hour < 17) return Colors.orange.shade400;
    if (hour >= 17 && hour < 18) return Colors.deepOrange.shade400;
    if (hour >= 18 && hour < 19) return Colors.indigo.shade700;
    return Colors.indigo.shade900;
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
        final size = math.min(constraints.maxWidth, constraints.maxHeight);
        _currentSize = Size(size, size);
        final scale = (size / 300).clamp(0.5, 1.5);

        return RepaintBoundary(
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.center,
              children: [
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
                          ),
                        );
                      },
                    ),
                  ),
                ),

                // Selection indicator at top
                Positioned(
                  top: 0,
                  child: IgnorePointer(
                    child: Container(
                      width: 20 * scale,
                      height: 30 * scale,
                      decoration: BoxDecoration(
                        color: Colors.red,
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

                // Center content
                IgnorePointer(
                  ignoring: true,
                  child: _buildCenterContent(size, isDark),
                ),

                // Return to Now button
                if (_selectedHourOffset > 0)
                  Positioned(
                    bottom: size * 0.22,
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

                // Provider name
                if (widget.providerName != null && widget.providerName!.isNotEmpty)
                  Positioned(
                    top: 4 * scale,
                    left: 4 * scale,
                    child: IgnorePointer(
                      child: Text(
                        widget.providerName!,
                        style: TextStyle(
                          fontSize: 10 * scale,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white54 : Colors.black45,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCenterContent(double size, bool isDark) {
    final scale = (size / 300).clamp(0.5, 1.5);
    final outerMargin = 27.0 * scale;
    final outerRadius = size / 2 - outerMargin;
    final innerRadius = outerRadius * 0.72;
    final centerSize = innerRadius * 2;
    final forecast = _selectedHourOffset < widget.hourlyForecasts.length
        ? widget.hourlyForecasts[_selectedHourOffset]
        : null;

    final selectedTime = DateTime.now().add(Duration(minutes: _selectedMinuteOffset));
    final bgColor = _getTimeOfDayColor(selectedTime);

    return Container(
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
      child: forecast == null
          ? const Center(child: Text('No data'))
          : _buildForecastContent(forecast, selectedTime, isDark, centerSize),
    );
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
              // Time label
              Text(
                _formatSelectedTime(time),
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

  String _formatSelectedTime(DateTime time) {
    final now = DateTime.now();
    final isToday = time.day == now.day && time.month == now.month && time.year == now.year;
    final tomorrow = now.add(const Duration(days: 1));
    final isTomorrow = time.day == tomorrow.day && time.month == tomorrow.month && time.year == tomorrow.year;

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
    // Use actual sun times if available - matches _computeSegmentColor logic
    final times = widget.sunMoonTimes;
    if (times != null && times.days.isNotEmpty) {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final dayIndex = time.difference(todayStart).inDays;
      final dayTimes = times.getDay(dayIndex);

      if (dayTimes != null) {
        final sunrise = dayTimes.sunrise;
        final sunset = dayTimes.sunset;
        final dawn = dayTimes.dawn;
        final dusk = dayTimes.dusk;
        final goldenHour = dayTimes.goldenHour;
        final goldenHourEnd = dayTimes.goldenHourEnd;
        final nauticalDawn = dayTimes.nauticalDawn;
        final nauticalDusk = dayTimes.nauticalDusk;

        if (sunrise != null && sunset != null) {
          final timeMinutes = time.hour * 60 + time.minute;
          final sunriseLocal = sunrise.toLocal();
          final sunsetLocal = sunset.toLocal();
          final sunriseMin = sunriseLocal.hour * 60 + sunriseLocal.minute;
          final sunsetMin = sunsetLocal.hour * 60 + sunsetLocal.minute;
          final dawnLocal = dawn?.toLocal();
          final duskLocal = dusk?.toLocal();
          final nauticalDawnLocal = nauticalDawn?.toLocal();
          final nauticalDuskLocal = nauticalDusk?.toLocal();
          final goldenHourLocal = goldenHour?.toLocal();
          final goldenHourEndLocal = goldenHourEnd?.toLocal();
          final dawnMin = dawnLocal != null ? dawnLocal.hour * 60 + dawnLocal.minute : sunriseMin - 30;
          final duskMin = duskLocal != null ? duskLocal.hour * 60 + duskLocal.minute : sunsetMin + 30;
          final nauticalDawnMin = nauticalDawnLocal != null ? nauticalDawnLocal.hour * 60 + nauticalDawnLocal.minute : dawnMin - 30;
          final nauticalDuskMin = nauticalDuskLocal != null ? nauticalDuskLocal.hour * 60 + nauticalDuskLocal.minute : duskMin + 30;
          final goldenHourEndMin = goldenHourEndLocal != null ? goldenHourEndLocal.hour * 60 + goldenHourEndLocal.minute : sunriseMin + 60;
          final goldenHourMin = goldenHourLocal != null ? goldenHourLocal.hour * 60 + goldenHourLocal.minute : sunsetMin - 60;

          if (timeMinutes < nauticalDawnMin) return Colors.indigo.shade900;
          if (timeMinutes >= nauticalDawnMin && timeMinutes < dawnMin) return Colors.indigo.shade700;
          if (timeMinutes >= dawnMin && timeMinutes < sunriseMin) return Colors.indigo.shade400;
          if (timeMinutes >= sunriseMin && timeMinutes < goldenHourEndMin) return Colors.orange.shade300;
          if (timeMinutes >= goldenHourEndMin && timeMinutes < goldenHourMin) return Colors.amber.shade200;
          if (timeMinutes >= goldenHourMin && timeMinutes < sunsetMin) return Colors.orange.shade300;
          if (timeMinutes >= sunsetMin && timeMinutes < duskMin) return Colors.deepOrange.shade400;
          if (timeMinutes >= duskMin && timeMinutes < nauticalDuskMin) return Colors.indigo.shade700;
          if (timeMinutes >= nauticalDuskMin) return Colors.indigo.shade900;
        }
      }
    }

    // Fallback: simplified hour-based colors - matches _computeSegmentColor fallback
    final hour = time.hour;
    if (hour >= 5 && hour < 6) return Colors.indigo.shade700;
    if (hour >= 6 && hour < 7) return Colors.indigo.shade400;
    if (hour >= 7 && hour < 8) return Colors.orange.shade300;
    if (hour >= 8 && hour < 16) return Colors.amber.shade200;
    if (hour >= 16 && hour < 17) return Colors.orange.shade400;
    if (hour >= 17 && hour < 18) return Colors.deepOrange.shade400;
    if (hour >= 18 && hour < 19) return Colors.indigo.shade700;
    return Colors.indigo.shade900;
  }

  String _getWindDirectionLabel(double degrees) {
    const directions = ['N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE',
                        'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW'];
    final index = ((degrees + 11.25) % 360 / 22.5).floor();
    return directions[index];
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

  _ForecastRimPainter({
    required this.times,
    required this.rotationAngle,
    required this.isDark,
    required this.selectedHourOffset,
    this.cachedSegmentColors,
    required this.cachedNow,
    required this.maxForecastHours,
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

    final outerMargin = 27.0 * scale;
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

    // Draw hour labels
    final textStyle = TextStyle(
      fontSize: 9 * scale,
      color: isDark ? Colors.white70 : Colors.black54,
      fontWeight: FontWeight.w500,
    );

    for (int i = 0; i < 24; i += 6) {
      final angle = -math.pi / 2 + (i * math.pi / 12);
      final labelRadius = innerRadius - 12 * scale;
      final labelCenter = Offset(
        center.dx + labelRadius * math.cos(angle),
        center.dy + labelRadius * math.sin(angle),
      );

      String labelText;
      if (i == 0) {
        final hour = cachedNow.hour;
        final minute = cachedNow.minute;
        final ampm = hour < 12 ? 'AM' : 'PM';
        final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
        labelText = '$displayHour:${minute.toString().padLeft(2, '0')} $ampm';
      } else {
        final futureTime = cachedNow.add(Duration(hours: i));
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

    String formatTime(DateTime time) {
      final local = time.toLocal();
      final hour = local.hour;
      final minute = local.minute;
      final minuteStr = minute.toString().padLeft(2, '0');
      if (hour == 0) return '12:$minuteStr AM';
      if (hour < 12) return '$hour:$minuteStr AM';
      if (hour == 12) return '12:$minuteStr PM';
      return '${hour - 12}:$minuteStr PM';
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

      final timeText = formatTime(eventTime);
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

    // Draw moon icon with phase
    void drawMoonIcon(Offset iconCenter, double angle, DateTime eventTime, bool isRise) {
      canvas.save();
      canvas.translate(iconCenter.dx, iconCenter.dy);
      canvas.rotate(-rotationAngle);

      final moonRadius = iconSize / 2 - 1 * scale;
      var phase = times!.moonPhase ?? 0.5;
      var fraction = times!.moonFraction ?? 0.5;
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
        final bool isWaxing = phase < 0.5;
        final termWidth = moonRadius * (2.0 * fraction - 1.0);
        final isGibbous = fraction > 0.5;
        final ellipseX = termWidth.abs().clamp(0.1, moonRadius - 0.1);

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
        }
      } else if (fraction >= 0.99) {
        canvas.drawCircle(Offset.zero, moonRadius, lightPaint);
      }

      // Draw arrow indicator
      final arrowPaint = Paint()
        ..color = isRise ? Colors.cyan.shade300 : Colors.blueGrey.shade400
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

      // Draw time label
      final labelRadius = outerRadius + 14 * scale;
      final labelCenter = Offset(
        center.dx + labelRadius * math.cos(angle),
        center.dy + labelRadius * math.sin(angle),
      );

      final timeText = formatTime(eventTime);
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

      // Sunrise - primary, on rim
      if (dayTimes.sunrise != null) {
        final angle = getAngleForTime(dayTimes.sunrise);
        if (angle != null) {
          final pos = Offset(center.dx + iconRadius * math.cos(angle),
                             center.dy + iconRadius * math.sin(angle));
          drawSunIcon(pos, angle, dayTimes.sunrise!, true);
        }
      }

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

      // Sunset - primary, on rim
      if (dayTimes.sunset != null) {
        final angle = getAngleForTime(dayTimes.sunset);
        if (angle != null) {
          final pos = Offset(center.dx + iconRadius * math.cos(angle),
                             center.dy + iconRadius * math.sin(angle));
          drawSunIcon(pos, angle, dayTimes.sunset!, false);
        }
      }

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

      // Moonrise - primary, on rim
      if (dayTimes.moonrise != null) {
        final angle = getAngleForTime(dayTimes.moonrise);
        if (angle != null) {
          final pos = Offset(center.dx + iconRadius * math.cos(angle),
                             center.dy + iconRadius * math.sin(angle));
          drawMoonIcon(pos, angle, dayTimes.moonrise!, true);
        }
      }

      // Moonset - primary, on rim
      if (dayTimes.moonset != null) {
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
