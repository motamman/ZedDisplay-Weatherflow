/// Activity Score Service
///
/// Centralized service for calculating and caching activity scores.
/// Provides scores accessible from any widget via Provider.
///
/// NOTE: This is a stub implementation. Full implementation requires
/// adding activity tolerance storage and forecast integration.

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

  /// Get tolerances for an activity (stub - returns defaults)
  ActivityTolerances getActivityTolerance(ActivityType activity) {
    return DefaultTolerances.forActivity(activity);
  }

  /// Get list of enabled activities (stub - returns empty list)
  List<ActivityType> get enabledActivities => [];

  /// Initialize the service with dependencies
  void initialize(StorageService storage, WeatherFlowService weatherService) {
    _storage = storage;
    _weatherService = weatherService;
    // Listen for weather changes
    _weatherService?.addListener(_onWeatherChanged);
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

  void _calculateScores() {
    // Stub implementation - no scoring yet
    // Would need to implement:
    // 1. Get hourly forecast for selected hour from WeatherFlowService
    // 2. Get enabled activities from StorageService
    // 3. Score each activity
    // 4. Update _activityScores list
    notifyListeners();
  }

  @override
  void dispose() {
    _weatherService?.removeListener(_onWeatherChanged);
    super.dispose();
  }
}
