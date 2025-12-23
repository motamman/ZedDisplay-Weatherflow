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
  final double? moonPhase;    // 0-1 (0=new, 0.5=full) for this day
  final double? moonFraction; // 0-1 illumination fraction for this day

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
    this.moonPhase,
    this.moonFraction,
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

  /// Latitude for hemisphere-aware moon display
  /// Negative = Southern Hemisphere (moon appears flipped)
  final double? latitude;

  /// UTC offset in seconds for the location's timezone
  /// Used to display times in the location's local time, not device time
  final int? utcOffsetSeconds;

  const SunMoonTimes({
    this.days = const [],
    this.todayIndex = 0,
    this.moonPhase,
    this.moonFraction,
    this.moonAngle,
    this.latitude,
    this.utcOffsetSeconds,
  });

  /// Whether location is in Southern Hemisphere
  bool get isSouthernHemisphere => (latitude ?? 0) < 0;

  /// Convert a DateTime to the location's timezone
  /// If utcOffsetSeconds is not set, falls back to device local time
  DateTime toLocationTime(DateTime utcTime) {
    if (utcOffsetSeconds == null) {
      return utcTime.toLocal();
    }
    // Convert to UTC first, then add the location's offset
    final utc = utcTime.toUtc();
    return utc.add(Duration(seconds: utcOffsetSeconds!));
  }

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
  final DateTime? time; // Actual time from API
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
  final double? windGust; // m/s
  final int? beaufort; // Beaufort scale 0-12
  final bool? isDay; // Whether it's daytime
  final double? uvIndex;
  final String? precipType; // rain, snow, sleet, hail, etc.
  final String? precipIcon;

  // Solar radiation fields (W/m²)
  final double? shortwaveRadiation;       // Total global horizontal irradiance
  final double? directRadiation;          // Direct radiation on horizontal surface
  final double? diffuseRadiation;         // Scattered/indirect radiation
  final double? directNormalIrradiance;   // Direct Normal Irradiance
  final double? globalTiltedIrradiance;   // Irradiance on tilted surface

  HourlyForecast({
    required this.hour,
    this.time,
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
    this.windGust,
    this.beaufort,
    this.isDay,
    this.uvIndex,
    this.precipType,
    this.precipIcon,
    this.shortwaveRadiation,
    this.directRadiation,
    this.diffuseRadiation,
    this.directNormalIrradiance,
    this.globalTiltedIrradiance,
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
    // OpenMeteo WMO icon names from weather_code.dart
    'mostly-clear-day': 'clear-day',
    'mostly-clear-night': 'clear-night',
    'freezing-drizzle': 'sleet',
    'rain-light': 'partly-cloudy-day-rain',
    'rain-heavy': 'rain',
    'freezing-rain': 'sleet',
    'snow-light': 'partly-cloudy-day-snow',
    'snow-heavy': 'snow',
    'snow-grains': 'snow',
    'showers-day': 'partly-cloudy-day-rain',
    'showers-night': 'partly-cloudy-night-rain',
    'showers': 'rain',
    'snow-showers': 'snow',
    'thunderstorm-hail': 'thunderstorms-rain',
  };

  /// Get asset path for weather icon
  String get weatherIconAsset {
    if (icon == null) return 'assets/weather_icons/bas_weather/production/fill/all/cloudy.svg';

    // Check if it's a WMO code (numeric string like "0", "45", "95")
    if (wmoIconMap.containsKey(icon)) {
      final isDay = _isCurrentlyDay();
      final dayNight = isDay ? 'day' : 'night';
      final iconName = wmoIconMap[icon]![dayNight]!;
      return 'assets/weather_icons/bas_weather/production/fill/all/$iconName.svg';
    }

    // Check if it's OpenMeteo WMO format (e.g., "wmo_0_day.svg", "wmo_45_night.svg")
    final wmoMatch = RegExp(r'wmo_(\d+)_(day|night)\.svg').firstMatch(icon!);
    if (wmoMatch != null) {
      final wmoCode = wmoMatch.group(1)!;
      final dayNight = wmoMatch.group(2)!;
      if (wmoIconMap.containsKey(wmoCode)) {
        final iconName = wmoIconMap[wmoCode]![dayNight]!;
        return 'assets/weather_icons/bas_weather/production/fill/all/$iconName.svg';
      }
    }

    // Check if it's a Meteoblue icon (e.g., "07_night.svg")
    if (icon!.contains('_') && icon!.endsWith('.svg') && !icon!.startsWith('wmo_')) {
      // Convert to monochrome hollow version
      final baseName = icon!.replaceAll('.svg', '');
      return 'assets/weather_icons/meteoblue_specific/monochrome_hollow_hourly/${baseName}_monochrome_hollow.svg';
    }

    // Check if it's already a BAS weather icon name
    final mappedIcon = basIconMap[icon?.toLowerCase()];
    if (mappedIcon != null) {
      return 'assets/weather_icons/bas_weather/production/fill/all/$mappedIcon.svg';
    }

    // Fallback
    return 'assets/weather_icons/bas_weather/production/fill/all/cloudy.svg';
  }

  /// Determine if it's currently daytime based on API's isDay field (or fallback to hour)
  bool _isCurrentlyDay() {
    // Use API's isDay field if available (considers actual sunrise/sunset)
    if (isDay != null) {
      return isDay!;
    }
    // Fallback: Use actual time from API if available
    if (time != null) {
      final forecastHour = time!.hour;
      return forecastHour >= 6 && forecastHour < 18;
    }
    // Fallback to calculating from hour index
    final now = DateTime.now();
    final forecastTime = now.add(Duration(hours: hour));
    final forecastHour = forecastTime.hour;
    return forecastHour >= 6 && forecastHour < 18;
  }

  /// Fallback Flutter icon
  IconData get fallbackIcon {
    final code = icon ?? '';
    // Check WMO codes first
    if (wmoIconMap.containsKey(code)) {
      final iconName = wmoIconMap[code]!['day']!;
      if (iconName.contains('clear')) return Icons.wb_sunny;
      if (iconName.contains('partly-cloudy')) return Icons.cloud_queue;
      if (iconName.contains('cloudy') || iconName.contains('overcast')) return Icons.cloud;
      if (iconName.contains('rain')) return Icons.water_drop;
      if (iconName.contains('thunder')) return Icons.thunderstorm;
      if (iconName.contains('snow')) return Icons.ac_unit;
      if (iconName.contains('sleet')) return Icons.grain;
      if (iconName.contains('fog')) return Icons.foggy;
      if (iconName.contains('drizzle')) return Icons.water_drop;
      return Icons.cloud;
    }
    // Check text-based icon names
    final lowerCode = code.toLowerCase();
    if (lowerCode.contains('clear')) return Icons.wb_sunny;
    if (lowerCode.contains('partly-cloudy')) return Icons.cloud_queue;
    if (lowerCode.contains('cloudy')) return Icons.cloud;
    if (lowerCode.contains('rainy') || lowerCode.contains('rain')) return Icons.water_drop;
    if (lowerCode.contains('thunder')) return Icons.thunderstorm;
    if (lowerCode.contains('snow')) return Icons.ac_unit;
    if (lowerCode.contains('sleet')) return Icons.grain;
    if (lowerCode.contains('foggy') || lowerCode.contains('fog')) return Icons.foggy;
    if (lowerCode.contains('drizzle')) return Icons.water_drop;
    if (lowerCode.contains('windy')) return Icons.air;
    return Icons.cloud;
  }
}

