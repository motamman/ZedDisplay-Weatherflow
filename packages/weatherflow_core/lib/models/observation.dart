/// Observation model for real-time weather data
/// Supports data from UDP, WebSocket, and REST API sources

/// Source of the observation data
enum ObservationSource { udp, websocket, rest }

/// Precipitation types
enum PrecipType { none, rain, hail, rainAndHail }

/// Real-time observation from a Tempest device
class Observation {
  final DateTime timestamp;
  final int deviceId;
  final ObservationSource source;

  // Wind measurements (all in m/s, direction in degrees)
  final double? windLull;
  final double? windAvg;
  final double? windGust;
  final double? windDirection; // degrees (0-360)

  // Atmospheric
  final double? stationPressure; // Pa
  final double? temperature; // K
  final double? humidity; // 0-1 ratio

  // Light & UV
  final double? illuminance; // lux
  final double? uvIndex;
  final double? solarRadiation; // W/m²

  // Precipitation
  final double? rainAccumulated; // m (total since midnight)
  final double? rainRate; // m/hr
  final PrecipType precipType;

  // Lightning
  final double? lightningDistance; // meters (converted from API km)
  final int? lightningCount; // strikes in last minute

  // Device health
  final double? batteryVoltage;
  final int? reportInterval; // minutes

  // Calculated values
  final double? feelsLike; // K
  final double? dewPoint; // K
  final double? heatIndex; // K
  final double? windChill; // K
  final double? wetBulbTemperature; // K
  final double? deltaTempRatio;
  final double? airDensity; // kg/m³
  final double? seaLevelPressure; // Pa

  const Observation({
    required this.timestamp,
    required this.deviceId,
    this.source = ObservationSource.rest,
    this.windLull,
    this.windAvg,
    this.windGust,
    this.windDirection,
    this.stationPressure,
    this.temperature,
    this.humidity,
    this.illuminance,
    this.uvIndex,
    this.solarRadiation,
    this.rainAccumulated,
    this.rainRate,
    this.precipType = PrecipType.none,
    this.lightningDistance,
    this.lightningCount,
    this.batteryVoltage,
    this.reportInterval,
    this.feelsLike,
    this.dewPoint,
    this.heatIndex,
    this.windChill,
    this.wetBulbTemperature,
    this.deltaTempRatio,
    this.airDensity,
    this.seaLevelPressure,
  });

  /// Parse from UDP obs_st message (Tempest observation)
  /// Format: [epoch, windLull, windAvg, windGust, windDir, pressure, temp, humidity,
  ///          illuminance, uv, solarRad, rainAccum, precipType, lightningDist,
  ///          lightningCount, battery, reportInterval, localDayRainAccum, rainCheck1,
  ///          rainCheck2, localDayFinalRainAccum]
  factory Observation.fromUdpTempest(List<dynamic> obs, int deviceId) {
    return Observation(
      timestamp: DateTime.fromMillisecondsSinceEpoch((obs[0] as int) * 1000),
      deviceId: deviceId,
      source: ObservationSource.udp,
      windLull: (obs[1] as num?)?.toDouble(),
      windAvg: (obs[2] as num?)?.toDouble(),
      windGust: (obs[3] as num?)?.toDouble(),
      windDirection: (obs[4] as num?)?.toDouble(),
      stationPressure: obs[5] != null ? (obs[5] as num).toDouble() * 100 : null, // mbar to Pa
      temperature: obs[6] != null ? (obs[6] as num).toDouble() + 273.15 : null, // C to K
      humidity: obs[7] != null ? (obs[7] as num).toDouble() / 100 : null, // % to ratio
      illuminance: (obs[8] as num?)?.toDouble(),
      uvIndex: (obs[9] as num?)?.toDouble(),
      solarRadiation: (obs[10] as num?)?.toDouble(),
      rainAccumulated: obs[11] != null ? (obs[11] as num).toDouble() / 1000 : null, // mm to m
      precipType: _parsePrecipType(obs[12] as int?),
      lightningDistance: obs[13] != null ? (obs[13] as num).toDouble() * 1000 : null, // km to m
      lightningCount: obs[14] as int?,
      batteryVoltage: (obs[15] as num?)?.toDouble(),
      reportInterval: obs[16] as int?,
    );
  }

