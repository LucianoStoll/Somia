import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// O mesmo grafite e a mesma hierarquia do Resumo nos módulos financeiros.
class ModuleSurface extends StatelessWidget {
  const ModuleSurface({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Theme(
        data: Theme.of(context).copyWith(
          cardTheme: Theme.of(context)
              .cardTheme
              .copyWith(margin: const EdgeInsets.only(bottom: 12)),
          expansionTileTheme: const ExpansionTileThemeData(
            shape: Border(),
            collapsedShape: Border(),
            iconColor: SomiaColors.muted,
            collapsedIconColor: SomiaColors.muted,
            tilePadding: EdgeInsets.zero,
          ),
        ),
        child: ColoredBox(
            color: SomiaColors.background,
            child: Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1280),
                    child: child))),
      );
}

class ModuleHero extends StatelessWidget {
  const ModuleHero(
      {super.key,
      required this.label,
      required this.value,
      required this.icon,
      this.color = SomiaColors.blue,
      this.children = const []});
  final String label, value;
  final IconData icon;
  final Color color;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Card(
          child: Padding(
        padding: const EdgeInsets.all(20),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
                child: Text(label,
                    style: const TextStyle(
                        color: SomiaColors.muted, fontSize: 13))),
            Icon(icon, color: color, size: 22),
          ]),
          const SizedBox(height: 10),
          Text(value,
              style: TextStyle(
                  color: color,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5)),
          if (children.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 12),
            ...children
          ],
        ]),
      ));
}

class ModuleDetails extends StatelessWidget {
  const ModuleDetails(
      {super.key, this.title = 'Detalhes', required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => ExpansionTile(
        title: Text(title,
            style: const TextStyle(fontSize: 13, color: SomiaColors.muted)),
        childrenPadding: const EdgeInsets.only(bottom: 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );
}

class ModuleStat extends StatelessWidget {
  const ModuleStat(
      {super.key,
      required this.label,
      required this.value,
      this.color = SomiaColors.blue});
  final String label, value;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(color: SomiaColors.muted, fontSize: 12)),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 19, fontWeight: FontWeight.w700)),
        ]),
      );
}

class ModuleValueRow extends StatelessWidget {
  const ModuleValueRow({super.key, required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: LayoutBuilder(builder: (context, box) {
          final title = Text(label,
              style: const TextStyle(color: SomiaColors.muted, fontSize: 13));
          final amount = Text(value,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w600));
          if (box.maxWidth < 340 ||
              MediaQuery.textScalerOf(context).scale(14) > 21) {
            return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [title, const SizedBox(height: 4), amount]);
          }
          return Row(children: [
            Expanded(child: title),
            const SizedBox(width: 16),
            Flexible(child: amount)
          ]);
        }),
      );
}
