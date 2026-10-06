import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';
import '../di/injection.dart';
import '../database/backup_manager.dart';
import '../widgets/somia_brand.dart';
import 'app_router.dart';

final _mobileScaffoldKey = GlobalKey<ScaffoldState>();

class _MenuDestination {
  const _MenuDestination(this.label, this.path, this.icon,
      [this.color = SomiaColors.muted]);
  final String label;
  final String path;
  final IconData icon;
  final Color color;
}

const _menu = <_MenuDestination>[
  _MenuDestination(
      'Resumo', AppRoutes.dashboardPath, Icons.home_outlined, SomiaColors.blue),
  _MenuDestination('Receitas', AppRoutes.incomePath,
      Icons.arrow_circle_up_outlined, SomiaColors.green),
  _MenuDestination('Despesas', AppRoutes.expensesPath,
      Icons.arrow_circle_down_outlined, SomiaColors.red),
  _MenuDestination('Transferências', AppRoutes.transfersPath, Icons.swap_horiz),
  _MenuDestination(
      'Contas', AppRoutes.accountsPath, Icons.account_balance_wallet_outlined),
  _MenuDestination(
      'Investimentos', AppRoutes.investmentsPath, Icons.savings_outlined),
  _MenuDestination('Cartões', AppRoutes.cardsPath, Icons.credit_card_outlined),
  _MenuDestination('Categorias', AppRoutes.categoriesPath, Icons.sell_outlined),
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
              context.go(location.startsWith('${AppRoutes.accountsPath}/')
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
        return Scaffold(
            key: _mobileScaffoldKey,
            drawer: Drawer(
                width: math.min(300, constraints.maxWidth * 0.82),
                child: _SomiaMenu(location: location, isDrawer: true)),
            body: child);
      });
}

class _SomiaMenu extends StatelessWidget {
  const _SomiaMenu(
      {required this.location, this.isDrawer = false, this.compact = false});
  final String location;
  final bool isDrawer;
  final bool compact;

  @override
  Widget build(BuildContext context) {
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
                for (final destination in _menu)
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
            )));
  }
}

class SomiaQuickActions extends StatelessWidget {
  const SomiaQuickActions({super.key});

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
        tooltip: 'Adicionar lançamento ou transferência',
        icon: const Icon(Icons.add),
        iconColor: Theme.of(context).colorScheme.onPrimary,
        style: IconButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.primary,
            minimumSize: const Size(56, 56)),
        onSelected: (action) {
          if (action == 'transfer') {
            context.go('${AppRoutes.transfersPath}?create=1');
          } else {
            final path = action == 'income'
                ? AppRoutes.incomePath
                : AppRoutes.expensesPath;
            context.go('$path?create=1');
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(
              value: 'income',
              child: ListTile(
                  leading: Icon(Icons.south_west), title: Text('Receita'))),
          PopupMenuItem(
              value: 'expense',
              child: ListTile(
                  leading: Icon(Icons.north_east), title: Text('Despesa'))),
          PopupMenuItem(
              value: 'transfer',
              child: ListTile(
                  leading: Icon(Icons.swap_horiz),
                  title: Text('Transferência'))),
        ],
      );
}
