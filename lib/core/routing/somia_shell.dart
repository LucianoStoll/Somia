import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';
import '../di/injection.dart';
import '../database/backup_manager.dart';
import '../widgets/somia_brand.dart';
import 'app_router.dart';

final _mobileScaffoldKey = GlobalKey<ScaffoldState>();

bool somiaUsesMobileNavigation(BuildContext context) =>
    context.dependOnInheritedWidgetOfExactType<_MobileNavigationScope>() !=
    null;

class _MobileNavigationScope extends InheritedWidget {
  const _MobileNavigationScope({required super.child});

  @override
  bool updateShouldNotify(_MobileNavigationScope oldWidget) => false;
}

class _MenuDestination {
  const _MenuDestination(this.label, this.path, this.icon,
      [this.color = SomiaColors.muted]);
  final String label;
  final String path;
  final IconData icon;
  final Color color;
}

abstract final class MovementIdentity {
  static const incomeIcon = Icons.arrow_circle_up_outlined;
  static const expenseIcon = Icons.arrow_circle_down_outlined;
  static const transferIcon = Icons.swap_horiz;
  static const incomeColor = SomiaColors.green;
  static const expenseColor = SomiaColors.red;
  static const transferColor = SomiaColors.muted;
}

const _menu = <_MenuDestination>[
  _MenuDestination(
      'Resumo', AppRoutes.dashboardPath, Icons.home_outlined, SomiaColors.blue),
  _MenuDestination('Receitas', AppRoutes.incomePath,
      MovementIdentity.incomeIcon, MovementIdentity.incomeColor),
  _MenuDestination('Despesas', AppRoutes.expensesPath,
      MovementIdentity.expenseIcon, MovementIdentity.expenseColor),
  _MenuDestination('Transferências', AppRoutes.transfersPath,
      MovementIdentity.transferIcon, MovementIdentity.transferColor),
  _MenuDestination(
      'Contas', AppRoutes.accountsPath, Icons.account_balance_wallet_outlined),
  _MenuDestination('Cartões', AppRoutes.cardsPath, Icons.credit_card_outlined),
  _MenuDestination('Débito', AppRoutes.debitCardsPath, Icons.payment_outlined),
  _MenuDestination('Cashback', AppRoutes.cashbackPath, Icons.paid_outlined),
  _MenuDestination('Pessoas e reembolsos', AppRoutes.reimbursementsPath,
      Icons.people_outline),
  _MenuDestination('Planejamento', AppRoutes.planningPath, Icons.flag_outlined),
  _MenuDestination(
      'Análises', AppRoutes.analysisPath, Icons.bar_chart_outlined),
  _MenuDestination(
      'Investimentos', AppRoutes.investmentsPath, Icons.savings_outlined),
  _MenuDestination(
      'Bens e patrimônio', AppRoutes.assetsPath, Icons.home_work_outlined),
  _MenuDestination('Dívidas e empréstimos', AppRoutes.debtsPath,
      Icons.account_balance_outlined),
  _MenuDestination('Categorias', AppRoutes.categoriesPath, Icons.sell_outlined),
  _MenuDestination('Lixeira', AppRoutes.trashPath, Icons.delete_outline),
  _MenuDestination(
      'Configurações', AppRoutes.settingsPath, Icons.settings_outlined),
];

/// O drawer pertence ao Scaffold externo; este botão o abre a partir das páginas.
Widget? somiaMenuLeading(BuildContext context) =>
    MediaQuery.sizeOf(context).width < 800 ? const SomiaMenuButton() : null;

class SomiaMenuButton extends StatelessWidget {
  const SomiaMenuButton({super.key});
  @override
  Widget build(BuildContext context) => IconButton(
      tooltip: 'Abrir menu',
      icon: const Icon(Icons.menu),
      onPressed: () => _mobileScaffoldKey.currentState?.openDrawer());
}

