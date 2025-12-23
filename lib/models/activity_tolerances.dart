/// Activity tolerance definitions for the Activity Forecaster
///
/// Defines tolerance ranges and weights for scoring weather conditions
/// against user preferences for various activities.

import 'activity_definition.dart';

/// Tolerance range for a numeric parameter
/// All values stored in SI units
class RangeTolerance {
  /// Minimum value of ideal range (score = 100)
  final double idealMin;

  /// Maximum value of ideal range (score = 100)
  final double idealMax;

  /// Minimum acceptable value (score = 0 below this)
  final double acceptableMin;

  /// Maximum acceptable value (score = 0 above this)
  final double acceptableMax;

  /// Weight for this parameter (0-10, 0 = ignore)
  final int weight;

  const RangeTolerance({
    required this.idealMin,
    required this.idealMax,
    required this.acceptableMin,
    required this.acceptableMax,
    this.weight = 5,
  });

  /// Create from JSON map
  factory RangeTolerance.fromJson(Map<String, dynamic> json) {
    return RangeTolerance(
      idealMin: (json['idealMin'] as num).toDouble(),
      idealMax: (json['idealMax'] as num).toDouble(),
      acceptableMin: (json['acceptableMin'] as num).toDouble(),
      acceptableMax: (json['acceptableMax'] as num).toDouble(),
      weight: json['weight'] as int? ?? 5,
    );
  }

  /// Convert to JSON map
  Map<String, dynamic> toJson() => {
        'idealMin': idealMin,
        'idealMax': idealMax,
        'acceptableMin': acceptableMin,
        'acceptableMax': acceptableMax,
        'weight': weight,
      };

  /// Create a copy with modified values
  RangeTolerance copyWith({
    double? idealMin,
    double? idealMax,
    double? acceptableMin,
    double? acceptableMax,
    int? weight,
  }) {
    return RangeTolerance(
      idealMin: idealMin ?? this.idealMin,
      idealMax: idealMax ?? this.idealMax,
      acceptableMin: acceptableMin ?? this.acceptableMin,
      acceptableMax: acceptableMax ?? this.acceptableMax,
      weight: weight ?? this.weight,
    );
  }
}

/// Tolerance for precipitation types
class PrecipitationTolerance {
  /// Set of acceptable WMO weather codes
  /// See: https://open-meteo.com/en/docs (weather codes)
  final Set<int> acceptableCodes;

  /// Weight for precipitation tolerance (0-10)
  final int weight;

  const PrecipitationTolerance({
    required this.acceptableCodes,
    this.weight = 5,
  });

  /// Common precipitation code groups
  static const clearCodes = {0, 1, 2, 3}; // Clear to overcast
  static const fogCodes = {45, 48}; // Fog
  static const drizzleCodes = {51, 53, 55, 56, 57}; // Drizzle
  static const rainCodes = {61, 63, 65, 66, 67, 80, 81, 82}; // Rain
  static const snowCodes = {71, 73, 75, 77, 85, 86}; // Snow
  static const thunderCodes = {95, 96, 99}; // Thunderstorm

  /// Create from JSON map
  factory PrecipitationTolerance.fromJson(Map<String, dynamic> json) {
    return PrecipitationTolerance(
      acceptableCodes:
          (json['acceptableCodes'] as List).map((e) => e as int).toSet(),
      weight: json['weight'] as int? ?? 5,
    );
  }

  /// Convert to JSON map
  Map<String, dynamic> toJson() => {
        'acceptableCodes': acceptableCodes.toList(),
        'weight': weight,
      };

  /// Create a copy with modified values
  PrecipitationTolerance copyWith({
    Set<int>? acceptableCodes,
    int? weight,
  }) {
    return PrecipitationTolerance(
      acceptableCodes: acceptableCodes ?? this.acceptableCodes,
      weight: weight ?? this.weight,
    );
  }
}

/// Seasonal profile for temperature adjustment
enum Season {
  winter,
  spring,
  summer,
  autumn;

  String get displayName {
    switch (this) {
      case Season.winter:
        return 'Winter';
      case Season.spring:
        return 'Spring';
      case Season.summer:
        return 'Summer';
      case Season.autumn:
        return 'Autumn';
    }
  }

  /// Temperature offset in Kelvin for this season
  double get temperatureOffset {
    switch (this) {
      case Season.winter:
        return -10.0; // Colder temps acceptable
      case Season.spring:
        return -2.0;
      case Season.summer:
        return 5.0; // Warmer temps acceptable
      case Season.autumn:
        return 0.0;
    }
  }
}

