/// Unit definitions for WeatherFlow data conversions
/// Based on signalk-units-preference patterns

/// Categories of measurements
enum MeasurementCategory {
  temperature,
  pressure,
  speed,
  distance,
  angle,
  percentage,
  illuminance,
  power,
  voltage,
  length, // for rainfall
}

/// A single unit conversion definition
class UnitConversion {
  final String symbol;
  final String longName;
  final String formula; // formula using 'value' as variable
  final String inverseFormula; // reverse conversion

  const UnitConversion({
    required this.symbol,
    required this.longName,
    required this.formula,
    required this.inverseFormula,
  });
}

/// Base unit definition with all available conversions
class UnitDefinition {
  final String baseUnit;
  final MeasurementCategory category;
  final Map<String, UnitConversion> conversions;

  const UnitDefinition({
    required this.baseUnit,
    required this.category,
    required this.conversions,
  });

  /// Get all available target units
  List<String> get targetUnits => conversions.keys.toList();

  /// Get conversion to target unit
  UnitConversion? getConversion(String targetUnit) => conversions[targetUnit];
}

/// Built-in unit definitions for weather measurements
/// All base units are SI (Kelvin, Pascals, m/s, meters, etc.)
class WeatherUnits {
  static const temperature = UnitDefinition(
    baseUnit: 'K',
    category: MeasurementCategory.temperature,
    conversions: {
      '°C': UnitConversion(
        symbol: '°C',
        longName: 'Celsius',
        formula: 'value - 273.15',
        inverseFormula: 'value + 273.15',
      ),
      '°F': UnitConversion(
        symbol: '°F',
        longName: 'Fahrenheit',
        formula: '(value - 273.15) * 9/5 + 32',
        inverseFormula: '(value - 32) * 5/9 + 273.15',
      ),
      'K': UnitConversion(
        symbol: 'K',
        longName: 'Kelvin',
        formula: 'value',
        inverseFormula: 'value',
      ),
    },
  );

  static const pressure = UnitDefinition(
    baseUnit: 'Pa',
    category: MeasurementCategory.pressure,
    conversions: {
      'hPa': UnitConversion(
        symbol: 'hPa',
        longName: 'hectopascals',
        formula: 'value / 100',
        inverseFormula: 'value * 100',
      ),
      'mbar': UnitConversion(
        symbol: 'mbar',
        longName: 'millibars',
        formula: 'value / 100',
        inverseFormula: 'value * 100',
      ),
      'inHg': UnitConversion(
        symbol: 'inHg',
        longName: 'inches of mercury',
        formula: 'value * 0.00029530',
        inverseFormula: 'value / 0.00029530',
      ),
      'mmHg': UnitConversion(
        symbol: 'mmHg',
        longName: 'millimeters of mercury',
        formula: 'value * 0.00750062',
        inverseFormula: 'value / 0.00750062',
      ),
      'Pa': UnitConversion(
        symbol: 'Pa',
        longName: 'pascals',
        formula: 'value',
        inverseFormula: 'value',
      ),
    },
  );

  static const windSpeed = UnitDefinition(
    baseUnit: 'm/s',
    category: MeasurementCategory.speed,
    conversions: {
      'kn': UnitConversion(
        symbol: 'kn',
        longName: 'knots',
        formula: 'value * 1.94384',
        inverseFormula: 'value / 1.94384',
      ),
      'km/h': UnitConversion(
        symbol: 'km/h',
        longName: 'kilometers per hour',
        formula: 'value * 3.6',
        inverseFormula: 'value / 3.6',
      ),
      'mph': UnitConversion(
        symbol: 'mph',
        longName: 'miles per hour',
        formula: 'value * 2.23694',
        inverseFormula: 'value / 2.23694',
      ),
      'm/s': UnitConversion(
        symbol: 'm/s',
        longName: 'meters per second',
        formula: 'value',
        inverseFormula: 'value',
      ),
      'Bft': UnitConversion(
        symbol: 'Bft',
        longName: 'Beaufort scale',
        // Approximation using standard Beaufort formula
        formula: 'pow(value / 0.836, 2/3)',
        inverseFormula: '0.836 * pow(value, 3/2)',
      ),
    },
  );

  static const rainfall = UnitDefinition(
    baseUnit: 'm',
    category: MeasurementCategory.length,
    conversions: {
      'mm': UnitConversion(
        symbol: 'mm',
        longName: 'millimeters',
        formula: 'value * 1000',
        inverseFormula: 'value / 1000',
      ),
      'in': UnitConversion(
        symbol: 'in',
        longName: 'inches',
        formula: 'value * 39.3701',
        inverseFormula: 'value / 39.3701',
      ),
      'cm': UnitConversion(
        symbol: 'cm',
        longName: 'centimeters',
        formula: 'value * 100',
        inverseFormula: 'value / 100',
      ),
      'm': UnitConversion(
        symbol: 'm',
        longName: 'meters',
        formula: 'value',
        inverseFormula: 'value',
      ),
    },
  );

