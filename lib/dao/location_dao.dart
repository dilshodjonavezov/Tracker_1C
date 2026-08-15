import 'package:background_location_tracker/background_location_tracker.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

/// Durable, transactional local journal of GPS samples.
///
/// SharedPreferences is intentionally not used for the queue: rewriting one
/// large string on every GPS callback is slow and can lose data on a crash.
class LocationDao {
  static LocationDao? _instance;
  static Database? _database;
  static const _databaseName = 'tracker_locations.db';
  static const _table = 'locations';
  static const _eventsTable = 'device_events';

  LocationDao._();
  factory LocationDao() => _instance ??= LocationDao._();

  Future<Database> get _db async {
    if (_database != null) return _database!;
    final dbPath = await getDatabasesPath();
    _database = await openDatabase(
      path.join(dbPath, _databaseName),
      version: 5,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_table (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id TEXT NOT NULL,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            horizontal_accuracy REAL NOT NULL,
            altitude REAL NOT NULL,
            vertical_accuracy REAL NOT NULL,
            course REAL NOT NULL,
            course_accuracy REAL NOT NULL,
            speed REAL NOT NULL,
            speed_accuracy REAL NOT NULL,
            captured_at INTEGER NOT NULL,
            sync_state INTEGER NOT NULL DEFAULT 0,
            lease_until INTEGER NOT NULL DEFAULT 0,
            rejection_reason TEXT,
            sent_at INTEGER,
            last_attempt_at INTEGER,
            last_error_code TEXT,
            last_error_message TEXT,
            failure_owner TEXT,
            last_http_status INTEGER,
            last_server_response TEXT,
            attempt_count INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_locations_sync ON $_table(sync_state, lease_until, id)',
        );
        await db.execute(
          'CREATE INDEX idx_locations_user_time ON $_table(user_id, captured_at)',
        );
        await _createDeviceEventsTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db
              .execute('ALTER TABLE $_table ADD COLUMN rejection_reason TEXT');
        }
        if (oldVersion < 3) {
          await db.execute('ALTER TABLE $_table ADD COLUMN sent_at INTEGER');
          await db.execute(
              'ALTER TABLE $_table ADD COLUMN last_attempt_at INTEGER');
          await db
              .execute('ALTER TABLE $_table ADD COLUMN last_error_code TEXT');
          await db.execute(
              'ALTER TABLE $_table ADD COLUMN last_error_message TEXT');
          await db.execute('ALTER TABLE $_table ADD COLUMN failure_owner TEXT');
          await db.execute(
            'ALTER TABLE $_table ADD COLUMN attempt_count INTEGER NOT NULL DEFAULT 0',
          );
        }
        if (oldVersion < 4) {
          await _createDeviceEventsTable(db);
        }
        if (oldVersion < 5) {
          await db.execute(
              'ALTER TABLE $_table ADD COLUMN last_http_status INTEGER');
          await db.execute(
              'ALTER TABLE $_table ADD COLUMN last_server_response TEXT');
        }
      },
    );
    return _database!;
  }

  static Future<void> _createDeviceEventsTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_eventsTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id TEXT NOT NULL,
        event_type TEXT NOT NULL,
        event_name TEXT NOT NULL,
        owner TEXT NOT NULL,
        started_at INTEGER NOT NULL,
        ended_at INTEGER,
        last_detected_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_device_events_user_time '
      'ON $_eventsTable(user_id, started_at, ended_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_device_events_open '
      'ON $_eventsTable(user_id, ended_at, id)',
    );
  }

  Future<void> saveLocation(
    BackgroundLocationUpdateData data, {
    String? userId,
    DateTime? capturedAt,
    bool syncable = true,
    String? rejectionReason,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final resolvedUserId = userId ?? prefs.getString('user_id');
    if (resolvedUserId == null || resolvedUserId.isEmpty) return;

    final db = await _db;
    await db.insert(_table, {
      'user_id': resolvedUserId,
      'latitude': data.lat,
      'longitude': data.lon,
      'horizontal_accuracy': data.horizontalAccuracy,
      'altitude': data.alt,
      'vertical_accuracy': data.verticalAccuracy,
      'course': data.course,
      'course_accuracy': data.courseAccuracy,
      'speed': data.speed,
      'speed_accuracy': data.speedAccuracy,
      'captured_at': (capturedAt ?? DateTime.now()).millisecondsSinceEpoch,
      'sync_state': syncable ? 0 : 2,
      'lease_until': 0,
      'rejection_reason': rejectionReason,
      'attempt_count': 0,
    });
  }

  Future<List<String>> getLocations({int limit = 500}) async {
    final db = await _db;
    final rows = await db.query(_table, orderBy: 'id DESC', limit: limit);
    return rows
        .map((row) {
          final date =
              DateTime.fromMillisecondsSinceEpoch(row['captured_at'] as int);
          return '${_formatDateTime(date)} - Широта: ${(row['latitude'] as num).toDouble().toStringAsFixed(6)}, Долгота: ${(row['longitude'] as num).toDouble().toStringAsFixed(6)}';
        })
        .toList()
        .reversed
        .toList();
  }

  Future<List<Map<String, dynamic>>> claimPendingBatch({
    required int limit,
    required Duration lease,
  }) async {
    final db = await _db;
    final now = DateTime.now().millisecondsSinceEpoch;
    final leaseUntil = now + lease.inMilliseconds;
    return db.transaction((txn) async {
      final rows = await txn.query(
        _table,
        where: '(sync_state = 0 OR (sync_state = 1 AND lease_until <= ?))',
        whereArgs: [now],
        orderBy: 'id ASC',
        limit: limit,
      );
      if (rows.isEmpty) return <Map<String, dynamic>>[];
      final ids = rows.map((row) => row['id']).toList();
      final placeholders = List.filled(ids.length, '?').join(',');
      await txn.rawUpdate(
        'UPDATE $_table SET sync_state = 1, lease_until = ? WHERE id IN ($placeholders)',
        [leaseUntil, ...ids],
      );
      return rows;
    });
  }

  Future<void> markBatchSent(
    Iterable<int> ids, {
    required DateTime sentAt,
    required int? httpStatus,
    required String? serverResponse,
  }) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    final db = await _db;
    final placeholders = List.filled(list.length, '?').join(',');
    await db.rawUpdate(
      '''
      UPDATE $_table
      SET sync_state = 2,
          lease_until = 0,
          sent_at = ?,
          last_attempt_at = ?,
          last_http_status = ?,
          last_server_response = ?,
          attempt_count = attempt_count + 1
      WHERE id IN ($placeholders)
      ''',
      [
        sentAt.millisecondsSinceEpoch,
        sentAt.millisecondsSinceEpoch,
        httpStatus,
        serverResponse,
        ...list,
      ],
    );
  }

  Future<void> markBatchFailed(
    Iterable<int> ids, {
    required DateTime attemptedAt,
    required String errorCode,
    required String message,
    required String owner,
    int? httpStatus,
    String? serverResponse,
  }) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    final db = await _db;
    final placeholders = List.filled(list.length, '?').join(',');
    await db.rawUpdate(
      '''
      UPDATE $_table
      SET sync_state = 0,
          lease_until = 0,
          last_attempt_at = ?,
          last_error_code = ?,
          last_error_message = ?,
          failure_owner = ?,
          last_http_status = COALESCE(?, last_http_status),
          last_server_response = COALESCE(?, last_server_response),
          attempt_count = attempt_count + 1
      WHERE id IN ($placeholders)
      ''',
      [
        attemptedAt.millisecondsSinceEpoch,
        errorCode,
        message,
        owner,
        httpStatus,
        serverResponse,
        ...list,
      ],
    );
  }

  Future<void> annotatePendingFailure({
    required DateTime attemptedAt,
    required String errorCode,
    required String message,
    required String owner,
  }) async {
    final db = await _db;
    await db.rawUpdate(
      '''
      UPDATE $_table
      SET last_attempt_at = ?,
          last_error_code = ?,
          last_error_message = ?,
          failure_owner = ?,
          attempt_count = attempt_count + 1
      WHERE sync_state = 0
      ''',
      [
        attemptedAt.millisecondsSinceEpoch,
        errorCode,
        message,
        owner,
      ],
    );
  }

  Future<int> pendingCount() async {
    final db = await _db;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM $_table WHERE sync_state = 0',
    );
    return (result.first['count'] as int?) ?? 0;
  }

  Future<List<LocationReportRow>> getReportRows({
    required DateTime from,
    required DateTime toExclusive,
    String? userId,
  }) async {
    final db = await _db;
    final where = StringBuffer('captured_at >= ? AND captured_at < ?');
    final args = <Object?>[
      from.millisecondsSinceEpoch,
      toExclusive.millisecondsSinceEpoch,
    ];
    if (userId != null && userId.isNotEmpty) {
      where.write(' AND user_id = ?');
      args.add(userId);
    }
    final rows = await db.query(
      _table,
      where: where.toString(),
      whereArgs: args,
      orderBy: 'captured_at ASC, id ASC',
    );
    return rows.map(LocationReportRow.fromMap).toList();
  }

  Future<LocationDateRange?> getAvailableDateRange({String? userId}) async {
    final db = await _db;
    final filter =
        userId != null && userId.isNotEmpty ? ' WHERE user_id = ?' : '';
    final result = await db.rawQuery(
      'SELECT MIN(captured_at) AS first_at, MAX(captured_at) AS last_at '
      'FROM $_table$filter',
      userId != null && userId.isNotEmpty ? [userId] : null,
    );
    final first = result.first['first_at'] as int?;
    final last = result.first['last_at'] as int?;
    if (first == null || last == null) return null;
    return LocationDateRange(
      start: DateTime.fromMillisecondsSinceEpoch(first),
      end: DateTime.fromMillisecondsSinceEpoch(last),
    );
  }

  Future<void> recordOpenDeviceIssue({
    required String userId,
    required String eventType,
    required String eventName,
    required String owner,
    DateTime? detectedAt,
  }) async {
    if (userId.isEmpty) return;
    final db = await _db;
    final now = (detectedAt ?? DateTime.now()).millisecondsSinceEpoch;
    await db.transaction((txn) async {
      final openRows = await txn.query(
        _eventsTable,
        where: 'user_id = ? AND ended_at IS NULL',
        whereArgs: [userId],
        orderBy: 'id DESC',
        limit: 1,
      );
      if (openRows.isNotEmpty) {
        final open = openRows.first;
        if (open['event_type'] == eventType) {
          await txn.update(
            _eventsTable,
            {'last_detected_at': now},
            where: 'id = ?',
            whereArgs: [open['id']],
          );
          return;
        }
        await txn.update(
          _eventsTable,
          {'ended_at': now, 'last_detected_at': now},
          where: 'id = ?',
          whereArgs: [open['id']],
        );
      }
      await txn.insert(_eventsTable, {
        'user_id': userId,
        'event_type': eventType,
        'event_name': eventName,
        'owner': owner,
        'started_at': now,
        'ended_at': null,
        'last_detected_at': now,
      });
    });
  }

  Future<void> closeOpenDeviceIssues({
    required String userId,
    DateTime? endedAt,
  }) async {
    if (userId.isEmpty) return;
    final db = await _db;
    final now = (endedAt ?? DateTime.now()).millisecondsSinceEpoch;
    await db.update(
      _eventsTable,
      {'ended_at': now, 'last_detected_at': now},
      where: 'user_id = ? AND ended_at IS NULL',
      whereArgs: [userId],
    );
  }

  Future<List<DeviceEventRow>> getDeviceEvents({
    required DateTime from,
    required DateTime toExclusive,
    required String userId,
  }) async {
    final db = await _db;
    final rows = await db.query(
      _eventsTable,
      where: '''
        user_id = ?
        AND started_at < ?
        AND (ended_at IS NULL OR ended_at >= ?)
      ''',
      whereArgs: [
        userId,
        toExclusive.millisecondsSinceEpoch,
        from.millisecondsSinceEpoch,
      ],
      orderBy: 'started_at ASC, id ASC',
    );
    return rows.map(DeviceEventRow.fromMap).toList();
  }

  /// Manual UI action only. Never call this during application startup.
  Future<void> clear() async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete(_table);
      await txn.delete(_eventsTable);
    });
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day.toString().padLeft(2, '0')}.${dateTime.month.toString().padLeft(2, '0')}.${dateTime.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';
  }
}