/// Na rota da seção, sobreposições continuam recebendo Voltar antes dela.
class SomiaSectionBackScope extends StatelessWidget {
  const SomiaSectionBackScope(
      {super.key, required this.location, required this.child});
  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final manager =
        getIt.isRegistered<BackupManager>() ? getIt<BackupManager>() : null;
    Widget scope() => PopScope<Object?>(
          canPop: !(manager?.restoring ?? false) &&
              (Theme.of(context).platform != TargetPlatform.android ||
                  location == AppRoutes.dashboardPath),
          onPopInvokedWithResult: (didPop, result) {
            if ((manager?.restoring ?? false) ||
                didPop ||
                Theme.of(context).platform != TargetPlatform.android) {
              return;
            }
            final scaffold = _mobileScaffoldKey.currentState;
            if (scaffold?.isDrawerOpen ?? false) {
              scaffold!.closeDrawer();
            } else if (location != AppRoutes.dashboardPath) {
              context.go(location == AppRoutes.settingsPath &&
                      GoRouterState.of(context)
                              .uri
                              .queryParameters['section'] !=
                          null
                  ? AppRoutes.settingsPath
                  : location == AppRoutes.cardsPath &&
                          GoRouterState.of(context)
                                  .uri
                                  .queryParameters['card'] !=
                              null
                      ? AppRoutes.cardsPath
                      : location.startsWith('${AppRoutes.accountsPath}/')
                          ? AppRoutes.accountsPath
                          : AppRoutes.dashboardPath);
            }
          },
          child: child,
        );
    return manager == null
        ? scope()
        : AnimatedBuilder(animation: manager, builder: (context, _) => scope());
  }
}

class SomiaShell extends StatelessWidget {
  const SomiaShell({super.key, required this.location, required this.child});
  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        if (constraints.maxWidth >= 800) {
          return Scaffold(
              body: Row(children: [
            SizedBox(
                width: constraints.maxWidth < 1060
                    ? 104 + MediaQuery.paddingOf(context).left
                    : 228 + MediaQuery.paddingOf(context).left,
                child: _SomiaMenu(
                    location: location, compact: constraints.maxWidth < 1060)),
            const VerticalDivider(width: 1),
            Expanded(child: child),
          ]));
        }
        final mobileNavigation =
            Theme.of(context).platform == TargetPlatform.android;
        return Scaffold(
            key: _mobileScaffoldKey,
            drawer: Drawer(
                width: constraints.maxWidth,
                child: _SomiaMenu(location: location, isDrawer: true)),
            body:
                mobileNavigation ? _MobileNavigationScope(child: child) : child,
            bottomNavigationBar:
                !mobileNavigation || MediaQuery.viewInsetsOf(context).bottom > 0
                    ? null
                    : _SomiaMobileNavigation(location: location));
      });
}

class _SomiaMobileNavigation extends StatelessWidget {
  const _SomiaMobileNavigation({required this.location});
  final String location;

  @override
  Widget build(BuildContext context) {
    final movements = {
      AppRoutes.transactionsPath,
      AppRoutes.incomePath,
      AppRoutes.expensesPath,
      AppRoutes.transfersPath,
    }.contains(location);
    final planning = location == AppRoutes.planningPath;
    final more = location != AppRoutes.dashboardPath && !movements && !planning;

    Widget destination(
        String label, IconData icon, bool selected, VoidCallback onTap) {
      final color = selected ? SomiaColors.blue : SomiaColors.muted;
      return Expanded(
          child: InkWell(
              key: ValueKey('bottom-$label'),
              onTap: onTap,
              child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(icon, color: color, size: 25),
                    const SizedBox(height: 4),
                    Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: color,
                            fontSize: 11,
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w400)),
                    const SizedBox(height: 3),
                    Container(
                        width: 28,
                        height: 3,
                        decoration: BoxDecoration(
                            color: selected
                                ? SomiaColors.blue
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(3))),
                  ]))));
    }

    return Material(
        color: SomiaColors.sidebar,
        child: SafeArea(
            top: false,
            child: Container(
                decoration: const BoxDecoration(
                    border:
                        Border(top: BorderSide(color: SomiaColors.outline))),
                child: Row(children: [
                  destination(
                      'Resumo',
                      Icons.home_outlined,
                      location == AppRoutes.dashboardPath,
                      () => context.go(AppRoutes.dashboardPath)),
                  destination('Movimentos', Icons.receipt_long_outlined,
                      movements, () => context.go(AppRoutes.transactionsPath)),
                  const Expanded(
                      child:
                          Center(heightFactor: 1, child: SomiaQuickActions())),
                  destination('Planejamento', Icons.bar_chart_outlined,
                      planning, () => context.go(AppRoutes.planningPath)),
                  destination('Mais', Icons.more_horiz, more,
                      () => _mobileScaffoldKey.currentState?.openDrawer()),
                ]))));
  }
}

