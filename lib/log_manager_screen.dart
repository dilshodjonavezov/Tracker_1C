// import 'package:shared_preferences/shared_preferences.dart';

// class LogManager {
//   static const String _logKey = 'persistent_logs';
//   static const String _userLogKey = 'user_logs';
//   static const String _logSeparator = '|';
//   static const int _maxLogCount = 1000;
//   static const int _maxUserLogCount = 100;

//   static LogManager? _instance;

//   LogManager._();

//   factory LogManager() => _instance ??= LogManager._();

//   Future<void> log(String message) async {
//     final prefs = await SharedPreferences.getInstance();
//     final existingLogs = prefs.getStringList(_logKey) ?? [];
//     final timestamp = DateTime.now().toIso8601String();
//     final logEntry = '$timestamp - $message';
//     existingLogs.add(logEntry);
//     if (existingLogs.length > _maxLogCount) {
//       existingLogs.removeRange(0, existingLogs.length - _maxLogCount);
//     }
//     await prefs.setStringList(_logKey, existingLogs);
//     print('LogManager: Saved log - $logEntry, total logs: ${existingLogs.length}');
//   }

//   Future<void> logUser(String category, String message) async {
//     final prefs = await SharedPreferences.getInstance();
//     final existingUserLogs = prefs.getStringList(_userLogKey) ?? [];
//     final timestamp = _formatDateTime(DateTime.now());
//     final logEntry = '$timestamp$_logSeparator$category$_logSeparator$message';
//     existingUserLogs.add(logEntry);
//     if (existingUserLogs.length > _maxUserLogCount) {
//       existingUserLogs.removeRange(0, existingUserLogs.length - _maxUserLogCount);
//     }
//     await prefs.setStringList(_userLogKey, existingUserLogs);
//     print('LogManager: Saved user log - $category: $message, total user logs: ${existingUserLogs.length}');
//   }

//   Future<List<String>> getLogs() async {
//     final prefs = await SharedPreferences.getInstance();
//     await prefs.reload();
//     return prefs.getStringList(_logKey) ?? [];
//   }

//   Future<List<Map<String, String>>> getUserLogs() async {
//     final prefs = await SharedPreferences.getInstance();
//     await prefs.reload();
//     final userLogs = prefs.getStringList(_userLogKey) ?? [];
//     return userLogs.map((log) {
//       final parts = log.split(_logSeparator);
//       return {
//         'timestamp': parts[0],
//         'category': parts[1],
//         'message': parts[2],
//       };
//     }).toList();
//   }

//   Future<void> clearLogs() async {
//     final prefs = await SharedPreferences.getInstance();
//     await prefs.remove(_logKey);
//     print('LogManager: Developer logs cleared');
//   }

//   Future<void> clearUserLogs() async {
//     final prefs = await SharedPreferences.getInstance();
//     await prefs.remove(_userLogKey);
//     print('LogManager: User logs cleared');
//   }

//   String _formatDateTime(DateTime dateTime) {
//     return '${dateTime.day.toString().padLeft(2, '0')}.${dateTime.month.toString().padLeft(2, '0')}.${dateTime.year} '
//         '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';
//   }
// }