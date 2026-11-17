import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_theme.dart';
import '../di/injection.dart';
import '../database/backup_manager.dart';
import '../sync/sync_manager.dart';
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
  _MenuDestination(
    this.label,
    this.path,
    this.icon, {
    this.hint,
    this.also = const {},
  });
  final String label;
  final String path;
  final IconData icon;

  /// Descrição curta exibida no menu do celular.
  final String? hint;

  /// Outras rotas que mantêm este item selecionado.
  final Set<String> also;
}

abstract final class MovementIdentity {
  static const incomeIcon = Icons.arrow_circle_up_outlined;
  static const expenseIcon = Icons.arrow_circle_down_outlined;
  static const transferIcon = Icons.swap_horiz;
  // Getters: a cor acompanha o tema ativo (claro ou escuro).
  static Color get incomeColor => SomiaColors.green;
  static Color get expenseColor => SomiaColors.red;
  static Color get transferColor => SomiaColors.purple;
}

/// Destinos da barra inferior do Android; no Windows ficam no topo da
/// barra lateral.
final _primary = <_MenuDestination>[
  _MenuDestination('Resumo', AppRoutes.dashboardPath, Icons.home_outlined),
  _MenuDestination(
    'Movimentos',
    AppRoutes.transactionsPath,
    Icons.receipt_long_outlined,
    also: {
      AppRoutes.incomePath,
      AppRoutes.expensesPath,
      AppRoutes.transfersPath,
    },
  ),
  _MenuDestination(
    'Cartões',
    AppRoutes.cardsPath,
    Icons.credit_card_outlined,
    also: {AppRoutes.debitCardsPath, AppRoutes.cashbackPath},
  ),
  _MenuDestination(
      'Relatórios', AppRoutes.analysisPath, Icons.bar_chart_outlined),
];

/// Áreas que só aparecem no menu lateral.
final _secondary = <_MenuDestination>[
  _MenuDestination(
    'Contas',
    AppRoutes.accountsPath,
    Icons.account_balance_outlined,
    hint: 'Saldos e extratos',
  ),
  _MenuDestination(
    'Planejamento',
    AppRoutes.planningPath,
    Icons.flag_outlined,
    hint: 'Orçamentos e metas',
  ),
  _MenuDestination(
    'Patrimônio',
    AppRoutes.investmentsPath,
    Icons.savings_outlined,
    hint: 'Investimentos, bens e dívidas',
    also: {AppRoutes.assetsPath, AppRoutes.debtsPath},
  ),
  _MenuDestination(
    'Pessoas e reembolsos',
    AppRoutes.reimbursementsPath,
    Icons.people_outline,
    hint: 'Valores a receber de outras pessoas',
  ),
  _MenuDestination(
    'Categorias',
    AppRoutes.categoriesPath,
    Icons.sell_outlined,
    hint: 'Despesas e receitas',
  ),
];

final _settings = _MenuDestination(
  'Configurações',
  AppRoutes.settingsPath,
  Icons.settings_outlined,
  also: {AppRoutes.trashPath},
);

/// O drawer pertence ao Scaffold externo; este botão o abre a partir das páginas.
Widget? somiaMenuLeading(BuildContext context) =>
    MediaQuery.sizeOf(context).width < 800 ? const SomiaMenuButton() : null;

class SomiaMenuButton extends StatelessWidget {
  const SomiaMenuButton({super.key});
  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Abrir menu',
        icon: const Icon(Icons.menu),
        onPressed: () => _mobileScaffoldKey.currentState?.openDrawer(),
      );
}

