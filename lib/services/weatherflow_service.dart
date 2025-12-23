import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:weatherflow_core/weatherflow_core.dart' hide HourlyForecast, DailyForecast;
import 'storage_service.dart';
import 'websocket_service.dart';
import 'udp_service.dart';
import '../widgets/forecast_models.dart';
import '../models/marine_data.dart';
import '../utils/sun_calc.dart' show SunCalc, MoonCalc;

/// Connection type currently in use
enum ConnectionType { none, rest, websocket, udp }

/// Main WeatherFlow data service
/// Orchestrates data from REST API, WebSocket, and UDP
class WeatherFlowService extends ChangeNotifier {
  final StorageService _storage;
  final ConversionService _conversions;

  WeatherFlowApi? _api;
  WebSocketService? _websocket;
  UdpService? _udp;

  // Current state
  ConnectionType _connectionType = ConnectionType.none;
  bool _isLoading = false;
  String? _error;

  // Data cache
  List<Station> _stations = [];
  Station? _selectedStation;
  Observation? _currentObservation;
  ForecastResponse? _currentForecast;

  // Per-device observations (keyed by device serial number)
  final Map<String, Observation> _deviceObservations = {};

  // Event history
  final List<LightningStrike> _lightningStrikes = [];
  DateTime? _lastRainStart;

  // Refresh timer
  Timer? _refreshTimer;

  // State for spinner compatibility
  bool _isRefreshing = false;
  SunMoonTimes? _sunMoonTimes;
  List<HourlyForecast> _displayHourlyForecasts = [];
  List<DailyForecast> _displayDailyForecasts = [];

  WeatherFlowService({
    required StorageService storage,
    ConversionService? conversions,
  })  : _storage = storage,
        _conversions = conversions ?? ConversionService();

  // ============ Getters ============

  /// Current connection type
  ConnectionType get connectionType => _connectionType;

  /// Whether currently loading data
  bool get isLoading => _isLoading;

  /// Current error message
  String? get error => _error;

  /// Whether connected to any data source
  bool get isConnected => _connectionType != ConnectionType.none;

  /// All available stations
  List<Station> get stations => _stations;

  /// Currently selected station
  Station? get selectedStation => _selectedStation;

  /// Latest observation
  Observation? get currentObservation => _currentObservation;

  /// Current forecast
  ForecastResponse? get currentForecast => _currentForecast;

  /// Conversion service
  ConversionService get conversions => _conversions;

  /// Recent lightning strikes
  List<LightningStrike> get lightningStrikes => List.unmodifiable(_lightningStrikes);

  /// Time of last rain start event
  DateTime? get lastRainStart => _lastRainStart;

  /// Whether UDP is enabled in settings
  bool get udpEnabled => _storage.udpEnabled;

  /// Whether UDP is currently listening
  bool get udpListening => _udp?.isListening ?? false;

  /// UDP service for external access
  UdpService? get udpService => _udp;

  /// WebSocket service for external access
  WebSocketService? get websocketService => _websocket;

  /// All device observations (keyed by serial number)
  Map<String, Observation> get deviceObservations => Map.unmodifiable(_deviceObservations);

  /// API client for external access (e.g., history service)
  WeatherFlowApi? get api => _api;

  // ============ Spinner Compatibility Getters ============

  /// Whether a refresh is in progress
  bool get isRefreshing => _isRefreshing;

  /// Whether we have any data available
  bool get hasData => _currentForecast != null || _currentObservation != null;

  /// Calculated sun and moon times
  SunMoonTimes? get sunMoonTimes => _sunMoonTimes;

  /// Hourly forecasts formatted for display
  List<HourlyForecast> get displayHourlyForecasts => _displayHourlyForecasts;

  /// Daily forecasts formatted for display
  List<DailyForecast> get displayDailyForecasts => _displayDailyForecasts;

  /// Marine data (stub - WeatherFlow doesn't provide marine data)
  MarineData? get marineData => null;

  /// Whether marine data is loading (stub)
  bool get isLoadingMarine => false;

