// Forecast Chart Tool
// Line chart displaying future weather forecast data (hourly or daily)
// Ported from ZedDisplay-OpenMeteo

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:weatherflow_core/weatherflow_core.dart' hide HourlyForecast, DailyForecast;
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../services/tool_registry.dart';
import '../../services/weatherflow_service.dart';
import '../forecast_models.dart';

/// Get complementary color (opposite on color wheel)
Color _getComplementaryColor(Color color) {
  final hsl = HSLColor.fromColor(color);
  return hsl.withHue((hsl.hue + 180) % 360).toColor();
}

/// Builder for Forecast Chart tool
class ForecastChartToolBuilder implements ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return const ToolDefinition(
      id: 'forecast_chart',
      name: 'Forecast Chart',
      description: 'Future weather forecast with hourly or daily data',
      category: ToolCategory.charts,
      configSchema: ConfigSchema(
        allowsMinMax: false,
        allowsColorCustomization: true,
        allowsMultiplePaths: false,
        minPaths: 0,
        maxPaths: 0,
        styleOptions: ['dataElement', 'chartMode', 'chartStyle', 'forecastDays', 'showGrid', 'showLegend', 'showDataPoints'],
      ),
      defaultWidth: 4,
      defaultHeight: 3,
    );
  }

  @override
  Widget build(ToolConfig config, WeatherFlowService weatherFlowService, {bool isEditMode = false, String? name, void Function(ToolConfig)? onConfigChanged}) {
    return ForecastChartTool(
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
        primaryColor: '#4A90D9',
        customProperties: {
          'dataElement': 'temperature',
          'chartMode': 'combo',
          'chartStyle': 'spline',
          'forecastDays': 3,
          'showGrid': true,
          'showLegend': true,
          'showDataPoints': false,
        },
      ),
    );
  }

  /// Available data elements for hourly mode (WeatherFlow forecast fields)
  static const Map<String, String> hourlyDataElements = {
    // Temperature
    'temperature': 'Temperature',
    'feels_like': 'Feels Like',
    // Precipitation
    'precipitation_probability': 'Precip Probability',
    // Humidity & Pressure
    'humidity': 'Humidity',
    'pressure': 'Pressure',
    // Wind
    'wind_speed': 'Wind Speed',
    'wind_direction': 'Wind Direction',
    'beaufort': 'Beaufort Scale',
  };

  /// Available data elements for daily mode
  static const Map<String, String> dailyDataElements = {
    // Temperature
    'temperature_high': 'Temperature (High)',
    'temperature_low': 'Temperature (Low)',
    'temperature_range': 'Temperature Range (Hi/Lo)',
    // Precipitation
    'precipitation_probability': 'Precip Probability',
  };

  /// Convert raw value to user's preferred units
  static double? convertValue(String dataKey, double? value, ConversionService conversions) {
    if (value == null) return null;

    switch (dataKey) {
      // Temperature (Kelvin) - use ConversionService
      case 'temperature':
      case 'temperature_high':
      case 'temperature_low':
      case 'feels_like':
        return conversions.convertTemperature(value);
      // Wind speed (m/s) - use ConversionService
      case 'wind_speed':
        return conversions.convertWindSpeed(value);
      // Pressure (Pascals) - use ConversionService
      case 'pressure':
        return conversions.convertPressure(value);
      // Ratios to percentage - use ConversionService
      case 'humidity':
        return conversions.convertHumidity(value);
      case 'precipitation_probability':
        return conversions.convertProbability(value);
      // No conversion needed
      case 'wind_direction':
      case 'beaufort':
        return value;
      default:
        return value;
    }
  }

  /// Get unit label for display
  static String getUnitLabel(String dataKey, ConversionService conversions) {
    switch (dataKey) {
      // Temperature - use ConversionService symbol
      case 'temperature':
      case 'temperature_high':
      case 'temperature_low':
      case 'temperature_range':
      case 'feels_like':
        return conversions.temperatureSymbol;
      // Wind speed - use ConversionService symbol
      case 'wind_speed':
        return conversions.windSpeedSymbol;
      // Pressure - use ConversionService symbol
      case 'pressure':
        return conversions.pressureSymbol;
      // Percentage (fixed)
      case 'humidity':
      case 'precipitation_probability':
        return '%';
      // Degrees (fixed)
      case 'wind_direction':
        return '°';
      // No unit (fixed)
      case 'beaufort':
        return '';
      default:
        return '';
    }
  }
}

