import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:weatherflow_core/weatherflow_core.dart';
import '../services/weatherflow_service.dart';
import 'dashboard_screen.dart';

/// Screen for selecting a weather station
class StationListScreen extends StatefulWidget {
  final bool isInitialSetup;

  const StationListScreen({
    super.key,
    this.isInitialSetup = false,
  });

  @override
  State<StationListScreen> createState() => _StationListScreenState();
}

class _StationListScreenState extends State<StationListScreen> {
  @override
  void initState() {
    super.initState();
    // Refresh stations if needed
    final weatherFlow = context.read<WeatherFlowService>();
    if (weatherFlow.stations.isEmpty) {
      weatherFlow.fetchStations();
    }
  }

  Future<void> _selectStation(Station station) async {
    final weatherFlow = context.read<WeatherFlowService>();
    await weatherFlow.selectStation(station);

    if (!mounted) return;

    if (widget.isInitialSetup) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const DashboardScreen()),
      );
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final weatherFlow = context.watch<WeatherFlowService>();
    final stations = weatherFlow.stations;
    final selectedStation = weatherFlow.selectedStation;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Station'),
        automaticallyImplyLeading: !widget.isInitialSetup,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: weatherFlow.isLoading ? null : () => weatherFlow.fetchStations(),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: weatherFlow.isLoading && stations.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : weatherFlow.error != null && stations.isEmpty
              ? _buildError(weatherFlow.error!)
              : stations.isEmpty
                  ? _buildEmpty()
                  : _buildStationList(stations, selectedStation),
    );
  }

  Widget _buildError(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              error,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => context.read<WeatherFlowService>().fetchStations(),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cloud_off,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'No stations found',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Make sure your WeatherFlow account has stations configured.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStationList(List<Station> stations, Station? selected) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: stations.length,
      itemBuilder: (context, index) {
        final station = stations[index];
        final isSelected = selected?.stationId == station.stationId;
        final device = station.tempestDevice;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Icon(
                Icons.cloud,
                color: isSelected
                    ? Theme.of(context).colorScheme.onPrimary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            title: Text(
              station.name,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (device != null)
                  Text('${device.deviceTypeName} - ${device.serialNumber}'),
                Text(
                  '${station.latitude.toStringAsFixed(4)}, ${station.longitude.toStringAsFixed(4)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            trailing: isSelected
                ? Icon(
                    Icons.check_circle,
                    color: Theme.of(context).colorScheme.primary,
                  )
                : const Icon(Icons.chevron_right),
            onTap: () => _selectStation(station),
          ),
        );
      },
    );
  }
}
