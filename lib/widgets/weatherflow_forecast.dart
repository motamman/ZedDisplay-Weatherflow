/// WeatherFlow Forecast Widget
/// Full-featured forecast display with hourly, daily, sun/moon arc
/// Ported from ZedDisplay with all features intact

import 'package:flutter/material.dart';
import 'forecast_models.dart';
import '../services/daylight_service.dart';
import '../utils/date_time_formatter.dart';

/// Data source for current condition values
enum ConditionDataSource {
  /// Live data from UDP (local network) - green dot
  udp,
  /// Observation data from REST/WebSocket - blue dot
  observation,
  /// Forecast data for current hour - orange dot
  forecast,
  /// No data available
  none,
}

extension ConditionDataSourceColor on ConditionDataSource {
  Color get color {
    switch (this) {
      case ConditionDataSource.udp:
        return Colors.green;
      case ConditionDataSource.observation:
        return Colors.blue;
      case ConditionDataSource.forecast:
        return Colors.orange;
      case ConditionDataSource.none:
        return Colors.grey;
    }
  }

  String get label {
    switch (this) {
      case ConditionDataSource.udp:
        return 'UDP';
      case ConditionDataSource.observation:
        return 'Live';
      case ConditionDataSource.forecast:
        return 'Forecast';
      case ConditionDataSource.none:
        return 'N/A';
    }
  }
}

/// WeatherFlow Forecast widget showing current conditions and hourly/daily forecast
class WeatherFlowForecast extends StatefulWidget {
  /// Current observations (already converted by ConversionUtils)
  final double? currentTemp;
  final double? currentHumidity;
  final double? currentPressure;
  final double? currentWindSpeed;
  final double? currentWindGust;
  final double? currentWindDirection; // degrees
  final double? rainLastHour; // precipitation in last hour
  final double? rainToday; // today's total precipitation

  /// Data sources for each condition (for source indicator dots)
  final ConditionDataSource tempSource;
  final ConditionDataSource humiditySource;
  final ConditionDataSource pressureSource;
  final ConditionDataSource windSource;
  final ConditionDataSource rainSource;

  /// Unit labels for display
  final String tempUnit;
  final String pressureUnit;
  final String windUnit;
  final String rainUnit;

  /// Hourly forecasts (up to 72 hours)
  final List<HourlyForecast> hourlyForecasts;

  /// Daily forecasts (up to 10 days)
  final List<DailyForecast> dailyForecasts;

  /// Number of hours to display
  final int hoursToShow;

  /// Number of days to display
  final int daysToShow;

  /// Primary color
  final Color primaryColor;

  /// Show current conditions section
  final bool showCurrentConditions;

  /// Sun/Moon times for arc display
  final SunMoonTimes? sunMoonTimes;

  /// Show sun/moon arc
  final bool showSunMoonArc;

  /// Show daily forecast section
  final bool showDailyForecast;

  /// Use 24-hour (military) time format instead of 12-hour AM/PM
  final bool use24HourFormat;

  /// Widget title (display name)
  final String? title;

  /// Show widget title
  final bool showTitle;

  const WeatherFlowForecast({
    super.key,
    this.currentTemp,
    this.currentHumidity,
    this.currentPressure,
    this.currentWindSpeed,
    this.currentWindGust,
    this.currentWindDirection,
    this.rainLastHour,
    this.rainToday,
    this.tempSource = ConditionDataSource.none,
    this.humiditySource = ConditionDataSource.none,
    this.pressureSource = ConditionDataSource.none,
    this.windSource = ConditionDataSource.none,
    this.rainSource = ConditionDataSource.none,
    this.tempUnit = '°C',
    this.pressureUnit = 'hPa',
    this.windUnit = 'kts',
    this.rainUnit = 'mm',
    this.hourlyForecasts = const [],
    this.dailyForecasts = const [],
    this.hoursToShow = 12,
    this.daysToShow = 7,
    this.primaryColor = Colors.blue,
    this.showCurrentConditions = true,
    this.sunMoonTimes,
    this.showSunMoonArc = true,
    this.showDailyForecast = true,
    this.use24HourFormat = false,
    this.title,
    this.showTitle = true,
  });

  @override
  State<WeatherFlowForecast> createState() => _WeatherFlowForecastState();
}

