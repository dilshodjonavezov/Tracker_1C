// import 'dart:async';
// import 'dart:convert';
// import 'package:background_location_tracker_example/log_manager_screen.dart';
// import 'package:connectivity_plus/connectivity_plus.dart';
// import 'package:http/http.dart' as http;
// import 'package:shared_preferences/shared_preferences.dart';
// import 'package:background_location_tracker_example/log_manager.dart';

// class ServerService {
//   static const String _baseUrl = 'http://192.168.88.249/MR';
//   static const String _username = 'testMobi';
//   static const String _password = 'nE8vecon';
//   String get _auth => 'Basic ${base64Encode(utf8.encode("$_username:$_password"))}';
//   bool _isSendingPendingData = false;
//   DateTime? _lastSentTime;
//   static const int _minSendIntervalSeconds = 10;
//   Timer? _periodicSendTimer;
//   final _logController = StreamController<String>.broadcast();
//   final _logManager = LogManager();

//   Stream<String> get logStream => _logController.stream;

//   void init() async {
//     await _logManager.log('ServerService: Initializing service');
//     await _logManager.log('ServerService: Base URL: $_baseUrl, Auth: $_auth');
//     await _checkAndSendPendingData();
//     _startPeriodicSending();
//     await _logManager.log('ServerService: Initialization completed');
//   }

//   void dispose() {
//     _logManager.log('ServerService: Disposing service');
//     _periodicSendTimer?.cancel();
//     _logController.close();
//   }

//   void _startPeriodicSending() async {
//     print('ServerService: Starting periodic sending every 10 seconds');
//     await _logManager.log('ServerService: Starting periodic sending every 10 seconds');
//     _periodicSendTimer?.cancel();
//     _periodicSendTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
//       print('ServerService: Periodic send triggered');
//       await _logManager.log('ServerService: Periodic send triggered');
//       await _sendLatestLocation();
//     });
//   }

//   Future<void> _sendLatestLocation() async {
//     print('ServerService: Attempting to send latest location');
//     await _logManager.log('ServerService: Attempting to send latest location');
//     try {
//       final prefs = await SharedPreferences.getInstance();
//       final userId = prefs.getString('user_id') ?? '21435';
//       await _logManager.log('ServerService: User ID: $userId');
//       final lastLocationJson = prefs.getString('last_location');
//       double latitude = 0.0;
//       double longitude = 0.0;
//       String source = 'Периодическая';

//       if (lastLocationJson != null) {
//         try {
//           final lastLocation = jsonDecode(lastLocationJson) as Map<String, dynamic>;
//           latitude = double.parse(lastLocation['latitude'] ?? '0.0');
//           longitude = double.parse(lastLocation['longitude'] ?? '0.0');
//           source = 'Периодическая (последнее местоположение)';
//           print('ServerService: Using last known location: lat=$latitude, lon=$longitude');
//           await _logManager.log('ServerService: Using last known location: lat=$latitude, lon=$longitude');
//         } catch (e) {
//           print('ServerService: Error decoding last location: $e');
//           await _logManager.log('ServerService: Error decoding last location: $e');
//         }
//       } else {
//         print('ServerService: No last location available, sending default coordinates');
//         await _logManager.log('ServerService: No last location available, sending default coordinates');
//       }

//       await sendLocationToServer(latitude, longitude, source: source);
//     } catch (e) {
//       print('ServerService: Error in periodic send: $e');
//       await _logManager.log('ServerService: Error in periodic send: $e');
//     }
//   }

//   Future<Map<String, dynamic>?> getUserStatus(String userId) async {
//     final logPrefix = 'ServerService.getUserStatus';
//     await _logManager.log('$logPrefix: Starting request for user_id=$userId');
    
