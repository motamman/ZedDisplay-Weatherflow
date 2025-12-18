import 'dart:math' as math;
import 'package:math_expressions/math_expressions.dart';
import 'unit_definitions.dart';

/// User preferences for unit display
class UnitPreferences {
  final String temperature; // '°C', '°F', 'K'
  final String pressure; // 'hPa', 'mbar', 'inHg', 'mmHg'
  final String windSpeed; // 'm/s', 'kn', 'km/h', 'mph', 'Bft'
  final String rainfall; // 'mm', 'in', 'cm'
  final String distance; // 'km', 'mi', 'nm', 'm'
  final String displayFormat; // '0', '0.0', '0.00'

  const UnitPreferences({
    this.temperature = '°C',
    this.pressure = 'hPa',
    this.windSpeed = 'kn',
    this.rainfall = 'mm',
    this.distance = 'km',
    this.displayFormat = '0.0',
  });

  /// Metric preset (SI units)
  static const metric = UnitPreferences(
    temperature: '°C',
    pressure: 'hPa',
    windSpeed: 'm/s',
    rainfall: 'mm',
    distance: 'km',
    displayFormat: '0.0',
  );

  /// Imperial US preset
  static const imperialUS = UnitPreferences(
    temperature: '°F',
    pressure: 'inHg',
    windSpeed: 'mph',
    rainfall: 'in',
    distance: 'mi',
    displayFormat: '0.0',
  );

  /// Nautical preset (for marine use)
  static const nautical = UnitPreferences(
    temperature: '°C',
    pressure: 'hPa',
    windSpeed: 'kn',
    rainfall: 'mm',
    distance: 'nm',
    displayFormat: '0.0',
  );

