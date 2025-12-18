/// Dashboard layout model for WeatherFlow dashboard
/// Adapted from ZedDisplay architecture

import 'dashboard_screen.dart';

/// Complete dashboard layout with multiple screens
class DashboardLayout {
  final String id;              // Unique layout ID
  final String name;            // Display name (e.g., "Default", "Compact", "Detailed")
  final List<DashboardScreen> screens;
  final int activeScreenIndex;  // Currently active screen (0-based)

  const DashboardLayout({
    required this.id,
    required this.name,
    required this.screens,
    this.activeScreenIndex = 0,
  });

  factory DashboardLayout.fromJson(Map<String, dynamic> json) {
    return DashboardLayout(
      id: json['id'] as String,
      name: json['name'] as String,
      screens: (json['screens'] as List<dynamic>?)
          ?.map((e) => DashboardScreen.fromJson(e as Map<String, dynamic>))
          .toList() ?? const [],
      activeScreenIndex: json['activeScreenIndex'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'screens': screens.map((s) => s.toJson()).toList(),
    'activeScreenIndex': activeScreenIndex,
  };

  /// Create a copy with modified fields
  DashboardLayout copyWith({
    String? id,
    String? name,
    List<DashboardScreen>? screens,
    int? activeScreenIndex,
  }) {
    return DashboardLayout(
      id: id ?? this.id,
      name: name ?? this.name,
      screens: screens ?? this.screens,
      activeScreenIndex: activeScreenIndex ?? this.activeScreenIndex,
    );
  }

  /// Get the currently active screen
  DashboardScreen? get activeScreen {
    if (activeScreenIndex >= 0 && activeScreenIndex < screens.length) {
      return screens[activeScreenIndex];
    }
    return null;
  }

  /// Add a screen to this layout
  DashboardLayout addScreen(DashboardScreen screen) {
    return copyWith(screens: [...screens, screen]);
  }

  /// Remove a screen from this layout
  DashboardLayout removeScreen(String screenId) {
    return copyWith(
      screens: screens.where((s) => s.id != screenId).toList(),
    );
  }

  /// Update a screen in this layout
  DashboardLayout updateScreen(DashboardScreen updatedScreen) {
    return copyWith(
      screens: screens.map((s) =>
        s.id == updatedScreen.id ? updatedScreen : s
      ).toList(),
    );
  }

  /// Set the active screen by index
  DashboardLayout setActiveScreen(int index) {
    if (index >= 0 && index < screens.length) {
      return copyWith(activeScreenIndex: index);
    }
    return this;
  }

  /// Set the active screen by ID
  DashboardLayout setActiveScreenById(String screenId) {
    final index = screens.indexWhere((s) => s.id == screenId);
    if (index >= 0) {
      return copyWith(activeScreenIndex: index);
    }
    return this;
  }

  /// Get all unique tool IDs referenced across all screens
  List<String> getAllToolIds() {
    final toolIds = <String>{};
    for (final screen in screens) {
      toolIds.addAll(screen.getToolIds());
    }
    return toolIds.toList();
  }
}