//     try {
//       final connectivityResult = await Connectivity().checkConnectivity();
//       await _logManager.log('$logPrefix: Connectivity check: $connectivityResult');
//       final hasInternet = await _isInternetAvailable();
//       await _logManager.log('$logPrefix: Internet available: $hasInternet');
//       if (!hasInternet) {
//         await _logManager.log('$logPrefix: No internet, returning null');
//         await _logManager.logUser('Причина', 'Не удалось проверить статус: нет интернета');
//         return null;
//       }

//       final url = '$_baseUrl/hs/data/auth';
//       final headers = {
//         'Authorization': _auth,
//         'Content-Type': 'application/json',
//         'Accept': 'application/json',
//       };
//       final body = jsonEncode({'user_id': userId});
//       await _logManager.log('$logPrefix: Request details - URL: $url, Headers: $headers, Body: $body');

//       await _logManager.log('$logPrefix: Authorization header: $_auth');
//       await _logManager.log('$logPrefix: Username: $_username, Password: [HIDDEN]');

//       final response = await http.post(
//         Uri.parse(url),
//         headers: headers,
//         body: body,
//       ).timeout(const Duration(seconds: 10), onTimeout: () {
//         _logManager.log('$logPrefix: Request timeout for $url');
//         _logManager.logUser('Причина', 'Не удалось проверить статус: сервер не отвечает');
//         throw Exception('Request timeout');
//       });

//       await _logManager.log(
//         '$logPrefix: Response - Status: ${response.statusCode}, '
//         'Headers: ${response.headers}, '
//         'Body: ${response.body}, '
//         'Reason: ${response.reasonPhrase}',
//       );

//       if (response.statusCode == 200) {
//         try {
//           final data = jsonDecode(response.body) as Map<String, dynamic>;
//           await _logManager.log('$logPrefix: Successfully parsed response: $data');
//           await _logManager.logUser('Успех', 'Статус пользователя получен');
//           return data;
//         } catch (e) {
//           await _logManager.log('$logPrefix: Error parsing response body: $e');
//           await _logManager.logUser('Причина', 'Ошибка обработки данных от сервера');
//           return null;
//         }
//       } else {
//         await _logManager.log(
//           '$logPrefix: Server error - Status: ${response.statusCode}, '
//           'Reason: ${response.reasonPhrase}',
//         );
//         await _logManager.logUser('Причина', 'Ошибка сервера: ${response.statusCode}');
//         return null;
//       }
//     } catch (e, stackTrace) {
//       await _logManager.log('$logPrefix: Exception during request: $e, StackTrace: $stackTrace');
//       await _logManager.logUser('Причина', 'Не удалось проверить статус: ошибка связи');
//       return null;
//     }
//   }

//   Future<void> sendLocationToServer(double latitude, double longitude, {String source = 'Автоматическая'}) async {
//     final now = DateTime.now();
//     await _logManager.log('ServerService: Sending location: lat=$latitude, lon=$longitude, source=$source');
//     try {
//       final prefs = await SharedPreferences.getInstance();
//       final userId = prefs.getString('user_id') ?? '21435';
//       await _logManager.log('ServerService: User ID: $userId');

//       final hasInternet = await _isInternetAvailable();
//       await _logManager.log('ServerService: Internet availability: $hasInternet');
//       if (!hasInternet) {
//         await _logManager.log('ServerService: No internet, saving to pending');
//         await _logManager.logUser('Сохранено', 'Координаты сохранены для отправки позже: Широта $latitude, Долгота $longitude');
//         await _savePendingData({
//           'user_id': userId,
//           'latitude': latitude.toString(),
//           'longitude': longitude.toString(),
//           'date': _formatDateTime(now),
//         });
//         return;
//       }

//       final canSend = await _canSendLocation();
//       await _logManager.log('ServerService: Can send location: $canSend');
//       if (!canSend) {
//         await _logManager.log('ServerService: Sending prohibited (time/GPS), saving to pending');
//         await _logManager.logUser('Сохранено', 'Координаты сохранены: вне времени отправки');
//         await _savePendingData({
//           'user_id': userId,
//           'latitude': latitude.toString(),
//           'longitude': longitude.toString(),
//           'date': _formatDateTime(now),
//         });
//         return;
//       }

