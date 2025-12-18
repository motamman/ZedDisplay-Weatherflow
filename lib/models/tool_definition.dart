/// Tool type definitions for WeatherFlow tools
/// Adapted from ZedDisplay architecture

/// Categories for tool types
enum ToolCategory {
  weather,       // Weather displays: conditions, forecast, spinner
  instruments,   // Data display: gauges, text
  charts,        // Time-series: historical, realtime
  controls,      // Interactive: switches, sliders
  system,        // Admin: settings, station info
}

/// Configuration schema defining what can be configured
class ConfigSchema {
  final bool allowsMinMax;        // Can set min/max values
  final bool allowsColorCustomization;
  final bool allowsMultiplePaths; // Can show multiple data sources
  final int minPaths;             // Minimum required paths
  final int maxPaths;             // Maximum allowed paths
  final List<String> styleOptions; // Available style properties

  const ConfigSchema({
    this.allowsMinMax = true,
    this.allowsColorCustomization = true,
    this.allowsMultiplePaths = false,
    this.minPaths = 0,
    this.maxPaths = 1,
    this.styleOptions = const [],
  });

  factory ConfigSchema.fromJson(Map<String, dynamic> json) {
    return ConfigSchema(
      allowsMinMax: json['allowsMinMax'] as bool? ?? true,
      allowsColorCustomization: json['allowsColorCustomization'] as bool? ?? true,
      allowsMultiplePaths: json['allowsMultiplePaths'] as bool? ?? false,
      minPaths: json['minPaths'] as int? ?? 0,
      maxPaths: json['maxPaths'] as int? ?? 1,
      styleOptions: (json['styleOptions'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ?? const [],
    );
  }

  Map<String, dynamic> toJson() => {
    'allowsMinMax': allowsMinMax,
    'allowsColorCustomization': allowsColorCustomization,
    'allowsMultiplePaths': allowsMultiplePaths,
    'minPaths': minPaths,
    'maxPaths': maxPaths,
    'styleOptions': styleOptions,
  };
}

/// Definition of a tool type (e.g., "current_conditions", "wind", "forecast_spinner")
class ToolDefinition {
  final String id;              // e.g., "current_conditions"
  final String name;            // e.g., "Current Conditions"
  final String description;
  final ToolCategory category;
  final ConfigSchema configSchema;
  final int defaultWidth;       // Default grid width
  final int defaultHeight;      // Default grid height

  const ToolDefinition({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.configSchema,
    this.defaultWidth = 2,
    this.defaultHeight = 2,
  });

  factory ToolDefinition.fromJson(Map<String, dynamic> json) {
    return ToolDefinition(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      category: ToolCategory.values.firstWhere(
        (e) => e.name == json['category'],
        orElse: () => ToolCategory.weather,
      ),
      configSchema: ConfigSchema.fromJson(json['configSchema'] as Map<String, dynamic>),
      defaultWidth: json['defaultWidth'] as int? ?? 2,
      defaultHeight: json['defaultHeight'] as int? ?? 2,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'category': category.name,
    'configSchema': configSchema.toJson(),
    'defaultWidth': defaultWidth,
    'defaultHeight': defaultHeight,
  };
}
