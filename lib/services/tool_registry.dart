/// Tool registry for WeatherFlow tools
/// Adapted from ZedDisplay architecture

import 'package:flutter/widgets.dart';
import '../models/tool_definition.dart';
import '../models/tool_config.dart';
import 'weatherflow_service.dart';

/// Abstract builder for tool widgets
abstract class ToolBuilder {
  /// Get the definition for this tool type
  ToolDefinition getDefinition();

  /// Build a widget instance with the given configuration
  /// [isEditMode] indicates if the dashboard is in edit mode (tool should hide its own controls)
  /// [name] is the user-configured display name for this tool instance
  /// [onConfigChanged] callback to save config changes (e.g., reordering)
  Widget build(ToolConfig config, WeatherFlowService weatherFlowService, {bool isEditMode = false, String? name, void Function(ToolConfig)? onConfigChanged});

  /// Get default config for this tool type (optional)
  ToolConfig? getDefaultConfig() => null;
}

/// Registry for all available tool types
class ToolRegistry extends ChangeNotifier {
  static final ToolRegistry _instance = ToolRegistry._internal();
  factory ToolRegistry() => _instance;
  ToolRegistry._internal();

  final Map<String, ToolBuilder> _builders = {};

  /// Register a tool builder
  void register(String toolTypeId, ToolBuilder builder) {
    _builders[toolTypeId] = builder;
    notifyListeners();
  }

  /// Build a tool widget from configuration
  /// [isEditMode] is passed to the tool widget so it can hide its own controls
  /// [name] is the user-configured display name for this tool instance
  /// [onConfigChanged] callback to save config changes
  Widget buildTool(String toolTypeId, ToolConfig config, WeatherFlowService service, {bool isEditMode = false, String? name, void Function(ToolConfig)? onConfigChanged}) {
    final builder = _builders[toolTypeId];
    if (builder == null) {
      return Center(
        child: Text(
          'Unknown tool: $toolTypeId',
          style: const TextStyle(color: Color(0xFFFF0000)),
        ),
      );
    }
    return builder.build(config, service, isEditMode: isEditMode, name: name, onConfigChanged: onConfigChanged);
  }

  /// Get definition for a tool type
  ToolDefinition? getDefinition(String toolTypeId) {
    return _builders[toolTypeId]?.getDefinition();
  }

  /// Get all registered tool types
  List<ToolDefinition> getAllDefinitions() {
    return _builders.values.map((b) => b.getDefinition()).toList();
  }

  /// Get all tool type IDs
  List<String> getAllToolTypeIds() {
    return _builders.keys.toList();
  }

  /// Check if a tool type is registered
  bool isRegistered(String toolTypeId) {
    return _builders.containsKey(toolTypeId);
  }

  /// Get default config for a tool type
  ToolConfig? getDefaultConfig(String toolTypeId) {
    return _builders[toolTypeId]?.getDefaultConfig();
  }

  /// Get definitions filtered by category
  List<ToolDefinition> getDefinitionsByCategory(ToolCategory category) {
    return _builders.values
        .map((b) => b.getDefinition())
        .where((d) => d.category == category)
        .toList();
  }

  /// Clear all registered tools (mainly for testing)
  void clear() {
    _builders.clear();
    notifyListeners();
  }

  /// Number of registered tools
  int get count => _builders.length;

  /// Register all default/built-in weather tools
  /// This is called from main.dart after tool widget imports are available
  void registerDefaults() {
    // Tools are registered by importing tool files that call register()
    // This method is a placeholder for future centralized registration
  }
}