/// Daily forecast entry
class DailyForecast {
  final int dayIndex; // 0 = today, 1 = tomorrow, etc.
  final DateTime? date; // Actual date from API
  final double? tempHigh;
  final double? tempLow;
  final String? conditions;
  final String? icon;
  final double? precipProbability;
  final String? precipIcon;
  final DateTime? sunrise;
  final DateTime? sunset;
  final double? shortwaveRadiationSum; // MJ/m² daily total solar radiation

  DailyForecast({
    required this.dayIndex,
    this.date,
    this.tempHigh,
    this.tempLow,
    this.conditions,
    this.icon,
    this.precipProbability,
    this.precipIcon,
    this.sunrise,
    this.sunset,
    this.shortwaveRadiationSum,
  });

  /// Get day name from date or fallback to index calculation
  String get dayName {
    // Use actual date if available
    if (date != null) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final forecastDate = DateTime(date!.year, date!.month, date!.day);

      if (forecastDate == today) return 'Today';
      if (forecastDate == today.add(const Duration(days: 1))) return 'Tomorrow';

      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[date!.weekday - 1];
    }
    // Fallback to index-based calculation
    if (dayIndex == 0) return 'Today';
    if (dayIndex == 1) return 'Tomorrow';
    final calcDate = DateTime.now().add(Duration(days: dayIndex));
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[calcDate.weekday - 1];
  }

  IconData get fallbackIcon {
    final code = icon ?? '';
    // Check WMO codes first (reuse HourlyForecast's mapping)
    if (HourlyForecast.wmoIconMap.containsKey(code)) {
      final iconName = HourlyForecast.wmoIconMap[code]!['day']!;
      if (iconName.contains('clear')) return Icons.wb_sunny;
      if (iconName.contains('partly-cloudy')) return Icons.cloud_queue;
      if (iconName.contains('cloudy') || iconName.contains('overcast')) return Icons.cloud;
      if (iconName.contains('rain')) return Icons.water_drop;
      if (iconName.contains('thunder')) return Icons.thunderstorm;
      if (iconName.contains('snow')) return Icons.ac_unit;
      if (iconName.contains('sleet')) return Icons.grain;
      if (iconName.contains('fog')) return Icons.foggy;
      if (iconName.contains('drizzle')) return Icons.water_drop;
      return Icons.cloud;
    }
    // Check text-based icon names
    final lowerCode = code.toLowerCase();
    if (lowerCode.contains('clear')) return Icons.wb_sunny;
    if (lowerCode.contains('partly-cloudy')) return Icons.cloud_queue;
    if (lowerCode.contains('cloudy')) return Icons.cloud;
    if (lowerCode.contains('rainy') || lowerCode.contains('rain')) return Icons.water_drop;
    if (lowerCode.contains('thunder')) return Icons.thunderstorm;
    if (lowerCode.contains('snow')) return Icons.ac_unit;
    if (lowerCode.contains('sleet')) return Icons.grain;
    if (lowerCode.contains('foggy') || lowerCode.contains('fog')) return Icons.foggy;
    if (lowerCode.contains('drizzle')) return Icons.water_drop;
    if (lowerCode.contains('windy')) return Icons.air;
    return Icons.cloud;
  }

  /// Get weather icon asset path
  String get weatherIconAsset {
    if (icon == null) return 'assets/weather_icons/bas_weather/production/fill/all/cloudy.svg';

    // Check if it's a WMO code - use HourlyForecast's mapping
    if (HourlyForecast.wmoIconMap.containsKey(icon)) {
      final iconName = HourlyForecast.wmoIconMap[icon]!['day']!;
      return 'assets/weather_icons/bas_weather/production/fill/all/$iconName.svg';
    }

    // Map common icon names to BAS weather icons
    final mappedIcon = HourlyForecast.basIconMap[icon?.toLowerCase()];
    if (mappedIcon != null) {
      return 'assets/weather_icons/bas_weather/production/fill/all/$mappedIcon.svg';
    }

    return 'assets/weather_icons/bas_weather/production/fill/all/cloudy.svg';
  }
}

/// Weather effect types for animation
enum WeatherEffectType { none, rain, snow, wind, hail, thunder, sleet }