class _WeatherFlowForecastState extends State<WeatherFlowForecast> {
  /// Currently expanded day index (null = none expanded, shows today's arc)
  int? _expandedDayIndex;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Use scrollable layout in landscape or when space is tight
            final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
            final useScroll = isLandscape || constraints.maxHeight < 300;

            final content = Column(
              mainAxisSize: useScroll ? MainAxisSize.min : MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header (title)
                if (widget.showTitle) ...[
                  _buildHeader(context),
                  const SizedBox(height: 8),
                ],

                // Sun/Moon arc (beneath header, above current conditions)
                // Shows selected day if expanded, otherwise today
                if (widget.showSunMoonArc && widget.sunMoonTimes != null) ...[
                  _SunMoonArc(
                    times: widget.sunMoonTimes!,
                    isDark: isDark,
                    use24HourFormat: widget.use24HourFormat,
                    selectedDayIndex: _expandedDayIndex,
                  ),
                  const SizedBox(height: 8),
                ],

                // Current conditions
                if (widget.showCurrentConditions) ...[
                  _buildCurrentConditions(context, isDark),
                  const SizedBox(height: 6),
                  Divider(color: isDark ? Colors.white24 : Colors.black12),
                  const SizedBox(height: 4),
                ],

                // Daily forecast with accordion hourly expansion
                if (widget.showDailyForecast) ...[
                  if (useScroll)
                    _buildDailyForecast(context, isDark, shrinkWrap: true)
                  else
                    Expanded(
                      child: _buildDailyForecast(context, isDark, shrinkWrap: false),
                    ),
                ],
              ],
            );

            if (useScroll) {
              return SingleChildScrollView(child: content);
            }
            return content;
          },
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    // Use custom title if provided, otherwise default
    final displayTitle = widget.title?.isNotEmpty == true
        ? widget.title!
        : 'WeatherFlow Forecast';

    return Row(
      children: [
        Icon(
          Icons.cloud,
          color: widget.primaryColor,
          size: 20,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            displayTitle,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildCurrentConditions(BuildContext context, bool isDark) {
    // Format rain display: "1h / today" or just one if other is null/zero
    String rainDisplay = '--';
    if (widget.rainLastHour != null || widget.rainToday != null) {
      final lastHour = widget.rainLastHour ?? 0;
      final today = widget.rainToday ?? 0;
      if (lastHour > 0 || today > 0) {
        rainDisplay = '${lastHour.toStringAsFixed(1)}/${today.toStringAsFixed(1)}';
      } else {
        rainDisplay = '0';
      }
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildConditionItem(
          context,
          Icons.thermostat,
          widget.currentTemp != null ? '${widget.currentTemp!.toStringAsFixed(1)}${widget.tempUnit}' : '--',
          'Temp',
          Colors.orange,
          isDark,
          widget.tempSource,
        ),
        _buildConditionItem(
          context,
          Icons.water_drop,
          widget.currentHumidity != null ? '${widget.currentHumidity!.toStringAsFixed(0)}%' : '--',
          'Humidity',
          Colors.cyan,
          isDark,
          widget.humiditySource,
        ),
        _buildConditionItem(
          context,
          Icons.umbrella,
          rainDisplay,
          '${widget.rainUnit} 1h/day',
          Colors.blue,
          isDark,
          widget.rainSource,
        ),
        _buildConditionItem(
          context,
          Icons.speed,
          widget.currentPressure != null ? widget.currentPressure!.toStringAsFixed(0) : '--',
          widget.pressureUnit,
          Colors.purple,
          isDark,
          widget.pressureSource,
        ),
        _buildConditionItem(
          context,
          Icons.air,
          widget.currentWindSpeed != null
              ? (widget.currentWindGust != null
                  ? '${widget.currentWindSpeed!.toStringAsFixed(1)}/${widget.currentWindGust!.toStringAsFixed(0)}'
                  : widget.currentWindSpeed!.toStringAsFixed(1))
              : '--',
          widget.windUnit,
          Colors.teal,
          isDark,
          widget.windSource,
          subtitle2: widget.currentWindDirection != null ? _getWindDirectionLabel(widget.currentWindDirection!) : null,
        ),
      ],
    );
  }

  Widget _buildConditionItem(
    BuildContext context,
    IconData icon,
    String value,
    String label,
    Color color,
    bool isDark,
    ConditionDataSource source, {
    String? subtitle2,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 20),
        // Data source indicator dot
        if (source != ConditionDataSource.none)
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              color: source.color,
              shape: BoxShape.circle,
            ),
          ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: isDark ? Colors.white60 : Colors.black45,
          ),
        ),
        if (subtitle2 != null)
          Text(
            subtitle2,
            style: TextStyle(
              fontSize: 10,
              color: isDark ? Colors.white60 : Colors.black45,
            ),
          ),
      ],
    );
  }

  String _getWindDirectionLabel(double degrees) {
    const directions = ['N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE',
                        'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW'];
    final index = ((degrees + 11.25) % 360 / 22.5).floor();
    return directions[index];
  }

  Widget _buildDailyForecast(BuildContext context, bool isDark, {bool shrinkWrap = false}) {
    if (widget.dailyForecasts.isEmpty) {
      return Center(
        child: Text(
          'No daily forecast data available',
          style: TextStyle(
            color: isDark ? Colors.white54 : Colors.black45,
          ),
        ),
      );
    }

    final forecasts = widget.dailyForecasts.take(widget.daysToShow).toList();

    return ListView.builder(
      scrollDirection: Axis.vertical,
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      itemCount: forecasts.length,
      itemBuilder: (context, index) {
        final forecast = forecasts[index];
        final isExpanded = _expandedDayIndex == index;

        // Get hourly forecasts for this day
        final dayHourlyForecasts = _getHourlyForecastsForDay(forecast.date);

        return _buildDayCard(
          context,
          forecast,
          isDark,
          isExpanded: isExpanded,
          hourlyForecasts: dayHourlyForecasts,
          onTap: () {
            setState(() {
              // Toggle: if already expanded, collapse; otherwise expand this day
              _expandedDayIndex = isExpanded ? null : index;
            });
          },
        );
      },
    );
  }

  /// Get hourly forecasts that fall on a specific day
  List<HourlyForecast> _getHourlyForecastsForDay(DateTime? date) {
    if (date == null) return [];

    return widget.hourlyForecasts.where((h) {
      if (h.time == null) return false;
      return h.time!.year == date.year &&
             h.time!.month == date.month &&
             h.time!.day == date.day;
    }).toList();
  }

  Widget _buildDayCard(
    BuildContext context,
    DailyForecast forecast,
    bool isDark, {
    bool isExpanded = false,
    List<HourlyForecast> hourlyForecasts = const [],
    VoidCallback? onTap,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Day header (clickable)
        GestureDetector(
          onTap: onTap,
          child: Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            decoration: BoxDecoration(
              color: isExpanded
                  ? (isDark ? widget.primaryColor.withValues(alpha: 0.2) : widget.primaryColor.withValues(alpha: 0.1))
                  : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03)),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isExpanded
                    ? widget.primaryColor.withValues(alpha: 0.5)
                    : (isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.1)),
              ),
            ),
            child: Row(
              children: [
                // Expand/collapse indicator
                Icon(
                  isExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: isDark ? Colors.white54 : Colors.black45,
                ),
                const SizedBox(width: 4),
                // Day name
                SizedBox(
                  width: 55,
                  child: Text(
                    forecast.dayName,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                ),
                // Weather icon
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Icon(
                    forecast.fallbackIcon,
                    color: _getWeatherIconColor(forecast.icon),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 8),
                // Conditions
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        forecast.conditions ?? '',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white60 : Colors.black45,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      // Sunrise/Sunset times
                      if (forecast.sunrise != null || forecast.sunset != null)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (forecast.sunrise != null) ...[
                              Icon(Icons.wb_sunny, size: 9, color: Colors.amber.shade400),
                              const SizedBox(width: 2),
                              Text(
                                DateTimeFormatter.formatTime(
                                  widget.sunMoonTimes?.toLocationTime(forecast.sunrise!) ?? forecast.sunrise!.toLocal(),
                                  use24Hour: widget.use24HourFormat,
                                ),
                                style: TextStyle(fontSize: 9, color: isDark ? Colors.white38 : Colors.black38),
                              ),
                            ],
                            if (forecast.sunrise != null && forecast.sunset != null)
                              const SizedBox(width: 6),
                            if (forecast.sunset != null) ...[
                              Icon(Icons.nights_stay, size: 9, color: Colors.indigo.shade300),
                              const SizedBox(width: 2),
                              Text(
                                DateTimeFormatter.formatTime(
                                  widget.sunMoonTimes?.toLocationTime(forecast.sunset!) ?? forecast.sunset!.toLocal(),
                                  use24Hour: widget.use24HourFormat,
                                ),
                                style: TextStyle(fontSize: 9, color: isDark ? Colors.white38 : Colors.black38),
                              ),
                            ],
                          ],
                        ),
                    ],
                  ),
                ),
                // Precip probability
                if (forecast.precipProbability != null && forecast.precipProbability! > 0)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.water_drop,
                          size: 10,
                          color: Colors.blue.shade300,
                        ),
                        Text(
                          '${forecast.precipProbability!.toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.blue.shade300,
                          ),
                        ),
                      ],
                    ),
                  ),
                // High/Low temps
                SizedBox(
                  width: 80,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        forecast.tempHigh != null ? '${forecast.tempHigh!.toStringAsFixed(0)}${widget.tempUnit}' : '--',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      Text(
                        '/',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white38 : Colors.black26,
                        ),
                      ),
                      Text(
                        forecast.tempLow != null ? '${forecast.tempLow!.toStringAsFixed(0)}${widget.tempUnit}' : '--',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white54 : Colors.black45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // Expanded hourly forecast
        if (isExpanded) ...[
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: hourlyForecasts.isNotEmpty ? 100 : 40,
            margin: const EdgeInsets.only(bottom: 8, left: 8, right: 8),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.03)
                  : Colors.black.withValues(alpha: 0.02),
              borderRadius: BorderRadius.circular(6),
            ),
            child: hourlyForecasts.isNotEmpty
                ? _buildHourlyRow(hourlyForecasts, isDark)
                : Center(
                    child: Text(
                      'No hourly data for this day',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                    ),
                  ),
          ),
        ],
      ],
    );
  }

  /// Build horizontal scrolling row of hourly forecasts
  Widget _buildHourlyRow(List<HourlyForecast> forecasts, bool isDark) {
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      itemCount: forecasts.length,
      itemBuilder: (context, index) {
        return _buildHourCard(context, forecasts[index], isDark);
      },
    );
  }

  Widget _buildHourCard(BuildContext context, HourlyForecast forecast, bool isDark) {
    final temp = forecast.temperature;
    final precipProb = forecast.precipProbability;
    final windSpeed = forecast.windSpeed;
    final windDir = forecast.windDirection;

    // Calculate hour label with day abbreviation if different day
    final now = DateTime.now();
    final forecastTime = now.add(Duration(hours: forecast.hour));
    final isToday = forecastTime.day == now.day && forecastTime.month == now.month;
    final dayAbbrev = DateTimeFormatter.getDayAbbrev(forecastTime);
    final timeStr = DateTimeFormatter.formatTime(forecastTime, use24Hour: widget.use24HourFormat, includeMinutes: false);
    final hourLabel = forecast.hour == 0
        ? 'Now'
        : isToday
            ? timeStr
            : '$dayAbbrev $timeStr';

    return Container(
      width: 58,
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 3),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.black.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Hour - fixed at top
          Text(
            hourLabel,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const Spacer(),
          // Wind direction arrow + speed combined
          if (windDir != null || windSpeed != null)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (windDir != null)
                  Transform.rotate(
                    angle: (windDir + 180) * 3.14159 / 180,
                    child: Icon(
                      Icons.navigation,
                      size: 12,
                      color: Colors.teal.shade300,
                    ),
                  ),
                if (windSpeed != null)
                  Text(
                    windSpeed.toStringAsFixed(0),
                    style: TextStyle(
                      fontSize: 9,
                      color: Colors.teal.shade300,
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 2),
          // Weather icon
          Expanded(
            flex: 2,
            child: Center(
              child: Icon(
                forecast.fallbackIcon,
                color: _getWeatherIconColor(forecast.icon),
                size: 24,
              ),
            ),
          ),
          const SizedBox(height: 2),
          // Temperature
          Text(
            temp != null ? '${temp.toStringAsFixed(0)}${widget.tempUnit}' : '--',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          // Precipitation probability
          if (precipProb != null && precipProb > 0)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.water_drop,
                  size: 8,
                  color: Colors.blue.shade300,
                ),
                Text(
                  precipProb.toStringAsFixed(0),
                  style: TextStyle(
                    fontSize: 9,
                    color: Colors.blue.shade300,
                  ),
                ),
              ],
            ),
          const Spacer(),
        ],
      ),
    );
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

