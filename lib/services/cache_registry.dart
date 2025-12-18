/// Cache Registry - Inventory of all data caches in the app
/// Reference this when adding new caches or debugging cache issues

import 'package:flutter/foundation.dart';
import 'storage_service.dart';
import 'weatherflow_service.dart';

/// All cache types in the app
enum CacheType {
  /// Station list and details
  /// Key: stationId, Source: REST API
  /// Refreshed: app startup, manual refresh, API token change
  stations,

  /// Current weather observation per device
  /// Key: deviceId, Source: REST API, WebSocket, UDP
  /// Refreshed: station switch, websocket msg, UDP msg, REST poll (60s)
  observations,

  /// Hourly forecast per station (up to 72 hours)
  /// Key: stationId, Source: REST API
  /// Refreshed: station switch, refresh button, REST poll (30m)
  hourlyForecasts,

  /// Daily forecast per station (up to 10 days)
  /// Key: stationId, Source: REST API
  /// Refreshed: station switch, refresh button, REST poll (30m)
  dailyForecasts,
}

/// Data source types
enum DataSourceType {
  restApi,
  websocket,
  udp,
  cache,
}

/// Cache entry metadata
class CacheMetadata {
  final CacheType type;
  final String key;
  final DataSourceType source;
  final DateTime cachedAt;
  final Duration? maxAge;

  const CacheMetadata({
    required this.type,
    required this.key,
    required this.source,
    required this.cachedAt,
    this.maxAge,
  });

  bool get isExpired {
    if (maxAge == null) return false;
    return DateTime.now().difference(cachedAt) > maxAge!;
  }

  Duration get age => DateTime.now().difference(cachedAt);
}

/// Definition of a cached data source
class CachedDataSource {
  final CacheType cacheType;
  final String dataType;
  final List<DataSourceType> sources;
  final String keyPattern;
  final Duration maxAge;
  final String hiveBox;

  const CachedDataSource({
    required this.cacheType,
    required this.dataType,
    required this.sources,
    required this.keyPattern,
    required this.maxAge,
    required this.hiveBox,
  });
}

/// Static inventory of all cached data sources in the app
/// Use this list programmatically to know all cache sources
class CachedDataSources {
  CachedDataSources._();

  /// All cached data sources - reference this list when you need to
  /// know what data is cached and how to refresh it
  static const List<CachedDataSource> all = [
    CachedDataSource(
      cacheType: CacheType.stations,
      dataType: 'Stations',
      sources: [DataSourceType.restApi],
      keyPattern: '{stationId}',
      maxAge: Duration(hours: 24),
      hiveBox: 'stations',
    ),
    CachedDataSource(
      cacheType: CacheType.observations,
      dataType: 'Observations',
      sources: [DataSourceType.restApi, DataSourceType.websocket, DataSourceType.udp],
      keyPattern: 'latest_{deviceId}',
      maxAge: Duration(minutes: 5),
      hiveBox: 'observations',
    ),
    CachedDataSource(
      cacheType: CacheType.hourlyForecasts,
      dataType: 'Hourly Forecasts',
      sources: [DataSourceType.restApi],
      keyPattern: '{stationId}',
      maxAge: Duration(minutes: 30),
      hiveBox: 'forecasts',
    ),
    CachedDataSource(
      cacheType: CacheType.dailyForecasts,
      dataType: 'Daily Forecasts',
      sources: [DataSourceType.restApi],
      keyPattern: '{stationId}',
      maxAge: Duration(minutes: 30),
      hiveBox: 'forecasts',
    ),
  ];

  /// Get sources by cache type
  static CachedDataSource? byType(CacheType type) {
    return all.cast<CachedDataSource?>().firstWhere(
      (s) => s?.cacheType == type,
      orElse: () => null,
    );
  }

  /// Get all sources that use a specific data source type
  static List<CachedDataSource> byDataSource(DataSourceType sourceType) {
    return all.where((s) => s.sources.contains(sourceType)).toList();
  }

  /// Get all sources stored in a specific Hive box
  static List<CachedDataSource> byHiveBox(String boxName) {
    return all.where((s) => s.hiveBox == boxName).toList();
  }
}

/// Cache registry for managing all app caches
class CacheRegistry {
  final StorageService _storage;
  final WeatherFlowService? _weatherService;

  CacheRegistry(this._storage, [this._weatherService]);

  /// Get description of a cache type
  static String getDescription(CacheType type) {
    switch (type) {
      case CacheType.stations:
        return 'Station list and details (keyed by stationId)';
      case CacheType.observations:
        return 'Current weather observations (keyed by deviceId)';
      case CacheType.hourlyForecasts:
        return 'Hourly forecasts up to 72 hours (keyed by stationId)';
      case CacheType.dailyForecasts:
        return 'Daily forecasts up to 10 days (keyed by stationId)';
    }
  }

