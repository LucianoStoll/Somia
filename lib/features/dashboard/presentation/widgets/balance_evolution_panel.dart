import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

import '../../../accounts/domain/money_minor.dart';
import '../../domain/entities/dashboard_summary.dart';
import 'dashboard_overview.dart' show SummaryPanel;

/// Presentation only: forecasts retain the repository's cumulative balances.
class BalanceEvolutionPanel extends StatefulWidget {
  const BalanceEvolutionPanel({
    super.key,
    required this.currency,
    this.today,
    this.bare = false,
  });

  /// Sem moldura nem eixo de valores, como no Resumo do celular.
  final bool bare;
  final DashboardCurrencySummary currency;
  final DateTime? today;

  @override
  State<BalanceEvolutionPanel> createState() => _BalanceEvolutionPanelState();
}

class _BalanceEvolutionPanelState extends State<BalanceEvolutionPanel> {
  int? selected;

  @override
  void didUpdateWidget(covariant BalanceEvolutionPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currency.dailyBalances.firstOrNull?.date !=
        widget.currency.dailyBalances.firstOrNull?.date) {
      selected = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final points = widget.currency.dailyBalances;
    if (points.isEmpty) {
      return const SummaryPanel(
        title: 'Evolução do saldo',
        child: Text('Sem histórico diário disponível.'),
      );
    }
    final now = widget.today ?? DateTime.now();
    final today = DateTime.utc(now.year, now.month, now.day);
    final todayIndex = points.indexWhere((p) => _date(p.date) == today);
    final actualEnd = points.lastIndexWhere(
      (p) => !_date(p.date).isAfter(today),
    );
    final values = [
      for (var i = 0; i < points.length; i++)
        i <= actualEnd ? points[i].currentMinor : points[i].projectedMinor,
    ];
    final index =
        (selected ?? (todayIndex >= 0 ? todayIndex : points.length - 1)).clamp(
      0,
      points.length - 1,
    );
    final point = points[index];
    final axis = _BalanceAxis(values);
    final scaler = MediaQuery.textScalerOf(context);
    final labelStyle = Theme.of(context).textTheme.bodySmall!.copyWith(
          color: SomiaColors.muted,
          fontSize: 11,
          fontWeight: FontWeight.w400,
        );
    final direction = Directionality.of(context);
    final labels = axis.ticks.map(axis.label).toList();
    final bare = widget.bare;
    final t = context.somia;
    final left = bare
        ? 6.0
        : labels
                .map((value) =>
                    _text(value, labelStyle, scaler, direction).width)
                .reduce(math.max) +
            12;
    final top = bare ? 8.0 : scaler.scale(11) + 13;
    final bottom = scaler.scale(bare ? 12 : 11) + 18;
    String detail(int i) => 'Dia ${points[i].date.day} • '
        '${i <= actualEnd ? 'realizado' : 'previsto'} '
        '${MoneyMinor.display(values[i], widget.currency.currencyCode)}';
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, box) {
            final height = bare
                ? 120.0 + top + bottom
                : (box.maxWidth * .38).clamp(130.0, 220.0) + top + bottom;
            final plot = Rect.fromLTRB(
              left,
              top,
              box.maxWidth - (bare ? 6 : 8),
              height - bottom,
            );
            void select(double x) => setState(
                  () => selected =
                      ((x - plot.left) / plot.width * (points.length - 1))
                          .round()
                          .clamp(0, points.length - 1),
                );
            return Semantics(
              label: 'Consultar saldo diário',
              hint:
                  'Toque ou arraste para consultar os valores. Previsão inclui pendências cadastradas e faturas, inclusive vencidas.',
              value: detail(index),
              increasedValue:
                  index < points.length - 1 ? detail(index + 1) : null,
              decreasedValue: index > 0 ? detail(index - 1) : null,
              onIncrease: index < points.length - 1
                  ? () => setState(() => selected = index + 1)
                  : null,
              onDecrease:
                  index > 0 ? () => setState(() => selected = index - 1) : null,
              child: GestureDetector(
                key: const ValueKey('balance-evolution-plot'),
                behavior: HitTestBehavior.opaque,
                onTapDown: (event) => select(event.localPosition.dx),
                onHorizontalDragUpdate: (event) =>
                    select(event.localPosition.dx),
                child: SizedBox(
                  height: height,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: _BalancePainter(
                      points: points,
                      values: values,
                      actualEnd: actualEnd,
                      todayIndex: todayIndex,
                      selected: selected == null ? null : index,
                      axis: axis,
                      plot: plot,
                      labelStyle: labelStyle,
                      scaler: scaler,
                      direction: direction,
                      tokens: t,
                      bare: bare,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        SizedBox(height: bare ? 4 : 12),
        Wrap(
          spacing: bare ? 16 : 24,
          runSpacing: 10,
          children: [
            for (final projected in [false, true])
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 27,
                    height: 12,
                    child: CustomPaint(painter: _LegendPainter(projected, t)),
                  ),
                  const SizedBox(width: 9),
                  Flexible(
                      child: Text(
                    projected ? 'Previsto' : 'Realizado',
                    style: TextStyle(color: t.muted, fontSize: 12),
                  )),
                ],
              ),
          ],
        ),
        if (selected != null) ...[
          const SizedBox(height: 12),
          Text(
            detail(index),
            key: const ValueKey('balance-day-detail'),
            style: TextStyle(color: t.ink, fontWeight: FontWeight.w600),
          ),
          if (index <= actualEnd && point.projectedMinor != point.currentMinor)
            Text(
              'Com pendências: ${MoneyMinor.display(point.projectedMinor, widget.currency.currencyCode)}',
              style: TextStyle(color: SomiaColors.muted),
            ),
        ],
      ],
    );
    return bare
        ? content
        : SummaryPanel(title: 'Evolução do saldo', child: content);
  }
}

