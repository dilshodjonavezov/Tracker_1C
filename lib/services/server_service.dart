import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:background_location_tracker_example/managers/log_manager.dart';
import '../utils/utils.dart';

class ServerService {
  static const String _baseUrl = 'http://192.168.88.249/MR';
  static const String _username = 'testMobi';
  static const String _password = 'nE8vecon';
  final LogManager _logManager = LogManager();
  final _logController = StreamController<String>.broadcast();
  bool _isSendingPendingData = false;
  DateTime? _lastSentTime;
  Timer? _periodicSendTimer;
  
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
    _logManager.log('ServerService: Requesting user status for user_id=$userId');
    try {
      final url = '$_baseUrl/hs/data/auth?user_id=$userId';
      final headers = {'Authorization': _auth, 'Content-Type': 'application/json', 'Accept': 'application/json'};
      _logManager.log('ServerService: GET request to $url');
      _logManager.log('ServerService: Headers: $headers');

      final response = await http.get(Uri.parse(url), headers: headers).timeout(
        const Duration(seconds: 10), // ⏱️ 10 секунд - таймаут для запроса статуса
        onTimeout: () => http.Response('Timeout', 408),
      );

      _logManager.log('ServerService: Response status: ${response.statusCode}');
      if (response.statusCode == 200) return jsonDecode(response.body) as Map<String, dynamic>;
      return null;
    } catch (e) {
      _logManager.log('ServerService: Exception during status request: $e');
      return null;
    }
  }

  // 📤 Отправка координат на сервер (основной метод)
  Future<void> sendLocationToServer(double latitude, double longitude, {String source = 'Автоматическая'}) async {
    final now = DateTime.now();
    _logManager.log('ServerService: Sending location: lat=$latitude, lon=$longitude, source=$source');
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id') ?? '21435';
      
      // 🌐 Проверяем наличие интернета
      final hasInternet = await _isInternetAvailable();
      if (!hasInternet) {
        _logManager.log('ServerService: No internet, saving to pending');
        await _savePendingData({'latitude': latitude.toString(), 'longitude': longitude.toString(), 'date': _formatDateTime(now)});
        return;
      }

      // ⏰ Проверяем, можно ли отправлять (рабочее время + GPS включен)
      final canSend = await _canSendLocation();
      if (!canSend) {
        _logManager.log('ServerService: Cannot send due to time or GPS, saving to pending');
        await _savePendingData({'latitude': latitude.toString(), 'longitude': longitude.toString(), 'date': _formatDateTime(now)});
        return;
      }

      // 📦 Формируем данные для отправки
      final data = {'user_id': userId, 'latitude': latitude.toString(), 'longitude': longitude.toString(), 'date': _formatDateTime(now)};
      await prefs.setString('last_location', jsonEncode({'latitude': latitude.toString(), 'longitude': longitude.toString()}));

      // 🚀 Отправляем на сервер
      final response = await http.post(
        Uri.parse('$_baseUrl/hs/data/coordinates'),
        headers: {'Content-Type': 'application/json', 'Authorization': _auth},
        body: jsonEncode([data]),
      ).timeout(
        const Duration(seconds: 10), // ⏱️ 10 секунд - таймаут для отправки координат
        onTimeout: () => throw Exception('Request timeout')
      );

      if (response.statusCode == 200) {
        _lastSentTime = now;
        _logController.add('$source отправка: lat=$latitude, lon=$longitude, time=$now');
        await _checkAndSendPendingData(); // Попытка отправить накопленные данные
      } else {
        _logManager.log('ServerService: Failed to send, status code: ${response.statusCode}');
        await _savePendingData(data);
      }
    } catch (e) {
      _logManager.log('ServerService: Error sending location: $e');
      await _savePendingData({'latitude': latitude.toString(), 'longitude': longitude.toString(), 'date': _formatDateTime(now)});
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

      final canSend = await _canSendLocation();
      if (!canSend) return;

      List<Map<String, dynamic>> dataList = pendingData.map((s) => jsonDecode(s) as Map<String, dynamic>).where((d) => d.isNotEmpty).toList();
      if (dataList.isEmpty) return;

      int retryCount = 0;
      while (retryCount < 3 && !await _sendPendingBatch(dataList)) retryCount++;
    } finally {
      _isSendingPendingData = false;
    }
  }

  // 📤 Отправка пакета накопленных координат
  Future<bool> _sendPendingBatch(List<Map<String, dynamic>> dataList) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/hs/data/coordinates'),
        headers: {'Content-Type': 'application/json', 'Authorization': _auth},
        body: jsonEncode(dataList),
      ).timeout(const Duration(seconds: 10)); // ⏱️ 10 секунд - таймаут для пакетной отправки
      
      if (response.statusCode == 200) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList('pending_locations', []);
        _lastSentTime = DateTime.now();
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
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) return false;
      final response = await http.get(Uri.parse(_baseUrl)).timeout(
        const Duration(seconds: 5) // ⏱️ 5 секунд - таймаут для проверки интернета
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // ⏰ Проверка, можно ли отправлять (GPS включен + в рабочее время)
  Future<bool> _canSendLocation() async {
    final prefs = await SharedPreferences.getInstance();
    final gps = prefs.getBool('gps') ?? true;
    final from = DateTime.parse(prefs.getString('from') ?? '0001-01-01T08:00:00');
    final to = DateTime.parse(prefs.getString('to') ?? '0001-01-01T18:00:00');
    final now = DateTime.now();
    final currentTimeInMinutes = now.hour * 60 + now.minute;
    final fromTimeInMinutes = from.hour * 60 + from.minute;
    final toTimeInMinutes = to.hour * 60 + to.minute;
    return gps && currentTimeInMinutes >= fromTimeInMinutes && currentTimeInMinutes < toTimeInMinutes;
  }

  // 💾 Сохранение данных в очередь (когда нет интернета или нельзя отправить)
  Future<void> _savePendingData(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> pendingData = prefs.getStringList('pending_locations') ?? [];
    if (pendingData.length >= 10000) pendingData.removeAt(0); // Ограничение на 10000 записей
    pendingData.add(jsonEncode(data));
    await prefs.setStringList('pending_locations', pendingData);
  }

  // 🔧 Инициализация сервиса
  void init() {
    _logManager.log('ServerService: Initialization started');
    _checkAndSendPendingData();
    
    // ⏱️ 10 секунд - периодическая отправка последней сохранённой позиции
    // (это резервный механизм, основная отправка происходит в repo.dart)
    _periodicSendTimer = Timer.periodic(const Duration(seconds: 10), (_) => _sendLatestLocation());
    _logManager.log('ServerService: Initialization completed with 10-second periodic sender');
  }

  void dispose() {
    _periodicSendTimer?.cancel();
    _logController.close();
  }

  // 📤 Отправка последней сохранённой позиции (резервный механизм)
  Future<void> _sendLatestLocation() async {
    final prefs = await SharedPreferences.getInstance();
    final lastLocationJson = prefs.getString('last_location');
    if (lastLocationJson != null) {
      final lastLocation = jsonDecode(lastLocationJson) as Map<String, dynamic>;
      await sendLocationToServer(
        double.parse(lastLocation['latitude'] ?? '0.0'), 
        double.parse(lastLocation['longitude'] ?? '0.0'), 
        source: 'Periodic' // Метка источника для логирования
      );
    }
  }
}