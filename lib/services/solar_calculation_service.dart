import 'package:flutter/material.dart';
import '../widgets/forecast_models.dart';

/// Service for solar energy calculations
/// Holds system-wide solar panel configuration that both spinner and solar widget use
class SolarCalculationService extends ChangeNotifier {
  // Standard Test Conditions: 1000 W/m² at 25°C = 100% rated output
  static const double stcIrradiance = 1000.0;

  // Default values
  static const double defaultPanelMaxWatts = 200.0;
  static const double defaultSystemDerate = 0.85;
  static const double defaultPanelTilt = 30.0;
  static const double defaultPanelAzimuth = 180.0;

  // System-wide panel configuration
  double _panelMaxWatts = defaultPanelMaxWatts;
  double _systemDerate = defaultSystemDerate;
  double _panelTilt = defaultPanelTilt;
  double _panelAzimuth = defaultPanelAzimuth;

  // Getters
  double get panelMaxWatts => _panelMaxWatts;
  double get systemDerate => _systemDerate;
  double get panelTilt => _panelTilt;
  double get panelAzimuth => _panelAzimuth;

  /// Update panel max watts
  void setPanelMaxWatts(double value) {
    if (value > 0 && value != _panelMaxWatts) {
      _panelMaxWatts = value;
      notifyListeners();
    }
  }

  /// Update system derate factor
  void setSystemDerate(double value) {
    if (value > 0 && value <= 1.0 && value != _systemDerate) {
      _systemDerate = value;
      notifyListeners();
    }
  }

  /// Update panel tilt
  void setPanelTilt(double value) {
    if (value >= 0 && value <= 90 && value != _panelTilt) {
      _panelTilt = value;
      notifyListeners();
    }
  }

  /// Update panel azimuth
  void setPanelAzimuth(double value) {
    if (value >= -180 && value <= 180 && value != _panelAzimuth) {
      _panelAzimuth = value;
      notifyListeners();
    }
  }

  /// Update all values at once
  void updateConfig({
    double? panelMaxWatts,
    double? systemDerate,
    double? panelTilt,
    double? panelAzimuth,
  }) {
    bool changed = false;

    if (panelMaxWatts != null && panelMaxWatts > 0 && panelMaxWatts != _panelMaxWatts) {
      _panelMaxWatts = panelMaxWatts;
      changed = true;
    }
    if (systemDerate != null && systemDerate > 0 && systemDerate <= 1.0 && systemDerate != _systemDerate) {
      _systemDerate = systemDerate;
      changed = true;
    }
    if (panelTilt != null && panelTilt >= 0 && panelTilt <= 90 && panelTilt != _panelTilt) {
      _panelTilt = panelTilt;
      changed = true;
    }
    if (panelAzimuth != null && panelAzimuth >= -180 && panelAzimuth <= 180 && panelAzimuth != _panelAzimuth) {
      _panelAzimuth = panelAzimuth;
      changed = true;
    }

    if (changed) {
      notifyListeners();
    }
  }

  /// Load config from storage
  void loadFromStorage(Map<String, dynamic>? config) {
    if (config == null) return;

    _panelMaxWatts = (config['panelMaxWatts'] as num?)?.toDouble() ?? defaultPanelMaxWatts;
    _systemDerate = (config['systemDerate'] as num?)?.toDouble() ?? defaultSystemDerate;
    _panelTilt = (config['panelTilt'] as num?)?.toDouble() ?? defaultPanelTilt;
    _panelAzimuth = (config['panelAzimuth'] as num?)?.toDouble() ?? defaultPanelAzimuth;
    notifyListeners();
  }

  /// Export config for storage
  Map<String, dynamic> toJson() => {
    'panelMaxWatts': _panelMaxWatts,
    'systemDerate': _systemDerate,
    'panelTilt': _panelTilt,
    'panelAzimuth': _panelAzimuth,
  };

  /// Calculate instantaneous power output using service's panel config
  double calculatePower({required double irradiance}) {
    if (irradiance <= 0 || _panelMaxWatts <= 0) return 0.0;
    return (irradiance / stcIrradiance) * _panelMaxWatts * _systemDerate;
  }

  /// Static: Calculate instantaneous power output from irradiance
  static double calculateInstantPower({
    required double irradiance,
    required double maxWatts,
    double systemDerate = 0.85,
  }) {
    if (irradiance <= 0 || maxWatts <= 0) return 0.0;
    return (irradiance / stcIrradiance) * maxWatts * systemDerate;
  }