/// Seasonal profile configuration
class SeasonalProfile {
  /// Whether to auto-detect season based on location/date
  final bool autoDetect;

  /// Manual season override (used when autoDetect is false)
  final Season? manualSeason;

  const SeasonalProfile({
    this.autoDetect = true,
    this.manualSeason,
  });

  /// Get current season based on latitude and month
  static Season detectSeason(double latitude, int month) {
    // Northern hemisphere
    final isNorthern = latitude >= 0;

    // Determine season by month
    Season season;
    if (month >= 3 && month <= 5) {
      season = Season.spring;
    } else if (month >= 6 && month <= 8) {
      season = Season.summer;
    } else if (month >= 9 && month <= 11) {
      season = Season.autumn;
    } else {
      season = Season.winter;
    }

    // Flip for southern hemisphere
    if (!isNorthern) {
      switch (season) {
        case Season.winter:
          season = Season.summer;
          break;
        case Season.summer:
          season = Season.winter;
          break;
        case Season.spring:
          season = Season.autumn;
          break;
        case Season.autumn:
          season = Season.spring;
          break;
      }
    }

    return season;
  }

  /// Get effective season (auto-detected or manual)
  Season getEffectiveSeason(double latitude, int month) {
    if (autoDetect) {
      return detectSeason(latitude, month);
    }
    return manualSeason ?? Season.autumn;
  }

  /// Create from JSON map
  factory SeasonalProfile.fromJson(Map<String, dynamic> json) {
    return SeasonalProfile(
      autoDetect: json['autoDetect'] as bool? ?? true,
      manualSeason: json['manualSeason'] != null
          ? Season.values.firstWhere((e) => e.name == json['manualSeason'])
          : null,
    );
  }

  /// Convert to JSON map
  Map<String, dynamic> toJson() => {
        'autoDetect': autoDetect,
        'manualSeason': manualSeason?.name,
      };

  /// Create a copy with modified values
  SeasonalProfile copyWith({
    bool? autoDetect,
    Season? manualSeason,
  }) {
    return SeasonalProfile(
      autoDetect: autoDetect ?? this.autoDetect,
      manualSeason: manualSeason ?? this.manualSeason,
    );
  }
}

/// Complete tolerance configuration for an activity
class ActivityTolerances {
  /// Activity type this configuration applies to
  final ActivityType activity;

  /// Whether this activity is enabled for scoring
  final bool enabled;

  /// Cloud cover tolerance (ratio 0-1)
  final RangeTolerance cloudCover;

  /// Wind speed tolerance (m/s)
  final RangeTolerance windSpeed;

  /// Temperature tolerance (Kelvin)
  final RangeTolerance temperature;

  /// Precipitation probability tolerance (ratio 0-1)
  final RangeTolerance precipProbability;

  /// Precipitation type tolerance
  final PrecipitationTolerance precipType;

  /// UV index tolerance (0-11+)
  final RangeTolerance uvIndex;

  /// Wave height tolerance (meters) - marine only
  final RangeTolerance? waveHeight;

  /// Wave period tolerance (seconds) - marine only
  final RangeTolerance? wavePeriod;

  /// Seasonal profile for temperature adjustment
  final SeasonalProfile seasonalProfile;

  const ActivityTolerances({
    required this.activity,
    this.enabled = false,
    required this.cloudCover,
    required this.windSpeed,
    required this.temperature,
    required this.precipProbability,
    required this.precipType,
    required this.uvIndex,
    this.waveHeight,
    this.wavePeriod,
    this.seasonalProfile = const SeasonalProfile(),
  });

  /// Create from JSON map
  factory ActivityTolerances.fromJson(Map<String, dynamic> json) {
    final activityKey = json['activity'] as String;
    final activity = ActivityTypeExtension.fromKey(activityKey);
    if (activity == null) {
      throw ArgumentError('Unknown activity type: $activityKey');
    }

    return ActivityTolerances(
      activity: activity,
      enabled: json['enabled'] as bool? ?? false,
      cloudCover: RangeTolerance.fromJson(json['cloudCover']),
      windSpeed: RangeTolerance.fromJson(json['windSpeed']),
      temperature: RangeTolerance.fromJson(json['temperature']),
      precipProbability: RangeTolerance.fromJson(json['precipProbability']),
      precipType: PrecipitationTolerance.fromJson(json['precipType']),
      uvIndex: RangeTolerance.fromJson(json['uvIndex']),
      waveHeight: json['waveHeight'] != null
          ? RangeTolerance.fromJson(json['waveHeight'])
          : null,
      wavePeriod: json['wavePeriod'] != null
          ? RangeTolerance.fromJson(json['wavePeriod'])
          : null,
      seasonalProfile: json['seasonalProfile'] != null
          ? SeasonalProfile.fromJson(json['seasonalProfile'])
          : const SeasonalProfile(),
    );
  }

