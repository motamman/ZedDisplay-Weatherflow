/// Condition Card Widget
///
/// Modern card design for displaying weather condition variables.
/// Features gradient backgrounds, custom icons, and value indicators.

import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:weatherflow_core/weatherflow_core.dart';
import '../services/observation_history_service.dart';

/// Configuration for a condition variable's visual styling
class ConditionStyle {
  final IconData icon;
  final Color lowColor;
  final Color midColor;
  final Color highColor;
  final double minRange;
  final double maxRange;
  final String Function(double, String) formatValue;

  const ConditionStyle({
    required this.icon,
    required this.lowColor,
    required this.midColor,
    required this.highColor,
    required this.minRange,
    required this.maxRange,
    required this.formatValue,
  });

  /// Get interpolated color based on value
  Color getColorForValue(double value) {
    final normalized = ((value - minRange) / (maxRange - minRange)).clamp(0.0, 1.0);
    if (normalized < 0.5) {
      return Color.lerp(lowColor, midColor, normalized * 2)!;
    } else {
      return Color.lerp(midColor, highColor, (normalized - 0.5) * 2)!;
    }
  }

  /// Get fill percentage (0-1) for indicator
  double getFillForValue(double value) {
    return ((value - minRange) / (maxRange - minRange)).clamp(0.0, 1.0);
  }
}

/// Get styling for a condition variable
ConditionStyle getStyleForVariable(ConditionVariable variable) {
  switch (variable) {
    case ConditionVariable.temperature:
    case ConditionVariable.feelsLike:
      return ConditionStyle(
        icon: Icons.thermostat,
        lowColor: Colors.blue.shade300,
        midColor: Colors.green.shade400,
        highColor: Colors.red.shade500,
        minRange: 250, // ~-10°F in Kelvin
        maxRange: 315, // ~110°F in Kelvin
        formatValue: (v, u) => '${v.toStringAsFixed(0)}$u',
      );

    case ConditionVariable.humidity:
      return ConditionStyle(
        icon: Icons.water_drop,
        lowColor: Colors.brown.shade300,
        midColor: Colors.blue.shade300,
        highColor: Colors.blue.shade700,
        minRange: 0,
        maxRange: 1, // 0-100% as 0-1
        formatValue: (v, u) => '${(v * 100).toStringAsFixed(0)}$u',
      );

    case ConditionVariable.dewPoint:
      return ConditionStyle(
        icon: Icons.opacity,
        lowColor: Colors.blue.shade200,
        midColor: Colors.blue.shade400,
        highColor: Colors.blue.shade600,
        minRange: 250,
        maxRange: 300,
        formatValue: (v, u) => '${v.toStringAsFixed(0)}$u',
      );

    case ConditionVariable.pressure:
      return ConditionStyle(
        icon: Icons.compress,
        lowColor: Colors.purple.shade300,
        midColor: Colors.purple.shade500,
        highColor: Colors.purple.shade700,
        minRange: 98000, // Low pressure in Pa
        maxRange: 104000, // High pressure in Pa
        formatValue: (v, u) => '${v.toStringAsFixed(0)} $u',
      );

    case ConditionVariable.windSpeed:
      return ConditionStyle(
        icon: Icons.air,
        lowColor: Colors.green.shade300,
        midColor: Colors.orange.shade400,
        highColor: Colors.red.shade600,
        minRange: 0,
        maxRange: 25, // m/s
        formatValue: (v, u) => '${v.toStringAsFixed(1)} $u',
      );

    case ConditionVariable.windGust:
      return ConditionStyle(
        icon: Icons.air,
        lowColor: Colors.orange.shade300,
        midColor: Colors.orange.shade500,
        highColor: Colors.red.shade700,
        minRange: 0,
        maxRange: 35,
        formatValue: (v, u) => '${v.toStringAsFixed(1)} $u',
      );

    case ConditionVariable.windDirection:
      return ConditionStyle(
        icon: Icons.navigation,
        lowColor: Colors.teal.shade400,
        midColor: Colors.teal.shade400,
        highColor: Colors.teal.shade400,
        minRange: 0,
        maxRange: 360,
        formatValue: (v, u) => _getDirectionLabel(v),
      );

    case ConditionVariable.rainRate:
      return ConditionStyle(
        icon: Icons.umbrella,
        lowColor: Colors.blue.shade200,
        midColor: Colors.blue.shade400,
        highColor: Colors.blue.shade800,
        minRange: 0,
        maxRange: 0.05, // m/hr (heavy rain)
        formatValue: (v, u) => '${(v * 1000).toStringAsFixed(1)} $u',
      );

    case ConditionVariable.rainAccumulated:
      return ConditionStyle(
        icon: Icons.water,
        lowColor: Colors.blue.shade200,
        midColor: Colors.blue.shade400,
        highColor: Colors.blue.shade700,
        minRange: 0,
        maxRange: 0.1, // 100mm max
        formatValue: (v, u) => '${(v * 1000).toStringAsFixed(1)} $u',
      );

    case ConditionVariable.precipType:
      return ConditionStyle(
        icon: Icons.grain,
        lowColor: Colors.grey.shade400,   // none
        midColor: Colors.blue.shade500,   // rain
        highColor: Colors.cyan.shade300,  // snow/sleet
        minRange: 0,
        maxRange: 6,
        formatValue: (v, u) => ObservationHistoryService.precipTypeLabel(v),
      );

    case ConditionVariable.uvIndex:
      return ConditionStyle(
        icon: Icons.wb_sunny,
        lowColor: Colors.green.shade400,
        midColor: Colors.yellow.shade600,
        highColor: Colors.purple.shade600,
        minRange: 0,
        maxRange: 11,
        formatValue: (v, u) => v.toStringAsFixed(1),
      );

    case ConditionVariable.solarRadiation:
      return ConditionStyle(
        icon: Icons.solar_power,
        lowColor: Colors.yellow.shade300,
        midColor: Colors.orange.shade400,
        highColor: Colors.deepOrange.shade600,
        minRange: 0,
        maxRange: 1200,
        formatValue: (v, u) => '${v.toStringAsFixed(0)} $u',
      );

    case ConditionVariable.illuminance:
      return ConditionStyle(
        icon: Icons.lightbulb,
        lowColor: Colors.grey.shade400,
        midColor: Colors.yellow.shade400,
        highColor: Colors.yellow.shade100,
        minRange: 0,
        maxRange: 100000,
        formatValue: (v, u) => '${_formatLargeNumber(v)} $u',
      );

    case ConditionVariable.lightningDistance:
      return ConditionStyle(
        icon: Icons.flash_on,
        lowColor: Colors.red.shade600,
        midColor: Colors.yellow.shade600,
        highColor: Colors.grey.shade400,
        minRange: 0,
        maxRange: 50000, // 50km in meters
        formatValue: (v, u) => '${(v / 1000).toStringAsFixed(1)} $u',
      );

    case ConditionVariable.lightningCount:
      return ConditionStyle(
        icon: Icons.bolt,
        lowColor: Colors.grey.shade400,
        midColor: Colors.yellow.shade500,
        highColor: Colors.red.shade600,
        minRange: 0,
        maxRange: 50,
        formatValue: (v, u) => v.toStringAsFixed(0),
      );

    case ConditionVariable.batteryVoltage:
      return ConditionStyle(
        icon: Icons.battery_full,
        lowColor: Colors.red.shade500,
        midColor: Colors.yellow.shade500,
        highColor: Colors.green.shade500,
        minRange: 2.0,
        maxRange: 2.8,
        formatValue: (v, u) => '${v.toStringAsFixed(2)} $u',
      );
  }
}

