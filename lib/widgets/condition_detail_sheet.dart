/// Condition Detail Sheet
///
/// Bottom sheet showing historical data and forecast for a condition variable.
/// Uses fl_chart to display the time series with past, current, and future data.

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:weatherflow_core/weatherflow_core.dart';
import '../services/observation_history_service.dart';
import '../services/weatherflow_service.dart';
import 'condition_card.dart';

/// Helper to format value for display using ConversionService
String formatConditionValue(ConditionVariable variable, double val, ConversionService conversions) {
  switch (variable) {
    case ConditionVariable.temperature:
    case ConditionVariable.feelsLike:
    case ConditionVariable.dewPoint:
      return conversions.formatTemperature(val);
    case ConditionVariable.humidity:
      return conversions.formatHumidity(val);
    case ConditionVariable.pressure:
      return conversions.formatPressure(val);
    case ConditionVariable.windSpeed:
    case ConditionVariable.windGust:
      return conversions.formatWindSpeed(val);
    case ConditionVariable.windDirection:
      return '${val.toStringAsFixed(0)}°';
    case ConditionVariable.rainRate:
    case ConditionVariable.rainAccumulated:
      return conversions.formatRainfall(val);
    case ConditionVariable.uvIndex:
      return val.toStringAsFixed(1);
    case ConditionVariable.solarRadiation:
      return '${val.toStringAsFixed(0)} W/m²';
    case ConditionVariable.illuminance:
      if (val >= 1000000) return '${(val / 1000000).toStringAsFixed(1)}M lux';
      if (val >= 1000) return '${(val / 1000).toStringAsFixed(1)}k lux';
      return '${val.toStringAsFixed(0)} lux';
    case ConditionVariable.lightningDistance:
      return conversions.formatDistance(val);
    case ConditionVariable.lightningCount:
      return val.toStringAsFixed(0);
    case ConditionVariable.batteryVoltage:
      return '${val.toStringAsFixed(2)} V';
  }
}

/// Time range options for the chart
enum ChartTimeRange {
  hours24('24 Hours', Duration(hours: 24)),
  days3('3 Days', Duration(days: 3)),
  days5('5 Days', Duration(days: 5));

  final String label;
  final Duration duration;

  const ChartTimeRange(this.label, this.duration);
}

/// Bottom sheet showing condition history and forecast
class ConditionDetailSheet extends StatefulWidget {
  final ConditionVariable variable;
  final WeatherFlowService weatherFlowService;

  const ConditionDetailSheet({
    super.key,
    required this.variable,
    required this.weatherFlowService,
  });

  @override
  State<ConditionDetailSheet> createState() => _ConditionDetailSheetState();
}

class _ConditionDetailSheetState extends State<ConditionDetailSheet> {
  ChartTimeRange _timeRange = ChartTimeRange.hours24;
  List<DataPoint> _historyData = [];
  List<DataPoint> _forecastData = [];
  SeriesStatistics? _stats;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Get device serial (prefer Tempest, then any device)
      final station = widget.weatherFlowService.selectedStation;
      if (station == null || station.devices.isEmpty) {
        setState(() {
          _error = 'No station selected';
          _isLoading = false;
        });
        return;
      }

      // Find best device (prefer ST/Tempest)
      final device = station.devices.firstWhere(
        (d) => d.deviceType == 'ST',
        orElse: () => station.devices.first,
      );

      // Fetch history
      final now = DateTime.now();
      final startTime = now.subtract(_timeRange.duration);

      final historyObs = await widget.weatherFlowService.getDeviceHistory(
        serialNumber: device.serialNumber,
        startTime: startTime,
        endTime: now,
      );

      // Extract series from history
      final historyService = ObservationHistoryService();
      final historyPoints = historyObs != null
          ? historyService.extractSeries(historyObs, widget.variable)
          : <DataPoint>[];

      // Calculate statistics
      final stats = historyService.calculateStatistics(historyPoints);

      // Get forecast data if available
      final forecastPoints = _extractForecastData();

