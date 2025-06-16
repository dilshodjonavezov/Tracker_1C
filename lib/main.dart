import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:background_location_tracker_example/login_screen.dart';
import 'package:background_location_tracker_example/working_screen.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:background_location_tracker/background_location_tracker.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

@pragma('vm:entry-point')
void backgroundCallback() {
  BackgroundLocationTrackerManager.handleBackgroundUpdated(
    (data) async => Repo().update(data),
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await PermissionManager.requestAllPermissions();

  final prefs = await SharedPreferences.getInstance();
  final userId = prefs.getString('user_id');
  int? trackingIntervalSeconds;

  if (userId != null && userId.isNotEmpty) {
    final serverService = ServerService();
    final status = await serverService.getUserStatus(userId);
    if (status != null) {
      await prefs.setString('cached_user_status', jsonEncode(status));
      await prefs.setInt('last_status_timestamp', DateTime.now().millisecondsSinceEpoch);
      trackingIntervalSeconds = status['interval'];
      trackingIntervalSeconds = trackingIntervalSeconds?.clamp(10, 3600);
    }
  }
print('=================================');
print(trackingIntervalSeconds);
print('=================================');

  await BackgroundLocationTrackerManager.initialize(
    backgroundCallback,
    config: BackgroundLocationTrackerConfig(
      loggingEnabled: true,
      androidConfig: AndroidConfig(
        notificationIcon: 'explore',
        trackingInterval: Duration(seconds: trackingIntervalSeconds ?? 10),
        distanceFilterMeters: null,
      ),
    ),
  );

  runApp(
    MaterialApp(
      home: userId == null || userId.isEmpty
          ? const UserIdInputScreen()
          : const MyApp(),
    ),
  );
}

class PermissionManager {
  static Future<void> requestAllPermissions() async {
    final locationStatus = await Permission.location.request();

    if (Platform.isAndroid) {
      final notificationStatus = await Permission.notification.request();
    }
    if (Platform.isIOS) {
      await Permission.locationAlways.request();
    }
  }
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  MyAppState createState() => MyAppState();
}

class MyAppState extends State<MyApp> {
  var isTracking = false;
  Timer? _timer;
  Timer? _statusCheckTimer;
  List<String> _locations = [];
  final _serverService = ServerService();
  bool _isStatusCheckInProgress = false;

  @override
  void initState() {
    super.initState();
    _getTrackingStatus();
    _startLocationsUpdatesStream();
    _serverService.init();
    _startStatusCheckTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _statusCheckTimer?.cancel();
    _serverService.dispose();
    super.dispose();
  }

  void _startStatusCheckTimer() async {
    _statusCheckTimer?.cancel();

    await _checkUserStatus();

    _statusCheckTimer = Timer.periodic(const Duration(hours: 8), (timer) async {
      await _checkUserStatus();
    });
  }

  Future<void> _checkUserStatus() async {
    if (_isStatusCheckInProgress) return;
    _isStatusCheckInProgress = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id');

      if (userId == null || userId.isEmpty) {
        return;
      }

      final status = await _serverService.getUserStatus(userId);
      if (status != null) {
        await prefs.setBool('gps', status['gps'] ?? true);
        await prefs.setString('from', status['from'] ?? '0001-01-01T08:00:00');
        await prefs.setString('to', status['to'] ?? '0001-01-01T18:00:00');

        if (!(status['gps'] ?? true)) {
          if (isTracking) {
            await BackgroundLocationTrackerManager.stopTracking();
            setState(() => isTracking = false);
          }
        } else {
          final now = DateTime.now();
          final fromTime = DateTime.parse(status['from'] ?? '0001-01-01T08:00:00');
          final toTime = DateTime.parse(status['to'] ?? '0001-01-01T18:00:00');

          final currentTimeInMinutes = now.hour * 60 + now.minute;
          final fromTimeInMinutes = fromTime.hour * 60 + fromTime.minute;
          final toTimeInMinutes = toTime.hour * 60 + toTime.minute;

          final isInTimeWindow = currentTimeInMinutes >= fromTimeInMinutes &&
              currentTimeInMinutes < toTimeInMinutes;

          if (isInTimeWindow && !isTracking) {
            await BackgroundLocationTrackerManager.startTracking();
            setState(() => isTracking = true);
          } else if (!isInTimeWindow && isTracking) {
            await BackgroundLocationTrackerManager.stopTracking();
            setState(() => isTracking = false);
          }
        }
      }
    } catch (e) {
    } finally {
      _isStatusCheckInProgress = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: Colors.teal,
        scaffoldBackgroundColor: Colors.grey[100],
        textTheme: const TextTheme(
          bodyMedium: TextStyle(fontSize: 16, color: Colors.black87),
          titleLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.teal),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            backgroundColor: Colors.teal,
            foregroundColor: Colors.white,
          ),
        ),
      ),
      home: isTracking ? const TrackingScreen() : _buildMainScreen(),
    );
  }

  Widget _buildMainScreen() {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(60),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(20),
            ),
            color: Colors.teal,
          ),
          child: AppBar(
            title: const Text(
              'Трекер местоположения',
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.transparent,
            centerTitle: true,
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              color: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Контроль',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.teal),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: Icon(isTracking ? Icons.stop : Icons.play_arrow),
                            label: Text(isTracking ? 'Остановить' : 'Начать'),
                            onPressed: isTracking
                                ? () async {
                                    await LocationDao().clear();
                                    await _getLocations();
                                    await BackgroundLocationTrackerManager.stopTracking();
                                    setState(() => isTracking = false);
                                  }
                                : () async {
                                    await BackgroundLocationTrackerManager.startTracking();
                                    setState(() => isTracking = true);
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isTracking ? Colors.redAccent : Colors.teal,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Card(
                color: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.only(left: 16, right: 8, top: 8, bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              'История местоположений',
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.teal),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_locations.isNotEmpty)
                            TextButton(
                              onPressed: () async {
                                await LocationDao().clear();
                                setState(() => _locations = []);
                              },
                              child: const Text('Очистить', style: TextStyle(color: Colors.red)),
                            )
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: _locations.isEmpty
                            ? const Center(
                                child: Text(
                                  'Местоположение пока не сохранено.',
                                  style: TextStyle(fontSize: 16, color: Colors.grey),
                                ),
                              )
                            : ListView.builder(
                                itemCount: _locations.length,
                                itemBuilder: (context, index) {
                                  final parts = _locations[index].split(' - ');
                                  return Card(
                                    color: Colors.white,
                                    margin: const EdgeInsets.symmetric(vertical: 2),
                                    elevation: 0.5,
                                    child: ListTile(
                                      leading: const Icon(Icons.place, color: Colors.teal),
                                      title: Text(
                                        parts[1],
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      subtitle: Text(
                                        parts[0],
                                        style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _getTrackingStatus() async {
    isTracking = await BackgroundLocationTrackerManager.isTracking();
    setState(() {});
  }

  Future<void> _getLocations() async {
    final locations = await LocationDao().getLocations();
    setState(() {
      _locations = locations;
    });
  }

  void _startLocationsUpdatesStream() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 5), (timer) => _getLocations());
  }
}

String _formatDateTime(DateTime dateTime) {
  return '${dateTime.day.toString().padLeft(2, '0')}.${dateTime.month.toString().padLeft(2, '0')}.${dateTime.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';
}

class Repo {
  static Repo? _instance;
  final _serverService = ServerService();
  DateTime? _lastUpdateTime;
  static const int _minUpdateIntervalSeconds = 300; 

  Repo._();

  factory Repo() => _instance ??= Repo._();

  Future<void> update(BackgroundLocationUpdateData data) async {
    final now = DateTime.now();
    if (_lastUpdateTime != null &&
        now.difference(_lastUpdateTime!).inSeconds < _minUpdateIntervalSeconds) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id');

    if (userId == null || userId.isEmpty) {
      return;
    }

    Map<String, dynamic>? status = await _getOrRefreshUserStatus(userId, prefs);
    if (status == null) {
      await _saveLocationAsPending(data);
      return;
    }

    final gpsEnabled = status['gps'] ?? true;
    if (!gpsEnabled) {
      return;
    }

    final fromTime = DateTime.parse(status['from'] ?? '0001-01-01T08:00:00');
    final toTime = DateTime.parse(status['to'] ?? '0001-01-01T18:00:00');
    final currentTimeInMinutes = now.hour * 60 + now.minute;
    final fromTimeInMinutes = fromTime.hour * 60 + fromTime.minute;
    final toTimeInMinutes = toTime.hour * 60 + toTime.minute;

    final isInTimeWindow = currentTimeInMinutes >= fromTimeInMinutes &&
        currentTimeInMinutes < toTimeInMinutes;

    if (!isInTimeWindow) {
      return;
    }

    final text = 'Location Update: Lat: ${data.lat} Lon: ${data.lon}';
    sendNotification(text);
    await LocationDao().saveLocation(data);
    await _serverService.sendLocationToServer(data.lat, data.lon, source: 'Автоматическая');
    _lastUpdateTime = now; 
  }

  Future<Map<String, dynamic>?> _getOrRefreshUserStatus(String userId, SharedPreferences prefs) async {
    final lastStatusTimestamp = prefs.getInt('last_status_timestamp') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    const eightHoursInMillis = 8 * 60 * 60 * 1000;
// const twentySecondsInMillis = 20 * 1000;

    final cachedStatusJson = prefs.getString('cached_user_status');
    if (cachedStatusJson == null || (now - lastStatusTimestamp >= eightHoursInMillis)) {
      final status = await _serverService.getUserStatus(userId);
      if (status != null) {
        await prefs.setString('cached_user_status', jsonEncode(status));
        await prefs.setInt('last_status_timestamp', now);
        return status;
      } else {
      }
    }

    if (cachedStatusJson != null) {
      try {
        final cachedStatus = jsonDecode(cachedStatusJson) as Map<String, dynamic>;
        return cachedStatus;
      } catch (e) {
      }
    }

    return null;
  }

  Future<void> _saveLocationAsPending(BackgroundLocationUpdateData data) async {
    final now = DateTime.now();
    final formattedDate = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}'
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    final pendingData = {
      'latitude': data.lat,
      'longitude': data.lon,
      'date': formattedDate,
    };
    await _serverService._savePendingData(pendingData);
  }
}

class ServerService {
  static const String _username = 'Админ';
  static const String _password = '1';
  bool _isSendingPendingData = false;
  DateTime? _lastSentTime;
  static const int _minSendIntervalSeconds = 300;

  final _logController = StreamController<String>.broadcast();

  Stream<String> get logStream => _logController.stream;

  void init() async {
    _checkAndSendPendingData();
  }

  void dispose() {
    _logController.close();
  }

  Future<Map<String, dynamic>?> getUserStatus(String userId) async {
    try {
      final hasInternet = await _isInternetAvailable();
      if (!hasInternet) {
        return null;
      }

      String basicAuth = 'Basic ${base64Encode(utf8.encode('$_username:$_password'))}';

      final request = http.Request('GET', Uri.parse('http://192.168.88.200/MR_UZ/hs/data/auth'));
      request.headers.addAll({
        'Authorization': basicAuth,
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      });
      request.body = jsonEncode({'user_id': userId});

      final response = await request.send().timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception('Request timeout'),
      );

      final responseBody = await response.stream.bytesToString();
      print('DATA RESPONSE FROM API: User status response:====== ${response.statusCode} - $responseBody');

      if (response.statusCode == 200) {
        try {
          final data = jsonDecode(responseBody) as Map<String, dynamic>;
          return data;
        } catch (e) {
          return null;
        }
      } else {
        return null;
      }
    } catch (e) {
      return null;
    }
  }

  Future<bool> _isInternetAvailable() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      final isConnected = connectivityResult != ConnectivityResult.none;
      if (!isConnected) return false;

      final response = await http.get(Uri.parse('http://192.168.88.200')).timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw Exception('Server ping timeout'),
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<bool> _canSendLocation() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final gps = prefs.getBool('gps') ?? true;
      final from = prefs.getString('from') ?? '0001-01-01T08:00:00';
      final to = prefs.getString('to') ?? '0001-01-01T18:00:00';

      if (!gps) {
        return false;
      }

      final now = DateTime.now();
      final fromTime = DateTime.parse(from);
      final toTime = DateTime.parse(to);

      final currentTimeInMinutes = now.hour * 60 + now.minute;
      final fromTimeInMinutes = fromTime.hour * 60 + fromTime.minute;
      final toTimeInMinutes = toTime.hour * 60 + toTime.minute;

      return currentTimeInMinutes >= fromTimeInMinutes &&
          currentTimeInMinutes < toTimeInMinutes;
    } catch (e) {
      return false;
    }
  }

  Future<void> _savePendingData(Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> pendingData = prefs.getStringList('pending_locations') ?? [];
      const maxQueueSize = 10000;
      if (pendingData.length >= maxQueueSize) {
        pendingData.removeAt(0);
      }
      pendingData.add(jsonEncode(data));
      await prefs.setStringList('pending_locations', pendingData);
    } catch (e) {
    }
  }

  Future<void> _checkAndSendPendingData() async {
    if (_isSendingPendingData) return;
    _isSendingPendingData = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> pendingData = prefs.getStringList('pending_locations') ?? [];

      if (pendingData.isEmpty) return;

      final canSend = await _canSendLocation();
      if (!canSend) return;

      List<Map<String, dynamic>> dataList = pendingData.map((dataString) {
        try {
          return jsonDecode(dataString) as Map<String, dynamic>;
        } catch (e) {
          return <String, dynamic>{};
        }
      }).where((data) => data.isNotEmpty).toList();

      if (dataList.isEmpty) {
        return;
      }

      String basicAuth = 'Basic ${base64Encode(utf8.encode('$_username:$_password'))}';
      int retryCount = 0;
      const maxRetries = 3;
      bool success = false;

      while (retryCount < maxRetries && !success) {
        try {
          final response = await http.post(
            Uri.parse('http://192.168.88.200/MR_UZ/hs/data/coordinates'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': basicAuth,
            },
            body: jsonEncode(dataList),
          ).timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw Exception('Request timeout'),
          );


          if (response.statusCode == 200) {
            await prefs.setStringList('pending_locations', []);
            success = true;
            _lastSentTime = DateTime.now();
          } else {
            retryCount++;
            if (retryCount < maxRetries) {
              await Future.delayed(const Duration(seconds: 5));
            }
          }
        } catch (e) {
          retryCount++;
          if (retryCount < maxRetries) {
            await Future.delayed(const Duration(seconds: 5));
          }
        }
      }

      if (!success) {
      }
    } finally {
      _isSendingPendingData = false;
    }
  }

  Future<void> sendLocationToServer(double latitude, double longitude, {String source = 'Автоматическая'}) async {
    try {
      final now = DateTime.now();
      if (_lastSentTime != null &&
          now.difference(_lastSentTime!).inSeconds < _minSendIntervalSeconds) {
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id');

      final formattedDate = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}'
          '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
      final data = {
        'user_id': userId,
        'latitude': latitude,
        'longitude': longitude,
        'date': formattedDate,
      };

      await _savePendingData(data);
      await _checkAndSendPendingData();
      _logController.add('$source отправка: lat=$latitude, lon=$longitude, time=$now');
    } catch (e) {
    }
  }
}

