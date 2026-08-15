import 'dart:io';

import 'package:background_location_tracker_example/dao/location_dao.dart';
import 'package:background_location_tracker_example/services/location_report_service.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('creates a readable GPS workbook with delivery and gap diagnostics', () {
    final service = LocationReportService();
    final rows = [
      LocationReportRow(
        id: 1,
        userId: '21435-1250',
        latitude: 40.2106825,
        longitude: 69.3113062,
        horizontalAccuracy: 4.2,
        altitude: 830,
        speed: 3.5,
        capturedAt: DateTime(2026, 7, 26, 6, 41, 31),
        syncState: 2,
        attemptCount: 1,
        sentAt: DateTime(2026, 7, 26, 6, 50),
        lastHttpStatus: 200,
        lastServerResponse: '{"accepted":1}',
      ),
      LocationReportRow(
        id: 2,
        userId: '21435-1250',
        latitude: 39.91227739,
        longitude: 69.00222956,
        horizontalAccuracy: 9.8,
        altitude: 812,
        speed: 0,
        capturedAt: DateTime(2026, 7, 26, 7, 22, 24),
        syncState: 2,
        attemptCount: 2,
        sentAt: DateTime(2026, 7, 26, 7, 31, 12),
        lastAttemptAt: DateTime(2026, 7, 26, 7, 30),
        lastErrorCode: 'SERVER_UNREACHABLE',
        lastErrorMessage: 'Сервер недоступен: проверьте интернет или VPN',
        failureOwner: 'Телефон/сеть',
        lastHttpStatus: 204,
        lastServerResponse: 'Пустой ответ',
      ),
    ];

    final bytes = service.createWorkbook(
      rows: rows,
      events: [
        DeviceEventRow(
          id: 1,
          userId: '21435-1250',
          eventType: 'LOCATION_SERVICE_DISABLED',
          eventName: 'Геолокация отключена на устройстве',
          owner: 'Телефон',
          startedAt: DateTime(2026, 7, 26, 10, 0, 15),
          endedAt: DateTime(2026, 7, 26, 11, 11, 8),
          lastDetectedAt: DateTime(2026, 7, 26, 11, 10),
        ),
      ],
      from: DateTime(2026, 7, 20),
      to: DateTime(2026, 7, 28),
      userId: '21435-1250',
      userName: 'Актар Рахмонов',
      generatedAt: DateTime(2026, 7, 28, 12, 34, 56),
    );
    final decoded = Excel.decodeBytes(bytes);
    final sheet = decoded.tables['Отчёт GPS'];
    final eventsSheet = decoded.tables['События устройства'];

    expect(bytes, isNotEmpty);
    expect(sheet, isNotNull);
    expect(sheet!.cell(CellIndex.indexByString('A1')).value.toString(),
        contains('ОТЧЁТ'));
    expect(sheet.cell(CellIndex.indexByString('K7')).value.toString(),
        contains('после повтора'));
    expect(sheet.cell(CellIndex.indexByString('L7')).value.toString(),
        contains('07:31:12'));
    expect(sheet.cell(CellIndex.indexByString('M6')).value.toString(),
        equals('200'));
    expect(sheet.cell(CellIndex.indexByString('N6')).value.toString(),
        contains('accepted'));
    expect(sheet.cell(CellIndex.indexByString('M7')).value.toString(),
        equals('204'));
    expect(sheet.cell(CellIndex.indexByString('N7')).value.toString(),
        equals('Пустой ответ'));
    expect(sheet.cell(CellIndex.indexByString('O7')).value.toString(),
        contains('VPN'));
    expect(sheet.cell(CellIndex.indexByString('Q7')).value.toString(),
        contains('телефон/ОС'));
    expect(sheet.cell(CellIndex.indexByString('A4')).value.toString(),
        contains('28.07.2026 12:34:56'));
    expect(eventsSheet, isNotNull);
    expect(eventsSheet!.cell(CellIndex.indexByString('A1')).value.toString(),
        contains('СОБЫТИЯ'));
    expect(eventsSheet.cell(CellIndex.indexByString('B6')).value.toString(),
        contains('10:00:15'));
    expect(eventsSheet.cell(CellIndex.indexByString('C6')).value.toString(),
        contains('11:11:08'));
    expect(eventsSheet.cell(CellIndex.indexByString('D6')).value.toString(),
        equals('01:10:53'));
    expect(eventsSheet.cell(CellIndex.indexByString('E6')).value.toString(),
        contains('отключена'));
    expect(eventsSheet.cell(CellIndex.indexByString('F6')).value.toString(),
        equals('Телефон'));
    expect(eventsSheet.cell(CellIndex.indexByString('G6')).value.toString(),
        equals('Завершено'));

    final previewPath = Platform.environment['REPORT_PREVIEW_PATH'];
    if (previewPath != null && previewPath.isNotEmpty) {
      File(previewPath)
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes);
    }
  });
}
