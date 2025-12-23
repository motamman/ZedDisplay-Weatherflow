import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/station.dart';
import '../models/observation.dart';
import '../models/forecast.dart';
import 'api_constants.dart';

/// WeatherFlow REST API client
class WeatherFlowApi {
  final String token;
  final http.Client _client;

  WeatherFlowApi({required this.token, http.Client? client})
      : _client = client ?? http.Client();

  /// Fetch all stations for the authenticated user
  Future<List<Station>> getStations() async {
    final url = WeatherFlowApiUrls.stations(token);

    final response = await _client.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final stationResponse = StationListResponse.fromJson(json);
      return stationResponse.stations;
    } else {
      throw WeatherFlowApiException(
        'Failed to fetch stations',
        statusCode: response.statusCode,
        body: response.body,
      );
    }
  }

  /// Fetch a specific station by ID
  Future<Station> getStation(int stationId) async {
    final url = WeatherFlowApiUrls.station(stationId, token);
    final response = await _client.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final stations = StationListResponse.fromJson(json).stations;
      if (stations.isEmpty) {
        throw WeatherFlowApiException('Station not found', statusCode: 404);
      }
      return stations.first;
    } else {
      throw WeatherFlowApiException(
        'Failed to fetch station',
        statusCode: response.statusCode,
        body: response.body,
      );
    }
  }

  /// Fetch latest observation for a station
  Future<Observation> getStationObservation(int stationId) async {
    final url = WeatherFlowApiUrls.stationObservation(stationId, token);
    final response = await _client.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      // Get device_id from response
      final deviceId = (json['station_id'] as num?)?.toInt() ?? stationId;
      return Observation.fromRestStation(json, deviceId);
    } else {
      throw WeatherFlowApiException(
        'Failed to fetch observation',
        statusCode: response.statusCode,
        body: response.body,
      );
    }
  }

  /// Fetch observations for a specific device
  /// dayOffset: 0 = today, 1 = yesterday, etc.
  Future<List<Observation>> getDeviceObservations(
    int deviceId, {
    int? dayOffset,
    DateTime? startTime,
    DateTime? endTime,
  }) async {
    final url = WeatherFlowApiUrls.deviceObservation(
      deviceId,
      token,
      dayOffset: dayOffset,
      timeStart: startTime != null ? startTime.millisecondsSinceEpoch ~/ 1000 : null,
      timeEnd: endTime != null ? endTime.millisecondsSinceEpoch ~/ 1000 : null,
    );
    final response = await _client.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final obsList = <Observation>[];

      // Parse each observation in the response
      if (json['obs'] is List) {
        for (final obs in json['obs'] as List) {
          if (obs is List) {
            obsList.add(Observation.fromUdpTempest(obs, deviceId));
          }
        }
      }

      return obsList;
    } else {
      throw WeatherFlowApiException(
        'Failed to fetch device observations',
        statusCode: response.statusCode,
        body: response.body,
      );
    }
  }

  /// Fetch forecast for a station
  /// Note: Unit parameters are optional. The API returns data in default units
  /// (Celsius, m/s, mb, mm, km) when not specified. This matches the SignalK plugin behavior.
  Future<ForecastResponse> getForecast(
    int stationId, {
    String? unitsTemp,
    String? unitsWind,
    String? unitsPressure,
    String? unitsPrecip,
    String? unitsDistance,
  }) async {
    final url = WeatherFlowApiUrls.forecast(
      stationId,
      token,
      unitsTemp: unitsTemp,
      unitsWind: unitsWind,
      unitsPressure: unitsPressure,
      unitsPrecip: unitsPrecip,
      unitsDistance: unitsDistance,
    );
    final response = await _client.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return ForecastResponse.fromJson(json);
    } else {
      throw WeatherFlowApiException(
        'Failed to fetch forecast',
        statusCode: response.statusCode,
        body: response.body,
      );
    }
  }

  /// Validate the API token by fetching stations
  Future<bool> validateToken() async {
    try {
      await getStations();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Close the HTTP client
  void dispose() {
    _client.close();
  }
}

/// Exception for WeatherFlow API errors
class WeatherFlowApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? body;

  WeatherFlowApiException(this.message, {this.statusCode, this.body});

  @override
  String toString() {
    if (statusCode != null) {
      return 'WeatherFlowApiException: $message (HTTP $statusCode)';
    }
    return 'WeatherFlowApiException: $message';
  }

  /// Check if this is an authentication error
  bool get isAuthError => statusCode == 401 || statusCode == 403;

  /// Check if this is a not found error
  bool get isNotFound => statusCode == 404;

  /// Check if this is a rate limit error
  bool get isRateLimited => statusCode == 429;
}
