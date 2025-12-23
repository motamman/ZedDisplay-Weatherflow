/// Activity Scorer Service
///
/// Scores forecast conditions against user-defined activity tolerances
/// to produce color-coded suitability indicators.

import 'package:flutter/material.dart';
import '../widgets/forecast_models.dart';
import '../models/marine_data.dart';
import '../models/activity_definition.dart';
import '../models/activity_tolerances.dart';

/// Score level with associated color
enum ScoreLevel {
  excellent(90, Colors.green, 'Excellent'),
  good(80, Color(0xFFFFEB3B), 'Good'), // Yellow
  ok(70, Color(0xFFFF9800), 'OK'), // Orange
  poor(60, Color(0xFFE65100), 'Poor'), // Burnt orange
  bad(50, Colors.red, 'Bad'),
  dangerous(0, Color(0xFF7B1FA2), 'Dangerous'); // Violet

  final int minScore;
  final Color color;
  final String label;

  const ScoreLevel(this.minScore, this.color, this.label);

  /// Get score level from numeric score
  static ScoreLevel fromScore(double score) {
    if (score >= 90) return ScoreLevel.excellent;
    if (score >= 80) return ScoreLevel.good;
    if (score >= 70) return ScoreLevel.ok;
    if (score >= 60) return ScoreLevel.poor;
    if (score >= 50) return ScoreLevel.bad;
    return ScoreLevel.dangerous;
  }
}

/// Score result for a single activity
class ActivityScore {
  final ActivityType activity;
  final double score;
  final ScoreLevel level;
  final Map<String, double> parameterScores;
  final Map<String, double?> parameterValues; // Raw values in SI units

  const ActivityScore({
    required this.activity,
    required this.score,
    required this.level,
    this.parameterScores = const {},
    this.parameterValues = const {},
  });

  /// Activity icon
  IconData get icon => activity.icon;

  /// Score color
  Color get color => level.color;

  /// Score label
  String get label => level.label;

  /// Get display name for a parameter key
  static String getParameterDisplayName(String key) {
    const names = {
      'cloudCover': 'Cloud Cover',
      'windSpeed': 'Wind Speed',
      'temperature': 'Feels Like',
      'precipProbability': 'Precip Chance',
      'precipType': 'Weather Type',
      'uvIndex': 'UV Index',
      'waveHeight': 'Wave Height',
      'wavePeriod': 'Wave Period',
    };
    return names[key] ?? key;
  }

  /// Get the order for displaying parameters
  static List<String> get parameterDisplayOrder => [
    'temperature',
    'windSpeed',
    'cloudCover',
    'precipProbability',
    'precipType',
    'uvIndex',
    'waveHeight',
    'wavePeriod',
  ];
}

/// Service for scoring activities against forecast conditions
class ActivityScorerService {
  /// Score a single parameter value against a range tolerance
  double scoreParameter(double? value, RangeTolerance tolerance) {
    if (value == null) return 100.0; // No data = no penalty
    if (tolerance.weight == 0) return 100.0; // Ignored parameter

    // Within ideal range = 100%
    if (value >= tolerance.idealMin && value <= tolerance.idealMax) {
      return 100.0;
    }

    // Outside acceptable range = 0%
    if (value < tolerance.acceptableMin || value > tolerance.acceptableMax) {
      return 0.0;
    }

    // Linear interpolation in buffer zones
    if (value < tolerance.idealMin) {
      // Below ideal but above acceptable min
      return 100.0 *
          (value - tolerance.acceptableMin) /
          (tolerance.idealMin - tolerance.acceptableMin);
    } else {
      // Above ideal but below acceptable max
      return 100.0 *
          (tolerance.acceptableMax - value) /
          (tolerance.acceptableMax - tolerance.idealMax);
    }
  }

  /// Score precipitation type against tolerance
  double scorePrecipType(int? weatherCode, PrecipitationTolerance tolerance) {
    if (weatherCode == null) return 100.0;
    if (tolerance.weight == 0) return 100.0;

    return tolerance.acceptableCodes.contains(weatherCode) ? 100.0 : 0.0;
  }

  /// Calculate Beaufort scale from wind speed (m/s)
  int windSpeedToBeaufort(double windSpeed) {
    if (windSpeed < 0.5) return 0;
    if (windSpeed < 1.6) return 1;
    if (windSpeed < 3.4) return 2;
    if (windSpeed < 5.5) return 3;
    if (windSpeed < 8.0) return 4;
    if (windSpeed < 10.8) return 5;
    if (windSpeed < 13.9) return 6;
    if (windSpeed < 17.2) return 7;
    if (windSpeed < 20.8) return 8;
    if (windSpeed < 24.5) return 9;
    if (windSpeed < 28.5) return 10;
    if (windSpeed < 32.7) return 11;
    return 12;
  }

  /// Calculate Douglas scale from wave height (meters)
  int waveHeightToDouglas(double waveHeight) {
    if (waveHeight < 0.1) return 0;
    if (waveHeight < 0.5) return 1;
    if (waveHeight < 1.25) return 2;
    if (waveHeight < 2.5) return 3;
    if (waveHeight < 4.0) return 4;
    if (waveHeight < 6.0) return 5;
    if (waveHeight < 9.0) return 6;
    if (waveHeight < 14.0) return 7;
    return 8;
  }

