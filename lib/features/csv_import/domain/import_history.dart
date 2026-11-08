class ImportBatch {
  const ImportBatch(this.id, this.sourceName, this.createdAt, this.accountId);
  final String id, sourceName, accountId;
  final DateTime createdAt;
}

class ImportUndoEntry {
  const ImportUndoEntry(this.id, this.line, this.action, this.description,
      this.canUndo, this.reason);
  final String id, action, description;
  final int line;
  final bool canUndo;
  final String? reason;
}

abstract interface class CsvImportHistory {
  Future<List<ImportBatch>> batches();
  Future<List<ImportUndoEntry>> inspectUndo(String batchId);
  Future<int> undo(String batchId, Set<String> entryIds);
}
