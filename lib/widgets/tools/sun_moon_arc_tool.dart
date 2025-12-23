/// Sun/Moon Arc Tool for OpenMeteo
/// Displays sun and moon times with configurable arc styles

import 'package:flutter/material.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../services/tool_registry.dart';
import '../../services/weatherflow_service.dart';
import '../sun_moon_arc.dart';

/// Builder for Sun/Moon Arc tool
class SunMoonArcToolBuilder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return const ToolDefinition(
      id: 'sun_moon_arc',
      name: 'Sun/Moon Arc',
      description: 'Shows sun and moon positions with configurable arc display',
      category: ToolCategory.weather,
      configSchema: ConfigSchema(
        allowsMinMax: false,
        allowsColorCustomization: false,
        allowsMultiplePaths: false,
        minPaths: 0,
        maxPaths: 0,
        styleOptions: [
          'arcStyle',
          'use24HourFormat',
          'showTimeLabels',
          'showSunMarkers',
          'showMoonMarkers',
          'showTwilightSegments',
          'showCenterIndicator',
        ],
      ),
      defaultWidth: 4,
      defaultHeight: 1,
    );
  }

  @override
  Widget build(ToolConfig config, WeatherFlowService weatherFlowService, {bool isEditMode = false, String? name, void Function(ToolConfig)? onConfigChanged}) {
    return SunMoonArcTool(
      config: config,
      weatherFlowService: weatherFlowService,
      name: name,
    );
  }

  @override
  ToolConfig? getDefaultConfig() {
    return const ToolConfig(
      dataSources: [],
      style: StyleConfig(
        customProperties: {
          'showTitle': false,
          'arcStyle': 'half',
          'use24HourFormat': false,
          'showTimeLabels': true,
          'showSunMarkers': true,
          'showMoonMarkers': true,
          'showTwilightSegments': true,
          'showCenterIndicator': true,
        },
      ),
    );
  }
}

/// Sun/Moon Arc tool widget
class SunMoonArcTool extends StatelessWidget {
  final ToolConfig config;
  final WeatherFlowService weatherFlowService;
  final String? name;

  const SunMoonArcTool({
    super.key,
    required this.config,
    required this.weatherFlowService,
    this.name,
  });

  /// Parse arc style from config
  ArcStyle _getArcStyle() {
    final styleStr = config.style.customProperties?['arcStyle'] as String? ?? 'half';
    switch (styleStr) {
      case 'threeQuarter':
        return ArcStyle.threeQuarter;
      case 'wide':
        return ArcStyle.wide;
      case 'full':
        return ArcStyle.full;
      case 'half':
      default:
        return ArcStyle.half;
    }
  }

  /// Parse color from hex string
  Color? _parseColor(String? colorString) {
    if (colorString == null || colorString.isEmpty) return null;
    try {
      final hexColor = colorString.replaceAll('#', '');
      return Color(int.parse('FF$hexColor', radix: 16));
    } catch (e) {
      return null;
    }
  }

  /// Build arc config from tool config
  SunMoonArcConfig _buildArcConfig() {
    final props = config.style.customProperties ?? {};
    return SunMoonArcConfig(
      arcStyle: _getArcStyle(),
      use24HourFormat: props['use24HourFormat'] as bool? ?? false,
      showTimeLabels: props['showTimeLabels'] as bool? ?? true,
      showSunMarkers: props['showSunMarkers'] as bool? ?? true,
      showMoonMarkers: props['showMoonMarkers'] as bool? ?? true,
      showTwilightSegments: props['showTwilightSegments'] as bool? ?? true,
      showCenterIndicator: props['showCenterIndicator'] as bool? ?? true,
      showSecondaryIcons: props['showSecondaryIcons'] as bool? ?? true,
      showInteriorTime: props['showInteriorTime'] as bool? ?? false,
      strokeWidth: config.style.strokeWidth ?? 2.0,
      labelColor: _parseColor(config.style.primaryColor),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final props = config.style.customProperties ?? {};
    final showTitle = props['showTitle'] as bool? ?? false;
    final displayTitle = name?.isNotEmpty == true ? name! : 'Sun/Moon Arc';

    return ListenableBuilder(
      listenable: weatherFlowService,
      builder: (context, _) {
        final sunMoonTimes = weatherFlowService.sunMoonTimes;

        if (sunMoonTimes == null) {
          return const Center(
            child: Text(
              'Loading sun/moon data...',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          );
        }

        final arcWidget = Padding(
          padding: const EdgeInsets.all(4.0),
          child: SunMoonArcWidget(
            times: sunMoonTimes,
            config: _buildArcConfig(),
          ),
        );

        return _wrapWithTitle(showTitle, displayTitle, isDark, arcWidget);
      },
    );
  }

  /// Wrap content with optional title header
  Widget _wrapWithTitle(bool showTitle, String title, bool isDark, Widget content) {
    if (!showTitle) return content;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          child: Row(
            children: [
              Icon(
                Icons.wb_sunny_outlined,
                size: 16,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
        ),
        Expanded(child: content),
      ],
    );
  }
}
