/// Solar Radiation Widget
/// Shows solar energy potential and panel output forecast
/// Ported from ZedDisplay-OpenMeteo

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:weatherflow_core/weatherflow_core.dart' hide HourlyForecast, DailyForecast;
import 'forecast_models.dart';
import '../services/solar_calculation_service.dart';

/// Configuration for the SolarRadiation widget
class SolarRadiationConfig {
  final bool showBarChart;
  final bool showDailyTotal;
  final bool showCurrentPower;
  final bool showDailyView;
  final String dailyViewMode; // 'chart' or 'cards'
  final Color? primaryColor;

  const SolarRadiationConfig({
    this.showBarChart = true,
    this.showDailyTotal = true,
    this.showCurrentPower = true,
    this.showDailyView = true,
    this.dailyViewMode = 'cards',
    this.primaryColor,
  });
}

/// Solar radiation widget showing energy potential and hourly/daily charts
class SolarRadiationWidget extends StatefulWidget {
  final List<HourlyForecast> hourlyForecasts;
  final List<DailyForecast>? dailyForecasts;
  final SunMoonTimes? sunMoonTimes;
  final double panelMaxWatts;
  final double systemDerate;
  final ConversionService? conversions;
  final SolarRadiationConfig config;
  final bool? isDark;

  const SolarRadiationWidget({
    super.key,
    required this.hourlyForecasts,
    this.dailyForecasts,
    this.sunMoonTimes,
    required this.panelMaxWatts,
    this.systemDerate = 0.85,
    this.conversions,
    this.config = const SolarRadiationConfig(),
    this.isDark,
  });

  @override
  State<SolarRadiationWidget> createState() => _SolarRadiationWidgetState();
}

class _SolarRadiationWidgetState extends State<SolarRadiationWidget> {
  DateTime? _selectedDate;

  @override
  void initState() {
    super.initState();
    // Default to today
    final now = DateTime.now();
    final locationNow = widget.sunMoonTimes?.toLocationTime(now) ?? now;
    _selectedDate = DateTime(locationNow.year, locationNow.month, locationNow.day);
  }

  @override
  Widget build(BuildContext context) {
    final effectiveIsDark = widget.isDark ?? Theme.of(context).brightness == Brightness.dark;
    final primaryColor = widget.config.primaryColor ?? Colors.orange;

    // Get current hour's data (for "Now" display when viewing today)
    final currentOutput = SolarCalculationService.getOutputAtOffset(
      hourlyForecasts: widget.hourlyForecasts,
      hourOffset: 0,
      maxWatts: widget.panelMaxWatts,
      systemDerate: widget.systemDerate,
    );

    // Get hourly power for selected date
    final now = DateTime.now();
    final locationNow = widget.sunMoonTimes?.toLocationTime(now) ?? now;
    final today = DateTime(locationNow.year, locationNow.month, locationNow.day);
    final isToday = _selectedDate?.year == today.year &&
        _selectedDate?.month == today.month &&
        _selectedDate?.day == today.day;

    final hourlyPower = _selectedDate != null
        ? SolarCalculationService.getHourlyPowerForDate(
            hourlyForecasts: widget.hourlyForecasts,
            date: _selectedDate!,
            maxWatts: widget.panelMaxWatts,
            systemDerate: widget.systemDerate,
            sunMoonTimes: widget.sunMoonTimes,
            includeAllHours: isToday,
          )
        : SolarCalculationService.getHourlyPowerForecast(
            hourlyForecasts: widget.hourlyForecasts,
            maxWatts: widget.panelMaxWatts,
            systemDerate: widget.systemDerate,
            sunMoonTimes: widget.sunMoonTimes,
            hoursToShow: 24,
          );

    // Get daily summaries for daily view
    final dailySummaries = SolarCalculationService.getDailySummaries(
      hourlyForecasts: widget.hourlyForecasts,
      maxWatts: widget.panelMaxWatts,
      systemDerate: widget.systemDerate,
      sunMoonTimes: widget.sunMoonTimes,
      maxDays: 7,
    );

    // Find selected day's summary for header display
    final selectedDaySummary = _selectedDate != null
        ? dailySummaries.where((d) =>
            d.date.year == _selectedDate!.year &&
            d.date.month == _selectedDate!.month &&
            d.date.day == _selectedDate!.day).firstOrNull
        : dailySummaries.isNotEmpty ? dailySummaries.first : null;

    final selectedDayKwh = selectedDaySummary?.kWh ?? 0.0;
    final selectedDayLabel = _selectedDate != null ? _getDayName(_selectedDate!) : 'Today';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Daily total and current power header
        if (widget.config.showDailyTotal || widget.config.showCurrentPower)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.config.showDailyTotal)
                  Row(
                    children: [
                      Icon(
                        Icons.wb_sunny,
                        color: primaryColor,
                        size: 20,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$selectedDayLabel: ${_formatKwh(selectedDayKwh)} estimated',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: effectiveIsDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                // Only show "Now" power when viewing today
                if (widget.config.showCurrentPower && currentOutput != null && isToday) ...[
                  const SizedBox(height: 4),
                  _buildCurrentPowerRow(currentOutput, effectiveIsDark),
                ],
                // Show peak power for future days
                if (widget.config.showCurrentPower && !isToday && selectedDaySummary != null) ...[
                  const SizedBox(height: 4),
                  _buildPeakPowerRow(selectedDaySummary, effectiveIsDark),
                ],
              ],
            ),
          ),