  /// Create preferences from JSON
  factory UnitPreferences.fromJson(Map<String, dynamic> json) {
    return UnitPreferences(
      temperature: json['temperature'] as String? ?? '°C',
      pressure: json['pressure'] as String? ?? 'hPa',
      windSpeed: json['windSpeed'] as String? ?? 'kn',
      rainfall: json['rainfall'] as String? ?? 'mm',
      distance: json['distance'] as String? ?? 'km',
      displayFormat: json['displayFormat'] as String? ?? '0.0',
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() => {
        'temperature': temperature,
        'pressure': pressure,
        'windSpeed': windSpeed,
        'rainfall': rainfall,
        'distance': distance,
        'displayFormat': displayFormat,
      };

  /// Create copy with modifications
  UnitPreferences copyWith({
    String? temperature,
    String? pressure,
    String? windSpeed,
    String? rainfall,
    String? distance,
    String? displayFormat,
  }) {
    return UnitPreferences(
      temperature: temperature ?? this.temperature,
      pressure: pressure ?? this.pressure,
      windSpeed: windSpeed ?? this.windSpeed,
      rainfall: rainfall ?? this.rainfall,
      distance: distance ?? this.distance,
      displayFormat: displayFormat ?? this.displayFormat,
    );
  }
}

/// Service for converting weather values between units
class ConversionService {
  final Parser _parser = Parser();
  final ContextModel _context = ContextModel();

  UnitPreferences _preferences;

  ConversionService({UnitPreferences? preferences})
      : _preferences = preferences ?? UnitPreferences.nautical;

  /// Get current preferences
  UnitPreferences get preferences => _preferences;

  /// Update preferences
  void setPreferences(UnitPreferences preferences) {
    _preferences = preferences;
  }

  /// Convert a value using a formula string
  /// Formula should use 'value' as the variable name
  double? evaluateFormula(String formula, double value) {
    try {
      // Handle special math functions
      String processedFormula = formula
          .replaceAll('pow(', '_pow(')
          .replaceAll('sqrt(', '_sqrt(')
          .replaceAll('abs(', '_abs(')
          .replaceAll('pi', '${math.pi}');

      // For simple formulas, use direct evaluation
      if (!processedFormula.contains('_pow') &&
          !processedFormula.contains('_sqrt') &&
          !processedFormula.contains('_abs')) {
        final expression = _parser.parse(processedFormula.replaceAll('value', '$value'));
        return expression.evaluate(EvaluationType.REAL, _context) as double;
      }

      // Handle pow function manually
      if (processedFormula.contains('_pow')) {
        // Extract pow arguments and evaluate
        final regex = RegExp(r'_pow\(([^,]+),\s*([^)]+)\)');
        final match = regex.firstMatch(processedFormula);
        if (match != null) {
          final base = _evaluateSimple(match.group(1)!.replaceAll('value', '$value'));
          final exp = _evaluateSimple(match.group(2)!.replaceAll('value', '$value'));
          if (base != null && exp != null) {
            final powResult = math.pow(base, exp);
            processedFormula = processedFormula.replaceFirst(
              regex,
              '$powResult',
            );
          }
        }
      }

      // Handle sqrt function manually
      if (processedFormula.contains('_sqrt')) {
        final regex = RegExp(r'_sqrt\(([^)]+)\)');
        final match = regex.firstMatch(processedFormula);
        if (match != null) {
          final arg = _evaluateSimple(match.group(1)!.replaceAll('value', '$value'));
          if (arg != null) {
            processedFormula = processedFormula.replaceFirst(
              regex,
              '${math.sqrt(arg)}',
            );
          }
        }
      }

      // Handle abs function manually
      if (processedFormula.contains('_abs')) {
        final regex = RegExp(r'_abs\(([^)]+)\)');
        final match = regex.firstMatch(processedFormula);
        if (match != null) {
          final arg = _evaluateSimple(match.group(1)!.replaceAll('value', '$value'));
          if (arg != null) {
            processedFormula = processedFormula.replaceFirst(
              regex,
              '${arg.abs()}',
            );
          }
        }
      }

      final expression = _parser.parse(processedFormula.replaceAll('value', '$value'));
      return expression.evaluate(EvaluationType.REAL, _context) as double;
    } catch (e) {
      return null;
    }
  }

  double? _evaluateSimple(String expr) {
    try {
      final expression = _parser.parse(expr);
      return expression.evaluate(EvaluationType.REAL, _context) as double;
    } catch (_) {
      return null;
    }
  }

  /// Convert a temperature value to the user's preferred unit
  double? convertTemperature(double kelvin) {
    final conversion = WeatherUnits.temperature.getConversion(_preferences.temperature);
    if (conversion == null) return kelvin;
    return evaluateFormula(conversion.formula, kelvin);
  }

  /// Convert a pressure value to the user's preferred unit
  double? convertPressure(double pascals) {
    final conversion = WeatherUnits.pressure.getConversion(_preferences.pressure);
    if (conversion == null) return pascals;
    return evaluateFormula(conversion.formula, pascals);
  }

  /// Convert a wind speed value to the user's preferred unit
  double? convertWindSpeed(double metersPerSecond) {
    final conversion = WeatherUnits.windSpeed.getConversion(_preferences.windSpeed);
    if (conversion == null) return metersPerSecond;
    return evaluateFormula(conversion.formula, metersPerSecond);
  }

  /// Convert a rainfall value to the user's preferred unit
  double? convertRainfall(double meters) {
    final conversion = WeatherUnits.rainfall.getConversion(_preferences.rainfall);
    if (conversion == null) return meters;
    return evaluateFormula(conversion.formula, meters);
  }

  /// Convert a distance value to the user's preferred unit
  double? convertDistance(double meters) {
    final conversion = WeatherUnits.distance.getConversion(_preferences.distance);
    if (conversion == null) return meters;
    return evaluateFormula(conversion.formula, meters);
  }

  /// Convert humidity ratio to percentage
  double convertHumidity(double ratio) {
    return ratio * 100;
  }

  /// Convert probability ratio to percentage
  double convertProbability(double ratio) {
    return ratio * 100;
  }

  /// Get the symbol for temperature unit
  String get temperatureSymbol => _preferences.temperature;

  /// Get the symbol for pressure unit
  String get pressureSymbol => _preferences.pressure;

  /// Get the symbol for wind speed unit
  String get windSpeedSymbol => _preferences.windSpeed;

  /// Get the symbol for rainfall unit
  String get rainfallSymbol => _preferences.rainfall;

  /// Get the symbol for distance unit
  String get distanceSymbol => _preferences.distance;

  /// Format a number according to display preferences
  String formatNumber(double value, {String? format}) {
    final fmt = format ?? _preferences.displayFormat;
    final decimalPlaces = fmt.contains('.') ? fmt.split('.')[1].length : 0;
    return value.toStringAsFixed(decimalPlaces);
  }

  /// Format temperature with unit
  String formatTemperature(double kelvin, {String? format}) {
    final converted = convertTemperature(kelvin);
    if (converted == null) return '--';
    return '${formatNumber(converted, format: format)}$temperatureSymbol';
  }

  /// Format pressure with unit
  String formatPressure(double pascals, {String? format}) {
    final converted = convertPressure(pascals);
    if (converted == null) return '--';
    return '${formatNumber(converted, format: format)} $pressureSymbol';
  }

  /// Format wind speed with unit
  String formatWindSpeed(double metersPerSecond, {String? format}) {
    final converted = convertWindSpeed(metersPerSecond);
    if (converted == null) return '--';
    return '${formatNumber(converted, format: format)} $windSpeedSymbol';
  }

  /// Format rainfall with unit
  String formatRainfall(double meters, {String? format}) {
    final converted = convertRainfall(meters);
    if (converted == null) return '--';
    return '${formatNumber(converted, format: format)} $rainfallSymbol';
  }

  /// Format distance with unit
  String formatDistance(double meters, {String? format}) {
    final converted = convertDistance(meters);
    if (converted == null) return '--';
    return '${formatNumber(converted, format: format)} $distanceSymbol';
  }

  /// Format humidity as percentage
  String formatHumidity(double ratio, {String? format}) {
    return '${formatNumber(convertHumidity(ratio), format: format ?? '0')}%';
  }

  /// Format probability as percentage
  String formatProbability(double ratio, {String? format}) {
    return '${formatNumber(convertProbability(ratio), format: format ?? '0')}%';
  }

  /// Get wind direction as compass point
  String getWindDirectionLabel(double degrees) {
    const directions = [
      'N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE',
      'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW'
    ];
    final index = ((degrees + 11.25) % 360 / 22.5).floor();
    return directions[index];
  }
}