  static const distance = UnitDefinition(
    baseUnit: 'm',
    category: MeasurementCategory.distance,
    conversions: {
      'km': UnitConversion(
        symbol: 'km',
        longName: 'kilometers',
        formula: 'value / 1000',
        inverseFormula: 'value * 1000',
      ),
      'mi': UnitConversion(
        symbol: 'mi',
        longName: 'miles',
        formula: 'value / 1609.344',
        inverseFormula: 'value * 1609.344',
      ),
      'nm': UnitConversion(
        symbol: 'nm',
        longName: 'nautical miles',
        formula: 'value / 1852',
        inverseFormula: 'value * 1852',
      ),
      'ft': UnitConversion(
        symbol: 'ft',
        longName: 'feet',
        formula: 'value * 3.28084',
        inverseFormula: 'value / 3.28084',
      ),
      'm': UnitConversion(
        symbol: 'm',
        longName: 'meters',
        formula: 'value',
        inverseFormula: 'value',
      ),
    },
  );

  static const angle = UnitDefinition(
    baseUnit: 'rad',
    category: MeasurementCategory.angle,
    conversions: {
      '°': UnitConversion(
        symbol: '°',
        longName: 'degrees',
        formula: 'value * 180 / 3.14159265359',
        inverseFormula: 'value * 3.14159265359 / 180',
      ),
      'rad': UnitConversion(
        symbol: 'rad',
        longName: 'radians',
        formula: 'value',
        inverseFormula: 'value',
      ),
    },
  );

  static const percentage = UnitDefinition(
    baseUnit: 'ratio',
    category: MeasurementCategory.percentage,
    conversions: {
      '%': UnitConversion(
        symbol: '%',
        longName: 'percent',
        formula: 'value * 100',
        inverseFormula: 'value / 100',
      ),
      'ratio': UnitConversion(
        symbol: '',
        longName: 'ratio',
        formula: 'value',
        inverseFormula: 'value',
      ),
    },
  );

  static const illuminance = UnitDefinition(
    baseUnit: 'lux',
    category: MeasurementCategory.illuminance,
    conversions: {
      'lux': UnitConversion(
        symbol: 'lux',
        longName: 'lux',
        formula: 'value',
        inverseFormula: 'value',
      ),
      'klux': UnitConversion(
        symbol: 'klux',
        longName: 'kilolux',
        formula: 'value / 1000',
        inverseFormula: 'value * 1000',
      ),
    },
  );

  static const solarRadiation = UnitDefinition(
    baseUnit: 'W/m²',
    category: MeasurementCategory.power,
    conversions: {
      'W/m²': UnitConversion(
        symbol: 'W/m²',
        longName: 'watts per square meter',
        formula: 'value',
        inverseFormula: 'value',
      ),
    },
  );

  static const voltage = UnitDefinition(
    baseUnit: 'V',
    category: MeasurementCategory.voltage,
    conversions: {
      'V': UnitConversion(
        symbol: 'V',
        longName: 'volts',
        formula: 'value',
        inverseFormula: 'value',
      ),
      'mV': UnitConversion(
        symbol: 'mV',
        longName: 'millivolts',
        formula: 'value * 1000',
        inverseFormula: 'value / 1000',
      ),
    },
  );

  /// Get unit definition for a measurement field
  static UnitDefinition? getDefinitionForField(String field) {
    switch (field.toLowerCase()) {
      case 'temperature':
      case 'temp':
      case 'air_temperature':
      case 'feels_like':
      case 'dew_point':
      case 'heat_index':
      case 'wind_chill':
        return temperature;

      case 'pressure':
      case 'station_pressure':
      case 'sea_level_pressure':
        return pressure;

      case 'wind':
      case 'wind_avg':
      case 'wind_gust':
      case 'wind_lull':
      case 'wind_speed':
        return windSpeed;

      case 'rain':
      case 'rain_accumulated':
      case 'precip':
      case 'precipitation':
        return rainfall;

      case 'distance':
      case 'lightning_distance':
        return distance;

      case 'direction':
      case 'wind_direction':
        return angle;

      case 'humidity':
      case 'relative_humidity':
      case 'precip_probability':
        return percentage;

      case 'illuminance':
      case 'brightness':
        return illuminance;

      case 'solar_radiation':
        return solarRadiation;

      case 'battery':
      case 'battery_voltage':
        return voltage;

      default:
        return null;
    }
  }
}
