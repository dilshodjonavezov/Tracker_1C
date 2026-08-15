import 'package:background_location_tracker/background_location_tracker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../dao/location_dao.dart';
import 'server_service.dart';
import 'tracking_config.dart';

class LocationDiagnosticService {
  LocationDiagnosticService({ServerService? serverService})
      : _serverService = serverService ?? ServerService();

  final ServerService _serverService;

  Future<void> checkAndReport() async {
    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id');
    final issue = await _getLocationIssue();
    if (issue != null) {
      if (userId != null && userId.isNotEmpty) {
        await LocationDao().recordOpenDeviceIssue(
          userId: userId,
          eventType: issue.code,
          eventName: issue.message,
          owner: 'Телефон',
          detectedAt: now,
        );
      }
      await _serverService.sendLocationDisabledSignal(source: issue.message);
      return;
    }
    if (userId != null && userId.isNotEmpty) {
      await LocationDao().closeOpenDeviceIssues(
        userId: userId,
        endedAt: now,
      );
    }
    await _restartStaleTrackerIfNeeded();
  }

  Future<LocationIssue?> _getLocationIssue() async {
    final serviceStatus = await Permission.location.serviceStatus;
    if (serviceStatus == ServiceStatus.disabled) {
      return const LocationIssue(
        code: 'LOCATION_SERVICE_DISABLED',
        message: 'Геолокация отключена на устройстве',
      );
    }

    final locationStatus = await Permission.location.status;
    if (_isPermissionBlocked(locationStatus)) {
      return const LocationIssue(
        code: 'LOCATION_PERMISSION_MISSING',
        message: 'Нет разрешения на геолокацию',
      );
    }

    return null;
  }

  bool _isPermissionBlocked(PermissionStatus status) {
    return status.isDenied || status.isPermanentlyDenied || status.isRestricted;
  }

  Future<void> _restartStaleTrackerIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('gps') ?? true)) return;

    final lastLocationAt = prefs.getInt('last_location_received_at');
    if (lastLocationAt == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - lastLocationAt < const Duration(minutes: 2).inMilliseconds) {
      return;
    }

    final lastRestartAt = prefs.getInt('last_tracker_restart_at') ?? 0;
    if (now - lastRestartAt < const Duration(minutes: 10).inMilliseconds) {
      return;
    }
    await prefs.setInt('last_tracker_restart_at', now);

    try {
      if (await BackgroundLocationTrackerManager.isTracking()) {
        await BackgroundLocationTrackerManager.stopTracking();
      }
      await BackgroundLocationTrackerManager.startTracking(
        config: trackerAndroidConfig,
      );
    } catch (_) {
      // The next scheduled diagnostic will retry. Delivery diagnostics and the
      // local journal must keep working even if the OS rejects a restart.
    }
  }
}

class LocationIssue {
  const LocationIssue({required this.code, required this.message});

  final String code;
  final String message;
}