String _getDirectionLabel(double degrees) {
  const directions = ['N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE',
                      'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW'];
  final index = ((degrees + 11.25) / 22.5).floor() % 16;
  return '${directions[index]} ${degrees.toStringAsFixed(0)}°';
}

String _formatLargeNumber(double value) {
  if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}k';
  return value.toStringAsFixed(0);
}

/// Modern condition card widget
class ConditionCard extends StatelessWidget {
  final ConditionVariable variable;
  final double? value;  // Raw SI value
  final ConversionService? conversions;  // For formatting display values
  final VoidCallback? onTap;
  final bool compact;
  final bool showIndicator;
  final double? secondaryValue; // For wind direction, gust, etc.

  const ConditionCard({
    super.key,
    required this.variable,
    required this.value,
    this.conversions,
    this.onTap,
    this.compact = false,
    this.showIndicator = true,
    this.secondaryValue,
  });

  /// Format value for display using ConversionService
  String _formatValue(double val) {
    if (conversions == null) {
      // Fallback - simple format
      return val.toStringAsFixed(1);
    }

    switch (variable) {
      case ConditionVariable.temperature:
      case ConditionVariable.feelsLike:
      case ConditionVariable.dewPoint:
        return conversions!.formatTemperature(val);
      case ConditionVariable.humidity:
        return conversions!.formatHumidity(val);
      case ConditionVariable.pressure:
        return conversions!.formatPressure(val);
      case ConditionVariable.windSpeed:
      case ConditionVariable.windGust:
        return conversions!.formatWindSpeed(val);
      case ConditionVariable.windDirection:
        return '${val.toStringAsFixed(0)}°';
      case ConditionVariable.rainRate:
      case ConditionVariable.rainAccumulated:
        return conversions!.formatRainfall(val);
      case ConditionVariable.uvIndex:
        return val.toStringAsFixed(1);
      case ConditionVariable.solarRadiation:
        return '${val.toStringAsFixed(0)} W/m²';
      case ConditionVariable.illuminance:
        return '${_formatLargeNumber(val)} lux';
      case ConditionVariable.lightningDistance:
        return conversions!.formatDistance(val);
      case ConditionVariable.lightningCount:
        return val.toStringAsFixed(0);
      case ConditionVariable.batteryVoltage:
        return '${val.toStringAsFixed(2)} V';
      case ConditionVariable.precipType:
        return ObservationHistoryService.precipTypeLabel(val);
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = getStyleForVariable(variable);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Determine colors
    final valueColor = value != null
        ? style.getColorForValue(value!)
        : (isDark ? Colors.grey.shade600 : Colors.grey.shade400);

    final backgroundColor = isDark
        ? Colors.grey.shade900.withValues(alpha: 0.6)
        : Colors.white.withValues(alpha: 0.9);

    final textColor = isDark ? Colors.white : Colors.black87;
    final labelColor = isDark ? Colors.white70 : Colors.black54;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: EdgeInsets.all(compact ? 6 : 8),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: valueColor.withValues(alpha: 0.3),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: valueColor.withValues(alpha: 0.15),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Column(
                mainAxisSize: MainAxisSize.max,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header row: icon + label
                  Row(
                    children: [
                      Icon(
                        style.icon,
                        size: compact ? 14 : 18,
                        color: valueColor,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          variable.label,
                          style: TextStyle(
                            fontSize: compact ? 9 : 11,
                            fontWeight: FontWeight.w500,
                            color: labelColor,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),

                  // Value display
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value != null ? _formatValue(value!) : '--',
                      style: TextStyle(
                        fontSize: compact ? 16 : 20,
                        fontWeight: FontWeight.bold,
                        color: value != null ? textColor : Colors.grey,
                      ),
                    ),
                  ),

                  // Secondary value (e.g., wind direction for wind speed)
                  if (secondaryValue != null && variable == ConditionVariable.windSpeed) ...[
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Transform.rotate(
                          angle: (secondaryValue! + 180) * math.pi / 180,
                          child: Icon(
                            Icons.navigation,
                            size: compact ? 10 : 12,
                            color: valueColor,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Text(
                          _getDirectionLabel(secondaryValue!).split(' ').first,
                          style: TextStyle(
                            fontSize: compact ? 9 : 10,
                            color: labelColor,
                          ),
                        ),
                      ],
                    ),
                  ],

                  // Indicator bar
                  if (showIndicator && value != null && !compact) ...[
                    const Spacer(),
                    _buildIndicator(style, valueColor, isDark),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildIndicator(ConditionStyle style, Color valueColor, bool isDark) {
    final fill = style.getFillForValue(value!);

    // Special indicator for wind direction
    if (variable == ConditionVariable.windDirection) {
      return _buildCompassIndicator(value!, valueColor, isDark);
    }

    // Special indicator for battery
    if (variable == ConditionVariable.batteryVoltage) {
      return _buildBatteryIndicator(fill, valueColor, isDark);
    }

    // Default bar indicator
    return Container(
      height: 4,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(2),
        color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: fill,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            gradient: LinearGradient(
              colors: [
                style.lowColor,
                style.midColor,
                style.highColor,
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompassIndicator(double degrees, Color color, bool isDark) {
    return SizedBox(
      height: 24,
      child: Center(
        child: Transform.rotate(
          angle: (degrees + 180) * math.pi / 180,
          child: Icon(
            Icons.navigation,
            size: 20,
            color: color,
          ),
        ),
      ),
    );
  }

  Widget _buildBatteryIndicator(double fill, Color color, bool isDark) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 12,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
                width: 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: fill,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(1),
                    color: color,
                  ),
                ),
              ),
            ),
          ),
        ),
        Container(
          width: 4,
          height: 6,
          margin: const EdgeInsets.only(left: 1),
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.horizontal(right: Radius.circular(1)),
            color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
          ),
        ),
      ],
    );
  }
}

/// Grid of condition cards
class ConditionCardGrid extends StatelessWidget {
  final List<ConditionCardData> cards;
  final ConversionService? conversions;
  final int crossAxisCount;
  final double spacing;
  final bool compact;
  final void Function(ConditionVariable)? onCardTap;

  const ConditionCardGrid({
    super.key,
    required this.cards,
    this.conversions,
    this.crossAxisCount = 3,
    this.spacing = 8,
    this.compact = false,
    this.onCardTap,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.all(spacing),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: spacing,
        mainAxisSpacing: spacing,
        childAspectRatio: compact ? 1.4 : 1.2,
      ),
      itemCount: cards.length,
      itemBuilder: (context, index) {
        final data = cards[index];
        return ConditionCard(
          variable: data.variable,
          value: data.value,
          conversions: conversions,
          compact: compact,
          secondaryValue: data.secondaryValue,
          onTap: onCardTap != null ? () => onCardTap!(data.variable) : null,
        );
      },
    );
  }
}

/// Data for a single condition card
class ConditionCardData {
  final ConditionVariable variable;
  final double? value;  // Raw SI value
  final double? secondaryValue;

  const ConditionCardData({
    required this.variable,
    this.value,
    this.secondaryValue,
  });
}
