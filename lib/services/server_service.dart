import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:background_location_tracker_example/dao/location_dao.dart';
import 'package:background_location_tracker_example/managers/log_manager.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ServerService {
  // Старая версия у клиента (1С / MR):
  // static const String _baseUrl = 'http://192.168.88.249/MR';
  // static const String _username = 'testMobi';
  // static const String _password = 'nE8vecon';
  static const String _baseUrl = 'http://169.58.181.154';
  static const String _coordinatesPath = '/hs/data/coordinates';
  static const String _username = 'API_USER';
  static const String _password = 'API_PASSWORD';
  static const int _batchSize = 250;
  static const Duration _flushInterval = Duration(minutes: 10);
  static const int _minDiagnosticIntervalSeconds = 60;
  static const String _disabledLocationLatitude = '0.00000';
  static const String _disabledLocationLongitude = '0.00000';
  static const int _maxStoredResponseLength = 2000;

  static bool _isFlushing = false;
  static Completer<void>? _flushCompleter;
  final LogManager _logManager = LogManager();
  final _logController = StreamController<String>.broadcast();

  Stream<String> get logStream => _logController.stream;

  String get _auth =>
      'Basic ${base64Encode(utf8.encode('$_username:$_password'))}';

  String _formatDateTime(DateTime dateTime) =>
      '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}T${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';

  Future<Map<String, dynamic>?> getUserStatus(String userId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/hs/data/auth?user_id=$userId'),
        headers: {'Authorization': _auth, 'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      _logManager.log('ServerService: status request failed: $e');
      return null;
    }
  }

  /// Called after a sample is written. A sample is never sent directly.
  Future<void> maybeFlushPendingLocations({bool force = false}) async {
    if (_isFlushing) return;
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt('last_location_flush_at') ?? 0;
    final due = DateTime.now().millisecondsSinceEpoch - last >=
        _flushInterval.inMilliseconds;
    if (!force && !due) return;
    await flushPendingLocations(force: force);
  }

  /// Sends bounded sequential batches. At 5-second collection this is about
  /// 120 records per 10 minutes, so one request normally covers one interval.
  /// A larger backlog is drained in 250-record requests, never as one huge JSON.
  Future<void> flushPendingLocations({bool force = false}) async {
    if (_isFlushing) {
      await _flushCompleter?.future;
      return;
    }
    _isFlushing = true;
    final completer = Completer<void>();
    _flushCompleter = completer;
    final dao = LocationDao();
    try {
      final prefs = await SharedPreferences.getInstance();
      final attemptedAt = DateTime.now();
      // Record the attempt before network checks so a disconnected phone does
      // not retry every five-second GPS callback.
      await prefs.setInt(
        'last_location_flush_at',
        attemptedAt.millisecondsSinceEpoch,
      );
      if (!await _canSendLocation()) {
        await dao.annotatePendingFailure(
          attemptedAt: attemptedAt,
          errorCode: 'GPS_DISABLED_BY_SERVER',
          message: 'Отправка GPS отключена настройкой сервера',
          owner: 'Сервер',
        );
        return;
      }
      if (!await _isInternetAvailable()) {
        await dao.annotatePendingFailure(
          attemptedAt: attemptedAt,
          errorCode: 'NO_NETWORK',
          message: 'Нет подключения к интернету или VPN',
          owner: 'Телефон/сеть',
        );
        return;
      }

      // Limit work per wake-up. This protects both device battery and server
      // during long offline periods; the next 10-minute wake-up continues.
      for (var batchNumber = 0; batchNumber < 20; batchNumber++) {
        final rows = await dao.claimPendingBatch(
          limit: _batchSize,
          lease: const Duration(minutes: 5),
        );
        if (rows.isEmpty) break;

        final ids = rows.map((row) => row['id'] as int).toList();
        final payload = rows.map(_serverPayload).toList();
        final result = await _sendPrimary(payload);
        if (result.isSuccess) {
          await dao.markBatchSent(
            ids,
            sentAt: DateTime.now(),
            httpStatus: result.httpStatus,
            serverResponse: result.serverResponse,
          );
          _logController.add('Отправлен пакет GPS: ${ids.length} записей');
        } else {
          await dao.markBatchFailed(
            ids,
            attemptedAt: DateTime.now(),
            errorCode: result.code,
            message: result.message,
            owner: result.owner,
            httpStatus: result.httpStatus,
            serverResponse: result.serverResponse,
          );
          _logController.add(
            'Пакет GPS не отправлен: ${result.message} (${result.owner})',
          );
          break;
        }
      }
    } catch (e) {
      _logManager.log('ServerService: flush failed: $e');
    } finally {
      _isFlushing = false;
      if (!completer.isCompleted) completer.complete();
      if (identical(_flushCompleter, completer)) _flushCompleter = null;
    }
  }

  Map<String, dynamic> _serverPayload(Map<String, dynamic> row) => {
        // Keep the payload compatible with the existing backend contract.
        // Extended GPS metadata remains safely stored in the local SQLite
        // journal, but is not sent because the backend is unchanged.
        'user_id': row['user_id'],
        'latitude': (row['latitude'] as num).toDouble().toString(),
        'longitude': (row['longitude'] as num).toDouble().toString(),
        'date': _formatDateTime(
          DateTime.fromMillisecondsSinceEpoch(row['captured_at'] as int),
        ),
      };

  /// Legacy entry point kept for callers outside Repo. It now journals first.
  Future<void> sendLocationToServer(double latitude, double longitude,
      {String source = 'Автоматическая'}) async {
    _logManager.log(
        'ServerService: direct location call ignored in favor of local journal');
    await maybeFlushPendingLocations();
  }

  Future<void> sendLocationDisabledSignal(
      {String source = 'Геолокация выключена'}) async {
    final now = DateTime.now();
    try {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getString('last_location_disabled_signal_at');
      final lastAt = last == null ? null : DateTime.tryParse(last);
      if (lastAt != null &&
          now.difference(lastAt).inSeconds < _minDiagnosticIntervalSeconds) {
        return;
      }
      final userId = prefs.getString('user_id');
      if (userId == null || userId.isEmpty) return;
      if (!await _isInternetAvailable() || !await _canSendLocation()) return;

      final result = await _sendPrimary([
        {
          'user_id': userId,
          'latitude': _disabledLocationLatitude,
          'longitude': _disabledLocationLongitude,
          'date': _formatDateTime(now),
        }
      ]);
      if (result.isSuccess) {
        await prefs.setString(
            'last_location_disabled_signal_at', now.toIso8601String());
        _logController.add('$source: $now');
      }
    } catch (e) {
      _logManager.log('ServerService: disabled signal failed: $e');
    }
  }

  Future<bool> _isInternetAvailable() async {
    try {
      final result = await Connectivity().checkConnectivity();
      return result.any((item) => item != ConnectivityResult.none);
    } catch (_) {
      return false;
    }
  }

  Future<bool> _canSendLocation() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('gps') ?? true;
  }

  Future<SendResult> _sendPrimary(List<Map<String, dynamic>> dataList) async {
    if (dataList.isEmpty) return SendResult.success();
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl$_coordinatesPath'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': _auth,
              'Accept': 'application/json',
            },
            body: jsonEncode(dataList),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return SendResult.success(
          httpStatus: response.statusCode,
          serverResponse: _safeResponseBody(response.body),
        );
      }

      final result = SendResult.fromHttpStatus(
        response.statusCode,
        serverResponse: _safeResponseBody(response.body),
      );
      if (!result.isSuccess) {
        _logManager.log(
            'ServerService: batch failed ${response.statusCode} (${dataList.length} records)');
      }
      return result;
    } on TimeoutException {
      const result = SendResult.failure(
        code: 'TIMEOUT',
        message: 'Сервер не ответил за 20 секунд',
        owner: 'Сеть/сервер',
      );
      _logManager.log('ServerService: batch request timed out');
      return result;
    } on SocketException {
      const result = SendResult.failure(
        code: 'SERVER_UNREACHABLE',
        message: 'Сервер недоступен: проверьте интернет или VPN',
        owner: 'Телефон/сеть',
      );
      _logManager.log('ServerService: server unreachable');
      return result;
    } catch (e) {
      _logManager.log('ServerService: batch request failed: $e');
      return const SendResult.failure(
        code: 'UNKNOWN_NETWORK_ERROR',
        message: 'Неизвестная ошибка соединения',
        owner: 'Не определено',
      );
    }
  }

  String _safeResponseBody(String body) {
    final normalized = body.trim();
    if (normalized.isEmpty) return 'Пустой ответ';
    if (normalized.length <= _maxStoredResponseLength) return normalized;
    return '${normalized.substring(0, _maxStoredResponseLength)}…';
  }

  void init() {
    maybeFlushPendingLocations(force: true);
  }

  void dispose() {
    _logController.close();
  }
}

