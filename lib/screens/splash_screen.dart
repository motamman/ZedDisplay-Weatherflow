import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/storage_service.dart';
import '../services/weatherflow_service.dart';
import 'setup_wizard_screen.dart';
import 'station_list_screen.dart';
import 'dashboard_screen.dart';

/// Splash screen that handles initial routing
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    // Give UI time to render
    await Future.delayed(const Duration(milliseconds: 500));

    if (!mounted) return;

    final storage = context.read<StorageService>();
    final weatherFlow = context.read<WeatherFlowService>();

    // Check if we have an API token
    final token = storage.apiToken;

    if (token == null || token.isEmpty) {
      // Go to setup wizard
      _navigateTo(const SetupWizardScreen());
      return;
    }

    // Initialize weather service
    await weatherFlow.initialize();

    // Check if we have a selected station
    if (weatherFlow.selectedStation == null) {
      // Fetch stations and go to station list
      await weatherFlow.fetchStations();
      _navigateTo(const StationListScreen(isInitialSetup: true));
    } else {
      // Go directly to dashboard
      _navigateTo(const DashboardScreen());
    }
  }

  void _navigateTo(Widget screen) {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // App icon - same as native splash for consistency
            Image.asset(
              'assets/app_icons/icon_crop_1024.png',
              width: 200,
              height: 200,
            ),
            const SizedBox(height: 24),
            Text(
              'ZedDisplay',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              '+Weatherflow',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
            const SizedBox(height: 48),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
