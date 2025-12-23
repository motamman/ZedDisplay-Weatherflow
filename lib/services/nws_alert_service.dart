// NWS Alert Service
// Fetches weather alerts directly from the National Weather Service API
// Supports phone location, station location, or both with deduplication

import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';

/// Alert severity levels matching NWS classifications
enum AlertSeverity {
  extreme,
  severe,
  moderate,
  minor,
  unknown;

  static AlertSeverity fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'extreme':
        return AlertSeverity.extreme;
      case 'severe':
        return AlertSeverity.severe;
      case 'moderate':
        return AlertSeverity.moderate;
      case 'minor':
        return AlertSeverity.minor;
      default:
        return AlertSeverity.unknown;
    }
  }

  int get priority {
    switch (this) {
      case AlertSeverity.extreme:
        return 0;
      case AlertSeverity.severe:
        return 1;
      case AlertSeverity.moderate:
        return 2;
      case AlertSeverity.minor:
        return 3;
      case AlertSeverity.unknown:
        return 4;
    }
  }
}

/// Location source for fetching alerts
enum AlertLocationSource {
  phone,    // Use phone's GPS
  station,  // Use WeatherFlow station location
  both,     // Use both and deduplicate
}

/// Parsed NWS Alert
class NWSAlert {
  final String id;
  final String event;
  final String headline;
  final String description;
  final String? instruction;
  final AlertSeverity severity;
  final String certainty;
  final String urgency;
  final DateTime? effective;
  final DateTime? expires;
  final DateTime? onset;
  final DateTime? ends;
  final String areaDesc;
  final String senderName;
  final String source; // 'phone' or 'station' to track where it came from

  NWSAlert({
    required this.id,
    required this.event,
    required this.headline,
    required this.description,
    this.instruction,
    required this.severity,
    required this.certainty,
    required this.urgency,
    this.effective,
    this.expires,
    this.onset,
    this.ends,
    required this.areaDesc,
    required this.senderName,
    this.source = 'unknown',
  });

  /// Check if alert is currently active
  bool get isActive {
    final now = DateTime.now();
    if (expires != null && now.isAfter(expires!)) return false;
    if (ends != null && now.isAfter(ends!)) return false;
    if (urgency.toLowerCase() == 'past') return false;
    return true;
  }

  /// Check if alert is imminent (onset within 2 hours)
  bool get isImminent {
    if (onset == null) return false;
    final now = DateTime.now();
    final diff = onset!.difference(now);
    return diff.inHours <= 2 && diff.inMinutes >= 0;
  }

  /// Create a copy with a different source
  NWSAlert copyWithSource(String newSource) {
    return NWSAlert(
      id: id,
      event: event,
      headline: headline,
      description: description,
      instruction: instruction,
      severity: severity,
      certainty: certainty,
      urgency: urgency,
      effective: effective,
      expires: expires,
      onset: onset,
      ends: ends,
      areaDesc: areaDesc,
      senderName: senderName,
      source: newSource,
    );
  }

  factory NWSAlert.fromJson(Map<String, dynamic> properties, {String source = 'unknown'}) {
    return NWSAlert(
      id: properties['id'] ?? '',
      event: properties['event'] ?? 'Unknown Event',
      headline: properties['headline'] ?? properties['event'] ?? '',
      description: properties['description'] ?? '',
      instruction: properties['instruction'],
      severity: AlertSeverity.fromString(properties['severity']),
      certainty: properties['certainty'] ?? 'Unknown',
      urgency: properties['urgency'] ?? 'Unknown',
      effective: _parseDateTime(properties['effective']),
      expires: _parseDateTime(properties['expires']),
      onset: _parseDateTime(properties['onset']),
      ends: _parseDateTime(properties['ends']),
      areaDesc: properties['areaDesc'] ?? '',
      senderName: properties['senderName'] ?? 'NWS',
      source: source,
    );
  }

