/// Tool placement model for WeatherFlow dashboard
/// Adapted from ZedDisplay architecture

import 'tool_config.dart';

/// A lightweight reference to a tool placed on a dashboard screen
/// This separates the reusable tool from where it's positioned
class ToolPlacement {
  final String toolId;          // References Tool.id
  final String screenId;        // Which screen it's on
  final GridPosition position;  // Where on screen

  const ToolPlacement({
    required this.toolId,
    required this.screenId,
    required this.position,
  });

  factory ToolPlacement.fromJson(Map<String, dynamic> json) {
    return ToolPlacement(
      toolId: json['toolId'] as String,
      screenId: json['screenId'] as String,
      position: GridPosition.fromJson(json['position'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() => {
    'toolId': toolId,
    'screenId': screenId,
    'position': position.toJson(),
  };

  /// Create a copy with modified fields
  ToolPlacement copyWith({
    String? toolId,
    String? screenId,
    GridPosition? position,
  }) {
    return ToolPlacement(
      toolId: toolId ?? this.toolId,
      screenId: screenId ?? this.screenId,
      position: position ?? this.position,
    );
  }
}
