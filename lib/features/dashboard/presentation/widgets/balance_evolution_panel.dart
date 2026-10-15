import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../accounts/domain/money_minor.dart';
import '../../domain/entities/dashboard_summary.dart';
import 'dashboard_overview.dart' show SummaryPanel;
import 'dashboard_palette.dart';

/// Presentation only: forecasts retain the repository's cumulative balances.
class BalanceEvolutionPanel extends StatefulWidget {
  const BalanceEvolutionPanel({super.key, required this.currency, this.today});
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
    final left = labels
            .map((value) => _text(value, labelStyle, scaler, direction).width)
            .reduce(math.max) +
        12;
    final top = scaler.scale(11) + 13;
    final bottom = scaler.scale(11) + 18;
    String detail(int i) => 'Dia ${points[i].date.day} • '
        '${i <= actualEnd ? 'realizado' : 'previsto'} '
        '${MoneyMinor.display(values[i], widget.currency.currencyCode)}';
    return SummaryPanel(
      title: 'Evolução do saldo',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, box) {
              final height =
                  (box.maxWidth * .38).clamp(130.0, 220.0) + top + bottom;
              final plot = Rect.fromLTRB(
                left,
                top,
                box.maxWidth - 8,
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
                onDecrease: index > 0
                    ? () => setState(() => selected = index - 1)
                    : null,
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
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 24,
            runSpacing: 10,
            children: [
              for (final projected in [false, true])
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 27,
                      height: 12,
                      child: CustomPaint(painter: _LegendPainter(projected)),
                    ),
                    const SizedBox(width: 9),
                    Flexible(
                        child: Text(
                      projected ? 'Previsto' : 'Realizado',
                      style: const TextStyle(color: SomiaColors.muted),
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
              style: const TextStyle(color: SomiaColors.blue),
            ),
            if (index <= actualEnd &&
                point.projectedMinor != point.currentMinor)
              Text(
                'Com pendências: ${MoneyMinor.display(point.projectedMinor, widget.currency.currencyCode)}',
                style: const TextStyle(color: SomiaColors.muted),
              ),
          ],
        ],
      ),
    );
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
  });
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
    double x(int i) =>
        plot.left + i / math.max(1, points.length - 1) * plot.width;
    double y(num value) =>
        plot.bottom - (value - axis.low) / (axis.high - axis.low) * plot.height;
    final grid = Paint()
      ..color = SomiaColors.outline.withValues(alpha: .6)
      ..strokeWidth = 1;
    for (final value in axis.ticks) {
      canvas.drawLine(
        Offset(plot.left, y(value)),
        Offset(plot.right, y(value)),
        grid,
      );
      final label = _text(axis.label(value), labelStyle, scaler, direction);
      label.paint(
        canvas,
        Offset(plot.left - label.width - 12, y(value) - label.height / 2),
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
      canvas.drawLine(Offset(x(i), plot.top), Offset(x(i), plot.bottom), grid);
      final label = _text(
        points[i].date.day.toString().padLeft(2, '0'),
        labelStyle,
        scaler,
        direction,
      );
      label.paint(
        canvas,
        Offset(
          (x(i) - label.width / 2).clamp(0, size.width - label.width),
          plot.bottom + 10,
        ),
      );
    }
    canvas.drawLine(
      Offset(plot.left, y(0)),
      Offset(plot.right, y(0)),
      Paint()
        ..color = SomiaColors.blue.withValues(alpha: .32)
        ..strokeWidth = 1.2,
    );
    final locations = [
      for (var i = 0; i < points.length; i++) Offset(x(i), y(values[i])),
    ];
    final area = Path()..moveTo(plot.left, y(0));
    for (final location in locations) {
      area.lineTo(location.dx, location.dy);
    }
    area.lineTo(locations.last.dx, y(0));
    area.close();
    canvas.save();
    canvas.clipRect(plot.inflate(3));
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            SomiaColors.blue.withValues(alpha: .19),
            SomiaColors.blue.withValues(alpha: .03),
          ],
        ).createShader(plot),
    );
    final line = Paint()
      ..color = SomiaColors.blue
      ..strokeWidth = 2.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (actualEnd >= 0) {
      final path = Path()..moveTo(locations.first.dx, locations.first.dy);
      for (var i = 1; i <= actualEnd; i++) {
        path.lineTo(locations[i].dx, locations[i].dy);
      }
      canvas.drawPath(path, line);
      if (actualEnd == 0) {
        canvas.drawCircle(
          locations.first,
          2,
          Paint()..color = SomiaColors.blue,
        );
      }
    }
    // A single arc-length cadence keeps round dots evenly spaced across day boundaries.
    if (actualEnd < points.length - 1) {
      final first = math.max(0, actualEnd);
      final path = Path()..moveTo(locations[first].dx, locations[first].dy);
      for (var i = first + 1; i < locations.length; i++) {
        path.lineTo(locations[i].dx, locations[i].dy);
      }
      for (final metric in path.computeMetrics()) {
        for (var distance = 0.0; distance < metric.length; distance += 8) {
          canvas.drawCircle(
            metric.getTangentForOffset(distance)!.position,
            1.65,
            Paint()..color = SomiaColors.blue,
          );
        }
      }
      canvas.drawCircle(
        locations.last,
        1.65,
        Paint()..color = SomiaColors.blue,
      );
    }
    if (todayIndex >= 0) {
      final tx = x(todayIndex);
      final marker = Paint()
        ..color = SomiaColors.blue.withValues(alpha: .8)
        ..strokeWidth = 1;
      for (var yy = plot.top; yy < plot.bottom; yy += 6) {
        canvas.drawLine(
          Offset(tx, yy),
          Offset(tx, math.min(yy + 3, plot.bottom)),
          marker,
        );
      }
      canvas.drawCircle(
        Offset(tx, plot.top),
        2.6,
        Paint()..color = SomiaColors.blue,
      );
      canvas.drawCircle(
        locations[todayIndex],
        4.6,
        Paint()..color = SomiaColors.blue,
      );
    }
    if (selected != null && selected != todayIndex) {
      canvas.drawLine(
        Offset(x(selected!), plot.top),
        Offset(x(selected!), plot.bottom),
        Paint()..color = SomiaColors.blue.withValues(alpha: .25),
      );
      canvas.drawCircle(
        locations[selected!],
        3.5,
        Paint()..color = SomiaColors.blue,
      );
    }
    canvas.restore();
    if (todayIndex >= 0) {
      final label = _text('Hoje', labelStyle, scaler, direction);
      label.paint(
        canvas,
        Offset(
          (x(todayIndex) - label.width / 2).clamp(
            plot.left,
            size.width - label.width,
          ),
          0,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BalancePainter oldDelegate) => true;
}

class _LegendPainter extends CustomPainter {
  const _LegendPainter(this.projected);
  final bool projected;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = SomiaColors.blue
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;
    if (projected) {
      for (var x = 2.0; x < size.width; x += 7) {
        canvas.drawCircle(Offset(x, size.height / 2), 1.65, paint);
      }
    } else {
      canvas.drawLine(
        Offset(2, size.height / 2),
        Offset(size.width - 2, size.height / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LegendPainter oldDelegate) =>
      projected != oldDelegate.projected;
}
