/// Observation model for real-time weather data
/// Supports data from UDP, WebSocket, and REST API sources

/// Source of the observation data
enum ObservationSource { udp, websocket, rest }

/// Precipitation types
enum PrecipType { none, rain, hail, rainAndHail }

/// Tempest observation array indices per WeatherFlow API documentation
/// https://weatherflow.github.io/Tempest/api/swagger/
/// Single source of truth - update here if API changes
abstract class TempestObsIndex {
  static const int timestamp = 0;
  static const int windLull = 1;
  static const int windAvg = 2;
  static const int windGust = 3;
  static const int windDirection = 4;
  static const int windSampleInterval = 5;  // Not used in Observation model
  static const int pressure = 6;             // MB
  static const int temperature = 7;          // Celsius
  static const int humidity = 8;             // Percent
  static const int illuminance = 9;          // Lux
  static const int uvIndex = 10;
  static const int solarRadiation = 11;      // W/m²
  static const int rainAccumulation = 12;    // mm
  static const int precipType = 13;
  static const int lightningDistance = 14;   // km
  static const int lightningCount = 15;
  static const int battery = 16;             // Volts
  static const int reportInterval = 17;      // Minutes
}

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

  /// Parse from Tempest observation array (UDP or REST API)
  /// Uses TempestObsIndex constants - update those if API format changes
  factory Observation.fromTempestArray(List<dynamic> obs, int deviceId, {ObservationSource source = ObservationSource.udp}) {
    return Observation(
      timestamp: DateTime.fromMillisecondsSinceEpoch((obs[TempestObsIndex.timestamp] as num).toInt() * 1000),
      deviceId: deviceId,
      source: source,
      windLull: (obs[TempestObsIndex.windLull] as num?)?.toDouble(),
      windAvg: (obs[TempestObsIndex.windAvg] as num?)?.toDouble(),
      windGust: (obs[TempestObsIndex.windGust] as num?)?.toDouble(),
      windDirection: (obs[TempestObsIndex.windDirection] as num?)?.toDouble(),
      stationPressure: obs[TempestObsIndex.pressure] != null
          ? (obs[TempestObsIndex.pressure] as num).toDouble() * 100 : null, // mbar to Pa
      temperature: obs[TempestObsIndex.temperature] != null
          ? (obs[TempestObsIndex.temperature] as num).toDouble() + 273.15 : null, // C to K
      humidity: obs[TempestObsIndex.humidity] != null
          ? (obs[TempestObsIndex.humidity] as num).toDouble() / 100 : null, // % to ratio
      illuminance: (obs[TempestObsIndex.illuminance] as num?)?.toDouble(),
      uvIndex: (obs[TempestObsIndex.uvIndex] as num?)?.toDouble(),
      solarRadiation: (obs[TempestObsIndex.solarRadiation] as num?)?.toDouble(),
      rainAccumulated: obs[TempestObsIndex.rainAccumulation] != null
          ? (obs[TempestObsIndex.rainAccumulation] as num).toDouble() / 1000 : null, // mm to m
      precipType: _parsePrecipType((obs[TempestObsIndex.precipType] as num?)?.toInt()),
      lightningDistance: obs[TempestObsIndex.lightningDistance] != null
          ? (obs[TempestObsIndex.lightningDistance] as num).toDouble() * 1000 : null, // km to m
      lightningCount: (obs[TempestObsIndex.lightningCount] as num?)?.toInt(),
      batteryVoltage: (obs[TempestObsIndex.battery] as num?)?.toDouble(),
      reportInterval: (obs[TempestObsIndex.reportInterval] as num?)?.toInt(),
    );
  }

  /// Legacy alias for UDP parsing - uses same format as REST API
  factory Observation.fromUdpTempest(List<dynamic> obs, int deviceId) {
    return Observation.fromTempestArray(obs, deviceId, source: ObservationSource.udp);
  }

  /// Parse from UDP rapid_wind message
  /// Format: [epoch, windSpeed, windDirection]
  factory Observation.fromUdpRapidWind(List<dynamic> obs, int deviceId) {
    return Observation(
      timestamp: DateTime.fromMillisecondsSinceEpoch((obs[0] as num).toInt() * 1000),
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

    // obs[0] is the observation array - use shared parser
    final data = obs[0] as List;
    final baseObs = Observation.fromTempestArray(data, deviceId, source: ObservationSource.rest);

    // Add calculated values from summary
    return Observation(
      timestamp: baseObs.timestamp,
      deviceId: baseObs.deviceId,
      source: baseObs.source,
      windLull: baseObs.windLull,
      windAvg: baseObs.windAvg,
      windGust: baseObs.windGust,
      windDirection: baseObs.windDirection,
      stationPressure: baseObs.stationPressure,
      temperature: baseObs.temperature,
      humidity: baseObs.humidity,
      illuminance: baseObs.illuminance,
      uvIndex: baseObs.uvIndex,
      solarRadiation: baseObs.solarRadiation,
      rainAccumulated: baseObs.rainAccumulated,
      precipType: baseObs.precipType,
      lightningDistance: baseObs.lightningDistance,
      lightningCount: baseObs.lightningCount,
      batteryVoltage: baseObs.batteryVoltage,
      reportInterval: baseObs.reportInterval,
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
    final deviceId = (json['device_id'] as num?)?.toInt() ?? 0;

    if (obs == null || obs.isEmpty) {
      return Observation(
        timestamp: DateTime.now(),
        deviceId: deviceId,
        source: ObservationSource.websocket,
      );
    }

    // Use shared parser for consistent indices
    final data = obs[0] as List;
    return Observation.fromTempestArray(data, deviceId, source: ObservationSource.websocket);
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
      timestamp: DateTime.fromMillisecondsSinceEpoch((evt[0] as num).toInt() * 1000),
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
      timestamp: DateTime.fromMillisecondsSinceEpoch((evt[0] as num).toInt() * 1000),
      deviceId: json['device_id'] as int? ?? 0,
    );
  }
}
