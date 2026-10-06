import 'package:finapp/core/routing/sync_navigation_guard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets(
      'root, shell, formulários, diálogos e histórico local bloqueiam aplicação',
      (tester) async {
    final guard = SyncNavigationGuard();
    late BuildContext section;
    final router = GoRouter(observers: [
      guard.observer()
    ], routes: [
      ShellRoute(
          observers: [guard.observer()],
          builder: (c, s, child) => child,
          routes: [
            GoRoute(
                path: '/',
                builder: (c, s) {
                  section = c;
                  return const Scaffold(body: Text('Seção'));
                })
          ])
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(guard.safe, isTrue);
    final nav = Navigator.of(section);
    nav.push(MaterialPageRoute<void>(
        builder: (c) => const Scaffold(body: TextField())));
    await tester.pumpAndSettle();
    expect(guard.safe, isFalse);
    await tester.enterText(find.byType(TextField), 'Edição não salva');
    expect(find.text('Edição não salva'), findsOneWidget);
    nav.pop();
    await tester.pumpAndSettle();
    expect(guard.safe, isTrue);
    showDialog<void>(
        context: section,
        builder: (c) => const AlertDialog(content: Text('Diálogo')));
    await tester.pumpAndSettle();
    expect(guard.safe, isFalse);
    Navigator.of(section, rootNavigator: true).pop();
    await tester.pumpAndSettle();
    expect(guard.safe, isTrue);
    final entry = LocalHistoryEntry();
    ModalRoute.of(section)!.addLocalHistoryEntry(entry);
    expect(guard.safe, isFalse);
    entry.remove();
    expect(guard.safe, isTrue);
    guard.reset();
    expect(guard.safe, isFalse);
  });
}
