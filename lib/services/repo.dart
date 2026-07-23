import 'dart:convert';

import 'package:background_location_tracker/background_location_tracker.dart';
import 'package:background_location_tracker_example/dao/location_dao.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:background_location_tracker_example/services/gps_quality_filter.dart';
import 'package:background_location_tracker_example/services/server_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class Repo {
  static Repo? _instance;
  final ServerService _serverService = ServerService();
  final GpsQualityFilter _gpsQualityFilter = GpsQualityFilter();

  Repo._();

  factory Repo() => _instance ??= Repo._();

  Future<void> update(BackgroundLocationUpdateData data) async {
    final now = DateTime.now();

    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id');
    if (userId == null || userId.isEmpty) return;

    // 💾 Сохраняем последнюю позицию в памяти
    await prefs.setString(
        'last_location',
        jsonEncode({
          'latitude': data.lat.toString(),
          'longitude': data.lon.toString()
        }));

    final quality = await _gpsQualityFilter.evaluate(data, capturedAt: now);

    // Always journal the complete GPS sample first. Quality warnings stay in
    // SQLite for diagnostics, but every received coordinate is still uploaded.
    await LocationDao().saveLocation(
      data,
      userId: userId,
      capturedAt: now,
      syncable: true,
      rejectionReason: quality.rejectionReason,
    );

    if (quality.isAccepted) {
      await _gpsQualityFilter.markAccepted(data, capturedAt: now);
    }

    // Flush at most once per ten minutes. This is also invoked from the
    // foreground timer and on app startup, so recovery does not depend on UI.
    await _serverService.maybeFlushPendingLocations();
  }
}

void sendNotification(String text) {
  final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  const AndroidNotificationDetails androidPlatformChannelSpecifics =
      AndroidNotificationDetails(
    'location_channel',
    'Location Updates',
    channelDescription: 'Notifications for location updates',
    importance: Importance.low,
    priority: Priority.low,
  );
  const NotificationDetails platformChannelSpecifics =
      NotificationDetails(android: androidPlatformChannelSpecifics);
  flutterLocalNotificationsPlugin.show(
      0, 'Tracker GPS', text, platformChannelSpecifics);
}
