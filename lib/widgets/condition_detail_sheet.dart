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
  SeriesStatistics? _historyStats;
  SeriesStatistics? _forecastStats;
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

    final conversions = widget.weatherFlowService.conversions;

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

      // Extract series from history and CONVERT values
      final historyService = ObservationHistoryService();
      final rawHistoryPoints = historyObs != null
          ? historyService.extractSeries(historyObs, widget.variable)
          : <DataPoint>[];

      // Convert all history values using ConversionService
      final historyPoints = rawHistoryPoints.map((p) {
        final converted = _convertValue(p.value, conversions);
        return DataPoint(time: p.time, value: converted);
      }).toList();

      // Get forecast data (already converted in _extractForecastData)
      final forecastPoints = _extractForecastData(conversions);

      // Calculate statistics on CONVERTED values for both history and forecast
      final historyStats = historyService.calculateStatistics(historyPoints);
      final forecastStats = historyService.calculateStatistics(forecastPoints);

      setState(() {
        _historyData = historyPoints;
        _forecastData = forecastPoints;
        _historyStats = historyStats;
        _forecastStats = forecastStats;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  /// Convert a raw SI value to user's preferred units
  double _convertValue(double rawValue, ConversionService conversions) {
    switch (widget.variable) {
      case ConditionVariable.temperature:
      case ConditionVariable.feelsLike:
      case ConditionVariable.dewPoint:
        return conversions.convertTemperature(rawValue) ?? rawValue;
      case ConditionVariable.humidity:
        return conversions.convertHumidity(rawValue);
      case ConditionVariable.pressure:
        return conversions.convertPressure(rawValue) ?? rawValue;
      case ConditionVariable.windSpeed:
      case ConditionVariable.windGust:
        return conversions.convertWindSpeed(rawValue) ?? rawValue;
      case ConditionVariable.windDirection:
        return rawValue; // Degrees don't need conversion
      case ConditionVariable.rainRate:
      case ConditionVariable.rainAccumulated:
        return conversions.convertRainfall(rawValue) ?? rawValue;
      case ConditionVariable.lightningDistance:
        return conversions.convertDistance(rawValue) ?? rawValue;
      case ConditionVariable.uvIndex:
      case ConditionVariable.solarRadiation:
      case ConditionVariable.illuminance:
      case ConditionVariable.lightningCount:
      case ConditionVariable.batteryVoltage:
      case ConditionVariable.precipType:
        return rawValue; // No conversion needed
    }
  }

  List<DataPoint> _extractForecastData(ConversionService conversions) {
    if (!widget.variable.hasForecast) {
      debugPrint('ConditionDetailSheet: Variable ${widget.variable} has no forecast');
      return [];
    }

    final hourlyForecasts = widget.weatherFlowService.displayHourlyForecasts;
    debugPrint('ConditionDetailSheet: displayHourlyForecasts count: ${hourlyForecasts.length}');

    final now = DateTime.now();
    // Limit forecast to same duration as history (so 24h history = 24h into future)
    final maxForecastTime = now.add(_timeRange.duration);
    final points = <DataPoint>[];

    for (final forecast in hourlyForecasts) {
      if (forecast.time == null) continue;
      // Skip past forecasts and forecasts beyond our time range
      if (forecast.time!.isBefore(now) || forecast.time!.isAfter(maxForecastTime)) continue;

      double? rawValue;
      switch (widget.variable) {
        case ConditionVariable.temperature:
          rawValue = forecast.temperature;
          break;
        case ConditionVariable.feelsLike:
          rawValue = forecast.feelsLike;
          break;
        case ConditionVariable.humidity:
          rawValue = forecast.humidity;
          break;
        case ConditionVariable.pressure:
          rawValue = forecast.pressure;
          break;
        case ConditionVariable.windSpeed:
          rawValue = forecast.windSpeed;
          break;
        case ConditionVariable.windGust:
          rawValue = forecast.windGust;
          break;
        case ConditionVariable.windDirection:
          rawValue = forecast.windDirection;
          break;
        case ConditionVariable.uvIndex:
          rawValue = forecast.uvIndex;
          break;
        case ConditionVariable.precipType:
          rawValue = ObservationHistoryService.precipTypeStringToDouble(forecast.precipType);
          break;
        default:
          break;
      }

      if (rawValue != null) {
        // Convert to user's preferred units
        final converted = _convertValue(rawValue, conversions);
        points.add(DataPoint(time: forecast.time!, value: converted));
      }
    }

    debugPrint('ConditionDetailSheet: Extracted ${points.length} forecast points');
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
                              'Current: ${_convertValue(currentValue, conversions).toStringAsFixed(1)}${widget.variable.getUnitSymbol(conversions)}',
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
              if ((_historyStats != null || _forecastStats != null) && !_isLoading)
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
                  // Values are already converted, just format with unit
                  final unit = widget.variable.getUnitSymbol(conversions);
                  return Text(
                    '${value.toStringAsFixed(0)}$unit',
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
                  // Values are already converted, just format with unit
                  final unit = widget.variable.getUnitSymbol(conversions);
                  final formattedValue = '${spot.y.toStringAsFixed(1)}$unit';

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
    final unit = widget.variable.getUnitSymbol(conversions);
    final historyColor = style.midColor;
    final forecastColor = Colors.orange;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // History stats row
            if (_historyStats != null) ...[
              Row(
                children: [
                  Container(
                    width: 4,
                    height: 36,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: historyColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Text(
                    'History',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                  const Spacer(),
                  _buildCompactStat('Min', _historyStats!.min, unit, Colors.blue, isDark),
                  const SizedBox(width: 12),
                  _buildCompactStat('Max', _historyStats!.max, unit, Colors.red, isDark),
                  const SizedBox(width: 12),
                  _buildCompactStat('Avg', _historyStats!.avg, unit, Colors.purple, isDark),
                  const SizedBox(width: 12),
                  _buildTrendIndicator(_historyStats!, isDark),
                ],
              ),
            ],

            // Divider between history and forecast
            if (_historyStats != null && _forecastStats != null)
              Divider(
                height: 12,
                color: isDark ? Colors.white24 : Colors.black12,
              ),

            // Forecast stats row
            if (_forecastStats != null) ...[
              Row(
                children: [
                  Container(
                    width: 4,
                    height: 36,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: forecastColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Text(
                    'Forecast',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                  const Spacer(),
                  _buildCompactStat('Min', _forecastStats!.min, unit, Colors.blue.shade300, isDark),
                  const SizedBox(width: 12),
                  _buildCompactStat('Max', _forecastStats!.max, unit, Colors.red.shade300, isDark),
                  const SizedBox(width: 12),
                  _buildCompactStat('Avg', _forecastStats!.avg, unit, Colors.purple.shade300, isDark),
                  const SizedBox(width: 12),
                  _buildTrendIndicator(_forecastStats!, isDark),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCompactStat(String label, double value, String unit, Color color, bool isDark) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            color: isDark ? Colors.white38 : Colors.black38,
          ),
        ),
        Text(
          '${value.toStringAsFixed(0)}$unit',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildTrendIndicator(SeriesStatistics stats, bool isDark) {
    final color = stats.trend != null && stats.trend! > 0 ? Colors.green : Colors.orange;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Trend',
          style: TextStyle(
            fontSize: 9,
            color: isDark ? Colors.white38 : Colors.black38,
          ),
        ),
        Text(
          stats.trendIcon,
          style: TextStyle(
            fontSize: 14,
            color: color,
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
