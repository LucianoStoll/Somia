import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/month_selector.dart';
import '../../../accounts/domain/money_minor.dart';
import '../../domain/entities/dashboard_summary.dart';

typedef MonthTarget = Widget Function(DashboardMonthTotal month, Widget child);

/// Um único balão por gráfico, com âncora no mês e dados do próprio histórico.
class HistoryTooltipChart extends StatefulWidget {
  const HistoryTooltipChart(
      {super.key,
      required this.history,
      required this.currencyCode,
      required this.builder});
  final List<DashboardMonthTotal> history;
  final String currencyCode;
  final Widget Function(MonthTarget target) builder;
  @override
  State<HistoryTooltipChart> createState() => _HistoryTooltipChartState();
}

class _HistoryTooltipChartState extends State<HistoryTooltipChart> {
  final _controller = OverlayPortalController();
  final _anchors = <DateTime, GlobalKey>{};
  DateTime? _selected;
  ScrollPosition? _position;
  DateTime _month(DateTime date) => DateTime.utc(date.year, date.month);
  void _hide() {
    _controller.hide();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context)?.position;
    if (position != _position) {
      _position?.removeListener(_hide);
      _position = position;
      _position?.addListener(_hide);
    }
  }

  @override
  void didUpdateWidget(covariant HistoryTooltipChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    final months = widget.history.map((x) => _month(x.month)).toSet();
    _anchors.removeWhere((date, _) => !months.contains(date));
    if (!months.contains(_selected) ||
        widget.currencyCode != oldWidget.currencyCode) {
      _selected = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _selected == null) _hide();
      });
    }
  }

  @override
  void dispose() {
    _position?.removeListener(_hide);
    super.dispose();
  }

  Widget _target(DashboardMonthTotal month, Widget child) {
    final date = _month(month.month);
    return TapRegion(
        groupId: this,
        child: Semantics(
            button: true,
            label:
                '${monthNames[date.month - 1]} ${date.year}: receitas ${MoneyMinor.display(month.incomeMinor, widget.currencyCode)}, despesas ${MoneyMinor.display(month.expenseMinor, widget.currencyCode)}',
            child: Material(
                color: Colors.transparent,
                child: InkWell(
                    key: _anchors.putIfAbsent(date, () => GlobalKey()),
                    onTap: () => setState(() {
                          _selected = date;
                          _controller.show();
                        }),
                    child: KeyedSubtree(
                        key: ValueKey(
                            'history-month-${widget.currencyCode}-${date.year}-${date.month}'),
                        child: child)))));
  }

  @override
  Widget build(BuildContext context) => OverlayPortal(
      controller: _controller,
      overlayChildBuilder: (context) {
        final item = widget.history
            .where((x) => _month(x.month) == _selected)
            .firstOrNull;
        final anchor = _anchors[_selected]?.currentContext?.findRenderObject();
        final overlay = Overlay.of(context).context.findRenderObject();
        if (item == null ||
            anchor is! RenderBox ||
            !anchor.hasSize ||
            overlay is! RenderBox ||
            !overlay.hasSize) {
          return const SizedBox.shrink();
        }
        final offset = anchor.localToGlobal(Offset.zero) -
            overlay.localToGlobal(Offset.zero);
        final media = MediaQuery.of(context);
        final bounds = Rect.fromLTRB(
            media.padding.left + 8,
            media.padding.top + 8,
            overlay.size.width - media.padding.right - 8,
            overlay.size.height -
                media.padding.bottom -
                media.viewInsets.bottom -
                8);
        return CustomSingleChildLayout(
            delegate: _TooltipLayout(
                Rect.fromLTWH(
                    offset.dx,
                    offset.dy + math.max(0, anchor.size.height - 24),
                    anchor.size.width,
                    math.min(24, anchor.size.height)),
                bounds),
            child: TapRegion(
                groupId: this,
                onTapOutside: (_) => _hide(),
                child: Material(
                    key: const ValueKey('history-tooltip'),
                    elevation: 0,
                    color: SomiaColors.surfaceHigh,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: SomiaColors.outline)),
                    child: SingleChildScrollView(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                  '${monthNames[item.month.month - 1]} ${item.month.year}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: SomiaColors.blue)),
                              const SizedBox(height: 8),
                              for (final value in [
                                (
                                  'Receitas',
                                  item.incomeMinor,
                                  SomiaColors.green
                                ),
                                (
                                  'Despesas',
                                  item.expenseMinor,
                                  SomiaColors.red
                                ),
                                (
                                  'Saldo do mês',
                                  item.incomeMinor - item.expenseMinor,
                                  SomiaColors.blue
                                )
                              ])
                                Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 4),
                                    child:
                                        LayoutBuilder(builder: (context, box) {
                                      final label = Text(value.$1),
                                          amount = Text(
                                              MoneyMinor.display(value.$2,
                                                  widget.currencyCode),
                                              style: TextStyle(
                                                  color: value.$3,
                                                  fontWeight: FontWeight.w600));
                                      if (box.maxWidth < 260 ||
                                          MediaQuery.textScalerOf(context)
                                                  .scale(14) >
                                              20) {
                                        return Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [label, amount]);
                                      }
                                      return Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(child: label),
                                            const SizedBox(width: 8),
                                            Flexible(child: amount)
                                          ]);
                                    }))
                            ])))));
      },
      child: widget.builder(_target));
}

class _TooltipLayout extends SingleChildLayoutDelegate {
  _TooltipLayout(this.anchor, this.bounds);
  final Rect anchor, bounds;
  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.tightFor(width: math.min(300, math.max(0, bounds.width)))
          .copyWith(maxHeight: math.max(0, bounds.height));
  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final x = (anchor.center.dx - childSize.width / 2)
        .clamp(
            bounds.left, math.max(bounds.left, bounds.right - childSize.width))
        .toDouble();
    final above = anchor.top - childSize.height - 8;
    final y = (above >= bounds.top ? above : anchor.bottom + 8)
        .clamp(
            bounds.top, math.max(bounds.top, bounds.bottom - childSize.height))
        .toDouble();
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(covariant _TooltipLayout oldDelegate) =>
      anchor != oldDelegate.anchor || bounds != oldDelegate.bounds;
}
