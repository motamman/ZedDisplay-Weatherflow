/// Observation History Service
///
/// Fetches and caches historical observation data from WeatherFlow API.
/// Provides time series extraction for charting.

import 'dart:math' show pow;
import 'package:flutter/foundation.dart';
import 'package:weatherflow_core/weatherflow_core.dart';

/// Variables that can be charted from observations
enum ConditionVariable {
  temperature('Temperature', 'thermostat'),
  feelsLike('Feels Like', 'accessibility'),
  humidity('Humidity', 'water_drop'),
  dewPoint('Dew Point', 'opacity'),
  pressure('Pressure', 'compress'),
  windSpeed('Wind Speed', 'air'),
  windGust('Wind Gust', 'air'),
  windDirection('Wind Direction', 'navigation'),
  rainRate('Rain Rate', 'umbrella'),
  rainAccumulated('Rain Today', 'water'),
  precipType('Precip Type', 'grain'),
  uvIndex('UV Index', 'wb_sunny'),
  solarRadiation('Solar Radiation', 'solar_power'),
  illuminance('Brightness', 'lightbulb'),
  lightningDistance('Lightning', 'flash_on'),
  lightningCount('Lightning Strikes', 'bolt'),
  batteryVoltage('Battery', 'battery_full');

  final String label;
  final String iconName;

  const ConditionVariable(this.label, this.iconName);

  /// Check if this variable has forecast data available
  bool get hasForecast {
    switch (this) {
      case ConditionVariable.temperature:
      case ConditionVariable.feelsLike:
      case ConditionVariable.humidity:
      case ConditionVariable.pressure:
      case ConditionVariable.windSpeed:
      case ConditionVariable.windGust:
      case ConditionVariable.windDirection:
      case ConditionVariable.uvIndex:
      case ConditionVariable.precipType:
        return true;
      default:
        return false;
    }
  }

  /// Get unit symbol (will be converted by ConversionService at display)
  String getUnitSymbol(ConversionService conversions) {
    switch (this) {
      case ConditionVariable.temperature:
      case ConditionVariable.feelsLike:
      case ConditionVariable.dewPoint:
        return conversions.temperatureSymbol;
      case ConditionVariable.humidity:
        return '%';
      case ConditionVariable.pressure:
        return conversions.pressureSymbol;
      case ConditionVariable.windSpeed:
      case ConditionVariable.windGust:
        return conversions.windSpeedSymbol;
      case ConditionVariable.windDirection:
        return '°';
      case ConditionVariable.rainRate:
      case ConditionVariable.rainAccumulated:
        return conversions.rainfallSymbol;
      case ConditionVariable.precipType:
        return ''; // Categorical: 0=none, 1=rain, 2=hail, 3=mix, 4=snow, 5=sleet
      case ConditionVariable.uvIndex:
        return '';
      case ConditionVariable.solarRadiation:
        return 'W/m²';
      case ConditionVariable.illuminance:
        return 'lux';
      case ConditionVariable.lightningDistance:
        return conversions.distanceSymbol;
      case ConditionVariable.lightningCount:
        return '';
      case ConditionVariable.batteryVoltage:
        return 'V';
    }
  }
}

/// A single data point for charting
class DataPoint {
  final DateTime time;
  final double value;

  const DataPoint({required this.time, required this.value});

  @override
  String toString() => 'DataPoint($time, $value)';
}

/// Statistics for a time series
class SeriesStatistics {
  final double min;
  final double max;
  final double avg;
  final DateTime? minTime;
  final DateTime? maxTime;
  final double? trend; // Positive = rising, negative = falling

  const SeriesStatistics({
    required this.min,
    required this.max,
    required this.avg,
    this.minTime,
    this.maxTime,
    this.trend,
  });

  String get trendLabel {
    if (trend == null) return 'Steady';
    if (trend! > 0.1) return 'Rising';
    if (trend! < -0.1) return 'Falling';
    return 'Steady';
  }

