/// Configuration import service
/// Handles parsing and importing .wdwfjson configuration files

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/export_config.dart';
import '../models/tool.dart';
import '../models/dashboard_layout.dart';
import '../models/activity_definition.dart';
import '../models/activity_tolerances.dart';
import 'storage_service.dart';
import 'dashboard_service.dart';
import 'tool_service.dart';

/// Import modes
enum ImportMode {
  /// Replace all existing configuration
  replace,
  /// Merge with existing (add new, update existing)
  merge,
}

/// Service for importing app configuration
class ConfigImportService {
  final StorageService _storageService;
  final DashboardService _dashboardService;
  final ToolService _toolService;

  static const String fileExtension = '.wdwfjson';

  ConfigImportService(
    this._storageService,
    this._dashboardService,
    this._toolService,
  );

  /// Parse and validate a config file
  /// Returns ImportResult with preview on success, or error on failure
  Future<ImportResult> parseConfig(File file) async {
    try {
      // Validate file extension
      if (!file.path.toLowerCase().endsWith(fileExtension)) {
        return ImportResult.failure(
          'Invalid file type. Expected $fileExtension file.',
        );
      }

      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      final config = ExportConfig.fromJson(json);

      // Validate version compatibility
      if (!ExportConfig.isVersionSupported(config.version)) {
        return ImportResult.failure(
          'Unsupported config version: ${config.version}. '
          'Supported versions: ${supportedSchemaVersions.join(", ")}',
        );
      }

      // Build preview
      final preview = ImportPreview.fromConfig(config);
      return ImportResult.successWithPreview(preview);
    } on FormatException catch (e) {
      return ImportResult.failure('Invalid JSON format: ${e.message}');
    } catch (e) {
      return ImportResult.failure('Failed to parse config: $e');
    }
  }

  /// Parse a config file and return the ExportConfig object
  /// Use this after parseConfig() returns success
  Future<ExportConfig?> loadConfig(File file) async {
    try {
      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      return ExportConfig.fromJson(json);
    } catch (e) {
      debugPrint('ConfigImportService: Failed to load config: $e');
      return null;
    }
  }

  /// Apply imported configuration
  /// [config] - The parsed export config
  /// [mode] - Replace (clear all first) or Merge (add/update)
  /// [includeStations] - Whether to import station references from the config
  Future<ImportResult> applyConfig(
    ExportConfig config,
    ImportMode mode, {
    bool includeStations = true,
  }) async {
    try {
      final warnings = <String>[];

      if (mode == ImportMode.replace) {
        await _replaceAll(config, includeStations, warnings);
      } else {
        await _mergeConfig(config, includeStations, warnings);
      }

      // Notify services to refresh
      _dashboardService.refresh();
      _toolService.refresh();

      debugPrint('ConfigImportService: Import complete with ${warnings.length} warnings');
      return ImportResult.successWithPreview(
        ImportPreview.fromConfig(config),
        warnings: warnings,
      );
    } catch (e) {
      debugPrint('ConfigImportService: Import failed: $e');
      return ImportResult.failure('Failed to apply config: $e');
    }
  }

  /// Replace all existing config with imported config
  Future<void> _replaceAll(
    ExportConfig config,
    bool includeStations,
    List<String> warnings,
  ) async {
    debugPrint('ConfigImportService: Replacing all configuration');

    // Apply settings
    await _applySettings(config.config.settings);
    await _applyUnitPreferences(config.config.unitPreferences);
    await _applyActivityTolerances(config.config.activityTolerances);

    // Replace tools
    await _replaceTools(config.config.tools);

    // Replace dashboard layout
    if (config.config.dashboardLayout != null) {
      await _replaceDashboardLayout(config.config.dashboardLayout!);
    }

    // Apply station-specific tool configs
    await _applyStationToolConfigs(config.config.stationToolConfigs);

    // Note: Stations themselves can't be "imported" - they require API token
    // We only import the station tool configs for stations that already exist
    if (includeStations && config.stations != null && config.stations!.isNotEmpty) {
      warnings.add(
        'Station list imported for reference. '
        'Stations require API token authentication and cannot be auto-added.',
      );
    }
  }

