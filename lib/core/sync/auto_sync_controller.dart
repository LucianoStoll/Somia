import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'sync_manager.dart';

enum AutoSyncMode { grouped, eachChange }

abstract class AutoSyncPreference {
  Future<bool> read();
  Future<void> write(bool enabled);
  Future<AutoSyncMode> readMode();
  Future<void> writeMode(AutoSyncMode mode);
}

class FileAutoSyncPreference implements AutoSyncPreference {
  FileAutoSyncPreference(this.directory);
  final Directory directory;
  File get _file => File('${directory.path}/somia-sync-auto.txt');
  File get _modeFile => File('${directory.path}/somia-sync-mode.txt');
  @override
  Future<AutoSyncMode> readMode() async {
    if (!await _modeFile.exists()) return AutoSyncMode.grouped;
    final value = (await _modeFile.readAsString()).trim();
    return AutoSyncMode.values.firstWhere((mode) => mode.name == value,
        orElse: () =>
            throw const FormatException('Modo de sincronização inválido.'));
  }

  @override
  Future<void> writeMode(AutoSyncMode mode) async {
    await directory.create(recursive: true);
    final temporary = File('${_modeFile.path}.tmp');
    await temporary.writeAsString(mode.name, flush: true);
    await temporary.rename(_modeFile.path);
  }

  @override
  Future<bool> read() async {
    if (!await _file.exists()) return true;
    final value = (await _file.readAsString()).trim();
    if (value != 'true' && value != 'false') {
      throw const FormatException(
          'Preferência de sincronização inválida. Escolha novamente nos Ajustes.');
    }
    return value == 'true';
  }

  @override
  Future<void> write(bool enabled) async {
    await directory.create(recursive: true);
    final temporary = File('${_file.path}.tmp');
    await temporary.writeAsString('$enabled', flush: true);
    await temporary.rename(_file.path);
  }
}

/// One foreground loop: observe committed writes and poll Drive.
class AutoSyncController extends ChangeNotifier {
  AutoSyncController(this.manager, this.preference,
      {required this.safeToApply,
      this.poll = const Duration(seconds: 2),
      this.debounce = const Duration(seconds: 3),
      this.remoteInterval = const Duration(minutes: 1),
      this.retryDelays = const [
        Duration(seconds: 15),
        Duration(seconds: 30),
        Duration(minutes: 1),
        Duration(minutes: 2),
        Duration(minutes: 5)
      ],
      DateTime Function()? clock})
      : clock = clock ?? DateTime.now;
  final SyncManager manager;
  final AutoSyncPreference preference;
  final bool Function() safeToApply;
  final Duration poll, debounce, remoteInterval;
  final List<Duration> retryDelays;
  final DateTime Function() clock;
  bool enabled = true,
      loaded = false,
      active = false,
      saving = false,
      waiting = false;
  AutoSyncMode mode = AutoSyncMode.grouped;
  Duration get _writeDelay =>
      mode == AutoSyncMode.eachChange ? Duration.zero : debounce;
  StreamSubscription<void>? _changes;
  bool _wake = false;
  String? error;
  DateTime? retryAt;
  Timer? _timer;
  Future<void>? _initialization;
  bool _disposed = false, _checking = false;
  int _failures = 0;
  String? _base;
  int? _observedClock;
  DateTime? _due, _remoteDue, _observedSync;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() => _initialization ??= () async {
        try {
          enabled = await preference.read();
          mode = await preference.readMode();
        } catch (_) {
          enabled = false;
          error =
              'Não foi possível ler a preferência. Escolha novamente a sincronização automática.';
        }
        loaded = true;
        _notify();
        _schedule(Duration.zero);
      }();
  Future<void> setEnabled(bool value) async {
    if (saving || _disposed) return;
    await initialize();
    saving = true;
    _notify();
    try {
      await preference.write(value);
      if (_disposed) return;
      enabled = value;
      error = null;
      retryAt = null;
      _failures = 0;
      _due = clock();
      if (!enabled) {
        _timer?.cancel();
        waiting = false;
      }
    } catch (_) {
      error = 'Não foi possível salvar a preferência. Tente novamente.';
    } finally {
      saving = false;
      _notify();
      _schedule(Duration.zero);
    }
  }