  static DateTime? _parseDateTime(String? value) {
    if (value == null) return null;
    return DateTime.tryParse(value);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is NWSAlert && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

/// NWS Alert Service - fetches and manages weather alerts
class NWSAlertService extends ChangeNotifier {
  static const String _baseUrl = 'https://api.weather.gov/alerts';
  static const String _userAgent = 'ZedDisplay-Weatherflow/1.0 (weather alert app)';

  List<NWSAlert> _alerts = [];
  Set<String> _seenAlertIds = {};
  Set<String> _newAlertIds = {};
  bool _isLoading = false;
  String? _error;
  DateTime? _lastFetch;
  Timer? _refreshTimer;

  // Location state
  Position? _phonePosition;
  double? _stationLat;
  double? _stationLon;
  AlertLocationSource _locationSource = AlertLocationSource.both;

  // Getters
  List<NWSAlert> get alerts => _alerts;
  List<NWSAlert> get activeAlerts => _alerts.where((a) => a.isActive).toList();
  Set<String> get newAlertIds => _newAlertIds;
  bool get isLoading => _isLoading;
  String? get error => _error;
  DateTime? get lastFetch => _lastFetch;
  AlertLocationSource get locationSource => _locationSource;

  /// Safely notify listeners to prevent "setState during build" errors
  void _safeNotifyListeners() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      notifyListeners();
    });
  }

  /// Set the location source preference
  void setLocationSource(AlertLocationSource source) {
    _locationSource = source;
    _safeNotifyListeners();
  }

  /// Set the station location (from WeatherFlow)
  void setStationLocation(double? lat, double? lon) {
    _stationLat = lat;
    _stationLon = lon;
  }

  /// Start auto-refresh timer
  void startAutoRefresh({Duration interval = const Duration(minutes: 5)}) {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(interval, (_) => fetchAlerts());
  }

  /// Stop auto-refresh timer
  void stopAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  /// Fetch alerts from NWS API
  Future<void> fetchAlerts() async {
    if (_isLoading) return;

    _isLoading = true;
    _error = null;
    _safeNotifyListeners();

    try {
      final allAlerts = <NWSAlert>[];

      // Fetch from phone location
      if (_locationSource == AlertLocationSource.phone ||
          _locationSource == AlertLocationSource.both) {
        try {
          final phoneAlerts = await _fetchFromPhoneLocation();
          allAlerts.addAll(phoneAlerts);
        } catch (e) {
          debugPrint('NWSAlertService: Failed to fetch from phone location: $e');
          if (_locationSource == AlertLocationSource.phone) {
            _error = 'Failed to get phone location: $e';
          }
        }
      }

      // Fetch from station location
      if (_locationSource == AlertLocationSource.station ||
          _locationSource == AlertLocationSource.both) {
        if (_stationLat != null && _stationLon != null) {
          try {
            final stationAlerts = await _fetchFromLocation(
              _stationLat!,
              _stationLon!,
              source: 'station',
            );
            allAlerts.addAll(stationAlerts);
          } catch (e) {
            debugPrint('NWSAlertService: Failed to fetch from station location: $e');
            if (_locationSource == AlertLocationSource.station) {
              _error = 'Failed to fetch alerts: $e';
            }
          }
        } else if (_locationSource == AlertLocationSource.station) {
          _error = 'No station location available';
        }
      }

      // Deduplicate alerts by ID (keep first occurrence)
      final deduped = <String, NWSAlert>{};
      for (final alert in allAlerts) {
        if (!deduped.containsKey(alert.id)) {
          deduped[alert.id] = alert;
        } else {
          // If we have the same alert from both sources, mark it as 'both'
          final existing = deduped[alert.id]!;
          if (existing.source != alert.source) {
            deduped[alert.id] = existing.copyWithSource('both');
          }
        }
      }

      final dedupedList = deduped.values.toList();

      // Sort by severity (highest first), then by onset time
      dedupedList.sort((a, b) {
        final severityCompare = a.severity.priority.compareTo(b.severity.priority);
        if (severityCompare != 0) return severityCompare;
        if (a.onset != null && b.onset != null) {
          return a.onset!.compareTo(b.onset!);
        }
        return 0;
      });

      // Track new alerts
      final currentIds = dedupedList.map((a) => a.id).toSet();
      final newIds = currentIds.difference(_seenAlertIds);

      _alerts = dedupedList;
      _newAlertIds = newIds;
      _seenAlertIds = currentIds;
      _lastFetch = DateTime.now();
      _isLoading = false;

      debugPrint('NWSAlertService: Fetched ${_alerts.length} alerts (${_newAlertIds.length} new)');
      _safeNotifyListeners();
    } catch (e) {
      _error = 'Failed to fetch alerts: $e';
      _isLoading = false;
      _safeNotifyListeners();
    }
  }

  /// Fetch alerts from phone's GPS location
  Future<List<NWSAlert>> _fetchFromPhoneLocation() async {
    // Check location permission
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permission denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception('Location permission permanently denied');
    }

    // Get current position
    _phonePosition = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.low,
        timeLimit: Duration(seconds: 10),
      ),
    );

    return _fetchFromLocation(
      _phonePosition!.latitude,
      _phonePosition!.longitude,
      source: 'phone',
    );
  }

  /// Fetch alerts from a specific location
  Future<List<NWSAlert>> _fetchFromLocation(
    double lat,
    double lon, {
    required String source,
  }) async {
    final url = Uri.parse(
      '$_baseUrl?point=${lat.toStringAsFixed(4)},${lon.toStringAsFixed(4)}&status=actual&limit=50',
    );

    debugPrint('NWSAlertService: Fetching from $url');

    final response = await http.get(
      url,
      headers: {
        'User-Agent': _userAgent,
        'Accept': 'application/geo+json',
      },
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: ${response.reasonPhrase}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final features = data['features'] as List<dynamic>? ?? [];

    final alerts = <NWSAlert>[];
    for (final feature in features) {
      final properties = feature['properties'] as Map<String, dynamic>?;
      if (properties != null) {
        alerts.add(NWSAlert.fromJson(properties, source: source));
      }
    }

    return alerts;
  }

  /// Mark an alert as seen (removes from new alerts)
  void markAlertSeen(String alertId) {
    _newAlertIds.remove(alertId);
    _safeNotifyListeners();
  }

  /// Mark all alerts as seen
  void markAllSeen() {
    _newAlertIds.clear();
    _safeNotifyListeners();
  }

  /// Clear all alerts and state
  void clear() {
    _alerts.clear();
    _seenAlertIds.clear();
    _newAlertIds.clear();
    _error = null;
    _lastFetch = null;
    _safeNotifyListeners();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
}
