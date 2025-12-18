/// Dashboard service for managing dashboard layouts
/// Adapted from ZedDisplay architecture

import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/dashboard_layout.dart';
import '../models/dashboard_screen.dart';
import '../models/tool_placement.dart';
import 'storage_service.dart';
import 'tool_service.dart';

/// Service for managing dashboard layouts and screens
class DashboardService extends ChangeNotifier {
  final StorageService _storageService;
  final ToolService _toolService;

  DashboardLayout? _currentLayout;
  bool _initialized = false;
  bool _editMode = false;

  static const String _layoutStorageKey = 'dashboard_layout';
  static const String _activeLayoutKey = 'active_layout_id';

  DashboardService(this._storageService, this._toolService);

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

      // If no layout, create a default one
      if (_currentLayout == null) {
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
        await _saveDashboard();
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
