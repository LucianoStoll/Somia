# Planejamento — visão geral mensal

A aba Planejamento passa a abrir em Visão geral. Orçamentos mantém criação,
edição, exclusão e cópia de limites; Metas mantém o progresso das contas
vinculadas. Os indicadores anteriores ficam recolhidos na visão geral.

## Saldo previsto das contas

O destaque mostra o saldo acumulado até o último dia do mês selecionado,
com detalhamento expansível por conta. Reutiliza a consulta de saldos do
Resumo: corte realizado no menor entre hoje e o fim do mês, e corte de
previsão no fim do mês. Inclui saldos iniciais, movimentos, transferências,
baixas e faturas conforme as regras existentes. O pagamento da fatura não
duplica as compras. Não é apenas o resultado de receitas menos despesas.

A soma respeita includeInBalance. Moedas são exibidas separadamente, sem
conversão implícita. As receitas e despesas previstas seguem os critérios
de análise existentes, que podem incluir contas fora do saldo consolidado.

## Categorias e limites

Despesas e Receitas alternam no mesmo gráfico. O previsto inclui realizado
e pendente, usa o mês de vencimento/efetivação e considera compras no mês
da fatura. Rateios são preservados e subcategorias agrupadas pela principal.
As cores vêm do cadastro. Mais de quatro categorias exibem três maiores
e Outras; Ver categorias abre a lista completa. Créditos líquidos negativos
ficam listados separadamente, sem fatias negativas ou totais ocultos.

Atenção aos limites mostra até três orçamentos com uso previsto a partir de
80%, ordenados por proporção. Ver todos abre Orçamentos. Indicadores mostra
os dados mensais e a taxa de poupança que já existiam.

## Validação

Regressões cobrem mudança mensal acumulada, igualdade com o Resumo,
pagamento futuro de fatura sem duplicação e navegação entre as abas.
O CI gera as prévias Android e Windows existentes com a nova visão geral.
A aprovação final requer conferir as prévias e testar no aparelho.
Nenhuma migration ou alteração de dados é necessária.
