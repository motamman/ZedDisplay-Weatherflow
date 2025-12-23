/// Marine data stub types
/// WeatherFlow doesn't provide marine data, so these are placeholder types
/// that allow the OpenMeteo code to compile but return "N/A" values

/// Marine data container (stub)
class MarineData {
  final List<HourlyMarine> hourly;
  final DateTime fetchedAt;

  MarineData({this.hourly = const [], DateTime? fetchedAt})
      : fetchedAt = fetchedAt ?? DateTime.now();

  /// WeatherFlow doesn't have marine data
  bool get isEmpty => true;

  /// Check if data is stale (older than given duration)
  bool isStale(Duration maxAge) {
    return DateTime.now().difference(fetchedAt) > maxAge;
  }
}

/// Hourly marine data entry (stub)
class HourlyMarine {
  final DateTime time;
  final double? waveHeight;
  final double? wavePeriod;
  final double? waveDirection;
  final double? swellWaveHeight;
  final double? swellWaveDirection;
  final double? swellWavePeriod;
  final int? douglas; // Douglas sea state scale

  const HourlyMarine({
    required this.time,
    this.waveHeight,
    this.wavePeriod,
    this.waveDirection,
    this.swellWaveHeight,
    this.swellWaveDirection,
    this.swellWavePeriod,
    this.douglas,
  });
}
