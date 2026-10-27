import 'dart:async';

import 'package:flutter/material.dart';

import '../models/diary_entry.dart';
import '../theme/app_theme.dart';
import '../utils/ru_date.dart';

/// Экран редактора записи. Привязан к дате; автосохранение при паузах.
class EditorScreen extends StatefulWidget {
  final DiaryEntry? existing; // null -> новая запись
  final String date; // ГГГГ-ММ-ДД
  final Future<void> Function(DiaryEntry entry) onSave;
  final Future<void> Function(DiaryEntry entry)? onDelete;

  const EditorScreen({
    super.key,
    required this.date,
    required this.onSave,
    this.existing,
    this.onDelete,
  });

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final TextEditingController _title;
  late final TextEditingController _text;
  Timer? _autoSave;
  bool _dirty = false;
  bool _savedOnce = false;
  late DiaryEntry _entry;

  @override
  void initState() {
    super.initState();
    _entry = widget.existing ?? DiaryEntry.create(date: widget.date);
    _title = TextEditingController(text: _entry.title);
    _text = TextEditingController(text: _entry.text);
    _title.addListener(_markDirty);
    _text.addListener(_markDirty);
  }

  void _markDirty() {
    _dirty = true;
    _autoSave?.cancel();
    _autoSave = Timer(const Duration(milliseconds: 900), _save);
    setState(() {}); // обновить счётчик слов
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    final text = _text.text;
    if (title.isEmpty && text.trim().isEmpty) return;
    _entry = _entry.copyWith(
      title: title,
      text: text,
      updatedAt: DateTime.now(),
    );
    await widget.onSave(_entry);
    _savedOnce = true;
    if (mounted) setState(() => _dirty = false);
  }

  @override
  void dispose() {
    _autoSave?.cancel();
    // Финальное сохранение при выходе.
    final title = _title.text.trim();
    final text = _text.text;
    if (title.isNotEmpty || text.trim().isNotEmpty) {
      _entry = _entry.copyWith(
        title: title,
        text: text,
        updatedAt: DateTime.now(),
      );
      widget.onSave(_entry);
    }
    _title.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Удалить запись?'),
        content: const Text('Это действие нельзя отменить.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok == true && widget.onDelete != null) {
      await widget.onDelete!(_entry);
      if (context.mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entriesText = _text.text;
    final words = entriesText.trim().isEmpty
        ? 0
        : entriesText.trim().split(RegExp(r'\s+')).length;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () async {
            await _save();
            if (context.mounted) Navigator.pop(context);
          },
        ),
        title: Text(
          RuDate.prettyWithWeekday(widget.date),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
        actions: [
          if (widget.existing != null && widget.onDelete != null)
            IconButton(
              icon: const Icon(
                Icons.delete_outline_rounded,
                color: AppColors.danger,
              ),
              onPressed: _confirmDelete,
            ),
          Padding(
            padding: const EdgeInsets.only(right: 16, left: 4),
            child: Center(
              child: Text(
                _dirty ? 'сохранение…' : (_savedOnce ? 'сохранено' : ''),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textFaint,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
                decoration: const InputDecoration(
                  hintText: 'Заголовок (необязательно)',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  contentPadding: EdgeInsets.symmetric(vertical: 8),
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
              const Divider(),
              Expanded(
                child: TextField(
                  controller: _text,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(
                    fontSize: 16.5,
                    height: 1.6,
                    color: AppColors.textPrimary,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Как прошёл день? О чём думаете?..',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      RuDate.pretty(widget.date),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textFaint,
                      ),
                    ),
                    Text(
                      '$words ${_plural(words, 'слово', 'слова', 'слов')}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textFaint,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _plural(int n, String one, String few, String many) {
    final mod10 = n % 10;
    final mod100 = n % 100;
    if (mod10 == 1 && mod100 != 11) return one;
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 10 || mod100 >= 20)) return few;
    return many;
  }
}
