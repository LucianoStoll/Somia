import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finapp/core/theme/app_theme.dart';
import 'package:finapp/core/widgets/module_surface.dart';

void main() {
  for (final pair in [(320.0, 2.0), (780.0, 1.5), (1280.0, 1.0)]) {
    testWidgets('identidade dos módulos, valores e detalhes em $pair',
        (tester) async {
      tester.view.physicalSize = Size(pair.$1, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
          theme: AppTheme.dark,
          home: MediaQuery(
            data: MediaQueryData(
                size: Size(pair.$1, 900),
                textScaler: TextScaler.linear(pair.$2)),
            child: const ModuleSurface(
                child: Scaffold(
                    body: SingleChildScrollView(
                        padding: EdgeInsets.all(16),
                        child: ModuleHero(
                          label: 'Patrimônio líquido cadastrado',
                          value: 'R\$ 123.456,78',
                          icon: Icons.home_work_outlined,
                          children: [
                            ModuleValueRow(
                                label:
                                    'Financiamentos e outras dívidas vinculadas',
                                value: 'R\$ -100.000,00'),
                            ModuleDetails(
                                title: 'Dados do bem',
                                children: [Text('Contrato preservado')])
                          ],
                        )))),
          )));
      await tester.pumpAndSettle();
      expect(find.text('R\$ 123.456,78'), findsOneWidget);
      expect(find.text('Contrato preservado'), findsNothing);
      await tester.ensureVisible(find.text('Dados do bem'));
      await tester.tap(find.text('Dados do bem'));
      await tester.pumpAndSettle();
      expect(find.text('Contrato preservado'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final theme = Theme.of(tester.element(find.byType(ModuleHero)));
      expect(theme.scaffoldBackgroundColor, SomiaColors.background);
      expect(theme.cardTheme.color, SomiaColors.surface);
    });
  }
}