  /// Get data sources for a cache type
  static List<DataSourceType> getDataSources(CacheType type) {
    switch (type) {
      case CacheType.stations:
        return [DataSourceType.restApi];
      case CacheType.observations:
        return [DataSourceType.restApi, DataSourceType.websocket, DataSourceType.udp];
      case CacheType.hourlyForecasts:
      case CacheType.dailyForecasts:
        return [DataSourceType.restApi];
    }
  }

  /// Get refresh triggers for a cache type
  static List<String> getRefreshTriggers(CacheType type) {
    switch (type) {
      case CacheType.stations:
        return ['App startup', 'Manual station list refresh', 'API token change'];
      case CacheType.observations:
        return ['Station switch', 'WebSocket message', 'UDP broadcast', 'REST poll (60s)', 'Manual refresh'];
      case CacheType.hourlyForecasts:
      case CacheType.dailyForecasts:
        return ['Station switch', 'Refresh button', 'REST poll (30m)'];
    }
  }

  /// Get recommended max age for a cache type
  static Duration getMaxAge(CacheType type) {
    switch (type) {
      case CacheType.stations:
        return const Duration(hours: 24);
      case CacheType.observations:
        return const Duration(minutes: 5);
      case CacheType.hourlyForecasts:
      case CacheType.dailyForecasts:
        return const Duration(minutes: 30);
    }
  }

  /// Clear a specific cache type
  Future<void> clear(CacheType type) async {
    debugPrint('CacheRegistry: Clearing ${type.name} cache');
    switch (type) {
      case CacheType.stations:
        await _storage.clearStations();
        break;
      case CacheType.observations:
        await _storage.clearObservations();
        break;
      case CacheType.hourlyForecasts:
      case CacheType.dailyForecasts:
        // Both are stored together in forecasts box
        await _storage.clearForecasts();
        break;
    }
  }

  /// Refresh a specific cache type from source
  Future<void> refresh(CacheType type) async {
    final weatherService = _weatherService;
    if (weatherService == null) {
      debugPrint('CacheRegistry: Cannot refresh - no weather service');
      return;
    }

    debugPrint('CacheRegistry: Refreshing ${type.name} from source');
    switch (type) {
      case CacheType.stations:
        await weatherService.fetchStations();
        break;
      case CacheType.observations:
        await weatherService.refresh();
        break;
      case CacheType.hourlyForecasts:
      case CacheType.dailyForecasts:
        await weatherService.fetchForecast();
        break;
    }
  }

  /// Clear and refresh a specific cache type
  Future<void> clearAndRefresh(CacheType type) async {
    await clear(type);
    await refresh(type);
  }

  /// Clear multiple cache types
  Future<void> clearMultiple(List<CacheType> types) async {
    for (final type in types) {
      await clear(type);
    }
  }

  /// Refresh multiple cache types
  Future<void> refreshMultiple(List<CacheType> types) async {
    for (final type in types) {
      await refresh(type);
    }
  }

  /// Clear all caches (keeps settings)
  Future<void> clearAll() async {
    debugPrint('CacheRegistry: Clearing ALL caches');
    await _storage.clearCache();
  }

  /// Refresh all caches from source
  Future<void> refreshAll() async {
    debugPrint('CacheRegistry: Refreshing ALL caches from source');
    for (final type in CacheType.values) {
      await refresh(type);
    }
  }

  /// Caches that should be cleared on station switch
  static const stationSwitchCaches = [
    CacheType.observations,
    CacheType.hourlyForecasts,
    CacheType.dailyForecasts,
  ];

  /// Caches that should be cleared on logout/token change
  static const logoutCaches = [
    CacheType.stations,
    CacheType.observations,
    CacheType.hourlyForecasts,
    CacheType.dailyForecasts,
  ];

  /// Handle station switch - clear and refresh relevant caches
  Future<void> onStationSwitch() async {
    debugPrint('CacheRegistry: Station switch - clearing related caches');
    await clearMultiple(stationSwitchCaches);
  }

  /// Handle logout - clear all caches
  Future<void> onLogout() async {
    debugPrint('CacheRegistry: Logout - clearing all caches');
    await clearMultiple(logoutCaches);
  }

  /// Print inventory to debug console
  static void printInventory() {
    debugPrint('=== CACHE INVENTORY ===');
    for (final type in CacheType.values) {
      debugPrint('');
      debugPrint('${type.name.toUpperCase()}:');
      debugPrint('  ${getDescription(type)}');
      debugPrint('  Data sources: ${getDataSources(type).map((s) => s.name).join(", ")}');
      debugPrint('  Max age: ${getMaxAge(type).inMinutes} minutes');
      debugPrint('  Refresh triggers:');
      for (final trigger in getRefreshTriggers(type)) {
        debugPrint('    - $trigger');
      }
    }
    debugPrint('=======================');
  }

  /// Get cache statistics
  Map<String, dynamic> getStats() {
    return {
      'stations_count': _storage.cachedStations.length,
      // Add more stats as needed
    };
  }
}
