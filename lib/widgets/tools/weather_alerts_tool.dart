// NWS Weather Alerts Tool
// Displays NWS weather alerts with severity-based alerting
// Supports phone location, station location, or both

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../services/tool_registry.dart';
import '../../services/nws_alert_service.dart';
import '../../services/weatherflow_service.dart';

/// Extension for severity colors and icons
extension AlertSeverityUI on AlertSeverity {
  Color get color {
    switch (this) {
      case AlertSeverity.extreme:
        return Colors.purple.shade700;
      case AlertSeverity.severe:
        return Colors.red.shade700;
      case AlertSeverity.moderate:
        return Colors.orange.shade700;
      case AlertSeverity.minor:
        return Colors.yellow.shade700;
      case AlertSeverity.unknown:
        return Colors.grey.shade600;
    }
  }

  Color get backgroundColor {
    switch (this) {
      case AlertSeverity.extreme:
        return Colors.purple.shade100;
      case AlertSeverity.severe:
        return Colors.red.shade100;
      case AlertSeverity.moderate:
        return Colors.orange.shade100;
      case AlertSeverity.minor:
        return Colors.yellow.shade100;
      case AlertSeverity.unknown:
        return Colors.grey.shade200;
    }
  }

  IconData get icon {
    switch (this) {
      case AlertSeverity.extreme:
        return PhosphorIcons.warning();
      case AlertSeverity.severe:
        return PhosphorIcons.warningCircle();
      case AlertSeverity.moderate:
        return PhosphorIcons.info();
      case AlertSeverity.minor:
        return PhosphorIcons.bellRinging();
      case AlertSeverity.unknown:
        return PhosphorIcons.question();
    }
  }
}

/// Weather Alerts Tool - displays NWS alerts with severity-based alerting
class WeatherAlertsTool extends StatefulWidget {
  final ToolConfig config;
  final WeatherFlowService weatherFlowService;
  final bool isEditMode;

  const WeatherAlertsTool({
    super.key,
    required this.config,
    required this.weatherFlowService,
    this.isEditMode = false,
  });

  @override
  State<WeatherAlertsTool> createState() => _WeatherAlertsToolState();
}

