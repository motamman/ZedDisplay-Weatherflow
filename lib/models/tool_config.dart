/// Tool configuration models for WeatherFlow tools
/// Adapted from ZedDisplay architecture

/// Data source configuration for a tool
/// For WeatherFlow, this represents which observation field to display
class DataSource {
  final String path;            // e.g., "temperature", "windAvg", "pressure"
  final String? label;          // Display label override
  final String? color;          // For multi-path tools (hex color string)

  const DataSource({
    required this.path,
    this.label,
    this.color,
  });

  factory DataSource.fromJson(Map<String, dynamic> json) {
    return DataSource(
      path: json['path'] as String,
      label: json['label'] as String?,
      color: json['color'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'path': path,
    if (label != null) 'label': label,
    if (color != null) 'color': color,
  };

  DataSource copyWith({
    String? path,
    String? label,
    String? color,
  }) {
    return DataSource(
      path: path ?? this.path,
      label: label ?? this.label,
      color: color ?? this.color,
    );
  }
}

/// Style configuration for a tool
class StyleConfig {
  final double? minValue;
  final double? maxValue;
  final String? unit;            // Unit override
  final String? primaryColor;    // Hex color string (e.g., "#0000FF")
  final String? secondaryColor;
  final double? fontSize;
  final double? strokeWidth;
  final bool showLabel;
  final bool showValue;
  final bool showUnit;

  // Additional style properties for specific tools
  final Map<String, dynamic>? customProperties;

  const StyleConfig({
    this.minValue,
    this.maxValue,
    this.unit,
    this.primaryColor,
    this.secondaryColor,
    this.fontSize,
    this.strokeWidth,
    this.showLabel = true,
    this.showValue = true,
    this.showUnit = true,
    this.customProperties,
  });

  factory StyleConfig.fromJson(Map<String, dynamic> json) {
    return StyleConfig(
      minValue: (json['minValue'] as num?)?.toDouble(),
      maxValue: (json['maxValue'] as num?)?.toDouble(),
      unit: json['unit'] as String?,
      primaryColor: json['primaryColor'] as String?,
      secondaryColor: json['secondaryColor'] as String?,
      fontSize: (json['fontSize'] as num?)?.toDouble(),
      strokeWidth: (json['strokeWidth'] as num?)?.toDouble(),
      showLabel: json['showLabel'] as bool? ?? true,
      showValue: json['showValue'] as bool? ?? true,
      showUnit: json['showUnit'] as bool? ?? true,
      customProperties: json['customProperties'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() => {
    if (minValue != null) 'minValue': minValue,
    if (maxValue != null) 'maxValue': maxValue,
    if (unit != null) 'unit': unit,
    if (primaryColor != null) 'primaryColor': primaryColor,
    if (secondaryColor != null) 'secondaryColor': secondaryColor,
    if (fontSize != null) 'fontSize': fontSize,
    if (strokeWidth != null) 'strokeWidth': strokeWidth,
    'showLabel': showLabel,
    'showValue': showValue,
    'showUnit': showUnit,
    if (customProperties != null) 'customProperties': customProperties,
  };

  StyleConfig copyWith({
    double? minValue,
    double? maxValue,
    String? unit,
    String? primaryColor,
    String? secondaryColor,
    double? fontSize,
    double? strokeWidth,
    bool? showLabel,
    bool? showValue,
    bool? showUnit,
    Map<String, dynamic>? customProperties,
  }) {
    return StyleConfig(
      minValue: minValue ?? this.minValue,
      maxValue: maxValue ?? this.maxValue,
      unit: unit ?? this.unit,
      primaryColor: primaryColor ?? this.primaryColor,
      secondaryColor: secondaryColor ?? this.secondaryColor,
      fontSize: fontSize ?? this.fontSize,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      showLabel: showLabel ?? this.showLabel,
      showValue: showValue ?? this.showValue,
      showUnit: showUnit ?? this.showUnit,
      customProperties: customProperties ?? this.customProperties,
    );
  }
}

/// Grid position for layout
class GridPosition {
  final int row;
  final int col;
  final int width;   // Columns to span
  final int height;  // Rows to span

  const GridPosition({
    required this.row,
    required this.col,
    this.width = 1,
    this.height = 1,
  });

  factory GridPosition.fromJson(Map<String, dynamic> json) {
    return GridPosition(
      row: json['row'] as int,
      col: json['col'] as int,
      width: json['width'] as int? ?? 1,
      height: json['height'] as int? ?? 1,
    );
  }

  Map<String, dynamic> toJson() => {
    'row': row,
    'col': col,
    'width': width,
    'height': height,
  };

  GridPosition copyWith({
    int? row,
    int? col,
    int? width,
    int? height,
  }) {
    return GridPosition(
      row: row ?? this.row,
      col: col ?? this.col,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }
}

/// Configuration for a tool instance
class ToolConfig {
  final List<DataSource> dataSources;
  final StyleConfig style;

  const ToolConfig({
    required this.dataSources,
    required this.style,
  });

  factory ToolConfig.fromJson(Map<String, dynamic> json) {
    return ToolConfig(
      dataSources: (json['dataSources'] as List<dynamic>?)
          ?.map((e) => DataSource.fromJson(e as Map<String, dynamic>))
          .toList() ?? const [],
      style: StyleConfig.fromJson(json['style'] as Map<String, dynamic>? ?? {}),
    );
  }

  Map<String, dynamic> toJson() => {
    'dataSources': dataSources.map((e) => e.toJson()).toList(),
    'style': style.toJson(),
  };

  ToolConfig copyWith({
    List<DataSource>? dataSources,
    StyleConfig? style,
  }) {
    return ToolConfig(
      dataSources: dataSources ?? this.dataSources,
      style: style ?? this.style,
    );
  }

  /// Get the first data source path (convenience)
  String? get primaryPath => dataSources.isNotEmpty ? dataSources.first.path : null;
}
