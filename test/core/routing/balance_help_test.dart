import 'package:finapp/core/app_version.dart';
import 'package:finapp/core/widgets/balance_help_button.dart';
import 'package:finapp/features/settings/presentation/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ajustes mostram versão e abrem a explicação dos saldos',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    await tester.scrollUntilVisible(find.text(AppVersion.label), 250);
    expect(find.text(AppVersion.label), findsOneWidget);
    await tester.ensureVisible(find.text('Entender os saldos'));
    await tester.tap(find.text('Entender os saldos'));
    await tester.pumpAndSettle();
    expect(find.text('Como os saldos são calculados'), findsOneWidget);
    expect(find.text('Saldo efetivado'), findsOneWidget);
    await tester.tap(find.text('Entendi'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ajuda permite ler até o fim com texto ampliado no celular',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
      home: const Scaffold(body: BalanceHelpButton()),
    ));
    await tester.tap(find.byTooltip('Entender os saldos'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Contas e transferências'), 400);
    expect(find.text('Contas e transferências').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Entendi'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
}
