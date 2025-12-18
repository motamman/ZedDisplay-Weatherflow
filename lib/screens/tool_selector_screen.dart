/// Tool Selector Screen for WeatherFlow
/// Allows users to select and add tools to the dashboard

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/tool_definition.dart';
import '../models/tool_placement.dart';
import '../models/tool_config.dart';
import '../services/tool_registry.dart';
import '../services/tool_service.dart';
import '../services/dashboard_service.dart';

/// Screen for selecting a tool type to add to the dashboard
class ToolSelectorScreen extends StatelessWidget {
  const ToolSelectorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final toolRegistry = context.watch<ToolRegistry>();
    final definitions = toolRegistry.getAllDefinitions();

    // Group by category
    final grouped = <ToolCategory, List<ToolDefinition>>{};
    for (final def in definitions) {
      grouped.putIfAbsent(def.category, () => []).add(def);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Widget'),
      ),
      body: definitions.isEmpty
          ? _buildEmpty(context)
          : ListView(
              children: [
                for (final category in ToolCategory.values)
                  if (grouped[category]?.isNotEmpty ?? false)
                    _buildCategorySection(context, category, grouped[category]!),
              ],
            ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.widgets_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'No tools available',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Register tools in the ToolRegistry',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildCategorySection(
    BuildContext context,
    ToolCategory category,
    List<ToolDefinition> definitions,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            _categoryName(category),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ...definitions.map((def) => _buildToolTile(context, def)),
      ],
    );
  }

  String _categoryName(ToolCategory category) {
    switch (category) {
      case ToolCategory.weather:
        return 'Weather';
      case ToolCategory.instruments:
        return 'Instruments';
      case ToolCategory.charts:
        return 'Charts';
      case ToolCategory.controls:
        return 'Controls';
      case ToolCategory.system:
        return 'System';
    }
  }

  IconData _categoryIcon(ToolCategory category) {
    switch (category) {
      case ToolCategory.weather:
        return Icons.cloud;
      case ToolCategory.instruments:
        return Icons.speed;
      case ToolCategory.charts:
        return Icons.show_chart;
      case ToolCategory.controls:
        return Icons.tune;
      case ToolCategory.system:
        return Icons.settings;
    }
  }

  Widget _buildToolTile(BuildContext context, ToolDefinition definition) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        child: Icon(
          _categoryIcon(definition.category),
          color: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
      ),
      title: Text(definition.name),
      subtitle: Text(
        definition.description,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        '${definition.defaultWidth}x${definition.defaultHeight}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      onTap: () => _addTool(context, definition),
    );
  }

  Future<void> _addTool(BuildContext context, ToolDefinition definition) async {
    final toolService = context.read<ToolService>();
    final dashboardService = context.read<DashboardService>();
    final toolRegistry = context.read<ToolRegistry>();

    // Get default config
    final defaultConfig = toolRegistry.getDefaultConfig(definition.id) ??
        const ToolConfig(
          dataSources: [],
          style: StyleConfig(),
        );

    // Create tool instance
    final tool = await toolService.createTool(
      name: definition.name,
      definition: definition,
      config: defaultConfig,
    );

    // Find position for new tool
    final activeScreen = dashboardService.currentLayout?.activeScreen;
    if (activeScreen == null) return;

    // Find an empty position (simple algorithm - first available row)
    int row = 0;
    int col = 0;
    final existingPlacements = activeScreen.portraitPlacements;

    // Simple grid placement - find next available slot
    if (existingPlacements.isNotEmpty) {
      // Find the max row used
      int maxRow = 0;
      for (final p in existingPlacements) {
        final endRow = p.position.row + p.position.height;
        if (endRow > maxRow) maxRow = endRow;
      }
      row = maxRow;
    }

    // Create placement
    final placement = ToolPlacement(
      toolId: tool.id,
      screenId: activeScreen.id,
      position: GridPosition(
        row: row,
        col: col,
        width: definition.defaultWidth,
        height: definition.defaultHeight,
      ),
    );

    await dashboardService.addPlacement(placement);

    if (context.mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added ${definition.name}')),
      );
    }
  }
}