  /// Parse from UDP rapid_wind message
  /// Format: [epoch, windSpeed, windDirection]
  factory Observation.fromUdpRapidWind(List<dynamic> obs, int deviceId) {
    return Observation(
      timestamp: DateTime.fromMillisecondsSinceEpoch((obs[0] as int) * 1000),
      deviceId: deviceId,
      source: ObservationSource.udp,
      windAvg: (obs[1] as num?)?.toDouble(),
      windDirection: (obs[2] as num?)?.toDouble(),
    );
  }

  /// Parse from REST API station observation response
  factory Observation.fromRestStation(Map<String, dynamic> json, int deviceId) {
    final obs = json['obs'] as List?;
    if (obs == null || obs.isEmpty) {
      return Observation(
        timestamp: DateTime.now(),
        deviceId: deviceId,
        source: ObservationSource.rest,
      );
    }

    // obs[0] is the observation array
    final data = obs[0] as List;

    return Observation(
      timestamp: DateTime.fromMillisecondsSinceEpoch((data[0] as int) * 1000),
      deviceId: deviceId,
      source: ObservationSource.rest,
      windLull: (data[1] as num?)?.toDouble(),
      windAvg: (data[2] as num?)?.toDouble(),
      windGust: (data[3] as num?)?.toDouble(),
      windDirection: (data[4] as num?)?.toDouble(),
      stationPressure: data[6] != null ? (data[6] as num).toDouble() * 100 : null, // mbar to Pa
      temperature: data[7] != null ? (data[7] as num).toDouble() + 273.15 : null, // C to K
      humidity: data[8] != null ? (data[8] as num).toDouble() / 100 : null, // % to ratio
      illuminance: (data[9] as num?)?.toDouble(),
      uvIndex: (data[10] as num?)?.toDouble(),
      solarRadiation: (data[11] as num?)?.toDouble(),
      rainAccumulated: data[12] != null ? (data[12] as num).toDouble() / 1000 : null, // mm to m
      precipType: _parsePrecipType(data[13] as int?),
      lightningCount: data[14] as int?,
      lightningDistance: data[15] != null ? (data[15] as num).toDouble() * 1000 : null, // km to m
      batteryVoltage: (data[16] as num?)?.toDouble(),
      reportInterval: data[17] as int?,
      // Calculated values from summary
      feelsLike: json['summary']?['feels_like'] != null
          ? (json['summary']['feels_like'] as num).toDouble() + 273.15
          : null,
      dewPoint: json['summary']?['dew_point'] != null
          ? (json['summary']['dew_point'] as num).toDouble() + 273.15
          : null,
      heatIndex: json['summary']?['heat_index'] != null
          ? (json['summary']['heat_index'] as num).toDouble() + 273.15
          : null,
      windChill: json['summary']?['wind_chill'] != null
          ? (json['summary']['wind_chill'] as num).toDouble() + 273.15
          : null,
      seaLevelPressure: json['summary']?['pressure_trend'] != null
          ? (json['summary']['pressure_trend'] as num).toDouble() * 100
          : null,
    );
  }

