/// Device model for WeatherFlow Tempest devices
/// Device types: ST (Tempest), AR (Air), SK (Sky), HB (Hub)

class DeviceStatus {
  final int uptime; // seconds
  final double voltage;
  final String firmwareRevision;
  final int rssi; // signal strength
  final int hubRssi;
  final int sensorStatus; // bit flags for sensor health
  final bool debugEnabled;

  const DeviceStatus({
    this.uptime = 0,
    this.voltage = 0.0,
    this.firmwareRevision = '',
    this.rssi = 0,
    this.hubRssi = 0,
    this.sensorStatus = 0,
    this.debugEnabled = false,
  });

  factory DeviceStatus.fromJson(Map<String, dynamic> json) {
    return DeviceStatus(
      uptime: json['uptime'] as int? ?? 0,
      voltage: (json['voltage'] as num?)?.toDouble() ?? 0.0,
      firmwareRevision: json['firmware_revision'] as String? ?? '',
      rssi: json['rssi'] as int? ?? 0,
      hubRssi: json['hub_rssi'] as int? ?? 0,
      sensorStatus: json['sensor_status'] as int? ?? 0,
      debugEnabled: json['debug'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'uptime': uptime,
        'voltage': voltage,
        'firmware_revision': firmwareRevision,
        'rssi': rssi,
        'hub_rssi': hubRssi,
        'sensor_status': sensorStatus,
        'debug': debugEnabled,
      };

  /// Check if a specific sensor is failing based on sensor_status bit flags
  /// Bit positions: 0=lightning, 1=lightning_noise, 2=lightning_disturber,
  /// 3=pressure, 4=temperature, 5=humidity, 6=wind, 7=precip, 8=light/UV
  bool isSensorFailing(int bitPosition) {
    return (sensorStatus & (1 << bitPosition)) != 0;
  }

  bool get isLightningFailing => isSensorFailing(0);
  bool get isPressureFailing => isSensorFailing(3);
  bool get isTemperatureFailing => isSensorFailing(4);
  bool get isHumidityFailing => isSensorFailing(5);
  bool get isWindFailing => isSensorFailing(6);
  bool get isPrecipFailing => isSensorFailing(7);
  bool get isLightUvFailing => isSensorFailing(8);

  bool get hasAnyFailure => sensorStatus != 0;
}

class Device {
  final int deviceId;
  final String serialNumber;
  final String deviceType; // 'ST' (Tempest), 'AR' (Air), 'SK' (Sky), 'HB' (Hub)
  final String? deviceName;
  final String firmwareRevision;
  final String hardwareRevision;
  final DeviceStatus? status;

  const Device({
    required this.deviceId,
    required this.serialNumber,
    required this.deviceType,
    this.deviceName,
    this.firmwareRevision = '',
    this.hardwareRevision = '',
    this.status,
  });

  factory Device.fromJson(Map<String, dynamic> json) {
    return Device(
      deviceId: json['device_id'] as int? ?? 0,
      serialNumber: json['serial_number'] as String? ?? '',
      deviceType: json['device_type'] as String? ?? 'ST',
      deviceName: json['device_meta']?['name'] as String?,
      firmwareRevision: json['firmware_revision'] as String? ?? '',
      hardwareRevision: json['hardware_revision'] as String? ?? '',
      status: json['device_status'] != null
          ? DeviceStatus.fromJson(json['device_status'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'device_id': deviceId,
        'serial_number': serialNumber,
        'device_type': deviceType,
        'device_meta': deviceName != null ? {'name': deviceName} : null,
        'firmware_revision': firmwareRevision,
        'hardware_revision': hardwareRevision,
        'device_status': status?.toJson(),
      };

  /// Get human-readable device type name
  String get deviceTypeName {
    switch (deviceType) {
      case 'ST':
        return 'Tempest';
      case 'AR':
        return 'Air';
      case 'SK':
        return 'Sky';
      case 'HB':
        return 'Hub';
      default:
        return deviceType;
    }
  }

  /// Display name (custom name or serial number)
  String get displayName => deviceName ?? serialNumber;

  /// Check if this is a Tempest (combined sensor)
  bool get isTempest => deviceType == 'ST';

  /// Check if this is a Hub
  bool get isHub => deviceType == 'HB';
}
