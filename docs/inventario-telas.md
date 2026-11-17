# Somia — Inventário de telas e plano da interface Fluxo

Versão: 1.0 • 17/11/2026 • Ciclo v0.4.0-alpha
Base: código da branch `v0.4.0-alpha` e direção visual “Fluxo” (ver
`identidade-visual.md`, seção Direção Fluxo).

O app tem **19 rotas** e cerca de **30 telas secundárias** (formulários, painéis
e diálogos). Todas foram redesenhadas no protótipo da direção Fluxo, mantendo
todas as funções existentes. Os nomes `P-xx` são as pranchetas do protótipo.

## 1. Navegação

| Elemento | Hoje | Na direção Fluxo |
| --- | --- | --- |
| Barra inferior (Android) | Resumo, Movimentos, Relatórios, Cartões | Mantida, com item ativo marcado em âmbar (P-03, P-10, P-30, P-40) |
| Menu lateral (mobile) | Drawer com Finanças, Planejamento, Aplicativo; títulos de grupo em caixa alta | Mesma ordem e grupos, títulos em caixa normal, painel mais estreito (P-01) |
| Sidebar (Windows) | 228px, ícones abaixo de 1060px | Mantida, com item ativo em âmbar (prancheta B · Resumo no Windows) |
| Botão + | Ícone com folha Receita, Despesa, Transferência | Somente o ícone **+**; folha “Adicionar movimento” (P-02) |
| Seletor de mês | Setas e rótulo; toque abre “Escolher mês” | Setas circulares contornadas; diálogo redesenhado (P-06) |

## 2. Telas por área

### Resumo e componentes globais

| Tela | Arquivo principal | Pontos de atenção hoje | Protótipo |
| --- | --- | --- | --- |
| Resumo (`/`) | `dashboard/presentation/widgets/mobile_dashboard.dart` | 10 blocos com pesos visuais parecidos; gráfico de barras compete com o saldo | P-03 |
| Detalhamento do saldo | `balance_details_panel.dart` | Lista longa sem hierarquia entre consolidado e previsto | P-04 |
| Detalhes do lançamento | `recent_activity_details.dart` | — | P-05 |
| Escolher mês | `core/widgets/month_selector.dart` | — | P-06 |
| Quando contabilizar / aviso de efetivação | `effectuation_date_dialog.dart`, `effectuation_feedback.dart` | — | P-07 |
| Calculadora | `monetary_calculator.dart` | — | P-08 |

### Movimentos

| Tela | Arquivo principal | Pontos de atenção hoje | Protótipo |
| --- | --- | --- | --- |
| Movimentos / Receitas / Despesas | `transactions/presentation/transactions_page.dart` | Linhas densas (ícone de estado, etiquetas, menu e valor na mesma linha); pendências misturadas às efetivadas | P-10, P-11 |
| Filtros | idem | 10 campos sem agrupamento | P-12 |
| Seleção e edição em lote | `bulk_movement_toolbar.dart` | — | P-13, P-14 |
| Detalhes do movimento e ações | `movement_list_row.dart` | Menu com 7 ações sem hierarquia | P-15 |
| Nova receita / despesa | `TransactionForm` | Muitos campos visíveis de uma vez; “Mais opções” com conteúdo extenso | P-16, P-17 |
| Baixas e histórico | `transaction_settlements_page.dart` | — | P-18 |
| Anexos | `attachments_page.dart` | — | P-19 |

### Transferências, contas e categorias

| Tela | Arquivo principal | Protótipo |
| --- | --- | --- |
| Transferências e formulário | `transfers/presentation/transfers_page.dart` | P-20, P-21 |
| Contas | `accounts/presentation/accounts_page.dart` | P-22 |
| Extrato da conta | `account_statement_page.dart` | P-23 |
| Nova conta e escolher instituição | `accounts_page.dart`, `bank_selector.dart` | P-24, P-25 |
| Categorias e formulário | `categories/presentation/categories_page.dart` | P-26, P-27 |

### Cartões

| Tela | Arquivo principal | Protótipo |
| --- | --- | --- |
| Lista de cartões | `cards/presentation/cards_page.dart` | P-30 |
| Cartão: Fatura, Extrato, Pagamentos | idem | P-31, P-32, P-33 |
| Pagar fatura | `card_forms.dart` | P-34 |
| Novo cartão | `card_forms.dart` | P-35 |
| Débito | `debit_cards_page.dart` | P-36 |
| Cashback e regra | `cashback_page.dart` | P-37, P-38 |

Formulários de ajuste, datas reais, antecipação e compras cobertas seguem o
padrão de formulário de P-34 e não têm prancheta própria.

### Planejamento, análises e patrimônio

| Tela | Arquivo principal | Protótipo |
| --- | --- | --- |
| Análises (Relatórios) | `analysis/presentation/expense_analysis_page.dart` | P-40 |
| Planejamento: Visão geral, Orçamentos, Metas | `planning/presentation/*` | P-41, P-42, P-43 |
| Investimentos e movimentar aplicação | `investments/presentation/*` | P-44, P-45 |
| Dívidas e detalhe | `debts/presentation/*` | P-46, P-47 |
| Bens e patrimônio | `assets/presentation/*` | P-48 |

### Pessoas, configurações e dados

| Tela | Arquivo principal | Protótipo |
| --- | --- | --- |
| Pessoas e reembolsos, receber reembolso | `reimbursements/presentation/*` | P-50, P-51 |
| Configurações | `settings/presentation/settings_page.dart` | P-52 |
| Backup, Google Drive, Sincronização | `local_backups_panel.dart`, `drive_backups_panel.dart`, `sync_panel.dart` | P-53, P-54, P-55 |
| Importar extrato (passos 1 a 3) | `csv_import/presentation/csv_import_page.dart` | P-56, P-57 |
| Lixeira | `transactions/presentation/trash_page.dart` | P-58 |

## 3. Problemas transversais encontrados

1. **Estilos soltos:** 144 `TextStyle` e 86 `fontSize` escritos nas telas, além
   de 362 usos de cores fixas. A base de tokens (`SomiaTokens`) já resolve as
   cores; tipografia e espaçamento migram tela a tela.
2. **Cartões demais:** quase todo bloco é um cartão com borda, o que deixa as
   telas densas. Na direção Fluxo, as superfícies agrupam conteúdo relacionado e
   o restante fica sobre o fundo.
3. **Pendências pouco visíveis:** o estado “pendente” aparece como ícone pequeno.
   Passa a ter marcador contornado e ação **Efetivar** na própria linha.
4. **Valores dependentes de cor:** padronizar sinal `+`/`−` em todos os valores.
5. **Rótulos em caixa alta** nos grupos do menu: passam para caixa normal.

## 4. Ordem sugerida de implementação

1. Componentes compartilhados: cabeçalho com seletor de mês, linha de
   movimento, bloco de superfície, folha inferior, campo de formulário,
   pílulas de filtro, barra inferior e botão +.
2. Resumo (P-03 a P-05) e gráfico de saldo do mês.
3. Movimentos, Receitas, Despesas e formulário (P-10 a P-19).
4. Cartões (P-30 a P-38).
5. Contas, transferências e categorias (P-20 a P-27).
6. Planejamento, análises e patrimônio (P-40 a P-48).
7. Pessoas, configurações e importação (P-50 a P-58).
