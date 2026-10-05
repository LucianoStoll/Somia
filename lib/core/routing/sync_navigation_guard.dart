import 'package:flutter/widgets.dart';

/// Declarative section pages may refresh; imperative forms and popups wait.
class SyncNavigationGuard {
  final List<_SyncObserver> _observers = [];
  bool get safe =>
      _observers.isNotEmpty &&
      _observers.every((o) => o.routes
          .every((r) => r.settings is Page && !r.willHandlePopInternally));
  void reset() => _observers.clear();
  NavigatorObserver observer() {
    final value = _SyncObserver();
    _observers.add(value);
    return value;
  }
}

class _SyncObserver extends NavigatorObserver {
  final List<Route<dynamic>> routes = [];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routes.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routes.remove(route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routes.remove(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    routes.remove(oldRoute);
    if (newRoute != null) routes.add(newRoute);
  }
}

final syncNavigation = SyncNavigationGuard();