/// Data point for chart
class ForecastDataPoint {
  final DateTime time;
  final double? value;
  final double? secondaryValue; // For temperature range (low) or combo mode (hourly min)
  final double? hourlyMax;      // For combo mode: max of hourly values that day
  final double? hourlyMin;      // For combo mode: min of hourly values that day

  const ForecastDataPoint({
    required this.time,
    this.value,
    this.secondaryValue,
    this.hourlyMax,
    this.hourlyMin,
  });
}

/// Forecast Chart display widget
class ForecastChartTool extends StatefulWidget {
  final ToolConfig config;
  final WeatherFlowService weatherFlowService;
  final bool isEditMode;
  final String? name;

  const ForecastChartTool({
    super.key,
    required this.config,
    required this.weatherFlowService,
    this.isEditMode = false,
    this.name,
  });

  @override
  State<ForecastChartTool> createState() => _ForecastChartToolState();
}

class _ForecastChartToolState extends State<ForecastChartTool> {
  @override
  void initState() {
    super.initState();
    widget.weatherFlowService.addListener(_onDataChanged);
  }

  @override
  void dispose() {
    widget.weatherFlowService.removeListener(_onDataChanged);
    super.dispose();
  }

  void _onDataChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(ForecastChartTool oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.weatherFlowService != widget.weatherFlowService) {
      oldWidget.weatherFlowService.removeListener(_onDataChanged);
      widget.weatherFlowService.addListener(_onDataChanged);
    }
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

  /// Extract hourly data for a given element
  List<ForecastDataPoint> _getHourlyData(String dataElement, int maxHours) {
    final hourlyList = widget.weatherFlowService.displayHourlyForecasts;
    final result = <ForecastDataPoint>[];

    for (int i = 0; i < hourlyList.length && i < maxHours; i++) {
      final hour = hourlyList[i];
      double? value;

      switch (dataElement) {
        case 'temperature':
          value = hour.temperature;
          break;
        case 'feels_like':
          value = hour.feelsLike;
          break;
        case 'precipitation_probability':
          value = hour.precipProbability;
          break;
        case 'humidity':
          value = hour.humidity;
          break;
        case 'pressure':
          value = hour.pressure;
          break;
        case 'wind_speed':
          value = hour.windSpeed;
          break;
        case 'wind_direction':
          value = hour.windDirection;
          break;
        case 'beaufort':
          value = hour.beaufort?.toDouble();
          break;
      }

      if (hour.time != null) {
        result.add(ForecastDataPoint(time: hour.time!, value: value));
      }
    }

    return result;
  }

  /// Extract daily data for a given element
  List<ForecastDataPoint> _getDailyData(String dataElement, int maxDays) {
    final dailyList = widget.weatherFlowService.displayDailyForecasts;
    final result = <ForecastDataPoint>[];

    for (int i = 0; i < dailyList.length && i < maxDays; i++) {
      final day = dailyList[i];
      double? value;
      double? secondaryValue;

      switch (dataElement) {
        case 'temperature_high':
          value = day.tempHigh;
          break;
        case 'temperature_low':
          value = day.tempLow;
          break;
        case 'temperature_range':
          value = day.tempHigh;
          secondaryValue = day.tempLow;
          break;
        case 'precipitation_probability':
          value = day.precipProbability;
          break;
      }

      if (day.date != null) {
        result.add(ForecastDataPoint(
          time: day.date!,
          value: value,
          secondaryValue: secondaryValue,
        ));
      }
    }

    return result;
  }

