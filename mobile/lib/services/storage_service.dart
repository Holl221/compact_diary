import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/diary_entry.dart';

/// Хранилище записей, пароля и логика экспорта в txt-файлы.
///
/// Работает на Android (на диске) и в web (только SharedPreferences) —
/// поэтому все файловые операции обёрнуты в проверку платформы.
class StorageService {
  static const _kEntries = 'diary_entries_v1';
  static const _kPassHash = 'diary_pass_hash_v1';
  static const _kPassSalt = 'diary_pass_salt_v1';
  static const _kHasPass = 'diary_has_pass_v1';

  SharedPreferences? _prefs;

  Future<SharedPreferences> get _p async =>
      _prefs ??= await SharedPreferences.getInstance();

  bool get _supportsFiles => !kIsWeb;

  // ───────────────────────── ПАРОЛЬ ─────────────────────────

  Future<bool> hasPassword() async {
    final p = await _p;
    return p.getBool(_kHasPass) ?? false;
  }

  /// Устанавливает пароль. Хранится только sha256(соль + пароль).
  Future<void> setPassword(String password) async {
    final p = await _p;
    final salt = _randomSalt();
    p.setString(_kPassSalt, salt);
    p.setString(_kPassHash, _hash(password, salt));
    p.setBool(_kHasPass, true);
  }

  Future<bool> verifyPassword(String password) async {
    final p = await _p;
    final salt = p.getString(_kPassSalt);
    final hash = p.getString(_kPassHash);
    if (salt == null || hash == null) return false;
    return _hash(password, salt) == hash;
  }

  Future<void> clearPassword() async {
    final p = await _p;
    p.remove(_kPassHash);
    p.remove(_kPassSalt);
    p.setBool(_kHasPass, false);
  }

  String _randomSalt() {
    final now = DateTime.now().microsecondsSinceEpoch;
    return '${now}_${now.hashCode}';
  }

  String _hash(String password, String salt) {
    return sha256.convert(utf8.encode('$salt::$password')).toString();
  }

  // ───────────────────────── ЗАПИСИ ─────────────────────────

  Future<List<DiaryEntry>> loadEntries() async {
    final p = await _p;
    final raw = p.getString(_kEntries);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final entries = list
          .map((e) => DiaryEntry.fromMap(e as Map<String, dynamic>))
          .toList();
      entries.sort((a, b) {
        final byDate = b.date.compareTo(a.date);
        if (byDate != 0) return byDate;
        return b.updatedAt.compareTo(a.updatedAt);
      });
      return entries;
    } catch (_) {
      return [];
    }
  }

  Future<void> saveEntries(List<DiaryEntry> entries) async {
    final p = await _p;
    final raw = jsonEncode(entries.map((e) => e.toMap()).toList());
    await p.setString(_kEntries, raw);
  }

  // ───────────────────────── ЭКСПОРТ / ИМПОРТ ─────────────────────────

  /// Папка на телефоне, куда сохраняем txt-файлы.
  Future<Directory?> _exportDir() async {
    if (!_supportsFiles) return null;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/DiaryExport');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Раскладывает все записи в отдельные txt-файлы `ГГГГ-ММ-ДД.txt`
  /// в папке DiaryExport. Возвращает путь к папке (или null на web).
  Future<String?> exportToTxtFiles(List<DiaryEntry> entries) async {
    final dir = await _exportDir();
    if (dir == null) return null;

    // Группируем по дате: несколько записей одного дня -> один файл.
    final byDate = <String, List<DiaryEntry>>{};
    for (final e in entries) {
      byDate.putIfAbsent(e.date, () => []).add(e);
    }

    for (final entry in byDate.entries) {
      final date = entry.key;
      final items = entry.value
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      final sb = StringBuffer();
      sb.writeln('=== $date ===');
      for (var i = 0; i < items.length; i++) {
        final it = items[i];
        if (it.title.trim().isNotEmpty) {
          sb.writeln();
          sb.writeln('— ${it.title.trim()} —');
        }
        sb.writeln();
        sb.write(it.text);
        sb.writeln();
        if (i != items.length - 1) {
          sb.writeln();
          sb.writeln('· · ·');
        }
      }
      final file = File('${dir.path}/$date.txt');
      await file.writeAsString(sb.toString());
    }
    return dir.path;
  }

  /// Экспортирует записи и возвращает пути к получившимся txt-файлам
  /// (для системного меню «Поделиться»).
  Future<List<String>> exportAndListFiles(List<DiaryEntry> entries) async {
    final dirPath = await exportToTxtFiles(entries);
    if (dirPath == null) return [];
    final dir = Directory(dirPath);
    final files = <String>[];
    await for (final f in dir.list()) {
      if (f is File && f.path.toLowerCase().endsWith('.txt')) {
        files.add(f.path);
      }
    }
    files.sort();
    return files;
  }

  Future<String?> exportDirPath() async {
    final dir = await _exportDir();
    return dir?.path;
  }

  /// Импорт из папки с txt-файлами (на случай переноса с ноутбука обратно).
  /// Распознаёт первый же паттерн ГГГГ-ММ-ДД в имени файла.
  Future<List<DiaryEntry>> importFromTxtDir(String dirPath) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return [];
    final result = <DiaryEntry>[];
    final regex = RegExp(r'(\d{4})-(\d{2})-(\d{2})');
    await for (final f in dir.list()) {
      if (f is! File || !f.path.toLowerCase().endsWith('.txt')) continue;
      final name = f.uri.pathSegments.last;
      final m = regex.firstMatch(name);
      if (m == null) continue;
      final date = '${m.group(1)}-${m.group(2)}-${m.group(3)}';
      final content = await f.readAsString();
      var text = content;
      // Убираем служебную строку "=== дата ===".
      text = text.replaceFirst(RegExp(r'^===\s*.*?\s*===\s*'), '');
      final entry = DiaryEntry.create(date: date, text: text.trim());
      result.add(entry);
    }
    return result;
  }
}
