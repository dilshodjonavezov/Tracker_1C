import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:android_intent_plus/android_intent.dart';

class PermissionManager {
  static Future<void> requestAllPermissions() async {
    print('PermissionManager: Requesting permissions at ${DateTime.now()}');
    
    final permissions = [
      Permission.location,
      Permission.locationAlways,
      Permission.notification,
    ];
    
    for (var permission in permissions) {
      final status = await permission.request();
      print('PermissionManager: $permission status: $status');
    }

    if (Platform.isAndroid) {
      try {
        final intent = AndroidIntent(
          action: 'android.settings.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
          data: 'package:com.example.example',
        );
        await intent.launch();
        print('PermissionManager: Battery optimization requested');
      } catch (e) {
        print('PermissionManager: Error: $e');
      }
    }
  }
}