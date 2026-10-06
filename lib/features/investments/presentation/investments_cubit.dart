import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/investment.dart';

class InvestmentsState {
  const InvestmentsState({this.overview, this.loading = false, this.error});
  final InvestmentOverview? overview;
  final bool loading;
  final String? error;
}

class InvestmentsCubit extends Cubit<InvestmentsState> {
  InvestmentsCubit(this.repository) : super(const InvestmentsState()) {
    load();
  }
  final InvestmentsRepository repository;
  int _request = 0;
  Future<void> load() async {
    final request = ++_request;
    emit(InvestmentsState(overview: state.overview, loading: true));
    try {
      final overview = await repository.load();
      if (!isClosed && request == _request)
        emit(InvestmentsState(overview: overview));
    } catch (_) {
      if (!isClosed && request == _request)
        emit(
          InvestmentsState(
            overview: state.overview,
            error: 'Não foi possível carregar as aplicações.',
          ),
        );
    }
  }
}
