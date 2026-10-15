import 'dart:io';

import 'package:finapp/features/csv_import/domain/csv_import.dart';
import 'package:finapp/features/csv_import/domain/csv_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('perfil reaplica colunas por cabeçalho após reordenação', () {
    final mapping = CsvMapping(
      description: 0,
      amount: 1,
      date: 2,
      due: 2,
      effective: 2,
      direction: CsvDirection.expense,
    );
    final profile = CsvProfile.capture('Banco', ';', [
      'Descrição',
      'Valor',
      'Data',
    ], mapping);
    final restored = CsvProfile.fromJson(profile.toJson());
    final applied = restored.apply(['Data', 'Descrição', 'Valor']);
    expect(
      [
        applied.description,
        applied.amount,
        applied.date,
        applied.due,
        applied.effective,
      ],
      [1, 2, 0, 0, 0],
    );
    expect(applied.direction, CsvDirection.expense);
    expect(
      () => restored.apply(['Data', 'Descrição', 'Outro']),
      throwsFormatException,
    );
  });

  test(
    'perfis locais substituem nome repetido e preservam arquivo inválido',
    () async {
      final dir = await Directory.systemTemp.createTemp('somia-profiles-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/profiles.json');
      final store = CsvProfileStore(file);
      final headers = ['Descrição', 'Valor', 'Data'];
      await store.save(
        CsvProfile.capture(
          'Banco',
          null,
          headers,
          CsvMapping(description: 0, amount: 1, date: 2),
        ),
      );
      await store.save(
        CsvProfile.capture(
          'banco',
          ';',
          headers,
          CsvMapping(description: 0, amount: 1, date: 2, effective: 2),
        ),
      );
      expect((await store.load()).single.delimiter, ';');
      await file.writeAsString('{invalid');
      await expectLater(store.load(), throwsFormatException);
      expect(await file.readAsString(), '{invalid');
    },
  );
}
