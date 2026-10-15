import 'dart:convert';
import 'dart:io';

/// Preferências visuais locais; não participam da base financeira ou do sync.
class InterfacePreferences {
  InterfacePreferences(this.file);
  final File file;
  Map<String, bool> _values = {};
  Future<void> _pending = Future.value();

  Future<void> load() async {
    try {
      final data =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      _values = {
        for (final e in data.entries)
          if (e.value is bool) e.key: e.value as bool
      };
    } on FileSystemException {
      _values = {};
    } on FormatException {
      _values = {};
    } on TypeError {
      _values = {};
    }
  }

  bool read(String key, {bool fallback = false}) => _values[key] ?? fallback;

  Future<void> write(String key, bool value) {
    _values[key] = value;
    final snapshot = jsonEncode(_values);
    final operation = _pending.then((_) async {
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(snapshot, flush: true);
      await temporary.rename(file.path);
    });
    _pending = operation.catchError((Object _) {});
    return operation;
  }
}
