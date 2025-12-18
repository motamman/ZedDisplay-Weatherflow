/// WeatherFlow API Constants

/// Base URLs for WeatherFlow APIs
class WeatherFlowApiUrls {
  static const String restBase = 'https://swd.weatherflow.com/swd/rest';
  static const String websocket = 'wss://ws.weatherflow.com/swd/data';
  static const int udpPort = 50222;

  // REST API endpoints
  static String stations(String token) => '$restBase/stations?token=$token';

  static String station(int stationId, String token) =>
      '$restBase/stations/$stationId?token=$token';

  static String stationObservation(int stationId, String token) =>
      '$restBase/observations/station/$stationId?token=$token';

  static String deviceObservation(int deviceId, String token, {int? dayOffset, int? timeStart, int? timeEnd}) {
    var url = '$restBase/observations/?device_id=$deviceId&token=$token';
    if (dayOffset != null) url += '&day_offset=$dayOffset';
    if (timeStart != null) url += '&time_start=$timeStart';
    if (timeEnd != null) url += '&time_end=$timeEnd';
    return url;
  }

  static String forecast(
    int stationId,
    String token, {
    String? unitsTemp,
    String? unitsWind,
    String? unitsPressure,
    String? unitsPrecip,
    String? unitsDistance,
  }) {
    // Note: SignalK plugin works WITHOUT unit parameters
    // Only add unit params if explicitly specified
    var url = '$restBase/better_forecast?station_id=$stationId&token=$token';
    if (unitsTemp != null) url += '&units_temp=$unitsTemp';
    if (unitsWind != null) url += '&units_wind=$unitsWind';
    if (unitsPressure != null) url += '&units_pressure=$unitsPressure';
    if (unitsPrecip != null) url += '&units_precip=$unitsPrecip';
    if (unitsDistance != null) url += '&units_distance=$unitsDistance';
    return url;
  }

  /// WebSocket URL with token
  static String websocketUrl(String token) => '$websocket?token=$token';
}

/// UDP message types from Tempest Hub
class UdpMessageTypes {
  static const String rapidWind = 'rapid_wind';
  static const String observationTempest = 'obs_st';
  static const String observationAir = 'obs_air';
  static const String observationSky = 'obs_sky';
  static const String deviceStatus = 'device_status';
  static const String hubStatus = 'hub_status';
  static const String precipEvent = 'evt_precip';
  static const String lightningEvent = 'evt_strike';
}

/// WebSocket message types
class WsMessageTypes {
  static const String listenStart = 'listen_start';
  static const String listenStop = 'listen_stop';
  static const String listenStartEvents = 'listen_start_events';
  static const String listenStopEvents = 'listen_stop_events';
  static const String ack = 'ack';
  static const String observationTempest = 'obs_st';
  static const String observationAir = 'obs_air';
  static const String observationSky = 'obs_sky';
  static const String rapidWind = 'rapid_wind';
  static const String precipEvent = 'evt_precip';
  static const String lightningEvent = 'evt_strike';
}

/// Device types
class DeviceTypes {
  static const String tempest = 'ST';
  static const String air = 'AR';
  static const String sky = 'SK';
  static const String hub = 'HB';
}