//       final formattedDate = _formatDateTime(now);
//       final data = {
//         'user_id': userId,
//         'latitude': latitude.toString(),
//         'longitude': longitude.toString(),
//         'date': formattedDate,
//       };
//       final headers = {
//         'Content-Type': 'application/json',
//         'Authorization': _auth,
//       };
//       await _logManager.log('ServerService: Prepared data: $data, Headers: $headers');

//       await prefs.setString('last_location', jsonEncode({
//         'latitude': latitude.toString(),
//         'longitude': longitude.toString(),
//       }));

//       final url = '$_baseUrl/hs/data/coordinates';
//       await _logManager.log('ServerService: POST request to $url');
//       final response = await http.post(
//         Uri.parse(url),
//         headers: headers,
//         body: jsonEncode([data]),
//       ).timeout(const Duration(seconds: 10), onTimeout: () {
//         _logManager.log('ServerService: Request timeout for $url');
//         _logManager.logUser('Причина', 'Не удалось отправить координаты: сервер не отвечает');
//         throw Exception('Request timeout');
//       });

//       await _logManager.log(
//           'ServerService: POST response: status=${response.statusCode}, headers=${response.headers}, body=${response.body}, reason=${response.reasonPhrase}');
//       if (response.statusCode == 200) {
//         _lastSentTime = now;
//         _logController.add('$source отправка: lat=$latitude, lon=$longitude, time=$now');
//         await _logManager.log('ServerService: Successful send, time: $now');
//         await _logManager.logUser('Успех', 'Координаты отправлены: Широта $latitude, Долгота $longitude');
//         await _checkAndSendPendingData();
//       } else {
//         await _logManager.log('ServerService: Send error: status=${response.statusCode}, reason=${response.reasonPhrase}');
//         await _logManager.logUser('Причина', 'Не удалось отправить координаты: ошибка сервера ${response.statusCode}');
//         await _savePendingData(data);
//       }
//     } catch (e) {
//       await _logManager.log('ServerService: Exception during send: $e');
//       await _logManager.logUser('Причина', 'Не удалось отправить координаты: ошибка связи');
//       await _savePendingData({
//         'latitude': latitude.toString(),
//         'longitude': longitude.toString(),
//         'date': _formatDateTime(now),
//       });
//     }
//   }

//   Future<void> _checkAndSendPendingData() async {
//     await _logManager.log('ServerService: Checking and sending pending data');
//     if (_isSendingPendingData) {
//       await _logManager.log('ServerService: Already sending pending data, skipping');
//       return;
//     }
//     _isSendingPendingData = true;
//     await _logManager.log('ServerService: Starting to send pending data');

//     try {
//       final prefs = await SharedPreferences.getInstance();
//       List<String> pendingData = prefs.getStringList('pending_locations') ?? [];
//       await _logManager.log('ServerService: Pending data count: ${pendingData.length}');

//       if (pendingData.isEmpty) {
//         await _logManager.log('ServerService: No pending data to send');
//         return;
//       }

//       final canSend = await _canSendLocation();
//       await _logManager.log('ServerService: Can send location: $canSend');
//       if (!canSend) {
//         await _logManager.log('ServerService: Sending prohibited (time/GPS), skipping');
//         return;
//       }

//       List<Map<String, dynamic>> dataList = pendingData.map((dataString) {
//         try {
//           return jsonDecode(dataString) as Map<String, dynamic>;
//         } catch (e) {
//           _logManager.log('ServerService: Error decoding pending data: $e');
//           _logManager.logUser('Причина', 'Ошибка обработки сохранённых координат');
//           return <String, dynamic>{};
//         }
//       }).where((data) => data.isNotEmpty).toList();
//       await _logManager.log('ServerService: Prepared data list: $dataList');

