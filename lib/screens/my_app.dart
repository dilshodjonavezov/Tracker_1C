  import 'dart:async';
import 'package:background_location_tracker_example/dao/location_dao.dart';
import 'package:background_location_tracker_example/log_manager.dart';
import 'package:background_location_tracker_example/login_screen.dart';
import 'package:background_location_tracker_example/working_screen.dart';
import 'package:flutter/material.dart';
import 'package:background_location_tracker/background_location_tracker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:background_location_tracker_example/managers/log_manager.dart';
import 'package:background_location_tracker_example/services/server_service.dart';

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
  final ServerService _serverService = ServerService();
  bool _isStatusCheckInProgress = false;
  StreamSubscription<String>? _logSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _getTrackingStatus();
        _startLocationsUpdatesStream();
        _serverService.init();
        _startStatusCheckTimer();
        _subscribeToLogStream();
      }
    });
  }

  void _subscribeToLogStream() {
    _logSubscription = _serverService.logStream.listen((log) {
      if (log == 'AUTH_REQUIRED') Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const UserIdInputScreen()));
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _statusCheckTimer?.cancel();
    _logSubscription?.cancel();
    _serverService.dispose();
    super.dispose();
  }

  void _startStatusCheckTimer() {
    _statusCheckTimer?.cancel();
    _checkUserStatus();
    _statusCheckTimer = Timer.periodic(const Duration(hours: 8), (_) => _checkUserStatus());
  }

  Future<void> _checkUserStatus() async {
    if (_isStatusCheckInProgress) return;
    _isStatusCheckInProgress = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id');
      if (userId == null) return;

      final status = await _serverService.getUserStatus(userId);
      if (status != null) {
        await prefs.setBool('gps', status['gps'] ?? true);
        await prefs.setString('from', status['from'] ?? '0001-01-01T08:00:00');
        await prefs.setString('to', status['to'] ?? '0001-01-01T18:00:00');
        final now = DateTime.now();
        final fromTime = DateTime.parse(status['from'] ?? '0001-01-01T08:00:00');
        final toTime = DateTime.parse(status['to'] ?? '0001-01-01T18:00:00');
        final isInTimeWindow = now.hour * 60 + now.minute >= fromTime.hour * 60 + fromTime.minute &&
            now.hour * 60 + now.minute < toTime.hour * 60 + toTime.minute;
        if (!(status['gps'] ?? true) || !isInTimeWindow) {
          if (isTracking) {
            await BackgroundLocationTrackerManager.stopTracking();
            setState(() => isTracking = false);
          }
        } else if (!isTracking) {
          await BackgroundLocationTrackerManager.startTracking();
          setState(() => isTracking = true);
        }
      }
    } catch (e) {
      print('MyAppState: Error checking status: $e');
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
        textTheme: const TextTheme(bodyMedium: TextStyle(fontSize: 16, color: Colors.black87), titleLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.teal)),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), backgroundColor: Colors.teal, foregroundColor: Colors.white),
        ),
      ),
      home: isTracking ? const TrackingScreen() : _buildMainScreen(),
    );
  }

  Widget _buildMainScreen() {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: Container(
          decoration: const BoxDecoration(borderRadius: BorderRadius.only(bottomLeft: Radius.circular(20), bottomRight: Radius.circular(20)), color: Colors.teal),
          child: AppBar(
            title: const Text('Трекер местоположения', style: TextStyle(color: Colors.white)),
            backgroundColor: Colors.transparent,
            centerTitle: true,
            actions: [
              IconButton(icon: const Icon(Icons.list_alt, color: Colors.white), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LogScreen())), tooltip: 'Просмотр логов'),
            ],
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
                    const Text('Контроль', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.teal)),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: Icon(isTracking ? Icons.stop : Icons.play_arrow),
                            label: Text(isTracking ? 'Остановить' : 'Начать'),
                            onPressed: isTracking
                                ? () async {
                                    await LocationDao().clear();
                                    await BackgroundLocationTrackerManager.stopTracking();
                                    setState(() => isTracking = false);
                                  }
                                : () async {
                                    await BackgroundLocationTrackerManager.startTracking();
                                    setState(() => isTracking = true);
                                  },
                            style: ElevatedButton.styleFrom(backgroundColor: isTracking ? Colors.redAccent : Colors.teal),
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
                          const Expanded(child: Text('История местоположений', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.teal), overflow: TextOverflow.ellipsis)),
                          if (_locations.isNotEmpty)
                            TextButton(onPressed: () async { await LocationDao().clear(); setState(() => _locations = []); }, child: const Text('Очистить', style: TextStyle(color: Colors.red))),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: _locations.isEmpty
                            ? const Center(child: Text('Местоположение пока не сохранено.', style: TextStyle(fontSize: 16, color: Colors.grey)))
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
                                      title: Text(parts[1], style: const TextStyle(fontSize: 12)),
                                      subtitle: Text(parts[0], style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
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
    final isTrackingActive = await BackgroundLocationTrackerManager.isTracking();
    setState(() => isTracking = isTrackingActive);
    if (!isTrackingActive) await BackgroundLocationTrackerManager.startTracking();
  }

  Future<void> _getLocations() async {
    _locations = await LocationDao().getLocations();
    setState(() {});
  }

  void _startLocationsUpdatesStream() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _getLocations());
  }
}