class _SomiaMenu extends StatelessWidget {
  const _SomiaMenu(
      {required this.location, this.isDrawer = false, this.compact = false});
  final String location;
  final bool isDrawer;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (isDrawer) return _buildDrawer(context);
    return Material(
        color: SomiaColors.sidebar,
        child: SafeArea(
            right: false,
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                  compact ? 10 : 14, 18, compact ? 10 : 14, 16),
              children: [
                Padding(
                    padding: EdgeInsets.fromLTRB(compact ? 8 : 14, 20, 8, 32),
                    child: Row(
                        mainAxisAlignment: compact
                            ? MainAxisAlignment.center
                            : MainAxisAlignment.start,
                        children: [
                          if (compact)
                            const SomiaBrand(symbolOnly: true, height: 32)
                          else
                            const Expanded(
                                child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: SomiaBrand(height: 42))),
                          if (isDrawer)
                            IconButton(
                                tooltip: 'Fechar menu',
                                icon: const Icon(Icons.close),
                                onPressed: () => Navigator.of(context).pop()),
                        ])),
                for (final destination in _menu) ...[
                  if (const {'/', '/planning', '/investments', '/categories'}
                      .contains(destination.path))
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 16, 8, 8),
                      child: Text(
                          switch (destination.path) {
                            '/planning' => 'PLANEJAMENTO',
                            '/investments' => 'PATRIMÔNIO',
                            '/categories' => 'ORGANIZAÇÃO',
                            _ => 'DIA A DIA',
                          },
                          style: const TextStyle(
                              fontSize: 11, color: SomiaColors.muted)),
                    ),
                  Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: ListTile(
                        key: ValueKey('menu-${destination.path}'),
                        leading:
                            Icon(destination.icon, color: destination.color),
                        title: compact ? null : Text(destination.label),
                        minLeadingWidth: 0,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: compact ? 18 : 14),
                        selected: location == destination.path ||
                            (destination.path == AppRoutes.accountsPath &&
                                location
                                    .startsWith('${AppRoutes.accountsPath}/')),
                        selectedTileColor: SomiaColors.surfaceHigh,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        onTap: () {
                          final router = GoRouter.of(context);
                          if (isDrawer) Navigator.of(context).pop();
                          if (location != destination.path) {
                            router.go(destination.path);
                          }
                        },
                      )),
                ],
              ],
            )));
  }

  Widget _buildDrawer(BuildContext context) {
    final groups = <(String, List<_MenuDestination>)>[
      ('Movimentos', _menu.sublist(1, 4)),
      ('Contas e cartões', _menu.sublist(4, 8)),
      ('Planejamento', _menu.sublist(8, 11)),
      ('Patrimônio', _menu.sublist(11, 14)),
      ('Organização', _menu.sublist(14)),
    ];
    return Material(
        color: SomiaColors.sidebar,
        child: SafeArea(
            right: false,
            child: Column(children: [
              Padding(
                  padding: const EdgeInsets.fromLTRB(24, 22, 16, 12),
                  child: Row(children: [
                    const Expanded(
                        child: Align(
                            alignment: Alignment.centerLeft,
                            child: SomiaBrand(height: 36))),
                    IconButton(
                        tooltip: 'Fechar menu',
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop()),
                  ])),
              Expanded(
                  child: ListView(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                      children: [
                    const Padding(
                        padding: EdgeInsets.fromLTRB(16, 8, 8, 8),
                        child: Text('NAVEGAÇÃO',
                            style: TextStyle(
                                fontSize: 11, color: SomiaColors.muted))),
                    _drawerDestination(context, _menu.first),
                    const SizedBox(height: 12),
                    for (final (title, destinations) in groups)
                      ExpansionTile(
                          key: ValueKey('drawer-group-$title'),
                          title: Text(title,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          tilePadding:
                              const EdgeInsets.symmetric(horizontal: 16),
                          childrenPadding: const EdgeInsets.only(bottom: 6),
                          initiallyExpanded: destinations
                              .any((destination) => _isSelected(destination)),
                          shape: const Border(),
                          collapsedShape: const Border(),
                          children: [
                            for (final destination in destinations)
                              _drawerDestination(context, destination),
                          ]),
                  ])),
            ])));
  }

  bool _isSelected(_MenuDestination destination) =>
      location == destination.path ||
      (destination.path == AppRoutes.accountsPath &&
          location.startsWith('${AppRoutes.accountsPath}/'));

  Widget _drawerDestination(
      BuildContext context, _MenuDestination destination) {
    return Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: ListTile(
            key: ValueKey('menu-${destination.path}'),
            dense: true,
            minLeadingWidth: 0,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            leading: Icon(destination.icon, color: destination.color),
            title: Text(destination.label),
            selected: _isSelected(destination),
            selectedTileColor: SomiaColors.surfaceHigh,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onTap: () {
              final router = GoRouter.of(context);
              Navigator.of(context).pop();
              if (location != destination.path) router.go(destination.path);
            }));
  }
}