  String get trendIcon {
    if (trend == null) return '→';
    if (trend! > 0.1) return '↗';
    if (trend! < -0.1) return '↘';
    return '→';
  }
}

/// Service for fetching and caching historical observations
class ObservationHistoryService extends ChangeNotifier {
  WeatherFlowApi? _api;

  // Cache: deviceId -> (startTime -> observations)
  final Map<int, Map<int, List<Observation>>> _cache = {};

  // Loading state per request
  final Map<String, bool> _loadingState = {};
  String? _lastError;

  // Getters
  String? get lastError => _lastError;

  /// Initialize with API client
  void initialize(WeatherFlowApi api) {
    _api = api;
  }

  /// Check if a request is currently loading
  bool isLoading(int deviceId, DateTime start, DateTime end) {
    final key = _cacheKey(deviceId, start, end);
    return _loadingState[key] ?? false;
  }

  /// Fetch historical observations for a device
  Future<List<Observation>> getHistory({
    required int deviceId,
    int? dayOffset,
    DateTime? startTime,
    DateTime? endTime,
  }) async {
    if (_api == null) {
      throw Exception('ObservationHistoryService not initialized');
    }

    // Calculate actual start/end times
    final now = DateTime.now();
    final DateTime actualStart;
    final DateTime actualEnd;

    if (dayOffset != null) {
      // Day offset mode: fetch entire day
      actualStart = DateTime(now.year, now.month, now.day - dayOffset);
      actualEnd = actualStart.add(const Duration(days: 1));
    } else if (startTime != null && endTime != null) {
      actualStart = startTime;
      actualEnd = endTime;
    } else {
      // Default: last 24 hours
      actualEnd = now;
      actualStart = now.subtract(const Duration(hours: 24));
    }

    // Check cache
    final cacheKey = _cacheKey(deviceId, actualStart, actualEnd);
    final cached = _getCached(deviceId, actualStart);
    if (cached != null) {
      debugPrint('ObservationHistoryService: Cache hit for device $deviceId');
      return cached;
    }

    // Set loading state
    _loadingState[cacheKey] = true;
    _lastError = null;
    notifyListeners();

    try {
      debugPrint('ObservationHistoryService: Fetching history for device $deviceId from $actualStart to $actualEnd');

      final observations = await _api!.getDeviceObservations(
        deviceId,
        dayOffset: dayOffset,
        startTime: startTime ?? actualStart,
        endTime: endTime ?? actualEnd,
      );

      debugPrint('ObservationHistoryService: Received ${observations.length} observations');

      // Cache the result
      _setCached(deviceId, actualStart, observations);

      _loadingState[cacheKey] = false;
      notifyListeners();

      return observations;
    } catch (e) {
      debugPrint('ObservationHistoryService: Error fetching history: $e');
      _lastError = e.toString();
      _loadingState[cacheKey] = false;
      notifyListeners();
      rethrow;
    }
  }

  /// Fetch history for a specific time range (convenience method)
  Future<List<Observation>> getHistoryRange({
    required int deviceId,
    required Duration range,
  }) async {
    final now = DateTime.now();
    return getHistory(
      deviceId: deviceId,
      startTime: now.subtract(range),
      endTime: now,
    );
  }

  /// Extract time series for a specific variable from observations
  List<DataPoint> extractSeries(
    List<Observation> observations,
    ConditionVariable variable,
  ) {
    final points = <DataPoint>[];

    for (final obs in observations) {
      final value = _extractValue(obs, variable);
      if (value != null && obs.timestamp != null) {
        points.add(DataPoint(time: obs.timestamp!, value: value));
      }
    }

    // Sort by time
    points.sort((a, b) => a.time.compareTo(b.time));

    return points;
  }