//       if (dataList.isEmpty) {
//         await _logManager.log('ServerService: Data list empty after filtering');
//         return;
//       }

//       int retryCount = 0;
//       const maxRetries = 3;
//       bool success = false;

//       while (retryCount < maxRetries && !success) {
//         await _logManager.log('ServerService: Attempt $retryCount to send pending data');
//         try {
//           final headers = {
//             'Content-Type': 'application/json',
//             'Authorization': _auth,
//           };
//           final url = '$_baseUrl/hs/data/coordinates';
//           await _logManager.log('ServerService: POST request for pending data: $url, Headers: $headers, Body: ${jsonEncode(dataList)}');
//           final response = await http.post(
//             Uri.parse(url),
//             headers: headers,
//             body: jsonEncode(dataList),
//           ).timeout(
//             const Duration(seconds: 10),
//             onTimeout: () => throw Exception('Request timeout'),
//           );

//           await _logManager.log(
//               'ServerService: POST response: status=${response.statusCode}, headers=${response.headers}, body=${response.body}, reason=${response.reasonPhrase}');
//           if (response.statusCode == 200) {
//             await prefs.setStringList('pending_locations', []);
//             success = true;
//             _lastSentTime = DateTime.now();
//             await _logManager.log('ServerService: Pending data sent, queue cleared');
//             await _logManager.logUser('Успех', 'Сохранённые координаты отправлены: ${dataList.length} записей');
//           } else {
//             retryCount++;
//             await _logManager.log(
//                 'ServerService: Send error: status=${response.statusCode}, reason=${response.reasonPhrase}, retrying');
//             await _logManager.logUser('Причина', 'Не удалось отправить сохранённые координаты: ошибка сервера ${response.statusCode}');
//             if (retryCount < maxRetries) {
//               await Future.delayed(const Duration(seconds: 5));
//             }
//           }
//         } catch (e) {
//           await _logManager.log('ServerService: Exception during pending data send: $e');
//           await _logManager.logUser('Причина', 'Не удалось отправить сохранённые координаты: ошибка связи');
//           retryCount++;
//           if (retryCount < maxRetries) {
//             await Future.delayed(const Duration(seconds: 5));
//           }
//         }
//       }

//       if (!success) {
//         await _logManager.log('ServerService: All retries for pending data failed');
//       }
//     } finally {
//       _isSendingPendingData = false;
//       await _logManager.log('ServerService: Pending data send completed');
//     }
//   }

//   Future<bool> _isInternetAvailable() async {
//     print('ServerService: Checking internet availability');
//     await _logManager.log('ServerService: Checking internet availability');
//     try {
//       final connectivityResult = await Connectivity().checkConnectivity();
//       print('ServerService: Connectivity result: $connectivityResult');
//       await _logManager.log('ServerService: Connectivity result: $connectivityResult');
//       final isConnected = connectivityResult != ConnectivityResult.none;
//       if (!isConnected) {
//         await _logManager.log('ServerService: No internet connection');
//         await _logManager.logUser('Причина', 'Нет подключения к интернету');
//         return false;
//       }

//       final url = '$_baseUrl';
//       await _logManager.log('ServerService: Pinging server: $url');
//       final response = await http.get(Uri.parse(url)).timeout(
//         const Duration(seconds: 5),
//         onTimeout: () => throw Exception('Server ping timeout'),
//       );
//       print('ServerService: Server ping response code: ${response.statusCode}, headers=${response.headers}, body=${response.body}');
//       await _logManager.log(
//           'ServerService: Server ping response: status=${response.statusCode}, headers=${response.headers}, body=${response.body}');
//       if (response.statusCode != 200) {
//         await _logManager.logUser('Причина', 'Сервер недоступен');
//       }
//       return response.statusCode == 200;
//     } catch (e) {
//       print('ServerService: Internet check failed: $e');
//       await _logManager.log('ServerService: Internet check failed: $e');
//       await _logManager.logUser('Причина', 'Ошибка проверки интернета');
//       return false;
//     }
//   }

