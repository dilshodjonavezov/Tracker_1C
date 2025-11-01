// import 'dart:async';
// import 'package:background_location_tracker_example/log_manager_screen.dart';
// import 'package:background_location_tracker_example/main.dart';
// import 'package:background_location_tracker_example/server_service.dart';
// import 'package:flutter/material.dart';
// import 'package:background_location_tracker_example/log_manager.dart';
// import 'package:shared_preferences/shared_preferences.dart';

// class UserLogScreen extends StatefulWidget {
//   const UserLogScreen({Key? key}) : super(key: key);

//   @override
//   _UserLogScreenState createState() => _UserLogScreenState();
// }

// class _UserLogScreenState extends State<UserLogScreen> {
//   List<Map<String, String>> _userLogs = [];
//   Timer? _refreshTimer;

//   @override
//   void initState() {
//     super.initState();
//     print('UserLogScreen: Initializing');
//     _loadUserLogs();
//     _startPeriodicRefresh();
//   }

//   Future<void> _loadUserLogs() async {
//     final logs = await LogManager().getUserLogs();
//     setState(() {
//       _userLogs = logs.reversed.toList();
//     });
//     print('UserLogScreen: Loaded ${_userLogs.length} user logs');
//   }

//   void _startPeriodicRefresh() {
//     _refreshTimer?.cancel();
//     _refreshTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
//       print('UserLogScreen: Periodic log refresh triggered');
//       await _loadUserLogs();
//     });
//   }

