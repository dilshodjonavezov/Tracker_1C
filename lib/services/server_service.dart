import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:background_location_tracker_example/managers/log_manager.dart';

class ServerService {
  static const String _baseUrl = 'http://192.168.88.249/MR';
  static const String _coordinatesPath = '/hs/data/coordinates';
  static const String _username = 'testMobi';
  static const String _password = 'nE8vecon';
  static const int _maxPendingLocations = 100000;
  static const int _minDiagnosticIntervalSeconds = 60;
  static const String _disabledLocationLatitude = '0.00000';
  static const String _disabledLocationLongitude = '0.00000';
  final LogManager _logManager = LogManager();
  final _logController = StreamController<String>.broadcast();
  bool _isSendingPendingData = false;
  static const int _minDuplicateIntervalSeconds = 15;

  // Expose the log stream
  Stream<String> get logStream => _logController.stream;

  String get _auth {
    final authString = '$_username:$_password';
    final authEncoded = base64Encode(utf8.encode(authString));
    _logManager.log('ServerService: Generated auth header: Basic $authEncoded');
    return 'Basic $authEncoded';
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}T${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';
  }

  // 🔍 Получение статуса пользователя с сервера (включен ли GPS, рабочее время)
  Future<Map<String, dynamic>?> getUserStatus(String userId) async {
    _logManager
        .log('ServerService: Requesting user status for user_id=$userId');
    try {
      final primaryStatus = await _getUserStatusFromServer(_baseUrl, userId);
      if (primaryStatus != null) return primaryStatus;

      _logManager
          .log('ServerService: User status request failed on primary server');
      return null;
    } catch (e) {
      _logManager.log('ServerService: Exception during status request: $e');
      return null;
    }
  }