//   Future<bool> _canSendLocation() async {
//     print('ServerService: Checking if location can be sent');
//     await _logManager.log('ServerService: Checking if location can be sent');
//     try {
//       final prefs = await SharedPreferences.getInstance();
//       final gps = prefs.getBool('gps') ?? true;
//       final from = prefs.getString('from') ?? '0001-01-01T08:00:00';
//       final to = prefs.getString('to') ?? '0001-01-01T18:00:00';
//       print('ServerService: GPS: $gps, From: $from, To: $to');
//       await _logManager.log('ServerService: GPS: $gps, From: $from, To: $to');

//       if (!gps) {
//         print('ServerService: GPS disabled, cannot send');
//         await _logManager.log('ServerService: GPS disabled, cannot send');
//         await _logManager.logUser('Причина', 'GPS отключён');
//         return false;
//       }

//       final now = DateTime.now();
//       final fromTime = DateTime.parse(from);
//       final toTime = DateTime.parse(to);
//       final currentTimeInMinutes = now.hour * 60 + now.minute;
//       final fromTimeInMinutes = fromTime.hour * 60 + fromTime.minute;
//       final toTimeInMinutes = toTime.hour * 60 + toTime.minute;
//       print('ServerService: Time check - now: $currentTimeInMinutes, from: $fromTimeInMinutes, to: $toTimeInMinutes');
//       await _logManager.log(
//           'ServerService: Time check - now: $currentTimeInMinutes, from: $fromTimeInMinutes, to: $toTimeInMinutes');

//       final result = currentTimeInMinutes >= fromTimeInMinutes && currentTimeInMinutes < toTimeInMinutes;
//       print('ServerService: Can send location: $result');
//       await _logManager.log('ServerService: Can send location: $result');
//       return result;
//     } catch (e) {
//       print('ServerService: Error in canSendLocation: $e');
//       await _logManager.log('ServerService: Error in canSendLocation: $e');
//       await _logManager.logUser('Причина', 'Ошибка проверки времени');
//       return false;
//     }
//   }

//   Future<void> _savePendingData(Map<String, dynamic> data) async {
//     print('ServerService: Saving pending data: $data');
//     await _logManager.log('ServerService: Saving pending data: $data');
//     try {
//       final prefs = await SharedPreferences.getInstance();
//       List<String> pendingData = prefs.getStringList('pending_locations') ?? [];
//       const maxQueueSize = 10000;
//       print('ServerService: Current pending data count: ${pendingData.length}');
//       await _logManager.log('ServerService: Current pending data count: ${pendingData.length}');
//       if (pendingData.length >= maxQueueSize) {
//         pendingData.removeAt(0);
//         print('ServerService: Removed oldest pending data due to max size');
//         await _logManager.log('ServerService: Removed oldest pending data due to max size');
//       }
//       pendingData.add(jsonEncode(data));
//       print('ServerService: Added new pending data, new count: ${pendingData.length}');
//       await _logManager.log('ServerService: Added new pending data, new count: ${pendingData.length}');
//       await prefs.setStringList('pending_locations', pendingData);
//     } catch (e) {
//       print('ServerService: Error saving pending data: $e');
//       await _logManager.log('ServerService: Error saving pending data: $e');
//       await _logManager.logUser('Причина', 'Ошибка сохранения координат');
//     }
//   }

//   String _formatDateTime(DateTime dateTime) {
//     return '${dateTime.year}${dateTime.month.toString().padLeft(2, '0')}${dateTime.day.toString().padLeft(2, '0')}'
//         '${dateTime.hour.toString().padLeft(2, '0')}${dateTime.minute.toString().padLeft(2, '0')}';
//   }
// }