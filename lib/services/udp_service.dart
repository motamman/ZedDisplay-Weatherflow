import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:weatherflow_core/weatherflow_core.dart';

/// UDP connection states
enum UdpState {
  disconnected,
  binding,
  listening,
  error,
}

/// Callback types for UDP events
typedef UdpObservationCallback = void Function(Observation observation);
typedef UdpRapidWindCallback = void Function(Observation rapidWind);
typedef UdpLightningCallback = void Function(LightningStrike strike);
typedef UdpRainStartCallback = void Function(RainStartEvent event);
typedef UdpHubStatusCallback = void Function(Map<String, dynamic> status);
typedef UdpDeviceStatusCallback = void Function(Map<String, dynamic> status);

/// UDP listener service for local Tempest broadcasts
/// The Tempest hub broadcasts weather data on the local network via UDP
class UdpService extends ChangeNotifier {
  RawDatagramSocket? _socket;
  int _port;

  UdpState _state = UdpState.disconnected;
  DateTime? _lastMessageAt;
  String? _lastError;

  // Device filtering - process messages from these devices
  // Map of serial number -> device ID for all station sensors
  final Map<String, int> _allowedDevices = {};

  // Hub info (discovered from broadcasts)
  String? _hubSerialNumber;
  String? _hubFirmwareVersion;

  // Callbacks
  UdpObservationCallback? onObservation;
  UdpRapidWindCallback? onRapidWind;
  UdpLightningCallback? onLightning;
  UdpRainStartCallback? onRainStart;
  UdpHubStatusCallback? onHubStatus;
  UdpDeviceStatusCallback? onDeviceStatus;

  // Message type constants
  static const String _msgObsTempest = 'obs_st';
  static const String _msgObsAir = 'obs_air';
  static const String _msgObsSky = 'obs_sky';
  static const String _msgRapidWind = 'rapid_wind';
  static const String _msgEvtPrecip = 'evt_precip';
  static const String _msgEvtStrike = 'evt_strike';
  static const String _msgHubStatus = 'hub_status';
  static const String _msgDeviceStatus = 'device_status';

  UdpService({int port = 50222}) : _port = port;

  /// Current connection state
  UdpState get state => _state;

  /// Whether listening for broadcasts
  bool get isListening => _state == UdpState.listening;

  /// Time of last received message
  DateTime? get lastMessageAt => _lastMessageAt;

  /// Last error message
  String? get lastError => _lastError;

  /// Current port
  int get port => _port;

  /// Allowed device serial numbers
  Set<String> get allowedDevices => _allowedDevices.keys.toSet();

  /// Hub serial number (discovered from broadcasts)
  String? get hubSerialNumber => _hubSerialNumber;

  /// Hub firmware version
  String? get hubFirmwareVersion => _hubFirmwareVersion;

  /// Update the port (requires restart to take effect)
  void setPort(int port) {
    _port = port;
  }

  /// Set the device to filter for (only process messages from this device)
  /// [serialNumber] is the device serial number (e.g., "ST-00000512")
  /// [deviceId] is the numeric device ID used in observations
  void setDevice(String serialNumber, int deviceId) {
    _allowedDevices.clear();
    _allowedDevices[serialNumber] = deviceId;
    debugPrint('UdpService: Filtering for device $serialNumber (ID: $deviceId)');
  }

  /// Set multiple devices to accept (all sensor devices from a station)
  /// Map of serial number -> device ID
  void setDevices(Map<String, int> devices) {
    _allowedDevices.clear();
    _allowedDevices.addAll(devices);
    debugPrint('UdpService: Filtering for ${devices.length} devices: ${devices.keys.join(", ")}');
  }

  /// Clear device filter (process all messages)
  void clearDevices() {
    _allowedDevices.clear();
  }

  /// Get device ID for a serial number
  int? getDeviceId(String serialNumber) => _allowedDevices[serialNumber];