/// Sun/Moon arc widget showing day progression
class _SunMoonArc extends StatelessWidget {
  final SunMoonTimes times;
  final bool isDark;
  final bool use24HourFormat;
  final int? selectedDayIndex; // null = today, 0 = first day, etc.

  const _SunMoonArc({
    required this.times,
    required this.isDark,
    this.use24HourFormat = false,
    this.selectedDayIndex,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().toUtc();

    // Calculate the center time for the arc
    // Today (selectedDayIndex == null or 0) centers on current time
    // Future days center on solar noon
    DateTime arcCenter;
    bool showNoonIndicator = false;

    if (selectedDayIndex != null && selectedDayIndex! > 0) {
      // Future day selected - center on noon
      final dayIndex = selectedDayIndex! + times.todayIndex;
      if (dayIndex >= 0 && dayIndex < times.days.length) {
        final selectedDay = times.days[dayIndex];
        // Use solar noon if available, otherwise estimate noon
        arcCenter = selectedDay.solarNoon ??
            DateTime(now.year, now.month, now.day + selectedDayIndex!, 12, 0).toUtc();
      } else {
        arcCenter = now;
      }
      showNoonIndicator = true;
    } else {
      // Today or no selection - center on current time
      arcCenter = now;
    }

    return SizedBox(
      height: 70,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return CustomPaint(
            size: Size(constraints.maxWidth, constraints.maxHeight),
            painter: _SunMoonArcPainter(
              times: times,
              now: arcCenter,
              isDark: isDark,
              use24HourFormat: use24HourFormat,
              isSelectedDay: showNoonIndicator,
            ),
            child: _buildIconsOverlay(constraints, arcCenter, showNoonIndicator),
          );
        },
      ),
    );
  }

  Widget _buildIconsOverlay(BoxConstraints constraints, DateTime now, bool isSelectedDay) {
    final width = constraints.maxWidth;
    final height = constraints.maxHeight;

    // Center arc on "now" with 12 hours before and after
    final arcStart = now.subtract(const Duration(hours: 12));
    final arcEnd = now.add(const Duration(hours: 12));
    const arcDuration = 1440; // 24 hours in minutes

    final children = <Widget>[];

    // Helper to calculate position on arc (for markers like sunrise/sunset)
    (double x, double y)? getArcPosition(DateTime time, {double size = 16}) {
      final minutesFromStart = time.difference(arcStart).inMinutes;
      final progress = minutesFromStart / arcDuration;
      if (progress < 0 || progress > 1) return null;

      final xPercent = 0.05 + progress * 0.9;
      final normalizedX = (progress - 0.5) * 2;
      final yPercent = 0.15 + (1 - normalizedX * normalizedX) * 0.5;

      final x = width * xPercent - size / 2;
      final y = height * (1 - yPercent) - size / 2;
      return (x, y);
    }

    // Add sunrise/sunset/solar noon and moon markers for all days within arc range
    for (final day in times.days) {
      // Sunrise marker
      if (day.sunrise != null && day.sunrise!.isAfter(arcStart) && day.sunrise!.isBefore(arcEnd)) {
        final sunrisePos = getArcPosition(day.sunrise!, size: 20);
        if (sunrisePos != null) {
          children.add(
            Positioned(
              left: sunrisePos.$1,
              top: sunrisePos.$2,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.arrow_upward,
                    color: Colors.amber.shade600,
                    size: 10,
                  ),
                  const Icon(Icons.wb_sunny, color: Colors.amber, size: 16),
                ],
              ),
            ),
          );
        }
      }

      // Sunset marker
      if (day.sunset != null && day.sunset!.isAfter(arcStart) && day.sunset!.isBefore(arcEnd)) {
        final sunsetPos = getArcPosition(day.sunset!, size: 20);
        if (sunsetPos != null) {
          children.add(
            Positioned(
              left: sunsetPos.$1,
              top: sunsetPos.$2 - 10,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.wb_sunny, color: Colors.deepOrange, size: 16),
                  Icon(
                    Icons.arrow_downward,
                    color: Colors.deepOrange.shade600,
                    size: 10,
                  ),
                ],
              ),
            ),
          );
        }
      }

      // Solar noon marker (sun at max height)
      if (day.solarNoon != null && day.solarNoon!.isAfter(arcStart) && day.solarNoon!.isBefore(arcEnd)) {
        final noonPos = getArcPosition(day.solarNoon!, size: 24);
        if (noonPos != null) {
          children.add(
            Positioned(
              left: noonPos.$1,
              top: noonPos.$2 - 8, // Slightly higher to show it's at peak
              child: const Icon(Icons.wb_sunny, color: Colors.amber, size: 24),
            ),
          );
        }
      }

      // Moonrise marker - use per-day moon phase
      if (day.moonrise != null && day.moonrise!.isAfter(arcStart) && day.moonrise!.isBefore(arcEnd)) {
        final moonrisePos = getArcPosition(day.moonrise!, size: 20);
        if (moonrisePos != null) {
          children.add(
            Positioned(
              left: moonrisePos.$1,
              top: moonrisePos.$2,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.arrow_upward,
                    color: Colors.blueGrey.shade300,
                    size: 8,
                  ),
                  _buildMoonIcon(day.moonPhase, day.moonFraction, size: 14),
                ],
              ),
            ),
          );
        }
      }

      // Moonset marker - use per-day moon phase
      if (day.moonset != null && day.moonset!.isAfter(arcStart) && day.moonset!.isBefore(arcEnd)) {
        final moonsetPos = getArcPosition(day.moonset!, size: 20);
        if (moonsetPos != null) {
          children.add(
            Positioned(
              left: moonsetPos.$1,
              top: moonsetPos.$2 - 8,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildMoonIcon(day.moonPhase, day.moonFraction, size: 14),
                  Icon(
                    Icons.arrow_downward,
                    color: Colors.blueGrey.shade400,
                    size: 8,
                  ),
                ],
              ),
            ),
          );
        }
      }

      // Moon max height (lunar transit - midpoint between moonrise and moonset)
      if (day.moonrise != null && day.moonset != null) {
        // Calculate lunar transit (moon at max height)
        DateTime lunarTransit;
        if (day.moonset!.isAfter(day.moonrise!)) {
          // Normal case: moonrise before moonset on same day
          final midpoint = day.moonrise!.add(
            Duration(minutes: day.moonset!.difference(day.moonrise!).inMinutes ~/ 2),
          );
          lunarTransit = midpoint;
        } else {
          // Moonset is next day - transit is ~12 hours from moonrise
          lunarTransit = day.moonrise!.add(const Duration(hours: 6));
        }

        if (lunarTransit.isAfter(arcStart) && lunarTransit.isBefore(arcEnd)) {
          final transitPos = getArcPosition(lunarTransit, size: 20);
          if (transitPos != null) {
            children.add(
              Positioned(
                left: transitPos.$1,
                top: transitPos.$2 - 6, // Slightly higher to show it's at peak
                child: _buildMoonIcon(day.moonPhase, day.moonFraction, size: 20),
              ),
            );
          }
        }
      }
    }

    // Center indicator - "now" for today, "noon" for selected day
    final nowX = width * 0.5;
    final baseY = height - 10;
    final indicatorColor = isSelectedDay ? Colors.amber : Colors.red;
    final indicatorLabel = isSelectedDay ? 'noon' : 'now';
    children.add(
      Positioned(
        left: nowX - 12,
        top: baseY - 20,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              indicatorLabel,
              style: TextStyle(
                fontSize: 8,
                color: indicatorColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            Container(
              width: 2,
              height: 10,
              color: indicatorColor,
            ),
          ],
        ),
      ),
    );

    return Stack(clipBehavior: Clip.hardEdge, children: children);
  }

  Widget _buildMoonIcon(double? phase, double? fraction, {double size = 16}) {
    return CustomPaint(
      size: Size(size, size),
      painter: _MoonPhasePainter(
        phase: phase ?? 0.5,
        fraction: fraction ?? 0.5,
        isSouthernHemisphere: times.isSouthernHemisphere,
      ),
    );
  }
}

