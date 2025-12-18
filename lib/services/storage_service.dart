import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:weatherflow_core/weatherflow_core.dart';

/// Keys for Hive storage boxes
class StorageKeys {
  static const String settings = 'settings';
  static const String stations = 'stations';
  static const String observations = 'observations';
  static const String forecasts = 'forecasts';
  static const String dashboards = 'dashboards';

  // Settings keys
  static const String apiToken = 'api_token';
  static const String selectedStationId = 'selected_station_id';
  static const String unitPreferences = 'unit_preferences';
  static const String themeMode = 'theme_mode';
  static const String udpEnabled = 'udp_enabled';
  static const String udpPort = 'udp_port';
  static const String refreshInterval = 'refresh_interval';
}

/// Storage service using Hive for local persistence
class StorageService extends ChangeNotifier {
  late Box<String> _settingsBox;
  late Box<String> _stationsBox;
  late Box<String> _observationsBox;
  late Box<String> _forecastsBox;
  late Box<String> _dashboardsBox;

  bool _initialized = false;

  /// Whether storage has been initialized
  bool get isInitialized => _initialized;

  /// Initialize Hive and open boxes
  Future<void> initialize() async {
    if (_initialized) return;

    await Hive.initFlutter('weatherflow');

    _settingsBox = await Hive.openBox<String>(StorageKeys.settings);
    _stationsBox = await Hive.openBox<String>(StorageKeys.stations);
    _observationsBox = await Hive.openBox<String>(StorageKeys.observations);
    _forecastsBox = await Hive.openBox<String>(StorageKeys.forecasts);
    _dashboardsBox = await Hive.openBox<String>(StorageKeys.dashboards);

    _initialized = true;
    debugPrint('StorageService: Initialized');
  }

  // ============ API Token ============

  /// Get saved API token
  String? get apiToken => _settingsBox.get(StorageKeys.apiToken);

  /// Save API token
  Future<void> setApiToken(String token) async {
    await _settingsBox.put(StorageKeys.apiToken, token);
    notifyListeners();
  }

  /// Clear API token
  Future<void> clearApiToken() async {
    await _settingsBox.delete(StorageKeys.apiToken);
    notifyListeners();
  }

  // ============ Selected Station ============

  /// Get selected station ID
  int? get selectedStationId {
    final value = _settingsBox.get(StorageKeys.selectedStationId);
    return value != null ? int.tryParse(value) : null;
  }

  /// Save selected station ID
  Future<void> setSelectedStationId(int stationId) async {
    await _settingsBox.put(StorageKeys.selectedStationId, stationId.toString());
    notifyListeners();
  }

  // ============ Unit Preferences ============

  /// Get unit preferences
  UnitPreferences get unitPreferences {
    final json = _settingsBox.get(StorageKeys.unitPreferences);
    if (json == null) return UnitPreferences.nautical;
    try {
      return UnitPreferences.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } catch (_) {
      return UnitPreferences.nautical;
    }
  }

  /// Save unit preferences
  Future<void> setUnitPreferences(UnitPreferences prefs) async {
    await _settingsBox.put(StorageKeys.unitPreferences, jsonEncode(prefs.toJson()));
    notifyListeners();
  }

  // ============ Theme Mode ============

  /// Get theme mode (light, dark, system)
  String get themeMode => _settingsBox.get(StorageKeys.themeMode) ?? 'system';

  /// Save theme mode
  Future<void> setThemeMode(String mode) async {
    await _settingsBox.put(StorageKeys.themeMode, mode);
    notifyListeners();
  }

  // ============ UDP Settings ============

  /// Whether UDP is enabled
  bool get udpEnabled {
    final value = _settingsBox.get(StorageKeys.udpEnabled);
    return value == 'true';
  }

  /// Set UDP enabled
  Future<void> setUdpEnabled(bool enabled) async {
    await _settingsBox.put(StorageKeys.udpEnabled, enabled.toString());
    notifyListeners();
  }

  /// Get UDP port (default 50222)
  int get udpPort {
    final value = _settingsBox.get(StorageKeys.udpPort);
    return value != null ? int.tryParse(value) ?? 50222 : 50222;
  }

  /// Set UDP port
  Future<void> setUdpPort(int port) async {
    await _settingsBox.put(StorageKeys.udpPort, port.toString());
    notifyListeners();
  }

  // ============ Refresh Interval ============

  /// Get refresh interval in minutes
  int get refreshInterval {
    final value = _settingsBox.get(StorageKeys.refreshInterval);
    return value != null ? int.tryParse(value) ?? 15 : 15;
  }

  /// Set refresh interval in minutes
  Future<void> setRefreshInterval(int minutes) async {
    await _settingsBox.put(StorageKeys.refreshInterval, minutes.toString());
    notifyListeners();
  }

  // ============ Stations Cache ============

