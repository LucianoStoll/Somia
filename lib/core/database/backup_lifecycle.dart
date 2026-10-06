import 'dart:async';
import 'package:flutter/widgets.dart';
import 'backup_manager.dart';

class BackupLifecycle extends StatefulWidget {
  const BackupLifecycle(
      {super.key, required this.manager, required this.child});
  final BackupManager manager;
  final Widget child;
  @override
  State<BackupLifecycle> createState() => _BackupLifecycleState();
}

class _BackupLifecycleState extends State<BackupLifecycle>
    with WidgetsBindingObserver {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  void _check() {
    _timer?.cancel();
    unawaited(widget.manager.daily());
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    _timer = Timer(tomorrow.difference(now), _check);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _check();
    } else {
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
