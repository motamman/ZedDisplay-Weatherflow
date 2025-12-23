/// Conditions Dashboard Tool
///
/// Modern grid of all current weather conditions.
/// Tapping any card opens a detail chart with history and forecast.

import 'dart:math' show pow;
import 'package:flutter/material.dart';
import 'package:weatherflow_core/weatherflow_core.dart' hide HourlyForecast, DailyForecast;
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../services/tool_registry.dart';
import '../../services/weatherflow_service.dart';
import '../../services/observation_history_service.dart';
import '../condition_card.dart';
import '../condition_detail_sheet.dart';

/// Builder for Conditions Dashboard tool
class ConditionsDashboardToolBuilder implements ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return const ToolDefinition(
      id: 'conditions_dashboard',
      name: 'Conditions Dashboard',
      description: 'All current conditions with tap-to-chart history',
      category: ToolCategory.weather,
      configSchema: ConfigSchema(
        allowsMinMax: false,
        allowsColorCustomization: true,
        allowsMultiplePaths: false,
        minPaths: 0,
        maxPaths: 0,
        styleOptions: ['layout', 'cardSize', 'showIndicators', 'columns'],
      ),
      defaultWidth: 8,
      defaultHeight: 4,
    );
  }

  @override
  Widget build(ToolConfig config, WeatherFlowService weatherFlowService,
      {bool isEditMode = false, String? name, void Function(ToolConfig)? onConfigChanged}) {
    return ConditionsDashboardTool(
      config: config,
      weatherFlowService: weatherFlowService,
      isEditMode: isEditMode,
      name: name,
      onConfigChanged: onConfigChanged,
    );
  }

  @override
  ToolConfig? getDefaultConfig() {
    return const ToolConfig(
      dataSources: [],
      style: StyleConfig(
        customProperties: {
          'layout': 'grid',
          'cardSize': 'normal',
          'showIndicators': true,
          'columns': 4,
          'showTitle': true,
          // Variables to show (all by default)
          'showTemperature': true,
          'showFeelsLike': true,
          'showHumidity': true,
          'showPressure': true,
          'showWindSpeed': true,
          'showWindGust': true,
          'showRainRate': true,
          'showRainAccumulated': true,
          'showUvIndex': true,
          'showSolarRadiation': true,
          'showPrecipType': true,
          'showLightning': true,
          'showBattery': true,
          // Card order (list of variable keys) - null means default order
          'cardOrder': null,
        },
      ),
    );
  }
}

/// Data class for card order management
class _CardDefinition {
  final String key;
  final ConditionVariable variable;
  final double? Function(Observation) getValue;
  final double? Function(Observation)? getSecondary;

  const _CardDefinition({
    required this.key,
    required this.variable,
    required this.getValue,
    this.getSecondary,
  });
}

/// Conditions Dashboard Widget
class ConditionsDashboardTool extends StatefulWidget {
  final ToolConfig config;
  final WeatherFlowService weatherFlowService;
  final bool isEditMode;
  final String? name;
  final void Function(ToolConfig)? onConfigChanged;

  const ConditionsDashboardTool({
    super.key,
    required this.config,
    required this.weatherFlowService,
    this.isEditMode = false,
    this.name,
    this.onConfigChanged,
  });

  @override
  State<ConditionsDashboardTool> createState() => _ConditionsDashboardToolState();
}

class _ConditionsDashboardToolState extends State<ConditionsDashboardTool> {
  // Local card order for reordering
  List<String> _cardOrder = [];

  // Cached observation - only updated when valid data arrives
  Observation? _cachedObservation;
  bool _wasLoading = false;

  // Default order of all card keys
  static const List<String> _defaultOrder = [
    'showTemperature',
    'showFeelsLike',
    'showHumidity',
    'showPressure',
    'showWindSpeed',
    'showWindGust',
    'showRainRate',
    'showRainAccumulated',
    'showUvIndex',
    'showSolarRadiation',
    'showPrecipType',
    'showLightning',
    'showBattery',
  ];

  @override
  void initState() {
    super.initState();
    widget.weatherFlowService.addListener(_onDataChanged);
    _initCardOrder();
    // Initialize with current data if available
    final currentObs = widget.weatherFlowService.currentObservation;
    if (currentObs != null) {
      _cachedObservation = currentObs;
    }
  }