  /// Get cached stations
  List<Station> get cachedStations {
    final stations = <Station>[];
    for (final key in _stationsBox.keys) {
      final json = _stationsBox.get(key);
      if (json != null) {
        try {
          stations.add(Station.fromJson(jsonDecode(json) as Map<String, dynamic>));
        } catch (_) {}
      }
    }
    return stations;
  }

  /// Cache a station
  Future<void> cacheStation(Station station) async {
    await _stationsBox.put(
      station.stationId.toString(),
      jsonEncode(station.toJson()),
    );
  }

  /// Cache multiple stations
  Future<void> cacheStations(List<Station> stations) async {
    for (final station in stations) {
      await cacheStation(station);
    }
  }

  /// Get cached station by ID
  Station? getCachedStation(int stationId) {
    final json = _stationsBox.get(stationId.toString());
    if (json == null) return null;
    try {
      return Station.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  // ============ Observations Cache ============

  /// Cache an observation
  Future<void> cacheObservation(int deviceId, Observation obs) async {
    await _observationsBox.put(
      'latest_$deviceId',
      jsonEncode({
        'timestamp': obs.timestamp.toIso8601String(),
        'device_id': obs.deviceId,
        'wind_avg': obs.windAvg,
        'wind_direction': obs.windDirection,
        'wind_gust': obs.windGust,
        'wind_lull': obs.windLull,
        'temperature': obs.temperature,
        'humidity': obs.humidity,
        'pressure': obs.stationPressure,
        'uv_index': obs.uvIndex,
        'solar_radiation': obs.solarRadiation,
        'rain_accumulated': obs.rainAccumulated,
        'lightning_count': obs.lightningCount,
        'lightning_distance': obs.lightningDistance,
        'battery_voltage': obs.batteryVoltage,
      }),
    );
  }

  /// Get cached observation for device
  Observation? getCachedObservation(int deviceId) {
    final json = _observationsBox.get('latest_$deviceId');
    if (json == null) return null;
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      return Observation(
        timestamp: DateTime.parse(map['timestamp'] as String),
        deviceId: map['device_id'] as int,
        windAvg: (map['wind_avg'] as num?)?.toDouble(),
        windDirection: (map['wind_direction'] as num?)?.toDouble(),
        windGust: (map['wind_gust'] as num?)?.toDouble(),
        windLull: (map['wind_lull'] as num?)?.toDouble(),
        temperature: (map['temperature'] as num?)?.toDouble(),
        humidity: (map['humidity'] as num?)?.toDouble(),
        stationPressure: (map['pressure'] as num?)?.toDouble(),
        uvIndex: (map['uv_index'] as num?)?.toDouble(),
        solarRadiation: (map['solar_radiation'] as num?)?.toDouble(),
        rainAccumulated: (map['rain_accumulated'] as num?)?.toDouble(),
        lightningCount: map['lightning_count'] as int?,
        lightningDistance: (map['lightning_distance'] as num?)?.toDouble(),
        batteryVoltage: (map['battery_voltage'] as num?)?.toDouble(),
        source: ObservationSource.rest,
      );
    } catch (_) {
      return null;
    }
  }

  // ============ Forecast Cache ============

  /// Cache forecast response
  Future<void> cacheForecast(int stationId, ForecastResponse forecast) async {
    // Store hourly forecast data for offline use
    final hourlyData = forecast.hourlyForecasts.take(48).map((h) => {
      'time': h.time.toIso8601String(),
      'temperature': h.temperature,
      'humidity': h.humidity,
      'wind_avg': h.windAvg,
      'wind_direction': h.windDirection,
      'pressure': h.pressure,
      'precip_probability': h.precipProbability,
      'conditions': h.conditions,
      'icon': h.icon,
    }).toList();

    // Store daily forecast data
    final dailyData = forecast.dailyForecasts.take(10).map((d) => {
      'date': d.date.toIso8601String(),
      'day_index': d.dayIndex,
      'temp_high': d.tempHigh,
      'temp_low': d.tempLow,
      'conditions': d.conditions,
      'icon': d.icon,
      'precip_probability': d.precipProbability,
      'precip_icon': d.precipIcon,
      'sunrise': d.sunrise?.toIso8601String(),
      'sunset': d.sunset?.toIso8601String(),
    }).toList();

    await _forecastsBox.put(
      stationId.toString(),
      jsonEncode({
        'fetched_at': forecast.fetchedAt.toIso8601String(),
        'hourly': hourlyData,
        'daily': dailyData,
      }),
    );
  }

  /// Get cached forecast
  ForecastResponse? getCachedForecast(int stationId) {
    final json = _forecastsBox.get(stationId.toString());
    if (json == null) return null;
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      final hourlyList = <HourlyForecast>[];
      final dailyList = <DailyForecast>[];

      // Parse hourly forecasts
      if (map['hourly'] is List) {
        for (final h in map['hourly'] as List) {
          if (h is Map<String, dynamic>) {
            hourlyList.add(HourlyForecast(
              time: DateTime.parse(h['time'] as String),
              temperature: (h['temperature'] as num?)?.toDouble(),
              humidity: (h['humidity'] as num?)?.toDouble(),
              windAvg: (h['wind_avg'] as num?)?.toDouble(),
              windDirection: (h['wind_direction'] as num?)?.toDouble(),
              pressure: (h['pressure'] as num?)?.toDouble(),
              precipProbability: (h['precip_probability'] as num?)?.toDouble(),
              conditions: h['conditions'] as String?,
              icon: h['icon'] as String?,
            ));
          }
        }
      }

      // Parse daily forecasts
      if (map['daily'] is List) {
        for (final d in map['daily'] as List) {
          if (d is Map<String, dynamic>) {
            dailyList.add(DailyForecast(
              date: DateTime.parse(d['date'] as String),
              dayIndex: d['day_index'] as int,
              tempHigh: (d['temp_high'] as num?)?.toDouble(),
              tempLow: (d['temp_low'] as num?)?.toDouble(),
              conditions: d['conditions'] as String?,
              icon: d['icon'] as String?,
              precipProbability: (d['precip_probability'] as num?)?.toDouble(),
              precipIcon: d['precip_icon'] as String?,
              sunrise: d['sunrise'] != null ? DateTime.parse(d['sunrise'] as String) : null,
              sunset: d['sunset'] != null ? DateTime.parse(d['sunset'] as String) : null,
            ));
          }
        }
      }

      return ForecastResponse(
        hourlyForecasts: hourlyList,
        dailyForecasts: dailyList,
        fetchedAt: DateTime.parse(map['fetched_at'] as String),
      );
    } catch (_) {
      return null;
    }
  }

