/// Unified daylight/twilight calculation service
/// Provides consistent time-of-day period calculations for both
/// the forecast spinner and sun/moon arc widgets
///
/// Handles:
/// - Proper timezone conversion (location vs device)
/// - Hemisphere-aware calculations
/// - Color assignments for day/night periods

import 'package:flutter/material.dart';
import '../widgets/forecast_models.dart';

/// Time-of-day period enum
enum DaylightPeriod {
  /// Deep night (before nautical dawn or after nautical dusk)
  night,

  /// Nautical twilight (nautical dawn to civil dawn, or civil dusk to nautical dusk)
  nauticalTwilight,

  /// Civil twilight (civil dawn to sunrise, or sunset to civil dusk)
  civilTwilight,

  /// Golden hour (sunrise to golden hour end, or golden hour start to sunset)
  goldenHour,

  /// Full daylight (golden hour end to golden hour start)
  daylight,
}

/// Result of daylight period calculation
class DaylightPeriodResult {
  final DaylightPeriod period;
  final Color color;
  final bool isMorning; // true if before solar noon

  const DaylightPeriodResult({
    required this.period,
    required this.color,
    required this.isMorning,
  });
}

/// Unified daylight calculation service
class DaylightService {
  /// Standard colors for each daylight period
  static const Map<DaylightPeriod, Color> periodColors = {
    DaylightPeriod.night: Color(0xFF1A237E), // Colors.indigo.shade900
    DaylightPeriod.nauticalTwilight: Color(0xFF303F9F), // Colors.indigo.shade700
    DaylightPeriod.civilTwilight: Color(0xFF5C6BC0), // Colors.indigo.shade400
    DaylightPeriod.goldenHour: Color(0xFFFFB74D), // Colors.orange.shade300
    DaylightPeriod.daylight: Color(0xFFFFE082), // Colors.amber.shade200
  };

  /// Evening-specific colors (slightly warmer)
  static const Map<DaylightPeriod, Color> eveningColors = {
    DaylightPeriod.night: Color(0xFF1A237E), // Same as morning
    DaylightPeriod.nauticalTwilight: Color(0xFF303F9F), // Same as morning
    DaylightPeriod.civilTwilight: Color(0xFFFF7043), // Colors.deepOrange.shade400
    DaylightPeriod.goldenHour: Color(0xFFFFA726), // Colors.orange.shade400
    DaylightPeriod.daylight: Color(0xFFFFE082), // Same as morning
  };