  /// Convert to JSON map
  Map<String, dynamic> toJson() => {
        'activity': activity.key,
        'enabled': enabled,
        'cloudCover': cloudCover.toJson(),
        'windSpeed': windSpeed.toJson(),
        'temperature': temperature.toJson(),
        'precipProbability': precipProbability.toJson(),
        'precipType': precipType.toJson(),
        'uvIndex': uvIndex.toJson(),
        if (waveHeight != null) 'waveHeight': waveHeight!.toJson(),
        if (wavePeriod != null) 'wavePeriod': wavePeriod!.toJson(),
        'seasonalProfile': seasonalProfile.toJson(),
      };

  /// Create a copy with modified values
  ActivityTolerances copyWith({
    ActivityType? activity,
    bool? enabled,
    RangeTolerance? cloudCover,
    RangeTolerance? windSpeed,
    RangeTolerance? temperature,
    RangeTolerance? precipProbability,
    PrecipitationTolerance? precipType,
    RangeTolerance? uvIndex,
    RangeTolerance? waveHeight,
    RangeTolerance? wavePeriod,
    SeasonalProfile? seasonalProfile,
  }) {
    return ActivityTolerances(
      activity: activity ?? this.activity,
      enabled: enabled ?? this.enabled,
      cloudCover: cloudCover ?? this.cloudCover,
      windSpeed: windSpeed ?? this.windSpeed,
      temperature: temperature ?? this.temperature,
      precipProbability: precipProbability ?? this.precipProbability,
      precipType: precipType ?? this.precipType,
      uvIndex: uvIndex ?? this.uvIndex,
      waveHeight: waveHeight ?? this.waveHeight,
      wavePeriod: wavePeriod ?? this.wavePeriod,
      seasonalProfile: seasonalProfile ?? this.seasonalProfile,
    );
  }
}

/// Default tolerances factory
class DefaultTolerances {
  /// Get default tolerances for an activity type
  static ActivityTolerances forActivity(ActivityType activity) {
    switch (activity) {
      case ActivityType.running:
        return _runningDefaults;
      case ActivityType.cycling:
        return _cyclingDefaults;
      case ActivityType.walking:
        return _walkingDefaults;
      case ActivityType.hiking:
        return _hikingDefaults;
      case ActivityType.beingOutside:
        return _beingOutsideDefaults;
      case ActivityType.skiing:
        return _skiingDefaults;
      case ActivityType.motorBoating:
        return _motorBoatingDefaults;
      case ActivityType.sailing:
        return _sailingDefaults;
      case ActivityType.kitesurfing:
        return _kitesurfingDefaults;
      case ActivityType.surfing:
        return _surfingDefaults;
      case ActivityType.swimming:
        return _swimmingDefaults;
    }
  }

  // Base land activity tolerances
  static const _baseLandCloudCover = RangeTolerance(
    idealMin: 0.0,
    idealMax: 0.5,
    acceptableMin: 0.0,
    acceptableMax: 1.0,
    weight: 3,
  );

  static const _baseLandPrecipProb = RangeTolerance(
    idealMin: 0.0,
    idealMax: 0.1,
    acceptableMin: 0.0,
    acceptableMax: 0.5,
    weight: 8,
  );

  static final _baseLandPrecipType = PrecipitationTolerance(
    acceptableCodes: {
      ...PrecipitationTolerance.clearCodes,
      ...PrecipitationTolerance.fogCodes,
    },
    weight: 7,
  );

  static const _baseLandUvIndex = RangeTolerance(
    idealMin: 0.0,
    idealMax: 6.0,
    acceptableMin: 0.0,
    acceptableMax: 10.0,
    weight: 4,
  );

