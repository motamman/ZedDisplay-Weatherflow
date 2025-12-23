/// Conditions Dashboard Tool
///
/// Modern grid of all current weather conditions.
/// Tapping any card opens a detail chart with history and forecast.

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
      {bool isEditMode = false, String? name}) {
    return ConditionsDashboardTool(
      config: config,
      weatherFlowService: weatherFlowService,
      isEditMode: isEditMode,
      name: name,
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
          'showLightning': true,
          'showBattery': true,
        },
      ),
    );
  }
}

/// Conditions Dashboard Widget
class ConditionsDashboardTool extends StatefulWidget {
  final ToolConfig config;
  final WeatherFlowService weatherFlowService;
  final bool isEditMode;
  final String? name;

  const ConditionsDashboardTool({
    super.key,
    required this.config,
    required this.weatherFlowService,
    this.isEditMode = false,
    this.name,
  });

  @override
  State<ConditionsDashboardTool> createState() => _ConditionsDashboardToolState();
}

class _ConditionsDashboardToolState extends State<ConditionsDashboardTool> {
  @override
  void initState() {
    super.initState();
    widget.weatherFlowService.addListener(_onDataChanged);
  }

  @override
  void dispose() {
    widget.weatherFlowService.removeListener(_onDataChanged);
    super.dispose();
  }

  void _onDataChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(ConditionsDashboardTool oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.weatherFlowService != widget.weatherFlowService) {
      oldWidget.weatherFlowService.removeListener(_onDataChanged);
      widget.weatherFlowService.addListener(_onDataChanged);
    }
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

  @override
  Widget build(BuildContext context) {
    final props = widget.config.style.customProperties ?? {};
    final cardSize = props['cardSize'] as String? ?? 'normal';
    final showIndicators = props['showIndicators'] as bool? ?? true;
    final columns = props['columns'] as int? ?? 4;
    final showTitle = props['showTitle'] as bool? ?? true;

    final compact = cardSize == 'compact';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Get current observation
    final observation = widget.weatherFlowService.currentObservation;
    final conversions = widget.weatherFlowService.conversions;

    // Build list of cards based on config
    final cards = _buildCardList(props, observation);

    // Loading state
    if (widget.weatherFlowService.isLoading && observation == null) {
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
                if (observation != null)
                  Text(
                    _formatTime(observation.timestamp),
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white54 : Colors.black45,
                    ),
                  ),
              ],
            ),
          ),
        ],

        // Cards grid
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Calculate optimal column count based on width
              final effectiveColumns = _calculateColumns(
                constraints.maxWidth,
                columns,
                compact,
              );

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

  int _calculateColumns(double width, int preferredColumns, bool compact) {
    final minCardWidth = compact ? 80.0 : 100.0;
    final maxColumns = (width / minCardWidth).floor();
    return preferredColumns.clamp(2, maxColumns);
  }

  List<ConditionCardData> _buildCardList(
    Map<String, dynamic> props,
    Observation? obs,
  ) {
    final cards = <ConditionCardData>[];

    // Helper to add card if enabled - passes RAW SI values
    // Card uses ConversionService to format display
    void addIfEnabled(String key, ConditionVariable variable,
        double? Function(Observation) getValue,
        {double? Function(Observation)? getSecondary}) {
      if (props[key] as bool? ?? true) {
        cards.add(ConditionCardData(
          variable: variable,
          value: obs != null ? getValue(obs) : null,
          secondaryValue: obs != null && getSecondary != null ? getSecondary(obs) : null,
        ));
      }
    }

    // Add cards in order - all values are RAW SI units
    // Temperature: Kelvin, Pressure: Pascals, Wind: m/s, Rain: meters, Humidity: ratio 0-1
    addIfEnabled('showTemperature', ConditionVariable.temperature,
        (o) => o.temperature);

    addIfEnabled('showFeelsLike', ConditionVariable.feelsLike,
        (o) => o.feelsLike);

    addIfEnabled('showHumidity', ConditionVariable.humidity,
        (o) => o.humidity);

    addIfEnabled('showPressure', ConditionVariable.pressure,
        (o) => o.seaLevelPressure ?? o.stationPressure);

    addIfEnabled('showWindSpeed', ConditionVariable.windSpeed,
        (o) => o.windAvg,
        getSecondary: (o) => o.windDirection);

    addIfEnabled('showWindGust', ConditionVariable.windGust,
        (o) => o.windGust);

    addIfEnabled('showRainRate', ConditionVariable.rainRate,
        (o) => o.rainRate);

    addIfEnabled('showRainAccumulated', ConditionVariable.rainAccumulated,
        (o) => o.rainAccumulated);

    addIfEnabled('showUvIndex', ConditionVariable.uvIndex,
        (o) => o.uvIndex);

    addIfEnabled('showSolarRadiation', ConditionVariable.solarRadiation,
        (o) => o.solarRadiation);

    addIfEnabled('showLightning', ConditionVariable.lightningCount,
        (o) => o.lightningCount?.toDouble());

    addIfEnabled('showBattery', ConditionVariable.batteryVoltage,
        (o) => o.batteryVoltage);

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
}
