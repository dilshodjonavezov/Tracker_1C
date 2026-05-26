import 'package:permission_handler/permission_handler.dart';

import 'server_service.dart';

class LocationDiagnosticService {
  LocationDiagnosticService({ServerService? serverService})
      : _serverService = serverService ?? ServerService();

  final ServerService _serverService;

  Future<void> checkAndReport() async {
    final disabledReason = await _getDisabledReason();
    if (disabledReason == null) return;

    await _serverService.sendLocationDisabledSignal(source: disabledReason);
  }

  Future<String?> _getDisabledReason() async {
    final serviceStatus = await Permission.location.serviceStatus;
    if (serviceStatus == ServiceStatus.disabled) {
      return 'Геолокация выключена на устройстве';
    }

    final locationStatus = await Permission.location.status;
    if (_isPermissionBlocked(locationStatus)) {
      return 'Нет разрешения геолокации';
    }

    return null;
  }

  bool _isPermissionBlocked(PermissionStatus status) {
    return status.isDenied || status.isPermanentlyDenied || status.isRestricted;
  }
}