class LocationReportRow {
  const LocationReportRow({
    required this.id,
    required this.userId,
    required this.latitude,
    required this.longitude,
    required this.horizontalAccuracy,
    required this.altitude,
    required this.speed,
    required this.capturedAt,
    required this.syncState,
    required this.attemptCount,
    this.sentAt,
    this.lastAttemptAt,
    this.lastErrorCode,
    this.lastErrorMessage,
    this.failureOwner,
    this.lastHttpStatus,
    this.lastServerResponse,
    this.qualityWarning,
  });

  factory LocationReportRow.fromMap(Map<String, Object?> row) {
    DateTime? dateFrom(String key) {
      final value = row[key] as int?;
      return value == null ? null : DateTime.fromMillisecondsSinceEpoch(value);
    }

    return LocationReportRow(
      id: row['id'] as int,
      userId: row['user_id'] as String,
      latitude: (row['latitude'] as num).toDouble(),
      longitude: (row['longitude'] as num).toDouble(),
      horizontalAccuracy: (row['horizontal_accuracy'] as num?)?.toDouble() ?? 0,
      altitude: (row['altitude'] as num?)?.toDouble() ?? 0,
      speed: (row['speed'] as num?)?.toDouble() ?? 0,
      capturedAt:
          DateTime.fromMillisecondsSinceEpoch(row['captured_at'] as int),
      syncState: (row['sync_state'] as int?) ?? 0,
      attemptCount: (row['attempt_count'] as int?) ?? 0,
      sentAt: dateFrom('sent_at'),
      lastAttemptAt: dateFrom('last_attempt_at'),
      lastErrorCode: row['last_error_code'] as String?,
      lastErrorMessage: row['last_error_message'] as String?,
      failureOwner: row['failure_owner'] as String?,
      lastHttpStatus: row['last_http_status'] as int?,
      lastServerResponse: row['last_server_response'] as String?,
      qualityWarning: row['rejection_reason'] as String?,
    );
  }

