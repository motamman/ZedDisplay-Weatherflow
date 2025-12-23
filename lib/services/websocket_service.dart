import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:weatherflow_core/weatherflow_core.dart';

/// WebSocket connection states
enum WebSocketState {
  disconnected,
  connecting,
  connected,
  reconnecting,
}

/// Callback types for WebSocket events
typedef ObservationCallback = void Function(Observation observation);
typedef RapidWindCallback = void Function(Observation rapidWind);
typedef LightningCallback = void Function(LightningStrike strike);
typedef RainStartCallback = void Function(RainStartEvent event);

/// WebSocket service for real-time WeatherFlow data
class WebSocketService extends ChangeNotifier {
  final String _token;
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;

  WebSocketState _state = WebSocketState.disconnected;
  DateTime? _lastMessageAt;
  int _reconnectAttempts = 0;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;

  // Subscribed devices
  final Set<int> _subscribedDevices = {};

  // Callbacks
  ObservationCallback? onObservation;
  RapidWindCallback? onRapidWind;
  LightningCallback? onLightning;
  RainStartCallback? onRainStart;
  VoidCallback? onConnectionFailed; // Called when connection fails (for REST fallback)

  // Constants
  static const Duration _heartbeatInterval = Duration(seconds: 30);
  static const Duration _reconnectBaseDelay = Duration(seconds: 5);
  static const int _maxReconnectAttempts = 10;

  WebSocketService({required String token}) : _token = token;

  /// Current connection state
  WebSocketState get state => _state;

  /// Whether connected and ready
  bool get isConnected => _state == WebSocketState.connected;

  /// Time of last received message
  DateTime? get lastMessageAt => _lastMessageAt;

  /// Connect to WebSocket server
  Future<void> connect() async {
    if (_state == WebSocketState.connected || _state == WebSocketState.connecting) {
      return;
    }

    _state = WebSocketState.connecting;
    notifyListeners();

    try {
      final url = WeatherFlowApiUrls.websocketUrl(_token);
      _channel = WebSocketChannel.connect(Uri.parse(url));

      // Wait for connection
      await _channel!.ready;

      _subscription = _channel!.stream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDone,
        cancelOnError: false,
      );

      _state = WebSocketState.connected;
      _reconnectAttempts = 0;
      _lastMessageAt = DateTime.now();
      _startHeartbeat();

      // Re-subscribe to any previously subscribed devices
      for (final deviceId in _subscribedDevices) {
        _sendListenStart(deviceId);
      }

      notifyListeners();
      debugPrint('WebSocketService: Connected');
    } catch (e) {
      debugPrint('WebSocketService: Connection error: $e');
      _state = WebSocketState.disconnected;
      notifyListeners();
      // Notify listener to fallback to REST API
      onConnectionFailed?.call();
      _scheduleReconnect();
    }
  }

  /// Disconnect from WebSocket server
  void disconnect() {
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    _channel = null;
    _state = WebSocketState.disconnected;
    _reconnectAttempts = 0;
    notifyListeners();
    debugPrint('WebSocketService: Disconnected');
  }

  /// Subscribe to observations from a device
  void subscribeDevice(int deviceId) {
    _subscribedDevices.add(deviceId);
    if (isConnected) {
      _sendListenStart(deviceId);
    }
  }

  /// Unsubscribe from observations from a device
  void unsubscribeDevice(int deviceId) {
    _subscribedDevices.remove(deviceId);
    if (isConnected) {
      _sendListenStop(deviceId);
    }
  }

  /// Subscribe to rapid wind from a device
  void subscribeRapidWind(int deviceId) {
    if (isConnected) {
      _sendListenStartRapidWind(deviceId);
    }
  }

  /// Unsubscribe from rapid wind from a device
  void unsubscribeRapidWind(int deviceId) {
    if (isConnected) {
      _sendListenStopRapidWind(deviceId);
    }
  }

  void _sendListenStart(int deviceId) {
    _sendMessage({
      'type': WsMessageTypes.listenStart,
      'device_id': deviceId,
      'id': 'obs_$deviceId',
    });
  }

  void _sendListenStop(int deviceId) {
    _sendMessage({
      'type': WsMessageTypes.listenStop,
      'device_id': deviceId,
      'id': 'obs_$deviceId',
    });
  }

  void _sendListenStartRapidWind(int deviceId) {
    _sendMessage({
      'type': 'listen_rapid_start',
      'device_id': deviceId,
      'id': 'rapid_$deviceId',
    });
  }

  void _sendListenStopRapidWind(int deviceId) {
    _sendMessage({
      'type': 'listen_rapid_stop',
      'device_id': deviceId,
      'id': 'rapid_$deviceId',
    });
  }

  void _sendMessage(Map<String, dynamic> message) {
    if (_channel == null || _state != WebSocketState.connected) return;
    try {
      _channel!.sink.add(jsonEncode(message));
    } catch (e) {
      debugPrint('WebSocketService: Send error: $e');
    }
  }

  void _handleMessage(dynamic message) {
    _lastMessageAt = DateTime.now();

    try {
      final json = jsonDecode(message as String) as Map<String, dynamic>;
      final type = json['type'] as String?;

      switch (type) {
        case WsMessageTypes.observationTempest:
        case WsMessageTypes.observationAir:
        case WsMessageTypes.observationSky:
          final obs = Observation.fromWebSocket(json);
          onObservation?.call(obs);
          break;

        case WsMessageTypes.rapidWind:
          final obs = json['ob'] as List?;
          if (obs != null) {
            final rapidWind = Observation.fromUdpRapidWind(
              obs,
              json['device_id'] as int? ?? 0,
            );
            onRapidWind?.call(rapidWind);
          }
          break;

        case WsMessageTypes.lightningEvent:
          final strike = LightningStrike.fromUdp(json);
          onLightning?.call(strike);
          break;

        case WsMessageTypes.precipEvent:
          final event = RainStartEvent.fromUdp(json);
          onRainStart?.call(event);
          break;

        case WsMessageTypes.ack:
          // Acknowledgement received
          debugPrint('WebSocketService: Ack for ${json['id']}');
          break;

        default:
          debugPrint('WebSocketService: Unknown message type: $type');
      }
    } catch (e) {
      debugPrint('WebSocketService: Parse error: $e');
    }
  }

  void _handleError(Object error) {
    debugPrint('WebSocketService: Error: $error');
    _state = WebSocketState.disconnected;
    notifyListeners();
    _scheduleReconnect();
  }

  void _handleDone() {
    debugPrint('WebSocketService: Connection closed');
    _state = WebSocketState.disconnected;
    _heartbeatTimer?.cancel();
    notifyListeners();
    _scheduleReconnect();
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      // Check if we've received a message recently
      if (_lastMessageAt != null) {
        final elapsed = DateTime.now().difference(_lastMessageAt!);
        if (elapsed > const Duration(minutes: 2)) {
          // Connection might be stale, reconnect
          debugPrint('WebSocketService: Connection stale, reconnecting');
          disconnect();
          connect();
        }
      }
    });
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      debugPrint('WebSocketService: Max reconnect attempts reached');
      return;
    }

    _reconnectTimer?.cancel();
    _state = WebSocketState.reconnecting;
    notifyListeners();

    // Exponential backoff
    final delay = _reconnectBaseDelay * (1 << _reconnectAttempts);
    _reconnectAttempts++;

    debugPrint('WebSocketService: Reconnecting in ${delay.inSeconds}s (attempt $_reconnectAttempts)');

    _reconnectTimer = Timer(delay, () {
      connect();
    });
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