  // Running defaults - moderate conditions, low wind
  static final _runningDefaults = ActivityTolerances(
    activity: ActivityType.running,
    cloudCover: _baseLandCloudCover,
    windSpeed: const RangeTolerance(
      idealMin: 0.0,
      idealMax: 5.0, // ~18 km/h
      acceptableMin: 0.0,
      acceptableMax: 10.0, // ~36 km/h
      weight: 6,
    ),
    temperature: const RangeTolerance(
      idealMin: 283.15, // 10°C
      idealMax: 293.15, // 20°C
      acceptableMin: 268.15, // -5°C
      acceptableMax: 303.15, // 30°C
      weight: 7,
    ),
    precipProbability: _baseLandPrecipProb,
    precipType: _baseLandPrecipType,
    uvIndex: _baseLandUvIndex,
  );

  // Cycling defaults - similar to running but more wind sensitive
  static final _cyclingDefaults = ActivityTolerances(
    activity: ActivityType.cycling,
    cloudCover: _baseLandCloudCover,
    windSpeed: const RangeTolerance(
      idealMin: 0.0,
      idealMax: 4.0, // ~14 km/h
      acceptableMin: 0.0,
      acceptableMax: 8.0, // ~29 km/h
      weight: 8,
    ),
    temperature: const RangeTolerance(
      idealMin: 285.15, // 12°C
      idealMax: 295.15, // 22°C
      acceptableMin: 273.15, // 0°C
      acceptableMax: 305.15, // 32°C
      weight: 6,
    ),
    precipProbability: _baseLandPrecipProb,
    precipType: _baseLandPrecipType,
    uvIndex: _baseLandUvIndex,
  );

  // Walking defaults - most tolerant
  static final _walkingDefaults = ActivityTolerances(
    activity: ActivityType.walking,
    cloudCover: _baseLandCloudCover.copyWith(weight: 2),
    windSpeed: const RangeTolerance(
      idealMin: 0.0,
      idealMax: 6.0,
      acceptableMin: 0.0,
      acceptableMax: 12.0,
      weight: 4,
    ),
    temperature: const RangeTolerance(
      idealMin: 280.15, // 7°C
      idealMax: 298.15, // 25°C
      acceptableMin: 263.15, // -10°C
      acceptableMax: 308.15, // 35°C
      weight: 5,
    ),
    precipProbability: _baseLandPrecipProb.copyWith(weight: 6),
    precipType: _baseLandPrecipType.copyWith(weight: 5),
    uvIndex: _baseLandUvIndex,
  );

  // Hiking defaults - more tolerant of conditions
  static final _hikingDefaults = ActivityTolerances(
    activity: ActivityType.hiking,
    cloudCover: _baseLandCloudCover.copyWith(weight: 2),
    windSpeed: const RangeTolerance(
      idealMin: 0.0,
      idealMax: 6.0,
      acceptableMin: 0.0,
      acceptableMax: 15.0,
      weight: 5,
    ),
    temperature: const RangeTolerance(
      idealMin: 278.15, // 5°C
      idealMax: 293.15, // 20°C
      acceptableMin: 263.15, // -10°C
      acceptableMax: 303.15, // 30°C
      weight: 6,
    ),
    precipProbability: _baseLandPrecipProb,
    precipType: _baseLandPrecipType,
    uvIndex: const RangeTolerance(
      idealMin: 0.0,
      idealMax: 5.0,
      acceptableMin: 0.0,
      acceptableMax: 8.0,
      weight: 5,
    ),
  );

  // Being outside defaults - general outdoor comfort
  static final _beingOutsideDefaults = ActivityTolerances(
    activity: ActivityType.beingOutside,
    cloudCover: const RangeTolerance(
      idealMin: 0.0,
      idealMax: 0.3,
      acceptableMin: 0.0,
      acceptableMax: 0.8,
      weight: 5,
    ),
    windSpeed: const RangeTolerance(
      idealMin: 0.0,
      idealMax: 5.0,
      acceptableMin: 0.0,
      acceptableMax: 10.0,
      weight: 5,
    ),
    temperature: const RangeTolerance(
      idealMin: 291.15, // 18°C
      idealMax: 299.15, // 26°C
      acceptableMin: 278.15, // 5°C
      acceptableMax: 308.15, // 35°C
      weight: 7,
    ),
    precipProbability: _baseLandPrecipProb,
    precipType: _baseLandPrecipType,
    uvIndex: _baseLandUvIndex,
  );

