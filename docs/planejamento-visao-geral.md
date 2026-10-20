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

## Expansão de saldos e detalhamento das categorias

Os blocos expansíveis de contas e indicadores possuem chaves de estado próprias
por mês e moeda. Sua expansão não compartilha mais o identificador usado para
guardar a posição de rolagem da lista. A regressão exercita expandir, rolar,
recriar a tela durante o carregamento e alternar outubro/novembro/outubro.

Tocar em uma categoria na legenda ou em Ver categorias abre as subcategorias.
Valores lançados diretamente na principal aparecem como Sem subcategoria.
Transações e compras de cartão na mesma subcategoria são somadas; créditos
mantêm o sinal. Outras abre as categorias reais agrupadas, que também podem
ser detalhadas. O total da principal não é somado outra vez às subcategorias.

## Lançamentos por subcategoria

Tocar em uma subcategoria abre os lançamentos que compõem o seu valor no mês,
tipo e moeda selecionados. O painel mostra descrição, conta/cartão, data e
valor, com total e opção de repetir uma leitura que falhou. Fechar retorna ao
painel de subcategorias.

A consulta usa a mesma base dos gráficos: efetivação/vencimento nos movimentos,
vencimento da fatura nas compras, categorias exatas e parcelas de rateios.
Lançamentos diretos na principal não incluem suas filhas; Sem categoria filtra
somente valores sem categoria. Estornos conservam sinal e pagamentos de
fatura não repetem a despesa. Quando o valor é parte de um rateio, o painel
informa essa condição e o valor completo do lançamento.
