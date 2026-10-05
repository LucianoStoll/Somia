import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'sync_manager.dart';

abstract class AutoSyncPreference {
  Future<bool> read();
  Future<void> write(bool enabled);
}

class FileAutoSyncPreference implements AutoSyncPreference {
  FileAutoSyncPreference(this.directory);
  final Directory directory;
  File get _file => File('${directory.path}/somia-sync-auto.txt');
  @override
  Future<bool> read() async {
    if (!await _file.exists()) return true;
    final value=(await _file.readAsString()).trim();
    if(value!='true' && value!='false') throw const FormatException('Preferência de sincronização inválida. Escolha novamente nos Ajustes.');
    return value=='true';
  }
  @override
  Future<void> write(bool enabled) async {
    await directory.create(recursive:true);
    final temporary=File('${_file.path}.tmp');
    await temporary.writeAsString('$enabled',flush:true);
    await temporary.rename(_file.path);
  }
}

/// One foreground loop: observe local clock, debounce writes and poll Drive.
class AutoSyncController extends ChangeNotifier {
  AutoSyncController(this.manager,this.preference,{required this.safeToApply,
    this.poll=const Duration(seconds:2),this.debounce=const Duration(seconds:3),
    this.remoteInterval=const Duration(minutes:1),
    this.retryDelays=const [Duration(seconds:15),Duration(seconds:30),Duration(minutes:1),Duration(minutes:2),Duration(minutes:5)],
    DateTime Function()? clock}) : clock=clock??DateTime.now;
  final SyncManager manager;
  final AutoSyncPreference preference;
  final bool Function() safeToApply;
  final Duration poll,debounce,remoteInterval;
  final List<Duration> retryDelays;
  final DateTime Function() clock;
  bool enabled=true,loaded=false,active=false,saving=false,waiting=false;
  String? error;
  DateTime? retryAt;
  Timer? _timer;
  Future<void>? _initialization;
  bool _disposed=false,_checking=false;
  int _failures=0;
  String? _base;
  int? _observedClock;
  DateTime? _due,_remoteDue;
  void _notify(){if(!_disposed)notifyListeners();}
  Future<void> initialize()=>_initialization??=()async{
    try{enabled=await preference.read();}
    catch(_){enabled=false;error='Não foi possível ler a preferência. Escolha novamente a sincronização automática.';}
    loaded=true;_notify();_schedule(Duration.zero);
  }();
  Future<void> setEnabled(bool value) async {
    if(saving || _disposed)return;
    await initialize();saving=true;_notify();
    try{
      await preference.write(value);
      if(_disposed)return;
      enabled=value;error=null;retryAt=null;_failures=0;_due=clock();
      if(!enabled){_timer?.cancel();waiting=false;}
    }catch(_){error='Não foi possível salvar a preferência. Tente novamente.';}
    finally{saving=false;_notify();_schedule(Duration.zero);}
  }
  void resume(){
    if(_disposed || active)return;
    active=true;_due=clock();retryAt=null;_failures=0;_notify();
    unawaited(initialize());_schedule(Duration.zero);
  }
  void pause(){active=false;_timer?.cancel();waiting=false;_notify();}
  void _schedule(Duration delay){
    _timer?.cancel();
    if(!_disposed && active && loaded && enabled)_timer=Timer(delay,()=>unawaited(_check()));
  }
  void _retry(){
    final index=_failures<retryDelays.length?_failures:retryDelays.length-1;
    retryAt=clock().add(retryDelays[index]);_failures++;
  }
  Future<void> _check() async {
    if(_disposed || !active || !enabled || _checking)return;
    _checking=true;
    try{
      if(manager.busy || manager.local.busy || manager.drive.busy)return;
      final state=await manager.store.state();
      if(_disposed || !active || !enabled)return;
      manager.observe(state);
      if(state.base==null){_base=null;_observedClock=null;retryAt=null;_due=null;_remoteDue=null;waiting=false;return;}
      final now=clock();
      if(state.base!=_base){
        _base=state.base;_observedClock=state.clock;_due=now;retryAt=null;_failures=0;
      }else if(state.clock!=_observedClock){
        _observedClock=state.clock;
        if(state.pending>0 || state.uploads>0)_due=now.add(debounce);
      }
      if(retryAt!=null && now.isBefore(retryAt!))return;
      final due=(_due!=null && !now.isBefore(_due!)) || (_remoteDue!=null && !now.isBefore(_remoteDue!));
      if(!due)return;
      if(!safeToApply()){waiting=true;return;}
      waiting=false;
      final completed=manager.completedSyncCycles;
      await manager.synchronize(automatic:true,canApply:()=>!_disposed && active && enabled && safeToApply());
      if(_disposed)return;
      if(manager.deferred){waiting=true;_due=clock();return;}
      if(manager.busy || (manager.completedSyncCycles==completed && manager.error==null))return;
      if(manager.error!=null){_retry();return;}
      _failures=0;retryAt=null;error=null;
      _remoteDue=clock().add(remoteInterval);
      final latest=manager.state;
      _observedClock=latest?.clock;
      _due=(latest!=null && (latest.pending>0 || latest.uploads>0))?clock().add(debounce):null;
    }catch(_){error='Não foi possível verificar a sincronização. As alterações foram preservadas.';_retry();}
    finally{_checking=false;_notify();_schedule(poll);}
  }
  @override
  void dispose(){_disposed=true;_timer?.cancel();super.dispose();}
}