  /// Parse from WebSocket obs message
  factory Observation.fromWebSocket(Map<String, dynamic> json) {
    final obs = json['obs'] as List?;
    final deviceId = json['device_id'] as int? ?? 0;

    if (obs == null || obs.isEmpty) {
      return Observation(
        timestamp: DateTime.now(),
        deviceId: deviceId,
        source: ObservationSource.websocket,
      );
    }

    final data = obs[0] as List;

    return Observation(
      timestamp: DateTime.fromMillisecondsSinceEpoch((data[0] as int) * 1000),
      deviceId: deviceId,
      source: ObservationSource.websocket,
      windLull: (data[1] as num?)?.toDouble(),
      windAvg: (data[2] as num?)?.toDouble(),
      windGust: (data[3] as num?)?.toDouble(),
      windDirection: (data[4] as num?)?.toDouble(),
      stationPressure: data[6] != null ? (data[6] as num).toDouble() * 100 : null,
      temperature: data[7] != null ? (data[7] as num).toDouble() + 273.15 : null,
      humidity: data[8] != null ? (data[8] as num).toDouble() / 100 : null,
      illuminance: (data[9] as num?)?.toDouble(),
      uvIndex: (data[10] as num?)?.toDouble(),
      solarRadiation: (data[11] as num?)?.toDouble(),
      rainAccumulated: data[12] != null ? (data[12] as num).toDouble() / 1000 : null, // mm to m
      precipType: _parsePrecipType(data[13] as int?),
      lightningCount: data[14] as int?,
      lightningDistance: data[15] != null ? (data[15] as num).toDouble() * 1000 : null, // km to m
      batteryVoltage: (data[16] as num?)?.toDouble(),
      reportInterval: data[17] as int?,
    );
  }

  static PrecipType _parsePrecipType(int? type) {
    switch (type) {
      case 1:
        return PrecipType.rain;
      case 2:
        return PrecipType.hail;
      case 3:
        return PrecipType.rainAndHail;
      default:
        return PrecipType.none;
    }
  }

  /// Merge this observation with rapid wind data
  Observation mergeWithRapidWind(Observation rapidWind) {
    return Observation(
      timestamp: rapidWind.timestamp,
      deviceId: deviceId,
      source: source,
      windLull: windLull,
      windAvg: rapidWind.windAvg ?? windAvg,
      windGust: windGust,
      windDirection: rapidWind.windDirection ?? windDirection,
      stationPressure: stationPressure,
      temperature: temperature,
      humidity: humidity,
      illuminance: illuminance,
      uvIndex: uvIndex,
      solarRadiation: solarRadiation,
      rainAccumulated: rainAccumulated,
      rainRate: rainRate,
      precipType: precipType,
      lightningDistance: lightningDistance,
      lightningCount: lightningCount,
      batteryVoltage: batteryVoltage,
      reportInterval: reportInterval,
      feelsLike: feelsLike,
      dewPoint: dewPoint,
      heatIndex: heatIndex,
      windChill: windChill,
      wetBulbTemperature: wetBulbTemperature,
      deltaTempRatio: deltaTempRatio,
      airDensity: airDensity,
      seaLevelPressure: seaLevelPressure,
    );
  }

  /// Check if this is a rapid wind observation (only has wind data)
  bool get isRapidWind =>
      windAvg != null &&
      temperature == null &&
      stationPressure == null;

  /// Get age of this observation
  Duration get age => DateTime.now().difference(timestamp);

  /// Check if observation is stale (older than 5 minutes)
  bool get isStale => age > const Duration(minutes: 5);
}

/// Lightning strike event
class LightningStrike {
  final DateTime timestamp;
  final int deviceId;
  final double distance; // meters (converted from API km)
  final double energy;

  const LightningStrike({
    required this.timestamp,
    required this.deviceId,
    required this.distance,
    required this.energy,
  });

  factory LightningStrike.fromUdp(Map<String, dynamic> json) {
    final evt = json['evt'] as List;
    return LightningStrike(
      timestamp: DateTime.fromMillisecondsSinceEpoch((evt[0] as int) * 1000),
      deviceId: json['device_id'] as int? ?? 0,
      distance: (evt[1] as num).toDouble() * 1000, // km to m
      energy: (evt[2] as num).toDouble(),
    );
  }
}

/// Rain start event
class RainStartEvent {
  final DateTime timestamp;
  final int deviceId;

  const RainStartEvent({
    required this.timestamp,
    required this.deviceId,
  });

  factory RainStartEvent.fromUdp(Map<String, dynamic> json) {
    final evt = json['evt'] as List;
    return RainStartEvent(
      timestamp: DateTime.fromMillisecondsSinceEpoch((evt[0] as int) * 1000),
      deviceId: json['device_id'] as int? ?? 0,
    );
  }
}
