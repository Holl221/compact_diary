import 'package:intl/intl.dart';

/// Русские месяцы и дни недели (intl иногда требует инициализации локали,
/// поэтому надёжнее держать собственные словари).
class RuDate {
  static const List<String> months = [
    'января',
    'февраля',
    'марта',
    'апреля',
    'мая',
    'июня',
    'июля',
    'августа',
    'сентября',
    'октября',
    'ноября',
    'декабря',
  ];

  static const List<String> monthsNominative = [
    'Январь',
    'Февраль',
    'Март',
    'Апрель',
    'Май',
    'Июнь',
    'Июль',
    'Август',
    'Сентябрь',
    'Октябрь',
    'Ноябрь',
    'Декабрь',
  ];

  static const List<String> weekdaysShort = [
    'Пн',
    'Вт',
    'Ср',
    'Чт',
    'Пт',
    'Сб',
    'Вс',
  ];

  static const List<String> weekdaysFull = [
    'Понедельник',
    'Вторник',
    'Среда',
    'Четверг',
    'Пятница',
    'Суббота',
    'Воскресенье',
  ];

  /// 2025-03-14 -> 14 марта 2025
  static String pretty(String isoDate) {
    final d = DateTime.tryParse(isoDate);
    if (d == null) return isoDate;
    return prettyDate(d);
  }

  static String prettyDate(DateTime d) {
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  /// 2025-03-14 -> "14 марта 2025, пятница"
  static String prettyWithWeekday(String isoDate) {
    final d = DateTime.tryParse(isoDate);
    if (d == null) return isoDate;
    return '${prettyDate(d)}, ${weekdaysFull[d.weekday - 1].toLowerCase()}';
  }

  /// 2025-03-14 -> "14 мар"
  static String short(String isoDate) {
    final d = DateTime.tryParse(isoDate);
    if (d == null) return isoDate;
    final m = months[d.month - 1];
    return '${d.day} ${m.substring(0, m.length >= 3 ? 3 : m.length)}';
  }

  static String monthTitle(int month) => monthsNominative[month - 1];

  /// "Сегодня", "Вчера" или дата.
  static String relative(String isoDate) {
    final d = DateTime.tryParse(isoDate);
    if (d == null) return isoDate;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(d.year, d.month, d.day);
    final diff = today.difference(target).inDays;
    if (diff == 0) return 'Сегодня';
    if (diff == 1) return 'Вчера';
    if (diff == 2) return 'Позавчера';
    return prettyDate(d);
  }

  static String time(DateTime dt) => DateFormat('HH:mm').format(dt);

  static String isoOf(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static String isoToday() => isoOf(DateTime.now());

  /// Дата на русском для календаря в верхней панели.
  static String calendarHeader(DateTime d) =>
      '${monthTitle(d.month)} ${d.year}';
}