  final int id;
  final String userId;
  final double latitude;
  final double longitude;
  final double horizontalAccuracy;
  final double altitude;
  final double speed;
  final DateTime capturedAt;
  final int syncState;
  final int attemptCount;
  final DateTime? sentAt;
  final DateTime? lastAttemptAt;
  final String? lastErrorCode;
  final String? lastErrorMessage;
  final String? failureOwner;
  final int? lastHttpStatus;
  final String? lastServerResponse;
  final String? qualityWarning;

  String get deliveryStatus {
    if (syncState == 2) {
      if (attemptCount > 1 && lastErrorMessage != null) {
        return 'Отправлено после повтора';
      }
      return 'Отправлено';
    }
    if (syncState == 1) return 'Отправляется';
    if (attemptCount > 0) return 'Ожидает повторной отправки';
    return 'Ожидает отправки';
  }
}

class LocationDateRange {
  const LocationDateRange({required this.start, required this.end});

  final DateTime start;
  final DateTime end;
}

class DeviceEventRow {
  const DeviceEventRow({
    required this.id,
    required this.userId,
    required this.eventType,
    required this.eventName,
    required this.owner,
    required this.startedAt,
    required this.lastDetectedAt,
    this.endedAt,
  });

  factory DeviceEventRow.fromMap(Map<String, Object?> row) {
    final endedAt = row['ended_at'] as int?;
    return DeviceEventRow(
      id: row['id'] as int,
      userId: row['user_id'] as String,
      eventType: row['event_type'] as String,
      eventName: row['event_name'] as String,
      owner: row['owner'] as String,
      startedAt: DateTime.fromMillisecondsSinceEpoch(row['started_at'] as int),
      endedAt:
          endedAt == null ? null : DateTime.fromMillisecondsSinceEpoch(endedAt),
      lastDetectedAt: DateTime.fromMillisecondsSinceEpoch(
        row['last_detected_at'] as int,
      ),
    );
  }

  final int id;
  final String userId;
  final String eventType;
  final String eventName;
  final String owner;
  final DateTime startedAt;
  final DateTime? endedAt;
  final DateTime lastDetectedAt;
}
