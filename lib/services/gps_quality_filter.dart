import 'dart:convert';
import 'dart:math' as math;

import 'package:background_location_tracker/background_location_tracker.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GpsQualityResult {
  const GpsQualityResult.accepted() : rejectionReason = null;
  const GpsQualityResult.rejected(this.rejectionReason);

  final String? rejectionReason;
  bool get isAccepted => rejectionReason == null;
}

class GpsQualityFilter {
  static const double _maxHorizontalAccuracyMeters = 100;
  static const double _maxReportedSpeedMetersPerSecond = 60;
  static const double _maxInferredSpeedMetersPerSecond = 80;
  static const double _minJumpDistanceMeters = 300;
  static const Duration _minExactDuplicateInterval = Duration(minutes: 10);

  static const String _lastAcceptedLocationKey = 'last_accepted_location';

  Future<GpsQualityResult> evaluate(
    BackgroundLocationUpdateData data, {
    required DateTime capturedAt,
  }) async {
    if (!_isValidCoordinate(data.lat, data.lon)) {
      return const GpsQualityResult.rejected('invalid_coordinate');
    }

    if (data.lat == 0 && data.lon == 0) {
      return const GpsQualityResult.rejected('zero_coordinate');
    }

    if (data.horizontalAccuracy >= 0 &&
        data.horizontalAccuracy > _maxHorizontalAccuracyMeters) {
      return GpsQualityResult.rejected(
        'poor_accuracy_${data.horizontalAccuracy.toStringAsFixed(1)}m',
      );
    }

    if (data.speed >= 0 && data.speed > _maxReportedSpeedMetersPerSecond) {
      return GpsQualityResult.rejected(
        'impossible_reported_speed_${data.speed.toStringAsFixed(1)}mps',
      );
    }

    final previous = await _readLastAcceptedLocation();
    if (previous != null) {
      final distance = _distanceMeters(
        previous.latitude,
        previous.longitude,
        data.lat,
        data.lon,
      );
      final elapsedSeconds =
          capturedAt.difference(previous.capturedAt).inMilliseconds / 1000;

      if (elapsedSeconds > 0) {
        final inferredSpeed = distance / elapsedSeconds;
        if (distance > _minJumpDistanceMeters &&
            inferredSpeed > _maxInferredSpeedMetersPerSecond) {
          return GpsQualityResult.rejected(
            'impossible_jump_${distance.toStringAsFixed(0)}m_${inferredSpeed.toStringAsFixed(1)}mps',
          );
        }
      }

      final samePoint = previous.latitude == data.lat &&
          previous.longitude == data.lon &&
          previous.horizontalAccuracy == data.horizontalAccuracy;
      if (samePoint &&
          capturedAt.difference(previous.capturedAt) <
              _minExactDuplicateInterval) {
        return const GpsQualityResult.rejected('exact_duplicate');
      }
    }

    return const GpsQualityResult.accepted();
  }

  Future<void> markAccepted(
    BackgroundLocationUpdateData data, {
    required DateTime capturedAt,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _lastAcceptedLocationKey,
      jsonEncode({
        'latitude': data.lat,
        'longitude': data.lon,
        'horizontal_accuracy': data.horizontalAccuracy,
        'captured_at': capturedAt.toIso8601String(),
      }),
    );
  }

  Future<_PreviousLocation?> _readLastAcceptedLocation() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_lastAcceptedLocationKey);
    if (raw == null || raw.isEmpty) return null;

    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final capturedAt =
          DateTime.tryParse(data['captured_at']?.toString() ?? '');
      if (capturedAt == null) return null;

      return _PreviousLocation(
        latitude: (data['latitude'] as num).toDouble(),
        longitude: (data['longitude'] as num).toDouble(),
        horizontalAccuracy: (data['horizontal_accuracy'] as num).toDouble(),
        capturedAt: capturedAt,
      );
    } catch (_) {
      return null;
    }
  }

  bool _isValidCoordinate(double latitude, double longitude) =>
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180 &&
      latitude.isFinite &&
      longitude.isFinite;

  double _distanceMeters(
    double fromLat,
    double fromLon,
    double toLat,
    double toLon,
  ) {
    const earthRadiusMeters = 6371000.0;
    final fromLatRad = _toRadians(fromLat);
    final toLatRad = _toRadians(toLat);
    final deltaLat = _toRadians(toLat - fromLat);
    final deltaLon = _toRadians(toLon - fromLon);

    final a = math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
        math.cos(fromLatRad) *
            math.cos(toLatRad) *
            math.sin(deltaLon / 2) *
            math.sin(deltaLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusMeters * c;
  }

  double _toRadians(double degrees) => degrees * math.pi / 180;
}

class _PreviousLocation {
  const _PreviousLocation({
    required this.latitude,
    required this.longitude,
    required this.horizontalAccuracy,
    required this.capturedAt,
  });

  final double latitude;
  final double longitude;
  final double horizontalAccuracy;
  final DateTime capturedAt;
}
