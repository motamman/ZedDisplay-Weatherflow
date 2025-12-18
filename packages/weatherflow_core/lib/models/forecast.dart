/// Forecast models for WeatherFlow better_forecast API

/// Hourly forecast entry
class HourlyForecast {
  final DateTime time;
  final double? temperature; // K
  final double? feelsLike; // K
  final double? humidity; // 0-1 ratio
  final double? precipProbability; // 0-1 ratio
  final double? precipAmount; // m
  final String? precipType;
  final String? precipIcon;
  final double? windAvg; // m/s
  final double? windDirection; // degrees
  final double? windGust; // m/s
  final double? pressure; // Pa (sea level)
  final double? uvIndex;
  final String? conditions;
  final String? icon;

  const HourlyForecast({
    required this.time,
    this.temperature,
    this.feelsLike,
    this.humidity,
    this.precipProbability,
    this.precipAmount,
    this.precipType,
    this.precipIcon,
    this.windAvg,
    this.windDirection,
    this.windGust,
    this.pressure,
    this.uvIndex,
    this.conditions,
    this.icon,
  });

  factory HourlyForecast.fromJson(Map<String, dynamic> json) {
    // Parse time
    DateTime time;
    final timeValue = json['time'];
    if (timeValue is int) {
      time = DateTime.fromMillisecondsSinceEpoch(timeValue * 1000);
    } else if (timeValue is String) {
      time = DateTime.tryParse(timeValue) ?? DateTime.now();
    } else {
      time = DateTime.now();
    }

    return HourlyForecast(
      time: time,
      // API returns Celsius, convert to Kelvin
      temperature: json['air_temperature'] != null
          ? (json['air_temperature'] as num).toDouble() + 273.15
          : null,
      feelsLike: json['feels_like'] != null
          ? (json['feels_like'] as num).toDouble() + 273.15
          : null,
      humidity: json['relative_humidity'] != null
          ? (json['relative_humidity'] as num).toDouble() / 100
          : null,
      precipProbability: json['precip_probability'] != null
          ? (json['precip_probability'] as num).toDouble() / 100
          : null,
      precipAmount: json['precip'] != null
          ? (json['precip'] as num).toDouble() / 1000 // mm to m
          : null,
      precipType: json['precip_type'] as String?,
      precipIcon: json['precip_icon'] as String?,
      windAvg: json['wind_avg'] != null
          ? _convertWindSpeed(json['wind_avg'] as num, json)
          : null,
      windDirection: (json['wind_direction'] as num?)?.toDouble(),
      windGust: json['wind_gust'] != null
          ? _convertWindSpeed(json['wind_gust'] as num, json)
          : null,
      pressure: json['sea_level_pressure'] != null
          ? (json['sea_level_pressure'] as num).toDouble() * 100 // mbar to Pa
          : null,
      uvIndex: (json['uv'] as num?)?.toDouble(),
      conditions: json['conditions'] as String?,
      icon: json['icon'] as String?,
    );
  }

  /// Convert wind speed based on units in response (default is mps)
  static double _convertWindSpeed(num value, Map<String, dynamic> json) {
    // API returns in requested units, but we store in m/s
    // If no units specified, assume m/s
    return value.toDouble();
  }
}

/// Daily forecast entry
class DailyForecast {
  final DateTime date;
  final int dayIndex; // 0 = today, 1 = tomorrow, etc.
  final double? tempHigh; // K
  final double? tempLow; // K
  final double? precipProbability; // 0-1 ratio
  final double? precipAmount; // m
  final String? precipType;
  final String? precipIcon;
  final String? conditions;
  final String? icon;
  final DateTime? sunrise;
  final DateTime? sunset;

  const DailyForecast({
    required this.date,
    required this.dayIndex,
    this.tempHigh,
    this.tempLow,
    this.precipProbability,
    this.precipAmount,
    this.precipType,
    this.precipIcon,
    this.conditions,
    this.icon,
    this.sunrise,
    this.sunset,
  });