  /// Location data from selected station
  ({double latitude, double longitude, String? timezone})? get location {
    if (_selectedStation == null) return null;
    return (
      latitude: _selectedStation!.latitude,
      longitude: _selectedStation!.longitude,
      timezone: _selectedStation!.timezone,
    );
  }

  /// Active weather model ID (stub - not applicable for WeatherFlow)
  String? get activeModelId => 'weatherflow';

  /// Get observation for a specific device by serial number
  Observation? getDeviceObservation(String serialNumber) => _deviceObservations[serialNumber];

  /// Get device ID for a serial number
  int? getDeviceId(String serialNumber) {
    final device = _selectedStation?.devices.firstWhere(
      (d) => d.serialNumber == serialNumber,
      orElse: () => Device(deviceId: 0, serialNumber: '', deviceType: ''),
    );
    return device?.deviceId != 0 ? device?.deviceId : null;
  }

  /// Get historical observations for a device by serial number
  /// Returns null if API not available or device not found
  Future<List<Observation>?> getDeviceHistory({
    required String serialNumber,
    int? dayOffset,
    DateTime? startTime,
    DateTime? endTime,
  }) async {
    if (_api == null) return null;

    final deviceId = getDeviceId(serialNumber);
    if (deviceId == null) return null;

    try {
      return await _api!.getDeviceObservations(
        deviceId,
        dayOffset: dayOffset,
        startTime: startTime,
        endTime: endTime,
      );
    } catch (e) {
      debugPrint('WeatherFlowService: Error fetching device history: $e');
      return null;
    }
  }

  /// Get observation for a specific device type (ST, AR, SK)
  /// Returns the first matching device observation
  Observation? getObservationByDeviceType(String deviceType) {
    final device = _selectedStation?.devices.firstWhere(
      (d) => d.deviceType == deviceType,
      orElse: () => Device(deviceId: 0, serialNumber: '', deviceType: ''),
    );
    if (device != null && device.serialNumber.isNotEmpty) {
      return _deviceObservations[device.serialNumber];
    }
    return null;
  }

  /// Get merged observation using specified device sources for each measurement
  /// Sources map: measurement type -> device serial number (or 'auto' for best available)
  Observation? getMergedObservation({
    String? tempSource,
    String? humiditySource,
    String? pressureSource,
    String? windSource,
    String? lightSource,
    String? rainSource,
    String? lightningSource,
  }) {
    final result = getMergedObservationWithSources(
      tempSource: tempSource,
      humiditySource: humiditySource,
      pressureSource: pressureSource,
      windSource: windSource,
      lightSource: lightSource,
      rainSource: rainSource,
      lightningSource: lightningSource,
    );
    return result?.observation;
  }

