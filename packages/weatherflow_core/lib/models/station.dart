import 'device.dart';

/// Station model for WeatherFlow Tempest stations
/// A station contains one or more devices (Tempest, Air, Sky, Hub)

class StationLocation {
  final double latitude;
  final double longitude;
  final int elevation; // meters

  const StationLocation({
    required this.latitude,
    required this.longitude,
    this.elevation = 0,
  });

  factory StationLocation.fromJson(Map<String, dynamic> json) {
    return StationLocation(
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      elevation: json['elevation'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'elevation': elevation,
      };
}

class Station {
  final int stationId;
  final String name;
  final StationLocation location;
  final String timezone;
  final bool isPublic;
  final List<Device> devices;
  final DateTime? lastModified;

  const Station({
    required this.stationId,
    required this.name,
    required this.location,
    this.timezone = 'UTC',
    this.isPublic = false,
    this.devices = const [],
    this.lastModified,
  });

  factory Station.fromJson(Map<String, dynamic> json) {
    // Parse devices from the response
    final devicesList = <Device>[];
    if (json['devices'] is List) {
      for (final deviceJson in json['devices'] as List) {
        if (deviceJson is Map<String, dynamic>) {
          devicesList.add(Device.fromJson(deviceJson));
        }
      }
    }

    return Station(
      stationId: json['station_id'] as int? ?? 0,
      name: json['name'] as String? ?? 'Unknown Station',
      location: StationLocation(
        latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
        longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
        elevation: (json['station_meta']?['elevation'] as num?)?.toInt() ?? 0,
      ),
      timezone: json['timezone'] as String? ?? 'UTC',
      isPublic: json['is_public'] as bool? ?? false,
      devices: devicesList,
      lastModified: json['last_modified'] != null
          ? DateTime.tryParse(json['last_modified'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'station_id': stationId,
        'name': name,
        'latitude': location.latitude,
        'longitude': location.longitude,
        'station_meta': {'elevation': location.elevation},
        'timezone': timezone,
        'is_public': isPublic,
        'devices': devices.map((d) => d.toJson()).toList(),
        'last_modified': lastModified?.toIso8601String(),
      };

  /// Get the primary Tempest device (if any)
  Device? get tempestDevice {
    try {
      return devices.firstWhere((d) => d.isTempest);
    } catch (_) {
      return null;
    }
  }

  /// Get the Hub device (if any)
  Device? get hubDevice {
    try {
      return devices.firstWhere((d) => d.isHub);
    } catch (_) {
      return null;
    }
  }

  /// Get all non-hub devices
  List<Device> get sensorDevices => devices.where((d) => !d.isHub).toList();

  /// Latitude convenience getter
  double get latitude => location.latitude;

  /// Longitude convenience getter
  double get longitude => location.longitude;

  /// Elevation convenience getter
  int get elevation => location.elevation;
}

/// Response wrapper for station list API
class StationListResponse {
  final List<Station> stations;

  const StationListResponse({this.stations = const []});

  factory StationListResponse.fromJson(Map<String, dynamic> json) {
    final stationsList = <Station>[];
    if (json['stations'] is List) {
      for (final stationJson in json['stations'] as List) {
        if (stationJson is Map<String, dynamic>) {
          stationsList.add(Station.fromJson(stationJson));
        }
      }
    }
    return StationListResponse(stations: stationsList);
  }
}