  // Skiing defaults - cold weather, snow acceptable
  static final _skiingDefaults = ActivityTolerances(
    activity: ActivityType.skiing,
    cloudCover: const RangeTolerance(
      idealMin: 0.0,
      idealMax: 0.6,
      acceptableMin: 0.0,
      acceptableMax: 1.0,
      weight: 3,
    ),
    windSpeed: const RangeTolerance(
      idealMin: 0.0,
      idealMax: 6.0,
      acceptableMin: 0.0,
      acceptableMax: 15.0,
      weight: 7,
    ),
    temperature: const RangeTolerance(
      idealMin: 263.15, // -10°C
      idealMax: 273.15, // 0°C
      acceptableMin: 248.15, // -25°C
      acceptableMax: 278.15, // 5°C
      weight: 6,
    ),
    precipProbability: const RangeTolerance(
      idealMin: 0.0,
      idealMax: 0.3,
      acceptableMin: 0.0,
      acceptableMax: 0.7,
      weight: 5,
    ),
    precipType: PrecipitationTolerance(
      acceptableCodes: {
        ...PrecipitationTolerance.clearCodes,
        ...PrecipitationTolerance.snowCodes,
      },
      weight: 6,
    ),
    uvIndex: const RangeTolerance(
      idealMin: 0.0,
      idealMax: 4.0,
      acceptableMin: 0.0,
      acceptableMax: 8.0,
      weight: 3,
    ),
  );

  // Motor boating defaults - calm seas preferred
  static final _motorBoatingDefaults = ActivityTolerances(
    activity: ActivityType.motorBoating,
    cloudCover: _baseLandCloudCover,
    windSpeed: const RangeTolerance(
      idealMin: 0.0,
      idealMax: 6.0, // BF 3-4
      acceptableMin: 0.0,
      acceptableMax: 12.0, // BF 6
      weight: 7,
    ),
    temperature: const RangeTolerance(
      idealMin: 288.15, // 15°C
      idealMax: 303.15, // 30°C
      acceptableMin: 278.15, // 5°C
      acceptableMax: 313.15, // 40°C
      weight: 4,
    ),
    precipProbability: _baseLandPrecipProb,
    precipType: _baseLandPrecipType,
    uvIndex: _baseLandUvIndex,
    waveHeight: const RangeTolerance(
      idealMin: 0.0,
      idealMax: 0.5, // Calm to slight
      acceptableMin: 0.0,
      acceptableMax: 1.5, // Moderate
      weight: 8,
    ),
    wavePeriod: const RangeTolerance(
      idealMin: 4.0,
      idealMax: 10.0,
      acceptableMin: 2.0,
      acceptableMax: 15.0,
      weight: 4,
    ),
  );

  // Sailing defaults - needs wind, moderate waves OK
  static final _sailingDefaults = ActivityTolerances(
    activity: ActivityType.sailing,
    cloudCover: _baseLandCloudCover,
    windSpeed: const RangeTolerance(
      idealMin: 4.0, // BF 3 - need some wind
      idealMax: 10.0, // BF 5
      acceptableMin: 2.0, // BF 2
      acceptableMax: 15.0, // BF 7
      weight: 9,
    ),
    temperature: const RangeTolerance(
      idealMin: 285.15, // 12°C
      idealMax: 300.15, // 27°C
      acceptableMin: 275.15, // 2°C
      acceptableMax: 310.15, // 37°C
      weight: 3,
    ),
    precipProbability: _baseLandPrecipProb,
    precipType: _baseLandPrecipType,
    uvIndex: _baseLandUvIndex,
    waveHeight: const RangeTolerance(
      idealMin: 0.0,
      idealMax: 1.0,
      acceptableMin: 0.0,
      acceptableMax: 2.5,
      weight: 6,
    ),
    wavePeriod: const RangeTolerance(
      idealMin: 4.0,
      idealMax: 12.0,
      acceptableMin: 2.0,
      acceptableMax: 18.0,
      weight: 3,
    ),
  );

  // Kitesurfing defaults - needs good wind AND manageable waves
  static final _kitesurfingDefaults = ActivityTolerances(
    activity: ActivityType.kitesurfing,
    cloudCover: _baseLandCloudCover,
    windSpeed: const RangeTolerance(
      idealMin: 7.0, // ~25 km/h - good kite wind
      idealMax: 14.0, // ~50 km/h
      acceptableMin: 5.0, // ~18 km/h minimum
      acceptableMax: 18.0, // ~65 km/h strong
      weight: 10, // Critical for kitesurfing
    ),
    temperature: const RangeTolerance(
      idealMin: 288.15, // 15°C
      idealMax: 303.15, // 30°C
      acceptableMin: 283.15, // 10°C
      acceptableMax: 313.15, // 40°C
      weight: 3,
    ),
    precipProbability: _baseLandPrecipProb,
    precipType: _baseLandPrecipType,
    uvIndex: _baseLandUvIndex,
    waveHeight: const RangeTolerance(
      idealMin: 0.0,
      idealMax: 1.0, // Flat to small chop
      acceptableMin: 0.0,
      acceptableMax: 2.0, // Moderate waves OK
      weight: 5,
    ),
    wavePeriod: const RangeTolerance(
      idealMin: 3.0,
      idealMax: 8.0,
      acceptableMin: 2.0,
      acceptableMax: 12.0,
      weight: 3,
    ),
  );

