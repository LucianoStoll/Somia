import 'package:flutter/widgets.dart';
import 'auto_sync_controller.dart';

class SyncLifecycle extends StatefulWidget {
  const SyncLifecycle({super.key,required this.controller,required this.child});
  final AutoSyncController controller;
  final Widget child;
  @override State<SyncLifecycle> createState()=>_SyncLifecycleState();
}
class _SyncLifecycleState extends State<SyncLifecycle> with WidgetsBindingObserver {
  @override void initState(){
    super.initState();WidgetsBinding.instance.addObserver(this);
    final state=WidgetsBinding.instance.lifecycleState;
    if(state==null || state==AppLifecycleState.resumed)widget.controller.resume();
  }
  @override void didUpdateWidget(covariant SyncLifecycle oldWidget){
    super.didUpdateWidget(oldWidget);
    if(oldWidget.controller!=widget.controller){oldWidget.controller.pause();
      if(WidgetsBinding.instance.lifecycleState==null || WidgetsBinding.instance.lifecycleState==AppLifecycleState.resumed)widget.controller.resume();}
  }
  @override void didChangeAppLifecycleState(AppLifecycleState state){
    if(state==AppLifecycleState.resumed)widget.controller.resume();else widget.controller.pause();
  }
  @override void dispose(){WidgetsBinding.instance.removeObserver(this);widget.controller.pause();super.dispose();}
  @override Widget build(BuildContext context)=>widget.child;
}
