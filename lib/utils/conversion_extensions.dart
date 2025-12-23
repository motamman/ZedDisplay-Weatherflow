/// Extensions for ConversionService
/// Adds missing methods needed by the spinner from OpenMeteo

import 'package:weatherflow_core/weatherflow_core.dart';

/// Extension to add OpenMeteo-compatible methods to ConversionService
extension ConversionServiceExtensions on ConversionService {
  /// Format wave height for display (meters or feet based on distance unit)
  String formatWaveHeight(double meters) {
    // Use distance preference to determine feet vs meters
    final distanceUnit = preferences.distance;
    if (distanceUnit == 'mi' || distanceUnit == 'nm') {
      // Convert to feet
      final feet = meters * 3.28084;
      return '${feet.toStringAsFixed(1)} ft';
    }
    return '${meters.toStringAsFixed(1)} m';
  }

  /// Convert wind speed from m/s to user preference
  double convertWindSpeedFromMps(double mps) {
    final unit = preferences.windSpeed;
    switch (unit) {
      case 'kn':
        return mps * 1.94384;
      case 'mph':
        return mps * 2.23694;
      case 'km/h':
        return mps * 3.6;
      case 'm/s':
      default:
        return mps;
    }
  }

  /// Convert temperature from Kelvin to user preference
  double convertTemperatureFromKelvin(double kelvin) {
    final unit = preferences.temperature;
    switch (unit) {
      case '°F':
        return (kelvin - 273.15) * 9 / 5 + 32;
      case 'K':
        return kelvin;
      case '°C':
      default:
        return kelvin - 273.15;
    }
  }

  /// Convert probability from ratio (0-1) to percentage (0-100)
  /// This is a pass-through since WeatherFlow already provides percentages
  double convertProbabilityFromRatio(double ratio) {
    // OpenMeteo provides 0-1, but WeatherFlow provides 0-100
    // If value > 1, assume it's already a percentage
    if (ratio > 1) return ratio;
    return ratio * 100;
  }

  /// Convert humidity from ratio (0-1) to percentage (0-100)
  /// This is a pass-through since WeatherFlow already provides percentages
  double convertHumidityFromRatio(double ratio) {
    // OpenMeteo provides 0-1, but WeatherFlow provides 0-100
    // If value > 1, assume it's already a percentage
    if (ratio > 1) return ratio;
    return ratio * 100;
  }

  /// Convert pressure from Pascals to user preference
  double convertPressureFromPascals(double pascals) {
    // Convert to hPa (millibars) first
    final hPa = pascals / 100;
    final unit = preferences.pressure;
    switch (unit) {
      case 'inHg':
        return hPa * 0.02953;
      case 'mmHg':
        return hPa * 0.750062;
      case 'hPa':
      case 'mb':
      default:
        return hPa;
    }
  }

  /// Convert pressure from hPa/mb to user preference
  double convertPressureFromHpa(double hPa) {
    final unit = preferences.pressure;
    switch (unit) {
      case 'inHg':
        return hPa * 0.02953;
      case 'mmHg':
        return hPa * 0.750062;
      case 'hPa':
      case 'mb':
      default:
        return hPa;
    }
  }
}
