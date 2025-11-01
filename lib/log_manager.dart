  import 'dart:async';
  import 'package:background_location_tracker_example/log_manager_screen.dart';
  import 'package:background_location_tracker_example/managers/log_manager.dart';
  import 'package:background_location_tracker_example/server_service.dart';
  import 'package:background_location_tracker_example/services/server_service.dart';
  import 'package:flutter/material.dart';
  import 'package:flutter/services.dart'; // Для копирования в буфер обмена
  import 'main.dart'; // Импортируем основной файл с ServerService и LogManager

  class LogScreen extends StatefulWidget {
    const LogScreen({Key? key}) : super(key: key);

    @override
    _LogScreenState createState() => _LogScreenState();
  }

  class _LogScreenState extends State<LogScreen> {
    List<String> _logs = [];
    Timer? _refreshTimer;
    final _serverService = ServerService();
    StreamSubscription<String>? _logSubscription;

    @override
    void initState() {
      super.initState();
      print('LogScreen: Initializing');
      _loadLogs();
      _startPeriodicRefresh();
      _subscribeToLogStream();
    }

  Future<void> _loadLogs() async {
    print('LogScreen: Loading logs');
    final logs = await LogManager().getLogs();
    print('LogScreen: Loaded ${logs.length} logs');
    setState(() {
      _logs = logs.reversed.toList();
      print('LogScreen: setState called with ${_logs.length} logs');
    });
  }

    void _startPeriodicRefresh() {
      _refreshTimer?.cancel();
      _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
        print('LogScreen: Periodic log refresh triggered');
        await _loadLogs();
      });
    }

  void _subscribeToLogStream() {
    _logSubscription?.cancel();
    _logSubscription = _serverService.logStream.listen((log) async {
      print('LogScreen: Received stream log: $log');
      await LogManager().log(log);
      await _loadLogs(); // Перезагружаем логи
    });
  }

    @override
    void dispose() {
      print('LogScreen: Disposing');
      _refreshTimer?.cancel();
      _logSubscription?.cancel();
      super.dispose();
    }

  @override
  Widget build(BuildContext context) {
    print('LogScreen: Building UI with ${_logs.length} logs');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Логи приложения'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Всего логов: ${_logs.length}',
                  style: const TextStyle(fontSize: 16, color: Colors.teal),
                ),
                TextButton(
                  onPressed: () async {
                    print('LogScreen: Clearing logs');
                    await LogManager().clearLogs();
                    setState(() {
                      _logs = [];
                      print('LogScreen: Logs cleared, setState called');
                    });
                  },
                  child: const Text('Очистить логи', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _logs.isEmpty
                  ? const Center(
                      child: Text(
                        'Логи отсутствуют',
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      key: ValueKey(_logs.length), // Уникальный ключ для принудительного перестроения
                      itemCount: _logs.length,
                      itemBuilder: (context, index) {
                        final log = _logs[index];
                        String category = 'Общее';
                        Color categoryColor = Colors.grey;
                        if (log.contains('ServerService.getUserStatus')) {
                          category = 'Авторизация';
                          categoryColor = Colors.blue;
                        } else if (log.contains('ServerService.sendLocationToServer')) {
                          category = 'Отправка координат';
                          categoryColor = Colors.green;
                        } else if (log.contains('ServerService.isInternetAvailable')) {
                          category = 'Сеть';
                          categoryColor = Colors.orange;
                        }

                        return Card(
                          color: Colors.white,
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ExpansionTile(
                            title: Text(
                              '[$category] ${log.split(' - ').first}',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: categoryColor,
                              ),
                            ),
                            subtitle: Text(
                              log.split(' - ').sublist(1).join(' - '),
                              style: const TextStyle(fontSize: 12),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(8),
                                child: Text(
                                  log,
                                  style: const TextStyle(fontSize: 12, fontFamily: 'Courier'),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
  }