  /// Score an activity for a given forecast hour
  ActivityScore scoreActivity({
    required ActivityTolerances tolerances,
    required HourlyForecast weather,
    HourlyMarine? marine,
    double? latitude,
    int? month,
  }) {
    final parameterScores = <String, double>{};
    final parameterValues = <String, double?>{};
    var totalWeight = 0;
    var weightedSum = 0.0;

    // Get seasonal temperature offset
    double tempOffset = 0.0;
    if (latitude != null && month != null) {
      final season = tolerances.seasonalProfile.getEffectiveSeason(latitude, month);
      tempOffset = season.temperatureOffset;
    }

    // Score cloud cover - WeatherFlow doesn't have cloud cover, skip
    // final cloudScore = scoreParameter(weather.cloudCover, tolerances.cloudCover);
    // parameterScores['cloudCover'] = cloudScore;
    // parameterValues['cloudCover'] = weather.cloudCover;
    // totalWeight += tolerances.cloudCover.weight;
    // weightedSum += cloudScore * tolerances.cloudCover.weight;

    // Score wind speed
    final windScore = scoreParameter(weather.windSpeed, tolerances.windSpeed);
    parameterScores['windSpeed'] = windScore;
    parameterValues['windSpeed'] = weather.windSpeed;
    totalWeight += tolerances.windSpeed.weight;
    weightedSum += windScore * tolerances.windSpeed.weight;

    // Score temperature (with seasonal offset)
    // Adjust the tolerance range by the offset instead of the value
    final adjustedTempTolerance = tolerances.temperature.copyWith(
      idealMin: tolerances.temperature.idealMin + tempOffset,
      idealMax: tolerances.temperature.idealMax + tempOffset,
      acceptableMin: tolerances.temperature.acceptableMin + tempOffset,
      acceptableMax: tolerances.temperature.acceptableMax + tempOffset,
    );
    final tempValue = weather.feelsLike ?? weather.temperature;
    final tempScore = scoreParameter(tempValue, adjustedTempTolerance);
    parameterScores['temperature'] = tempScore;
    parameterValues['temperature'] = tempValue;
    totalWeight += tolerances.temperature.weight;
    weightedSum += tempScore * tolerances.temperature.weight;

    // Score precipitation probability
    final precipProbScore = scoreParameter(
      weather.precipProbability,
      tolerances.precipProbability,
    );
    parameterScores['precipProbability'] = precipProbScore;
    parameterValues['precipProbability'] = weather.precipProbability;
    totalWeight += tolerances.precipProbability.weight;
    weightedSum += precipProbScore * tolerances.precipProbability.weight;

    // Score precipitation type - use icon/conditions to infer weather code
    // WeatherFlow doesn't have WMO codes, so we skip this for now
    // final precipTypeScore = scorePrecipType(
    //   weather.weatherCode,
    //   tolerances.precipType,
    // );
    // parameterScores['precipType'] = precipTypeScore;
    // parameterValues['precipType'] = weather.weatherCode?.toDouble();
    // totalWeight += tolerances.precipType.weight;
    // weightedSum += precipTypeScore * tolerances.precipType.weight;

    // Score UV index - WeatherFlow doesn't have UV in forecast, skip
    // final uvScore = scoreParameter(weather.uvIndex, tolerances.uvIndex);
    // parameterScores['uvIndex'] = uvScore;
    // parameterValues['uvIndex'] = weather.uvIndex;
    // totalWeight += tolerances.uvIndex.weight;
    // weightedSum += uvScore * tolerances.uvIndex.weight;

    // Score marine parameters if applicable
    if (tolerances.activity.requiresMarineData && marine != null) {
      // Wave height
      if (tolerances.waveHeight != null) {
        final waveHeightScore = scoreParameter(
          marine.waveHeight,
          tolerances.waveHeight!,
        );
        parameterScores['waveHeight'] = waveHeightScore;
        parameterValues['waveHeight'] = marine.waveHeight;
        totalWeight += tolerances.waveHeight!.weight;
        weightedSum += waveHeightScore * tolerances.waveHeight!.weight;
      }

      // Wave period
      if (tolerances.wavePeriod != null) {
        final wavePeriodScore = scoreParameter(
          marine.wavePeriod,
          tolerances.wavePeriod!,
        );
        parameterScores['wavePeriod'] = wavePeriodScore;
        parameterValues['wavePeriod'] = marine.wavePeriod;
        totalWeight += tolerances.wavePeriod!.weight;
        weightedSum += wavePeriodScore * tolerances.wavePeriod!.weight;
      }
    }

    // Calculate final score
    final finalScore = totalWeight > 0 ? weightedSum / totalWeight : 100.0;

    return ActivityScore(
      activity: tolerances.activity,
      score: finalScore,
      level: ScoreLevel.fromScore(finalScore),
      parameterScores: parameterScores,
      parameterValues: parameterValues,
    );
  }

  /// Score all enabled activities for a forecast hour
  List<ActivityScore> scoreHour({
    required List<ActivityTolerances> enabledActivities,
    required HourlyForecast weather,
    HourlyMarine? marine,
    double? latitude,
    int? month,
  }) {
    final scores = <ActivityScore>[];

    for (final tolerances in enabledActivities) {
      if (!tolerances.enabled) continue;

      // Skip marine activities if no marine data
      if (tolerances.activity.requiresMarineData && marine == null) {
        continue;
      }

      scores.add(scoreActivity(
        tolerances: tolerances,
        weather: weather,
        marine: marine,
        latitude: latitude,
        month: month,
      ));
    }

    return scores;
  }

  /// Find the hourly marine data matching a weather forecast time
  HourlyMarine? findMarineForHour(MarineData? marineData, DateTime time) {
    if (marineData == null) return null;

    for (final marine in marineData.hourly) {
      if (marine.time.hour == time.hour &&
          marine.time.day == time.day &&
          marine.time.month == time.month &&
          marine.time.year == time.year) {
        return marine;
      }
    }

    return null;
  }
}