DateTime _date(DateTime value) =>
    DateTime.utc(value.year, value.month, value.day);

TextPainter _text(
  String text,
  TextStyle style,
  TextScaler scaler,
  TextDirection direction,
) =>
    TextPainter(
      text: TextSpan(text: text, style: style),
      textScaler: scaler,
      textDirection: direction,
    )..layout();

class _BalanceAxis {
  _BalanceAxis(List<int> values) {
    final min = math.min(0, values.reduce(math.min)).toDouble();
    final max = math.max(0, values.reduce(math.max)).toDouble();
    final raw = math.max(100.0, max - min) / 3;
    final magnitude =
        math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    final normalized = raw / magnitude;
    step = [1.0, 1.5, 2.0, 2.5, 5.0, 10.0].firstWhere((v) => v >= normalized) *
        magnitude;
    low = (min / step).floor() * step;
    high = (max / step).ceil() * step;
    if (high == low) high = low + step * 3;
  }
  late final double step, low;
  late double high;
  List<double> get ticks => [
        for (var v = low; v <= high + step * .01; v += step) v,
      ];
  String label(double value) {
    final major = value / 100;
    if (major.abs() >= 1000000) {
      return '${(major / 1000000).toStringAsFixed(1).replaceAll('.', ',')} mi';
    }
    if (major.abs() >= 100000) {
      return '${(major / 1000).toStringAsFixed(0)} mil';
    }
    final parts = major
        .toStringAsFixed(major == major.roundToDouble() ? 0 : 2)
        .split('.');
    final integer = parts.first.replaceAllMapped(
        RegExp(r'\d{1,3}(?=(\d{3})+$)'), (match) => '${match[0]}.');
    return parts.length == 1 ? integer : '$integer,${parts.last}';
  }
}

class _BalancePainter extends CustomPainter {
  _BalancePainter({
    required this.points,
    required this.values,
    required this.actualEnd,
    required this.todayIndex,
    required this.selected,
    required this.axis,
    required this.plot,
    required this.labelStyle,
    required this.scaler,
    required this.direction,
    required this.tokens,
    required this.bare,
  });
  final SomiaTokens tokens;
  final bool bare;
  final List<DashboardDailyBalance> points;
  final List<int> values;
  final int actualEnd, todayIndex;
  final int? selected;
  final _BalanceAxis axis;
  final Rect plot;
  final TextStyle labelStyle;
  final TextScaler scaler;
  final TextDirection direction;