  /// Extract combo data: daily value + hourly min/max range for each day
  List<ForecastDataPoint> _getComboData(String dataElement, int maxDays) {
    final hourlyList = widget.weatherFlowService.displayHourlyForecasts;
    final dailyList = widget.weatherFlowService.displayDailyForecasts;
    final result = <ForecastDataPoint>[];

    for (int dayIndex = 0; dayIndex < dailyList.length && dayIndex < maxDays; dayIndex++) {
      final day = dailyList[dayIndex];
      if (day.date == null) continue;

      final dayStart = DateTime(day.date!.year, day.date!.month, day.date!.day);
      final dayEnd = dayStart.add(const Duration(days: 1));

      // Get hourly values for this day
      final hourlyForDay = hourlyList.where((h) =>
          h.time != null && !h.time!.isBefore(dayStart) && h.time!.isBefore(dayEnd)).toList();

      // Extract hourly values for the selected element
      final hourlyValues = <double>[];
      for (final hour in hourlyForDay) {
        double? value;
        switch (dataElement) {
          case 'temperature':
            value = hour.temperature;
            break;
          case 'feels_like':
            value = hour.feelsLike;
            break;
          case 'precipitation_probability':
            value = hour.precipProbability;
            break;
          case 'humidity':
            value = hour.humidity;
            break;
          case 'wind_speed':
            value = hour.windSpeed;
            break;
          case 'pressure':
            value = hour.pressure;
            break;
          default:
            value = hour.temperature;
        }
        if (value != null) hourlyValues.add(value);
      }

      // Calculate hourly min/max
      double? hourlyMin;
      double? hourlyMax;
      if (hourlyValues.isNotEmpty) {
        hourlyMin = hourlyValues.reduce((a, b) => a < b ? a : b);
        hourlyMax = hourlyValues.reduce((a, b) => a > b ? a : b);
      }

      // Get daily value (use mean or specific daily field)
      double? dailyValue;
      switch (dataElement) {
        case 'temperature':
          // Use mean of high/low
          if (day.tempHigh != null && day.tempLow != null) {
            dailyValue = (day.tempHigh! + day.tempLow!) / 2;
          }
          break;
        case 'precipitation_probability':
          dailyValue = day.precipProbability;
          break;
        default:
          // For elements without daily equivalent, use hourly mean
          if (hourlyValues.isNotEmpty) {
            dailyValue = hourlyValues.reduce((a, b) => a + b) / hourlyValues.length;
          }
      }

      result.add(ForecastDataPoint(
        time: day.date!,
        value: dailyValue,
        hourlyMax: hourlyMax,
        hourlyMin: hourlyMin,
      ));
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = _getPrimaryColor(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Get config values
    final dataElement = widget.config.style.customProperties?['dataElement'] as String? ?? 'temperature';
    final chartMode = widget.config.style.customProperties?['chartMode'] as String? ?? 'combo';
    final chartStyle = widget.config.style.customProperties?['chartStyle'] as String? ?? 'spline';
    final forecastDays = widget.config.style.customProperties?['forecastDays'] as int? ?? 3;
    final showGrid = widget.config.style.customProperties?['showGrid'] as bool? ?? true;
    final showLegend = widget.config.style.customProperties?['showLegend'] as bool? ?? true;
    final showDataPoints = widget.config.style.customProperties?['showDataPoints'] as bool? ?? false;

    final isHourly = chartMode == 'hourly';
    final isCombo = chartMode == 'combo';
    final maxHours = forecastDays * 24;

    // Loading state
    if (widget.weatherFlowService.isLoading && !widget.weatherFlowService.hasData) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    // No data state
    if (!widget.weatherFlowService.hasData) {
      return const Center(
        child: Text('No forecast data'),
      );
    }

    // Get data series based on mode
    List<ForecastDataPoint> dataSeries;
    if (isCombo) {
      dataSeries = _getComboData(dataElement, forecastDays);
    } else if (isHourly) {
      dataSeries = _getHourlyData(dataElement, maxHours);
    } else {
      dataSeries = _getDailyData(dataElement, forecastDays);
    }

    if (dataSeries.isEmpty) {
      return const Center(
        child: Text('No data for selected element'),
      );
    }

    // Convert values using user preferences
    final conversions = widget.weatherFlowService.conversions;
    final convertedData = dataSeries.map((point) {
      return ForecastDataPoint(
        time: point.time,
        value: ForecastChartToolBuilder.convertValue(dataElement, point.value, conversions),
        secondaryValue: ForecastChartToolBuilder.convertValue(dataElement, point.secondaryValue, conversions),
        hourlyMax: ForecastChartToolBuilder.convertValue(dataElement, point.hourlyMax, conversions),
        hourlyMin: ForecastChartToolBuilder.convertValue(dataElement, point.hourlyMin, conversions),
      );
    }).toList();

    // Get display name (combo and hourly use hourly elements)
    final dataElements = (isHourly || isCombo)
        ? ForecastChartToolBuilder.hourlyDataElements
        : ForecastChartToolBuilder.dailyDataElements;
    final displayName = dataElements[dataElement] ?? dataElement;

    // Build chart
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title and legend
          if (showLegend)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      displayName,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  // Legend items
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isCombo) ...[
                        // Combo legend: box for range, line for daily
                        Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: primaryColor.withValues(alpha: 0.3),
                            border: Border.all(
                              color: primaryColor.withValues(alpha: 0.6),
                              width: 1,
                            ),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text('Range', style: Theme.of(context).textTheme.labelSmall),
                        const SizedBox(width: 8),
                        Container(
                          width: 14,
                          height: 3,
                          color: primaryColor,
                        ),
                        const SizedBox(width: 4),
                        Text('Avg', style: Theme.of(context).textTheme.labelSmall),
                      ] else ...[
                        Container(
                          width: 12,
                          height: 3,
                          color: primaryColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isHourly ? 'Hourly' : 'Daily',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        if (dataElement == 'temperature_range') ...[
                          const SizedBox(width: 12),
                          Container(
                            width: 12,
                            height: 3,
                            color: primaryColor.withValues(alpha: 0.5),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Low',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ],
                    ],
                  ),
                ],
              ),
            ),

          // Chart
          Expanded(
            child: _buildChart(
              context,
              convertedData,
              primaryColor,
              isDark,
              showGrid,
              showDataPoints,
              dataElement,
              conversions,
              isHourly,
              isCombo,
              chartStyle,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChart(
    BuildContext context,
    List<ForecastDataPoint> data,
    Color primaryColor,
    bool isDark,
    bool showGrid,
    bool showDataPoints,
    String dataElement,
    ConversionService conversions,
    bool isHourly,
    bool isCombo,
    String chartStyle,
  ) {
    final complementaryColor = _getComplementaryColor(primaryColor);
    // Build spots for data line(s)
    final primarySpots = <FlSpot>[];
    final secondarySpots = <FlSpot>[]; // For temperature range
    final rangeHighSpots = <FlSpot>[]; // For combo mode (hourly max)
    final rangeLowSpots = <FlSpot>[];  // For combo mode (hourly min)

    for (int i = 0; i < data.length; i++) {
      if (data[i].value != null) {
        primarySpots.add(FlSpot(i.toDouble(), data[i].value!));
      }
      if (data[i].secondaryValue != null) {
        secondarySpots.add(FlSpot(i.toDouble(), data[i].secondaryValue!));
      }
      if (data[i].hourlyMax != null) {
        rangeHighSpots.add(FlSpot(i.toDouble(), data[i].hourlyMax!));
      }
      if (data[i].hourlyMin != null) {
        rangeLowSpots.add(FlSpot(i.toDouble(), data[i].hourlyMin!));
      }
    }

    if (primarySpots.isEmpty && rangeHighSpots.isEmpty) {
      return const Center(child: Text('No valid data points'));
    }

    // Calculate min/max for Y axis
    final allValues = [
      ...primarySpots.map((s) => s.y),
      ...secondarySpots.map((s) => s.y),
      ...rangeHighSpots.map((s) => s.y),
      ...rangeLowSpots.map((s) => s.y),
    ];
    if (allValues.isEmpty) {
      return const Center(child: Text('No valid data points'));
    }
    final minY = allValues.reduce((a, b) => a < b ? a : b);
    final maxY = allValues.reduce((a, b) => a > b ? a : b);
    final range = maxY - minY;
    final padding = range > 0 ? range * 0.1 : 1.0;
    final chartMinY = minY - padding;
    final chartMaxY = maxY + padding;

    // Get unit label
    final unitLabel = ForecastChartToolBuilder.getUnitLabel(dataElement, conversions);

    // For combo mode, use a different chart structure
    if (isCombo && rangeHighSpots.isNotEmpty) {
      return _buildComboChart(
        context, data, primaryColor, complementaryColor, isDark, showGrid, unitLabel,
        primarySpots, rangeHighSpots, rangeLowSpots, chartMinY, chartMaxY,
        conversions,
      );
    }

    // For bar chart style, build bar chart instead of line chart
    if (chartStyle == 'bar') {
      return _buildBarChart(
        context, data, primaryColor, isDark, showGrid, unitLabel,
        primarySpots, chartMinY, chartMaxY, conversions, isHourly,
      );
    }

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (data.length - 1).toDouble(),
        minY: chartMinY,
        maxY: chartMaxY,
        lineTouchData: LineTouchData(
          enabled: true,
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touchedSpots) {
              if (touchedSpots.isEmpty) return [];

              final index = touchedSpots.first.x.toInt();
              if (index < 0 || index >= data.length) return [];

              final dataPoint = data[index];
              final timeStr = isHourly
                  ? DateFormat('EEE h a').format(dataPoint.time)
                  : DateFormat('EEE, MMM d').format(dataPoint.time);
              final primaryValue = dataPoint.value?.toStringAsFixed(1) ?? '--';

              String tooltipText;
              if (dataElement == 'temperature_range' && dataPoint.secondaryValue != null) {
                final secondaryValue = dataPoint.secondaryValue!.toStringAsFixed(1);
                tooltipText = '$timeStr\nHi: $primaryValue / Lo: $secondaryValue $unitLabel';
              } else {
                tooltipText = '$timeStr\n$primaryValue $unitLabel';
              }

              return [
                LineTooltipItem(
                  tooltipText,
                  TextStyle(
                    color: isDark ? Colors.white : Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                ...List.filled(touchedSpots.length - 1, null),
              ];
            },
          ),
        ),
        gridData: FlGridData(
          show: showGrid,
          drawVerticalLine: false,
          horizontalInterval: _calculateInterval(chartMinY, chartMaxY),
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: isDark ? Colors.white12 : Colors.black12,
              strokeWidth: 1,
            );
          },
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            axisNameWidget: unitLabel.isNotEmpty
                ? Text(
                    unitLabel,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  )
                : null,
            axisNameSize: unitLabel.isNotEmpty ? 24 : 0,
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              interval: _calculateInterval(chartMinY, chartMaxY),
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toStringAsFixed(0),
                  style: TextStyle(
                    fontSize: 12,
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
              interval: _calculateTimeInterval(data.length, isHourly),
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= data.length) {
                  return const SizedBox.shrink();
                }
                final time = data[index].time;
                final label = isHourly
                    ? DateFormat('ha').format(time).toLowerCase()
                    : DateFormat('E').format(time);
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
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
          // Primary data line
          LineChartBarData(
            spots: primarySpots,
            isCurved: true,
            curveSmoothness: 0.2,
            color: primaryColor,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: showDataPoints,
              getDotPainter: (spot, percent, barData, index) {
                return FlDotCirclePainter(
                  radius: 3,
                  color: primaryColor,
                  strokeWidth: 0,
                );
              },
            ),
            belowBarData: BarAreaData(
              show: chartStyle == 'splineFilled' || (dataElement == 'temperature_range' && secondarySpots.isNotEmpty),
              gradient: chartStyle == 'splineFilled'
                  ? LinearGradient(
                      colors: [
                        primaryColor.withValues(alpha: 0.4),
                        complementaryColor.withValues(alpha: 0.1),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    )
                  : null,
              color: chartStyle != 'splineFilled' ? primaryColor.withValues(alpha: 0.2) : null,
              cutOffY: secondarySpots.isNotEmpty ? secondarySpots.map((s) => s.y).reduce((a, b) => a < b ? a : b) : chartMinY,
              applyCutOffY: false,
            ),
          ),
          // Secondary line for temperature range (low)
          if (secondarySpots.isNotEmpty)
            LineChartBarData(
              spots: secondarySpots,
              isCurved: true,
              curveSmoothness: 0.2,
              color: primaryColor.withValues(alpha: 0.5),
              barWidth: 2,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: showDataPoints,
                getDotPainter: (spot, percent, barData, index) {
                  return FlDotCirclePainter(
                    radius: 3,
                    color: primaryColor.withValues(alpha: 0.5),
                    strokeWidth: 0,
                  );
                },
              ),
            ),
        ],
        // Fill between lines for temperature range
        betweenBarsData: dataElement == 'temperature_range' && secondarySpots.isNotEmpty
            ? [
                BetweenBarsData(
                  fromIndex: 0,
                  toIndex: 1,
                  color: primaryColor.withValues(alpha: 0.15),
                ),
              ]
            : [],
      ),
    );
  }

  /// Build combo chart with box plot style range bars and daily value line
  Widget _buildComboChart(
    BuildContext context,
    List<ForecastDataPoint> data,
    Color primaryColor,
    Color complementaryColor,
    bool isDark,
    bool showGrid,
    String unitLabel,
    List<FlSpot> dailySpots,
    List<FlSpot> rangeHighSpots,
    List<FlSpot> rangeLowSpots,
    double chartMinY,
    double chartMaxY,
    ConversionService conversions,
  ) {
    // Calculate line thickness based on data range
    final dataRange = chartMaxY - chartMinY;
    final lineThickness = dataRange * 0.02;

    // Build bar groups for box plot style range display with gradients
    final barGroups = <BarChartGroupData>[];
    for (int i = 0; i < data.length; i++) {
      final point = data[i];
      if (point.hourlyMin != null && point.hourlyMax != null && point.value != null) {
        final avgPosition = (point.value! - point.hourlyMin!) / (point.hourlyMax! - point.hourlyMin!);

        barGroups.add(
          BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                fromY: point.value! - lineThickness,
                toY: point.value! + lineThickness,
                color: primaryColor,
                width: 24,
                borderRadius: BorderRadius.zero,
                backDrawRodData: BackgroundBarChartRodData(
                  show: true,
                  fromY: point.hourlyMin!,
                  toY: point.hourlyMax!,
                  gradient: LinearGradient(
                    colors: [
                      complementaryColor.withValues(alpha: 0.5),
                      primaryColor.withValues(alpha: 0.3),
                      complementaryColor.withValues(alpha: 0.5),
                    ],
                    stops: [0.0, avgPosition.clamp(0.1, 0.9), 1.0],
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                  ),
                ),
              ),
            ],
          ),
        );
      } else if (point.hourlyMin != null && point.hourlyMax != null) {
        barGroups.add(
          BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                fromY: point.hourlyMin!,
                toY: point.hourlyMax!,
                width: 24,
                borderRadius: BorderRadius.circular(2),
                gradient: LinearGradient(
                  colors: [
                    complementaryColor.withValues(alpha: 0.4),
                    primaryColor.withValues(alpha: 0.2),
                    complementaryColor.withValues(alpha: 0.4),
                  ],
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                ),
              ),
            ],
          ),
        );
      }
    }

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        minY: chartMinY,
        maxY: chartMaxY,
        barGroups: barGroups,
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              if (groupIndex < 0 || groupIndex >= data.length) return null;
              final dataPoint = data[groupIndex];
              final timeStr = DateFormat('EEE, MMM d').format(dataPoint.time);
              final dailyValue = dataPoint.value?.toStringAsFixed(1) ?? '--';
              final highValue = dataPoint.hourlyMax?.toStringAsFixed(1) ?? '--';
              final lowValue = dataPoint.hourlyMin?.toStringAsFixed(1) ?? '--';
              return BarTooltipItem(
                '$timeStr\nAvg: $dailyValue $unitLabel\nRange: $lowValue - $highValue $unitLabel',
                TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              );
            },
          ),
        ),
        gridData: FlGridData(
          show: showGrid,
          drawVerticalLine: false,
          horizontalInterval: _calculateInterval(chartMinY, chartMaxY),
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: isDark ? Colors.white12 : Colors.black12,
              strokeWidth: 1,
            );
          },
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            axisNameWidget: unitLabel.isNotEmpty
                ? Text(
                    unitLabel,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  )
                : null,
            axisNameSize: unitLabel.isNotEmpty ? 24 : 0,
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              interval: _calculateInterval(chartMinY, chartMaxY),
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toStringAsFixed(0),
                  style: TextStyle(
                    fontSize: 12,
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
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= data.length) {
                  return const SizedBox.shrink();
                }
                final time = data[index].time;
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    DateFormat('E').format(time),
                    style: TextStyle(
                      fontSize: 12,
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
      ),
    );
  }

  /// Build bar chart for hourly/daily data (non-combo mode)
  Widget _buildBarChart(
    BuildContext context,
    List<ForecastDataPoint> data,
    Color primaryColor,
    bool isDark,
    bool showGrid,
    String unitLabel,
    List<FlSpot> spots,
    double chartMinY,
    double chartMaxY,
    ConversionService conversions,
    bool isHourly,
  ) {
    final barGroups = <BarChartGroupData>[];
    final barWidth = isHourly ? 8.0 : 20.0;

    for (int i = 0; i < spots.length; i++) {
      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: spots[i].y,
              fromY: chartMinY,
              color: primaryColor,
              width: barWidth,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
            ),
          ],
        ),
      );
    }

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        minY: chartMinY,
        maxY: chartMaxY,
        barGroups: barGroups,
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              if (groupIndex < 0 || groupIndex >= data.length) return null;
              final dataPoint = data[groupIndex];
              final timeStr = isHourly
                  ? DateFormat('EEE h a').format(dataPoint.time)
                  : DateFormat('EEE, MMM d').format(dataPoint.time);
              final value = dataPoint.value?.toStringAsFixed(1) ?? '--';
              return BarTooltipItem(
                '$timeStr\n$value $unitLabel',
                TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              );
            },
          ),
        ),
        gridData: FlGridData(
          show: showGrid,
          drawVerticalLine: false,
          horizontalInterval: _calculateInterval(chartMinY, chartMaxY),
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: isDark ? Colors.white12 : Colors.black12,
              strokeWidth: 1,
            );
          },
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            axisNameWidget: unitLabel.isNotEmpty
                ? Text(
                    unitLabel,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  )
                : null,
            axisNameSize: unitLabel.isNotEmpty ? 24 : 0,
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              interval: _calculateInterval(chartMinY, chartMaxY),
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toStringAsFixed(0),
                  style: TextStyle(
                    fontSize: 12,
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
              interval: _calculateTimeInterval(data.length, isHourly),
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= data.length) {
                  return const SizedBox.shrink();
                }
                final time = data[index].time;
                final label = isHourly
                    ? DateFormat('ha').format(time).toLowerCase()
                    : DateFormat('E').format(time);
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
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
      ),
    );
  }

  double _calculateInterval(double min, double max) {
    final range = max - min;
    if (range <= 10) return 2;
    if (range <= 50) return 10;
    if (range <= 100) return 20;
    if (range <= 500) return 100;
    return (range / 5).roundToDouble();
  }

  double _calculateTimeInterval(int dataLength, bool isHourly) {
    if (isHourly) {
      if (dataLength <= 24) return 4;
      if (dataLength <= 48) return 6;
      if (dataLength <= 72) return 12;
      return 24;
    } else {
      if (dataLength <= 7) return 1;
      if (dataLength <= 14) return 2;
      return 3;
    }
  }
}
