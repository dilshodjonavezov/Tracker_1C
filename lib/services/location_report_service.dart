import 'dart:typed_data';
import 'dart:ui';

import 'package:background_location_tracker_example/dao/location_dao.dart';
import 'package:excel/excel.dart';
import 'package:share_plus/share_plus.dart';

class LocationReportService {
  Future<LocationReportData> buildReport({
    required DateTime from,
    required DateTime toInclusive,
    required String userId,
    String? userName,
  }) async {
    final generatedAt = DateTime.now();
    final toExclusive =
        DateTime(toInclusive.year, toInclusive.month, toInclusive.day + 1);
    final rows = await LocationDao().getReportRows(
      from: DateTime(from.year, from.month, from.day),
      toExclusive: toExclusive,
      userId: userId,
    );
    final events = await LocationDao().getDeviceEvents(
      from: DateTime(from.year, from.month, from.day),
      toExclusive: toExclusive,
      userId: userId,
    );
    if (rows.isEmpty && events.isEmpty) {
      throw const LocationReportException(
        'За выбранный период координат и событий нет.',
      );
    }

    final bytes = createWorkbook(
      rows: rows,
      events: events,
      from: from,
      to: toInclusive,
      userId: userId,
      userName: userName,
      generatedAt: generatedAt,
    );
    final fileName = 'gps_report_${_fileDate(from)}_${_fileDate(toInclusive)}'
        '_${_fileTimestamp(generatedAt)}.xlsx';
    return LocationReportData(
      bytes: bytes,
      fileName: fileName,
      total: rows.length,
      sent: rows.where((row) => row.syncState == 2).length,
      pending: rows.where((row) => row.syncState != 2).length,
      longGaps: _countLongGaps(rows),
      deviceEvents: events.length,
    );
  }

  Future<void> shareReport(
    LocationReportData report, {
    Rect? sharePositionOrigin,
  }) async {
    await SharePlus.instance.share(
      ShareParams(
        title: 'Отчёт GPS',
        subject: 'Отчёт GPS ${report.fileName}',
        text: 'Отчёт GPS сформирован приложением Tracker GPS.',
        files: [
          XFile.fromData(
            report.bytes,
            mimeType:
                'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          ),
        ],
        fileNameOverrides: [report.fileName],
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
  }

  /// Builds the XLSX bytes from already loaded journal rows.
  ///
  /// Kept separate from SQLite access so the workbook format can be tested
  /// without platform plugins.
  Uint8List createWorkbook({
    required List<LocationReportRow> rows,
    List<DeviceEventRow> events = const [],
    required DateTime from,
    required DateTime to,
    required String userId,
    String? userName,
    DateTime? generatedAt,
  }) {
    final reportGeneratedAt = generatedAt ?? DateTime.now();
    final excel = Excel.createExcel();
    final sheet = excel['Отчёт GPS'];
    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    final normalizedUserName = userName?.trim() ?? '';
    final hasName = normalizedUserName.isNotEmpty;
    final headers = <String>[
      '№',
      'Дата',
      'Время',
      'User ID',
      if (hasName) 'Имя',
      'Широта',
      'Долгота',
      'Точность, м',
      'Скорость, м/с',
      'Интервал',
      'Статус отправки',
      'Время отправки',
      'HTTP-код',
      'Ответ сервера',
      'Последняя ошибка',
      'Сторона ошибки',
      'Диагностика GPS',
    ];
    final lastColumn = headers.length - 1;

    final teal = ExcelColor.fromHexString('FF0F766E');
    final darkTeal = ExcelColor.fromHexString('FF115E59');
    final lightTeal = ExcelColor.fromHexString('FFCCFBF1');
    final lightGray = ExcelColor.fromHexString('FFF8FAFC');
    final warning = ExcelColor.fromHexString('FFFFF7ED');
    final borderColor = ExcelColor.fromHexString('FFCBD5E1');
    final thinBorder = Border(
      borderStyle: BorderStyle.Thin,
      borderColorHex: borderColor,
    );

    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
      CellIndex.indexByColumnRow(columnIndex: lastColumn, rowIndex: 0),
      customValue: TextCellValue('ОТЧЁТ ПО ГЕОЛОКАЦИИ'),
    );
    final titleCell = sheet.cell(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
    );
    titleCell.cellStyle = CellStyle(
      backgroundColorHex: darkTeal,
      fontColorHex: ExcelColor.white,
      fontSize: 16,
      bold: true,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );
    sheet.setRowHeight(0, 30);

    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1),
      CellIndex.indexByColumnRow(columnIndex: lastColumn, rowIndex: 1),
      customValue: TextCellValue(
        'Период: ${_date(from)} — ${_date(to)}  •  User ID: $userId'
        '${hasName ? '  •  $normalizedUserName' : ''}',
      ),
    );
    final subtitle = sheet.cell(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1),
    );
    subtitle.cellStyle = CellStyle(
      backgroundColorHex: lightTeal,
      fontColorHex: darkTeal,
      bold: true,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );
    sheet.setRowHeight(1, 24);

