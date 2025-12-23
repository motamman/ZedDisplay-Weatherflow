/// Configuration export service
/// Handles gathering and exporting app configuration to .wdwfjson files

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../models/export_config.dart';
import '../models/activity_definition.dart';
import '../models/activity_tolerances.dart';
import 'storage_service.dart';
import 'dashboard_service.dart';
import 'tool_service.dart';
import 'weatherflow_service.dart';

/// Service for exporting app configuration
class ConfigExportService {
  final StorageService _storageService;
  final DashboardService _dashboardService;
  final ToolService _toolService;
  final WeatherFlowService _weatherFlowService;

  static const String fileExtension = '.wdwfjson';
  static const String mimeType = 'application/json';

  ConfigExportService(
    this._storageService,
    this._dashboardService,
    this._toolService,
    this._weatherFlowService,
  );

  /// Gather all configuration data into an ExportConfig
  Future<ExportConfig> gatherConfig({bool includeStations = true}) async {
    // Get device and app info
    final deviceInfo = await _getDeviceInfo();
    final packageInfo = await PackageInfo.fromPlatform();

    // Gather settings
    final settings = ExportAppSettings(
      themeMode: _storageService.themeMode,
      refreshInterval: _storageService.refreshInterval,
      udpEnabled: _storageService.udpEnabled,
      udpPort: _storageService.udpPort,
    );

    // Gather activity tolerances
    final activityTolerances = <String, ActivityTolerances>{};
    for (final activity in ActivityType.values) {
      final tolerance = _storageService.getActivityTolerance(activity);
      activityTolerances[activity.key] = tolerance;
    }

    // Gather station-specific tool configs
    final stationToolConfigs = <String, Map<String, Map<String, dynamic>>>{};
    final stations = _weatherFlowService.stations;
    for (final station in stations) {
      final stationId = station.stationId.toString();
      final configs = _storageService.getStationToolConfigs(station.stationId);
      if (configs.isNotEmpty) {
        stationToolConfigs[stationId] = configs;
      }
    }

    // Build config data
    final configData = ExportConfigData(
      settings: settings,
      unitPreferences: _storageService.unitPreferences,
      activityTolerances: activityTolerances.isNotEmpty ? activityTolerances : null,
      dashboardLayout: _dashboardService.currentLayout,
      tools: _toolService.tools,
      stationToolConfigs: stationToolConfigs,
    );

    // Gather stations if requested
    List<ExportStation>? exportStations;
    if (includeStations && stations.isNotEmpty) {
      exportStations = stations.map((s) => ExportStation.fromStation(s)).toList();
    }

    // Build export config
    return ExportConfig(
      version: exportSchemaVersion,
      appVersion: packageInfo.version,
      exportedAt: DateTime.now().toUtc(),
      deviceInfo: deviceInfo,
      config: configData,
      stations: exportStations,
    );
  }

  /// Get device info for export metadata
  Future<DeviceInfo> _getDeviceInfo() async {
    final deviceInfoPlugin = DeviceInfoPlugin();

    try {
      if (Platform.isIOS) {
        final iosInfo = await deviceInfoPlugin.iosInfo;
        return DeviceInfo(
          platform: 'ios',
          osVersion: iosInfo.systemVersion,
          deviceModel: iosInfo.model,
        );
      } else if (Platform.isAndroid) {
        final androidInfo = await deviceInfoPlugin.androidInfo;
        return DeviceInfo(
          platform: 'android',
          osVersion: androidInfo.version.release,
          deviceModel: androidInfo.model,
        );
      }
    } catch (e) {
      debugPrint('ConfigExportService: Error getting device info: $e');
    }

    return DeviceInfo.fromCurrentDevice();
  }

  /// Export config to JSON string
  Future<String> exportToJson({bool includeStations = true}) async {
    final config = await gatherConfig(includeStations: includeStations);
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(config.toJson());
  }

  /// Export and save to file in app documents directory
  Future<File> exportToFile({
    String? filename,
    bool includeStations = true,
  }) async {
    final json = await exportToJson(includeStations: includeStations);
    final dir = await getApplicationDocumentsDirectory();
    final name = filename ?? generateFilename();
    final file = File('${dir.path}/$name$fileExtension');
    await file.writeAsString(json);
    debugPrint('ConfigExportService: Exported to ${file.path}');
    return file;
  }

  /// Export and share via system share sheet
  Future<ShareResult> shareConfig({
    String? filename,
    bool includeStations = true,
  }) async {
    final file = await exportToFile(
      filename: filename,
      includeStations: includeStations,
    );

    final result = await Share.shareXFiles(
      [XFile(file.path, mimeType: mimeType)],
      subject: 'ZedDisplay WeatherFlow Configuration',
      text: 'My ZedDisplay WeatherFlow app configuration',
    );

    debugPrint('ConfigExportService: Share result: ${result.status}');
    return result;
  }

  /// Generate default filename for export
  String generateFilename() {
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-')
        .substring(0, 19); // YYYY-MM-DDTHH-MM-SS
    return 'zeddisplay-weatherflow-$timestamp';
  }
}