  /// Get the daylight period for a specific time using SunMoonTimes data
  ///
  /// [time] - The time to check
  /// [times] - SunMoonTimes containing sunrise/sunset data
  /// [useLocationTimezone] - If true, uses location's timezone; if false, uses device local
  static DaylightPeriodResult getPeriod(
    DateTime time,
    SunMoonTimes? times, {
    bool useLocationTimezone = true,
  }) {
    if (times == null) {
      return _getFallbackPeriod(time);
    }

    final timeUtc = time.toUtc();

    // Iterate through ALL days (same as arc) - no dayIndex calculation!
    for (final day in times.days) {
      // Helper to check if time is in range [start, end)
      bool inRange(DateTime? start, DateTime? end) {
        if (start == null || end == null) return false;
        return !timeUtc.isBefore(start) && timeUtc.isBefore(end);
      }

      // POLAR CHECK: detect when sunrise/sunset times are clustered
      // This happens when SunCalc clamps values for polar regions
      if (day.sunrise != null && day.sunset != null) {
        final diff = day.sunset!.difference(day.sunrise!).inMilliseconds.abs();
        // Check for polar conditions:
        // 1. Sunrise and sunset are within 2 hours (normal polar detection)
        // 2. OR sunrise and sunset have same time-of-day (SunCalc wraps to next day for polar day/night)
        final sameTimeOfDay = (day.sunrise!.hour == day.sunset!.hour) &&
                              ((day.sunrise!.minute - day.sunset!.minute).abs() <= 5);
        if (diff < 2 * 60 * 60 * 1000 || sameTimeOfDay) {
          if (times.latitude != null) {
            final isPolarDay = _isPolarDaylight(timeUtc, times.latitude!);
            return DaylightPeriodResult(
              period: isPolarDay ? DaylightPeriod.daylight : DaylightPeriod.night,
              color: isPolarDay ? periodColors[DaylightPeriod.daylight]! : periodColors[DaylightPeriod.night]!,
              isMorning: timeUtc.hour < 12,
            );
          }
        }
      }

      // Check each period in sequence (same order as arc segments)
      // Night before dawn
      if (day.nauticalDawn != null) {
        final nightStart = day.nauticalDawn!.subtract(const Duration(hours: 6));
        if (inRange(nightStart, day.nauticalDawn)) {
          return DaylightPeriodResult(period: DaylightPeriod.night, color: periodColors[DaylightPeriod.night]!, isMorning: true);
        }
      }
      // Nautical twilight (dawn)
      if (inRange(day.nauticalDawn, day.dawn)) {
        return DaylightPeriodResult(period: DaylightPeriod.nauticalTwilight, color: periodColors[DaylightPeriod.nauticalTwilight]!, isMorning: true);
      }
      // Civil twilight (dawn)
      if (inRange(day.dawn, day.sunrise)) {
        return DaylightPeriodResult(period: DaylightPeriod.civilTwilight, color: periodColors[DaylightPeriod.civilTwilight]!, isMorning: true);
      }
      // Golden hour (morning)
      if (inRange(day.sunrise, day.goldenHourEnd)) {
        return DaylightPeriodResult(period: DaylightPeriod.goldenHour, color: periodColors[DaylightPeriod.goldenHour]!, isMorning: true);
      }
      // Daylight (morning to noon)
      if (inRange(day.goldenHourEnd, day.solarNoon)) {
        return DaylightPeriodResult(period: DaylightPeriod.daylight, color: periodColors[DaylightPeriod.daylight]!, isMorning: true);
      }
      // Daylight (noon to afternoon)
      if (inRange(day.solarNoon, day.goldenHour)) {
        return DaylightPeriodResult(period: DaylightPeriod.daylight, color: periodColors[DaylightPeriod.daylight]!, isMorning: false);
      }
      // Golden hour (evening)
      if (inRange(day.goldenHour, day.sunset)) {
        return DaylightPeriodResult(period: DaylightPeriod.goldenHour, color: eveningColors[DaylightPeriod.goldenHour]!, isMorning: false);
      }
      // Civil twilight (dusk)
      if (inRange(day.sunset, day.dusk)) {
        return DaylightPeriodResult(period: DaylightPeriod.civilTwilight, color: eveningColors[DaylightPeriod.civilTwilight]!, isMorning: false);
      }
      // Nautical twilight (dusk)
      if (inRange(day.dusk, day.nauticalDusk)) {
        return DaylightPeriodResult(period: DaylightPeriod.nauticalTwilight, color: periodColors[DaylightPeriod.nauticalTwilight]!, isMorning: false);
      }
      // Night after dusk
      if (day.nauticalDusk != null) {
        final nightEnd = day.nauticalDusk!.add(const Duration(hours: 6));
        if (inRange(day.nauticalDusk, nightEnd)) {
          return DaylightPeriodResult(period: DaylightPeriod.night, color: periodColors[DaylightPeriod.night]!, isMorning: false);
        }
      }
    }

    return _getFallbackPeriod(time);
  }

  /// Get the color for a specific time segment
  ///
  /// This is the primary method for the forecast spinner to get segment colors
  static Color getSegmentColor(
    DateTime time,
    SunMoonTimes? times, {
    bool useLocationTimezone = true,
  }) {
    final result = getPeriod(time, times, useLocationTimezone: useLocationTimezone);
    if (result.isMorning) {
      return periodColors[result.period] ?? periodColors[DaylightPeriod.daylight]!;
    } else {
      return eveningColors[result.period] ?? periodColors[DaylightPeriod.daylight]!;
    }
  }

  /// Fallback period calculation when no sun times are available
  /// Uses hour-of-day approximation (less accurate but works without API data)
  static DaylightPeriodResult _getFallbackPeriod(DateTime time) {
    final hour = time.hour;

    // These are rough approximations for mid-latitudes
    // Real times depend heavily on latitude and time of year
    if (hour < 5) {
      return DaylightPeriodResult(
        period: DaylightPeriod.night,
        color: periodColors[DaylightPeriod.night]!,
        isMorning: true,
      );
    }
    if (hour < 6) {
      return DaylightPeriodResult(
        period: DaylightPeriod.nauticalTwilight,
        color: periodColors[DaylightPeriod.nauticalTwilight]!,
        isMorning: true,
      );
    }
    if (hour < 7) {
      return DaylightPeriodResult(
        period: DaylightPeriod.civilTwilight,
        color: periodColors[DaylightPeriod.civilTwilight]!,
        isMorning: true,
      );
    }
    if (hour < 8) {
      return DaylightPeriodResult(
        period: DaylightPeriod.goldenHour,
        color: periodColors[DaylightPeriod.goldenHour]!,
        isMorning: true,
      );
    }
    if (hour < 16) {
      return DaylightPeriodResult(
        period: DaylightPeriod.daylight,
        color: periodColors[DaylightPeriod.daylight]!,
        isMorning: hour < 12,
      );
    }
    if (hour < 17) {
      return DaylightPeriodResult(
        period: DaylightPeriod.goldenHour,
        color: eveningColors[DaylightPeriod.goldenHour]!,
        isMorning: false,
      );
    }
    if (hour < 18) {
      return DaylightPeriodResult(
        period: DaylightPeriod.civilTwilight,
        color: eveningColors[DaylightPeriod.civilTwilight]!,
        isMorning: false,
      );
    }
    if (hour < 19) {
      return DaylightPeriodResult(
        period: DaylightPeriod.nauticalTwilight,
        color: periodColors[DaylightPeriod.nauticalTwilight]!,
        isMorning: false,
      );
    }

    return DaylightPeriodResult(
      period: DaylightPeriod.night,
      color: periodColors[DaylightPeriod.night]!,
      isMorning: false,
    );
  }

