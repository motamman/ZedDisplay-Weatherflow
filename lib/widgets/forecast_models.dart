/// Forecast data models for WeatherFlow
/// Adapted from ZedDisplay architecture

import 'package:flutter/material.dart';

/// Sun times for a single day
class DaySunTimes {
  final DateTime? sunrise;
  final DateTime? sunset;
  final DateTime? dawn;
  final DateTime? dusk;
  final DateTime? nauticalDawn;
  final DateTime? nauticalDusk;
  final DateTime? solarNoon;
  final DateTime? goldenHour;
  final DateTime? goldenHourEnd;
  final DateTime? night;
  final DateTime? nightEnd;
  final DateTime? moonrise;
  final DateTime? moonset;

  const DaySunTimes({
    this.sunrise,
    this.sunset,
    this.dawn,
    this.dusk,
    this.nauticalDawn,
    this.nauticalDusk,
    this.solarNoon,
    this.goldenHour,
    this.goldenHourEnd,
    this.night,
    this.nightEnd,
    this.moonrise,
    this.moonset,
  });
}

/// Sun/Moon times for multiple days
class SunMoonTimes {
  /// List of daily sun/moon times
  /// When todayIndex > 0, earlier indices are past days (e.g., yesterday)
  final List<DaySunTimes> days;

  /// Index in [days] that represents today (default 0)
  /// Set to 1 when yesterday is included at index 0
  final int todayIndex;

  /// Moon phase info (current)
  final double? moonPhase; // 0-1 (0=new, 0.5=full)
  final double? moonFraction; // 0-1 illumination fraction
  final double? moonAngle; // radians

  const SunMoonTimes({
    this.days = const [],
    this.todayIndex = 0,
    this.moonPhase,
    this.moonFraction,
    this.moonAngle,
  });

  /// Get sun times for a specific day relative to today
  /// 0 = today, 1 = tomorrow, -1 = yesterday, etc.
  DaySunTimes? getDay(int relativeDay) {
    final index = todayIndex + relativeDay;
    if (index >= 0 && index < days.length) {
      return days[index];
    }
    return null;
  }

  /// Get today's sun times
  DaySunTimes? get today => getDay(0);

  /// Convenience getters for today's times
  DateTime? get sunrise => today?.sunrise;
  DateTime? get sunset => today?.sunset;
  DateTime? get dawn => today?.dawn;
  DateTime? get dusk => today?.dusk;
  DateTime? get nauticalDawn => today?.nauticalDawn;
  DateTime? get nauticalDusk => today?.nauticalDusk;
  DateTime? get solarNoon => today?.solarNoon;
  DateTime? get goldenHour => today?.goldenHour;
  DateTime? get goldenHourEnd => today?.goldenHourEnd;
}

/// Hourly forecast entry
class HourlyForecast {
  final int hour;
  final double? temperature;
  final double? feelsLike;
  final String? conditions;
  final String? longDescription;
  final String? icon;
  final double? precipProbability; // 0-100
  final double? humidity;
  final double? pressure;
  final double? windSpeed;
  final double? windDirection; // degrees

  HourlyForecast({
    required this.hour,
    this.temperature,
    this.feelsLike,
    this.conditions,
    this.longDescription,
    this.icon,
    this.precipProbability,
    this.humidity,
    this.pressure,
    this.windSpeed,
    this.windDirection,
  });

  /// WMO weather code to BAS weather icon mapping
  static const wmoIconMap = {
    '0': {'day': 'clear-day', 'night': 'clear-night'},
    '1': {'day': 'clear-day', 'night': 'clear-night'},
    '2': {'day': 'partly-cloudy-day', 'night': 'partly-cloudy-night'},
    '3': {'day': 'overcast', 'night': 'overcast'},
    '45': {'day': 'fog', 'night': 'fog'},
    '48': {'day': 'fog', 'night': 'fog'},
    '51': {'day': 'drizzle', 'night': 'drizzle'},
    '53': {'day': 'drizzle', 'night': 'drizzle'},
    '55': {'day': 'drizzle', 'night': 'drizzle'},
    '56': {'day': 'sleet', 'night': 'sleet'},
    '57': {'day': 'sleet', 'night': 'sleet'},
    '61': {'day': 'partly-cloudy-day-rain', 'night': 'partly-cloudy-night-rain'},
    '63': {'day': 'rain', 'night': 'rain'},
    '65': {'day': 'rain', 'night': 'rain'},
    '66': {'day': 'sleet', 'night': 'sleet'},
    '67': {'day': 'sleet', 'night': 'sleet'},
    '71': {'day': 'partly-cloudy-day-snow', 'night': 'partly-cloudy-night-snow'},
    '73': {'day': 'snow', 'night': 'snow'},
    '75': {'day': 'snow', 'night': 'snow'},
    '77': {'day': 'snow', 'night': 'snow'},
    '80': {'day': 'partly-cloudy-day-rain', 'night': 'partly-cloudy-night-rain'},
    '81': {'day': 'rain', 'night': 'rain'},
    '82': {'day': 'rain', 'night': 'rain'},
    '85': {'day': 'partly-cloudy-day-snow', 'night': 'partly-cloudy-night-snow'},
    '86': {'day': 'snow', 'night': 'snow'},
    '95': {'day': 'thunderstorms', 'night': 'thunderstorms'},
    '96': {'day': 'thunderstorms-rain', 'night': 'thunderstorms-rain'},
    '99': {'day': 'thunderstorms-rain', 'night': 'thunderstorms-rain'},
  };

