/// Tool instance model for WeatherFlow tools
/// Adapted from ZedDisplay architecture

import 'tool_config.dart';
import 'tool_definition.dart';

/// A reusable tool with configuration and metadata
/// Every tool can be placed on dashboards and configured
class Tool {
  final String id;              // Unique tool ID (UUID)
  final String name;            // Display name
  final String description;     // Detailed description
  final DateTime createdAt;     // Creation timestamp
  final DateTime? updatedAt;    // Last update timestamp

  // Tool configuration
  final String toolTypeId;      // Which tool type this is (e.g., "current_conditions")
  final ToolConfig config;      // Configuration (data sources, style, etc.)

  // Default sizing
  final int defaultWidth;       // Default width when placed (grid units)
  final int defaultHeight;      // Default height when placed (grid units)

  // Organization & discovery
  final ToolCategory category;
  final List<String> tags;      // Searchable tags

  const Tool({
    required this.id,
    required this.name,
    required this.description,
    required this.createdAt,
    this.updatedAt,
    required this.toolTypeId,
    required this.config,
    this.defaultWidth = 2,
    this.defaultHeight = 2,
    this.category = ToolCategory.weather,
    this.tags = const [],
  });

  factory Tool.fromJson(Map<String, dynamic> json) {
    return Tool(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : null,
      toolTypeId: json['toolTypeId'] as String,
      config: ToolConfig.fromJson(json['config'] as Map<String, dynamic>),
      defaultWidth: json['defaultWidth'] as int? ?? 2,
      defaultHeight: json['defaultHeight'] as int? ?? 2,
      category: ToolCategory.values.firstWhere(
        (e) => e.name == json['category'],
        orElse: () => ToolCategory.weather,
      ),
      tags: (json['tags'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ?? const [],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'createdAt': createdAt.toIso8601String(),
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    'toolTypeId': toolTypeId,
    'config': config.toJson(),
    'defaultWidth': defaultWidth,
    'defaultHeight': defaultHeight,
    'category': category.name,
    'tags': tags,
  };

  /// Create a copy with modified fields
  Tool copyWith({
    String? id,
    String? name,
    String? description,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? toolTypeId,
    ToolConfig? config,
    int? defaultWidth,
    int? defaultHeight,
    ToolCategory? category,
    List<String>? tags,
  }) {
    return Tool(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      toolTypeId: toolTypeId ?? this.toolTypeId,
      config: config ?? this.config,
      defaultWidth: defaultWidth ?? this.defaultWidth,
      defaultHeight: defaultHeight ?? this.defaultHeight,
      category: category ?? this.category,
      tags: tags ?? this.tags,
    );
  }
}