  /// Static version: Get output at a specific hour offset
  static ({double irradiance, double watts})? getOutputAtOffset({
    required List<HourlyForecast> hourlyForecasts,
    required int hourOffset,
    required double maxWatts,
    double systemDerate = 0.85,
  }) {
    if (hourOffset < 0 || hourOffset >= hourlyForecasts.length) {
      return null;
    }

    final forecast = hourlyForecasts[hourOffset];
    final irradiance = getBestIrradiance(forecast);
    final watts = calculateInstantPower(
      irradiance: irradiance,
      maxWatts: maxWatts,
      systemDerate: systemDerate,
    );

    return (irradiance: irradiance, watts: watts);
  }

  /// Static version: Get hourly power forecast
  static List<({DateTime time, double watts, double irradiance})> getHourlyPowerForecast({
    required List<HourlyForecast> hourlyForecasts,
    required double maxWatts,
    double systemDerate = 0.85,
    SunMoonTimes? sunMoonTimes,
    int hoursToShow = 24,
  }) {
    final result = <({DateTime time, double watts, double irradiance})>[];
    final now = DateTime.now();
    final locationNow = sunMoonTimes?.toLocationTime(now) ?? now;

    int count = 0;
    for (final forecast in hourlyForecasts) {
      if (count >= hoursToShow) break;
      if (forecast.time == null) continue;

      // API times are already in location's timezone - don't double-convert
      final forecastTime = forecast.time!;

      if (forecastTime.isBefore(locationNow.subtract(const Duration(hours: 1)))) {
        continue;
      }

      final irradiance = getBestIrradiance(forecast);
      final isDay = forecast.isDay ?? (irradiance > 0);

      if (isDay || irradiance > 0) {
        final watts = calculateInstantPower(
          irradiance: irradiance,
          maxWatts: maxWatts,
          systemDerate: systemDerate,
        );
        result.add((time: forecastTime, watts: watts, irradiance: irradiance));
      }
      count++;
    }

    return result;
  }

  /// Static version: Get hourly power for a specific date
  static List<({DateTime time, double watts, double irradiance})> getHourlyPowerForDate({
    required List<HourlyForecast> hourlyForecasts,
    required DateTime date,
    required double maxWatts,
    double systemDerate = 0.85,
    SunMoonTimes? sunMoonTimes,
    bool includeAllHours = false,
  }) {
    final targetDay = DateTime(date.year, date.month, date.day);
    final Map<int, ({double watts, double irradiance})> hourData = {};

    for (final forecast in hourlyForecasts) {
      if (forecast.time == null) continue;

      // API times are already in location's timezone - don't double-convert
      final forecastTime = forecast.time!;
      final forecastDay = DateTime(forecastTime.year, forecastTime.month, forecastTime.day);

      if (forecastDay != targetDay) continue;

      final irradiance = getBestIrradiance(forecast);
      final watts = calculateInstantPower(
        irradiance: irradiance,
        maxWatts: maxWatts,
        systemDerate: systemDerate,
      );

      hourData[forecastTime.hour] = (watts: watts, irradiance: irradiance);
    }

    if (includeAllHours) {
      // Use sunrise/sunset to limit chart to daylight hours only
      final sunriseHour = sunMoonTimes?.sunrise?.hour ?? 6;
      final sunsetHour = sunMoonTimes?.sunset?.hour ?? 20;

      final result = <({DateTime time, double watts, double irradiance})>[];
      for (int hour = sunriseHour; hour <= sunsetHour; hour++) {
        final time = DateTime(targetDay.year, targetDay.month, targetDay.day, hour);
        final data = hourData[hour];
        result.add((
          time: time,
          watts: data?.watts ?? 0.0,
          irradiance: data?.irradiance ?? 0.0,
        ));
      }
      return result;
    }

    final result = <({DateTime time, double watts, double irradiance})>[];
    final sortedHours = hourData.keys.toList()..sort();
    for (final hour in sortedHours) {
      final time = DateTime(targetDay.year, targetDay.month, targetDay.day, hour);
      final data = hourData[hour]!;
      result.add((time: time, watts: data.watts, irradiance: data.irradiance));
    }
    return result;
  }