    final sentCount = rows.where((row) => row.syncState == 2).length;
    final pendingCount = rows.length - sentCount;
    final longGapCount = _countLongGaps(rows);
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 2),
      CellIndex.indexByColumnRow(columnIndex: lastColumn, rowIndex: 2),
      customValue: TextCellValue(
        'Всего точек: ${rows.length}  •  Отправлено: $sentCount  •  '
        'Ожидает: $pendingCount  •  Разрывов более 1 минуты: $longGapCount  •  '
        'Событий устройства: ${events.length}',
      ),
    );
    final summary = sheet.cell(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 2),
    );
    summary.cellStyle = CellStyle(
      fontColorHex: ExcelColor.fromHexString('FF334155'),
      bold: true,
      horizontalAlign: HorizontalAlign.Center,
    );

    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 3),
      CellIndex.indexByColumnRow(columnIndex: lastColumn, rowIndex: 3),
      customValue: TextCellValue(
        'Сформирован: ${_dateTime(reportGeneratedAt)}  •  '
        'Статусы актуальны на момент формирования отчёта',
      ),
    );
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 3))
        .cellStyle = CellStyle(
      fontColorHex: ExcelColor.fromHexString('FF475569'),
      italic: true,
      horizontalAlign: HorizontalAlign.Center,
    );

    for (var column = 0; column < headers.length; column++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: column, rowIndex: 4),
      );
      cell.value = TextCellValue(headers[column]);
      cell.cellStyle = CellStyle(
        backgroundColorHex: teal,
        fontColorHex: ExcelColor.white,
        bold: true,
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
        textWrapping: TextWrapping.WrapText,
        leftBorder: thinBorder,
        rightBorder: thinBorder,
        topBorder: thinBorder,
        bottomBorder: thinBorder,
      );
    }
    sheet.setRowHeight(4, 31);

    LocationReportRow? previous;
    for (var index = 0; index < rows.length; index++) {
      final row = rows[index];
      final gap = previous == null
          ? null
          : row.capturedAt.difference(previous.capturedAt);
      final isLongGap = gap != null && gap.inSeconds > 60;
      final values = <CellValue?>[
        IntCellValue(index + 1),
        TextCellValue(_date(row.capturedAt)),
        TextCellValue(_time(row.capturedAt)),
        TextCellValue(row.userId),
        if (hasName) TextCellValue(normalizedUserName),
        DoubleCellValue(row.latitude),
        DoubleCellValue(row.longitude),
        DoubleCellValue(row.horizontalAccuracy),
        DoubleCellValue(row.speed),
        TextCellValue(gap == null ? '—' : _duration(gap)),
        TextCellValue(row.deliveryStatus),
        TextCellValue(row.sentAt == null ? '—' : _dateTime(row.sentAt!)),
        TextCellValue(row.lastHttpStatus?.toString() ?? '—'),
        TextCellValue(row.lastServerResponse ?? '—'),
        TextCellValue(row.lastErrorMessage ?? '—'),
        TextCellValue(row.failureOwner ?? '—'),
        TextCellValue(
          isLongGap
              ? 'Нет GPS-точек ${_duration(gap)} (телефон/ОС)'
              : (row.qualityWarning ?? 'Норма'),
        ),
      ];
      final rowIndex = index + 5;
      for (var column = 0; column < values.length; column++) {
        final cell = sheet.cell(
          CellIndex.indexByColumnRow(
            columnIndex: column,
            rowIndex: rowIndex,
          ),
        );
        cell.value = values[column];
        cell.cellStyle = CellStyle(
          backgroundColorHex: isLongGap
              ? warning
              : (index.isOdd ? lightGray : ExcelColor.white),
          verticalAlign: VerticalAlign.Center,
          textWrapping: TextWrapping.WrapText,
          leftBorder: thinBorder,
          rightBorder: thinBorder,
          topBorder: thinBorder,
          bottomBorder: thinBorder,
        );
      }
      previous = row;
    }

    final widths = <double>[
      7,
      13,
      11,
      17,
      if (hasName) 24,
      15,
      15,
      14,
      15,
      14,
      27,
      21,
      12,
      42,
      38,
      19,
      42,
    ];
    for (var index = 0; index < widths.length; index++) {
      sheet.setColumnWidth(index, widths[index]);
    }

    _buildDeviceEventsSheet(
      excel: excel,
      events: events,
      from: from,
      to: to,
      userId: userId,
      userName: normalizedUserName,
    );

    final encoded = excel.encode();
    if (encoded == null) {
      throw const LocationReportException('Не удалось создать XLSX-файл.');
    }
    return Uint8List.fromList(encoded);
  }

  void _buildDeviceEventsSheet({
    required Excel excel,
    required List<DeviceEventRow> events,
    required DateTime from,
    required DateTime to,
    required String userId,
    required String userName,
  }) {
    final sheet = excel['События устройства'];
    final teal = ExcelColor.fromHexString('FF0F766E');
    final darkTeal = ExcelColor.fromHexString('FF115E59');
    final lightTeal = ExcelColor.fromHexString('FFCCFBF1');
    final lightGray = ExcelColor.fromHexString('FFF8FAFC');
    final warning = ExcelColor.fromHexString('FFFFF7ED');
    final borderColor = ExcelColor.fromHexString('FFCBD5E1');
    final thinBorder = Border(
      borderStyle: BorderStyle.Thin,
      borderColorHex: borderColor,
    );
    const headers = [
      '№',
      'Начало',
      'Окончание',
      'Длительность',
      'Событие',
      'Сторона',
      'Статус',
      'Примечание',
    ];

    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
      CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: 0),
      customValue: TextCellValue('СОБЫТИЯ УСТРОЙСТВА'),
    );
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0))
        .cellStyle = CellStyle(
      backgroundColorHex: darkTeal,
      fontColorHex: ExcelColor.white,
      fontSize: 16,
      bold: true,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );
    sheet.setRowHeight(0, 30);

    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1),
      CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: 1),
      customValue: TextCellValue(
        'Период: ${_date(from)} — ${_date(to)}  •  User ID: $userId'
        '${userName.isNotEmpty ? '  •  $userName' : ''}',
      ),
    );
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1))
        .cellStyle = CellStyle(
      backgroundColorHex: lightTeal,
      fontColorHex: darkTeal,
      bold: true,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );
    sheet.setRowHeight(1, 24);

    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 2),
      CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: 2),
      customValue: TextCellValue(
        events.isEmpty
            ? 'За выбранный период события устройства не зафиксированы'
            : 'Всего событий: ${events.length}',
      ),
    );
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 2))
        .cellStyle = CellStyle(
      fontColorHex: ExcelColor.fromHexString('FF334155'),
      bold: true,
      horizontalAlign: HorizontalAlign.Center,
    );

    for (var column = 0; column < headers.length; column++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: column, rowIndex: 4),
      );
      cell.value = TextCellValue(headers[column]);
      cell.cellStyle = CellStyle(
        backgroundColorHex: teal,
        fontColorHex: ExcelColor.white,
        bold: true,
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
        textWrapping: TextWrapping.WrapText,
        leftBorder: thinBorder,
        rightBorder: thinBorder,
        topBorder: thinBorder,
        bottomBorder: thinBorder,
      );
    }
    sheet.setRowHeight(4, 31);

    final generatedAt = DateTime.now();
    for (var index = 0; index < events.length; index++) {
      final event = events[index];
      final effectiveEnd = event.endedAt ?? generatedAt;
      final values = <CellValue?>[
        IntCellValue(index + 1),
        TextCellValue(_dateTime(event.startedAt)),
        TextCellValue(
          event.endedAt == null ? 'Продолжается' : _dateTime(event.endedAt!),
        ),
        TextCellValue(_duration(effectiveEnd.difference(event.startedAt))),
        TextCellValue(event.eventName),
        TextCellValue(event.owner),
        TextCellValue(event.endedAt == null ? 'Продолжается' : 'Завершено'),
        TextCellValue(
          'Время определяется проверкой приложения и может отличаться '
          'от фактического на несколько минут',
        ),
      ];
      final rowIndex = index + 5;
      for (var column = 0; column < values.length; column++) {
        final cell = sheet.cell(
          CellIndex.indexByColumnRow(
            columnIndex: column,
            rowIndex: rowIndex,
          ),
        );
        cell.value = values[column];
        cell.cellStyle = CellStyle(
          backgroundColorHex: event.endedAt == null
              ? warning
              : (index.isOdd ? lightGray : ExcelColor.white),
          verticalAlign: VerticalAlign.Center,
          textWrapping: TextWrapping.WrapText,
          leftBorder: thinBorder,
          rightBorder: thinBorder,
          topBorder: thinBorder,
          bottomBorder: thinBorder,
        );
      }
      sheet.setRowHeight(rowIndex, 31);
    }

    const widths = <double>[7, 22, 22, 17, 38, 16, 17, 48];
    for (var index = 0; index < widths.length; index++) {
      sheet.setColumnWidth(index, widths[index]);
    }
  }

  int _countLongGaps(List<LocationReportRow> rows) {
    var count = 0;
    for (var index = 1; index < rows.length; index++) {
      if (rows[index]
              .capturedAt
              .difference(rows[index - 1].capturedAt)
              .inSeconds >
          60) {
        count++;
      }
    }
    return count;
  }

  String _fileDate(DateTime value) =>
      '${value.year}-${_two(value.month)}-${_two(value.day)}';
  String _fileTimestamp(DateTime value) =>
      '${value.year}${_two(value.month)}${_two(value.day)}_'
      '${_two(value.hour)}${_two(value.minute)}${_two(value.second)}_'
      '${value.millisecond.toString().padLeft(3, '0')}';
  String _date(DateTime value) =>
      '${_two(value.day)}.${_two(value.month)}.${value.year}';
  String _time(DateTime value) =>
      '${_two(value.hour)}:${_two(value.minute)}:${_two(value.second)}';
  String _dateTime(DateTime value) => '${_date(value)} ${_time(value)}';
  String _two(int value) => value.toString().padLeft(2, '0');

  String _duration(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60);
    final seconds = value.inSeconds.remainder(60);
    return '${_two(hours)}:${_two(minutes)}:${_two(seconds)}';
  }
}

class LocationReportData {
  const LocationReportData({
    required this.bytes,
    required this.fileName,
    required this.total,
    required this.sent,
    required this.pending,
    required this.longGaps,
    required this.deviceEvents,
  });

  final Uint8List bytes;
  final String fileName;
  final int total;
  final int sent;
  final int pending;
  final int longGaps;
  final int deviceEvents;
}

class LocationReportException implements Exception {
  const LocationReportException(this.message);

  final String message;

  @override
  String toString() => message;
}