  @override
  void paint(Canvas canvas, Size size) {
    final t = tokens;
    double x(int i) =>
        plot.left + i / math.max(1, points.length - 1) * plot.width;
    // No modo enxuto a escala acompanha o mês, sem partir do zero.
    final minValue = values.reduce(math.min).toDouble();
    final maxValue = values.reduce(math.max).toDouble();
    final spread = math.max(maxValue - minValue, maxValue.abs() * .02 + 1);
    final low = bare ? minValue - spread * .15 : axis.low.toDouble();
    final high = bare ? maxValue + spread * .15 : axis.high.toDouble();
    double y(num value) =>
        plot.bottom - (value - low) / (high - low) * plot.height;
    final grid = Paint()
      ..color = t.outline.withValues(alpha: .7)
      ..strokeWidth = 1;
    void label(String text, double cx, {bool strong = false}) {
      final painter = _text(
        text,
        strong
            ? labelStyle.copyWith(
                color: t.ink, fontWeight: FontWeight.w700, fontSize: 12)
            : labelStyle.copyWith(fontSize: bare ? 12 : 11),
        scaler,
        direction,
      );
      painter.paint(
        canvas,
        Offset((cx - painter.width / 2).clamp(0, size.width - painter.width),
            plot.bottom + 10),
      );
    }

    if (!bare) {
      for (final value in axis.ticks) {
        canvas.drawLine(
          Offset(plot.left, y(value)),
          Offset(plot.right, y(value)),
          grid,
        );
        final text = _text(axis.label(value), labelStyle, scaler, direction);
        text.paint(
          canvas,
          Offset(plot.left - text.width - 12, y(value) - text.height / 2),
        );
      }
      final tickCount = math.min(
        points.length,
        plot.width < scaler.scale(210) ? 4 : 6,
      );
      for (final i in {
        for (var n = 0; n < tickCount; n++)
          (n * (points.length - 1) / math.max(1, tickCount - 1)).round(),
      }) {
        if (i == todayIndex) continue;
        label(points[i].date.day.toString().padLeft(2, '0'), x(i));
      }
    } else {
      final edges = {0, points.length - 1}..remove(todayIndex);
      for (final i in edges) {
        if (todayIndex >= 0 && (x(i) - x(todayIndex)).abs() < 36) continue;
        label(points[i].date.day.toString(), x(i));
      }
    }
    final locations = [
      for (var i = 0; i < points.length; i++) Offset(x(i), y(values[i])),
    ];
    canvas.save();
    canvas.clipRect(plot.inflate(8));
    if (actualEnd >= 0) {
      final area = Path()..moveTo(locations.first.dx, plot.bottom);
      for (var i = 0; i <= actualEnd; i++) {
        area.lineTo(locations[i].dx, locations[i].dy);
      }
      area.lineTo(locations[actualEnd].dx, plot.bottom);
      area.close();
      canvas.drawPath(area, Paint()..color = t.chartArea);
      final path = Path()..moveTo(locations.first.dx, locations.first.dy);
      for (var i = 1; i <= actualEnd; i++) {
        path.lineTo(locations[i].dx, locations[i].dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = t.ink
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      if (actualEnd == 0) {
        canvas.drawCircle(locations.first, 2, Paint()..color = t.ink);
      }
    }
    if (actualEnd < points.length - 1) {
      final first = math.max(0, actualEnd);
      final path = Path()..moveTo(locations[first].dx, locations[first].dy);
      for (var i = first + 1; i < locations.length; i++) {
        path.lineTo(locations[i].dx, locations[i].dy);
      }
      final dash = Paint()
        ..color = t.accent
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      for (final metric in path.computeMetrics()) {
        for (var distance = 0.0; distance < metric.length; distance += 11) {
          canvas.drawPath(
            metric.extractPath(distance, math.min(distance + 5, metric.length)),
            dash,
          );
        }
      }
    }
    if (todayIndex >= 0) {
      final tx = x(todayIndex);
      final marker = Paint()
        ..color = t.muted
        ..strokeWidth = 1;
      for (var yy = plot.top; yy < plot.bottom; yy += 6) {
        canvas.drawLine(
          Offset(tx, yy),
          Offset(tx, math.min(yy + 2, plot.bottom)),
          marker,
        );
      }
      canvas.drawCircle(
          locations[todayIndex], 6, Paint()..color = t.background);
      canvas.drawCircle(
        locations[todayIndex],
        6,
        Paint()
          ..color = t.ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }
    if (selected != null && selected != todayIndex) {
      canvas.drawLine(
        Offset(x(selected!), plot.top),
        Offset(x(selected!), plot.bottom),
        Paint()..color = t.muted.withValues(alpha: .5),
      );
      canvas.drawCircle(locations[selected!], 4, Paint()..color = t.ink);
    }
    canvas.restore();
    if (todayIndex >= 0) label('Hoje', x(todayIndex), strong: true);
  }

  @override
  bool shouldRepaint(covariant _BalancePainter oldDelegate) => true;
}

class _LegendPainter extends CustomPainter {
  const _LegendPainter(this.projected, this.tokens);
  final bool projected;
  final SomiaTokens tokens;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = projected ? tokens.accent : tokens.ink
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final y = size.height / 2;
    if (projected) {
      for (var x = 2.0; x < size.width - 2; x += 9) {
        canvas.drawLine(
            Offset(x, y), Offset(math.min(x + 4, size.width - 2), y), paint);
      }
    } else {
      canvas.drawLine(Offset(2, y), Offset(size.width - 2, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _LegendPainter oldDelegate) =>
      projected != oldDelegate.projected || tokens != oldDelegate.tokens;
}
