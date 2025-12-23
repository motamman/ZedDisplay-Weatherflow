import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/storage_service.dart';
import 'services/weatherflow_service.dart';
import 'services/nws_alert_service.dart';
import 'services/tool_registry.dart';
import 'services/tool_service.dart';
import 'services/dashboard_service.dart';
import 'screens/splash_screen.dart';

// Tool imports - register all available tools
import 'widgets/tools/current_conditions_tool.dart';
import 'widgets/tools/wind_tool.dart';
import 'widgets/tools/weather_api_spinner_tool.dart';
import 'widgets/tools/weatherflow_forecast_tool.dart';
import 'widgets/tools/weather_alerts_tool.dart';
import 'widgets/tools/sun_moon_arc_tool.dart';

// Service imports for activity scoring and solar
import 'services/activity_score_service.dart';
import 'services/solar_calculation_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize storage service
  final storage = StorageService();
  await storage.initialize();

  // Initialize tool registry and register tools
  final toolRegistry = ToolRegistry();
  _registerTools(toolRegistry);

  runApp(
    MultiProvider(
      providers: [
        // Storage
        ChangeNotifierProvider.value(value: storage),

        // Tool Registry (singleton)
        ChangeNotifierProvider.value(value: toolRegistry),

        // Tool Service
        ChangeNotifierProxyProvider<StorageService, ToolService>(
          create: (context) => ToolService(context.read<StorageService>()),
          update: (context, storage, previous) =>
              previous ?? ToolService(storage),
        ),

        // Dashboard Service
        ChangeNotifierProxyProvider2<StorageService, ToolService, DashboardService>(
          create: (context) => DashboardService(
            context.read<StorageService>(),
            context.read<ToolService>(),
          ),
          update: (context, storage, toolService, previous) =>
              previous ?? DashboardService(storage, toolService),
        ),

        // WeatherFlow Service
        ChangeNotifierProxyProvider<StorageService, WeatherFlowService>(
          create: (context) => WeatherFlowService(
            storage: context.read<StorageService>(),
          ),
          update: (context, storage, previous) =>
              previous ?? WeatherFlowService(storage: storage),
        ),

        // NWS Alert Service (shared across all tools)
        ChangeNotifierProxyProvider<WeatherFlowService, NWSAlertService>(
          create: (context) => NWSAlertService(),
          update: (context, weatherFlow, previous) {
            final service = previous ?? NWSAlertService();
            // Update station location when it changes
            final station = weatherFlow.selectedStation;
            if (station != null) {
              service.setStationLocation(station.latitude, station.longitude);
            }
            return service;
          },
        ),

        // Activity Score Service
        ChangeNotifierProxyProvider2<StorageService, WeatherFlowService, ActivityScoreService>(
          create: (context) => ActivityScoreService(),
          update: (context, storage, weatherFlow, previous) {
            final service = previous ?? ActivityScoreService();
            service.initialize(storage, weatherFlow);
            return service;
          },
        ),

        // Solar Calculation Service
        ChangeNotifierProvider<SolarCalculationService>(
          create: (context) => SolarCalculationService(),
        ),
      ],
      child: const WeatherFlowApp(),
    ),
  );
}

/// Register all available tool builders
void _registerTools(ToolRegistry registry) {
  registry.register('current_conditions', CurrentConditionsToolBuilder());
  registry.register('wind', WindToolBuilder());
  registry.register('weather_api_spinner', WeatherApiSpinnerToolBuilder());
  registry.register('weatherflow_forecast', WeatherFlowForecastToolBuilder());
  registry.register('weather_alerts', WeatherAlertsToolBuilder());
  registry.register('sun_moon_arc', SunMoonArcToolBuilder());
  // Add more tools here as they are created:
  // registry.register('lightning', LightningToolBuilder());
  // registry.register('rain', RainToolBuilder());
  // registry.register('uv_solar', UvSolarToolBuilder());
  // registry.register('pressure', PressureToolBuilder());
}

class WeatherFlowApp extends StatelessWidget {
  const WeatherFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();

    return MaterialApp(
      title: 'ZedDisplay WeatherFlow',
      debugShowCheckedModeBanner: false,
      themeMode: _getThemeMode(storage.themeMode),
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
        ),
      ),
      home: const SplashScreen(),
    );
  }

  ThemeMode _getThemeMode(String mode) {
    switch (mode) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }
}