  void _initCardOrder() {
    final props = widget.config.style.customProperties ?? {};
    final savedOrder = props['cardOrder'];
    if (savedOrder is List && savedOrder.isNotEmpty) {
      _cardOrder = List<String>.from(savedOrder);
      // Add any new cards that weren't in saved order
      for (final key in _defaultOrder) {
        if (!_cardOrder.contains(key)) {
          _cardOrder.add(key);
        }
      }
    } else {
      _cardOrder = List.from(_defaultOrder);
    }
  }

  @override
  void dispose() {
    widget.weatherFlowService.removeListener(_onDataChanged);
    super.dispose();
  }

  void _onDataChanged() {
    if (!mounted) return;

    final isLoading = widget.weatherFlowService.isLoading;
    final newObservation = widget.weatherFlowService.currentObservation;

    // Only update cached data when loading completes (transition from loading to not loading)
    // AND there's valid new data
    if (_wasLoading && !isLoading && newObservation != null) {
      _cachedObservation = newObservation;
    }
    // Also update if we get new data while not in a loading cycle (e.g., UDP updates)
    else if (!isLoading && !_wasLoading && newObservation != null) {
      // Check if observation is actually newer
      if (_cachedObservation == null ||
          newObservation.timestamp.isAfter(_cachedObservation!.timestamp)) {
        _cachedObservation = newObservation;
      }
    }

    _wasLoading = isLoading;
    setState(() {});
  }