  // 📤 Отправка координат на сервер (основной метод)
  Future<void> sendLocationToServer(double latitude, double longitude,
      {String source = 'Автоматическая'}) async {
    final now = DateTime.now();
    _logManager.log(
        'ServerService: Sending location: lat=$latitude, lon=$longitude, source=$source');
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id') ?? '21435';
      final data = {
        'user_id': userId,
        'latitude': latitude.toString(),
        'longitude': longitude.toString(),
        'date': _formatDateTime(now)
      };

      if (await _isDuplicateSend(prefs, latitude, longitude, now)) {
        _logManager.log('ServerService: Duplicate location skipped');
        return;
      }

      // 🌐 Проверяем наличие интернета
      final hasInternet = await _isInternetAvailable();
      if (!hasInternet) {
        _logManager.log('ServerService: No internet, saving to pending');
        await _savePendingData(data);
        return;
      }

      // ⏰ Проверяем, можно ли отправлять (рабочее время + GPS включен)
      final canSend = await _canSendLocation();
      if (!canSend) {
        _logManager.log(
            'ServerService: Cannot send due to time or GPS, saving to pending');
        await _savePendingData(data);
        return;
      }

      // 📦 Формируем данные для отправки
      await prefs.setString(
          'last_location',
          jsonEncode({
            'latitude': latitude.toString(),
            'longitude': longitude.toString()
          }));

      // 🚀 Отправляем только на основной сервер
      final primaryOk = await _sendPrimary([data]);

      if (primaryOk) {
        _logController
            .add('$source отправка: lat=$latitude, lon=$longitude, time=$now');
        await _markLastSent(prefs, latitude, longitude, now);
        await _checkAndSendPendingData(); // Попытка отправить накопленные данные
      }

      if (!primaryOk) {
        _logManager.log(
            'ServerService: Primary server unavailable, saving data for retry');
        await _savePendingData(data);
      }
    } catch (e) {
      _logManager.log('ServerService: Error sending location: $e');
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id') ?? '21435';
      final data = {
        'user_id': userId,
        'latitude': latitude.toString(),
        'longitude': longitude.toString(),
        'date': _formatDateTime(now)
      };
      await _savePendingData(data);
    }
  }

  Future<void> sendLocationDisabledSignal(
      {String source = 'Геолокация выключена'}) async {
    final now = DateTime.now();
    _logManager
        .log('ServerService: Sending disabled location signal, source=$source');

    try {
      final prefs = await SharedPreferences.getInstance();
      final lastSignalAt = prefs.getString('last_location_disabled_signal_at');
      final parsedLastSignalAt =
          lastSignalAt == null ? null : DateTime.tryParse(lastSignalAt);
      if (parsedLastSignalAt != null &&
          now.difference(parsedLastSignalAt).inSeconds <
              _minDiagnosticIntervalSeconds) {
        _logManager
            .log('ServerService: Disabled location signal skipped by interval');
        return;
      }

      final userId = prefs.getString('user_id');
      if (userId == null || userId.isEmpty) return;

      final data = {
        'user_id': userId,
        'latitude': _disabledLocationLatitude,
        'longitude': _disabledLocationLongitude,
        'date': _formatDateTime(now),
      };

      final hasInternet = await _isInternetAvailable();
      if (!hasInternet) {
        _logManager.log(
            'ServerService: No internet, saving disabled location signal to pending');
        await _savePendingData(data);
        await prefs.setString(
            'last_location_disabled_signal_at', now.toIso8601String());
        return;
      }

      final canSend = await _canSendLocation();
      if (!canSend) {
        _logManager.log(
            'ServerService: Disabled location signal skipped due to server GPS flag or time window');
        return;
      }

      final sent = await _sendPrimary([data]);
      if (sent) {
        _logController.add(
            '$source: lat=$_disabledLocationLatitude, lon=$_disabledLocationLongitude, time=$now');
        await prefs.setString(
            'last_location_disabled_signal_at', now.toIso8601String());
        await _checkAndSendPendingData();
      } else {
        _logManager.log(
            'ServerService: Server unavailable, saving disabled location signal to pending');
        await _savePendingData(data);
        await prefs.setString(
            'last_location_disabled_signal_at', now.toIso8601String());
      }
    } catch (e) {
      _logManager
          .log('ServerService: Error sending disabled location signal: $e');
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id');
      if (userId == null || userId.isEmpty) return;

      await _savePendingData({
        'user_id': userId,
        'latitude': _disabledLocationLatitude,
        'longitude': _disabledLocationLongitude,
        'date': _formatDateTime(now),
      });
      await prefs.setString(
          'last_location_disabled_signal_at', now.toIso8601String());
    }
  }

  // 📦 Проверка и отправка накопленных данных (когда интернет появился)
  Future<void> _checkAndSendPendingData() async {
    _logManager.log('ServerService: Checking and sending pending data');
    if (_isSendingPendingData) return;
    _isSendingPendingData = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> pendingData = prefs.getStringList('pending_locations') ?? [];
      if (pendingData.isEmpty) return;

      List<Map<String, dynamic>> dataList = pendingData
          .map((s) => jsonDecode(s) as Map<String, dynamic>)
          .where((d) => d.isNotEmpty)
          .toList();

      if (dataList.isNotEmpty) {
        int retryCount = 0;
        while (retryCount < 3 && !await _sendPendingBatch(dataList)) {
          retryCount++;
        }
      }
    } finally {
      _isSendingPendingData = false;
    }
  }

  // 📤 Отправка пакета накопленных координат
  Future<bool> _sendPendingBatch(List<Map<String, dynamic>> dataList) async {
    try {
      final sent = await _sendPrimary(dataList);
      if (sent) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList('pending_locations', []);
        return true;
      }
      return false;
    } catch (e) {
      _logManager.log('ServerService: Error sending pending batch: $e');
      return false;
    }
  }

  // 🌐 Проверка доступности интернета
  Future<bool> _isInternetAvailable() async {
    try {
      final dynamic connectivityResult =
          await Connectivity().checkConnectivity();
      if (connectivityResult is List<ConnectivityResult>) {
        return connectivityResult
            .any((result) => result != ConnectivityResult.none);
      }
      return connectivityResult != ConnectivityResult.none;
    } catch (e) {
      return false;
    }
  }

  // ⏰ Проверка, можно ли отправлять (GPS включен + в рабочее время)
  Future<bool> _canSendLocation() async {
    final prefs = await SharedPreferences.getInstance();
    final gps = prefs.getBool('gps') ?? true;
    final from =
        DateTime.parse(prefs.getString('from') ?? '0001-01-01T08:00:00');
    final to = DateTime.parse(prefs.getString('to') ?? '0001-01-01T18:00:00');
    final now = DateTime.now();
    final currentTimeInMinutes = now.hour * 60 + now.minute;
    final fromTimeInMinutes = from.hour * 60 + from.minute;
    final toTimeInMinutes = to.hour * 60 + to.minute;
    return gps &&
        currentTimeInMinutes >= fromTimeInMinutes &&
        currentTimeInMinutes < toTimeInMinutes;
  }

  // 💾 Сохранение данных в очередь (когда нет интернета или нельзя отправить)
  Future<void> _savePendingData(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> pendingData = prefs.getStringList('pending_locations') ?? [];
    if (pendingData.length >= _maxPendingLocations) pendingData.removeAt(0);
    pendingData.add(jsonEncode(data));
    await prefs.setStringList('pending_locations', pendingData);
  }

  Future<Map<String, dynamic>?> _getUserStatusFromServer(
      String baseUrl, String userId) async {
    final url = '$baseUrl/hs/data/auth?user_id=$userId';
    final headers = {
      'Authorization': _auth,
      'Content-Type': 'application/json',
      'Accept': 'application/json'
    };
    _logManager.log('ServerService: GET request to $url');
    _logManager.log('ServerService: Headers: $headers');

    final response = await http.get(Uri.parse(url), headers: headers).timeout(
          const Duration(seconds: 10),
          onTimeout: () => http.Response('Timeout', 408),
        );

    _logManager.log(
        'ServerService: Response status from $baseUrl: ${response.statusCode}');
    if (response.statusCode != 200) return null;
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  // ✅ Основной сервер с авторизацией
  Future<bool> _sendPrimary(List<Map<String, dynamic>> dataList) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl$_coordinatesPath'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': _auth
            },
            body: jsonEncode(dataList),
          )
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw Exception('Request timeout'),
          );
      if (response.statusCode != 200) {
        _logManager.log(
            'ServerService: Primary send failed with status ${response.statusCode}');
      }
      return response.statusCode == 200;
    } catch (e) {
      _logManager.log('ServerService: Primary send error: $e');
      return false;
    }
  }

  // 🔧 Инициализация сервиса
  void init() {
    _logManager.log('ServerService: Initialization started');
    _checkAndSendPendingData();
    _logManager.log('ServerService: Initialization completed');
  }

  void dispose() {
    _logController.close();
  }

  Future<bool> _isDuplicateSend(
    SharedPreferences prefs,
    double latitude,
    double longitude,
    DateTime now,
  ) async {
    final lastSentAt = prefs.getString('last_sent_at');
    final lastLatitude = prefs.getString('last_sent_latitude');
    final lastLongitude = prefs.getString('last_sent_longitude');
    if (lastSentAt == null || lastLatitude == null || lastLongitude == null) {
      return false;
    }

    final sentAt = DateTime.tryParse(lastSentAt);
    if (sentAt == null) return false;

    final isSamePoint = lastLatitude == latitude.toString() &&
        lastLongitude == longitude.toString();
    final isTooSoon =
        now.difference(sentAt).inSeconds < _minDuplicateIntervalSeconds;
    return isSamePoint && isTooSoon;
  }

  Future<void> _markLastSent(
    SharedPreferences prefs,
    double latitude,
    double longitude,
    DateTime now,
  ) async {
    await prefs.setString('last_sent_at', now.toIso8601String());
    await prefs.setString('last_sent_latitude', latitude.toString());
    await prefs.setString('last_sent_longitude', longitude.toString());
  }
}