class SomiaQuickActions extends StatelessWidget {
  const SomiaQuickActions({super.key});

  String _pathFor(String action) => '${switch (action) {
        'income' => AppRoutes.incomePath,
        'expense' => AppRoutes.expensesPath,
        _ => AppRoutes.transfersPath,
      }}?create=1';

  Future<void> _openMobileActions(BuildContext context) async {
    final action = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
            top: false,
            child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: Text('Adicionar movimento',
                              style: TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.w700)))),
                  for (final (action, label, description, icon, color) in [
                    (
                      'income',
                      'Receita',
                      'Dinheiro que entrou',
                      MovementIdentity.incomeIcon,
                      MovementIdentity.incomeColor
                    ),
                    (
                      'expense',
                      'Despesa',
                      'Pagamento ou compra',
                      MovementIdentity.expenseIcon,
                      MovementIdentity.expenseColor
                    ),
                    (
                      'transfer',
                      'Transferência',
                      'Entre suas contas',
                      MovementIdentity.transferIcon,
                      MovementIdentity.transferColor
                    ),
                  ])
                    Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                            key: ValueKey('quick-$action'),
                            leading: Icon(icon, color: color, size: 30),
                            title: Text(label),
                            subtitle: Text(description),
                            trailing: const Icon(Icons.chevron_right),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                            tileColor: SomiaColors.surfaceHigh,
                            onTap: () =>
                                Navigator.of(sheetContext).pop(action))),
                ]))));
    if (action != null && context.mounted) context.go(_pathFor(action));
  }

  @override
  Widget build(BuildContext context) {
    if (Theme.of(context).platform == TargetPlatform.android &&
        MediaQuery.sizeOf(context).width < 800) {
      return IconButton(
          tooltip: 'Adicionar lançamento ou transferência',
          icon: const Icon(Icons.add, size: 30),
          color: Theme.of(context).colorScheme.onPrimary,
          style: IconButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              minimumSize: const Size(56, 56)),
          onPressed: () => _openMobileActions(context));
    }
    return PopupMenuButton<String>(
      tooltip: 'Adicionar lançamento ou transferência',
      icon: const Icon(Icons.add),
      iconColor: Theme.of(context).colorScheme.onPrimary,
      style: IconButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.primary,
          minimumSize: const Size(56, 56)),
      onSelected: (action) => context.go(_pathFor(action)),
      itemBuilder: (_) => const [
        PopupMenuItem(
            value: 'income',
            child: ListTile(
                leading: Icon(MovementIdentity.incomeIcon,
                    color: MovementIdentity.incomeColor),
                title: Text('Receita'))),
        PopupMenuItem(
            value: 'expense',
            child: ListTile(
                leading: Icon(MovementIdentity.expenseIcon,
                    color: MovementIdentity.expenseColor),
                title: Text('Despesa'))),
        PopupMenuItem(
            value: 'transfer',
            child: ListTile(
                leading: Icon(MovementIdentity.transferIcon,
                    color: MovementIdentity.transferColor),
                title: Text('Transferência'))),
      ],
    );
  }
}
