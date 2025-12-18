/// Wind Tool for WeatherFlow
/// Displays wind speed, direction, and gust

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../services/tool_registry.dart';
import '../../services/weatherflow_service.dart';

/// Builder for Wind tool
class WindToolBuilder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return const ToolDefinition(
      id: 'wind',
      name: 'Wind',
      description: 'Shows wind speed, direction with compass, and gusts',
      category: ToolCategory.weather,
      configSchema: ConfigSchema(
        allowsMinMax: true,
        allowsColorCustomization: true,
        allowsMultiplePaths: false,
        minPaths: 0,
        maxPaths: 0,
      ),
      defaultWidth: 2,
      defaultHeight: 2,
    );
  }

  @override
  Widget build(ToolConfig config, WeatherFlowService weatherFlowService, {bool isEditMode = false}) {
    return WindTool(
      config: config,
      weatherFlowService: weatherFlowService,
    );
  }

  @override
  ToolConfig? getDefaultConfig() {
    return const ToolConfig(
      dataSources: [],
      style: StyleConfig(),
    );
  }
}

/// Wind display widget with compass
class WindTool extends StatelessWidget {
  final ToolConfig config;
  final WeatherFlowService weatherFlowService;

  const WindTool({
    super.key,
    required this.config,
    required this.weatherFlowService,
  });

  /// Get configured primary color or fall back to theme color
  Color _getPrimaryColor(BuildContext context) {
    final colorString = config.style.primaryColor;
    if (colorString != null && colorString.isNotEmpty) {
      try {
        final hexColor = colorString.replaceAll('#', '');
        return Color(int.parse('FF$hexColor', radix: 16));
      } catch (e) {
        // Invalid color format, fall back to theme
      }
    }
    return Theme.of(context).colorScheme.primary;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: weatherFlowService,
      builder: (context, _) {
        final observation = weatherFlowService.currentObservation;
        final conversions = weatherFlowService.conversions;
        final primaryColor = _getPrimaryColor(context);

        if (observation == null) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        final windAvg = observation.windAvg;
        final windGust = observation.windGust;
        final windDir = observation.windDirection;

        return Container(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Wind compass
              Expanded(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: CustomPaint(
                    painter: WindCompassPainter(
                      direction: windDir ?? 0,
                      color: primaryColor,
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            windAvg != null
                                ? conversions.formatWindSpeed(windAvg)
                                : '--',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (windDir != null)
                            Text(
                              conversions.getWindDirectionLabel(windDir),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 4),

              // Gust
              if (windGust != null)
                Text(
                  'Gust: ${conversions.formatWindSpeed(windGust)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Custom painter for wind compass
class WindCompassPainter extends CustomPainter {
  final double direction; // degrees
  final Color color;

  WindCompassPainter({
    required this.direction,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 4;

    // Draw circle
    final circlePaint = Paint()
      ..color = color.withOpacity(0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radius, circlePaint);

    // Draw cardinal points
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    const cardinals = ['N', 'E', 'S', 'W'];
    const angles = [0.0, 90.0, 180.0, 270.0];

    for (var i = 0; i < 4; i++) {
      final angle = angles[i] * math.pi / 180 - math.pi / 2;
      final x = center.dx + (radius - 12) * math.cos(angle);
      final y = center.dy + (radius - 12) * math.sin(angle);

      textPainter.text = TextSpan(
        text: cardinals[i],
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(x - textPainter.width / 2, y - textPainter.height / 2),
      );
    }

    // Draw direction arrow
    final arrowAngle = direction * math.pi / 180 - math.pi / 2;
    final arrowLength = radius - 20;

    final arrowPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final arrowPath = Path();
    final tipX = center.dx + arrowLength * math.cos(arrowAngle);
    final tipY = center.dy + arrowLength * math.sin(arrowAngle);

    final baseAngle1 = arrowAngle + math.pi - 0.3;
    final baseAngle2 = arrowAngle + math.pi + 0.3;
    final baseLength = arrowLength * 0.6;

    arrowPath.moveTo(tipX, tipY);
    arrowPath.lineTo(
      center.dx + baseLength * math.cos(baseAngle1),
      center.dy + baseLength * math.sin(baseAngle1),
    );
    arrowPath.lineTo(center.dx, center.dy);
    arrowPath.lineTo(
      center.dx + baseLength * math.cos(baseAngle2),
      center.dy + baseLength * math.sin(baseAngle2),
    );
    arrowPath.close();

    canvas.drawPath(arrowPath, arrowPaint);
  }

  @override
  bool shouldRepaint(WindCompassPainter oldDelegate) {
    return direction != oldDelegate.direction || color != oldDelegate.color;
  }
}