class SendResult {
  const SendResult._({
    required this.isSuccess,
    required this.code,
    required this.message,
    required this.owner,
    required this.httpStatus,
    required this.serverResponse,
  });

  factory SendResult.success({
    int? httpStatus,
    String? serverResponse,
  }) =>
      SendResult._(
        isSuccess: true,
        code: 'OK',
        message: 'Отправлено',
        owner: '',
        httpStatus: httpStatus,
        serverResponse: serverResponse,
      );

  const SendResult.failure({
    required String code,
    required String message,
    required String owner,
    int? httpStatus,
    String? serverResponse,
  }) : this._(
          isSuccess: false,
          code: code,
          message: message,
          owner: owner,
          httpStatus: httpStatus,
          serverResponse: serverResponse,
        );

  factory SendResult.fromHttpStatus(
    int statusCode, {
    String? serverResponse,
  }) {
    if (statusCode >= 500) {
      return SendResult.failure(
        code: 'HTTP_$statusCode',
        message: 'Ошибка сервера HTTP $statusCode',
        owner: 'Сервер',
        httpStatus: statusCode,
        serverResponse: serverResponse,
      );
    }
    if (statusCode == 408 || statusCode == 429) {
      return SendResult.failure(
        code: 'HTTP_$statusCode',
        message: statusCode == 429
            ? 'Сервер временно ограничил частоту запросов'
            : 'Сервер не успел обработать запрос',
        owner: 'Сервер',
        httpStatus: statusCode,
        serverResponse: serverResponse,
      );
    }
    if (statusCode == 401 || statusCode == 403) {
      return SendResult.failure(
        code: 'HTTP_$statusCode',
        message: 'Сервер отклонил авторизацию HTTP $statusCode',
        owner: 'API/сервер',
        httpStatus: statusCode,
        serverResponse: serverResponse,
      );
    }
    return SendResult.failure(
      code: 'HTTP_$statusCode',
      message: 'API отклонил пакет HTTP $statusCode',
      owner: 'API/сервер',
      httpStatus: statusCode,
      serverResponse: serverResponse,
    );
  }

  final bool isSuccess;
  final String code;
  final String message;
  final String owner;
  final int? httpStatus;
  final String? serverResponse;
}