  /// Merge imported config with existing (add new, update existing)
  Future<void> _mergeConfig(
    ExportConfig config,
    bool includeStations,
    List<String> warnings,
  ) async {
    debugPrint('ConfigImportService: Merging configuration');

    // Settings are always replaced (no merge concept for individual settings)
    await _applySettings(config.config.settings);
    await _applyUnitPreferences(config.config.unitPreferences);
    await _applyActivityTolerances(config.config.activityTolerances);

    // Merge tools (add new, update existing by ID)
    await _mergeTools(config.config.tools, warnings);

    // Merge dashboard layout
    if (config.config.dashboardLayout != null) {
      await _mergeDashboardLayout(config.config.dashboardLayout!, warnings);
    }

    // Apply station-specific tool configs (merge)
    await _applyStationToolConfigs(config.config.stationToolConfigs);

    // Note about stations
    if (includeStations && config.stations != null && config.stations!.isNotEmpty) {
      warnings.add(
        'Station list imported for reference. '
        'Stations require API token authentication.',
      );
    }
  }

  // ============ Apply Settings ============

  Future<void> _applySettings(ExportAppSettings settings) async {
    await _storageService.setThemeMode(settings.themeMode);
    await _storageService.setRefreshInterval(settings.refreshInterval);
    await _storageService.setUdpEnabled(settings.udpEnabled);
    await _storageService.setUdpPort(settings.udpPort);
  }

  Future<void> _applyUnitPreferences(dynamic unitPrefs) async {
    if (unitPrefs != null) {
      await _storageService.setUnitPreferences(unitPrefs);
    }
  }

  Future<void> _applyActivityTolerances(
    Map<String, ActivityTolerances>? tolerances,
  ) async {
    if (tolerances == null) return;

    for (final entry in tolerances.entries) {
      final activity = ActivityTypeExtension.fromKey(entry.key);
      if (activity != null) {
        await _storageService.setActivityTolerance(entry.value);
      }
    }
  }

  // ============ Apply Tools ============

  Future<void> _replaceTools(List<Tool> tools) async {
    // Clear existing tools and add imported ones
    await _toolService.clearAllTools();
    for (final tool in tools) {
      await _toolService.importTool(tool);
    }
  }

  Future<void> _mergeTools(List<Tool> tools, List<String> warnings) async {
    for (final tool in tools) {
      final existing = _toolService.getTool(tool.id);
      if (existing != null) {
        // Update existing tool
        await _toolService.updateTool(tool);
        debugPrint('ConfigImportService: Updated tool ${tool.id}');
      } else {
        // Add new tool
        await _toolService.importTool(tool);
        debugPrint('ConfigImportService: Added tool ${tool.id}');
      }
    }
  }

  // ============ Apply Dashboard Layout ============

  Future<void> _replaceDashboardLayout(DashboardLayout layout) async {
    await _dashboardService.updateLayout(layout);
  }

  Future<void> _mergeDashboardLayout(
    DashboardLayout layout,
    List<String> warnings,
  ) async {
    // For merge, we add new screens but keep existing ones
    final current = _dashboardService.currentLayout;
    if (current == null) {
      await _dashboardService.updateLayout(layout);
      return;
    }

    // Add screens from imported layout that don't exist
    for (final screen in layout.screens) {
      final exists = current.screens.any((s) => s.id == screen.id);
      if (!exists) {
        await _dashboardService.importScreen(screen);
        debugPrint('ConfigImportService: Added screen ${screen.id}');
      } else {
        warnings.add('Skipped existing screen: ${screen.name}');
      }
    }
  }

  // ============ Apply Station Tool Configs ============

  Future<void> _applyStationToolConfigs(
    Map<String, Map<String, Map<String, dynamic>>> configs,
  ) async {
    for (final stationEntry in configs.entries) {
      final stationId = int.tryParse(stationEntry.key);
      if (stationId == null) continue;

      final toolConfigs = stationEntry.value;
      for (final toolEntry in toolConfigs.entries) {
        await _storageService.setToolConfigForStation(
          stationId,
          toolEntry.key,
          toolEntry.value,
        );
      }
    }
  }
}