  /// Start listening for UDP broadcasts
  Future<void> startListening() async {
    if (_state == UdpState.listening || _state == UdpState.binding) {
      return;
    }

    _state = UdpState.binding;
    _lastError = null;
    notifyListeners();

    try {
      // Bind to all interfaces on the specified port
      // Note: reusePort is not supported on Android, only use reuseAddress
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _port,
        reuseAddress: true,
      );

      // Enable broadcast reception
      _socket!.broadcastEnabled = true;

      _socket!.listen(
        _handleSocketEvent,
        onError: _handleError,
        onDone: _handleDone,
        cancelOnError: false,
      );

      _state = UdpState.listening;
      _lastMessageAt = DateTime.now();
      notifyListeners();
      debugPrint('UdpService: Listening on port $_port');
    } catch (e) {
      _lastError = 'Failed to bind to port $_port: $e';
      _state = UdpState.error;
      notifyListeners();
      debugPrint('UdpService: Bind error: $e');
    }
  }

  /// Stop listening for UDP broadcasts
  void stopListening() {
    _socket?.close();
    _socket = null;
    _state = UdpState.disconnected;
    notifyListeners();
    debugPrint('UdpService: Stopped listening');
  }

  /// Restart listening (useful after port change)
  Future<void> restart() async {
    stopListening();
    await Future.delayed(const Duration(milliseconds: 100));
    await startListening();
  }

  void _handleSocketEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;

    final datagram = _socket?.receive();
    if (datagram == null) return;

    _lastMessageAt = DateTime.now();
    debugPrint('UdpService: Received ${datagram.data.length} bytes from ${datagram.address.address}:${datagram.port}');

    try {
      final message = utf8.decode(datagram.data);
      final json = jsonDecode(message) as Map<String, dynamic>;
      _handleMessage(json);
    } catch (e) {
      debugPrint('UdpService: Parse error: $e');
    }
  }

  void _handleMessage(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    final serialNumber = json['serial_number'] as String?;

    debugPrint('UdpService: Received $type from $serialNumber');

    // Filter messages by allowed devices (except hub status)
    if (_allowedDevices.isNotEmpty &&
        serialNumber != null &&
        type != _msgHubStatus &&
        !_allowedDevices.containsKey(serialNumber)) {
      // Message from device not in our allowed list, ignore
      debugPrint('UdpService: Ignoring message from $serialNumber (not in allowed devices)');
      return;
    }

    switch (type) {
      case _msgObsTempest:
        _handleObsTempest(json);
        break;

      case _msgObsAir:
        _handleObsAir(json);
        break;

      case _msgObsSky:
        _handleObsSky(json);
        break;

      case _msgRapidWind:
        _handleRapidWind(json);
        break;

      case _msgEvtPrecip:
        _handleRainStart(json);
        break;

      case _msgEvtStrike:
        _handleLightning(json);
        break;

      case _msgHubStatus:
        _handleHubStatus(json);
        break;

      case _msgDeviceStatus:
        _handleDeviceStatus(json);
        break;

      default:
        debugPrint('UdpService: Unknown message type: $type');
    }
  }

  void _handleObsTempest(Map<String, dynamic> json) {
    try {
      final obs = json['obs'] as List?;
      final serialNumber = json['serial_number'] as String? ?? '';
      // Use configured device ID from allowed list, or parse from serial number as fallback
      final deviceId = _allowedDevices[serialNumber] ?? _parseDeviceId(serialNumber);

      if (obs != null && obs.isNotEmpty) {
        // obs is a list of observation arrays
        for (final obsData in obs) {
          if (obsData is List) {
            final observation = Observation.fromUdpTempest(
              obsData,
              deviceId,
            );
            onObservation?.call(observation);
          }
        }
      }
    } catch (e) {
      debugPrint('UdpService: Error parsing obs_st: $e');
    }
  }

  void _handleObsAir(Map<String, dynamic> json) {
    // obs_air format: [epoch, pressure, temp, humidity, lightningCount, lightningAvgDist, battery, reportInterval]
    try {
      final obs = json['obs'] as List?;
      final serialNumber = json['serial_number'] as String? ?? '';
      final deviceId = _allowedDevices[serialNumber] ?? _parseDeviceId(serialNumber);

      if (obs != null && obs.isNotEmpty) {
        for (final obsData in obs) {
          if (obsData is List) {
            final observation = Observation(
              timestamp: DateTime.fromMillisecondsSinceEpoch((obsData[0] as int) * 1000),
              deviceId: deviceId,
              source: ObservationSource.udp,
              stationPressure: obsData[1] != null ? (obsData[1] as num).toDouble() * 100 : null, // mbar to Pa
              temperature: obsData[2] != null ? (obsData[2] as num).toDouble() + 273.15 : null, // C to K
              humidity: obsData[3] != null ? (obsData[3] as num).toDouble() / 100 : null, // % to ratio
              lightningCount: obsData[4] as int?,
              lightningDistance: obsData[5] != null ? (obsData[5] as num).toDouble() * 1000 : null, // km to m
              batteryVoltage: (obsData[6] as num?)?.toDouble(),
              reportInterval: obsData[7] as int?,
            );
            onObservation?.call(observation);
          }
        }
      }
    } catch (e) {
      debugPrint('UdpService: Error parsing obs_air: $e');
    }
  }

  void _handleObsSky(Map<String, dynamic> json) {
    // obs_sky format: [epoch, illuminance, uv, rainAccum, windLull, windAvg, windGust, windDir, battery, reportInterval, solarRad, dayRain, precipType, windInterval]
    try {
      final obs = json['obs'] as List?;
      final serialNumber = json['serial_number'] as String? ?? '';
      final deviceId = _allowedDevices[serialNumber] ?? _parseDeviceId(serialNumber);

      if (obs != null && obs.isNotEmpty) {
        for (final obsData in obs) {
          if (obsData is List) {
            final observation = Observation(
              timestamp: DateTime.fromMillisecondsSinceEpoch((obsData[0] as int) * 1000),
              deviceId: deviceId,
              source: ObservationSource.udp,
              illuminance: (obsData[1] as num?)?.toDouble(),
              uvIndex: (obsData[2] as num?)?.toDouble(),
              rainAccumulated: obsData[3] != null ? (obsData[3] as num).toDouble() / 1000 : null,
              windLull: (obsData[4] as num?)?.toDouble(),
              windAvg: (obsData[5] as num?)?.toDouble(),
              windGust: (obsData[6] as num?)?.toDouble(),
              windDirection: (obsData[7] as num?)?.toDouble(),
              batteryVoltage: (obsData[8] as num?)?.toDouble(),
              reportInterval: obsData[9] as int?,
              solarRadiation: (obsData[10] as num?)?.toDouble(),
            );
            onObservation?.call(observation);
          }
        }
      }
    } catch (e) {
      debugPrint('UdpService: Error parsing obs_sky: $e');
    }
  }

  void _handleRapidWind(Map<String, dynamic> json) {
    try {
      final obs = json['ob'] as List?;
      final serialNumber = json['serial_number'] as String? ?? '';
      final deviceId = _allowedDevices[serialNumber] ?? _parseDeviceId(serialNumber);

      if (obs != null) {
        final rapidWind = Observation.fromUdpRapidWind(
          obs,
          deviceId,
        );
        onRapidWind?.call(rapidWind);
      }
    } catch (e) {
      debugPrint('UdpService: Error parsing rapid_wind: $e');
    }
  }

  void _handleRainStart(Map<String, dynamic> json) {
    try {
      final evt = json['evt'] as List?;
      final serialNumber = json['serial_number'] as String? ?? '';
      final deviceId = _allowedDevices[serialNumber] ?? _parseDeviceId(serialNumber);

      if (evt != null && evt.isNotEmpty) {
        final event = RainStartEvent(
          timestamp: DateTime.fromMillisecondsSinceEpoch((evt[0] as int) * 1000),
          deviceId: deviceId,
        );
        onRainStart?.call(event);
      }
    } catch (e) {
      debugPrint('UdpService: Error parsing evt_precip: $e');
    }
  }

  void _handleLightning(Map<String, dynamic> json) {
    try {
      final evt = json['evt'] as List?;
      final serialNumber = json['serial_number'] as String? ?? '';
      final deviceId = _allowedDevices[serialNumber] ?? _parseDeviceId(serialNumber);

      if (evt != null && evt.length >= 3) {
        final strike = LightningStrike(
          timestamp: DateTime.fromMillisecondsSinceEpoch((evt[0] as int) * 1000),
          deviceId: deviceId,
          distance: (evt[1] as num).toDouble() * 1000, // km to m
          energy: (evt[2] as num).toDouble(),
        );
        onLightning?.call(strike);
      }
    } catch (e) {
      debugPrint('UdpService: Error parsing evt_strike: $e');
    }
  }

  void _handleHubStatus(Map<String, dynamic> json) {
    _hubSerialNumber = json['serial_number'] as String?;
    _hubFirmwareVersion = json['firmware_revision'] as String?;
    onHubStatus?.call(json);
    notifyListeners();
  }

  void _handleDeviceStatus(Map<String, dynamic> json) {
    onDeviceStatus?.call(json);
  }

  /// Parse device ID from serial number (e.g., "ST-00012345" -> 12345)
  int _parseDeviceId(String serialNumber) {
    // Try to extract numeric portion from serial number
    final match = RegExp(r'(\d+)$').firstMatch(serialNumber);
    if (match != null) {
      return int.tryParse(match.group(1)!) ?? serialNumber.hashCode;
    }
    return serialNumber.hashCode;
  }

  void _handleError(Object error) {
    _lastError = error.toString();
    _state = UdpState.error;
    notifyListeners();
    debugPrint('UdpService: Error: $error');
  }

  void _handleDone() {
    debugPrint('UdpService: Socket closed');
    _state = UdpState.disconnected;
    notifyListeners();
  }

  @override
  void dispose() {
    stopListening();
    super.dispose();
  }
}
