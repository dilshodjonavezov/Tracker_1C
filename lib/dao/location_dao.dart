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

  LocationDao._();
  factory LocationDao() => _instance ??= LocationDao._();

  Future<Database> get _db async {
    if (_database != null) return _database!;
    final dbPath = await getDatabasesPath();
    _database = await openDatabase(
      path.join(dbPath, _databaseName),
      version: 2,
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
            rejection_reason TEXT
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_locations_sync ON $_table(sync_state, lease_until, id)',
        );
        await db.execute(
          'CREATE INDEX idx_locations_user_time ON $_table(user_id, captured_at)',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db
              .execute('ALTER TABLE $_table ADD COLUMN rejection_reason TEXT');
        }
      },
    );
    return _database!;
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

  Future<void> deleteBatch(Iterable<int> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    final db = await _db;
    final placeholders = List.filled(list.length, '?').join(',');
    await db.delete(_table, where: 'id IN ($placeholders)', whereArgs: list);
  }

  Future<void> releaseBatch(Iterable<int> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    final db = await _db;
    final placeholders = List.filled(list.length, '?').join(',');
    await db.update(
      _table,
      {'sync_state': 0, 'lease_until': 0},
      where: 'id IN ($placeholders)',
      whereArgs: list,
    );
  }

  Future<int> pendingCount() async {
    final db = await _db;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM $_table WHERE sync_state = 0',
    );
    return (result.first['count'] as int?) ?? 0;
  }

  /// Manual UI action only. Never call this during application startup.
  Future<void> clear() async {
    final db = await _db;
    await db.delete(_table);
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day.toString().padLeft(2, '0')}.${dateTime.month.toString().padLeft(2, '0')}.${dateTime.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';
  }
}