  factory DailyForecast.fromJson(Map<String, dynamic> json, int dayIndex) {
    // Parse day_start_local as the date
    DateTime date;
    final dayStart = json['day_start_local'];
    if (dayStart is int) {
      date = DateTime.fromMillisecondsSinceEpoch(dayStart * 1000);
    } else {
      date = DateTime.now().add(Duration(days: dayIndex));
    }

    return DailyForecast(
      date: date,
      dayIndex: dayIndex,
      // API returns Celsius, convert to Kelvin
      tempHigh: json['air_temp_high'] != null
          ? (json['air_temp_high'] as num).toDouble() + 273.15
          : null,
      tempLow: json['air_temp_low'] != null
          ? (json['air_temp_low'] as num).toDouble() + 273.15
          : null,
      precipProbability: json['precip_probability'] != null
          ? (json['precip_probability'] as num).toDouble() / 100
          : null,
      precipAmount: json['precip'] != null
          ? (json['precip'] as num).toDouble() / 1000 // mm to m
          : null,
      precipType: json['precip_type'] as String?,
      precipIcon: json['precip_icon'] as String?,
      conditions: json['conditions'] as String?,
      icon: json['icon'] as String?,
      sunrise: json['sunrise'] != null
          ? DateTime.fromMillisecondsSinceEpoch((json['sunrise'] as int) * 1000)
          : null,
      sunset: json['sunset'] != null
          ? DateTime.fromMillisecondsSinceEpoch((json['sunset'] as int) * 1000)
          : null,
    );
  }

  /// Get day name from index
  String get dayName {
    if (dayIndex == 0) return 'Today';
    if (dayIndex == 1) return 'Tomorrow';
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[date.weekday - 1];
  }
}

/// Current conditions from forecast API
class CurrentConditions {
  final DateTime timestamp;
  final double? temperature; // K
  final double? feelsLike; // K
  final double? humidity; // 0-1 ratio
  final double? dewPoint; // K
  final double? windAvg; // m/s
  final double? windDirection; // degrees
  final double? windGust; // m/s
  final double? pressure; // Pa (sea level)
  final double? uvIndex;
  final double? solarRadiation; // W/m²
  final int? brightness; // lux
  final String? conditions;
  final String? icon;
  final bool isDay;

  const CurrentConditions({
    required this.timestamp,
    this.temperature,
    this.feelsLike,
    this.humidity,
    this.dewPoint,
    this.windAvg,
    this.windDirection,
    this.windGust,
    this.pressure,
    this.uvIndex,
    this.solarRadiation,
    this.brightness,
    this.conditions,
    this.icon,
    this.isDay = true,
  });

  factory CurrentConditions.fromJson(Map<String, dynamic> json) {
    // Parse time
    DateTime timestamp;
    final timeValue = json['time'];
    if (timeValue is int) {
      timestamp = DateTime.fromMillisecondsSinceEpoch(timeValue * 1000);
    } else {
      timestamp = DateTime.now();
    }

    return CurrentConditions(
      timestamp: timestamp,
      temperature: json['air_temperature'] != null
          ? (json['air_temperature'] as num).toDouble() + 273.15
          : null,
      feelsLike: json['feels_like'] != null
          ? (json['feels_like'] as num).toDouble() + 273.15
          : null,
      humidity: json['relative_humidity'] != null
          ? (json['relative_humidity'] as num).toDouble() / 100
          : null,
      dewPoint: json['dew_point'] != null
          ? (json['dew_point'] as num).toDouble() + 273.15
          : null,
      windAvg: (json['wind_avg'] as num?)?.toDouble(),
      windDirection: (json['wind_direction'] as num?)?.toDouble(),
      windGust: (json['wind_gust'] as num?)?.toDouble(),
      pressure: json['sea_level_pressure'] != null
          ? (json['sea_level_pressure'] as num).toDouble() * 100
          : null,
      uvIndex: (json['uv'] as num?)?.toDouble(),
      solarRadiation: (json['solar_radiation'] as num?)?.toDouble(),
      brightness: json['brightness'] as int?,
      conditions: json['conditions'] as String?,
      icon: json['icon'] as String?,
      isDay: json['is_day'] as bool? ?? true,
    );
  }
}

/// Full forecast response from better_forecast API
class ForecastResponse {
  final CurrentConditions? currentConditions;
  final List<HourlyForecast> hourlyForecasts;
  final List<DailyForecast> dailyForecasts;
  final String? units;
  final DateTime fetchedAt;

  const ForecastResponse({
    this.currentConditions,
    this.hourlyForecasts = const [],
    this.dailyForecasts = const [],
    this.units,
    DateTime? fetchedAt,
  }) : fetchedAt = fetchedAt ?? const _ConstantDateTime();

