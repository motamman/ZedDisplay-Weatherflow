/// Tool service for managing tool instances
/// Adapted from ZedDisplay architecture

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/tool.dart';
import '../models/tool_config.dart';
import '../models/tool_definition.dart';
import 'storage_service.dart';

/// Service for managing tool instances
class ToolService extends ChangeNotifier {
  final StorageService _storageService;
  final Map<String, Tool> _tools = {};
  bool _initialized = false;

  static const String _storageKey = 'tools';

  ToolService(this._storageService);

  bool get initialized => _initialized;
  List<Tool> get tools => _tools.values.toList();
  int get count => _tools.length;

  /// Initialize and load tools from storage
  Future<void> initialize() async {
    if (_initialized) return;

    await _loadTools();
    _initialized = true;
    notifyListeners();

    debugPrint('ToolService: Initialized with ${_tools.length} tools');
  }

  Future<void> _loadTools() async {
    try {
      final toolsJson = await _storageService.getString(_storageKey);
      if (toolsJson != null) {
        final toolsList = jsonDecode(toolsJson) as List<dynamic>;
        for (final toolJson in toolsList) {
          final tool = Tool.fromJson(toolJson as Map<String, dynamic>);
          _tools[tool.id] = tool;
        }
      }
    } catch (e) {
      debugPrint('ToolService: Error loading tools: $e');
    }
  }

  Future<void> _saveTools() async {
    try {
      final toolsList = _tools.values.map((t) => t.toJson()).toList();
      await _storageService.setString(_storageKey, jsonEncode(toolsList));
    } catch (e) {
      debugPrint('ToolService: Error saving tools: $e');
    }
  }

  /// Get a tool by ID
  Tool? getTool(String toolId) {
    return _tools[toolId];
  }

  /// Get effective config for a tool, merging base config with station-specific overrides
  ///
  /// This resolves the issue where device serial numbers in customProperties
  /// are station-specific but tools are stored globally.
  ///
  /// [toolId] - The tool ID to get config for
  /// [stationId] - Optional station ID; if null, returns base config
  ///
  /// Returns the tool's config with station-specific customProperties merged in
  ToolConfig? getEffectiveConfig(String toolId, int? stationId) {
    final tool = getTool(toolId);
    if (tool == null) return null;

    // If no station specified, return base config
    if (stationId == null) return tool.config;

    // Check for station-specific overrides
    final stationOverrides = _storageService.getToolConfigForStation(stationId, toolId);
    if (stationOverrides == null || stationOverrides.isEmpty) {
      // No station override - return base config with device sources reset to 'auto'
      // This ensures we don't use another station's device serial numbers
      final baseCustomProps = tool.config.style.customProperties ?? {};
      final resetProps = Map<String, dynamic>.from(baseCustomProps);

      // Reset device source properties to 'auto'
      const deviceSourceKeys = [
        'tempSource', 'humiditySource', 'pressureSource',
        'windSource', 'lightSource', 'rainSource', 'lightningSource'
      ];
      for (final key in deviceSourceKeys) {
        if (resetProps.containsKey(key)) {
          resetProps[key] = 'auto';
        }
      }

      return tool.config.copyWith(
        style: tool.config.style.copyWith(customProperties: resetProps),
      );
    }

    // Merge base config with station-specific overrides
    final baseCustomProps = tool.config.style.customProperties ?? {};
    final mergedProps = <String, dynamic>{
      ...baseCustomProps,
      ...stationOverrides,
    };

    return tool.config.copyWith(
      style: tool.config.style.copyWith(customProperties: mergedProps),
    );
  }

  /// Create a new tool from a definition
  Future<Tool> createTool({
    required String name,
    required ToolDefinition definition,
    required ToolConfig config,
    String? description,
    List<String> tags = const [],
  }) async {
    final tool = Tool(
      id: const Uuid().v4(),
      name: name,
      description: description ?? definition.description,
      createdAt: DateTime.now(),
      toolTypeId: definition.id,
      config: config,
      defaultWidth: definition.defaultWidth,
      defaultHeight: definition.defaultHeight,
      category: definition.category,
      tags: tags,
    );

    _tools[tool.id] = tool;
    await _saveTools();
    notifyListeners();

    debugPrint('ToolService: Created tool ${tool.id} (${tool.name})');
    return tool;
  }

  /// Update an existing tool
  Future<void> updateTool(Tool tool) async {
    final updated = tool.copyWith(updatedAt: DateTime.now());
    _tools[tool.id] = updated;
    await _saveTools();
    notifyListeners();
  }

  /// Delete a tool
  Future<void> deleteTool(String toolId) async {
    _tools.remove(toolId);
    await _saveTools();
    notifyListeners();
  }

  /// Get tools by category
  List<Tool> getToolsByCategory(ToolCategory category) {
    return _tools.values.where((t) => t.category == category).toList();
  }

  /// Get tools by type ID
  List<Tool> getToolsByType(String toolTypeId) {
    return _tools.values.where((t) => t.toolTypeId == toolTypeId).toList();
  }

  /// Search tools by name or tags
  List<Tool> searchTools(String query) {
    final lowerQuery = query.toLowerCase();
    return _tools.values.where((t) =>
      t.name.toLowerCase().contains(lowerQuery) ||
      t.tags.any((tag) => tag.toLowerCase().contains(lowerQuery))
    ).toList();
  }

  /// Check if a tool exists
  bool hasTool(String toolId) {
    return _tools.containsKey(toolId);
  }

  /// Clear all tools
  Future<void> clearAll() async {
    _tools.clear();
    await _saveTools();
    notifyListeners();
  }
}
