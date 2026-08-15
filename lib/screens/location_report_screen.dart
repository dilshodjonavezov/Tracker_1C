import 'package:background_location_tracker_example/dao/location_dao.dart';
import 'package:background_location_tracker_example/services/location_report_service.dart';
import 'package:background_location_tracker_example/services/server_service.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocationReportScreen extends StatefulWidget {
  const LocationReportScreen({super.key});

  @override
  State<LocationReportScreen> createState() => _LocationReportScreenState();
}

class _LocationReportScreenState extends State<LocationReportScreen> {
  final _reportService = LocationReportService();
  final _serverService = ServerService();
  late DateTimeRange _range;
  String? _userId;
  String? _userName;
  bool _loading = true;
  bool _sharing = false;
  int? _availablePoints;
  int? _availableEvents;

  @override
  void initState() {
    super.initState();
    final today = _dateOnly(DateTime.now());
    _range = DateTimeRange(
      start: today.subtract(const Duration(days: 7)),
      end: today,
    );
    _load();
  }

  Future<void> _load() async {
    final today = _dateOnly(DateTime.now());
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id');
    final available = await LocationDao().getAvailableDateRange(userId: userId);
    if (!mounted) return;
    setState(() {
      _userId = userId;
      _userName = prefs.getString('user_name');
      if (available != null) {
        final availableStart = _dateOnly(available.start);
        final availableEnd = _dateOnly(available.end);
        final defaultEnd = today.isAfter(availableEnd) ? availableEnd : today;
        final sevenDaysBefore = defaultEnd.subtract(const Duration(days: 7));
        final defaultStart = sevenDaysBefore.isBefore(availableStart)
            ? availableStart
            : sevenDaysBefore;
        _range = DateTimeRange(
          start: defaultStart,
          end: defaultEnd,
        );
      }
      _loading = false;
    });
    await _refreshCount();
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _range,
      helpText: 'ВЫБЕРИТЕ ПЕРИОД ОТЧЁТА',
      saveText: 'ГОТОВО',
      cancelText: 'ОТМЕНА',
      confirmText: 'ВЫБРАТЬ',
      fieldStartHintText: 'От',
      fieldEndHintText: 'До',
    );
    if (picked == null || !mounted) return;
    setState(() => _range = picked);
    await _refreshCount();
  }

  Future<void> _refreshCount() async {
    final userId = _userId;
    if (userId == null || userId.isEmpty) return;
    final rows = await LocationDao().getReportRows(
      from: _dateOnly(_range.start),
      toExclusive: _dateOnly(_range.end).add(const Duration(days: 1)),
      userId: userId,
    );
    final events = await LocationDao().getDeviceEvents(
      from: _dateOnly(_range.start),
      toExclusive: _dateOnly(_range.end).add(const Duration(days: 1)),
      userId: userId,
    );
    if (!mounted) return;
    setState(() {
      _availablePoints = rows.length;
      _availableEvents = events.length;
    });
  }

  Future<void> _share() async {
    final userId = _userId;
    if (userId == null || userId.isEmpty) {
      _showMessage('User ID не найден. Войдите в приложение заново.');
      return;
    }
    setState(() => _sharing = true);
    try {
      await _serverService.flushPendingLocations(force: true);
      final report = await _reportService.buildReport(
        from: _range.start,
        toInclusive: _range.end,
        userId: userId,
        userName: _userName,
      );
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      await _reportService.shareReport(
        report,
        sharePositionOrigin:
            box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      );
    } on LocationReportException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (error) {
      if (mounted) _showMessage('Не удалось подготовить отчёт: $error');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: const Text('Отчёт GPS'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: const BorderSide(color: Color(0xFFCCFBF1)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.calendar_month, color: Colors.teal),
                              SizedBox(width: 10),
                              Text(
                                'Период отчёта',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF134E4A),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          InkWell(
                            onTap: _sharing ? null : _pickRange,
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 15,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF0FDFA),
                                borderRadius: BorderRadius.circular(12),
                                border:
                                    Border.all(color: const Color(0xFF99F6E4)),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: _DateValue(
                                      label: 'От',
                                      value: _formatDate(_range.start),
                                    ),
                                  ),
                                  const Icon(
                                    Icons.arrow_forward,
                                    color: Colors.teal,
                                  ),
                                  Expanded(
                                    child: _DateValue(
                                      label: 'До',
                                      value: _formatDate(_range.end),
                                      alignEnd: true,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Сохранено точек: ${_availablePoints ?? 0}',
                            style: const TextStyle(
                              color: Color(0xFF475569),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Событий устройства: ${_availableEvents ?? 0}',
                            style: const TextStyle(
                              color: Color(0xFF475569),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Card(
                    elevation: 0,
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'В Excel войдут все точки, которые сохранил телефон: '
                        'отправленные, ожидающие и не отправленные. Для ошибок '
                        'будут указаны понятная причина и ответственная сторона. '
                        'Разрывы между GPS-точками также будут отмечены. '
                        'Отключение геолокации и её восстановление попадут '
                        'на отдельный лист «События устройства». Перед каждым '
                        'отчётом приложение обновит отправку и сохранит HTTP-код '
                        'и ответ сервера.',
                        style:
                            TextStyle(height: 1.45, color: Color(0xFF475569)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  FilledButton.icon(
                    onPressed: _sharing ? null : _share,
                    icon: _sharing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.ios_share),
                    label: Text(
                      _sharing
                          ? 'Синхронизируем и формируем…'
                          : 'Поделиться XLSX',
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.teal,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  String _formatDate(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}.'
      '${value.month.toString().padLeft(2, '0')}.${value.year}';
}

class _DateValue extends StatelessWidget {
  const _DateValue({
    required this.label,
    required this.value,
    this.alignEnd = false,
  });

  final String label;
  final String value;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF134E4A),
          ),
        ),
      ],
    );
  }
}