class _WeatherAlertsToolState extends State<WeatherAlertsTool>
    with SingleTickerProviderStateMixin {
  late NWSAlertService _alertService;
  String? _expandedAlertId;
  late AnimationController _pulseController;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _alertService = NWSAlertService();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _initializeService();
  }

  Future<void> _initializeService() async {
    // Get location source from config
    final props = widget.config.style.customProperties ?? {};
    final sourceStr = props['locationSource'] as String? ?? 'both';
    final source = AlertLocationSource.values.firstWhere(
      (s) => s.name == sourceStr,
      orElse: () => AlertLocationSource.both,
    );
    _alertService.setLocationSource(source);

    // Set station location from WeatherFlow if available
    final station = widget.weatherFlowService.selectedStation;
    if (station != null) {
      _alertService.setStationLocation(station.latitude, station.longitude);
    }

    // Fetch alerts
    await _alertService.fetchAlerts();

    // Start auto-refresh (every 5 minutes)
    final refreshInterval = props['refreshInterval'] as int? ?? 5;
    _alertService.startAutoRefresh(interval: Duration(minutes: refreshInterval));

    _alertService.addListener(_onAlertsChanged);

    if (mounted) {
      setState(() => _isInitialized = true);
    }
  }

  void _onAlertsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _alertService.removeListener(_onAlertsChanged);
    _alertService.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(WeatherAlertsTool oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Update station location if changed
    final station = widget.weatherFlowService.selectedStation;
    if (station != null) {
      _alertService.setStationLocation(station.latitude, station.longitude);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeAlerts = _alertService.activeAlerts;
    final props = widget.config.style.customProperties ?? {};
    final showCompact = props['compact'] as bool? ?? false;
    final showDescription = props['showDescription'] as bool? ?? true;
    final showInstruction = props['showInstruction'] as bool? ?? true;
    final showAreaDesc = props['showAreaDesc'] as bool? ?? false;
    final showSenderName = props['showSenderName'] as bool? ?? false;
    final showTimeRange = props['showTimeRange'] as bool? ?? true;

    if (!_isInitialized || _alertService.isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 8),
            Text(
              'Loading alerts...',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white60 : Colors.black45,
              ),
            ),
          ],
        ),
      );
    }

    if (_alertService.error != null && activeAlerts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              PhosphorIcons.warningCircle(),
              size: 32,
              color: Colors.red.shade400,
            ),
            const SizedBox(height: 8),
            Text(
              _alertService.error!,
              style: TextStyle(
                fontSize: 12,
                color: Colors.red.shade400,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => _alertService.fetchAlerts(),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (activeAlerts.isEmpty) {
      return _buildNoAlerts(isDark);
    }

    if (showCompact) {
      return _buildCompactView(activeAlerts, isDark);
    }

    return _buildFullView(
      activeAlerts,
      isDark,
      showTimeRange: showTimeRange,
      showDescription: showDescription,
      showInstruction: showInstruction,
      showAreaDesc: showAreaDesc,
      showSenderName: showSenderName,
    );
  }

  Widget _buildNoAlerts(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            PhosphorIcons.checkCircle(),
            size: 48,
            color: Colors.green.shade400,
          ),
          const SizedBox(height: 8),
          Text(
            'No Active Alerts',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _getLocationSourceLabel(),
            style: TextStyle(
              fontSize: 10,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),
        ],
      ),
    );
  }

  String _getLocationSourceLabel() {
    switch (_alertService.locationSource) {
      case AlertLocationSource.phone:
        return 'Using phone location';
      case AlertLocationSource.station:
        return 'Using station location';
      case AlertLocationSource.both:
        return 'Using phone & station locations';
    }
  }

  Widget _buildCompactView(List<NWSAlert> alerts, bool isDark) {
    final highestSeverity = alerts.first.severity;
    final hasNew = _alertService.newAlertIds.isNotEmpty;

    return GestureDetector(
      onTap: () => _showAlertsDialog(alerts),
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          final pulse = hasNew || highestSeverity == AlertSeverity.extreme
              ? 0.3 + (_pulseController.value * 0.2)
              : 0.0;

          return Container(
            decoration: BoxDecoration(
              color: highestSeverity.backgroundColor.withValues(alpha: 0.3 + pulse),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: highestSeverity.color,
                width: 2,
              ),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(
                        highestSeverity.icon,
                        size: 32,
                        color: highestSeverity.color,
                      ),
                      if (alerts.length > 1)
                        Positioned(
                          right: -8,
                          top: -8,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: highestSeverity.color,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '${alerts.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      alerts.first.event,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: highestSeverity.color,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFullView(
    List<NWSAlert> alerts,
    bool isDark, {
    required bool showTimeRange,
    required bool showDescription,
    required bool showInstruction,
    required bool showAreaDesc,
    required bool showSenderName,
  }) {
    return Column(
      children: [
        // Header with alert count
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: alerts.first.severity.color,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
          ),
          child: Row(
            children: [
              Icon(
                PhosphorIcons.warning(),
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                '${alerts.length} Active Alert${alerts.length != 1 ? 's' : ''}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              // Refresh button
              if (!widget.isEditMode)
                InkWell(
                  onTap: () => _alertService.fetchAlerts(),
                  child: Icon(
                    Icons.refresh,
                    color: Colors.white.withValues(alpha: 0.8),
                    size: 18,
                  ),
                ),
              const SizedBox(width: 8),
              Text(
                'NWS',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        // Alert list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: alerts.length,
            itemBuilder: (context, index) {
              final alert = alerts[index];
              final isExpanded = _expandedAlertId == alert.id;
              final isNew = _alertService.newAlertIds.contains(alert.id);

              return _buildAlertCard(
                alert,
                isExpanded,
                isNew,
                isDark,
                showTimeRange: showTimeRange,
                showDescription: showDescription,
                showInstruction: showInstruction,
                showAreaDesc: showAreaDesc,
                showSenderName: showSenderName,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAlertCard(
    NWSAlert alert,
    bool isExpanded,
    bool isNew,
    bool isDark, {
    required bool showTimeRange,
    required bool showDescription,
    required bool showInstruction,
    required bool showAreaDesc,
    required bool showSenderName,
  }) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final pulse = isNew ? 0.3 + (_pulseController.value * 0.2) : 0.0;

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          color: alert.severity.backgroundColor.withValues(alpha: 0.5 + pulse),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: alert.severity.color,
              width: isNew ? 2 : 1,
            ),
          ),
          child: InkWell(
            onTap: () {
              setState(() {
                _expandedAlertId = isExpanded ? null : alert.id;
                _alertService.markAlertSeen(alert.id);
              });
            },
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header row
                  Row(
                    children: [
                      Icon(
                        alert.severity.icon,
                        color: alert.severity.color,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          alert.event,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: alert.severity.color,
                          ),
                        ),
                      ),
                      // Source indicator
                      if (alert.source != 'unknown')
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          margin: const EdgeInsets.only(right: 4),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            alert.source == 'both' ? 'P+S' : (alert.source == 'phone' ? 'P' : 'S'),
                            style: TextStyle(
                              fontSize: 9,
                              color: isDark ? Colors.white54 : Colors.black38,
                            ),
                          ),
                        ),
                      if (alert.isImminent)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'IMMINENT',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      Icon(
                        isExpanded ? Icons.expand_less : Icons.expand_more,
                        color: alert.severity.color,
                      ),
                    ],
                  ),

                  // Time info
                  if (showTimeRange && (alert.onset != null || alert.ends != null)) ...[
                    const SizedBox(height: 4),
                    Text(
                      _formatTimeRange(alert),
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                  ],

                  // Expanded content
                  if (isExpanded) ...[
                    const Divider(height: 16),
                    Text(
                      alert.headline,
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    if (showDescription) ...[
                      const SizedBox(height: 8),
                      Text(
                        alert.description,
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white70 : Colors.black54,
                        ),
                      ),
                    ],
                    if (showInstruction && alert.instruction != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              PhosphorIcons.info(),
                              size: 14,
                              color: isDark ? Colors.white70 : Colors.black54,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                alert.instruction!,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontStyle: FontStyle.italic,
                                  color: isDark ? Colors.white70 : Colors.black54,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (showAreaDesc && alert.areaDesc.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Areas: ${alert.areaDesc}',
                        style: TextStyle(
                          fontSize: 10,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                      ),
                    ],
                    if (showSenderName) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Source: ${alert.senderName}',
                        style: TextStyle(
                          fontSize: 10,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatTimeRange(NWSAlert alert) {
    final now = DateTime.now();
    final parts = <String>[];

    if (alert.onset != null) {
      final onsetLocal = alert.onset!.toLocal();
      if (onsetLocal.isAfter(now)) {
        parts.add('Starts: ${_formatDateTime(onsetLocal)}');
      } else {
        parts.add('Started: ${_formatDateTime(onsetLocal)}');
      }
    }

    if (alert.ends != null) {
      final endsLocal = alert.ends!.toLocal();
      parts.add('Until: ${_formatDateTime(endsLocal)}');
    }

    return parts.join(' | ');
  }

  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final dtDate = DateTime(dt.year, dt.month, dt.day);

    String dayPart;
    if (dtDate == today) {
      dayPart = 'Today';
    } else if (dtDate == tomorrow) {
      dayPart = 'Tomorrow';
    } else {
      final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      dayPart = days[dt.weekday - 1];
    }

    final hour = dt.hour;
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = hour < 12 ? 'AM' : 'PM';
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);

    return '$dayPart $displayHour:$minute $ampm';
  }

  void _showAlertsDialog(List<NWSAlert> alerts) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(PhosphorIcons.warning(), color: alerts.first.severity.color),
            const SizedBox(width: 8),
            Text('${alerts.length} Active Alerts'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: ListView.builder(
            itemCount: alerts.length,
            itemBuilder: (context, index) {
              final alert = alerts[index];
              return ExpansionTile(
                leading: Icon(alert.severity.icon, color: alert.severity.color),
                title: Text(
                  alert.event,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: alert.severity.color,
                  ),
                ),
                subtitle: Text(_formatTimeRange(alert)),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(alert.description),
                        if (alert.instruction != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            alert.instruction!,
                            style: const TextStyle(fontStyle: FontStyle.italic),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

/// Builder for Weather Alerts tool
class WeatherAlertsToolBuilder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'weather_alerts',
      name: 'NWS Weather Alerts',
      description: 'Display NWS weather alerts for your location',
      category: ToolCategory.weather,
      configSchema: ConfigSchema(
        allowsMinMax: false,
        allowsColorCustomization: false,
        allowsMultiplePaths: false,
        minPaths: 0,
        maxPaths: 0,
        styleOptions: const ['compact'],
      ),
    );
  }

  @override
  ToolConfig? getDefaultConfig() {
    return const ToolConfig(
      dataSources: [],
      style: StyleConfig(
        customProperties: {
          'compact': false,
          'locationSource': 'both',
          'refreshInterval': 5,
          'showDescription': true,
          'showInstruction': true,
          'showAreaDesc': false,
          'showSenderName': false,
          'showTimeRange': true,
        },
      ),
    );
  }

  @override
  Widget build(
    ToolConfig config,
    WeatherFlowService weatherFlowService, {
    bool isEditMode = false,
  }) {
    return WeatherAlertsTool(
      config: config,
      weatherFlowService: weatherFlowService,
      isEditMode: isEditMode,
    );
  }
}
