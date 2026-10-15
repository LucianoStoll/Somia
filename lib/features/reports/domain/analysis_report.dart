import '../../accounts/domain/money_minor.dart';
import '../../analysis/domain/expense_analysis.dart';

class ReportMoney {
  const ReportMoney(this.minor);
  final int minor;
}

class ReportSection {
  ReportSection(this.title, this.headers, this.rows);
  final String title;
  final List<String> headers;
  final List<List<Object>> rows;
}

/// A single snapshot shared by both formats; currencies are never added together.
class AnalysisReport {
  AnalysisReport(this.title, this.month, this.currency, this.generatedAt,
      this.note, this.sections);
  final String title, currency, note;
  final DateTime month, generatedAt;
  final List<ReportSection> sections;

  static const titles = [
    'Despesas por categoria',
    'Comparação mensal',
    'Compromissos futuros',
    'Saldo por tipo de conta'
  ];
  static const notes = [
    'Efetivação ou vencimento; cartões pelo vencimento da fatura. Inclui previstos, rateios e estornos. Cada linha de rateio representa parte do lançamento.',
    'Efetivação ou vencimento; cartões pelo vencimento da fatura. A média considera os três meses anteriores completos, inclusive meses sem lançamentos. O mês selecionado pode estar incompleto.',
    'Próximos seis meses após o selecionado. Pendências existentes na geração do relatório; despesas e encargos de cartão não liquidados, sem repetir pagamentos ou saldos antigos. Recorrências ainda não geradas não são estimadas.',
    'Saldo efetivado até o fim do mês selecionado. Inclui todas as contas ativas, mesmo as excluídas do saldo do mês. Exclui arquivadas. Aplicações entram somente pelo saldo da conta.'
  ];

  factory AnalysisReport.fromAnalysis(
      ExpenseAnalysis data, String currency, int view,
      {DateTime? generatedAt}) {
    if (view < 0 ||
        view >= titles.length ||
        !data.currencies.contains(currency)) {
      throw ArgumentError('Análise ou moeda inválida.');
    }
    final sections = <ReportSection>[];
    List<Object> detail(AnalysisExpense e) => [
          e.date,
          e.description,
          e.source,
          e.category,
          e.subcategory,
          ReportMoney(e.amount),
          e.id
        ];
    ReportSection details(Iterable<AnalysisExpense> expenses) {
      final rows = expenses.toList()
        ..sort((a, b) {
          final date = a.date.compareTo(b.date);
          return date != 0 ? date : a.id.compareTo(b.id);
        });
      return ReportSection(
          'Lançamentos',
          [
            'Data de referência',
            'Descrição',
            'Origem',
            'Categoria',
            'Subcategoria',
            'Valor ($currency)',
            'Identificador'
          ],
          rows.map(detail).toList());
    }

    if (view == 0) {
      final rows = data.comparisons(currency).where((r) => r.current != 0);
      final total = rows.fold<int>(0, (s, r) => s + r.current);
      sections.add(ReportSection('Categorias', [
        'Categoria',
        'Valor ($currency)'
      ], [
        for (final r in rows) [r.category, ReportMoney(r.current)],
        ['Total líquido', ReportMoney(total)]
      ]));
      sections.add(details(data.inMonth(currency, data.month)));
    } else if (view == 1) {
      final rows = data.comparisons(currency);
      sections.add(ReportSection('Comparação', [
        'Categoria',
        'Mês selecionado ($currency)',
        'Mês anterior ($currency)',
        'Média de 3 meses ($currency)',
        'Diferença ($currency)',
        'Variação'
      ], [
        for (final r in rows)
          [
            r.category,
            ReportMoney(r.current),
            ReportMoney(r.previous),
            ReportMoney(r.average),
            ReportMoney(r.difference),
            r.changePercent == null
                ? 'Sem base percentual'
                : '${r.changePercent!.toStringAsFixed(1)}%'
          ],
        [
          'Total', ReportMoney(rows.fold<int>(0, (s, r) => s + r.current)),
          ReportMoney(rows.fold<int>(0, (s, r) => s + r.previous)),
          // Round the global average once, exactly as the screen does.
          ReportMoney(data.expenses
                  .where((e) =>
                      e.currency == currency &&
                      (e.date.year != data.month.year ||
                          e.date.month != data.month.month))
                  .fold<int>(0, (s, e) => s + e.amount) ~/
              3),
          ReportMoney(rows.fold<int>(0, (s, r) => s + r.difference)), ''
        ]
      ]));
      sections.add(details(data.expenses.where((e) => e.currency == currency)));
    } else if (view == 2) {
      final rows = data.commitments[currency] ?? <FutureCommitment>[];
      sections.add(ReportSection('Compromissos', [
        'Mês',
        'Despesas ($currency)',
        'Cartões ($currency)',
        'Total ($currency)'
      ], [
        for (final r in rows)
          [
            period(r.month),
            ReportMoney(r.expenseTotal),
            ReportMoney(r.cardTotal),
            ReportMoney(r.total)
          ],
        [
          'Total',
          ReportMoney(rows.fold<int>(0, (s, r) => s + r.expenseTotal)),
          ReportMoney(rows.fold<int>(0, (s, r) => s + r.cardTotal)),
          ReportMoney(rows.fold<int>(0, (s, r) => s + r.total))
        ]
      ]));
      sections.add(details(rows.expand((r) => [...r.expenses, ...r.cards])));
    } else {
      final values = data.balances(currency);
      sections.add(ReportSection('Tipos de conta', [
        'Tipo',
        'Saldo ($currency)'
      ], [
        for (final r in values.entries) [r.key.label, ReportMoney(r.value)],
        ['Total', ReportMoney(values.values.fold<int>(0, (s, v) => s + v))]
      ]));
      sections.add(ReportSection('Contas', [
        'Conta',
        'Tipo',
        'Incluída no saldo do mês',
        'Saldo ($currency)',
        'Identificador'
      ], [
        for (final a in data.accounts
            .where((a) => !a.isArchived && a.currencyCode == currency))
          [
            a.name,
            a.type.label,
            a.includeInBalance ? 'Sim' : 'Não',
            ReportMoney(a.currentBalanceMinor),
            a.id
          ]
      ]));
    }
    return AnalysisReport(titles[view], data.month, currency,
        generatedAt ?? DateTime.now(), notes[view], sections);
  }

  static String period(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}/${d.year}';
  static String date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${period(d)}';
  String display(Object value) => switch (value) {
        ReportMoney() => MoneyMinor.display(value.minor, currency),
        DateTime() => date(value),
        _ => value.toString()
      };
}
