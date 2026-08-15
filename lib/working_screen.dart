import 'package:background_location_tracker_example/log_manager.dart';
import 'package:background_location_tracker_example/managers/log_manager.dart';
import 'package:background_location_tracker_example/screens/location_report_screen.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TrackingScreen extends StatefulWidget {
  const TrackingScreen({Key? key}) : super(key: key);

  @override
  _TrackingScreenState createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen>
    with WidgetsBindingObserver {
  String? userId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeTracking();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Отслеживаем состояние приложения
    if (state == AppLifecycleState.resumed) {
      print('TrackingScreen: App resumed, reloading userId');
      _loadUserId();
    } else if (state == AppLifecycleState.paused) {
      print('TrackingScreen: App paused, ensuring data is saved');
      _ensureDataPersisted();
    }
  }

  Future<void> _initializeTracking() async {
    await LogManager().log('TrackingScreen: Initializing tracking screen');
    await _loadUserId();
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _loadUserId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? loadedUserId = prefs.getString('user_id');

      if (loadedUserId == null || loadedUserId.isEmpty) {
        await LogManager()
            .log('TrackingScreen: WARNING - userId is null or empty!');
        // Проверяем резервную копию
        loadedUserId = prefs.getString('user_id_backup');
        if (loadedUserId != null && loadedUserId.isNotEmpty) {
          await prefs.setString('user_id', loadedUserId);
          await LogManager().log(
              'TrackingScreen: Restored userId from backup: $loadedUserId');
        } else {
          // Если нет резервной копии, перенаправляем на экран логина
          await LogManager()
              .log('TrackingScreen: No valid userId, redirecting to login');
          Navigator.of(context).pushReplacementNamed('/');
          return;
        }
      }

      setState(() {
        userId = loadedUserId;
      });
      await LogManager().log('TrackingScreen: Loaded userId: $loadedUserId');
    } catch (e) {
      await LogManager().log('TrackingScreen: ERROR loading userId: $e');
    }
  }

  Future<void> _ensureDataPersisted() async {
    try {
      if (userId != null && userId!.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_id', userId!);
        await prefs.setString('user_id_backup', userId!); // Резервная копия
        await LogManager()
            .log('TrackingScreen: userId persisted before pause: $userId');
      }
    } catch (e) {
      await LogManager().log('TrackingScreen: ERROR persisting userId: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.cyan[800],
      appBar: AppBar(
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        title: const Text('Отслеживание активно'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const LocationReportScreen(),
                ),
              );
            },
            tooltip: 'Отчёт GPS',
          ),
          IconButton(
            icon: const Icon(Icons.list_alt),
            onPressed: () {
              print('TrackingScreen: Navigating to LogScreen');
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const LogScreen()),
              );
            },
            tooltip: 'Просмотр логов',
          ),
          // Кнопка для принудительной перезагрузки userId
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              await LogManager().log('TrackingScreen: Manual reload triggered');
              await _loadUserId();
            },
            tooltip: 'Обновить данные',
          ),
        ],
      ),
      body: Center(
        child: _isLoading
            ? const CircularProgressIndicator(color: Colors.white)
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Card(
                    color: Colors.white,
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Text(
                            'USER ID:',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey[400],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            userId ?? 'Не загружен',
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: userId != null ? Colors.black : Colors.red,
                            ),
                          ),
                          if (userId == null) ...[
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: () async {
                                // Возвращаемся на экран авторизации
                                Navigator.of(context).pushReplacementNamed('/');
                              },
                              icon: const Icon(Icons.login),
                              label: const Text('Войти заново'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Индикатор работы фонового сервиса
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: const BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Фоновое отслеживание активно',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
