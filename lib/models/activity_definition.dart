/// Activity definitions for the Activity Forecaster
///
/// Defines all supported outdoor activities with their display properties
/// and requirements.

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Types of outdoor activities that can be scored
enum ActivityType {
  running,
  cycling,
  walking,
  hiking,
  beingOutside,
  skiing,
  motorBoating,
  sailing,
  kitesurfing,
  surfing,
  swimming,
}

/// Extension methods for ActivityType
extension ActivityTypeExtension on ActivityType {
  /// Display name for the activity
  String get displayName {
    switch (this) {
      case ActivityType.running:
        return 'Running';
      case ActivityType.cycling:
        return 'Cycling';
      case ActivityType.walking:
        return 'Walking';
      case ActivityType.hiking:
        return 'Hiking';
      case ActivityType.beingOutside:
        return 'Being Outside';
      case ActivityType.skiing:
        return 'Skiing';
      case ActivityType.motorBoating:
        return 'Motor Boating';
      case ActivityType.sailing:
        return 'Sailing';
      case ActivityType.kitesurfing:
        return 'Kitesurfing';
      case ActivityType.surfing:
        return 'Surfing';
      case ActivityType.swimming:
        return 'Swimming';
    }
  }

  /// Phosphor icon for the activity
  IconData get icon {
    switch (this) {
      case ActivityType.running:
        return PhosphorIcons.personSimpleRun();
      case ActivityType.cycling:
        return PhosphorIcons.bicycle();
      case ActivityType.walking:
        return PhosphorIcons.personSimpleWalk();
      case ActivityType.hiking:
        return PhosphorIcons.mountains();
      case ActivityType.beingOutside:
        return PhosphorIcons.sun();
      case ActivityType.skiing:
        return PhosphorIcons.personSimpleSki();
      case ActivityType.motorBoating:
        return PhosphorIcons.boat();
      case ActivityType.sailing:
        return PhosphorIcons.sailboat();
      case ActivityType.kitesurfing:
        return PhosphorIcons.wind();
      case ActivityType.surfing:
        return PhosphorIcons.waveSquare();
      case ActivityType.swimming:
        return PhosphorIcons.swimmingPool();
    }
  }

  /// Whether this activity requires marine data
  bool get requiresMarineData {
    switch (this) {
      case ActivityType.motorBoating:
      case ActivityType.sailing:
      case ActivityType.kitesurfing:
      case ActivityType.surfing:
      case ActivityType.swimming:
        return true;
      default:
        return false;
    }
  }

  /// Whether this is a land-based activity
  bool get isLandActivity => !requiresMarineData;

  /// String key for storage/serialization
  String get key => name;

  /// Create from string key
  static ActivityType? fromKey(String key) {
    try {
      return ActivityType.values.firstWhere((e) => e.name == key);
    } catch (_) {
      return null;
    }
  }
}

/// List of all land activities
const landActivities = [
  ActivityType.running,
  ActivityType.cycling,
  ActivityType.walking,
  ActivityType.hiking,
  ActivityType.beingOutside,
  ActivityType.skiing,
];

/// List of all marine activities
const marineActivities = [
  ActivityType.motorBoating,
  ActivityType.sailing,
  ActivityType.kitesurfing,
  ActivityType.surfing,
  ActivityType.swimming,
];
