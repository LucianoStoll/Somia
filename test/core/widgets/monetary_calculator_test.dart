import 'package:finapp/core/theme/app_theme.dart';
import 'package:finapp/core/widgets/monetary_calculator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<TextEditingController> open(
  WidgetTester tester, {
  TargetPlatform platform = TargetPlatform.android,
  Size size = const Size(390, 844),
  double scale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  final controller = TextEditingController(text: '123,45');
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark.copyWith(platform: platform),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(body: MonetaryCalculatorField(controller: controller)),
    ),
  );
  await tester.tap(find.byType(TextFormField));
  await tester.pumpAndSettle();
  return controller;
}

Future<void> press(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey('calculator-key-$key'));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('abre com atual e confirma cálculo sem teclado nativo', (
    tester,
  ) async {
    final controller = await open(tester);
    expect(find.text('123,45'), findsNWidgets(2));
    expect(tester.testTextInput.isVisible, false);
    await press(tester, '+');
    await press(tester, '1');
    await tester.tap(find.text('Confirmar valor'));
    await tester.pumpAndSettle();
    expect(controller.text, '124,45');
    expect(find.text('Calculadora'), findsNothing);
    await tester.tap(find.byType(TextFormField));
    await tester.pumpAndSettle();
    expect(find.text('124,45'), findsNWidgets(2));
  });
  testWidgets('cancelar e voltar preservam o valor', (tester) async {
    final controller = await open(tester);
    await press(tester, '9');
    await tester.tap(find.byTooltip('Cancelar'));
    await tester.pumpAndSettle();
    expect(controller.text, '123,45');
    await tester.tap(find.byType(TextFormField));
    await tester.pumpAndSettle();
    await press(tester, '8');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(controller.text, '123,45');
    expect(find.text('Calculadora'), findsNothing);
  });
  testWidgets(
    'divisão por zero, zero e negativo não podem confirmar lançamento',
    (tester) async {
      final controller = await open(tester);
      await press(tester, '1');
      await press(tester, '÷');
      await press(tester, '0');
      await tester.tap(find.text('Confirmar valor'));
      await tester.pumpAndSettle();
      expect(find.text('Não é possível dividir por zero.'), findsOneWidget);
      expect(controller.text, '123,45');
      await press(tester, 'C');
      await tester.tap(find.text('Confirmar valor'));
      await tester.pumpAndSettle();
      expect(find.text('O valor deve ser maior que zero.'), findsOneWidget);
      await press(tester, '−');
      await press(tester, '1');
      await tester.tap(find.text('Confirmar valor'));
      await tester.pumpAndSettle();
      expect(controller.text, '123,45');
    },
  );
  testWidgets('Windows: teclado físico, Enter e Escape', (tester) async {
    final controller = await open(
      tester,
      platform: TargetPlatform.windows,
      size: const Size(1280, 900),
    );
    expect(find.byType(Dialog), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2, character: '2');
    await tester.sendKeyEvent(LogicalKeyboardKey.comma, character: ',');
    await tester.sendKeyEvent(LogicalKeyboardKey.digit5, character: '5');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(controller.text, '2,50');
    await tester.tap(find.byType(TextFormField));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.digit7, character: '7');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(controller.text, '2,50');
  });
  for (final size in [const Size(320, 640), const Size(780, 360)]) {
    testWidgets('$size, texto ampliado e conteúdo rolável', (tester) async {
      await open(tester, size: size, scale: 2);
      await press(tester, '1');
      await tester.ensureVisible(find.text('Confirmar valor'));
      await tester.tap(find.text('Confirmar valor'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