  @override
  void didUpdateWidget(ConditionsDashboardTool oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.weatherFlowService != widget.weatherFlowService) {
      oldWidget.weatherFlowService.removeListener(_onDataChanged);
      widget.weatherFlowService.addListener(_onDataChanged);
    }
    // Re-init card order if config changed externally
    if (oldWidget.config != widget.config) {
      _initCardOrder();
    }
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final item = _cardOrder.removeAt(oldIndex);
      _cardOrder.insert(newIndex, item);
    });
    _saveCardOrder();
  }

  void _saveCardOrder() {
    if (widget.onConfigChanged == null) return;

    final newProps = Map<String, dynamic>.from(
      widget.config.style.customProperties ?? {},
    );
    newProps['cardOrder'] = _cardOrder;

    final newConfig = ToolConfig(
      dataSources: widget.config.dataSources,
      style: StyleConfig(
        customProperties: newProps,
      ),
    );
    widget.onConfigChanged!(newConfig);
  }

  void _openDetailSheet(ConditionVariable variable) {
    if (widget.isEditMode) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ConditionDetailSheet(
        variable: variable,
        weatherFlowService: widget.weatherFlowService,
      ),
    );
  }

  /// Check if data is stale (older than 5 minutes or currently loading)
  bool get _isDataStale {
    if (widget.weatherFlowService.isLoading) return true;
    if (_cachedObservation == null) return false;
    final age = DateTime.now().difference(_cachedObservation!.timestamp);
    return age.inMinutes > 5;
  }

  @override
  Widget build(BuildContext context) {
    final props = widget.config.style.customProperties ?? {};
    final cardSize = props['cardSize'] as String? ?? 'normal';
    final showIndicators = props['showIndicators'] as bool? ?? true;
    final columns = props['columns'] as int? ?? 4;
    final showTitle = props['showTitle'] as bool? ?? true;

    final compact = cardSize == 'compact';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Use cached observation - only updates when valid data arrives
    final observation = _cachedObservation;
    final conversions = widget.weatherFlowService.conversions;
    final isLoading = widget.weatherFlowService.isLoading;
    final isStale = _isDataStale;

    // Build list of cards based on config
    final cards = _buildCardList(props, observation);

    // Only show loading spinner on first load when we have no cached data
    if (isLoading && observation == null && _cachedObservation == null) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title
        if (showTitle) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                Icon(
                  Icons.dashboard,
                  size: 18,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
                const SizedBox(width: 8),
                Text(
                  widget.name ?? 'Conditions',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const Spacer(),
                // Stale/loading indicator
                if (isStale) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isLoading
                          ? Colors.blue.withValues(alpha: 0.2)
                          : Colors.orange.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isLoading)
                          SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: Colors.blue,
                            ),
                          )
                        else
                          Icon(
                            Icons.access_time,
                            size: 12,
                            color: Colors.orange,
                          ),
                        const SizedBox(width: 4),
                        Text(
                          isLoading ? 'Updating' : 'Stale',
                          style: TextStyle(
                            fontSize: 10,
                            color: isLoading ? Colors.blue : Colors.orange,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                if (observation != null)
                  Text(
                    _formatTime(observation.timestamp),
                    style: TextStyle(
                      fontSize: 11,
                      color: isStale
                          ? (isDark ? Colors.orange.shade300 : Colors.orange.shade700)
                          : (isDark ? Colors.white54 : Colors.black45),
                    ),
                  ),
              ],
            ),
          ),
        ],

        // Cards grid or reorderable list in edit mode
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Calculate optimal column count based on width
              final effectiveColumns = _calculateColumns(
                constraints.maxWidth,
                columns,
                compact,
              );

              // In edit mode, use ReorderableListView
              if (widget.isEditMode) {
                return _buildReorderableGrid(
                  cards,
                  conversions,
                  compact,
                  showIndicators,
                  effectiveColumns,
                  constraints,
                );
              }

              // Normal mode: standard grid
              return GridView.builder(
                padding: const EdgeInsets.all(6),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: effectiveColumns,
                  crossAxisSpacing: 6,
                  mainAxisSpacing: 6,
                  childAspectRatio: compact ? 1.4 : 0.95,
                ),
                itemCount: cards.length,
                itemBuilder: (context, index) {
                  final card = cards[index];
                  return ConditionCard(
                    variable: card.variable,
                    value: card.value,
                    conversions: conversions,
                    compact: compact,
                    showIndicator: showIndicators,
                    secondaryValue: card.secondaryValue,
                    onTap: () => _openDetailSheet(card.variable),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  /// Build reorderable grid for edit mode
  Widget _buildReorderableGrid(
    List<ConditionCardData> cards,
    ConversionService conversions,
    bool compact,
    bool showIndicators,
    int columns,
    BoxConstraints constraints,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardHeight = compact ? 70.0 : 100.0;

    return Column(
      children: [
        // Edit mode hint
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
          child: Row(
            children: [
              Icon(Icons.drag_indicator, size: 16, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'Long press and drag to reorder cards',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.all(6),
            itemCount: cards.length,
            onReorder: _onReorder,
            proxyDecorator: (child, index, animation) {
              return Material(
                elevation: 4,
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                child: child,
              );
            },
            itemBuilder: (context, index) {
              final card = cards[index];
              return Container(
                key: ValueKey(card.variable.name),
                margin: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    // Drag handle
                    Container(
                      padding: const EdgeInsets.all(8),
                      child: Icon(
                        Icons.drag_handle,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                    ),
                    // Card content
                    Expanded(
                      child: SizedBox(
                        height: cardHeight,
                        child: ConditionCard(
                          variable: card.variable,
                          value: card.value,
                          conversions: conversions,
                          compact: compact,
                          showIndicator: showIndicators,
                          secondaryValue: card.secondaryValue,
                          onTap: null, // Disable tap in edit mode
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  int _calculateColumns(double width, int preferredColumns, bool compact) {
    final minCardWidth = compact ? 80.0 : 100.0;
    final maxColumns = (width / minCardWidth).floor();
    return preferredColumns.clamp(2, maxColumns);
  }

  /// Card definitions - maps keys to variable and value extractors
  Map<String, _CardDefinition> _getCardDefinitions() {
    return {
      'showTemperature': _CardDefinition(
        key: 'showTemperature',
        variable: ConditionVariable.temperature,
        getValue: (o) => o.temperature,
      ),
      'showFeelsLike': _CardDefinition(
        key: 'showFeelsLike',
        variable: ConditionVariable.feelsLike,
        getValue: (o) => o.feelsLike ?? _calculateFeelsLike(o),
      ),
      'showHumidity': _CardDefinition(
        key: 'showHumidity',
        variable: ConditionVariable.humidity,
        getValue: (o) => o.humidity,
      ),
      'showPressure': _CardDefinition(
        key: 'showPressure',
        variable: ConditionVariable.pressure,
        getValue: (o) => o.seaLevelPressure ?? o.stationPressure,
      ),
      'showWindSpeed': _CardDefinition(
        key: 'showWindSpeed',
        variable: ConditionVariable.windSpeed,
        getValue: (o) => o.windAvg,
        getSecondary: (o) => o.windDirection,
      ),
      'showWindGust': _CardDefinition(
        key: 'showWindGust',
        variable: ConditionVariable.windGust,
        getValue: (o) => o.windGust,
      ),
      'showRainRate': _CardDefinition(
        key: 'showRainRate',
        variable: ConditionVariable.rainRate,
        getValue: (o) => o.rainRate,
      ),
      'showRainAccumulated': _CardDefinition(
        key: 'showRainAccumulated',
        variable: ConditionVariable.rainAccumulated,
        getValue: (o) => o.rainAccumulated,
      ),
      'showUvIndex': _CardDefinition(
        key: 'showUvIndex',
        variable: ConditionVariable.uvIndex,
        getValue: (o) => o.uvIndex,
      ),
      'showSolarRadiation': _CardDefinition(
        key: 'showSolarRadiation',
        variable: ConditionVariable.solarRadiation,
        getValue: (o) => o.solarRadiation,
      ),
      'showPrecipType': _CardDefinition(
        key: 'showPrecipType',
        variable: ConditionVariable.precipType,
        getValue: (o) => _precipTypeToDouble(o.precipType),
      ),
      'showLightning': _CardDefinition(
        key: 'showLightning',
        variable: ConditionVariable.lightningCount,
        getValue: (o) => o.lightningCount?.toDouble(),
      ),
      'showBattery': _CardDefinition(
        key: 'showBattery',
        variable: ConditionVariable.batteryVoltage,
        getValue: (o) => o.batteryVoltage,
      ),
    };
  }

  List<ConditionCardData> _buildCardList(
    Map<String, dynamic> props,
    Observation? obs,
  ) {
    final cards = <ConditionCardData>[];
    final definitions = _getCardDefinitions();

    // Build cards in the order specified by _cardOrder
    for (final key in _cardOrder) {
      // Skip if not enabled in config
      if (!(props[key] as bool? ?? true)) continue;

      final def = definitions[key];
      if (def == null) continue;

      cards.add(ConditionCardData(
        variable: def.variable,
        value: obs != null ? def.getValue(obs) : null,
        secondaryValue: obs != null && def.getSecondary != null
            ? def.getSecondary!(obs)
            : null,
      ));
    }

    return cards;
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${time.month}/${time.day} ${time.hour}:${time.minute.toString().padLeft(2, '0')}';
  }

  /// Calculate feels like from observation data when not provided by API
  double? _calculateFeelsLike(Observation obs) {
    final tempK = obs.temperature;
    if (tempK == null) return null;

    final humidity = obs.humidity;
    final windMps = obs.windAvg;
    final tempC = tempK - 273.15;

    // Heat Index: when temp > 27°C and humidity > 40%
    if (tempC > 27 && humidity != null && humidity > 0.4) {
      final tempF = tempC * 9 / 5 + 32;
      final rh = humidity * 100;
      double hi = -42.379 +
          2.04901523 * tempF +
          10.14333127 * rh -
          0.22475541 * tempF * rh -
          0.00683783 * tempF * tempF -
          0.05481717 * rh * rh +
          0.00122874 * tempF * tempF * rh +
          0.00085282 * tempF * rh * rh -
          0.00000199 * tempF * tempF * rh * rh;
      return (hi - 32) * 5 / 9 + 273.15;
    }

    // Wind Chill: when temp < 10°C and wind > 1.34 m/s
    if (tempC < 10 && windMps != null && windMps > 1.34) {
      final tempF = tempC * 9 / 5 + 32;
      final windMph = windMps * 2.237;
      final windPow = pow(windMph > 0 ? windMph : 1, 0.16);
      final wc = 35.74 + 0.6215 * tempF - 35.75 * windPow + 0.4275 * tempF * windPow;
      return (wc - 32) * 5 / 9 + 273.15;
    }

    return tempK;
  }

  /// Convert PrecipType enum to double
  double _precipTypeToDouble(PrecipType type) {
    switch (type) {
      case PrecipType.none:
        return 0;
      case PrecipType.rain:
        return 1;
      case PrecipType.hail:
        return 2;
      case PrecipType.rainAndHail:
        return 3;
    }
  }
}
