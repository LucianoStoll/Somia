import 'dart:convert';
import 'dart:typed_data';

import '../../../core/app_version.dart';
import '../../../core/database/app_database.dart';

class ImportDiagnostics {
  static Future<Uint8List> export(AppDatabase db) async {
    final batches = await db.customSelect('''SELECT
      COUNT(*) AS total,
      COALESCE(SUM(CASE WHEN undone_at IS NULL THEN 1 ELSE 0 END),0) AS active
      FROM import_batches''').getSingle();
    final entries = await db.customSelect('''SELECT action,COUNT(*) AS total
      FROM import_batch_entries WHERE undone_at IS NULL GROUP BY action''').get();
    return Uint8List.fromList(
        utf8.encode(const JsonEncoder.withIndent('  ').convert({
      'appVersion': AppVersion.label,
      'schemaVersion': db.schemaVersion,
      'batchCount': batches.read<int>('total'),
      'activeBatchCount': batches.read<int>('active'),
      'activeEntryCounts': {
        for (final entry in entries)
          entry.read<String>('action'): entry.read<int>('total'),
      },
      'generatedAtUtc': DateTime.now().toUtc().toIso8601String(),
      'note': 'Sem descrições, valores, contas ou dados pessoais.',
    })));
  }
}
