/// Export configuration model for backup and sharing
/// File extension: .wdwfjson (ZedDisplay WeatherFlow JSON)

import 'dart:io';
import 'dashboard_layout.dart';
import 'tool.dart';
import 'activity_tolerances.dart';
import 'package:weatherflow_core/weatherflow_core.dart';

/// Schema version for export format
const String exportSchemaVersion = '1.0.0';

/// Supported schema versions for import
const List<String> supportedSchemaVersions = ['1.0.0'];

/// Device information for export metadata
class DeviceInfo {
  final String platform;
  final String? osVersion;
  final String? deviceModel;

  const DeviceInfo({
    required this.platform,
    this.osVersion,
    this.deviceModel,
  });

  factory DeviceInfo.fromJson(Map<String, dynamic> json) {
    return DeviceInfo(
      platform: json['platform'] as String? ?? 'unknown',
      osVersion: json['osVersion'] as String?,
      deviceModel: json['deviceModel'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'platform': platform,
    if (osVersion != null) 'osVersion': osVersion,
    if (deviceModel != null) 'deviceModel': deviceModel,
  };

  /// Create from current device
  static DeviceInfo fromCurrentDevice() {
    return DeviceInfo(
      platform: Platform.operatingSystem,
      osVersion: Platform.operatingSystemVersion,
    );
  }
}

/// App settings for export
class ExportAppSettings {
  final String themeMode;
  final int refreshInterval;
  final bool udpEnabled;
  final int udpPort;

  const ExportAppSettings({
    this.themeMode = 'system',
    this.refreshInterval = 5,
    this.udpEnabled = true,
    this.udpPort = 50222,
  });

  factory ExportAppSettings.fromJson(Map<String, dynamic> json) {
    return ExportAppSettings(
      themeMode: json['themeMode'] as String? ?? 'system',
      refreshInterval: json['refreshInterval'] as int? ?? 5,
      udpEnabled: json['udpEnabled'] as bool? ?? true,
      udpPort: json['udpPort'] as int? ?? 50222,
    );
  }

  Map<String, dynamic> toJson() => {
    'themeMode': themeMode,
    'refreshInterval': refreshInterval,
    'udpEnabled': udpEnabled,
    'udpPort': udpPort,
  };
}

/// Station info for export (minimal, no API token)
class ExportStation {
  final int stationId;
  final String name;
  final double? latitude;
  final double? longitude;
  final String? timezone;

  const ExportStation({
    required this.stationId,
    required this.name,
    this.latitude,
    this.longitude,
    this.timezone,
  });

  factory ExportStation.fromJson(Map<String, dynamic> json) {
    return ExportStation(
      stationId: json['stationId'] as int,
      name: json['name'] as String,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      timezone: json['timezone'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'stationId': stationId,
    'name': name,
    if (latitude != null) 'latitude': latitude,
    if (longitude != null) 'longitude': longitude,
    if (timezone != null) 'timezone': timezone,
  };

  /// Create from Station model
  factory ExportStation.fromStation(Station station) {
    return ExportStation(
      stationId: station.stationId,
      name: station.name,
      latitude: station.latitude,
      longitude: station.longitude,
      timezone: station.timezone,
    );
  }
}

/// Configuration data section of export
class ExportConfigData {
  final ExportAppSettings settings;
  final UnitPreferences unitPreferences;
  final Map<String, ActivityTolerances>? activityTolerances;
  final DashboardLayout? dashboardLayout;
  final List<Tool> tools;
  final Map<String, Map<String, Map<String, dynamic>>> stationToolConfigs;

  const ExportConfigData({
    required this.settings,
    required this.unitPreferences,
    this.activityTolerances,
    this.dashboardLayout,
    this.tools = const [],
    this.stationToolConfigs = const {},
  });

  factory ExportConfigData.fromJson(Map<String, dynamic> json) {
    // Parse activity tolerances
    Map<String, ActivityTolerances>? activityTolerances;
    if (json['activityTolerances'] != null) {
      activityTolerances = {};
      final tolerancesJson = json['activityTolerances'] as Map<String, dynamic>;
      for (final entry in tolerancesJson.entries) {
        activityTolerances[entry.key] = ActivityTolerances.fromJson(
          entry.value as Map<String, dynamic>,
        );
      }
    }

    // Parse station tool configs
    final stationToolConfigs = <String, Map<String, Map<String, dynamic>>>{};
    if (json['stationToolConfigs'] != null) {
      final stationConfigsJson = json['stationToolConfigs'] as Map<String, dynamic>;
      for (final stationEntry in stationConfigsJson.entries) {
        final toolConfigs = <String, Map<String, dynamic>>{};
        final toolConfigsJson = stationEntry.value as Map<String, dynamic>;
        for (final toolEntry in toolConfigsJson.entries) {
          toolConfigs[toolEntry.key] = Map<String, dynamic>.from(
            toolEntry.value as Map,
          );
        }
        stationToolConfigs[stationEntry.key] = toolConfigs;
      }
    }

    return ExportConfigData(
      settings: ExportAppSettings.fromJson(
        json['settings'] as Map<String, dynamic>? ?? {},
      ),
      unitPreferences: json['unitPreferences'] != null
          ? UnitPreferences.fromJson(json['unitPreferences'] as Map<String, dynamic>)
          : UnitPreferences.nautical,
      activityTolerances: activityTolerances,
      dashboardLayout: json['dashboardLayout'] != null
          ? DashboardLayout.fromJson(json['dashboardLayout'] as Map<String, dynamic>)
          : null,
      tools: (json['tools'] as List<dynamic>?)
          ?.map((e) => Tool.fromJson(e as Map<String, dynamic>))
          .toList() ?? const [],
      stationToolConfigs: stationToolConfigs,
    );
  }

  Map<String, dynamic> toJson() {
    // Serialize activity tolerances
    Map<String, dynamic>? activityTolerancesJson;
    if (activityTolerances != null) {
      activityTolerancesJson = {};
      for (final entry in activityTolerances!.entries) {
        activityTolerancesJson[entry.key] = entry.value.toJson();
      }
    }

    return {
      'settings': settings.toJson(),
      'unitPreferences': unitPreferences.toJson(),
      if (activityTolerancesJson != null) 'activityTolerances': activityTolerancesJson,
      if (dashboardLayout != null) 'dashboardLayout': dashboardLayout!.toJson(),
      'tools': tools.map((t) => t.toJson()).toList(),
      'stationToolConfigs': stationToolConfigs,
    };
  }
}

/// Full export configuration
class ExportConfig {
  final String version;
  final String? appVersion;
  final DateTime exportedAt;
  final DeviceInfo? deviceInfo;
  final ExportConfigData config;
  final List<ExportStation>? stations;

  const ExportConfig({
    required this.version,
    this.appVersion,
    required this.exportedAt,
    this.deviceInfo,
    required this.config,
    this.stations,
  });

  factory ExportConfig.fromJson(Map<String, dynamic> json) {
    return ExportConfig(
      version: json['version'] as String? ?? '1.0.0',
      appVersion: json['appVersion'] as String?,
      exportedAt: json['exportedAt'] != null
          ? DateTime.parse(json['exportedAt'] as String)
          : DateTime.now(),
      deviceInfo: json['deviceInfo'] != null
          ? DeviceInfo.fromJson(json['deviceInfo'] as Map<String, dynamic>)
          : null,
      config: ExportConfigData.fromJson(
        json['config'] as Map<String, dynamic>? ?? {},
      ),
      stations: (json['stations'] as List<dynamic>?)
          ?.map((e) => ExportStation.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'version': version,
    if (appVersion != null) 'appVersion': appVersion,
    'exportedAt': exportedAt.toIso8601String(),
    if (deviceInfo != null) 'deviceInfo': deviceInfo!.toJson(),
    'config': config.toJson(),
    if (stations != null) 'stations': stations!.map((s) => s.toJson()).toList(),
  };

  /// Check if version is supported for import
  static bool isVersionSupported(String version) {
    return supportedSchemaVersions.contains(version);
  }
}

/// Preview information for import dialog
class ImportPreview {
  final int toolsCount;
  final int screensCount;
  final int stationsCount;
  final int activitiesCount;
  final bool hasSettings;
  final bool hasUnitPreferences;
  final bool hasDashboardLayout;
  final String? exportVersion;
  final String? exportAppVersion;
  final DateTime? exportedAt;

  const ImportPreview({
    this.toolsCount = 0,
    this.screensCount = 0,
    this.stationsCount = 0,
    this.activitiesCount = 0,
    this.hasSettings = false,
    this.hasUnitPreferences = false,
    this.hasDashboardLayout = false,
    this.exportVersion,
    this.exportAppVersion,
    this.exportedAt,
  });

  /// Create from ExportConfig
  factory ImportPreview.fromConfig(ExportConfig config) {
    return ImportPreview(
      toolsCount: config.config.tools.length,
      screensCount: config.config.dashboardLayout?.screens.length ?? 0,
      stationsCount: config.stations?.length ?? 0,
      activitiesCount: config.config.activityTolerances?.length ?? 0,
      hasSettings: true,
      hasUnitPreferences: true,
      hasDashboardLayout: config.config.dashboardLayout != null,
      exportVersion: config.version,
      exportAppVersion: config.appVersion,
      exportedAt: config.exportedAt,
    );
  }
}

/// Result of import operation
class ImportResult {
  final bool success;
  final String? error;
  final ImportPreview? preview;
  final List<String> warnings;

  const ImportResult({
    required this.success,
    this.error,
    this.preview,
    this.warnings = const [],
  });

  /// Success result with preview
  factory ImportResult.successWithPreview(ImportPreview preview, {List<String> warnings = const []}) {
    return ImportResult(
      success: true,
      preview: preview,
      warnings: warnings,
    );
  }

  /// Error result
  factory ImportResult.failure(String error) {
    return ImportResult(
      success: false,
      error: error,
    );
  }
}