//   @override
//   void dispose() {
//     print('UserLogScreen: Disposing');
//     _refreshTimer?.cancel();
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: GestureDetector(
//           onLongPress: () {
//             print('UserLogScreen: Navigating to DevLogScreen');
//             Navigator.push(
//               context,
//               MaterialPageRoute(builder: (context) => const DevLogScreen()),
//             );
//           },
//           child: const Text('История работы', style: TextStyle(color: Colors.white)),
//         ),
//         backgroundColor: Colors.teal,
//         foregroundColor: Colors.white,
//         centerTitle: true,
//       ),
//       body: Padding(
//         padding: const EdgeInsets.all(16),
//         child: Column(
//           children: [
//             Row(
//               mainAxisAlignment: MainAxisAlignment.spaceBetween,
//               children: [
//                 Text(
//                   'Записей: ${_userLogs.length}',
//                   style: const TextStyle(fontSize: 16, color: Colors.teal),
//                 ),
//                 TextButton(
//                   onPressed: () async {
//                     await LogManager().clearUserLogs();
//                     setState(() {
//                       _userLogs = [];
//                     });
//                     print('UserLogScreen: User logs cleared');
//                   },
//                   child: const Text('Очистить', style: TextStyle(color: Colors.red)),
//                 ),
//               ],
//             ),
//             const SizedBox(height: 8),
//             Expanded(
//               child: _userLogs.isEmpty
//                   ? const Center(
//                       child: Text(
//                         'Нет записей',
//                         style: TextStyle(fontSize: 16, color: Colors.grey),
//                       ),
//                     )
//                   : ListView.builder(
//                       itemCount: _userLogs.length,
//                       itemBuilder: (context, index) {
//                         final log = _userLogs[index];
//                         final category = log['category'] ?? 'Общее';
//                         final message = log['message'] ?? '';
//                         final timestamp = log['timestamp'] ?? '';

//                         Color categoryColor;
//                         IconData icon;
//                         switch (category) {
//                           case 'Успех':
//                             categoryColor = Colors.green;
//                             icon = Icons.check_circle;
//                             break;
//                           case 'Причина':
//                             categoryColor = Colors.red;
//                             icon = Icons.error;
//                             break;
//                           case 'Сохранено':
//                             categoryColor = Colors.blue;
//                             icon = Icons.save;
//                             break;
//                           default:
//                             categoryColor = Colors.grey;
//                             icon = Icons.info;
//                         }

//                         return Card(
//                           color: Colors.white,
//                           margin: const EdgeInsets.symmetric(vertical: 4),
//                           child: ListTile(
//                             leading: Icon(icon, color: categoryColor),
//                             title: Text(
//                               message,
//                               style: TextStyle(
//                                 fontSize: 14,
//                                 fontWeight: FontWeight.bold,
//                                 color: categoryColor,
//                               ),
//                             ),
//                             subtitle: Text(
//                               timestamp,
//                               style: const TextStyle(fontSize: 12, color: Colors.grey),
//                             ),
//                           ),
//                         );
//                       },
//                     ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }

// class DevLogScreen extends StatefulWidget {
//   const DevLogScreen({Key? key}) : super(key: key);

//   @override
//   _DevLogScreenState createState() => _DevLogScreenState();
// }

// class _DevLogScreenState extends State<DevLogScreen> {
//   List<String> _logs = [];
//   String _filter = 'Все';
//   final List<String> _categories = ['Все', 'Сеть', 'Авторизация', 'Отправка координат', 'Ошибки'];
//   Timer? _refreshTimer;
//   final _serverService = ServerService();
//   StreamSubscription<String>? _logSubscription;

//   @override
//   void initState() {
//     super.initState();
//     print('DevLogScreen: Initializing');
//     _loadLogs();
//     _startPeriodicRefresh();
//     _subscribeToLogStream();
//   }

//   Future<void> _loadLogs() async {
//     final logs = await LogManager().getLogs();
//     setState(() {
//       _logs = logs.reversed.toList();
//       if (_filter != 'Все') {
//         _logs = _logs.where((log) {
//           if (_filter == 'Ошибки') return log.contains('status=401') || log.contains('Exception');
//           if (_filter == 'Сеть') return log.contains('ServerService.isInternetAvailable') || log.contains('Connectivity');
//           if (_filter == 'Авторизация') return log.contains('ServerService.getUserStatus');
//           if (_filter == 'Отправка координат') return log.contains('ServerService.sendLocationToServer');
//           return true;
//         }).toList();
//       }
//     });
//     print('DevLogScreen: Loaded ${_logs.length} logs');
//   }

//   void _startPeriodicRefresh() {
//     _refreshTimer?.cancel();
//     _refreshTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
//       print('DevLogScreen: Periodic log refresh triggered');
//       await _loadLogs();
//     });
//   }

//   void _subscribeToLogStream() {
//     _logSubscription?.cancel();
//     _logSubscription = _serverService.logStream.listen((log) async {
//       print('DevLogScreen: Received stream log: $log');
//       await LogManager().log(log);
//       await _loadLogs();
//     });
//   }

//   @override
//   void dispose() {
//     print('DevLogScreen: Disposing');
//     _refreshTimer?.cancel();
//     _logSubscription?.cancel();
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: const Text('Логи для разработчиков', style: TextStyle(color: Colors.white)),
//         backgroundColor: Colors.teal,
//         foregroundColor: Colors.white,
//         actions: [
//           IconButton(
//             icon: const Icon(Icons.people),
//             onPressed: () {
//               print('DevLogScreen: Navigating to UserLogScreen');
//               Navigator.pushReplacement(
//                 context,
//                 MaterialPageRoute(builder: (context) => const UserLogScreen()),
//               );
//             },
//             tooltip: 'Перейти к пользовательским логам',
//           ),
//         ],
//       ),
//       body: Padding(
//         padding: const EdgeInsets.all(16),
//         child: Column(
//           children: [
//             DropdownButton<String>(
//               value: _filter,
//               items: _categories.map((category) => DropdownMenuItem(
//                 value: category,
//                 child: Text(category),
//               )).toList(),
//               onChanged: (value) {
//                 setState(() {
//                   _filter = value!;
//                   _loadLogs();
//                 });
//               },
//             ),
//             Row(
//               mainAxisAlignment: MainAxisAlignment.spaceBetween,
//               children: [
//                 Text(
//                   'Всего логов: ${_logs.length}',
//                   style: const TextStyle(fontSize: 16, color: Colors.teal),
//                 ),
//                 TextButton(
//                   onPressed: () async {
//                     await LogManager().clearLogs();
//                     setState(() {
//                       _logs = [];
//                     });
//                     print('DevLogScreen: Logs cleared');
//                   },
//                   child: const Text('Очистить логи', style: TextStyle(color: Colors.red)),
//                 ),
//               ],
//             ),
//             const SizedBox(height: 8),
//             Expanded(
//               child: _logs.isEmpty
//                   ? const Center(
//                       child: Text(
//                         'Логи отсутствуют',
//                         style: TextStyle(fontSize: 16, color: Colors.grey),
//                       ),
//                     )
//                   : ListView.builder(
//                       itemCount: _logs.length,
//                       itemBuilder: (context, index) {
//                         final log = _logs[index];
//                         String category = 'Общее';
//                         Color categoryColor = Colors.grey;
//                         if (log.contains('ServerService.getUserStatus')) {
//                           category = 'Авторизация';
//                           categoryColor = Colors.blue;
//                         } else if (log.contains('ServerService.sendLocationToServer')) {
//                           category = 'Отправка координат';
//                           categoryColor = Colors.green;
//                         } else if (log.contains('ServerService.isInternetAvailable') || log.contains('Connectivity')) {
//                           category = 'Сеть';
//                           categoryColor = Colors.orange;
//                         } else if (log.contains('status=401') || log.contains('Exception')) {
//                           category = 'Ошибка';
//                           categoryColor = Colors.red;
//                         }

//                         return Card(
//                           color: Colors.white,
//                           margin: const EdgeInsets.symmetric(vertical: 4),
//                           child: ExpansionTile(
//                             title: Text(
//                               '[$category] ${log.split(' - ').first}',
//                               style: TextStyle(
//                                 fontSize: 14,
//                                 fontWeight: FontWeight.bold,
//                                 color: categoryColor,
//                               ),
//                             ),
//                             subtitle: Text(
//                               log.split(' - ').sublist(1).join(' - '),
//                               style: const TextStyle(fontSize: 12),
//                               maxLines: 2,
//                               overflow: TextOverflow.ellipsis,
//                             ),
//                             children: [
//                               Padding(
//                                 padding: const EdgeInsets.all(8),
//                                 child: Text(
//                                   log,
//                                   style: const TextStyle(fontSize: 12, fontFamily: 'Courier'),
//                                 ),
//                               ),
//                             ],
//                           ),
//                         );
//                       },
//                     ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }