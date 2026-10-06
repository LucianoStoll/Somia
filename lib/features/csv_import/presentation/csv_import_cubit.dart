import 'package:flutter_bloc/flutter_bloc.dart';
import '../domain/csv_document.dart';
import '../domain/csv_import.dart';

class CsvImportState {
  const CsvImportState(
      {this.references,
      this.rows = const [],
      this.busy = false,
      this.previewed = false,
      this.error,
      this.result});
  final CsvReferences? references;
  final List<CsvPreviewRow> rows;
  final bool busy, previewed;
  final String? error;
  final CsvImportResult? result;
  int get selected => rows.where((r) => r.selected).length;
}

class CsvImportCubit extends Cubit<CsvImportState> {
  CsvImportCubit(this.repository) : super(const CsvImportState());
  final CsvImportRepository repository;
  Future<void> load() async {
    emit(const CsvImportState(busy: true));
    try {
      final refs = await repository.references();
      if (!isClosed) emit(CsvImportState(references: refs));
    } catch (_) {
      if (!isClosed) {
        emit(const CsvImportState(
            error:
                'Não foi possível carregar contas e categorias. Tente novamente.'));
      }
    }
  }

  void reset() {
    if (!state.busy) emit(CsvImportState(references: state.references));
  }

  Future<void> preview(
      CsvDocument document, CsvMapping mapping, String accountId) async {
    if (state.busy) return;
    emit(CsvImportState(references: state.references, busy: true));
    try {
      final rows = await repository.preview(document, mapping, accountId);
      if (!isClosed) {
        emit(CsvImportState(
            references: state.references, rows: rows, previewed: true));
      }
    } catch (e) {
      if (!isClosed) {
        emit(CsvImportState(
            references: state.references,
            error: e is FormatException
                ? e.message
                : 'Não foi possível gerar a prévia. Tente novamente.'));
      }
    }
  }

  void select(int index, bool value) {
    if (state.busy) return;
    final rows = [...state.rows];
    rows[index] = rows[index].select(value);
    emit(CsvImportState(
        references: state.references, rows: rows, previewed: true));
  }

  void category(int index, String? value) {
    if (state.busy) return;
    final rows = [...state.rows];
    rows[index] = rows[index].category(value);
    emit(CsvImportState(
        references: state.references, rows: rows, previewed: true));
  }

  void selectNew(bool selected) {
    if (state.busy) return;
    emit(CsvImportState(
        references: state.references,
        previewed: true,
        rows: state.rows
            .map((r) => r.select(selected && !r.duplicate))
            .toList()));
  }

  Future<void> commit(String accountId) async {
    if (state.busy || state.selected == 0) return;
    final rows = state.rows;
    emit(CsvImportState(
        references: state.references, rows: rows, previewed: true, busy: true));
    try {
      final result = await repository.commit(rows, accountId);
      if (!isClosed) {
        emit(CsvImportState(
            references: state.references,
            rows: rows,
            previewed: true,
            result: result));
      }
    } catch (e) {
      if (!isClosed) {
        emit(CsvImportState(
            references: state.references,
            rows: rows,
            previewed: true,
            error: e is FormatException
                ? e.message
                : 'Não foi possível importar. Nenhum lançamento foi gravado. Confira conta e categorias e tente novamente.'));
      }
    }
  }
}
