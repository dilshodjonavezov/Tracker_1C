import 'dart:io';

import 'package:flutter/material.dart';
import 'package:background_location_tracker_example/services/permission_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:background_location_tracker/background_location_tracker.dart';
import 'package:workmanager/workmanager.dart';
import 'background_callback.dart';
import 'diagnostic_callback.dart';
import 'screens/user_id_input_screen.dart';
import 'screens/my_app.dart';
import 'dao/location_dao.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  print('Main: Starting application initialization at ${DateTime.now()}');

  // ✅ Сначала инициализируем всё ПЕРЕД runApp
  await PermissionManager.requestAllPermissions();

  await LocationDao().clear();
  print('Main: Cleared visible location history on app start');

  // 🔧 ИЗМЕНЕНО: Интервал получения GPS координат сокращён с 300 до 5 секунд
  // 📍 trackingInterval = 5 секунд - как часто система запрашивает координаты GPS
  await BackgroundLocationTrackerManager.initialize(
    backgroundCallback,
    config: const BackgroundLocationTrackerConfig(
      loggingEnabled: true,
      androidConfig: AndroidConfig(
        notificationIcon: 'ic_launcher',
        trackingInterval: Duration(seconds: 5), // ⏱️ 5 секунд - получение GPS
        distanceFilterMeters:
            5.0, // 📏 5 метров - минимальное изменение расстояния
      ),
    ),
  );
  print('Main: Background tracker initialized with 5-second GPS interval');

  if (Platform.isAndroid) {
    try {
      await Workmanager().initialize(diagnosticCallbackDispatcher);
      await Workmanager().registerPeriodicTask(
        locationDiagnosticUniqueName,
        locationDiagnosticTaskName,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingWorkPolicy.update,
      );
      print('Main: Location diagnostic background task registered');
    } catch (e) {
      print(
          'Main: Location diagnostic background task registration failed: $e');
    }
  }

  // ✅ Проверяем userId
  final prefs = await SharedPreferences.getInstance();
  String? userId = prefs.getString('user_id');

  // ✅ Только теперь запускаем UI с правильным экраном
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: userId == null || userId.isEmpty
          ? const UserIdInputScreen()
          : const MyApp(),
    ),
  );

  print('Main: App running at ${DateTime.now()}');
}