  factory ForecastResponse.fromJson(Map<String, dynamic> json) {
    // Debug: print the structure
    // ignore: avoid_print
    print('ForecastResponse.fromJson: Keys in response: ${json.keys.toList()}');
    if (json['forecast'] != null) {
      // ignore: avoid_print
      print('ForecastResponse.fromJson: Keys in forecast: ${(json['forecast'] as Map).keys.toList()}');
      if (json['forecast']['daily'] != null) {
        // ignore: avoid_print
        print('ForecastResponse.fromJson: Daily is ${json['forecast']['daily'].runtimeType}, length: ${(json['forecast']['daily'] as List?)?.length ?? 'N/A'}');
      } else {
        // ignore: avoid_print
        print('ForecastResponse.fromJson: Daily is NULL');
      }
    } else {
      // ignore: avoid_print
      print('ForecastResponse.fromJson: forecast key is NULL');
    }

    // Parse current conditions
    CurrentConditions? current;
    if (json['current_conditions'] != null) {
      current = CurrentConditions.fromJson(
        json['current_conditions'] as Map<String, dynamic>,
      );
    }

    // Parse hourly forecasts
    final hourlyList = <HourlyForecast>[];
    if (json['forecast']?['hourly'] is List) {
      for (final hourlyJson in json['forecast']['hourly'] as List) {
        if (hourlyJson is Map<String, dynamic>) {
          hourlyList.add(HourlyForecast.fromJson(hourlyJson));
        }
      }
    }

    // Parse daily forecasts
    final dailyList = <DailyForecast>[];
    if (json['forecast']?['daily'] is List) {
      int dayIndex = 0;
      for (final dailyJson in json['forecast']['daily'] as List) {
        if (dailyJson is Map<String, dynamic>) {
          dailyList.add(DailyForecast.fromJson(dailyJson, dayIndex));
          dayIndex++;
        }
      }
    }
    print('ForecastResponse.fromJson: Parsed ${dailyList.length} daily forecasts');

    // Units can be a string or a map - handle both
    String? units;
    final unitsValue = json['units'];
    if (unitsValue is String) {
      units = unitsValue;
    } else if (unitsValue is Map) {
      // WeatherFlow returns units as a map like {"units_temp": "c", "units_wind": "mps", ...}
      units = unitsValue.toString();
    }

    return ForecastResponse(
      currentConditions: current,
      hourlyForecasts: hourlyList,
      dailyForecasts: dailyList,
      units: units,
      fetchedAt: DateTime.now(),
    );
  }

  /// Check if forecast data is stale (older than 30 minutes)
  bool get isStale => DateTime.now().difference(fetchedAt) > const Duration(minutes: 30);
}

/// Constant DateTime for default value
class _ConstantDateTime implements DateTime {
  const _ConstantDateTime();

  @override
  int get year => 1970;
  @override
  int get month => 1;
  @override
  int get day => 1;
  @override
  int get hour => 0;
  @override
  int get minute => 0;
  @override
  int get second => 0;
  @override
  int get millisecond => 0;
  @override
  int get microsecond => 0;
  @override
  int get weekday => DateTime.thursday;
  @override
  bool get isUtc => true;
  @override
  String get timeZoneName => 'UTC';
  @override
  Duration get timeZoneOffset => Duration.zero;
  @override
  int get millisecondsSinceEpoch => 0;
  @override
  int get microsecondsSinceEpoch => 0;

  @override
  DateTime add(Duration duration) => DateTime.fromMillisecondsSinceEpoch(duration.inMilliseconds);
  @override
  DateTime subtract(Duration duration) => DateTime.fromMillisecondsSinceEpoch(-duration.inMilliseconds);
  @override
  Duration difference(DateTime other) => Duration(milliseconds: -other.millisecondsSinceEpoch);
  @override
  bool isAfter(DateTime other) => false;
  @override
  bool isBefore(DateTime other) => other.millisecondsSinceEpoch > 0;
  @override
  bool isAtSameMomentAs(DateTime other) => other.millisecondsSinceEpoch == 0;
  @override
  int compareTo(DateTime other) => -other.millisecondsSinceEpoch.sign;
  @override
  DateTime toLocal() => this;
  @override
  DateTime toUtc() => this;
  @override
  String toIso8601String() => '1970-01-01T00:00:00.000Z';
  @override
  String toString() => '1970-01-01 00:00:00.000Z';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
