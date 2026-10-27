import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:table_calendar/table_calendar.dart';

import '../models/diary_entry.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../utils/ru_date.dart';
import 'editor_screen.dart';

/// Главный экран: календарь с отметками дней, где есть записи,
/// и список записей выбранного дня.
class HomeScreen extends StatefulWidget {
  final StorageService storage;
  final VoidCallback onLock;

  const HomeScreen({super.key, required this.storage, required this.onLock});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<DiaryEntry> _all = [];
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay = DateTime.now();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await widget.storage.loadEntries();
    if (!mounted) return;
    setState(() {
      _all = entries;
      _loading = false;
    });
  }

  // Записи по конкретному дню.
  List<DiaryEntry> _forDay(DateTime day) {
    final iso = RuDate.isoOf(day);
    return _all.where((e) => e.date == iso).toList();
  }

  // Множество дат, где есть записи (для точек в календаре).
  Set<String> get _datedSet => _all.map((e) => e.date).toSet();

  Future<void> _openEditor({DiaryEntry? existing, DateTime? day}) async {
    final date =
        existing?.date ?? RuDate.isoOf(day ?? _selectedDay ?? DateTime.now());
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EditorScreen(
          date: date,
          existing: existing,
          onSave: (entry) async {
            final idx = _all.indexWhere((e) => e.id == entry.id);
            final list = List<DiaryEntry>.from(_all);
            if (idx >= 0) {
              list[idx] = entry;
            } else {
              list.add(entry);
            }
            await widget.storage.saveEntries(list);
            if (mounted) setState(() => _all = list);
          },
          onDelete: existing == null
              ? null
              : (entry) async {
                  final list = _all.where((e) => e.id != entry.id).toList();
                  await widget.storage.saveEntries(list);
                  if (mounted) setState(() => _all = list);
                },
        ),
      ),
    );
  }

  Future<void> _export() async {
    if (_all.isEmpty) {
      _snack('Пока нет записей для экспорта');
      return;
    }
    final box = context.findRenderObject() as RenderBox?;
    try {
      final paths = await widget.storage.exportAndListFiles(_all);
      if (paths.isNotEmpty) {
        await Share.shareXFiles(
          paths.map((p) => XFile(p)).toList(),
          subject: 'Дневник — ${_all.length} записей',
          sharePositionOrigin: box != null
              ? box.localToGlobal(Offset.zero) & box.size
              : null,
        );
        _snack('Экспортировано: ${paths.length} txt-файлов в DiaryExport');
      } else {
        _snack('Экспорт файлов недоступен на этой платформе');
      }
    } catch (e) {
      _snack('Ошибка экспорта: $e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final dayEntries = _selectedDay == null
        ? <DiaryEntry>[]
        : _forDay(_selectedDay!);

    return Scaffold(
      appBar: AppBar(
        title: _buildHeader(),
        actions: [
          IconButton(
            tooltip: 'Экспортировать в TXT',
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: _export,
          ),
          IconButton(
            tooltip: 'Заблокировать',
            icon: const Icon(Icons.lock_outline_rounded),
            onPressed: widget.onLock,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            )
          : RefreshIndicator(
              color: AppColors.accent,
              backgroundColor: AppColors.surface,
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                children: [
                  _CalendarCard(
                    focusedDay: _focusedDay,
                    selectedDay: _selectedDay,
                    datedSet: _datedSet,
                    onDaySelected: (selected, focused) {
                      setState(() {
                        _selectedDay = selected;
                        _focusedDay = focused;
                      });
                    },
                    onPageChanged: (focused) => _focusedDay = focused,
                  ),
                  const SizedBox(height: 20),
                  _sectionTitle(dayEntries),
                  const SizedBox(height: 12),
                  if (dayEntries.isEmpty)
                    _EmptyDay(
                      date: _selectedDay ?? DateTime.now(),
                      onWrite: () =>
                          _openEditor(day: _selectedDay ?? DateTime.now()),
                    )
                  else
                    ...dayEntries.map(
                      (e) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _EntryTile(
                          entry: e,
                          onTap: () => _openEditor(existing: e),
                        ),
                      ),
                    ),
                  if (_all.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    _RecentStrip(
                      entries: _all.take(8).toList(),
                      onTap: (e) => _openEditor(existing: e),
                    ),
                  ],
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(day: _selectedDay ?? DateTime.now()),
        icon: const Icon(Icons.edit_rounded),
        label: const Text('Запись'),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Мой дневник',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(
          '${_all.length} ${_pluralCount(_all.length)}',
          style: const TextStyle(
            fontSize: 12.5,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(List<DiaryEntry> dayEntries) {
    final label = _selectedDay != null
        ? RuDate.relative(RuDate.isoOf(_selectedDay!))
        : 'Выберите день';
    return Row(
      children: [
        Text(
          _selectedDay != null &&
                  RuDate.isoOf(_selectedDay!) == RuDate.isoToday()
              ? 'Сегодня'
              : label,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        if (_selectedDay != null && _selectedDay != DateTime.now()) ...[
          const SizedBox(width: 8),
          Text(
            RuDate.relative(RuDate.isoOf(_selectedDay!)),
            style: const TextStyle(fontSize: 13, color: AppColors.textFaint),
          ),
        ],
      ],
    );
  }

  static String _pluralCount(int n) {
    final mod10 = n % 10;
    final mod100 = n % 100;
    String word;
    if (mod10 == 1 && mod100 != 11) {
      word = 'запись';
    } else if (mod10 >= 2 && mod10 <= 4 && (mod100 < 10 || mod100 >= 20)) {
      word = 'записи';
    } else {
      word = 'записей';
    }
    return word;
  }
}

// ─────────────────────────── Календарь ───────────────────────────

class _CalendarCard extends StatelessWidget {
  final DateTime focusedDay;
  final DateTime? selectedDay;
  final Set<String> datedSet;
  final void Function(DateTime selected, DateTime focused) onDaySelected;
  final void Function(DateTime focused) onPageChanged;

  const _CalendarCard({
    required this.focusedDay,
    required this.selectedDay,
    required this.datedSet,
    required this.onDaySelected,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider),
      ),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      child: TableCalendar<Object>(
        firstDay: DateTime.utc(2000, 1, 1),
        lastDay: DateTime.utc(2100, 12, 31),
        focusedDay: focusedDay,
        selectedDayPredicate: (d) =>
            selectedDay != null && isSameDay(d, selectedDay),
        onDaySelected: onDaySelected,
        onPageChanged: onPageChanged,
        availableGestures: AvailableGestures.horizontalSwipe,
        rowHeight: 46,
        daysOfWeekHeight: 30,
        calendarFormat: CalendarFormat.month,
        headerStyle: HeaderStyle(
          formatButtonVisible: false,
          titleCentered: true,
          leftChevronIcon: const Icon(
            Icons.chevron_left_rounded,
            color: AppColors.accent,
          ),
          rightChevronIcon: const Icon(
            Icons.chevron_right_rounded,
            color: AppColors.accent,
          ),
          titleTextStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
          titleTextFormatter: (date, _) => RuDate.calendarHeader(date),
        ),
        daysOfWeekStyle: const DaysOfWeekStyle(
          weekdayStyle: TextStyle(
            color: AppColors.textFaint,
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
          ),
          weekendStyle: TextStyle(
            color: AppColors.textFaint,
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
          ),
          dowTextFormatter: _dowFormatter,
        ),
        calendarStyle: CalendarStyle(
          outsideDaysVisible: false,
          cellMargin: const EdgeInsets.all(4),
          defaultTextStyle: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14.5,
          ),
          weekendTextStyle: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14.5,
          ),
          todayDecoration: BoxDecoration(
            color: AppColors.surfaceHigh,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.accentSoft, width: 1.4),
          ),
          todayTextStyle: const TextStyle(
            color: AppColors.accent,
            fontWeight: FontWeight.w600,
          ),
          selectedDecoration: const BoxDecoration(
            color: AppColors.accent,
            shape: BoxShape.circle,
          ),
          selectedTextStyle: const TextStyle(
            color: Color(0xFF241B0E),
            fontWeight: FontWeight.w700,
          ),
          markerDecoration: const BoxDecoration(
            color: AppColors.accentSoft,
            shape: BoxShape.circle,
          ),
          markersMaxCount: 1,
          markerSize: 5,
          markerMargin: const EdgeInsets.only(top: 6),
        ),
        calendarBuilders: CalendarBuilders<Object>(
          markerBuilder: (context, day, events) {
            final iso = RuDate.isoOf(day);
            if (!datedSet.contains(iso)) return null;
            // Точка-маркер под датой.
            return Positioned(
              bottom: 6,
              child: Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: isSameDay(day, selectedDay ?? DateTime(1))
                      ? const Color(0xFF241B0E)
                      : AppColors.accentSoft,
                  shape: BoxShape.circle,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

String _dowFormatter(DateTime date, dynamic locale) {
  return RuDate.weekdaysShort[date.weekday - 1];
}

// ─────────────────────────── Плитка записи ───────────────────────────

class _EntryTile extends StatelessWidget {
  final DiaryEntry entry;
  final VoidCallback onTap;

  const _EntryTile({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (entry.title.isNotEmpty) ...[
                Text(
                  entry.title,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
              ],
              Text(
                entry.preview,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: AppColors.textSecondary,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(
                    Icons.schedule_rounded,
                    size: 13,
                    color: AppColors.textFaint,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    RuDate.time(entry.updatedAt),
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textFaint,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${entry.wordCount} сл.',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textFaint,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────── Пустой день ───────────────────────────

class _EmptyDay extends StatelessWidget {
  final DateTime date;
  final VoidCallback onWrite;

  const _EmptyDay({required this.date, required this.onWrite});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          Icon(
            Icons.edit_note_rounded,
            size: 44,
            color: AppColors.textFaint.withValues(alpha: 0.7),
          ),
          const SizedBox(height: 10),
          Text(
            'Нет записи за ${RuDate.pretty(RuDate.isoOf(date))}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onWrite,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Написать'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accent,
              side: const BorderSide(color: AppColors.accentSoft),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── Последние записи ───────────────────────────

class _RecentStrip extends StatelessWidget {
  final List<DiaryEntry> entries;
  final void Function(DiaryEntry) onTap;

  const _RecentStrip({required this.entries, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Последние записи',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: entries.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final e = entries[i];
              return InkWell(
                onTap: () => onTap(e),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: 150,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        RuDate.relative(e.date),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.accent,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Expanded(
                        child: Text(
                          e.title.isNotEmpty ? e.title : e.preview,
                          style: const TextStyle(
                            fontSize: 13,
                            height: 1.35,
                            color: AppColors.textSecondary,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