  /// Get merged observation with per-field source tracking
  /// Returns null if no observations available
  ({
    Observation observation,
    ObservationSource tempSource,
    ObservationSource humiditySource,
    ObservationSource pressureSource,
    ObservationSource windSource,
    ObservationSource lightSource,
    ObservationSource rainSource,
    ObservationSource lightningSource,
  })? getMergedObservationWithSources({
    String? tempSource,
    String? humiditySource,
    String? pressureSource,
    String? windSource,
    String? lightSource,
    String? rainSource,
    String? lightningSource,
  }) {
    if (_deviceObservations.isEmpty && _currentObservation == null) return null;

    // Helper to get value from specified source or auto-select, tracking the source
    (T?, ObservationSource?) getValueWithSource<T>(String? source, T? Function(Observation) getter) {
      if (source != null && source != 'auto' && _deviceObservations.containsKey(source)) {
        final obs = _deviceObservations[source]!;
        final value = getter(obs);
        return (value, value != null ? obs.source : null);
      }
      // Auto: try all device observations, then current observation
      for (final obs in _deviceObservations.values) {
        final value = getter(obs);
        if (value != null) return (value, obs.source);
      }
      if (_currentObservation != null) {
        final value = getter(_currentObservation!);
        return (value, value != null ? _currentObservation!.source : null);
      }
      return (null, null);
    }

    // Determine best source for observation metadata
    final bestObs = _deviceObservations.values.isNotEmpty
        ? _deviceObservations.values.first
        : _currentObservation;
    if (bestObs == null) return null;

    // Get values with source tracking
    final (temp, tempSrc) = getValueWithSource(tempSource, (o) => o.temperature);
    final (humidity, humiditySrc) = getValueWithSource(humiditySource, (o) => o.humidity);
    final (stationPressure, pressureSrc) = getValueWithSource(pressureSource, (o) => o.stationPressure);
    final (seaLevelPressure, _) = getValueWithSource(pressureSource, (o) => o.seaLevelPressure);
    final (windAvg, windSrc) = getValueWithSource(windSource, (o) => o.windAvg);
    final (windGust, _) = getValueWithSource(windSource, (o) => o.windGust);
    final (windLull, _) = getValueWithSource(windSource, (o) => o.windLull);
    final (windDirection, _) = getValueWithSource(windSource, (o) => o.windDirection);
    final (illuminance, lightSrc) = getValueWithSource(lightSource, (o) => o.illuminance);
    final (uvIndex, _) = getValueWithSource(lightSource, (o) => o.uvIndex);
    final (solarRadiation, _) = getValueWithSource(lightSource, (o) => o.solarRadiation);
    final (rainAccumulated, rainSrc) = getValueWithSource(rainSource, (o) => o.rainAccumulated);
    final (rainRate, _) = getValueWithSource(rainSource, (o) => o.rainRate);
    final (lightningDistance, lightningSrc) = getValueWithSource(lightningSource, (o) => o.lightningDistance);
    final (lightningCount, _) = getValueWithSource(lightningSource, (o) => o.lightningCount);
    final (feelsLike, _) = getValueWithSource(tempSource, (o) => o.feelsLike);
    final (dewPoint, _) = getValueWithSource(tempSource, (o) => o.dewPoint);
    final (heatIndex, _) = getValueWithSource(tempSource, (o) => o.heatIndex);
    final (windChill, _) = getValueWithSource(tempSource, (o) => o.windChill);

    final observation = Observation(
      timestamp: bestObs.timestamp,
      deviceId: bestObs.deviceId,
      source: bestObs.source,
      temperature: temp,
      humidity: humidity,
      stationPressure: stationPressure,
      seaLevelPressure: seaLevelPressure,
      windAvg: windAvg,
      windGust: windGust,
      windLull: windLull,
      windDirection: windDirection,
      illuminance: illuminance,
      uvIndex: uvIndex,
      solarRadiation: solarRadiation,
      rainAccumulated: rainAccumulated,
      rainRate: rainRate,
      precipType: bestObs.precipType,
      lightningDistance: lightningDistance,
      lightningCount: lightningCount,
      batteryVoltage: bestObs.batteryVoltage,
      reportInterval: bestObs.reportInterval,
      feelsLike: feelsLike,
      dewPoint: dewPoint,
      heatIndex: heatIndex,
      windChill: windChill,
    );

    return (
      observation: observation,
      tempSource: tempSrc ?? bestObs.source,
      humiditySource: humiditySrc ?? bestObs.source,
      pressureSource: pressureSrc ?? bestObs.source,
      windSource: windSrc ?? bestObs.source,
      lightSource: lightSrc ?? bestObs.source,
      rainSource: rainSrc ?? bestObs.source,
      lightningSource: lightningSrc ?? bestObs.source,
    );
  }

  // ============ Initialization ============