/// Custom painter for moon phase showing illumination
/// Handles both Northern and Southern hemisphere orientations
class _MoonPhasePainter extends CustomPainter {
  final double phase;
  final double fraction;
  final bool isSouthernHemisphere;

  _MoonPhasePainter({
    required this.phase,
    required this.fraction,
    this.isSouthernHemisphere = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 1;

    // Draw the dark side of the moon (background)
    final darkPaint = Paint()
      ..color = Colors.grey.shade800
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, darkPaint);

    // Draw the illuminated side
    final lightPaint = Paint()
      ..color = Colors.grey.shade200
      ..style = PaintingStyle.fill;

    if (fraction < 0.01) {
      return;
    } else if (fraction > 0.99) {
      canvas.drawCircle(center, radius, lightPaint);
      return;
    }

    // Determine waxing/waning - flip for Southern Hemisphere
    bool isWaxing = phase < 0.5;
    if (isSouthernHemisphere) {
      isWaxing = !isWaxing; // Moon appears flipped in Southern Hemisphere
    }

    final termWidth = radius * (2.0 * fraction - 1.0);
    final isGibbous = fraction > 0.5;

    final path = Path();

    if (isWaxing) {
      path.moveTo(center.dx, center.dy - radius);
      path.arcToPoint(
        Offset(center.dx, center.dy + radius),
        radius: Radius.circular(radius),
        clockwise: true,
      );
      path.arcToPoint(
        Offset(center.dx, center.dy - radius),
        radius: Radius.elliptical(termWidth.abs().clamp(0.1, radius), radius),
        clockwise: isGibbous,
      );
    } else {
      path.moveTo(center.dx, center.dy - radius);
      path.arcToPoint(
        Offset(center.dx, center.dy + radius),
        radius: Radius.circular(radius),
        clockwise: false,
      );
      path.arcToPoint(
        Offset(center.dx, center.dy - radius),
        radius: Radius.elliptical(termWidth.abs().clamp(0.1, radius), radius),
        clockwise: !isGibbous,
      );
    }

    path.close();
    canvas.drawPath(path, lightPaint);

    // Draw outline
    final outlinePaint = Paint()
      ..color = Colors.grey.shade400
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    canvas.drawCircle(center, radius, outlinePaint);
  }