  /// Map common icon names to BAS weather icons
  static const basIconMap = {
    'clear-day': 'clear-day',
    'clear-night': 'clear-night',
    'cloudy': 'cloudy',
    'foggy': 'fog',
    'fog': 'fog',
    'mist': 'mist',
    'partly-cloudy-day': 'partly-cloudy-day',
    'partly-cloudy-night': 'partly-cloudy-night',
    'possibly-rainy-day': 'partly-cloudy-day-rain',
    'possibly-rainy-night': 'partly-cloudy-night-rain',
    'possibly-sleet-day': 'partly-cloudy-day-sleet',
    'possibly-sleet-night': 'partly-cloudy-night-sleet',
    'possibly-snow-day': 'partly-cloudy-day-snow',
    'possibly-snow-night': 'partly-cloudy-night-snow',
    'possibly-thunderstorm-day': 'thunderstorms-day',
    'possibly-thunderstorm-night': 'thunderstorms-night',
    'rainy': 'rain',
    'rain': 'rain',
    'sleet': 'sleet',
    'snow': 'snow',
    'thunderstorm': 'thunderstorms',
    'thunderstorms': 'thunderstorms',
    'windy': 'wind',
    'wind': 'wind',
    'overcast': 'overcast',
    'overcast-day': 'overcast-day',
    'overcast-night': 'overcast-night',
    'drizzle': 'drizzle',
    'hail': 'hail',
  };

  /// Get asset path for weather icon
  String get weatherIconAsset {
    if (icon == null) return 'assets/weather_icons/bas_weather/production/fill/all/cloudy.svg';

    // Check if it's a WMO code
    if (wmoIconMap.containsKey(icon)) {
      final isDay = _isCurrentlyDay();
      final dayNight = isDay ? 'day' : 'night';
      final iconName = wmoIconMap[icon]![dayNight]!;
      return 'assets/weather_icons/bas_weather/production/fill/all/$iconName.svg';
    }

    // Check if it's already a BAS weather icon name
    final mappedIcon = basIconMap[icon?.toLowerCase()];
    if (mappedIcon != null) {
      return 'assets/weather_icons/bas_weather/production/fill/all/$mappedIcon.svg';
    }

    return 'assets/weather_icons/bas_weather/production/fill/all/cloudy.svg';
  }

  /// Determine if it's currently daytime based on the hour field
  bool _isCurrentlyDay() {
    final now = DateTime.now();
    final forecastTime = now.add(Duration(hours: hour));
    final forecastHour = forecastTime.hour;
    return forecastHour >= 6 && forecastHour < 18;
  }

  /// Fallback Flutter icon
  IconData get fallbackIcon {
    final code = icon?.toLowerCase() ?? '';
    if (code.contains('clear')) return Icons.wb_sunny;
    if (code.contains('partly-cloudy')) return Icons.cloud_queue;
    if (code.contains('cloudy')) return Icons.cloud;
    if (code.contains('rainy') || code.contains('rain')) return Icons.water_drop;
    if (code.contains('thunder')) return Icons.thunderstorm;
    if (code.contains('snow')) return Icons.ac_unit;
    if (code.contains('sleet')) return Icons.grain;
    if (code.contains('foggy')) return Icons.foggy;
    if (code.contains('windy')) return Icons.air;
    return Icons.help_outline;
  }
}

/// Daily forecast entry
class DailyForecast {
  final int dayIndex; // 0 = today, 1 = tomorrow, etc.
  final double? tempHigh;
  final double? tempLow;
  final String? conditions;
  final String? icon;
  final double? precipProbability;
  final String? precipIcon;
  final DateTime? sunrise;
  final DateTime? sunset;

  DailyForecast({
    required this.dayIndex,
    this.tempHigh,
    this.tempLow,
    this.conditions,
    this.icon,
    this.precipProbability,
    this.precipIcon,
    this.sunrise,
    this.sunset,
  });

  /// Get day name from index
  String get dayName {
    if (dayIndex == 0) return 'Today';
    if (dayIndex == 1) return 'Tomorrow';
    final date = DateTime.now().add(Duration(days: dayIndex));
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[date.weekday - 1];
  }

  IconData get fallbackIcon {
    final code = icon?.toLowerCase() ?? '';
    if (code.contains('clear')) return Icons.wb_sunny;
    if (code.contains('partly-cloudy')) return Icons.cloud_queue;
    if (code.contains('cloudy')) return Icons.cloud;
    if (code.contains('rainy') || code.contains('rain')) return Icons.water_drop;
    if (code.contains('thunder')) return Icons.thunderstorm;
    if (code.contains('snow')) return Icons.ac_unit;
    if (code.contains('sleet')) return Icons.grain;
    if (code.contains('foggy')) return Icons.foggy;
    if (code.contains('windy')) return Icons.air;
    return Icons.help_outline;
  }
}

/// Weather effect types for animation
enum WeatherEffectType { none, rain, snow, wind, hail, thunder, sleet }