class LocationDao {
  static const _locationsKey = 'background_updated_locations';
  static const _locationSeparator = '-/-/-/';

  static LocationDao? _instance;

  LocationDao._();

  factory LocationDao() => _instance ??= LocationDao._();

  SharedPreferences? _prefs;

  Future<SharedPreferences> get prefs async => _prefs ??= await SharedPreferences.getInstance();

  Future<void> saveLocation(BackgroundLocationUpdateData data) async {
    final locations = await getLocations();
    final now = DateTime.now();
    final formattedDate = _formatDateTime(now);
    final locationString = '$formattedDate - Широта: ${data.lat.toStringAsFixed(6)}, Долгота: ${data.lon.toStringAsFixed(6)}';
    locations.add(locationString);
    await (await prefs).setString(_locationsKey, locations.join(_locationSeparator));
  }

  Future<List<String>> getLocations() async {
    final prefs = await this.prefs;
    await prefs.reload();
    final locationsString = prefs.getString(_locationsKey);
    if (locationsString == null) return [];
    return locationsString.split(_locationSeparator);
  }

  Future<void> clear() async {
    final prefs = await this.prefs;
    final userId = prefs.getString('user_id');
    await prefs.clear();
    if (userId != null) {
      await prefs.setString('user_id', userId);
    }
  }
}

// void sendNotification(String text) {
// }

void sendNotification(String text) {
  // const settings = InitializationSettings(
  //   android: AndroidInitializationSettings('@mipmap/ic_launcher'),
  //   iOS: DarwinInitializationSettings(
  //     requestAlertPermission: false,
  //     requestBadgePermission: false,
  //     requestSoundPermission: false,
  //   ),
  // );
  // FlutterLocalNotificationsPlugin().initialize(settings);
  // FlutterLocalNotificationsPlugin().show(
  //   Random().nextInt(9999),
  //   'Title',
  //   text,
  //   const NotificationDetails(
  //     android: AndroidNotificationDetails('test_notification', 'Test'),
  //     iOS: DarwinNotificationDetails(),
  //   ),
  // );
}