  /// Initialize the service with stored token
  Future<void> initialize() async {
    final token = _storage.apiToken;
    if (token == null || token.isEmpty) {
      debugPrint('WeatherFlowService: No API token');
      return;
    }

    _api = WeatherFlowApi(token: token);

    // Load cached data
    _stations = _storage.cachedStations;
    final selectedId = _storage.selectedStationId;
    if (selectedId != null) {
      _selectedStation = _storage.getCachedStation(selectedId);
      if (_selectedStation != null) {
        // Load cached observation and forecast
        final device = _selectedStation!.tempestDevice;
        if (device != null) {
          _currentObservation = _storage.getCachedObservation(device.deviceId);
        }
        _currentForecast = _storage.getCachedForecast(selectedId);
      }
    }

    // Set up conversions
    _conversions.setPreferences(_storage.unitPreferences);

    // Start UDP listener if enabled and we have a selected station
    if (_storage.udpEnabled && _selectedStation != null) {
      await _connectUdp();
    }

    // Connect to WebSocket if we have a selected station
    if (_selectedStation != null) {
      final device = _selectedStation!.tempestDevice;
      if (device != null) {
        await _connectWebSocket(device.deviceId);
      }

      // Update derived data from cached forecast (displayHourlyForecasts, etc.)
      _updateDerivedData();

      // Start refresh timer
      _startRefreshTimer();

      // Fetch fresh data in background (don't await - let UI show cached data first)
      refresh();
    }

    notifyListeners();
  }

  /// Set API token and initialize API client
  Future<bool> setApiToken(String token) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final api = WeatherFlowApi(token: token);
      final isValid = await api.validateToken();

