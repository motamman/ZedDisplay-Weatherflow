/// Dashboard service for managing dashboard layouts
/// Adapted from ZedDisplay architecture

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../models/dashboard_layout.dart';
import '../models/dashboard_screen.dart';
import '../models/tool_placement.dart';
import '../models/tool_config.dart';
import '../models/export_config.dart';
import 'storage_service.dart';
import 'tool_service.dart';
import 'tool_registry.dart';

/// Service for managing dashboard layouts and screens
class DashboardService extends ChangeNotifier {
  final StorageService _storageService;
  final ToolService _toolService;
  ToolRegistry? _toolRegistry;

  DashboardLayout? _currentLayout;
  bool _initialized = false;
  bool _editMode = false;

  static const String _layoutStorageKey = 'dashboard_layout';

  DashboardService(this._storageService, this._toolService);

  /// Set the tool registry (called after initialization)
  void setToolRegistry(ToolRegistry registry) {
    _toolRegistry = registry;
  }

  DashboardLayout? get currentLayout => _currentLayout;
  bool get initialized => _initialized;
  bool get editMode => _editMode;

  /// Initialize and load the active dashboard
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // Try to load saved layout
      final layoutJson = await _storageService.getString(_layoutStorageKey);
      if (layoutJson != null) {
        _currentLayout = DashboardLayout.fromJson(
          jsonDecode(layoutJson) as Map<String, dynamic>,
        );
      }

      // If no layout, try bundled default config first, then fall back to hardcoded defaults
      if (_currentLayout == null) {
        final loadedFromBundle = await _loadBundledDefaultConfig();
        if (!loadedFromBundle) {
          // Fall back to hardcoded defaults
          final toolIds = await _createDefaultTools();

          _currentLayout = DashboardLayout(
            id: 'layout_default',
            name: 'Default Dashboard',
            screens: [
              // Screen 1: Hourly (spinner + alerts)
              DashboardScreen(
                id: 'screen_hourly',
                name: 'Hourly',
                placements: [
                  if (toolIds['spinner'] != null)
                    ToolPlacement(
                      toolId: toolIds['spinner']!,
                      screenId: 'screen_hourly',
                      position: const GridPosition(col: 0, row: 1, width: 8, height: 4),
                    ),
                  if (toolIds['alerts'] != null)
                    ToolPlacement(
                      toolId: toolIds['alerts']!,
                      screenId: 'screen_hourly',
                      position: const GridPosition(col: 0, row: 5, width: 8, height: 3),
                    ),
                ],
                order: 0,
              ),
              // Screen 2: Daily (forecast fills screen)
              DashboardScreen(
                id: 'screen_daily',
                name: 'Daily',
                placements: toolIds['forecast'] != null
                    ? [
                        ToolPlacement(
                          toolId: toolIds['forecast']!,
                          screenId: 'screen_daily',
                          position: const GridPosition(col: 0, row: 0, width: 8, height: 8),
                        ),
                      ]
                    : [],
                order: 1,
              ),
              // Screen 3: Charts (2 stacked vertically)
              DashboardScreen(
                id: 'screen_charts',
                name: 'Charts',
                placements: [
                  if (toolIds['tempChart'] != null)
                    ToolPlacement(
                      toolId: toolIds['tempChart']!,
                      screenId: 'screen_charts',
                      position: const GridPosition(col: 0, row: 0, width: 8, height: 4),
                    ),
                  if (toolIds['windChart'] != null)
                    ToolPlacement(
                      toolId: toolIds['windChart']!,
                      screenId: 'screen_charts',
                      position: const GridPosition(col: 0, row: 4, width: 8, height: 4),
                    ),
                ],
                order: 2,
              ),
            ],
            activeScreenIndex: 0,
          );
          await _saveDashboard();
        }
      }

      _initialized = true;
      notifyListeners();