/// Na rota da seção, sobreposições continuam recebendo Voltar antes dela.
class SomiaSectionBackScope extends StatelessWidget {
  const SomiaSectionBackScope({
    super.key,
    required this.location,
    required this.child,
  });
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
              context.go(
                location == AppRoutes.debtsPath &&
                        GoRouterState.of(context).uri.queryParameters['debt'] !=
                            null
                    ? AppRoutes.debtsPath
                    : location == AppRoutes.settingsPath &&
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
                                : AppRoutes.dashboardPath,
              );
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
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 800) {
            return Scaffold(
              body: Row(
                children: [
                  SizedBox(
                    width: constraints.maxWidth < 1060
                        ? 104 + MediaQuery.paddingOf(context).left
                        : 228 + MediaQuery.paddingOf(context).left,
                    child: _SomiaMenu(
                      location: location,
                      compact: constraints.maxWidth < 1060,
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: child),
                ],
              ),
            );
          }
          final mobileNavigation =
              Theme.of(context).platform == TargetPlatform.android;
          return Scaffold(
            key: _mobileScaffoldKey,
            drawer: Drawer(
              width: math.min(360, constraints.maxWidth * 0.88),
              child: _SomiaMenu(location: location, isDrawer: true),
            ),
            body:
                mobileNavigation ? _MobileNavigationScope(child: child) : child,
            bottomNavigationBar:
                !mobileNavigation || MediaQuery.viewInsetsOf(context).bottom > 0
                    ? null
                    : _SomiaMobileNavigation(location: location),
          );
        },
      );
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
    final reports = location == AppRoutes.analysisPath;
    final cards = {
      AppRoutes.cardsPath,
      AppRoutes.debitCardsPath,
      AppRoutes.cashbackPath,
    }.contains(location);
    final t = context.somia;

    Widget destination(
      String label,
      IconData icon,
      bool selected,
      VoidCallback onTap,
    ) {
      return Expanded(
        child: InkWell(
          key: ValueKey('bottom-$label'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 56,
                  height: 30,
                  decoration: BoxDecoration(
                    color: selected
                        ? t.accent.withValues(alpha: t.isDark ? 0.16 : 0.14)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(SomiaRadius.pill),
                  ),
                  child: Icon(icon,
                      color: selected ? t.accent : t.muted, size: 22),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? t.ink : t.muted,
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Material(
      color: t.surface,
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: t.outline)),
          ),
          child: Row(
            children: [
              destination(
                'Resumo',
                Icons.home_outlined,
                location == AppRoutes.dashboardPath,
                () => context.go(AppRoutes.dashboardPath),
              ),
              destination(
                'Movimentos',
                Icons.receipt_long_outlined,
                movements,
                () => context.go(AppRoutes.transactionsPath),
              ),
              destination(
                'Relatórios',
                Icons.bar_chart_outlined,
                reports,
                () => context.go(AppRoutes.analysisPath),
              ),
              destination(
                'Cartões',
                Icons.credit_card_outlined,
                cards,
                () => context.go(AppRoutes.cardsPath),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SomiaMenu extends StatelessWidget {
  const _SomiaMenu({
    required this.location,
    this.isDrawer = false,
    this.compact = false,
  });
  final String location;
  final bool isDrawer;
  final bool compact;

  bool _isSelected(_MenuDestination destination) =>
      location == destination.path ||
      destination.also.contains(location) ||
      (destination.path == AppRoutes.accountsPath &&
          location.startsWith('${AppRoutes.accountsPath}/'));

  void _go(BuildContext context, String path) {
    final router = GoRouter.of(context);
    if (isDrawer) Navigator.of(context).pop();
    if (location != path) router.go(path);
  }

  @override
  Widget build(BuildContext context) =>
      isDrawer ? _buildDrawer(context) : _buildSidebar(context);

  Widget _buildSidebar(BuildContext context) {
    final t = context.somia;
    return Material(
      color: t.sidebar,
      child: SafeArea(
        right: false,
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(compact ? 8 : 26, 28, 8, 24),
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
                        child: SomiaBrand(height: 38),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14),
                children: [
                  for (final destination in _primary)
                    _sidebarTile(context, destination),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: SomiaSpace.md, horizontal: SomiaSpace.md),
                    child: Divider(color: t.outline),
                  ),
                  for (final destination in _secondary)
                    _sidebarTile(context, destination),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                  compact ? 10 : 14, SomiaSpace.sm, compact ? 10 : 14, 16),
              child: _sidebarTile(context, _settings),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sidebarTile(BuildContext context, _MenuDestination destination) {
    final t = context.somia;
    final selected = _isSelected(destination);
    final tile = Padding(
      padding: const EdgeInsets.only(bottom: SomiaSpace.xs),
      child: ListTile(
        key: ValueKey('menu-${destination.path}'),
        leading: Icon(destination.icon,
            color: selected ? t.accent : t.muted, size: 22),
        title: compact
            ? null
            : Text(
                destination.label,
                style: TextStyle(
                  color: t.ink,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
        minLeadingWidth: 0,
        contentPadding: EdgeInsets.symmetric(horizontal: compact ? 18 : 14),
        selected: selected,
        selectedTileColor: t.accent.withValues(alpha: t.isDark ? 0.14 : 0.12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SomiaRadius.sm),
        ),
        onTap: () => _go(context, destination.path),
      ),
    );
    return compact ? Tooltip(message: destination.label, child: tile) : tile;
  }

  Widget _buildDrawer(BuildContext context) {
    final t = context.somia;
    final syncAvailable = getIt.isRegistered<SyncManager>();
    return Material(
      color: t.sidebar,
      child: SafeArea(
        right: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 12, 16),
              child: Row(
                children: [
                  const Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SomiaBrand(height: 34),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fechar menu',
                    icon: Icon(Icons.close, color: t.muted),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                children: [
                  for (final destination in _secondary)
                    _drawerDestination(context, destination),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: SomiaSpace.sm, horizontal: SomiaSpace.md),
                    child: Divider(color: t.outline),
                  ),
                  _drawerDestination(context, _settings),
                ],
              ),
            ),
            if (syncAvailable)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                child: Material(
                  color: t.surface,
                  borderRadius: BorderRadius.circular(SomiaRadius.md),
                  child: ListTile(
                    key: const ValueKey('menu-sync'),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(SomiaRadius.md),
                    ),
                    leading: Icon(Icons.sync, color: t.muted),
                    title: const Text('Sincronização'),
                    subtitle: const Text('Ver estado e sincronizar agora'),
                    onTap: () =>
                        _go(context, '${AppRoutes.settingsPath}?section=sync'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _drawerDestination(
    BuildContext context,
    _MenuDestination destination,
  ) {
    final t = context.somia;
    final selected = _isSelected(destination);
    return Padding(
      padding: const EdgeInsets.only(bottom: SomiaSpace.xxs),
      child: ListTile(
        key: ValueKey('menu-${destination.path}'),
        minLeadingWidth: 0,
        minTileHeight: 56,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: selected
                ? t.accent.withValues(alpha: t.isDark ? 0.16 : 0.12)
                : t.surface,
            borderRadius: BorderRadius.circular(SomiaRadius.sm),
          ),
          child: Icon(destination.icon,
              size: 20, color: selected ? t.accent : t.muted),
        ),
        title: Text(
          destination.label,
          style: TextStyle(
            color: t.ink,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
        subtitle: destination.hint == null
            ? null
            : Text(destination.hint!,
                style: TextStyle(color: t.muted, fontSize: 12)),
        selected: selected,
        selectedTileColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SomiaRadius.sm),
        ),
        onTap: () => _go(context, destination.path),
      ),
    );
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Adicionar movimento',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              for (final (action, label, description, icon, color) in [
                (
                  'income',
                  'Receita',
                  'Dinheiro que entrou',
                  MovementIdentity.incomeIcon,
                  MovementIdentity.incomeColor,
                ),
                (
                  'expense',
                  'Despesa',
                  'Pagamento ou compra',
                  MovementIdentity.expenseIcon,
                  MovementIdentity.expenseColor,
                ),
                (
                  'transfer',
                  'Transferência',
                  'Entre suas contas',
                  MovementIdentity.transferIcon,
                  MovementIdentity.transferColor,
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
                      borderRadius: BorderRadius.circular(14),
                    ),
                    tileColor: SomiaColors.surfaceHigh,
                    onTap: () => Navigator.of(sheetContext).pop(action),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
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
          minimumSize: const Size(60, 60),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SomiaRadius.md + 2),
          ),
        ),
        onPressed: () => _openMobileActions(context),
      );
    }
    return PopupMenuButton<String>(
      tooltip: 'Adicionar lançamento ou transferência',
      icon: Icon(Icons.add),
      iconColor: Theme.of(context).colorScheme.onPrimary,
      style: IconButton.styleFrom(
        backgroundColor: Theme.of(context).colorScheme.primary,
        minimumSize: const Size(56, 56),
      ),
      onSelected: (action) => context.go(_pathFor(action)),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'income',
          child: ListTile(
            leading: Icon(
              MovementIdentity.incomeIcon,
              color: MovementIdentity.incomeColor,
            ),
            title: Text('Receita'),
          ),
        ),
        PopupMenuItem(
          value: 'expense',
          child: ListTile(
            leading: Icon(
              MovementIdentity.expenseIcon,
              color: MovementIdentity.expenseColor,
            ),
            title: Text('Despesa'),
          ),
        ),
        PopupMenuItem(
          value: 'transfer',
          child: ListTile(
            leading: Icon(
              MovementIdentity.transferIcon,
              color: MovementIdentity.transferColor,
            ),
            title: Text('Transferência'),
          ),
        ),
      ],
    );
  }
}