      setState(() {
        _historyData = historyPoints;
        _forecastData = forecastPoints;
        _stats = stats;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  List<DataPoint> _extractForecastData() {
    if (!widget.variable.hasForecast) return [];

    final hourlyForecasts = widget.weatherFlowService.displayHourlyForecasts;
    final now = DateTime.now();
    final points = <DataPoint>[];

    for (final forecast in hourlyForecasts) {
      if (forecast.time == null || forecast.time!.isBefore(now)) continue;

      double? value;
      switch (widget.variable) {
        case ConditionVariable.temperature:
          value = forecast.temperature;
          break;
        case ConditionVariable.feelsLike:
          value = forecast.feelsLike;
          break;
        case ConditionVariable.humidity:
          value = forecast.humidity;
          break;
        case ConditionVariable.pressure:
          value = forecast.pressure;
          break;
        case ConditionVariable.windSpeed:
          value = forecast.windSpeed;
          break;
        case ConditionVariable.windGust:
          // Not directly available, skip
          break;
        case ConditionVariable.windDirection:
          value = forecast.windDirection;
          break;
        case ConditionVariable.uvIndex:
          // Not directly in HourlyForecast model, skip
          break;
        default:
          break;
      }

      if (value != null) {
        points.add(DataPoint(time: forecast.time!, value: value));
      }
    }

    return points;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final style = getStyleForVariable(widget.variable);
    final conversions = widget.weatherFlowService.conversions;

    // Current value
    final observation = widget.weatherFlowService.currentObservation;
    final historyService = ObservationHistoryService();
    final currentValue = historyService.getCurrentValue(observation, widget.variable);

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? Colors.grey.shade900 : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Drag handle
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      style.icon,
                      size: 28,
                      color: currentValue != null
                          ? style.getColorForValue(currentValue)
                          : Colors.grey,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.variable.label,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          if (currentValue != null)
                            Text(
                              'Current: ${formatConditionValue(widget.variable, currentValue, conversions)}',
                              style: TextStyle(
                                fontSize: 14,
                                color: isDark ? Colors.white70 : Colors.black54,
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              // Time range selector
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SegmentedButton<ChartTimeRange>(
                  segments: ChartTimeRange.values.map((range) {
                    return ButtonSegment<ChartTimeRange>(
                      value: range,
                      label: Text(range.label),
                    );
                  }).toList(),
                  selected: {_timeRange},
                  onSelectionChanged: (selected) {
                    setState(() {
                      _timeRange = selected.first;
                    });
                    _loadData();
                  },
                ),
              ),

              const SizedBox(height: 16),

              // Chart
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
                                const SizedBox(height: 8),
                                Text(_error!, style: TextStyle(color: Colors.red.shade300)),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: _loadData,
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          )
                        : _buildChart(isDark, style, conversions),
              ),

              // Statistics panel
              if (_stats != null && !_isLoading)
                _buildStatsPanel(isDark, style, conversions),
            ],
          ),
        );
      },
    );
  }

  Widget _buildChart(bool isDark, ConditionStyle style, ConversionService conversions) {
    if (_historyData.isEmpty && _forecastData.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.show_chart,
              size: 48,
              color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
            ),
            const SizedBox(height: 8),
            Text(
              'No data available',
              style: TextStyle(
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      );
    }

    // Build spots for chart
    final now = DateTime.now();
    final allPoints = [..._historyData, ..._forecastData];
    if (allPoints.isEmpty) return const SizedBox.shrink();

    // Find time range
    final minTime = allPoints.map((p) => p.time).reduce((a, b) => a.isBefore(b) ? a : b);
    final maxTime = allPoints.map((p) => p.time).reduce((a, b) => a.isAfter(b) ? a : b);
    final timeRange = maxTime.difference(minTime).inMinutes.toDouble();

    // Convert to spots
    final historySpots = _historyData.map((p) {
      final x = p.time.difference(minTime).inMinutes.toDouble();
      return FlSpot(x, p.value);
    }).toList();

    final forecastSpots = _forecastData.map((p) {
      final x = p.time.difference(minTime).inMinutes.toDouble();
      return FlSpot(x, p.value);
    }).toList();

    // Current time marker
    final nowX = now.difference(minTime).inMinutes.toDouble();

    // Find Y range
    final allValues = allPoints.map((p) => p.value).toList();
    final minY = allValues.reduce((a, b) => a < b ? a : b);
    final maxY = allValues.reduce((a, b) => a > b ? a : b);
    final yRange = maxY - minY;
    final yPadding = yRange > 0 ? yRange * 0.1 : 1.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 16, 8),
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: timeRange,
          minY: minY - yPadding,
          maxY: maxY + yPadding,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: _calculateYInterval(minY - yPadding, maxY + yPadding),
            getDrawingHorizontalLine: (value) => FlLine(
              color: isDark ? Colors.white12 : Colors.black12,
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 50,
                interval: _calculateYInterval(minY - yPadding, maxY + yPadding),
                getTitlesWidget: (value, meta) {
                  return Text(
                    formatConditionValue(widget.variable, value, conversions),
                    style: TextStyle(
                      fontSize: 10,
                      color: isDark ? Colors.white54 : Colors.black54,
                    ),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: _calculateTimeInterval(timeRange),
                getTitlesWidget: (value, meta) {
                  final time = minTime.add(Duration(minutes: value.toInt()));
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _formatTimeLabel(time, _timeRange),
                      style: TextStyle(
                        fontSize: 9,
                        color: isDark ? Colors.white54 : Colors.black54,
                      ),
                    ),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(
            show: true,
            border: Border(
              left: BorderSide(color: isDark ? Colors.white24 : Colors.black26),
              bottom: BorderSide(color: isDark ? Colors.white24 : Colors.black26),
            ),
          ),
          lineBarsData: [
            // History line
            if (historySpots.isNotEmpty)
              LineChartBarData(
                spots: historySpots,
                isCurved: true,
                curveSmoothness: 0.2,
                color: style.midColor,
                barWidth: 2,
                isStrokeCapRound: true,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    colors: [
                      style.midColor.withValues(alpha: 0.3),
                      style.midColor.withValues(alpha: 0.05),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            // Forecast line
            if (forecastSpots.isNotEmpty)
              LineChartBarData(
                spots: forecastSpots,
                isCurved: true,
                curveSmoothness: 0.2,
                color: Colors.orange,
                barWidth: 2,
                isStrokeCapRound: true,
                dashArray: [5, 3],
                dotData: const FlDotData(show: false),
              ),
          ],
          extraLinesData: ExtraLinesData(
            verticalLines: [
              // "Now" line
              VerticalLine(
                x: nowX.clamp(0, timeRange),
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
                  final time = minTime.add(Duration(minutes: spot.x.toInt()));
                  final formattedTime = DateFormat('MMM d, h:mm a').format(time);
                  final formattedValue = formatConditionValue(widget.variable, spot.y, conversions);

                  return LineTooltipItem(
                    '$formattedTime\n$formattedValue',
                    TextStyle(
                      color: spot.bar.color,
                      fontWeight: FontWeight.bold,
                    ),
                  );
                }).toList();
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatsPanel(bool isDark, ConditionStyle style, ConversionService conversions) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildStatItem(
              'Min',
              formatConditionValue(widget.variable, _stats!.min, conversions),
              _stats!.minTime != null ? DateFormat('h:mm a').format(_stats!.minTime!) : '',
              Colors.blue,
              isDark,
            ),
            _buildStatItem(
              'Max',
              formatConditionValue(widget.variable, _stats!.max, conversions),
              _stats!.maxTime != null ? DateFormat('h:mm a').format(_stats!.maxTime!) : '',
              Colors.red,
              isDark,
            ),
            _buildStatItem(
              'Avg',
              formatConditionValue(widget.variable, _stats!.avg, conversions),
              '',
              Colors.purple,
              isDark,
            ),
            _buildStatItem(
              'Trend',
              _stats!.trendIcon,
              _stats!.trendLabel,
              _stats!.trend != null && _stats!.trend! > 0 ? Colors.green : Colors.orange,
              isDark,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, String subtitle, Color color, bool isDark) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: isDark ? Colors.white54 : Colors.black54,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        if (subtitle.isNotEmpty)
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 10,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),
      ],
    );
  }

  double _calculateYInterval(double min, double max) {
    final range = max - min;
    if (range <= 10) return 2;
    if (range <= 50) return 10;
    if (range <= 100) return 20;
    if (range <= 500) return 100;
    return (range / 5).roundToDouble();
  }

  double _calculateTimeInterval(double rangeMinutes) {
    if (rangeMinutes <= 60) return 10; // 10 min intervals
    if (rangeMinutes <= 360) return 60; // 1 hour
    if (rangeMinutes <= 1440) return 180; // 3 hours
    if (rangeMinutes <= 4320) return 720; // 12 hours
    return 1440; // 1 day
  }

  String _formatTimeLabel(DateTime time, ChartTimeRange range) {
    switch (range) {
      case ChartTimeRange.hours24:
        return DateFormat('h a').format(time);
      case ChartTimeRange.days3:
      case ChartTimeRange.days5:
        return DateFormat('M/d').format(time);
    }
  }
}