  // Surfing defaults - needs waves, prefers less wind
  static final _surfingDefaults = ActivityTolerances(
    activity: ActivityType.surfing,
    cloudCover: _baseLandCloudCover.copyWith(weight: 1),
    windSpeed: const RangeTolerance(
      idealMin: 0.0, // Glassy preferred
      idealMax: 4.0, // Light wind OK
      acceptableMin: 0.0,
      acceptableMax: 8.0, // Choppy above this
      weight: 7,
    ),
    temperature: const RangeTolerance(
      idealMin: 285.15, // 12°C (wetsuit)
      idealMax: 305.15, // 32°C
      acceptableMin: 278.15, // 5°C (thick wetsuit)
      acceptableMax: 313.15, // 40°C
      weight: 2,
    ),
    precipProbability: const RangeTolerance(
      idealMin: 0.0,
      idealMax: 0.3,
      acceptableMin: 0.0,
      acceptableMax: 0.8, // Can surf in rain
      weight: 2,
    ),
    precipType: PrecipitationTolerance(
      acceptableCodes: {
        ...PrecipitationTolerance.clearCodes,
        ...PrecipitationTolerance.drizzleCodes,
        ...PrecipitationTolerance.rainCodes,
      },
      weight: 2,
    ),
    uvIndex: _baseLandUvIndex.copyWith(weight: 2),
    waveHeight: const RangeTolerance(
      idealMin: 0.5, // Need some waves
      idealMax: 2.0, // Head high
      acceptableMin: 0.3, // Small but surfable
      acceptableMax: 3.5, // Overhead+
      weight: 10, // Critical for surfing
    ),
    wavePeriod: const RangeTolerance(
      idealMin: 8.0, // Good ground swell
      idealMax: 14.0, // Clean long period
      acceptableMin: 5.0, // Short period wind swell
      acceptableMax: 20.0, // Very long period
      weight: 8,
    ),
  );

  // Swimming defaults - warm temps, calm water, feels like temp is critical
  static final _swimmingDefaults = ActivityTolerances(
    activity: ActivityType.swimming,
    cloudCover: _baseLandCloudCover.copyWith(weight: 2),
    windSpeed: const RangeTolerance(
      idealMin: 0.0,
      idealMax: 4.0, // Light breeze
      acceptableMin: 0.0,
      acceptableMax: 8.0, // Moderate wind
      weight: 5,
    ),
    temperature: const RangeTolerance(
      idealMin: 293.15, // 20°C - comfortable for swimming
      idealMax: 308.15, // 35°C
      acceptableMin: 283.15, // 10°C (with wetsuit)
      acceptableMax: 318.15, // 45°C
      weight: 9, // Feels like temp is critical for swimming
    ),
    precipProbability: const RangeTolerance(
      idealMin: 0.0,
      idealMax: 0.2,
      acceptableMin: 0.0,
      acceptableMax: 0.6, // Can swim in light rain
      weight: 3,
    ),
    precipType: PrecipitationTolerance(
      acceptableCodes: {
        ...PrecipitationTolerance.clearCodes,
        ...PrecipitationTolerance.drizzleCodes,
        ...PrecipitationTolerance.rainCodes,
      },
      weight: 3,
    ),
    uvIndex: const RangeTolerance(
      idealMin: 0.0,
      idealMax: 5.0,
      acceptableMin: 0.0,
      acceptableMax: 9.0,
      weight: 4,
    ),
    waveHeight: const RangeTolerance(
      idealMin: 0.0,
      idealMax: 0.5, // Calm to slight
      acceptableMin: 0.0,
      acceptableMax: 1.0, // Small waves OK
      weight: 7,
    ),
    wavePeriod: const RangeTolerance(
      idealMin: 3.0,
      idealMax: 10.0,
      acceptableMin: 2.0,
      acceptableMax: 15.0,
      weight: 2,
    ),
  );
}
