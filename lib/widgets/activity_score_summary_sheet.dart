/// Activity Score Summary Sheet
/// Shows parameter-by-parameter breakdown for an activity's score

import 'package:flutter/material.dart';
import 'package:weatherflow_core/weatherflow_core.dart';
import '../services/activity_scorer.dart';
import '../utils/conversion_extensions.dart';
import '../models/activity_definition.dart';
import '../models/activity_tolerances.dart';
import '../utils/date_time_formatter.dart';

/// Show a bottom sheet with activity score details
class ActivityScoreSummarySheet {
  /// Show as a draggable bottom sheet
  static Future<void> showAsSheet(
    BuildContext context, {
    required ActivityScore score,
    required ActivityTolerances tolerances,
    required ConversionService conversions,
    required DateTime forecastTime,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.3,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => _SummarySheetContent(
          score: score,
          tolerances: tolerances,
          conversions: conversions,
          scrollController: scrollController,
          forecastTime: forecastTime,
        ),
      ),
    );
  }
}

/// Main sheet content
class _SummarySheetContent extends StatelessWidget {
  final ActivityScore score;
  final ActivityTolerances tolerances;
  final ConversionService conversions;
  final ScrollController scrollController;
  final DateTime forecastTime;

  const _SummarySheetContent({
    required this.score,
    required this.tolerances,
    required this.conversions,
    required this.scrollController,
    required this.forecastTime,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? Colors.grey.shade900 : Colors.white;

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade400,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          _buildHeader(context),
          // Parameter list
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.all(16),
              children: _buildParameterCards(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: score.color.withValues(alpha: isDark ? 0.3 : 0.15),
        border: Border(
          bottom: BorderSide(color: score.color, width: 2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date and time row
          Row(
            children: [
              Icon(
                Icons.schedule,
                size: 16,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
              const SizedBox(width: 6),
              Text(
                _formatDateTime(forecastTime),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
              const Spacer(),
              // Close button
              IconButton(
                icon: const Icon(Icons.close),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Activity info row
          Row(
            children: [
              // Activity icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: score.color,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  score.icon,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              // Activity name and score
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      score.activity.displayName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          '${score.score.toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: score.color,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: score.color,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            score.label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Format the forecast time for display
  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final dtDate = DateTime(dt.year, dt.month, dt.day);

    // Day name
    String dayPart;
    if (dtDate == today) {
      dayPart = 'Today';
    } else if (dtDate == tomorrow) {
      dayPart = 'Tomorrow';
    } else {
      dayPart = '${DateTimeFormatter.getDayAbbrev(dt)}, ${DateTimeFormatter.formatDateShort(dt)}';
    }

    return '$dayPart at ${DateTimeFormatter.formatTime(dt)}';
  }

  List<Widget> _buildParameterCards(BuildContext context) {
    final cards = <Widget>[];

    // Build cards in display order
    for (final key in ActivityScore.parameterDisplayOrder) {
      if (!score.parameterScores.containsKey(key)) continue;

      final paramScore = score.parameterScores[key]!;
      final paramValue = score.parameterValues[key];

      cards.add(
        _ParameterCard(
          parameterKey: key,
          score: paramScore,
          rawValue: paramValue,
          tolerances: tolerances,
          conversions: conversions,
        ),
      );
    }

    return cards;
  }
}

/// Card showing a single parameter's score and details
class _ParameterCard extends StatelessWidget {
  final String parameterKey;
  final double score;
  final double? rawValue;
  final ActivityTolerances tolerances;
  final ConversionService conversions;

  const _ParameterCard({
    required this.parameterKey,
    required this.score,
    required this.rawValue,
    required this.tolerances,
    required this.conversions,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scoreColor = _getScoreColor(score);
    final tolerance = _getTolerance();
    final weight = _getWeight();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: scoreColor.withValues(alpha: isDark ? 0.15 : 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: scoreColor.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Expanded(
                  child: Text(
                    ActivityScore.getParameterDisplayName(parameterKey),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // Weight indicator
                if (weight > 0) ...[
                  _WeightIndicator(weight: weight),
                  const SizedBox(width: 12),
                ],
                // Score badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: scoreColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${score.toStringAsFixed(0)}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Current value
            Row(
              children: [
                const Text(
                  'Current: ',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                Text(
                  _formatValue(),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: scoreColor,
                  ),
                ),
              ],
            ),
            // Tolerance ranges
            if (tolerance != null) ...[
              const SizedBox(height: 8),
              _buildToleranceRanges(tolerance),
              const SizedBox(height: 12),
              // Visual progress bar
              _buildProgressBar(tolerance, scoreColor),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildToleranceRanges(RangeTolerance tolerance) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Ideal: ${_formatRange(tolerance.idealMin, tolerance.idealMax)}',
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: Colors.orange,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Acceptable: ${_formatRange(tolerance.acceptableMin, tolerance.acceptableMax)}',
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildProgressBar(RangeTolerance tolerance, Color scoreColor) {
    if (rawValue == null) return const SizedBox.shrink();

    // Calculate position as percentage of acceptable range
    final range = tolerance.acceptableMax - tolerance.acceptableMin;
    if (range <= 0) return const SizedBox.shrink();

    final position = ((rawValue! - tolerance.acceptableMin) / range).clamp(0.0, 1.0);

    // Calculate ideal range position
    final idealStart = (tolerance.idealMin - tolerance.acceptableMin) / range;
    final idealEnd = (tolerance.idealMax - tolerance.acceptableMin) / range;

    return SizedBox(
      height: 24,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;

          return Stack(
            children: [
              // Background (acceptable range)
              Container(
                height: 8,
                margin: const EdgeInsets.only(top: 8),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              // Ideal range
              Positioned(
                left: idealStart * width,
                width: (idealEnd - idealStart) * width,
                top: 8,
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              // Current value indicator
              Positioned(
                left: (position * width) - 8,
                top: 0,
                child: Container(
                  width: 16,
                  height: 24,
                  decoration: BoxDecoration(
                    color: scoreColor,
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  RangeTolerance? _getTolerance() {
    switch (parameterKey) {
      case 'cloudCover':
        return tolerances.cloudCover;
      case 'windSpeed':
        return tolerances.windSpeed;
      case 'temperature':
        return tolerances.temperature;
      case 'precipProbability':
        return tolerances.precipProbability;
      case 'uvIndex':
        return tolerances.uvIndex;
      case 'waveHeight':
        return tolerances.waveHeight;
      case 'wavePeriod':
        return tolerances.wavePeriod;
      default:
        return null;
    }
  }

  int _getWeight() {
    switch (parameterKey) {
      case 'cloudCover':
        return tolerances.cloudCover.weight;
      case 'windSpeed':
        return tolerances.windSpeed.weight;
      case 'temperature':
        return tolerances.temperature.weight;
      case 'precipProbability':
        return tolerances.precipProbability.weight;
      case 'precipType':
        return tolerances.precipType.weight;
      case 'uvIndex':
        return tolerances.uvIndex.weight;
      case 'waveHeight':
        return tolerances.waveHeight?.weight ?? 0;
      case 'wavePeriod':
        return tolerances.wavePeriod?.weight ?? 0;
      default:
        return 0;
    }
  }

  String _formatValue() {
    if (rawValue == null) return 'N/A';

    switch (parameterKey) {
      case 'cloudCover':
      case 'precipProbability':
        // Convert ratio to percentage
        return '${(rawValue! * 100).toStringAsFixed(0)}%';
      case 'windSpeed':
        final converted = conversions.convertWindSpeedFromMps(rawValue!);
        return '${converted?.toStringAsFixed(0) ?? rawValue!.toStringAsFixed(0)} ${conversions.windSpeedSymbol}';
      case 'temperature':
        final converted = conversions.convertTemperatureFromKelvin(rawValue!);
        return '${converted?.toStringAsFixed(0) ?? rawValue!.toStringAsFixed(0)}${conversions.temperatureSymbol}';
      case 'uvIndex':
        return rawValue!.toStringAsFixed(0);
      case 'waveHeight':
        return '${rawValue!.toStringAsFixed(1)} m';
      case 'wavePeriod':
        return '${rawValue!.toStringAsFixed(0)} s';
      case 'precipType':
        return _getWeatherDescription(rawValue!.toInt());
      default:
        return rawValue!.toStringAsFixed(1);
    }
  }

  String _formatRange(double min, double max) {
    switch (parameterKey) {
      case 'cloudCover':
      case 'precipProbability':
        return '${(min * 100).toStringAsFixed(0)}-${(max * 100).toStringAsFixed(0)}%';
      case 'windSpeed':
        final minC = conversions.convertWindSpeedFromMps(min)?.toStringAsFixed(0) ?? min.toStringAsFixed(0);
        final maxC = conversions.convertWindSpeedFromMps(max)?.toStringAsFixed(0) ?? max.toStringAsFixed(0);
        return '$minC-$maxC ${conversions.windSpeedSymbol}';
      case 'temperature':
        final minC = conversions.convertTemperatureFromKelvin(min)?.toStringAsFixed(0) ?? min.toStringAsFixed(0);
        final maxC = conversions.convertTemperatureFromKelvin(max)?.toStringAsFixed(0) ?? max.toStringAsFixed(0);
        return '$minC-$maxC${conversions.temperatureSymbol}';
      case 'uvIndex':
        return '${min.toStringAsFixed(0)}-${max.toStringAsFixed(0)}';
      case 'waveHeight':
        return '${min.toStringAsFixed(1)}-${max.toStringAsFixed(1)} m';
      case 'wavePeriod':
        return '${min.toStringAsFixed(0)}-${max.toStringAsFixed(0)} s';
      default:
        return '${min.toStringAsFixed(1)}-${max.toStringAsFixed(1)}';
    }
  }

  String _getWeatherDescription(int code) {
    // WMO weather codes
    if (code <= 3) return 'Clear/Cloudy';
    if (code <= 48) return 'Fog';
    if (code <= 57) return 'Drizzle';
    if (code <= 67) return 'Rain';
    if (code <= 77) return 'Snow';
    if (code <= 86) return 'Snow Showers';
    if (code <= 99) return 'Thunderstorm';
    return 'Unknown';
  }

  Color _getScoreColor(double score) {
    if (score >= 90) return Colors.green;
    if (score >= 80) return const Color(0xFFFFEB3B); // Yellow
    if (score >= 70) return const Color(0xFFFF9800); // Orange
    if (score >= 60) return const Color(0xFFE65100); // Burnt orange
    if (score >= 50) return Colors.red;
    return const Color(0xFF7B1FA2); // Violet
  }
}

/// Visual weight indicator (dots)
class _WeightIndicator extends StatelessWidget {
  final int weight;

  const _WeightIndicator({required this.weight});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Importance: $weight/10',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(5, (index) {
          final filled = index < (weight / 2).ceil();
          return Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(right: 2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: filled ? Colors.grey.shade600 : Colors.grey.shade300,
            ),
          );
        }),
      ),
    );
  }
}
