import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/weatherflow_service.dart';
import 'station_list_screen.dart';
import 'settings_screen.dart';

/// Main home screen with weather data display
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Ensure data is being fetched
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final weatherFlow = context.read<WeatherFlowService>();
      if (weatherFlow.currentObservation == null) {
        weatherFlow.refresh();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final weatherFlow = context.watch<WeatherFlowService>();
    final station = weatherFlow.selectedStation;
    final observation = weatherFlow.currentObservation;
    final conversions = weatherFlow.conversions;

    return Scaffold(
      appBar: AppBar(
        title: Text(station?.name ?? 'WeatherFlow'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: weatherFlow.isLoading ? null : () => weatherFlow.refresh(),
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: const Icon(Icons.swap_horiz),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const StationListScreen()),
            ),
            tooltip: 'Change Station',
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
            tooltip: 'Settings',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => weatherFlow.refresh(),
        child: observation == null
            ? _buildLoading(weatherFlow)
            : _buildWeatherDisplay(observation, conversions),
      ),
    );
  }

  Widget _buildLoading(WeatherFlowService weatherFlow) {
    if (weatherFlow.error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cloud_off,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              weatherFlow.error!,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => weatherFlow.refresh(),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Loading weather data...'),
        ],
      ),
    );
  }

  Widget _buildWeatherDisplay(dynamic observation, dynamic conversions) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Connection status
          _buildConnectionStatus(),
          const SizedBox(height: 16),

          // Temperature card
          _buildTemperatureCard(observation, conversions),
          const SizedBox(height: 16),

          // Wind card
          _buildWindCard(observation, conversions),
          const SizedBox(height: 16),

          // Atmospheric card
          _buildAtmosphericCard(observation, conversions),
          const SizedBox(height: 16),

          // Light & UV card
          _buildLightCard(observation),
          const SizedBox(height: 16),

          // Rain & Lightning card
          _buildPrecipCard(observation, conversions),
          const SizedBox(height: 16),

          // Last updated
          _buildLastUpdated(observation),
        ],
      ),
    );
  }

  Widget _buildConnectionStatus() {
    final weatherFlow = context.watch<WeatherFlowService>();
    final connectionType = weatherFlow.connectionType;

    IconData icon;
    String label;
    Color color;

    switch (connectionType) {
      case ConnectionType.websocket:
        icon = Icons.wifi;
        label = 'Live (WebSocket)';
        color = Colors.green;
        break;
      case ConnectionType.udp:
        icon = Icons.wifi;
        label = 'Live (UDP)';
        color = Colors.green;
        break;
      case ConnectionType.rest:
        icon = Icons.cloud;
        label = 'Polling (REST)';
        color = Colors.orange;
        break;
      case ConnectionType.none:
        icon = Icons.cloud_off;
        label = 'Disconnected';
        color = Colors.red;
        break;
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(color: color, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildTemperatureCard(dynamic observation, dynamic conversions) {
    final temp = observation.temperature;
    final humidity = observation.humidity;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(
              Icons.thermostat,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 8),
            Text(
              temp != null ? conversions.formatTemperature(temp, format: '0') : '--',
              style: Theme.of(context).textTheme.displayMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            if (humidity != null)
              Text(
                'Humidity: ${conversions.formatHumidity(humidity)}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildWindCard(dynamic observation, dynamic conversions) {
    final windAvg = observation.windAvg;
    final windGust = observation.windGust;
    final windDir = observation.windDirection;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.air, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Wind',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildWindValue(
                  'Speed',
                  windAvg != null ? conversions.formatWindSpeed(windAvg) : '--',
                ),
                _buildWindValue(
                  'Gust',
                  windGust != null ? conversions.formatWindSpeed(windGust) : '--',
                ),
                _buildWindValue(
                  'Direction',
                  windDir != null
                      ? '${windDir.toStringAsFixed(0)}° ${conversions.getWindDirectionLabel(windDir)}'
                      : '--',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWindValue(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
      ],
    );
  }

  Widget _buildAtmosphericCard(dynamic observation, dynamic conversions) {
    final pressure = observation.stationPressure;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.compress, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Atmospheric',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    Text(
                      'Pressure',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      pressure != null ? conversions.formatPressure(pressure) : '--',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLightCard(dynamic observation) {
    final uv = observation.uvIndex;
    final solar = observation.solarRadiation;
    final lux = observation.illuminance;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.wb_sunny, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Light & UV',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatValue('UV Index', uv?.toStringAsFixed(1) ?? '--'),
                _buildStatValue(
                    'Solar', solar != null ? '${solar.toStringAsFixed(0)} W/m²' : '--'),
                _buildStatValue(
                    'Brightness', lux != null ? '${(lux / 1000).toStringAsFixed(1)} klux' : '--'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrecipCard(dynamic observation, dynamic conversions) {
    final rain = observation.rainAccumulated;
    final lightning = observation.lightningCount;
    final lightningDist = observation.lightningDistance;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.water_drop, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Precipitation & Lightning',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatValue(
                  'Rain Today',
                  rain != null ? conversions.formatRainfall(rain) : '--',
                ),
                _buildStatValue(
                  'Lightning',
                  lightning != null ? '$lightning strikes' : '--',
                ),
                _buildStatValue(
                  'Distance',
                  lightningDist != null
                      ? conversions.formatDistance(lightningDist * 1000)
                      : '--',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatValue(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
      ],
    );
  }

  Widget _buildLastUpdated(dynamic observation) {
    final timestamp = observation.timestamp;
    final age = DateTime.now().difference(timestamp);

    String ageText;
    if (age.inSeconds < 60) {
      ageText = '${age.inSeconds}s ago';
    } else if (age.inMinutes < 60) {
      ageText = '${age.inMinutes}m ago';
    } else {
      ageText = '${age.inHours}h ago';
    }

    return Text(
      'Last updated: $ageText',
      style: Theme.of(context).textTheme.bodySmall,
      textAlign: TextAlign.center,
    );
  }
}
