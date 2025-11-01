import 'package:shared_preferences/shared_preferences.dart';

class LogManager {
  static const String _logKey = 'persistent_logs';
  static const String _logSeparator = '|';
  static const int _maxLogCount = 1000;

  static LogManager? _instance;

  LogManager._();

  factory LogManager() => _instance ??= LogManager._();

  Future<void> log(String message) async {
    final prefs = await SharedPreferences.getInstance();
    final existingLogs = prefs.getStringList(_logKey) ?? [];
    final logEntry = '${DateTime.now().toIso8601String()} - $message';
    existingLogs.add(logEntry);
    if (existingLogs.length > _maxLogCount) existingLogs.removeRange(0, existingLogs.length - _maxLogCount);
    await prefs.setStringList(_logKey, existingLogs);
    print('LogManager: Saved log - $logEntry, total logs: ${existingLogs.length}');
  }

  Future<List<String>> getLogs() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_logKey) ?? [];
  }

  Future<void> clearLogs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_logKey);
  }
}