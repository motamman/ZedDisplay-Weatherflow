/// Configuration Export Dialog
/// Allows users to export and share app configuration

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/config_export_service.dart';

/// Dialog for exporting app configuration
class ConfigExportDialog extends StatefulWidget {
  const ConfigExportDialog({super.key});

  /// Show the export dialog
  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (context) => const ConfigExportDialog(),
    );
  }

  @override
  State<ConfigExportDialog> createState() => _ConfigExportDialogState();
}

class _ConfigExportDialogState extends State<ConfigExportDialog> {
  bool _includeStations = true;
  bool _isExporting = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.file_upload_outlined, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          const Text('Export Configuration'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Export your app settings, dashboard layout, tools, and preferences to a .wdwfjson file.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          CheckboxListTile(
            title: const Text('Include Station References'),
            subtitle: const Text('Include station info (not API token)'),
            value: _includeStations,
            onChanged: _isExporting
                ? null
                : (value) {
                    setState(() {
                      _includeStations = value ?? true;
                    });
                  },
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.security,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Your API token is NOT exported for security.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (_isExporting)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isExporting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _isExporting ? null : () => _share(context),
          icon: const Icon(Icons.share),
          label: const Text('Share'),
        ),
      ],
    );
  }

  Future<void> _share(BuildContext context) async {
    setState(() {
      _isExporting = true;
    });

    try {
      final exportService = context.read<ConfigExportService>();
      final result = await exportService.shareConfig(
        includeStations: _includeStations,
      );

      if (context.mounted) {
        Navigator.pop(context);

        // Show result
        final status = result.status.name;
        if (status == 'success' || status == 'dismissed') {
          // Success or user dismissed - no message needed
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Export $status')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        setState(() {
          _isExporting = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }
}
