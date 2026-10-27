import 'dart:convert';

/// Одна запись дневника, привязанная к конкретной дате.
///
/// Формат хранения (JSON) совместим с тем, что читает ноутбучное приложение:
/// файл `ГГГГ-ММ-ДД.txt` содержит либо чистый текст, либо JSON с полями
/// date / title / text. Здесь мы храним всё в телефоне в JSON-базе, а при
/// экспорте раскладываем в отдельные txt-файлы по датам.
class DiaryEntry {
  final String id; // стабильный идентификатор (для нескольких записей в день)
  final String date; // ГГГГ-ММ-ДД
  final String title;
  final String text;
  final DateTime createdAt;
  final DateTime updatedAt;

  const DiaryEntry({
    required this.id,
    required this.date,
    required this.title,
    required this.text,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DiaryEntry.create({
    required String date,
    String title = '',
    String text = '',
  }) {
    final now = DateTime.now();
    return DiaryEntry(
      id: '${now.microsecondsSinceEpoch}',
      date: date,
      title: title,
      text: text,
      createdAt: now,
      updatedAt: now,
    );
  }

  DiaryEntry copyWith({
    String? title,
    String? text,
    DateTime? updatedAt,
  }) {
    return DiaryEntry(
      id: id,
      date: date,
      title: title ?? this.title,
      text: text ?? this.text,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'date': date,
        'title': title,
        'text': text,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory DiaryEntry.fromMap(Map<String, dynamic> m) => DiaryEntry(
        id: m['id'] as String,
        date: m['date'] as String,
        title: (m['title'] ?? '') as String,
        text: (m['text'] ?? '') as String,
        createdAt: DateTime.tryParse(m['createdAt'] ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(m['updatedAt'] ?? '') ?? DateTime.now(),
      );

  String toJson() => jsonEncode(toMap());

  /// Содержимое будущего txt-файла при экспорте на ноутбук.
  /// Заголовок с датой + текст — так ноут легко распознает запись.
  String toTxtFileContent() {
    final sb = StringBuffer();
    sb.writeln('=== $date ===');
    if (title.trim().isNotEmpty) {
      sb.writeln(title.trim());
      sb.writeln();
    }
    sb.write(text);
    return sb.toString();
  }

  /// Короткий предпросмотр для списка.
  String get preview {
    final t = text.replaceAll('\n', ' ').trim();
    if (t.isEmpty) return title.trim().isEmpty ? 'Пустая запись' : title.trim();
    return t.length > 90 ? '${t.substring(0, 90)}…' : t;
  }

  int get wordCount {
    final t = text.trim();
    if (t.isEmpty) return 0;
    return t.split(RegExp(r'\s+')).length;
  }
}