  /// Static version: Get daily summaries
  static List<({DateTime date, double kWh, double peakWatts, DateTime? peakTime})> getDailySummaries({
    required List<HourlyForecast> hourlyForecasts,
    required double maxWatts,
    double systemDerate = 0.85,
    SunMoonTimes? sunMoonTimes,
    int maxDays = 7,
  }) {
    final result = <({DateTime date, double kWh, double peakWatts, DateTime? peakTime})>[];
    final Map<DateTime, List<HourlyForecast>> byDay = {};

    for (final forecast in hourlyForecasts) {
      if (forecast.time == null) continue;

      final forecastTime = sunMoonTimes?.toLocationTime(forecast.time!) ?? forecast.time!;
      final day = DateTime(forecastTime.year, forecastTime.month, forecastTime.day);

      byDay.putIfAbsent(day, () => []);
      byDay[day]!.add(forecast);
    }

    final sortedDays = byDay.keys.toList()..sort();

    for (int i = 0; i < sortedDays.length && i < maxDays; i++) {
      final day = sortedDays[i];
      final forecasts = byDay[day]!;

      double totalWh = 0.0;
      double peakWatts = 0.0;
      DateTime? peakTime;

      for (final forecast in forecasts) {
        final irradiance = getBestIrradiance(forecast);
        final watts = calculateInstantPower(
          irradiance: irradiance,
          maxWatts: maxWatts,
          systemDerate: systemDerate,
        );

        totalWh += watts;

        if (watts > peakWatts) {
          peakWatts = watts;
          peakTime = sunMoonTimes?.toLocationTime(forecast.time!) ?? forecast.time;
        }
      }

      result.add((
        date: day,
        kWh: totalWh / 1000.0,
        peakWatts: peakWatts,
        peakTime: peakTime,
      ));
    }

    return result;
  }

  /// Calculate daily kWh potential from hourly forecasts
  double calculateDailyKwh({
    required List<HourlyForecast> hourlyForecasts,
    bool todayOnly = true,
    SunMoonTimes? sunMoonTimes,
  }) {
    if (hourlyForecasts.isEmpty || _panelMaxWatts <= 0) return 0.0;

    double totalWh = 0.0;
    final now = DateTime.now();
    final locationNow = sunMoonTimes?.toLocationTime(now) ?? now;
    final today = DateTime(locationNow.year, locationNow.month, locationNow.day);

    for (final forecast in hourlyForecasts) {
      final irradiance = forecast.globalTiltedIrradiance ??
          forecast.shortwaveRadiation ??
          0.0;

      if (irradiance <= 0) continue;

      if (todayOnly && forecast.time != null) {
        final forecastTime = sunMoonTimes?.toLocationTime(forecast.time!) ?? forecast.time!;
        final forecastDay = DateTime(forecastTime.year, forecastTime.month, forecastTime.day);
        if (forecastDay != today) continue;
      }

      totalWh += calculatePower(irradiance: irradiance);
    }

    return totalWh / 1000.0;
  }

  /// Get radiation intensity label
  static String getRadiationLabel(double wm2) {
    if (wm2 < 50) return 'Negligible';
    if (wm2 < 200) return 'Low';
    if (wm2 < 400) return 'Moderate';
    if (wm2 < 600) return 'Good';
    if (wm2 < 800) return 'Very Good';
    if (wm2 < 1000) return 'Excellent';
    return 'Peak';
  }

  /// Get color for radiation intensity level
  static Color getRadiationColor(double wm2) {
    if (wm2 < 50) return Colors.grey;
    if (wm2 < 200) return Colors.blue.shade300;
    if (wm2 < 400) return Colors.green;
    if (wm2 < 600) return Colors.yellow.shade700;
    if (wm2 < 800) return Colors.orange;
    if (wm2 < 1000) return Colors.deepOrange;
    return Colors.red;
  }

  /// Get the best available irradiance value from forecast
  static double getBestIrradiance(HourlyForecast forecast) {
    return forecast.globalTiltedIrradiance ??
        forecast.shortwaveRadiation ??
        0.0;
  }

  /// Calculate the percentage of max possible output
  static double getOutputPercentage(double irradiance) {
    if (irradiance <= 0) return 0.0;
    return (irradiance / stcIrradiance) * 100.0;
  }

  /// Calculate daily kWh from Open-Meteo's shortwave_radiation_sum (uses service config)
  double calculateDailyKwhFromSum({
    required double radiationSumMJ,
    double assumedDaylightHours = 10.0,
  }) {
    if (radiationSumMJ <= 0 || _panelMaxWatts <= 0) return 0.0;

    final whPerSqM = radiationSumMJ * 277.78;
    final avgIrradiance = whPerSqM / assumedDaylightHours;
    final avgPower = calculatePower(irradiance: avgIrradiance);
    final totalWh = avgPower * assumedDaylightHours;

    return totalWh / 1000.0;
  }
}