  @override
  bool shouldRepaint(covariant _MoonPhasePainter oldDelegate) {
    return oldDelegate.phase != phase ||
           oldDelegate.fraction != fraction ||
           oldDelegate.isSouthernHemisphere != isSouthernHemisphere;
  }
}

/// Custom painter for the sun/moon arc
class _SunMoonArcPainter extends CustomPainter {
  final SunMoonTimes times;
  final DateTime now;
  final bool isDark;
  final bool use24HourFormat;
  final bool isSelectedDay;

  _SunMoonArcPainter({
    required this.times,
    required this.now,
    required this.isDark,
    this.use24HourFormat = false,
    this.isSelectedDay = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final arcStart = now.subtract(const Duration(hours: 12));
    final arcEnd = now.add(const Duration(hours: 12));
    const arcDuration = 1440.0;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final segments = <_ArcSegment>[];

    void addSegment(DateTime? start, DateTime? end, Color color) {
      if (start == null || end == null) return;
      if (end.isBefore(arcStart) || start.isAfter(arcEnd)) return;
      segments.add(_ArcSegment(start, end, color));
    }

    // Add segments for each available day (handles arc spanning midnight)
    // Uses DaylightService colors for consistency with forecast spinner
    for (final day in times.days) {
      // Night before dawn
      if (day.nauticalDawn != null) {
        final nightStart = day.nauticalDawn!.subtract(const Duration(hours: 6));
        addSegment(nightStart, day.nauticalDawn,
            DaylightService.periodColors[DaylightPeriod.night]!.withValues(alpha: 0.5));
      }
      // Nautical twilight (dawn)
      addSegment(day.nauticalDawn, day.dawn,
          DaylightService.periodColors[DaylightPeriod.nauticalTwilight]!);
      // Civil twilight (dawn)
      addSegment(day.dawn, day.sunrise,
          DaylightService.periodColors[DaylightPeriod.civilTwilight]!);
      // Golden hour (morning)
      addSegment(day.sunrise, day.goldenHourEnd,
          DaylightService.periodColors[DaylightPeriod.goldenHour]!);
      // Daytime (morning to noon)
      addSegment(day.goldenHourEnd, day.solarNoon,
          DaylightService.periodColors[DaylightPeriod.daylight]!);
      // Daytime (noon to afternoon)
      addSegment(day.solarNoon, day.goldenHour,
          DaylightService.periodColors[DaylightPeriod.daylight]!);
      // Golden hour (evening)
      addSegment(day.goldenHour, day.sunset,
          DaylightService.eveningColors[DaylightPeriod.goldenHour]!);
      // Civil twilight (dusk)
      addSegment(day.sunset, day.dusk,
          DaylightService.eveningColors[DaylightPeriod.civilTwilight]!);
      // Nautical twilight (dusk)
      addSegment(day.dusk, day.nauticalDusk,
          DaylightService.periodColors[DaylightPeriod.nauticalTwilight]!);
      // Night after dusk
      if (day.nauticalDusk != null) {
        final nightEnd = day.nauticalDusk!.add(const Duration(hours: 6));
        addSegment(day.nauticalDusk, nightEnd,
            DaylightService.periodColors[DaylightPeriod.night]!.withValues(alpha: 0.5));
      }
    }

    // Draw baseline
    final baseY = size.height - 10;
    canvas.drawLine(
      Offset(size.width * 0.05, baseY),
      Offset(size.width * 0.95, baseY),
      Paint()
        ..color = isDark ? Colors.white24 : Colors.black12
        ..strokeWidth = 1,
    );

    // Draw arc segments
    for (final segment in segments) {
      final startProgress = segment.start.difference(arcStart).inMinutes / arcDuration;
      final endProgress = segment.end.difference(arcStart).inMinutes / arcDuration;

      if (startProgress >= 1 || endProgress <= 0) continue;

      final clampedStart = startProgress.clamp(0.0, 1.0);
      final clampedEnd = endProgress.clamp(0.0, 1.0);

      paint.color = segment.color;
      _drawArcSegment(canvas, size, clampedStart, clampedEnd, paint, baseY);
    }

    // Draw time labels
    _drawTimeLabels(canvas, size, arcStart, baseY);
  }

  void _drawArcSegment(Canvas canvas, Size size, double startProgress, double endProgress, Paint paint, double baseY) {
    final path = Path();
    const steps = 20;

    for (int i = 0; i <= steps; i++) {
      final t = startProgress + (endProgress - startProgress) * (i / steps);
      final x = size.width * (0.05 + t * 0.9);
      final normalizedX = (t - 0.5) * 2;
      final arcHeight = (size.height - 20) * 0.7;
      final y = baseY - (1 - normalizedX * normalizedX) * arcHeight;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);
  }

  void _drawTimeLabels(Canvas canvas, Size size, DateTime arcStart, double baseY) {
    final neutralColor = isDark ? Colors.white54 : Colors.black45;

    void drawLabel(double progress, String text, Color color) {
      if (progress < 0 || progress > 1) return;
      final x = size.width * (0.05 + progress * 0.9);
      final textSpan = TextSpan(
        text: text,
        style: TextStyle(fontSize: 8, color: color, fontWeight: FontWeight.w500),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(x - textPainter.width / 2, baseY + 2));
    }

    // Show actual times in location's timezone (not device local time)
    final startTime = times.toLocationTime(arcStart);
    final endTime = times.toLocationTime(arcStart.add(const Duration(hours: 24)));
    drawLabel(0.0, DateTimeFormatter.formatTime(startTime, use24Hour: use24HourFormat, includeMinutes: false), neutralColor);
    drawLabel(1.0, DateTimeFormatter.formatTime(endTime, use24Hour: use24HourFormat, includeMinutes: false), neutralColor);

    if (times.sunrise != null) {
      final progress = times.sunrise!.difference(arcStart).inMinutes / 1440.0;
      if (progress >= 0 && progress <= 1) {
        final local = times.toLocationTime(times.sunrise!);
        drawLabel(progress, DateTimeFormatter.formatTime(local, use24Hour: use24HourFormat), Colors.amber);
      }
    }

    if (times.sunset != null) {
      final progress = times.sunset!.difference(arcStart).inMinutes / 1440.0;
      if (progress >= 0 && progress <= 1) {
        final local = times.toLocationTime(times.sunset!);
        drawLabel(progress, DateTimeFormatter.formatTime(local, use24Hour: use24HourFormat), Colors.deepOrange);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SunMoonArcPainter oldDelegate) {
    return oldDelegate.now.minute != now.minute ||
           oldDelegate.use24HourFormat != use24HourFormat;
  }
}

class _ArcSegment {
  final DateTime start;
  final DateTime end;
  final Color color;

  _ArcSegment(this.start, this.end, this.color);
}

