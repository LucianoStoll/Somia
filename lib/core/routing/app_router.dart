import '../../features/assets/presentation/assets_page.dart';
import '../../features/investments/presentation/investments_page.dart';
import '../../features/accounts/presentation/account_statement_page.dart';
import '../../features/cards/presentation/cards_page.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../../features/dashboard/presentation/pages/dashboard_page.dart';
import '../../features/accounts/presentation/accounts_page.dart';
import '../../features/categories/presentation/categories_page.dart';
import '../../features/transactions/presentation/transactions_page.dart';
import '../../features/transactions/domain/financial_transaction.dart';
import '../../features/transfers/presentation/transfers_page.dart';
import '../../features/settings/presentation/settings_page.dart';
import 'somia_shell.dart';
import 'sync_navigation_guard.dart';

abstract final class AppRoutes {
  static const dashboard = 'dashboard';
  static const dashboardPath = '/';
  static const investments = 'investments';
  static const investmentsPath = '/investments';
  static const assetsPath = '/investments/assets';
  static const cards = 'cards';
  static const cardsPath = '/cards';
  static const accounts = 'accounts';
  static const accountsPath = '/accounts';
  static const categories = 'categories';
  static const categoriesPath = '/categories';
  static const transactions = 'transactions';
  static const transactionsPath = '/transactions';
  static const income = 'income';
  static const incomePath = '/income';
  static const expenses = 'expenses';
  static const expensesPath = '/expenses';
  static const transfers = 'transfers';
  static const transfersPath = '/transfers';
  static const settings = 'settings';
  static const settingsPath = '/settings';
}

GoRouter appRouter = createAppRouter();

GoRouter createAppRouter({String initialLocation = AppRoutes.dashboardPath}) {
  syncNavigation.reset();
  return GoRouter(
    observers: [syncNavigation.observer()],
    initialLocation: initialLocation,
    routes: [
      ShellRoute(
          observers: [syncNavigation.observer()],
          builder: (context, state, child) => SomiaSectionBackScope(
              location: state.uri.path,
              child: SomiaShell(location: state.uri.path, child: child)),
          routes: [
            GoRoute(
                path: AppRoutes.assetsPath,
                builder: (context, state) => SomiaSectionBackScope(
                    location: state.uri.path, child: const AssetsPage())),
            GoRoute(
                path: AppRoutes.investmentsPath,
                name: AppRoutes.investments,
                builder: (context, state) => SomiaSectionBackScope(
                    location: state.uri.path, child: const InvestmentsPage())),
            GoRoute(
                path: AppRoutes.cardsPath,
                name: AppRoutes.cards,
                builder: (context, state) => SomiaSectionBackScope(
                    location: state.uri.path,
                    child: CardsPage(
                        key: ValueKey(state.uri.toString()),
                        cardId: state.uri.queryParameters['card'],
                        month: DateTime.tryParse(
                            state.uri.queryParameters['month'] ?? '')))),
            GoRoute(
              path: AppRoutes.transfersPath,
              name: AppRoutes.transfers,
              builder: (context, state) => SomiaSectionBackScope(
                  location: state.uri.path,
                  child: TransfersPage(
                      key: ValueKey(state.uri.queryParameters['create']),
                      startCreate: state.uri.queryParameters['create'] == '1')),
            ),
            GoRoute(
              path: AppRoutes.transactionsPath,
              name: AppRoutes.transactions,
              builder: (context, state) => SomiaSectionBackScope(
                  location: state.uri.path,
                  child: TransactionsPage(
                      key: ValueKey(state.uri.queryParameters['create']),
                      initialCreateType: state.uri.queryParameters['create'])),
            ),
            GoRoute(
              path: AppRoutes.incomePath,
              name: AppRoutes.income,
              builder: (context, state) => SomiaSectionBackScope(
                  location: state.uri.path,
                  child: TransactionsPage(
                      key: ValueKey(state.uri.toString()),
                      sectionType: TransactionType.income,
                      initialCreateType:
                          state.uri.queryParameters['create'] == '1'
                              ? 'income'
                              : null)),
            ),
            GoRoute(
              path: AppRoutes.expensesPath,
              name: AppRoutes.expenses,
              builder: (context, state) => SomiaSectionBackScope(
                  location: state.uri.path,
                  child: TransactionsPage(
                      key: ValueKey(state.uri.toString()),
                      sectionType: TransactionType.expense,
                      initialCreateType:
                          state.uri.queryParameters['create'] == '1'
                              ? 'expense'
                              : null)),
            ),
            GoRoute(
              path: AppRoutes.categoriesPath,
              name: AppRoutes.categories,
              builder: (context, state) => SomiaSectionBackScope(
                  location: state.uri.path, child: const CategoriesPage()),
            ),
            GoRoute(
              path: AppRoutes.accountsPath,
              name: AppRoutes.accounts,
              builder: (context, state) => SomiaSectionBackScope(
                  location: state.uri.path, child: const AccountsPage()),
              routes: [
                GoRoute(
                    path: ':accountId',
                    builder: (context, state) => AccountStatementPage(
                        key: ValueKey(state.pathParameters['accountId']),
                        accountId: state.pathParameters['accountId']!))
              ],
            ),
            GoRoute(
              path: AppRoutes.settingsPath,
              name: AppRoutes.settings,
              builder: (context, state) => SomiaSectionBackScope(
                  location: state.uri.path, child: const SettingsPage()),
            ),
            GoRoute(
              path: AppRoutes.dashboardPath,
              name: AppRoutes.dashboard,
              builder: (context, state) => SomiaSectionBackScope(
                  location: state.uri.path, child: const DashboardPage()),
            ),
          ]),
    ],
  );
}