  /// Calculate statistics for a series
  SeriesStatistics? calculateStatistics(List<DataPoint> series) {
    if (series.isEmpty) return null;

    double sum = 0;
    double min = series.first.value;
    double max = series.first.value;
    DateTime? minTime;
    DateTime? maxTime;

    for (final point in series) {
      sum += point.value;
      if (point.value < min) {
        min = point.value;
        minTime = point.time;
      }
      if (point.value > max) {
        max = point.value;
        maxTime = point.time;
      }
    }

    final avg = sum / series.length;

    // Calculate trend (slope of last hour)
    double? trend;
    if (series.length >= 2) {
      final recentPoints = series.where((p) =>
          p.time.isAfter(DateTime.now().subtract(const Duration(hours: 1)))).toList();
      if (recentPoints.length >= 2) {
        final first = recentPoints.first;
        final last = recentPoints.last;
        final timeDiff = last.time.difference(first.time).inMinutes;
        if (timeDiff > 0) {
          trend = (last.value - first.value) / timeDiff * 60; // Per hour
        }
      }
    }

    return SeriesStatistics(
      min: min,
      max: max,
      avg: avg,
      minTime: minTime,
      maxTime: maxTime,
      trend: trend,
    );
  }

  /// Extract value for a specific variable from an observation
  double? _extractValue(Observation obs, ConditionVariable variable) {
    switch (variable) {
      case ConditionVariable.temperature:
        return obs.temperature;
      case ConditionVariable.feelsLike:
        // Use calculated feelsLike if available, otherwise calculate from temp/humidity/wind
        return obs.feelsLike ?? _calculateFeelsLike(obs);
      case ConditionVariable.humidity:
        return obs.humidity;
      case ConditionVariable.dewPoint:
        return obs.dewPoint;
      case ConditionVariable.pressure:
        return obs.seaLevelPressure ?? obs.stationPressure;
      case ConditionVariable.windSpeed:
        return obs.windAvg;
      case ConditionVariable.windGust:
        return obs.windGust;
      case ConditionVariable.windDirection:
        return obs.windDirection;
      case ConditionVariable.rainRate:
        return obs.rainRate;
      case ConditionVariable.rainAccumulated:
        return obs.rainAccumulated;
      case ConditionVariable.precipType:
        // Convert PrecipType enum to numeric: none=0, rain=1, hail=2, rainAndHail=3
        return _precipTypeToDouble(obs.precipType);
      case ConditionVariable.uvIndex:
        return obs.uvIndex;
      case ConditionVariable.solarRadiation:
        return obs.solarRadiation;
      case ConditionVariable.illuminance:
        return obs.illuminance;
      case ConditionVariable.lightningDistance:
        return obs.lightningDistance;
      case ConditionVariable.lightningCount:
        return obs.lightningCount?.toDouble();
      case ConditionVariable.batteryVoltage:
        return obs.batteryVoltage;
    }
  }

  /// Get current value for a variable from an observation
  double? getCurrentValue(Observation? obs, ConditionVariable variable) {
    if (obs == null) return null;
    return _extractValue(obs, variable);
  }

  /// Calculate feels like temperature from raw observation data
  /// Uses heat index when hot/humid, wind chill when cold/windy
  /// All calculations done in Kelvin
  double? _calculateFeelsLike(Observation obs) {
    final tempK = obs.temperature;
    if (tempK == null) return null;

    final humidity = obs.humidity; // 0-1 ratio
    final windMps = obs.windAvg;

    // Convert Kelvin to Celsius for threshold checks
    final tempC = tempK - 273.15;

    // Heat Index: when temp > 27°C (80°F) and humidity > 40%
    if (tempC > 27 && humidity != null && humidity > 0.4) {
      return _calculateHeatIndex(tempK, humidity);
    }

    // Wind Chill: when temp < 10°C (50°F) and wind > 1.34 m/s (3 mph)
    if (tempC < 10 && windMps != null && windMps > 1.34) {
      return _calculateWindChill(tempK, windMps);
    }

    // Otherwise, feels like = actual temperature
    return tempK;
  }

