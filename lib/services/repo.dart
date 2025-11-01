import 'dart:convert';

import 'package:background_location_tracker/background_location_tracker.dart';
import 'package:background_location_tracker_example/dao/location_dao.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:background_location_tracker_example/services/server_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class Repo {
  static Repo? _instance;
  final ServerService _serverService = ServerService();
  DateTime? _lastUpdateTime;
  static const int _minUpdateIntervalSeconds = 300;

  Repo._();

  factory Repo() => _instance ??= Repo._();

  Future<void> update(BackgroundLocationUpdateData data) async {
    final now = DateTime.now();
    if (_lastUpdateTime != null && now.difference(_lastUpdateTime!).inSeconds < _minUpdateIntervalSeconds) return;

    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id');
    if (userId == null || userId.isEmpty) return;

    await prefs.setString('last_location', jsonEncode({'latitude': data.lat.toString(), 'longitude': data.lon.toString()}));
    final status = await _getOrRefreshUserStatus(userId, prefs);
    if (status == null || !(status['gps'] ?? true)) return;

    final fromTime = DateTime.parse(status['from'] ?? '0001-01-01T08:00:00');
    final toTime = DateTime.parse(status['to'] ?? '0001-01-01T18:00:00');
    final currentTimeInMinutes = now.hour * 60 + now.minute;
    final fromTimeInMinutes = fromTime.hour * 60 + fromTime.minute;
    final toTimeInMinutes = toTime.hour * 60 + toTime.minute;
    if (currentTimeInMinutes < fromTimeInMinutes || currentTimeInMinutes >= toTimeInMinutes) return;

    sendNotification('Location Update: Lat: ${data.lat} Lon: ${data.lon}');
    await LocationDao().saveLocation(data);
    await _serverService.sendLocationToServer(data.lat, data.lon);
    _lastUpdateTime = now;
  }

  Future<Map<String, dynamic>?> _getOrRefreshUserStatus(String userId, SharedPreferences prefs) async {
    final lastStatusTimestamp = prefs.getInt('last_status_timestamp') ?? 0;
    const eightHoursInMillis = 8 * 60 * 60 * 1000;
    if (lastStatusTimestamp == 0 || DateTime.now().millisecondsSinceEpoch - lastStatusTimestamp >= eightHoursInMillis) {
      final status = await ServerService().getUserStatus(userId);
      if (status != null) {
        await prefs.setString('cached_user_status', jsonEncode(status));
        await prefs.setInt('last_status_timestamp', DateTime.now().millisecondsSinceEpoch);
        return status;
      }
    }
    final cachedStatusJson = prefs.getString('cached_user_status');
    return cachedStatusJson != null ? jsonDecode(cachedStatusJson) as Map<String, dynamic> : {'gps': true, 'from': '0001-01-01T08:00:00', 'to': '0001-01-01T18:00:00'};
  }
}

void sendNotification(String text) {
  final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  const AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(
    'location_channel',
    'Location Updates',
    channelDescription: 'Notifications for location updates',
    importance: Importance.low,
    priority: Priority.low,
  );
  const NotificationDetails platformChannelSpecifics = NotificationDetails(android: androidPlatformChannelSpecifics);
  flutterLocalNotificationsPlugin.show(0, 'Tracker GPS', text, platformChannelSpecifics);
}