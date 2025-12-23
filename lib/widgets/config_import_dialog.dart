/// Configuration Import Dialog
/// Allows users to preview and import app configuration from .wdwfjson files

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import '../models/export_config.dart';
import '../services/config_import_service.dart';

/// Dialog for importing app configuration
class ConfigImportDialog extends StatefulWidget {
  final File? file;

  const ConfigImportDialog({super.key, this.file});

  /// Show file picker and then import dialog
  static Future<bool> pickAndShow(BuildContext context) async {
    // Pick .wdwfjson file
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) {
      return false;
    }

    final filePath = result.files.first.path;
    if (filePath == null) {
      return false;
    }

    // Check file extension
    if (!filePath.toLowerCase().endsWith('.wdwfjson')) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select a .wdwfjson configuration file'),
          ),
        );
      }
      return false;
    }

    final file = File(filePath);
    if (!context.mounted) return false;

    return await show(context, file);
  }

  /// Show the import dialog with a pre-selected file
  static Future<bool> show(BuildContext context, File file) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ConfigImportDialog(file: file),
    );
    return result ?? false;
  }

  @override
  State<ConfigImportDialog> createState() => _ConfigImportDialogState();
}

class _ConfigImportDialogState extends State<ConfigImportDialog> {
  ImportMode _mode = ImportMode.merge;
  bool _includeStations = true;
  bool _isLoading = true;
  bool _isImporting = false;
  ImportResult? _parseResult;
  ExportConfig? _config;

  @override
  void initState() {
    super.initState();
    _parseFile();
  }

  Future<void> _parseFile() async {
    if (widget.file == null) {
      setState(() {
        _isLoading = false;
        _parseResult = ImportResult.failure('No file provided');
      });
      return;
    }

    final importService = context.read<ConfigImportService>();
    final result = await importService.parseConfig(widget.file!);

    if (result.success) {
      _config = await importService.loadConfig(widget.file!);
    }

    setState(() {
      _isLoading = false;
      _parseResult = result;
    });
  }

  String _formatDateTime(DateTime dateTime) {
    final formatter = DateFormat('MMM d, yyyy h:mm a');
    return formatter.format(dateTime.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return AlertDialog(
        title: Row(
          children: [
            Icon(Icons.file_download_outlined, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            const Text('Import Configuration'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Parsing configuration file...'),
          ],
        ),
      );
    }

    if (_parseResult == null || !_parseResult!.success) {
      return AlertDialog(
        title: Row(
          children: [
            Icon(Icons.error_outline, color: theme.colorScheme.error),
            const SizedBox(width: 8),
            const Text('Import Error'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Failed to parse configuration file:',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _parseResult?.error ?? 'Unknown error',
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Close'),
          ),
        ],
      );
    }

    final preview = _parseResult!.preview!;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.file_download_outlined, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          const Text('Import Configuration'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // File info
            if (preview.exportedAt != null) ...[
              Text(
                'Exported: ${_formatDateTime(preview.exportedAt!)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              if (preview.exportAppVersion != null)
                Text(
                  'App version: ${preview.exportAppVersion}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              const SizedBox(height: 16),
            ],

            // Preview counts
            Text(
              'Configuration Contents:',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            _buildPreviewItem(
              Icons.dashboard_customize,
              '${preview.screensCount} dashboard screen${preview.screensCount == 1 ? '' : 's'}',
            ),
            _buildPreviewItem(
              Icons.widgets,
              '${preview.toolsCount} tool${preview.toolsCount == 1 ? '' : 's'}',
            ),
            _buildPreviewItem(
              Icons.cloud,
              '${preview.stationsCount} saved station${preview.stationsCount == 1 ? '' : 's'}',
            ),
            _buildPreviewItem(
              Icons.directions_run,
              '${preview.activitiesCount} activity tolerance${preview.activitiesCount == 1 ? '' : 's'}',
            ),
            if (preview.hasSettings)
              _buildPreviewItem(Icons.settings, 'App settings'),
            if (preview.hasUnitPreferences)
              _buildPreviewItem(Icons.straighten, 'Unit preferences'),
            if (preview.hasDashboardLayout)
              _buildPreviewItem(Icons.view_quilt, 'Dashboard layout'),

            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),

            // Import mode
            Text(
              'Import Mode:',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            SegmentedButton<ImportMode>(
              segments: const [
                ButtonSegment(
                  value: ImportMode.merge,
                  label: Text('Merge'),
                  icon: Icon(Icons.merge),
                ),
                ButtonSegment(
                  value: ImportMode.replace,
                  label: Text('Replace All'),
                  icon: Icon(Icons.sync),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: _isImporting
                  ? null
                  : (selection) {
                      setState(() {
                        _mode = selection.first;
                      });
                    },
            ),
            const SizedBox(height: 8),
            Text(
              _mode == ImportMode.merge
                  ? 'Add new items and update existing ones by ID.'
                  : 'Clear all current configuration and replace with imported data.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),

            // Warning for replace mode
            if (_mode == ImportMode.replace) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: theme.colorScheme.error.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber, color: theme.colorScheme.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This will delete your current configuration!',
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Include stations option
            if (preview.stationsCount > 0)
              CheckboxListTile(
                title: const Text('Import Station References'),
                subtitle: Text('${preview.stationsCount} station${preview.stationsCount == 1 ? '' : 's'} (requires API token)'),
                value: _includeStations,
                onChanged: _isImporting
                    ? null
                    : (value) {
                        setState(() {
                          _includeStations = value ?? true;
                        });
                      },
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),

            if (_isImporting)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isImporting ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _isImporting ? null : () => _import(context),
          icon: const Icon(Icons.download),
          label: const Text('Import'),
        ),
      ],
    );
  }

  Widget _buildPreviewItem(IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.outline),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }

  Future<void> _import(BuildContext context) async {
    if (_config == null) return;

    setState(() {
      _isImporting = true;
    });

    try {
      final importService = context.read<ConfigImportService>();
      final result = await importService.applyConfig(
        _config!,
        _mode,
        includeStations: _includeStations,
      );

      if (context.mounted) {
        Navigator.pop(context, result.success);

        if (result.success) {
          String message = 'Configuration imported successfully';
          if (result.warnings.isNotEmpty) {
            message += ' (${result.warnings.length} warning${result.warnings.length == 1 ? '' : 's'})';
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message)),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Import failed: ${result.error}')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        setState(() {
          _isImporting = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: $e')),
        );
      }
    }
  }
}