      debugPrint('DashboardService: Initialized with ${_currentLayout!.screens.length} screens');
    } catch (e) {
      debugPrint('DashboardService: Error initializing: $e');
      // Create default layout on error
      _currentLayout = DashboardLayout(
        id: 'layout_default',
        name: 'Default Dashboard',
        screens: [
          DashboardScreen(
            id: 'screen_main',
            name: 'Main',
            placements: [],
            order: 0,
          ),
        ],
        activeScreenIndex: 0,
      );
      _initialized = true;
      notifyListeners();
    }
  }

  Future<void> _saveDashboard() async {
    if (_currentLayout == null) return;
    try {
      await _storageService.setString(
        _layoutStorageKey,
        jsonEncode(_currentLayout!.toJson()),
      );
    } catch (e) {
      debugPrint('DashboardService: Error saving dashboard: $e');
    }
  }

  /// Load bundled default config from assets if available
  /// Returns true if config was loaded successfully, false otherwise
  Future<bool> _loadBundledDefaultConfig() async {
    try {
      final jsonString = await rootBundle.loadString('assets/defaults/default-config.wdwfjson');
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      final config = ExportConfig.fromJson(json);

      // Validate version
      if (!ExportConfig.isVersionSupported(config.version)) {
        debugPrint('DashboardService: Bundled config version ${config.version} not supported');
        return false;
      }

      // Apply tools from config
      for (final tool in config.config.tools) {
        await _toolService.importTool(tool);
      }
      debugPrint('DashboardService: Imported ${config.config.tools.length} tools from bundled config');

      // Apply dashboard layout
      if (config.config.dashboardLayout != null) {
        _currentLayout = config.config.dashboardLayout;
        await _saveDashboard();
        debugPrint('DashboardService: Loaded dashboard layout from bundled config');
      }

      // Apply settings (but not stations - user will configure via API token)
      await _applyBundledSettings(config.config);

      debugPrint('DashboardService: Successfully loaded bundled default config');
      return _currentLayout != null;
    } catch (e) {
      // File doesn't exist or parse error - this is expected if no default config is bundled
      debugPrint('DashboardService: No bundled default config (assets/defaults/default-config.wdwfjson): $e');
      return false;
    }
  }

  /// Apply settings from bundled config (excluding stations)
  Future<void> _applyBundledSettings(ExportConfigData config) async {
    final settings = config.settings;

    await _storageService.setThemeMode(settings.themeMode);
    await _storageService.setRefreshInterval(settings.refreshInterval);
    await _storageService.setUdpEnabled(settings.udpEnabled);
    await _storageService.setUdpPort(settings.udpPort);

    // Apply unit preferences
    await _storageService.setUnitPreferences(config.unitPreferences);

    // Apply activity tolerances
    if (config.activityTolerances != null) {
      for (final entry in config.activityTolerances!.entries) {
        await _storageService.setActivityTolerance(entry.value);
      }
    }
  }

  /// Create default tools for first install
  Future<Map<String, String>> _createDefaultTools() async {
    final toolIds = <String, String>{};

    if (_toolRegistry == null) {
      debugPrint('DashboardService: No tool registry available, skipping default tools');
      return toolIds;
    }

    // 1. Spinner tool (for Hourly screen)
    final spinnerDef = _toolRegistry!.getDefinition('weather_api_spinner');
    if (spinnerDef != null) {
      final spinner = await _toolService.createTool(
        name: 'Hourly Conditions',
        definition: spinnerDef,
        config: _toolRegistry!.getDefaultConfig('weather_api_spinner') ??
            const ToolConfig(dataSources: [], style: StyleConfig()),
      );
      toolIds['spinner'] = spinner.id;
    }

    // 2. Forecast tool (for Daily screen)
    final forecastDef = _toolRegistry!.getDefinition('weatherflow_forecast');
    if (forecastDef != null) {
      final forecast = await _toolService.createTool(
        name: 'Weekly Forecast',
        definition: forecastDef,
        config: _toolRegistry!.getDefaultConfig('weatherflow_forecast') ??
            const ToolConfig(dataSources: [], style: StyleConfig()),
      );
      toolIds['forecast'] = forecast.id;
    }

    // 3. Weather Alerts tool (for Hourly screen)
    final alertsDef = _toolRegistry!.getDefinition('weather_alerts');
    if (alertsDef != null) {
      final alerts = await _toolService.createTool(
        name: 'Weather Alerts',
        definition: alertsDef,
        config: _toolRegistry!.getDefaultConfig('weather_alerts') ??
            const ToolConfig(dataSources: [], style: StyleConfig()),
      );
      toolIds['alerts'] = alerts.id;
    }

    // 4. Temperature chart (combo mode)
    final chartDef = _toolRegistry!.getDefinition('forecast_chart');
    if (chartDef != null) {
      final tempChart = await _toolService.createTool(
        name: 'Temperature',
        definition: chartDef,
        config: const ToolConfig(
          dataSources: [],
          style: StyleConfig(
            primaryColor: '#4A90D9',
            customProperties: {
              'dataElement': 'temperature',
              'chartMode': 'combo',
              'forecastDays': 7,
              'showGrid': true,
              'showLegend': true,
              'showDataPoints': false,
            },
          ),
        ),
      );
      toolIds['tempChart'] = tempChart.id;

      // 5. Wind chart (hourly mode)
      final windChart = await _toolService.createTool(
        name: 'Wind Speed',
        definition: chartDef,
        config: const ToolConfig(
          dataSources: [],
          style: StyleConfig(
            primaryColor: '#5CB85C',
            customProperties: {
              'dataElement': 'wind_speed',
              'chartMode': 'hourly',
              'forecastDays': 3,
              'showGrid': true,
              'showLegend': true,
              'showDataPoints': false,
            },
          ),
        ),
      );
      toolIds['windChart'] = windChart.id;
    }

    debugPrint('DashboardService: Created ${toolIds.length} default tools');
    return toolIds;
  }

  /// Toggle edit mode
  void toggleEditMode() {
    _editMode = !_editMode;
    notifyListeners();
  }

  /// Set edit mode
  void setEditMode(bool enabled) {
    _editMode = enabled;
    notifyListeners();
  }

  /// Refresh listeners (for config import)
  void refresh() {
    notifyListeners();
  }

  /// Update the current layout
  Future<void> updateLayout(DashboardLayout layout) async {
    _currentLayout = layout;
    notifyListeners();
    await _saveDashboard();
  }

  /// Add a screen to the current layout
  Future<void> addScreen({String? name}) async {
    if (_currentLayout == null) return;

    final screenName = name ?? 'Screen ${_currentLayout!.screens.length + 1}';
    final newScreen = DashboardScreen(
      id: 'screen_${DateTime.now().millisecondsSinceEpoch}',
      name: screenName,
      placements: [],
      order: _currentLayout!.screens.length,
    );

    _currentLayout = _currentLayout!.addScreen(newScreen);
    notifyListeners();
    await _saveDashboard();
  }

  /// Import a full screen (preserves original ID and placements)
  /// Used for config import
  Future<void> importScreen(DashboardScreen screen) async {
    if (_currentLayout == null) return;

    _currentLayout = _currentLayout!.addScreen(screen);
    notifyListeners();
    await _saveDashboard();
  }

  /// Remove a screen from the current layout
  /// If the last screen is removed, a blank replacement is created
  Future<void> removeScreen(String screenId) async {
    if (_currentLayout == null) return;

    _currentLayout = _currentLayout!.removeScreen(screenId);
    notifyListeners();
    await _saveDashboard();
  }

  /// Rename a screen
  Future<void> renameScreen(String screenId, String newName) async {
    if (_currentLayout == null) return;

    final screenIndex = _currentLayout!.screens.indexWhere((s) => s.id == screenId);
    if (screenIndex < 0) return;

    final screen = _currentLayout!.screens[screenIndex];
    final updatedScreen = screen.copyWith(name: newName);
    _currentLayout = _currentLayout!.updateScreen(updatedScreen);
    notifyListeners();
    await _saveDashboard();
  }

  /// Set the active screen by index
  void setActiveScreen(int index) {
    if (_currentLayout == null) return;
    _currentLayout = _currentLayout!.setActiveScreen(index);
    notifyListeners();
  }

  /// Add a tool placement to a screen
  Future<void> addPlacement(ToolPlacement placement) async {
    if (_currentLayout == null) return;

    final screenIndex = _currentLayout!.screens.indexWhere(
      (s) => s.id == placement.screenId,
    );
    if (screenIndex < 0) return;

    final screen = _currentLayout!.screens[screenIndex];
    final updatedScreen = screen.addPlacement(placement);
    _currentLayout = _currentLayout!.updateScreen(updatedScreen);
    notifyListeners();
    await _saveDashboard();

    debugPrint('DashboardService: Added placement ${placement.toolId} to ${placement.screenId}');
  }

  /// Remove a tool placement from a screen
  Future<void> removePlacement(String screenId, String toolId) async {
    if (_currentLayout == null) return;

    final screenIndex = _currentLayout!.screens.indexWhere((s) => s.id == screenId);
    if (screenIndex < 0) return;

    final screen = _currentLayout!.screens[screenIndex];
    final updatedScreen = screen.removePlacement(toolId);
    _currentLayout = _currentLayout!.updateScreen(updatedScreen);
    notifyListeners();
    await _saveDashboard();
  }

  /// Update a tool placement on a screen
  Future<void> updatePlacement(String screenId, ToolPlacement placement) async {
    if (_currentLayout == null) return;

    final screenIndex = _currentLayout!.screens.indexWhere((s) => s.id == screenId);
    if (screenIndex < 0) return;

    final screen = _currentLayout!.screens[screenIndex];
    final updatedScreen = screen.updatePlacement(placement);
    _currentLayout = _currentLayout!.updateScreen(updatedScreen);
    notifyListeners();
    await _saveDashboard();
  }

  /// Update a screen directly
  Future<void> updateScreen(DashboardScreen screen) async {
    if (_currentLayout == null) return;

    _currentLayout = _currentLayout!.updateScreen(screen);
    notifyListeners();
    await _saveDashboard();
  }

  /// Update placement size
  Future<void> updatePlacementSize(String screenId, String toolId, int width, int height) async {
    if (_currentLayout == null) return;

    final screenIndex = _currentLayout!.screens.indexWhere((s) => s.id == screenId);
    if (screenIndex < 0) return;

    final screen = _currentLayout!.screens[screenIndex];

    // Update in both orientations
    final updatedPortraitPlacements = screen.portraitPlacements.map((p) {
      if (p.toolId == toolId) {
        return p.copyWith(position: p.position.copyWith(width: width, height: height));
      }
      return p;
    }).toList();

    final updatedLandscapePlacements = screen.landscapePlacements.map((p) {
      if (p.toolId == toolId) {
        return p.copyWith(position: p.position.copyWith(width: width, height: height));
      }
      return p;
    }).toList();

    final updatedScreen = screen.copyWith(
      portraitPlacements: updatedPortraitPlacements,
      landscapePlacements: updatedLandscapePlacements,
    );

    _currentLayout = _currentLayout!.updateScreen(updatedScreen);
    notifyListeners();
    await _saveDashboard();
  }

  /// Save dashboard (public method)
  Future<void> saveDashboard() async {
    await _saveDashboard();
  }

  /// Get placements for a specific screen (returns portrait placements for backward compatibility)
  List<ToolPlacement> getPlacementsForScreen(String screenId) {
    if (_currentLayout == null) return [];

    final screen = _currentLayout!.screens.firstWhere(
      (s) => s.id == screenId,
      orElse: () => DashboardScreen(id: '', name: ''),
    );
    return screen.portraitPlacements;
  }

  /// Create a new blank dashboard
  Future<void> createNewDashboard({String? name}) async {
    _currentLayout = DashboardLayout(
      id: 'layout_${DateTime.now().millisecondsSinceEpoch}',
      name: name ?? 'New Dashboard',
      screens: [
        DashboardScreen(
          id: 'screen_${DateTime.now().millisecondsSinceEpoch}',
          name: 'Main',
          placements: [],
          order: 0,
        ),
      ],
      activeScreenIndex: 0,
    );

    notifyListeners();
    await _saveDashboard();
  }
}
