import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finapp/core/allocations/allocation_editor.dart';
import 'package:finapp/core/allocations/category_allocation.dart';
import 'package:finapp/features/categories/domain/category.dart';

void main() {
  const categories = [
    FinanceCategory(
        id: 'a',
        name: 'Mercado',
        type: CategoryType.expense,
        parentId: null,
        isArchived: false,
        iconKey: null,
        colorArgb: null),
    FinanceCategory(
        id: 'b',
        name: 'Casa',
        type: CategoryType.expense,
        parentId: null,
        isArchived: false,
        iconKey: null,
        colorArgb: null)
  ];
  testWidgets(
      'percentual conserva total, rejeita diferença e preserva estado em total alterado',
      (tester) async {
    final form = GlobalKey<FormState>();
    var total = 10001;
    late StateSetter change;
    List<CategoryAllocation> result = [];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: StatefulBuilder(builder: (context, setState) {
      change = setState;
      return SingleChildScrollView(
          child: Form(
              key: form,
              child: AllocationEditor(
                  categories: categories,
                  type: 'expense',
                  total: total,
                  initial: const [
                    CategoryAllocation('a', 6001),
                    CategoryAllocation('b', 4000)
                  ],
                  onChanged: (v) => result = v)));
    }))));
    expect(form.currentState!.validate(), isTrue);
    await tester.tap(find.text('Por percentual'));
    await tester.pumpAndSettle();
    expect(result.fold(0, (s, p) => s + p.amountMinor), 10001);
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.first, '50');
    await tester.pump();
    expect(form.currentState!.validate(), isFalse);
    await tester.enterText(fields.at(1), '50');
    await tester.pump();
    expect(form.currentState!.validate(), isTrue);
    expect(result.map((p) => p.amountMinor), [5001, 5000]);
    change(() => total = 20001);
    await tester.pump();
    expect(result.map((p) => p.amountMinor), [10001, 10000]);
    expect(tester.takeException(), isNull);
  });
}
