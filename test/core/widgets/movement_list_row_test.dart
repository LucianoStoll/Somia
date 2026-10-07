import 'dart:io';
import 'package:flutter/services.dart';
import 'package:finapp/core/theme/app_theme.dart';
import 'package:finapp/core/widgets/movement_list_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget row(
        {VoidCallback? edit,
        VoidCallback? status,
        VoidCallback? amount,
        bool effective = false,
        bool busy = false}) =>
    MovementListRow(
        id: 'a',
        description: 'Financiamento carro com descrição muito longa',
        account: 'Sicredi',
        amount: 'R\$ 999999999,99',
        dueDate: DateTime(2026, 10, 1),
        effectiveDate: effective ? DateTime(2026, 10, 1) : null,
        effective: effective,
        busy: busy,
        color: SomiaColors.red,
        categoryTags: const [
          MovementTag('Investimentos e patrimônio', Color(0xFF79D9B6)),
          MovementTag('Financiamento', Color(0xFFB9A8EB))
        ],
        onEdit: edit ?? () {},
        onEffective: status ?? () {},
        onAmount: amount,
        menu: PopupMenuButton<String>(
            key: const ValueKey('menu'),
            itemBuilder: (_) =>
                [const PopupMenuItem(value: 'edit', child: Text('Editar'))]));

Widget invoiceRow() => MovementListRow(
    id: 'invoice:mp',
    description: 'Cartão - mp',
    account: 'MercadoPago',
    amount: '-R\$ 242,00',
    dueDate: DateTime(2026, 11, 5),
    effectiveDate: null,
    effective: false,
    color: SomiaColors.red,
    pendingIcon: Icons.schedule,
    highlightLabel: 'Fecha dia 25/out.',
    effectiveLabel: 'Pagar fatura hoje',
    onEdit: () {},
    onEffective: () {},
    menu: PopupMenuButton<String>(
        itemBuilder: (_) =>
            [const PopupMenuItem(value: 'open', child: Text('Ver fatura'))]));

Future<void> open(
    WidgetTester tester, Widget child, Size size, double scale) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!),
      home: Scaffold(
          body: RepaintBoundary(
              key: const ValueKey('preview'),
              child: ListView(children: [child])))));
}

void main() {
  testWidgets('status, descrição, valor e menu têm toques independentes',
      (tester) async {
    var edits = 0, statuses = 0, values = 0;
    await open(
        tester,
        row(
            edit: () => edits++,
            status: () => statuses++,
            amount: () => values++),
        const Size(390, 844),
        1);
    await tester.tap(find.byKey(const ValueKey('movement-status-a')));
    expect(statuses, 1);
    expect(edits, 0);
    expect(values, 0);
    await tester.tap(find.byKey(const ValueKey('movement-edit-a')));
    expect(edits, 1);
    await tester.tap(find.byKey(const ValueKey('movement-amount-a')));
    expect(values, 1);
    expect(edits, 1);
    await tester.tap(find.byKey(const ValueKey('menu')));
    await tester.pumpAndSettle();
    expect(find.text('Editar'), findsOneWidget);
    expect(edits, 1);
    expect(statuses, 1);
  });
  testWidgets('etiquetas preservam cores e linha curta é compacta',
      (tester) async {
    await open(
        tester,
        MovementListRow(
            id: 'compact',
            description: 'Salário',
            account: 'Banco',
            amount: 'R\$ 1.314,56',
            dueDate: DateTime(2026, 10, 6),
            effectiveDate: null,
            effective: true,
            color: SomiaColors.green,
            categoryTags: const [
              MovementTag('Renda', Color(0xFF79D9B6)),
              MovementTag('Salário', Color(0xFFB9A8EB))
            ],
            onEdit: () {},
            onEffective: () {},
            menu: const SizedBox(width: 48, height: 48)),
        const Size(390, 844),
        1);
    expect(tester.getSize(find.byType(MovementListRow)).height,
        lessThanOrEqualTo(100));
    expect(tester.widget<Text>(find.text('Renda')).style!.color,
        const Color(0xFF79D9B6));
    expect(tester.widget<Text>(find.text('Salário').last).style!.color,
        const Color(0xFFB9A8EB));
    expect(tester.takeException(), isNull);
  });
  testWidgets('efetivado e ocupado não efetivam novamente', (tester) async {
    var calls = 0;
    for (final widget in [
      row(effective: true, status: () => calls++),
      row(busy: true, status: () => calls++)
    ]) {
      await open(tester, widget, const Size(390, 844), 1);
      await tester.tap(find.byKey(const ValueKey('movement-status-a')));
      expect(calls, 0);
    }
  });
  for (final size in [
    const Size(320, 640),
    const Size(390, 844),
    const Size(780, 360),
    const Size(1280, 900)
  ]) {
    testWidgets('layout $size, descrição longa, valor grande e texto ampliado',
        (tester) async {
      await open(tester, row(), size, 2);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
  if (const bool.fromEnvironment('SOMIA_RENDER_PREVIEW')) {
    testWidgets('renderiza lista mobile', (tester) async {
      final fonts = Directory(
          '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts');
      final font = FontLoader('Roboto');
      final icons = FontLoader('MaterialIcons');
      for (final file in fonts.listSync().whereType<File>()) {
        if (file.path.endsWith('Roboto-Regular.ttf') ||
            file.path.endsWith('Roboto-Bold.ttf')) {
          font.addFont(
              Future.value(ByteData.sublistView(file.readAsBytesSync())));
        }
        if (file.path.endsWith('MaterialIcons-Regular.otf')) {
          icons.addFont(
              Future.value(ByteData.sublistView(file.readAsBytesSync())));
        }
      }
      await font.load();
      await icons.load();
      await open(
          tester,
          Column(children: [invoiceRow(), row(), row(effective: true)]),
          const Size(390, 844),
          1);
      await expectLater(find.byKey(const ValueKey('preview')),
          matchesGoldenFile('movement-list-mobile-preview.png'));
    });
  }
}