      if (isValid) {
        await _storage.setApiToken(token);
        _api = api;
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _error = 'Invalid API token';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = 'Failed to validate token: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // ============ Station Management ============

  /// Fetch all stations from API
  Future<void> fetchStations() async {
    if (_api == null) {
      _error = 'Not authenticated';
      notifyListeners();
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _stations = await _api!.getStations();
      await _storage.cacheStations(_stations);

      // If we have a selected station, update it from fresh data
      if (_selectedStation != null) {
        final updated = _stations.firstWhere(
          (s) => s.stationId == _selectedStation!.stationId,
          orElse: () => _selectedStation!,
        );
        _selectedStation = updated;
      }

      _isLoading = false;
      notifyListeners();
    } on WeatherFlowApiException catch (e) {
      _error = e.message;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = 'Failed to fetch stations: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Select a station and connect to it
  Future<void> selectStation(Station station) async {
    _selectedStation = station;
    await _storage.setSelectedStationId(station.stationId);
    await _storage.cacheStation(station);

    // Clear old data from previous station
    _clearStationData();

    // Disconnect from previous WebSocket subscriptions
    _disconnectWebSocket();

    // Connect to new station
    await _connectToStation(station);

    notifyListeners();
  }

  /// Clear all station-specific data (called when switching stations)
  void _clearStationData() {
    _currentObservation = null;
    _currentForecast = null;
    _deviceObservations.clear();
    _lightningStrikes.clear();
    _lastRainStart = null;
    _error = null;
    debugPrint('WeatherFlowService: Cleared station data for station switch');
  }

  // ============ Data Connection ============

  Future<void> _connectToStation(Station station) async {
    final device = station.tempestDevice;
    if (device == null) {
      _error = 'No Tempest device found';
      notifyListeners();
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    // Start UDP if enabled (local network broadcasts)
    if (_storage.udpEnabled) {
      await _connectUdp();
    }

    // Try WebSocket for cloud connection
    await _connectWebSocket(device.deviceId);

    // Fetch initial data from REST
    await _fetchObservation(station.stationId);
    await _fetchForecast(station.stationId);

    // Start refresh timer
    _startRefreshTimer();

    _isLoading = false;
    notifyListeners();
  }

  Future<void> _connectWebSocket(int deviceId) async {
    final token = _storage.apiToken;
    if (token == null) return;

    _websocket = WebSocketService(token: token);

    _websocket!.onObservation = _handleObservation;
    _websocket!.onRapidWind = _handleRapidWind;
    _websocket!.onLightning = _handleLightning;
    _websocket!.onRainStart = _handleRainStart;
    _websocket!.onConnectionFailed = _handleWebSocketFailed;

    await _websocket!.connect();

    if (_websocket!.isConnected) {
      _websocket!.subscribeDevice(deviceId);
      _websocket!.subscribeRapidWind(deviceId);
      _connectionType = ConnectionType.websocket;
      debugPrint('WeatherFlowService: Connected via WebSocket');
    } else {
      _connectionType = ConnectionType.rest;
      debugPrint('WeatherFlowService: Falling back to REST');
    }
  }

  void _disconnectWebSocket() {
    _websocket?.disconnect();
    _websocket = null;
    if (_connectionType == ConnectionType.websocket) {
      _connectionType = _udp?.isListening == true ? ConnectionType.udp : ConnectionType.none;
    }
  }

  Future<void> _connectUdp() async {
    // Get ALL sensor devices from the selected station (ST, AR, SK - not Hub)
    final sensorDevices = _selectedStation?.sensorDevices ?? [];
    if (sensorDevices.isEmpty) {
      debugPrint('WeatherFlowService: No sensor devices for UDP');
      return;
    }

    _udp = UdpService(port: _storage.udpPort);

    // Configure device filter - accept all sensor devices from this station
    final deviceMap = <String, int>{};
    for (final device in sensorDevices) {
      deviceMap[device.serialNumber] = device.deviceId;
    }
    _udp!.setDevices(deviceMap);

    _udp!.onObservation = _handleUdpObservation;
    _udp!.onRapidWind = _handleRapidWind;
    _udp!.onLightning = _handleLightning;
    _udp!.onRainStart = _handleRainStart;

    await _udp!.startListening();

    if (_udp!.isListening) {
      // UDP is supplementary to WebSocket - prefer UDP connection type if WebSocket isn't connected
      if (_connectionType != ConnectionType.websocket) {
        _connectionType = ConnectionType.udp;
      }
      final deviceList = sensorDevices.map((d) => d.serialNumber).join(', ');
      debugPrint('WeatherFlowService: UDP listening on port ${_storage.udpPort} for devices: $deviceList');
    } else {
      debugPrint('WeatherFlowService: Failed to start UDP listener');
    }
  }

  void _disconnectUdp() {
    _udp?.stopListening();
    _udp = null;
    if (_connectionType == ConnectionType.udp) {
      _connectionType = ConnectionType.none;
    }
  }

  /// Start UDP listener (can be called from settings)
  Future<void> startUdp() async {
    await _connectUdp();
    notifyListeners();
  }

  /// Stop UDP listener (can be called from settings)
  /// Fetches fresh data from REST to replace stale UDP observation
  Future<void> stopUdp() async {
    _disconnectUdp();
    // Refresh from REST to replace the cached UDP observation
    if (_selectedStation != null) {
      await _fetchObservation(_selectedStation!.stationId);
    }
    notifyListeners();
  }

  /// Restart UDP with new port
  Future<void> restartUdp() async {
    _disconnectUdp();
    if (_storage.udpEnabled) {
      await _connectUdp();
    }
    notifyListeners();
  }

  void _handleUdpObservation(Observation obs) {
    _currentObservation = obs;

    // Store observation by device serial number
    final device = _selectedStation?.devices.firstWhere(
      (d) => d.deviceId == obs.deviceId,
      orElse: () => Device(deviceId: 0, serialNumber: '', deviceType: ''),
    );
    if (device != null && device.serialNumber.isNotEmpty) {
      _deviceObservations[device.serialNumber] = obs;
      debugPrint('WeatherFlowService: Stored observation for ${device.serialNumber} (${device.deviceTypeName})');
    }

    // Mark as UDP if we're not already on WebSocket
    if (_connectionType != ConnectionType.websocket) {
      _connectionType = ConnectionType.udp;
    }
    notifyListeners();

    // Cache observation
    _storage.cacheObservation(obs.deviceId, obs);
  }

  Future<void> _fetchObservation(int stationId) async {
    if (_api == null) return;

    try {
      final obs = await _api!.getStationObservation(stationId);
      _currentObservation = obs;

      // Cache for offline use
      await _storage.cacheObservation(obs.deviceId, obs);

      notifyListeners();
    } catch (e) {
      debugPrint('WeatherFlowService: Failed to fetch observation: $e');
    }
  }

  Future<void> _fetchForecast(int stationId) async {
    if (_api == null) return;

    try {
      // Don't specify units - API returns default units (C, m/s, mb, mm, km)
      // This matches the SignalK plugin behavior which gets daily forecasts
      final forecast = await _api!.getForecast(stationId);
      _currentForecast = forecast;

      // Cache for offline use
      await _storage.cacheForecast(stationId, forecast);

      // Update derived data (sun/moon times, display forecasts)
      _updateDerivedData();

      notifyListeners();
    } catch (e) {
      debugPrint('WeatherFlowService: Failed to fetch forecast: $e');
    }
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    final interval = Duration(minutes: _storage.refreshInterval);
    _refreshTimer = Timer.periodic(interval, (_) {
      refresh();
    });
  }

  /// Manually refresh data
  Future<void> refresh() async {
    if (_selectedStation == null) return;

    await _fetchObservation(_selectedStation!.stationId);
    await _fetchForecast(_selectedStation!.stationId);
  }

  /// Fetch forecast data (public method)
  Future<void> fetchForecast() async {
    if (_selectedStation == null) return;
    await _fetchForecast(_selectedStation!.stationId);
  }

  // ============ Spinner Compatibility Methods ============

  /// Force refresh all data (for spinner compatibility)
  Future<void> forceRefresh() async {
    _isRefreshing = true;
    notifyListeners();
    try {
      await refresh();
      _updateDerivedData();
    } finally {
      _isRefreshing = false;
      notifyListeners();
    }
  }

  /// Refresh forecast data (for spinner compatibility)
  Future<void> refreshForecast() async {
    _isRefreshing = true;
    notifyListeners();
    try {
      await fetchForecast();
      _updateDerivedData();
    } finally {
      _isRefreshing = false;
      notifyListeners();
    }
  }

  /// Fetch marine data (stub - WeatherFlow doesn't provide marine data)
  Future<void> fetchMarineData() async {
    // Stub - no marine data from WeatherFlow API
  }

  /// Update derived data (sun/moon times, hourly forecasts)
  void _updateDerivedData() {
    _updateSunMoonTimes();
    _updateDisplayForecasts();
  }

  /// Calculate sun and moon times from station location
  void _updateSunMoonTimes() {
    if (_selectedStation == null) return;

    final lat = _selectedStation!.latitude;
    final lng = _selectedStation!.longitude;
    final now = DateTime.now();

    // Calculate for today and next few days
    final days = <DaySunTimes>[];
    for (var i = -1; i < 10; i++) {
      final date = now.add(Duration(days: i));
      final times = SunCalc.getTimes(date, lat, lng);
      final moonTimes = MoonCalc.getTimes(date, lat, lng);
      final moonIllum = MoonCalc.getIllumination(date);

      days.add(DaySunTimes(
        sunrise: times.sunrise,
        sunset: times.sunset,
        solarNoon: times.solarNoon,
        dawn: times.dawn,
        dusk: times.dusk,
        nauticalDawn: times.nauticalDawn,
        nauticalDusk: times.nauticalDusk,
        goldenHour: times.goldenHour,
        goldenHourEnd: times.goldenHourEnd,
        night: times.night,
        nightEnd: times.nightEnd,
        moonrise: moonTimes.rise,
        moonset: moonTimes.set,
        moonPhase: moonIllum.phase,
        moonFraction: moonIllum.fraction,
      ));
    }

    // Get timezone offset
    int utcOffsetSeconds = DateTime.now().timeZoneOffset.inSeconds;

    _sunMoonTimes = SunMoonTimes(
      days: days,
      todayIndex: 1, // Index 0 is yesterday, 1 is today
      moonPhase: days.isNotEmpty ? days[1].moonPhase : 0.0,
      moonFraction: days.isNotEmpty ? days[1].moonFraction : 0.0,
      latitude: lat,
      utcOffsetSeconds: utcOffsetSeconds,
    );
  }

  /// Convert API forecasts to display format
  void _updateDisplayForecasts() {
    if (_currentForecast == null) {
      _displayHourlyForecasts = [];
      return;
    }

    int hourIndex = 0;
    _displayHourlyForecasts = _currentForecast!.hourlyForecasts.map((h) {
      // Calculate Beaufort scale from wind speed (m/s)
      int? beaufort;
      if (h.windAvg != null) {
        final windMps = h.windAvg!;
        if (windMps < 0.5) beaufort = 0;
        else if (windMps < 1.6) beaufort = 1;
        else if (windMps < 3.4) beaufort = 2;
        else if (windMps < 5.5) beaufort = 3;
        else if (windMps < 8.0) beaufort = 4;
        else if (windMps < 10.8) beaufort = 5;
        else if (windMps < 13.9) beaufort = 6;
        else if (windMps < 17.2) beaufort = 7;
        else if (windMps < 20.8) beaufort = 8;
        else if (windMps < 24.5) beaufort = 9;
        else if (windMps < 28.5) beaufort = 10;
        else if (windMps < 32.7) beaufort = 11;
        else beaufort = 12;
      }

      // Determine if daytime based on hour (simple approximation)
      final hour = h.time.hour;
      final isDay = hour >= 6 && hour < 20;

      return HourlyForecast(
        hour: hourIndex++,
        time: h.time,
        temperature: h.temperature,
        feelsLike: h.feelsLike ?? h.temperature, // Use feelsLike if available, fallback to temp
        humidity: h.humidity,
        windSpeed: h.windAvg,
        windDirection: h.windDirection,
        windGust: h.windGust,
        precipProbability: h.precipProbability != null
            ? h.precipProbability! * 100  // Convert from 0-1 to 0-100
            : null,
        pressure: h.pressure,
        icon: h.icon ?? (isDay ? 'clear-day' : 'clear-night'),
        conditions: h.conditions,
        beaufort: beaufort,
        isDay: isDay,
        uvIndex: h.uvIndex,
        precipType: h.precipType,
        precipIcon: h.precipIcon,
      );
    }).toList();

    // Also update daily forecasts
    _updateDisplayDailyForecasts();
  }

  /// Convert API daily forecasts to display format
  void _updateDisplayDailyForecasts() {
    if (_currentForecast == null) {
      _displayDailyForecasts = [];
      return;
    }

    int dayIndex = 0;
    _displayDailyForecasts = _currentForecast!.dailyForecasts.map((d) {
      return DailyForecast(
        dayIndex: dayIndex++,
        date: d.date,
        tempHigh: d.tempHigh,
        tempLow: d.tempLow,
        conditions: d.conditions,
        icon: d.icon ?? 'clear-day',
        precipProbability: d.precipProbability,
        precipIcon: d.precipIcon,
        sunrise: d.sunrise,
        sunset: d.sunset,
      );
    }).toList();
  }

  // ============ Event Handlers ============

  void _handleObservation(Observation obs) {
    _currentObservation = obs;
    _connectionType = ConnectionType.websocket;
    notifyListeners();

    // Cache observation
    _storage.cacheObservation(obs.deviceId, obs);
  }

  void _handleRapidWind(Observation rapidWind) {
    if (_currentObservation != null) {
      _currentObservation = _currentObservation!.mergeWithRapidWind(rapidWind);
      notifyListeners();
    }
  }

  void _handleLightning(LightningStrike strike) {
    _lightningStrikes.insert(0, strike);
    // Keep only last 50 strikes
    if (_lightningStrikes.length > 50) {
      _lightningStrikes.removeRange(50, _lightningStrikes.length);
    }
    notifyListeners();
  }

  void _handleRainStart(RainStartEvent event) {
    _lastRainStart = event.timestamp;
    notifyListeners();
  }

  /// Handle WebSocket connection failure - fallback to REST API
  void _handleWebSocketFailed() {
    debugPrint('WeatherFlowService: WebSocket failed, fetching from REST as fallback');
    _connectionType = ConnectionType.rest;
    // Fetch fresh data from REST to keep UI updated
    if (_selectedStation != null) {
      _fetchObservation(_selectedStation!.stationId);
    }
  }

  // ============ Disconnect ============

  /// Disconnect and clean up
  void disconnect() {
    _refreshTimer?.cancel();
    _disconnectWebSocket();
    _disconnectUdp();
    _connectionType = ConnectionType.none;
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    _api?.dispose();
    super.dispose();
  }
}
