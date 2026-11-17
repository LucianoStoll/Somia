import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../routing/app_router.dart';
import '../theme/app_theme.dart';

/// Abas em pílula que trocam entre telas irmãs de uma mesma área
/// (Movimentos: Todos, Receitas, Despesas, Transferências; Patrimônio:
/// Investimentos, Bens, Dívidas). Usadas como `AppBar.bottom`.
class SomiaSectionTabs extends StatelessWidget implements PreferredSizeWidget {
  const SomiaSectionTabs({
    super.key,
    required this.items,
    required this.current,
  });

  /// Abas de Movimentos, que substituem os itens separados do menu.
  const SomiaSectionTabs.movements({super.key, required this.current})
      : items = const [
          ('Todos', AppRoutes.transactionsPath),
          ('Receitas', AppRoutes.incomePath),
          ('Despesas', AppRoutes.expensesPath),
          ('Transferências', AppRoutes.transfersPath),
        ];

  /// Abas de Patrimônio.
  const SomiaSectionTabs.patrimony({super.key, required this.current})
      : items = const [
          ('Investimentos', AppRoutes.investmentsPath),
          ('Bens', AppRoutes.assetsPath),
          ('Dívidas', AppRoutes.debtsPath),
        ];

  final List<(String, String)> items;
  final String current;

  @override
  Size get preferredSize => const Size.fromHeight(52);

  @override
  Widget build(BuildContext context) {
    final t = context.somia;
    final text = Theme.of(context).textTheme.labelLarge;
    return SizedBox(
      height: preferredSize.height,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(
            SomiaSpace.lg, 0, SomiaSpace.lg, SomiaSpace.sm),
        child: Row(
          children: [
            for (final (label, path) in items)
              Padding(
                padding: const EdgeInsets.only(right: SomiaSpace.sm),
                child: Semantics(
                  selected: path == current,
                  button: true,
                  child: Material(
                    color: path == current ? t.ink : Colors.transparent,
                    shape: StadiumBorder(
                      side: BorderSide(
                          color: path == current ? t.ink : t.outline),
                    ),
                    child: InkWell(
                      key: ValueKey('section-$path'),
                      customBorder: const StadiumBorder(),
                      onTap: path == current ? null : () => context.go(path),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 40),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: SomiaSpace.lg),
                          child: Center(
                            widthFactor: 1,
                            child: Text(
                              label,
                              style: text?.copyWith(
                                color: path == current ? t.background : t.ink,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
