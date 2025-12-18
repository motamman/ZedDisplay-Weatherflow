/// Dashboard Screen for WeatherFlow
/// Renders tools in a grid layout with edit mode support
/// Adapted from ZedDisplay architecture with portrait/landscape layouts and resize/move

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/tool.dart';
import '../models/tool_placement.dart';
import '../models/tool_config.dart';
import '../models/dashboard_screen.dart' as model;
import '../services/weatherflow_service.dart';
import '../services/dashboard_service.dart';
import '../services/tool_service.dart';
import '../services/tool_registry.dart';
import 'station_list_screen.dart';
import 'settings_screen.dart';
import 'tool_selector_screen.dart';
import 'tool_config_screen.dart';

/// Main dashboard screen with configurable tool grid
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _isEditMode = false;
  bool _isFullScreen = false;
  bool _showAppBar = true;
  Timer? _appBarHideTimer;

  // For swipe gesture handling
  double _dragStartX = 0;
  double _dragDelta = 0;
  bool _isDragging = false;

  // Track widget being resized
  String? _resizingWidgetId;
  double _resizingWidth = 0;
  double _resizingHeight = 0;

  // Track widget being moved
  String? _movingWidgetId;
  double _movingX = 0;
  double _movingY = 0;

  // Track tool being placed (drag-to-place for new tools)
  Tool? _toolBeingPlaced;
  ToolPlacement? _placementBeingPlaced;
  double _placingX = 0;
  double _placingY = 0;
  double _placingWidth = 0;
  double _placingHeight = 0;

  @override
  void initState() {
    super.initState();

    // Initialize services
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final dashboardService = context.read<DashboardService>();
      final toolService = context.read<ToolService>();
      final weatherFlow = context.read<WeatherFlowService>();

      await dashboardService.initialize();
      await toolService.initialize();

      if (weatherFlow.currentObservation == null) {
        await weatherFlow.refresh();
      }
    });
  }

  @override
  void dispose() {
    _appBarHideTimer?.cancel();
    super.dispose();
  }

  /// Handle swipe to change screens with wrap-around
  void _onHorizontalSwipe(int direction, DashboardService dashboardService) {
    final totalScreens = dashboardService.currentLayout?.screens.length ?? 0;
    if (totalScreens <= 1) return;

    final currentIndex = dashboardService.currentLayout!.activeScreenIndex;
    int newIndex;

    if (direction > 0) {
      // Swipe left (next screen)
      newIndex = (currentIndex + 1) % totalScreens;
    } else {
      // Swipe right (previous screen)
      newIndex = (currentIndex - 1 + totalScreens) % totalScreens;
    }

    dashboardService.setActiveScreen(newIndex);
    _showAppBarTemporarily();
  }

  void _startAppBarHideTimer() {
    _appBarHideTimer?.cancel();
    if (_isFullScreen) {
      _appBarHideTimer = Timer(const Duration(seconds: 5), () {
        if (mounted && _isFullScreen) {
          setState(() => _showAppBar = false);
        }
      });
    }
  }

  void _showAppBarTemporarily() {
    if (_isFullScreen) {
      setState(() => _showAppBar = true);
      _startAppBarHideTimer();
    }
  }

  void _toggleFullScreen() {
    setState(() {
      _isFullScreen = !_isFullScreen;
      if (_isFullScreen) {
        SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.immersiveSticky,
          overlays: [],
        );
        _showAppBar = true;
        _startAppBarHideTimer();
      } else {
        SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.manual,
          overlays: SystemUiOverlay.values,
        );
        _appBarHideTimer?.cancel();
        _showAppBar = true;
      }
    });
  }

  Future<void> _addTool(BuildContext context) async {
    if (_toolBeingPlaced != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please place the current tool first!'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final dashboardService = context.read<DashboardService>();
    final activeScreen = dashboardService.currentLayout?.activeScreen;

    if (activeScreen == null) return;

    final result = await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ToolSelectorScreen()),
    );

    if (result is Map<String, dynamic> && mounted) {
      final tool = result['tool'] as Tool;
      final width = result['width'] as int? ?? 2;
      final height = result['height'] as int? ?? 2;

      final placement = ToolPlacement(
        toolId: tool.id,
        screenId: activeScreen.id,
        position: GridPosition(row: 0, col: 0, width: width, height: height),
      );

      setState(() {
        _toolBeingPlaced = tool;
        _placementBeingPlaced = placement;
        _placingX = 0;
        _placingY = 0;
        _placingWidth = width * 100.0;
        _placingHeight = height * 100.0;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Drag to position - Drag corner to resize - Release to place'),
          backgroundColor: Colors.blue,
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  void _removePlacement(String screenId, String toolId) async {
    final dashboardService = context.read<DashboardService>();
    await dashboardService.removePlacement(screenId, toolId);
  }

  void _confirmRemovePlacement(String screenId, String toolId, String toolName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Tool'),
        content: Text('Are you sure you want to remove "$toolName"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _removePlacement(screenId, toolId);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  void _showScreenSelector(BuildContext context) {
    final dashboardService = context.read<DashboardService>();
    final layout = dashboardService.currentLayout;

    if (layout == null) return;

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Select Screen',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: layout.screens.length,
                itemBuilder: (context, index) {
                  final screen = layout.screens[index];
                  final isActive = index == layout.activeScreenIndex;

                  return ListTile(
                    leading: Icon(
                      Icons.dashboard,
                      color: isActive ? Theme.of(context).colorScheme.primary : null,
                    ),
                    title: Text(
                      screen.name,
                      style: TextStyle(
                        fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                        color: isActive ? Theme.of(context).colorScheme.primary : null,
                      ),
                    ),
                    trailing: isActive ? const Icon(Icons.check, color: Colors.green) : null,
                    onTap: () {
                      Navigator.pop(context);
                      dashboardService.setActiveScreen(index);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showScreenManagementMenu() {
    final dashboardService = context.read<DashboardService>();

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Add Screen'),
              onTap: () async {
                Navigator.pop(context);
                _showAddScreenDialog();
              },
            ),
            if (dashboardService.currentLayout!.screens.length > 1)
              ListTile(
                leading: const Icon(Icons.delete),
                title: const Text('Remove Current Screen'),
                onTap: () async {
                  Navigator.pop(context);
                  final activeScreen = dashboardService.currentLayout!.activeScreen;
                  if (activeScreen != null) {
                    _confirmRemoveScreen(activeScreen.id, activeScreen.name);
                  }
                },
              ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Rename Current Screen'),
              onTap: () async {
                Navigator.pop(context);
                final activeScreen = dashboardService.currentLayout!.activeScreen;
                if (activeScreen != null) {
                  _showRenameDialog(activeScreen.id, activeScreen.name);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showAddScreenDialog() async {
    final nameController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Screen'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Screen Name',
            hintText: 'e.g., Forecast, Details, Charts',
          ),
          autofocus: true,
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(context, name);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (result != null && mounted) {
      final dashboardService = context.read<DashboardService>();
      await dashboardService.addScreen(name: result);

      // Jump to new screen
      final newIndex = dashboardService.currentLayout!.screens.length - 1;
      dashboardService.setActiveScreen(newIndex);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added screen "$result"')),
      );
    }
  }

  void _confirmRemoveScreen(String screenId, String screenName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Screen'),
        content: Text('Are you sure you want to remove "$screenName"?\nAll tools on this screen will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final dashboardService = context.read<DashboardService>();
              await dashboardService.removeScreen(screenId);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  Future<void> _configureTool(Tool tool, int currentWidth, int currentHeight) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ToolConfigScreen(
          tool: tool,
          currentWidth: currentWidth,
          currentHeight: currentHeight,
        ),
      ),
    );

    // If tool was updated, refresh
    if (result is Map<String, dynamic> && mounted) {
      setState(() {});
    }
  }

  void _showRenameDialog(String screenId, String currentName) {
    final controller = TextEditingController(text: currentName);
    final dashboardService = context.read<DashboardService>();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Screen'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Screen Name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                await dashboardService.renameScreen(screenId, newName);
                if (context.mounted) {
                  Navigator.pop(context);
                }
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final weatherFlow = context.watch<WeatherFlowService>();
    final dashboardService = context.watch<DashboardService>();
    final station = weatherFlow.selectedStation;
    final layout = dashboardService.currentLayout;

    return Scaffold(
      extendBody: _isFullScreen,
      extendBodyBehindAppBar: _isFullScreen,
      floatingActionButton: (_isFullScreen && !_showAppBar && _toolBeingPlaced == null)
          ? FloatingActionButton.small(
              onPressed: _showAppBarTemporarily,
              backgroundColor: Colors.black.withValues(alpha: 0.6),
              child: const Icon(Icons.arrow_upward, color: Colors.white),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endTop,
      appBar: (!_isFullScreen || _showAppBar || _toolBeingPlaced != null) ? AppBar(
        title: Text(station?.name ?? 'WeatherFlow'),
        actions: [
          // Add tool button
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _addTool(context),
            tooltip: 'Add Tool',
          ),
          // Edit mode toggle
          IconButton(
            icon: Icon(_isEditMode ? Icons.done : Icons.edit),
            onPressed: () => setState(() => _isEditMode = !_isEditMode),
            tooltip: _isEditMode ? 'Exit Edit Mode' : 'Edit Mode',
          ),
          // Screen management
          IconButton(
            icon: const Icon(Icons.view_carousel),
            onPressed: _showScreenManagementMenu,
            tooltip: 'Manage Screens',
          ),
          // Refresh
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: weatherFlow.isLoading ? null : () => weatherFlow.refresh(),
            tooltip: 'Refresh',
          ),
          // Fullscreen toggle
          IconButton(
            icon: Icon(_isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen),
            onPressed: _toggleFullScreen,
            tooltip: _isFullScreen ? 'Exit Full Screen' : 'Enter Full Screen',
          ),
          // Station switcher
          IconButton(
            icon: const Icon(Icons.swap_horiz),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const StationListScreen()),
            ),
            tooltip: 'Change Station',
          ),
          // Settings
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
            tooltip: 'Settings',
          ),
        ],
      ) : null,
      body: SafeArea(
        top: !_isFullScreen,
        bottom: !_isFullScreen,
        left: !_isFullScreen,
        right: !_isFullScreen,
        child: layout == null || layout.screens.isEmpty
            ? _buildEmptyState(dashboardService)
            : _buildDashboard(layout, dashboardService, weatherFlow),
      ),
    );
  }

  Widget _buildEmptyState(DashboardService dashboardService) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.dashboard,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'No dashboard configured',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => dashboardService.createNewDashboard(),
            icon: const Icon(Icons.add),
            label: const Text('Create Dashboard'),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboard(dynamic layout, DashboardService dashboardService, WeatherFlowService weatherFlow) {
    // Handle empty screens case
    if (layout.screens.isEmpty) {
      return const Center(
        child: Text('No screens available'),
      );
    }

    // Safely clamp activeScreenIndex to valid range
    final safeIndex = layout.activeScreenIndex.clamp(0, layout.screens.length - 1);

    return Stack(
      children: [
        // Swipe gesture detector + IndexedStack for screens
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: (_isEditMode || _toolBeingPlaced != null) ? null : (details) {
            _dragStartX = details.localPosition.dx;
            _dragDelta = 0;
            _isDragging = true;
          },
          onHorizontalDragUpdate: (_isEditMode || _toolBeingPlaced != null) ? null : (details) {
            _dragDelta = details.localPosition.dx - _dragStartX;
          },
          onHorizontalDragEnd: (_isEditMode || _toolBeingPlaced != null) ? null : (details) {
            if (_isDragging && _dragDelta.abs() > 50) {
              _onHorizontalSwipe(_dragDelta < 0 ? 1 : -1, dashboardService);
            }
            _isDragging = false;
            _dragDelta = 0;
          },
          child: IndexedStack(
            index: safeIndex,
            children: layout.screens.map<Widget>((screen) {
              return _buildScreenContent(screen, dashboardService, weatherFlow);
            }).toList(),
          ),
        ),

        // Screen selector button at bottom (only if multiple screens)
        if (layout.screens.length > 1)
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Center(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _showScreenSelector(context),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.dashboard,
                          color: Colors.white,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          layout.activeScreen?.name ?? 'Dashboard',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.arrow_drop_up,
                          color: Colors.white,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildScreenContent(model.DashboardScreen screen, DashboardService dashboardService, WeatherFlowService weatherFlow) {
    final toolService = context.watch<ToolService>();
    final toolRegistry = ToolRegistry();
    final orientation = MediaQuery.of(context).orientation;

    // Use orientation-specific placements
    final placements = orientation == Orientation.portrait
        ? screen.portraitPlacements
        : screen.landscapePlacements;

    // Empty screen content
    Widget emptyScreenWidget = Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.dashboard_customize, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No tools on "${screen.name}"',
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: () => _addTool(context),
            icon: const Icon(Icons.add),
            label: const Text('Add Your First Tool'),
          ),
        ],
      ),
    );

    if (placements.isEmpty && _toolBeingPlaced == null) {
      return emptyScreenWidget;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final screenHeight = constraints.maxHeight;
        final cellWidth = screenWidth / 8;
        final cellHeight = screenHeight / 8;

        // Get station ID for effective config lookup
        final stationId = weatherFlow.selectedStation?.stationId;

        Widget contentWidget = placements.isEmpty
            ? emptyScreenWidget
            : Stack(
          children: placements.map((placement) {
            final tool = toolService.getTool(placement.toolId);
            if (tool == null) return const SizedBox.shrink();

            // Get effective config with station-specific device sources
            final effectiveConfig = toolService.getEffectiveConfig(tool.id, stationId) ?? tool.config;

            // Calculate position
            final isBeingMoved = _movingWidgetId == placement.toolId;
            final x = isBeingMoved ? _movingX : placement.position.col * cellWidth;
            final y = isBeingMoved ? _movingY : placement.position.row * cellHeight;

            // Calculate size
            final isBeingResized = _resizingWidgetId == placement.toolId;
            final width = isBeingResized ? _resizingWidth : placement.position.width * cellWidth;
            final height = isBeingResized ? _resizingHeight : placement.position.height * cellHeight;

            Widget widgetContent;

            if (_isEditMode) {
              // Edit mode with controls
              widgetContent = Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Tool widget
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: toolRegistry.buildTool(tool.toolTypeId, effectiveConfig, weatherFlow, isEditMode: true, name: tool.name),
                    ),

                    // Drag-to-move handle at top-left
                    Positioned(
                      top: 4,
                      left: 4,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (details) {
                          setState(() {
                            _movingWidgetId = placement.toolId;
                            _movingX = x;
                            _movingY = y;
                          });
                        },
                        onPanUpdate: (details) {
                          setState(() {
                            _movingX = (_movingX + details.delta.dx).clamp(0, screenWidth - width);
                            _movingY = (_movingY + details.delta.dy).clamp(0, screenHeight - height);
                          });
                        },
                        onPanEnd: (details) {
                          final updatedPlacement = placement.copyWith(
                            position: placement.position.copyWith(
                              col: (_movingX / cellWidth).round(),
                              row: (_movingY / cellHeight).round(),
                            ),
                          );

                          final isPortrait = orientation == Orientation.portrait;
                          final updatedScreen = isPortrait
                              ? screen.copyWith(
                                  portraitPlacements: screen.portraitPlacements
                                      .map((p) => p.toolId == updatedPlacement.toolId ? updatedPlacement : p)
                                      .toList(),
                                )
                              : screen.copyWith(
                                  landscapePlacements: screen.landscapePlacements
                                      .map((p) => p.toolId == updatedPlacement.toolId ? updatedPlacement : p)
                                      .toList(),
                                );

                          dashboardService.updateScreen(updatedScreen);
                          setState(() => _movingWidgetId = null);
                        },
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Colors.purple.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(Icons.open_with, size: 20, color: Colors.white),
                        ),
                      ),
                    ),

                    // Configure button at top-right
                    Positioned(
                      top: 4,
                      right: 4,
                      child: IconButton(
                        icon: const Icon(Icons.settings, size: 16),
                        onPressed: () => _configureTool(tool, placement.position.width, placement.position.height),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.green.withValues(alpha: 0.7),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.all(4),
                          minimumSize: const Size(24, 24),
                        ),
                        tooltip: 'Configure',
                      ),
                    ),

                    // Delete button at bottom-left
                    Positioned(
                      bottom: 4,
                      left: 4,
                      child: IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () => _confirmRemovePlacement(screen.id, placement.toolId, tool.name),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.red.withValues(alpha: 0.7),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.all(4),
                          minimumSize: const Size(24, 24),
                        ),
                        tooltip: 'Remove',
                      ),
                    ),

                    // Resize handle at bottom-right
                    Positioned(
                      bottom: -4,
                      right: -4,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (details) {
                          setState(() {
                            _resizingWidgetId = placement.toolId;
                            _resizingWidth = width;
                            _resizingHeight = height;
                          });
                        },
                        onPanUpdate: (details) {
                          setState(() {
                            _resizingWidth = (_resizingWidth + details.delta.dx).clamp(100.0, screenWidth - x);
                            _resizingHeight = (_resizingHeight + details.delta.dy).clamp(100.0, screenHeight - y);
                          });
                        },
                        onPanEnd: (details) {
                          final updatedPlacement = placement.copyWith(
                            position: placement.position.copyWith(
                              width: (_resizingWidth / cellWidth).round().clamp(1, 8),
                              height: (_resizingHeight / cellHeight).round().clamp(1, 8),
                            ),
                          );

                          final isPortrait = orientation == Orientation.portrait;
                          final updatedScreen = isPortrait
                              ? screen.copyWith(
                                  portraitPlacements: screen.portraitPlacements
                                      .map((p) => p.toolId == updatedPlacement.toolId ? updatedPlacement : p)
                                      .toList(),
                                )
                              : screen.copyWith(
                                  landscapePlacements: screen.landscapePlacements
                                      .map((p) => p.toolId == updatedPlacement.toolId ? updatedPlacement : p)
                                      .toList(),
                                );

                          dashboardService.updateScreen(updatedScreen);
                          setState(() => _resizingWidgetId = null);
                        },
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.8),
                            borderRadius: const BorderRadius.only(topLeft: Radius.circular(8)),
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(Icons.zoom_out_map, size: 24, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            } else {
              // Normal mode
              widgetContent = Padding(
                padding: const EdgeInsets.all(8),
                child: toolRegistry.buildTool(tool.toolTypeId, effectiveConfig, weatherFlow, name: tool.name),
              );
            }

            return Positioned(
              key: ValueKey('tool_${placement.toolId}_${orientation.name}'),
              left: x,
              top: y,
              width: width,
              height: height,
              child: widgetContent,
            );
          }).toList(),
        );

        // Add overlay for tool being placed
        if (_toolBeingPlaced != null && _placementBeingPlaced != null) {
          contentWidget = Stack(
            children: [
              contentWidget,
              Positioned(
                left: _placingX,
                top: _placingY,
                width: _placingWidth,
                height: _placingHeight,
                child: GestureDetector(
                  onPanUpdate: (details) {
                    setState(() {
                      final maxX = (screenWidth - _placingWidth).clamp(0.0, double.infinity);
                      final maxY = (screenHeight - _placingHeight).clamp(0.0, double.infinity);
                      _placingX = (_placingX + details.delta.dx).clamp(0, maxX);
                      _placingY = (_placingY + details.delta.dy).clamp(0, maxY);
                    });
                  },
                  onPanEnd: (details) async {
                    final messenger = ScaffoldMessenger.of(context);

                    final updatedPlacement = _placementBeingPlaced!.copyWith(
                      position: _placementBeingPlaced!.position.copyWith(
                        col: (_placingX / cellWidth).round(),
                        row: (_placingY / cellHeight).round(),
                        width: (_placingWidth / cellWidth).round().clamp(1, 8),
                        height: (_placingHeight / cellHeight).round().clamp(1, 8),
                      ),
                    );

                    final updatedScreen = screen.addPlacement(updatedPlacement);
                    await dashboardService.updateScreen(updatedScreen);

                    final toolName = _toolBeingPlaced!.name;
                    setState(() {
                      _toolBeingPlaced = null;
                      _placementBeingPlaced = null;
                    });

                    if (mounted) {
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text('Tool "$toolName" placed'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  },
                  child: Opacity(
                    opacity: 0.7,
                    child: Stack(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.yellow, width: 6),
                            borderRadius: BorderRadius.circular(12),
                            color: Colors.yellow.withValues(alpha: 0.5),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.5),
                                blurRadius: 20,
                                spreadRadius: 5,
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(16),
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.pan_tool, size: 64, color: Colors.orange[900]),
                                const SizedBox(height: 16),
                                Text(
                                  _toolBeingPlaced!.name,
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 24,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'DRAG ME TO POSITION',
                                  style: TextStyle(
                                    color: Colors.red[900],
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Drag corner to resize • Release to place',
                                  style: TextStyle(color: Colors.black87, fontSize: 14),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Resize handle for placement
                        Positioned(
                          bottom: -4,
                          right: -4,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onPanUpdate: (details) {
                              setState(() {
                                _placingWidth = (_placingWidth + details.delta.dx).clamp(100.0, screenWidth - _placingX);
                                _placingHeight = (_placingHeight + details.delta.dy).clamp(100.0, screenHeight - _placingY);
                              });
                            },
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.8),
                                borderRadius: const BorderRadius.only(topLeft: Radius.circular(8)),
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                              child: const Icon(Icons.zoom_out_map, size: 24, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        }

        return contentWidget;
      },
    );
  }
}