  /// Calculate heat index using Rothfusz regression (returns Kelvin)
  double _calculateHeatIndex(double tempK, double humidityRatio) {
    // Convert to Fahrenheit for standard formula
    final tempF = (tempK - 273.15) * 9 / 5 + 32;
    final rh = humidityRatio * 100; // Convert to percentage

    // Rothfusz regression equation
    double hi = -42.379 +
        2.04901523 * tempF +
        10.14333127 * rh -
        0.22475541 * tempF * rh -
        0.00683783 * tempF * tempF -
        0.05481717 * rh * rh +
        0.00122874 * tempF * tempF * rh +
        0.00085282 * tempF * rh * rh -
        0.00000199 * tempF * tempF * rh * rh;

    // Adjustment for low humidity
    if (rh < 13 && tempF >= 80 && tempF <= 112) {
      hi -= ((13 - rh) / 4) * ((17 - (tempF - 95).abs()) / 17).clamp(0, 1);
    }
    // Adjustment for high humidity
    else if (rh > 85 && tempF >= 80 && tempF <= 87) {
      hi += ((rh - 85) / 10) * ((87 - tempF) / 5);
    }

    // Convert back to Kelvin
    return (hi - 32) * 5 / 9 + 273.15;
  }

  /// Calculate wind chill (returns Kelvin)
  double _calculateWindChill(double tempK, double windMps) {
    // Convert to units for standard formula
    final tempF = (tempK - 273.15) * 9 / 5 + 32;
    final windMph = windMps * 2.237; // m/s to mph

    // Standard wind chill formula
    final windPow = pow(windMph <= 0 ? 1 : windMph, 0.16);
    final wc = 35.74 +
        0.6215 * tempF -
        35.75 * windPow +
        0.4275 * tempF * windPow;

    // Convert back to Kelvin
    return (wc - 32) * 5 / 9 + 273.15;
  }

  /// Convert PrecipType enum to double for charting
  /// 0=none, 1=rain, 2=hail, 3=rainAndHail
  double _precipTypeToDouble(PrecipType type) {
    switch (type) {
      case PrecipType.none:
        return 0;
      case PrecipType.rain:
        return 1;
      case PrecipType.hail:
        return 2;
      case PrecipType.rainAndHail:
        return 3;
    }
  }

  /// Convert forecast precip type string to double for charting
  /// 0=none, 1=rain, 2=hail, 3=mix, 4=snow, 5=sleet, 6=freezing rain
  static double precipTypeStringToDouble(String? type) {
    if (type == null || type.isEmpty) return 0;
    final lower = type.toLowerCase();
    if (lower.contains('snow')) return 4;
    if (lower.contains('sleet')) return 5;
    if (lower.contains('freezing')) return 6;
    if (lower.contains('hail')) return 2;
    if (lower.contains('rain')) return 1;
    if (lower.contains('mix')) return 3;
    return 0;
  }

  /// Get label for precip type numeric value
  static String precipTypeLabel(double value) {
    switch (value.round()) {
      case 0:
        return 'None';
      case 1:
        return 'Rain';
      case 2:
        return 'Hail';
      case 3:
        return 'Mix';
      case 4:
        return 'Snow';
      case 5:
        return 'Sleet';
      case 6:
        return 'Freezing';
      default:
        return 'Unknown';
    }
  }

  // Cache helpers
  String _cacheKey(int deviceId, DateTime start, DateTime end) {
    return '$deviceId-${start.millisecondsSinceEpoch}-${end.millisecondsSinceEpoch}';
  }

  List<Observation>? _getCached(int deviceId, DateTime start) {
    final deviceCache = _cache[deviceId];
    if (deviceCache == null) return null;

    final startKey = start.millisecondsSinceEpoch ~/ 3600000; // Hour-level granularity
    return deviceCache[startKey];
  }

  void _setCached(int deviceId, DateTime start, List<Observation> observations) {
    _cache[deviceId] ??= {};
    final startKey = start.millisecondsSinceEpoch ~/ 3600000;
    _cache[deviceId]![startKey] = observations;
  }

  /// Clear all cached data
  void clearCache() {
    _cache.clear();
    _loadingState.clear();
    notifyListeners();
  }

  /// Clear cache for a specific device
  void clearCacheForDevice(int deviceId) {
    _cache.remove(deviceId);
    notifyListeners();
  }
}
