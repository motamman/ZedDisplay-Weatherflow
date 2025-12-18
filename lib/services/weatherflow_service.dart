import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:weatherflow_core/weatherflow_core.dart';
import 'storage_service.dart';
import 'websocket_service.dart';
import 'udp_service.dart';

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

  // Event history
  final List<LightningStrike> _lightningStrikes = [];
  DateTime? _lastRainStart;

  // Refresh timer
  Timer? _refreshTimer;

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
      // Start refresh timer
      _startRefreshTimer();
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
    // Get the selected station's Tempest device to filter UDP messages
    final device = _selectedStation?.tempestDevice;
    if (device == null) {
      debugPrint('WeatherFlowService: No Tempest device for UDP');
      return;
    }

    _udp = UdpService(port: _storage.udpPort);

    // Configure device filter - only process messages from this device
    _udp!.setDevice(device.serialNumber, device.deviceId);

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
      debugPrint('WeatherFlowService: UDP listening on port ${_storage.udpPort} for device ${device.serialNumber}');
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
  void stopUdp() {
    _disconnectUdp();
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