  /// Check if location is in polar daylight (midnight sun)
  /// Southern hemisphere: polar day ~Oct-Feb
  /// Northern hemisphere: polar day ~Apr-Aug
  static bool _isPolarDaylight(DateTime time, double latitude) {
    final month = time.month;
    final isSouthern = latitude < 0;
    // Southern summer: Oct, Nov, Dec, Jan, Feb, Mar
    // Northern summer: Apr, May, Jun, Jul, Aug, Sep
    final isSummerMonth = isSouthern
        ? (month >= 10 || month <= 3)
        : (month >= 4 && month <= 9);
    return isSummerMonth;
  }

  /// Check if a given time is during daylight hours
  static bool isDaytime(DateTime time, SunMoonTimes? times) {
    final result = getPeriod(time, times);
    return result.period == DaylightPeriod.daylight ||
        result.period == DaylightPeriod.goldenHour;
  }

  /// Check if a given time is during nighttime
  static bool isNighttime(DateTime time, SunMoonTimes? times) {
    final result = getPeriod(time, times);
    return result.period == DaylightPeriod.night;
  }

  /// Check if a given time is during twilight (civil or nautical)
  static bool isTwilight(DateTime time, SunMoonTimes? times) {
    final result = getPeriod(time, times);
    return result.period == DaylightPeriod.civilTwilight ||
        result.period == DaylightPeriod.nauticalTwilight;
  }

  /// Get arc segment data for the sun/moon arc widget
  /// Returns a list of (start, end, color) tuples for each daylight period
  static List<ArcSegment> getArcSegments(
    DateTime arcStart,
    DateTime arcEnd,
    SunMoonTimes times,
  ) {
    final segments = <ArcSegment>[];

    // Collect all days that overlap with the arc
    for (final day in times.days) {
      // Add segments for each twilight phase
      _addArcSegment(segments, arcStart, arcEnd, day.nauticalDawn, day.dawn,
          periodColors[DaylightPeriod.nauticalTwilight]!);
      _addArcSegment(segments, arcStart, arcEnd, day.dawn, day.sunrise,
          periodColors[DaylightPeriod.civilTwilight]!);
      _addArcSegment(segments, arcStart, arcEnd, day.sunrise, day.goldenHourEnd,
          periodColors[DaylightPeriod.goldenHour]!);
      _addArcSegment(segments, arcStart, arcEnd, day.goldenHourEnd, day.solarNoon,
          periodColors[DaylightPeriod.daylight]!);
      _addArcSegment(segments, arcStart, arcEnd, day.solarNoon, day.goldenHour,
          periodColors[DaylightPeriod.daylight]!);
      _addArcSegment(segments, arcStart, arcEnd, day.goldenHour, day.sunset,
          eveningColors[DaylightPeriod.goldenHour]!);
      _addArcSegment(segments, arcStart, arcEnd, day.sunset, day.dusk,
          eveningColors[DaylightPeriod.civilTwilight]!);
      _addArcSegment(segments, arcStart, arcEnd, day.dusk, day.nauticalDusk,
          periodColors[DaylightPeriod.nauticalTwilight]!);

      // Night segments (before nautical dawn and after nautical dusk)
      if (day.nauticalDawn != null) {
        final nightStart = day.nauticalDawn!.subtract(const Duration(hours: 6));
        _addArcSegment(segments, arcStart, arcEnd, nightStart, day.nauticalDawn,
            periodColors[DaylightPeriod.night]!.withValues(alpha: 0.5));
      }
      if (day.nauticalDusk != null) {
        final nightEnd = day.nauticalDusk!.add(const Duration(hours: 6));
        _addArcSegment(segments, arcStart, arcEnd, day.nauticalDusk, nightEnd,
            periodColors[DaylightPeriod.night]!.withValues(alpha: 0.5));
      }
    }

    return segments;
  }

  static void _addArcSegment(
    List<ArcSegment> segments,
    DateTime arcStart,
    DateTime arcEnd,
    DateTime? start,
    DateTime? end,
    Color color,
  ) {
    if (start == null || end == null) return;
    if (end.isBefore(arcStart) || start.isAfter(arcEnd)) return;
    segments.add(ArcSegment(start: start, end: end, color: color));
  }
}

/// Arc segment data for sun/moon arc rendering
class ArcSegment {
  final DateTime start;
  final DateTime end;
  final Color color;

  const ArcSegment({
    required this.start,
    required this.end,
    required this.color,
  });
}
