/// Reusable NWS Alerts Dialog
/// Can be used from any widget to display weather alerts

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../services/nws_alert_service.dart';
import '../utils/date_time_formatter.dart';

/// Extension for severity colors and icons (shared across widgets)
extension NWSAlertSeverityUI on AlertSeverity {
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

/// Show a dialog with NWS alerts
///
/// Usage:
/// ```dart
/// NWSAlertsDialog.show(context, alerts);
/// ```
class NWSAlertsDialog {
  /// Show alerts dialog
  static Future<void> show(BuildContext context, List<NWSAlert> alerts) {
    if (alerts.isEmpty) {
      return showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(PhosphorIcons.checkCircle(), color: Colors.green),
              const SizedBox(width: 8),
              const Text('No Active Alerts'),
            ],
          ),
          content: const Text('There are no active weather alerts for this location.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }

    return showDialog(
      context: context,
      builder: (context) => _AlertsDialogContent(alerts: alerts),
    );
  }

  /// Show alerts as a bottom sheet (alternative presentation)
  static Future<void> showAsSheet(BuildContext context, List<NWSAlert> alerts) {
    if (alerts.isEmpty) {
      return showModalBottomSheet(
        context: context,
        builder: (context) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(PhosphorIcons.checkCircle(), color: Colors.green, size: 48),
              const SizedBox(height: 16),
              const Text(
                'No Active Alerts',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text('There are no active weather alerts for this location.'),
              const SizedBox(height: 24),
            ],
          ),
        ),
      );
    }

    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.3,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => _AlertsSheetContent(
          alerts: alerts,
          scrollController: scrollController,
        ),
      ),
    );
  }
}

/// Dialog content widget
class _AlertsDialogContent extends StatelessWidget {
  final List<NWSAlert> alerts;

  const _AlertsDialogContent({required this.alerts});

  @override
  Widget build(BuildContext context) {
    final highestSeverity = alerts.first.severity;

    return AlertDialog(
      title: Row(
        children: [
          Icon(PhosphorIcons.warning(), color: highestSeverity.color),
          const SizedBox(width: 8),
          Text('${alerts.length} Active Alert${alerts.length != 1 ? 's' : ''}'),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: ListView.builder(
          itemCount: alerts.length,
          itemBuilder: (context, index) => _AlertExpansionTile(alert: alerts[index]),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// Bottom sheet content widget
class _AlertsSheetContent extends StatelessWidget {
  final List<NWSAlert> alerts;
  final ScrollController scrollController;

  const _AlertsSheetContent({
    required this.alerts,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final highestSeverity = alerts.first.severity;

    return Column(
      children: [
        // Drag handle
        Container(
          margin: const EdgeInsets.only(top: 8),
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.grey.shade400,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        // Header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: highestSeverity.backgroundColor,
            border: Border(
              bottom: BorderSide(color: highestSeverity.color, width: 2),
            ),
          ),
          child: Row(
            children: [
              Icon(PhosphorIcons.warning(), color: highestSeverity.color, size: 24),
              const SizedBox(width: 12),
              Text(
                '${alerts.length} Active Alert${alerts.length != 1 ? 's' : ''}',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: highestSeverity.color,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        // Alert list
        Expanded(
          child: ListView.builder(
            controller: scrollController,
            padding: const EdgeInsets.all(8),
            itemCount: alerts.length,
            itemBuilder: (context, index) => _AlertCard(alert: alerts[index]),
          ),
        ),
      ],
    );
  }
}

/// Expansion tile for dialog view
class _AlertExpansionTile extends StatelessWidget {
  final NWSAlert alert;

  const _AlertExpansionTile({required this.alert});

  @override
  Widget build(BuildContext context) {
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
              Text(
                alert.headline,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              Text(alert.description),
              if (alert.instruction != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(PhosphorIcons.info(), size: 16, color: Colors.blue.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          alert.instruction!,
                          style: TextStyle(
                            fontStyle: FontStyle.italic,
                            color: Colors.blue.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (alert.areaDesc.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Areas: ${alert.areaDesc}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  String _formatTimeRange(NWSAlert alert) {
    final parts = <String>[];
    final now = DateTime.now();

    if (alert.onset != null) {
      final onsetLocal = alert.onset!.toLocal();
      if (onsetLocal.isAfter(now)) {
        parts.add('Starts: ${_formatDateTime(onsetLocal)}');
      } else {
        parts.add('Started: ${_formatDateTime(onsetLocal)}');
      }
    }

    if (alert.ends != null) {
      parts.add('Until: ${_formatDateTime(alert.ends!.toLocal())}');
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
      dayPart = DateTimeFormatter.getDayAbbrev(dt);
    }

    return '$dayPart ${DateTimeFormatter.formatTime(dt)}';
  }
}

/// Card for bottom sheet view
class _AlertCard extends StatefulWidget {
  final NWSAlert alert;

  const _AlertCard({required this.alert});

  @override
  State<_AlertCard> createState() => _AlertCardState();
}

class _AlertCardState extends State<_AlertCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final alert = widget.alert;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: alert.severity.backgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: alert.severity.color, width: 1),
      ),
      child: InkWell(
        onTap: () => setState(() => _isExpanded = !_isExpanded),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Icon(alert.severity.icon, color: alert.severity.color, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      alert.event,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: alert.severity.color,
                      ),
                    ),
                  ),
                  if (alert.isImminent)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      margin: const EdgeInsets.only(right: 4),
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
                    _isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: alert.severity.color,
                  ),
                ],
              ),
              // Time
              const SizedBox(height: 4),
              Text(
                _AlertExpansionTile(alert: alert)._formatTimeRange(alert),
                style: TextStyle(fontSize: 11, color: Colors.black54),
              ),
              // Expanded content
              if (_isExpanded) ...[
                const Divider(height: 16),
                Text(
                  alert.headline,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  alert.description,
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                if (alert.instruction != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(PhosphorIcons.info(), size: 14, color: Colors.black54),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            alert.instruction!,
                            style: const TextStyle(
                              fontSize: 11,
                              fontStyle: FontStyle.italic,
                              color: Colors.black54,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
