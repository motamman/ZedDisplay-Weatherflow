/// Activity Score Service
///
/// Centralized service for calculating and caching activity scores.
/// Provides scores accessible from any widget via Provider.

import 'package:flutter/foundation.dart';
import 'package:weatherflow_core/weatherflow_core.dart' hide HourlyForecast;
import 'activity_scorer.dart';
import 'storage_service.dart';
import 'weatherflow_service.dart';
import '../models/activity_definition.dart';
import '../models/activity_tolerances.dart';
import '../models/marine_data.dart';
import '../widgets/forecast_models.dart';

/// Centralized service for activity scoring
class ActivityScoreService extends ChangeNotifier {
  // Dependencies
  final ActivityScorerService _scorer = ActivityScorerService();
  StorageService? _storage;
  WeatherFlowService? _weatherService;

  // State
  int _selectedHourOffset = 0;
  List<ActivityScore> _activityScores = [];
  HourlyForecast? _currentWeather;
  HourlyMarine? _currentMarine;

  // Getters
  List<ActivityScore> get activityScores => _activityScores;
  int get selectedHourOffset => _selectedHourOffset;
  HourlyForecast? get currentWeather => _currentWeather;
  HourlyMarine? get currentMarine => _currentMarine;

  /// Get tolerances for an activity from storage
  ActivityTolerances getActivityTolerance(ActivityType activity) {
    return _storage?.getActivityTolerance(activity) ??
           DefaultTolerances.forActivity(activity);
  }

  /// Get list of enabled activities from storage
  List<ActivityType> get enabledActivities {
    if (_storage == null) return [];
    return _storage!.enabledActivities
        .map((key) => ActivityTypeExtension.fromKey(key))
        .where((a) => a != null)
        .cast<ActivityType>()
        .toList();
  }

  /// Initialize the service with dependencies
  void initialize(StorageService storage, WeatherFlowService weatherService) {
    // Remove old listeners if reinitializing
    _weatherService?.removeListener(_onWeatherChanged);
    _storage?.removeListener(_onStorageChanged);

    _storage = storage;
    _weatherService = weatherService;

    // Listen for weather and storage changes
    _weatherService?.addListener(_onWeatherChanged);
    _storage?.addListener(_onStorageChanged);

    // Initial calculation
    _calculateScores();
  }

  /// Update the selected hour offset and recalculate scores
  void updateSelectedHour(int hourOffset) {
    if (hourOffset == _selectedHourOffset) return;
    _selectedHourOffset = hourOffset;
    _calculateScores();
  }

  void _onWeatherChanged() {
    _calculateScores();
  }

  void _onStorageChanged() {
    // Recalculate when activities are enabled/disabled or tolerances change
    _calculateScores();
  }

  void _calculateScores() {
    if (_storage == null || _weatherService == null) {
      _activityScores = [];
      _currentWeather = null;
      notifyListeners();
      return;
    }

    // Get hourly forecasts
    final hourlyForecasts = _weatherService!.displayHourlyForecasts;
    if (hourlyForecasts.isEmpty) {
      _activityScores = [];
      _currentWeather = null;
      notifyListeners();
      return;
    }

    // Get forecast for selected hour
    final hourIndex = _selectedHourOffset.clamp(0, hourlyForecasts.length - 1);
    _currentWeather = hourlyForecasts[hourIndex];

    // Get enabled activities
    final enabled = enabledActivities;
    if (enabled.isEmpty) {
      _activityScores = [];
      notifyListeners();
      return;
    }

    // Score each enabled activity
    final scores = <ActivityScore>[];
    for (final activity in enabled) {
      final tolerance = getActivityTolerance(activity);
      final score = _scoreActivity(activity, tolerance, _currentWeather!);
      scores.add(score);
    }

    _activityScores = scores;
    notifyListeners();
  }

  /// Score a single activity based on current weather
  ActivityScore _scoreActivity(
    ActivityType activity,
    ActivityTolerances tolerance,
    HourlyForecast weather,
  ) {
    final parameterScores = <String, double>{};
    final parameterValues = <String, double?>{};
    double totalWeight = 0;
    double weightedSum = 0;

    // Score temperature (already in Kelvin from weatherflow_core)
    if (weather.temperature != null) {
      parameterValues['temperature'] = weather.temperature;
      final tempScore = _scorer.scoreParameter(weather.temperature!, tolerance.temperature);
      parameterScores['temperature'] = tempScore;
      weightedSum += tempScore * tolerance.temperature.weight;
      totalWeight += tolerance.temperature.weight;
    }

    // Score wind speed (already in m/s from weatherflow_core)
    if (weather.windSpeed != null) {
      parameterValues['windSpeed'] = weather.windSpeed;
      final windScore = _scorer.scoreParameter(weather.windSpeed!, tolerance.windSpeed);
      parameterScores['windSpeed'] = windScore;
      weightedSum += windScore * tolerance.windSpeed.weight;
      totalWeight += tolerance.windSpeed.weight;
    }

    // Score precipitation probability (already 0-1 ratio from weatherflow_core)
    if (weather.precipProbability != null) {
      parameterValues['precipProbability'] = weather.precipProbability;
      final precipScore = _scorer.scoreParameter(weather.precipProbability!, tolerance.precipProbability);
      parameterScores['precipProbability'] = precipScore;
      weightedSum += precipScore * tolerance.precipProbability.weight;
      totalWeight += tolerance.precipProbability.weight;
    }

    // Score humidity as proxy for cloud cover (already 0-1 ratio from weatherflow_core)
    if (weather.humidity != null) {
      parameterValues['cloudCover'] = weather.humidity;
      final cloudScore = _scorer.scoreParameter(weather.humidity!, tolerance.cloudCover);
      parameterScores['cloudCover'] = cloudScore;
      weightedSum += cloudScore * tolerance.cloudCover.weight;
      totalWeight += tolerance.cloudCover.weight;
    }

    // Calculate overall score
    final overallScore = totalWeight > 0 ? weightedSum / totalWeight : 100.0;

    // Determine score level
    final level = _getScoreLevel(overallScore);

    return ActivityScore(
      activity: activity,
      score: overallScore,
      level: level,
      parameterScores: parameterScores,
      parameterValues: parameterValues,
    );
  }

  /// Convert score to level
  ScoreLevel _getScoreLevel(double score) {
    return ScoreLevel.fromScore(score);
  }

  @override
  void dispose() {
    _weatherService?.removeListener(_onWeatherChanged);
    _storage?.removeListener(_onStorageChanged);
    super.dispose();
  }
}
