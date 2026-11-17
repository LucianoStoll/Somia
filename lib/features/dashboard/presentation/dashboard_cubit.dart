import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/dashboard_repository.dart';
import '../../../core/filters/reference_month.dart';
import '../domain/entities/dashboard_summary.dart';

class DashboardState {
  const DashboardState(
      {required this.month,
      this.summary,
      this.loading = false,
      this.error,
      this.analysisMode = DashboardAnalysisMode.projected});

  final DashboardAnalysisMode analysisMode;
  final DateTime month;
  final DashboardSummary? summary;
  final bool loading;
  final String? error;
}

class DashboardCubit extends Cubit<DashboardState> {
  DashboardCubit(this._repository, {ReferenceMonth? selection})
      : _selection = selection,
        super(DashboardState(
            month: selection?.value ??
                DateTime(DateTime.now().year, DateTime.now().month))) {
    _selection?.addListener(_monthChanged);
    load();
  }

  final DashboardRepository _repository;
  final ReferenceMonth? _selection;
  int _request = 0;
  void selectAnalysisMode(DashboardAnalysisMode mode) => emit(DashboardState(
      month: state.month,
      summary: state.summary,
      loading: state.loading,
      error: state.error,
      analysisMode: mode));
  void _monthChanged() => load(_selection!.value);
  @override
  Future<void> close() {
    _selection?.removeListener(_monthChanged);
    return super.close();
  }

  Future<void> load([DateTime? month]) async {
    final request = ++_request;
    final selected = month ?? state.month;
    final previousSummary =
        selected.year == state.month.year && selected.month == state.month.month
            ? state.summary
            : null;
    emit(DashboardState(
        month: selected,
        summary: previousSummary,
        loading: true,
        analysisMode: state.analysisMode));
    try {
      final summary = await _repository.load(selected);
      if (!isClosed && request == _request) {
        emit(DashboardState(
            month: selected,
            summary: summary,
            analysisMode: state.analysisMode));
      }
    } catch (_) {
      if (!isClosed && request == _request) {
        emit(DashboardState(
            month: selected,
            summary: previousSummary,
            analysisMode: state.analysisMode,
            error: 'Não foi possível carregar o resumo.'));
      }
    }
  }

  void moveMonth(int delta) =>
      load(DateTime(state.month.year, state.month.month + delta));
}