        // Hourly chart
        if (widget.config.showBarChart && hourlyPower.isNotEmpty)
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: _buildHourlyChart(hourlyPower, effectiveIsDark, primaryColor),
            ),
          )
        else if (!widget.config.showBarChart)
          const Spacer(),

        // Daily view
        if (widget.config.showDailyView && dailySummaries.isNotEmpty)
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: widget.config.dailyViewMode == 'cards'
                  ? _buildDailyCards(dailySummaries, effectiveIsDark, primaryColor)
                  : _buildDailyChart(dailySummaries, effectiveIsDark, primaryColor),
            ),
          ),
      ],
    );
  }

  Widget _buildCurrentPowerRow(
    ({double irradiance, double watts}) output,
    bool isDark,
  ) {
    final label = SolarCalculationService.getRadiationLabel(output.irradiance);
    final color = SolarCalculationService.getRadiationColor(output.irradiance);

    return Row(
      children: [
        Icon(
          Icons.electric_bolt,
          color: color,
          size: 18,
        ),
        const SizedBox(width: 6),
        Text(
          'Now: ${_formatPower(output.watts)}',
          style: TextStyle(
            fontSize: 14,
            color: isDark ? Colors.white70 : Colors.black54,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPeakPowerRow(
    ({DateTime date, double kWh, double peakWatts, DateTime? peakTime}) summary,
    bool isDark,
  ) {
    final color = SolarCalculationService.getRadiationColor(
      summary.peakWatts / (widget.panelMaxWatts * widget.systemDerate) * 1000,
    );

    final peakTimeStr = summary.peakTime != null
        ? _formatHour(summary.peakTime!)
        : '';

    return Row(
      children: [
        Icon(
          Icons.trending_up,
          color: color,
          size: 18,
        ),
        const SizedBox(width: 6),
        Text(
          'Peak: ${_formatPower(summary.peakWatts)}',
          style: TextStyle(
            fontSize: 14,
            color: isDark ? Colors.white70 : Colors.black54,
          ),
        ),
        if (peakTimeStr.isNotEmpty) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '@ $peakTimeStr',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildHourlyChart(
    List<({DateTime time, double watts, double irradiance})> hourlyPower,
    bool isDark,
    Color primaryColor,
  ) {
    if (hourlyPower.isEmpty) {
      return Center(
        child: Text(
          'No solar data available',
          style: TextStyle(
            color: isDark ? Colors.white38 : Colors.black26,
          ),
        ),
      );
    }

    // Find max values for scaling
    final maxWatts = hourlyPower.map((h) => h.watts).reduce(math.max);
    final maxIrradiance = hourlyPower.map((h) => h.irradiance).reduce(math.max);

    // Prepare spots for both lines
    final powerSpots = <FlSpot>[];
    final irradianceSpots = <FlSpot>[];

    for (int i = 0; i < hourlyPower.length; i++) {
      final h = hourlyPower[i];
      powerSpots.add(FlSpot(h.time.hour.toDouble(), h.watts));
      final normalizedIrradiance = maxIrradiance > 0
          ? (h.irradiance / maxIrradiance) * maxWatts
          : 0.0;
      irradianceSpots.add(FlSpot(h.time.hour.toDouble(), normalizedIrradiance));
    }

    final firstHour = hourlyPower.first.time.hour.toDouble();
    final lastHour = hourlyPower.last.time.hour.toDouble();

    // Find current time marker position
    final now = DateTime.now();
    final locationNow = widget.sunMoonTimes?.toLocationTime(now) ?? now;
    double? currentTimeX;

    for (int i = 0; i < hourlyPower.length; i++) {
      final h = hourlyPower[i];
      if (h.time.hour == locationNow.hour &&
          h.time.day == locationNow.day &&
          h.time.month == locationNow.month) {
        currentTimeX = h.time.hour.toDouble();
        break;
      }
    }

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxWatts > 0 ? maxWatts / 4 : 100,
          getDrawingHorizontalLine: (value) => FlLine(
            color: isDark ? Colors.white10 : Colors.black12,
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            axisNameWidget: Text(
              'Power',
              style: TextStyle(
                fontSize: 10,
                color: primaryColor,
              ),
            ),
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 45,
              getTitlesWidget: (value, meta) {
                if (value == meta.max || value == meta.min) {
                  return const SizedBox.shrink();
                }
                return Text(
                  _formatPower(value),
                  style: TextStyle(
                    fontSize: 9,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                );
              },
            ),
          ),
          rightTitles: AxisTitles(
            axisNameWidget: Text(
              'W/m²',
              style: TextStyle(
                fontSize: 10,
                color: Colors.amber.shade700,
              ),
            ),
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                if (value == meta.max || value == meta.min) {
                  return const SizedBox.shrink();
                }
                final irradiance = maxWatts > 0 && maxIrradiance > 0
                    ? (value / maxWatts) * maxIrradiance
                    : 0.0;
                return Text(
                  _formatIrradiance(irradiance),
                  style: TextStyle(
                    fontSize: 9,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: 3,
              getTitlesWidget: (value, meta) {
                final hour = value.toInt();
                if (hour < firstHour || hour > lastHour) {
                  return const SizedBox.shrink();
                }
                final period = hour < 12 ? 'a' : 'p';
                final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
                return Text(
                  '$displayHour$period',
                  style: TextStyle(
                    fontSize: 9,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                );
              },
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        minX: firstHour,
        maxX: lastHour,
        minY: 0,
        maxY: maxWatts > 0 ? maxWatts * 1.1 : 100,
        lineBarsData: [
          // Power line (primary)
          LineChartBarData(
            spots: powerSpots,
            isCurved: true,
            curveSmoothness: 0.3,
            gradient: LinearGradient(
              colors: [
                Colors.blue.shade300,
                Colors.green,
                Colors.yellow.shade700,
                Colors.orange,
                Colors.deepOrange,
                Colors.red,
              ],
              stops: const [0.0, 0.2, 0.4, 0.6, 0.8, 1.0],
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
            ),
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  Colors.blue.shade300.withValues(alpha: 0.1),
                  Colors.green.withValues(alpha: 0.15),
                  Colors.yellow.shade700.withValues(alpha: 0.2),
                  Colors.orange.withValues(alpha: 0.25),
                  Colors.deepOrange.withValues(alpha: 0.3),
                  Colors.red.withValues(alpha: 0.35),
                ],
                stops: const [0.0, 0.2, 0.4, 0.6, 0.8, 1.0],
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
              ),
            ),
          ),
          // Irradiance line (secondary)
          LineChartBarData(
            spots: irradianceSpots,
            isCurved: true,
            curveSmoothness: 0.3,
            color: Colors.amber.shade700,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            dashArray: [5, 3],
          ),
        ],
        extraLinesData: ExtraLinesData(
          verticalLines: [
            if (currentTimeX != null)
              VerticalLine(
                x: currentTimeX,
                color: isDark ? Colors.white70 : Colors.red.shade400,
                strokeWidth: 2,
                dashArray: [5, 5],
                label: VerticalLineLabel(
                  show: true,
                  alignment: Alignment.topCenter,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.red.shade700,
                  ),
                  labelResolver: (line) => 'NOW',
                ),
              ),
          ],
        ),
        lineTouchData: LineTouchData(
          enabled: true,
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final index = spot.x.toInt();
                if (index < 0 || index >= hourlyPower.length) {
                  return null;
                }
                final data = hourlyPower[index];
                final isIrradiance = spot.barIndex == 1;

                if (isIrradiance) {
                  return LineTooltipItem(
                    _formatIrradiance(data.irradiance),
                    TextStyle(
                      color: Colors.amber.shade700,
                      fontWeight: FontWeight.bold,
                    ),
                  );
                }

                return LineTooltipItem(
                  '${_formatHour(data.time)}\n${_formatPower(data.watts)}',
                  TextStyle(
                    color: primaryColor,
                    fontWeight: FontWeight.bold,
                  ),
                );
              }).toList();
            },
          ),
        ),
      ),
    );
  }

  Widget _buildDailyChart(
    List<({DateTime date, double kWh, double peakWatts, DateTime? peakTime})> dailySummaries,
    bool isDark,
    Color primaryColor,
  ) {
    if (dailySummaries.isEmpty) {
      return const SizedBox.shrink();
    }

    final maxKwh = dailySummaries.map((d) => d.kWh).reduce(math.max);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Daily Forecast',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.white70 : Colors.black54,
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: maxKwh > 0 ? maxKwh * 1.2 : 10,
              barTouchData: BarTouchData(
                enabled: true,
                touchCallback: (event, response) {
                  if (event is FlTapUpEvent && response?.spot != null) {
                    final index = response!.spot!.touchedBarGroupIndex;
                    if (index >= 0 && index < dailySummaries.length) {
                      setState(() {
                        _selectedDate = dailySummaries[index].date;
                      });
                    }
                  }
                },
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    if (groupIndex < 0 || groupIndex >= dailySummaries.length) {
                      return null;
                    }
                    final data = dailySummaries[groupIndex];
                    return BarTooltipItem(
                      '${_getDayName(data.date)}\n${_formatKwh(data.kWh)}\nPeak: ${_formatPower(data.peakWatts)}',
                      TextStyle(
                        color: primaryColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    );
                  },
                ),
              ),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      final index = value.toInt();
                      if (index < 0 || index >= dailySummaries.length) {
                        return const SizedBox.shrink();
                      }
                      final date = dailySummaries[index].date;
                      final isSelected = _selectedDate?.day == date.day &&
                          _selectedDate?.month == date.month;
                      return Text(
                        _getDayName(date),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected
                              ? primaryColor
                              : (isDark ? Colors.white54 : Colors.black45),
                        ),
                      );
                    },
                  ),
                ),
              ),
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              barGroups: dailySummaries.asMap().entries.map((entry) {
                final index = entry.key;
                final data = entry.value;
                final isSelected = _selectedDate?.day == data.date.day &&
                    _selectedDate?.month == data.date.month;

                return BarChartGroupData(
                  x: index,
                  barRods: [
                    BarChartRodData(
                      toY: data.kWh,
                      color: isSelected
                          ? primaryColor
                          : primaryColor.withValues(alpha: 0.5),
                      width: 20,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(4),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDailyCards(
    List<({DateTime date, double kWh, double peakWatts, DateTime? peakTime})> dailySummaries,
    bool isDark,
    Color primaryColor,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Daily Forecast',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.white70 : Colors.black54,
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: dailySummaries.length,
            itemBuilder: (context, index) {
              final data = dailySummaries[index];
              final isSelected = _selectedDate?.day == data.date.day &&
                  _selectedDate?.month == data.date.month;

              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedDate = data.date;
                  });
                },
                child: Container(
                  width: 80,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? primaryColor.withValues(alpha: 0.2)
                        : (isDark ? Colors.white10 : Colors.grey.shade100),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected
                          ? primaryColor
                          : (isDark ? Colors.white24 : Colors.grey.shade300),
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _getDayName(data.date),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isSelected
                                ? primaryColor
                                : (isDark ? Colors.white : Colors.black87),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Icon(
                          Icons.wb_sunny,
                          color: primaryColor,
                          size: 20,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatKwh(data.kWh),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        Text(
                          'Peak: ${_formatPower(data.peakWatts)}',
                          style: TextStyle(
                            fontSize: 9,
                            color: isDark ? Colors.white54 : Colors.black45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // Formatting helpers
  String _formatPower(double watts) {
    if (watts >= 1000) {
      final kw = watts / 1000;
      return '${widget.conversions?.formatNumber(kw, format: '0.0') ?? kw.toStringAsFixed(1)} kW';
    }
    return '${widget.conversions?.formatNumber(watts, format: '0') ?? watts.toStringAsFixed(0)} W';
  }

  String _formatKwh(double kwh) {
    if (kwh < 0.1) return '< 0.1 kWh';
    return '${widget.conversions?.formatNumber(kwh, format: '0.0') ?? kwh.toStringAsFixed(1)} kWh';
  }

  String _formatIrradiance(double wm2) {
    return widget.conversions?.formatNumber(wm2, format: '0') ?? wm2.toStringAsFixed(0);
  }

  String _formatHour(DateTime time) {
    final hour = time.hour;
    if (hour == 0) return '12a';
    if (hour < 12) return '${hour}a';
    if (hour == 12) return '12p';
    return '${hour - 12}p';
  }

  String _getDayName(DateTime date) {
    final now = DateTime.now();
    final locationNow = widget.sunMoonTimes?.toLocationTime(now) ?? now;
    final today = DateTime(locationNow.year, locationNow.month, locationNow.day);
    final tomorrow = today.add(const Duration(days: 1));

    if (date.year == today.year && date.month == today.month && date.day == today.day) {
      return 'Today';
    }
    if (date.year == tomorrow.year && date.month == tomorrow.month && date.day == tomorrow.day) {
      return 'Tmrw';
    }

    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[date.weekday - 1];
  }
}