  // ============ Generic Storage ============

  /// Get a string value from dashboards box
  Future<String?> getString(String key) async {
    return _dashboardsBox.get(key);
  }

  /// Set a string value in dashboards box
  Future<void> setString(String key, String value) async {
    await _dashboardsBox.put(key, value);
  }

  /// Delete a key from dashboards box
  Future<void> deleteKey(String key) async {
    await _dashboardsBox.delete(key);
  }

  // ============ Station-Scoped Tool Configs ============

  /// Storage key for station-specific tool configs
  String _stationToolConfigKey(int stationId) => 'tool_configs_$stationId';

  /// Get all tool config overrides for a station
  /// Returns a map of toolId -> customProperties overrides
  Map<String, Map<String, dynamic>> getStationToolConfigs(int stationId) {
    final json = _dashboardsBox.get(_stationToolConfigKey(stationId));
    if (json == null) return {};
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      return map.map((key, value) => MapEntry(
        key,
        (value as Map<String, dynamic>?) ?? {},
      ));
    } catch (_) {
      return {};
    }
  }

  /// Get config override for a specific tool on a station
  /// Returns customProperties map or null if no override
  Map<String, dynamic>? getToolConfigForStation(int stationId, String toolId) {
    final configs = getStationToolConfigs(stationId);
    return configs[toolId];
  }

  /// Set config override for a specific tool on a station
  /// Only stores customProperties (device sources, etc.)
  Future<void> setToolConfigForStation(
    int stationId,
    String toolId,
    Map<String, dynamic> customProperties,
  ) async {
    final configs = getStationToolConfigs(stationId);
    configs[toolId] = customProperties;
    await _dashboardsBox.put(
      _stationToolConfigKey(stationId),
      jsonEncode(configs),
    );
    notifyListeners();
  }

  /// Clear config override for a specific tool on a station
  Future<void> clearToolConfigForStation(int stationId, String toolId) async {
    final configs = getStationToolConfigs(stationId);
    configs.remove(toolId);
    if (configs.isEmpty) {
      await _dashboardsBox.delete(_stationToolConfigKey(stationId));
    } else {
      await _dashboardsBox.put(
        _stationToolConfigKey(stationId),
        jsonEncode(configs),
      );
    }
    notifyListeners();
  }

  /// Clear all tool config overrides for a station
  Future<void> clearStationToolConfigs(int stationId) async {
    await _dashboardsBox.delete(_stationToolConfigKey(stationId));
    notifyListeners();
  }

  // ============ Clear Data ============

  /// Clear stations cache only
  Future<void> clearStations() async {
    await _stationsBox.clear();
    notifyListeners();
  }

  /// Clear observations cache only
  Future<void> clearObservations() async {
    await _observationsBox.clear();
    notifyListeners();
  }

  /// Clear forecasts cache only
  Future<void> clearForecasts() async {
    await _forecastsBox.clear();
    notifyListeners();
  }

  /// Clear all cached data (keep settings)
  Future<void> clearCache() async {
    await _stationsBox.clear();
    await _observationsBox.clear();
    await _forecastsBox.clear();
    notifyListeners();
  }

  /// Clear all data including settings
  Future<void> clearAll() async {
    await _settingsBox.clear();
    await _stationsBox.clear();
    await _observationsBox.clear();
    await _forecastsBox.clear();
    await _dashboardsBox.clear();
    notifyListeners();
  }
}