  Future<void> setMode(AutoSyncMode value) async {
    if (saving || _disposed) return;
    await initialize();
    saving = true;
    _notify();
    try {
      await preference.writeMode(value);
      if (_disposed) return;
      mode = value;
      error = null;
      if (_due != null) _due = clock().add(_writeDelay);
    } catch (_) {
      error = 'Não foi possível salvar a preferência. Tente novamente.';
    } finally {
      saving = false;
      _notify();
      _schedule(Duration.zero);
    }
  }

  void _onChange(void _) {
    if (_disposed || !active || !enabled) return;
    if (_checking) {
      _wake = true;
    } else {
      _schedule(Duration.zero);
    }
  }

  void resume() {
    if (_disposed || active) return;
    active = true;
    _changes ??= manager.store.changes.listen(_onChange);
    _due = clock();
    retryAt = null;
    _failures = 0;
    _notify();
    unawaited(initialize());
    _schedule(Duration.zero);
  }

  void pause() {
    active = false;
    _timer?.cancel();
    waiting = false;
    _notify();
  }

  void _schedule(Duration delay) {
    _timer?.cancel();
    if (!_disposed && active && loaded && enabled) {
      _timer = Timer(delay, () => unawaited(_check()));
    }
  }

  void _retry() {
    final index =
        _failures < retryDelays.length ? _failures : retryDelays.length - 1;
    retryAt = clock().add(retryDelays[index]);
    _failures++;
  }

  Future<void> _check() async {
    if (_disposed || !active || !enabled || _checking) return;
    _checking = true;
    var completedCycle = false;
    try {
      if (manager.busy || manager.local.busy || manager.drive.busy) return;
      final state = await manager.store.state();
      if (_disposed || !active || !enabled) return;
      manager.observe(state);
      if (state.base == null) {
        _base = null;
        _observedClock = null;
        retryAt = null;
        _due = null;
        _remoteDue = null;
        waiting = false;
        return;
      }
      final now = clock();
      if (state.lastSync != null &&
          state.lastSync != _observedSync &&
          manager.error == null) {
        retryAt = null;
        _failures = 0;
        _remoteDue = now.add(remoteInterval);
        if (state.pending == 0 && state.uploads == 0) _due = null;
      }
      _observedSync = state.lastSync;
      if (state.base != _base) {
        _base = state.base;
        _observedClock = state.clock;
        _due = now;
        retryAt = null;
        _failures = 0;
      } else if (state.clock != _observedClock) {
        _observedClock = state.clock;
        if (state.pending > 0 || state.uploads > 0) _due = now.add(_writeDelay);
      }
      if (retryAt != null && now.isBefore(retryAt!)) return;
      final due = (_due != null && !now.isBefore(_due!)) ||
          (_remoteDue != null && !now.isBefore(_remoteDue!));
      if (!due) return;
      if (!safeToApply()) {
        waiting = true;
        return;
      }
      waiting = false;
      final completed = manager.completedSyncCycles;
      await manager.synchronize(
          automatic: true,
          canApply: () => !_disposed && active && enabled && safeToApply());
      if (_disposed) return;
      if (manager.deferred) {
        waiting = true;
        _due = clock();
        return;
      }
      if (manager.busy ||
          (manager.completedSyncCycles == completed && manager.error == null)) {
        return;
      }
      if (manager.error != null) {
        _retry();
        return;
      }
      completedCycle = true;
      _failures = 0;
      retryAt = null;
      error = null;
      _remoteDue = clock().add(remoteInterval);
      final latest = manager.state;
      _observedClock = latest?.clock;
      _observedSync = latest?.lastSync;
      _due = (latest != null && (latest.pending > 0 || latest.uploads > 0))
          ? clock().add(_writeDelay)
          : null;
    } catch (_) {
      error =
          'Não foi possível verificar a sincronização. As alterações foram preservadas.';
      _retry();
    } finally {
      _checking = false;
      _notify();
      final immediatePending = completedCycle &&
          mode == AutoSyncMode.eachChange &&
          !waiting &&
          retryAt == null &&
          _due != null &&
          !clock().isBefore(_due!);
      final wake = _wake;
      _wake = false;
      _schedule(wake || immediatePending ? Duration.zero : poll);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_changes?.cancel());
    _timer?.cancel();
    super.dispose();
  }
}
