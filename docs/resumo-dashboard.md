# Resumo do mês — Android e Windows

Entrega da #77, relacionada à #59. Tema escuro preservado. Sem migração de banco.

## Organização

- Windows: largura útil de até 1760 px, quatro indicadores, vencimentos/curva, histórico/categorias e últimos cadastrados/contas em colunas quando houver espaço.
- Android: saldo, receber/pagar lado a lado, previsão final, vencimentos, curva, histórico, categorias, contas e últimos cadastrados. Texto ampliado empilha os indicadores.
- Resultado mensal permanece separado: receitas menos despesas analíticas, incluindo previstas. Não representa saldo acumulado ou fluxo líquido de caixa; compras e pagamentos de cartão não são somados novamente como despesas.
- Categorias mostram cinco maiores, valor e participação no total positivo; Ver todas abre Análises mantendo mês compartilhado.
- Contas mostram logo cadastrado, inclusão no saldo e agrupamento investimento/dia a dia por moeda; ocultar zeradas é uma escolha local da tela. Toque abre o extrato da conta.
- Últimos cadastrados é uma lista global ordenada por criação, com data de vencimento; pode conter outros meses.

## Regras preservadas

Os saldos usam o mesmo cálculo da listagem de contas, por moeda, sem incluir contas excluídas do saldo consolidado. O corte financeiro é o fim do mês selecionado, incluindo efetivações datadas naquele mês. Para meses futuros o primeiro indicador se chama Saldo previsto; para anteriores, Saldo efetivado no mês. A composição detalhada continua acessível pelos cards de saldo.

A receber e A pagar consideram pendências acumuladas até o fim do mês; A pagar inclui saldo de faturas ainda não coberto. Recebido/Pago usam movimentos efetivados no mês (pagamentos de fatura entram como caixa). Transferências continuam na composição do saldo, fora de receitas/despesas.

Curva: recalcula cada dia com o mesmo motor de saldos, com linhas efetivada e prevista e consulta pelo controle deslizante. Não prevê recorrências ainda não geradas; atualiza com os dados atuais e não é um histórico de versões antigas de previsões.

Vencimentos: receitas/despesas pendentes (saldo restante de baixas) e dívida de cartão até o mês selecionado, com atrasados. Mostra cinco primeiros. Efetivar usa a confirmação de data existente; baixas parciais e faturas devem usar suas telas especializadas. Erros preservam o estado e oferecem orientação.

## Conferência manual

1. Conferir mês atual, anterior e futuro e moedas separadas; abrir composição de saldo.
2. Conferir pendências e valores pagos/recebidos; testar vencimento passado e futuro e cancelar efetivação.
3. Conferir dívida de cartão com pagamento parcial, saldo credor e fatura anterior.
4. Mover controle da curva e comparar último dia com saldo final.
5. Ver categorias e Análises; ocultar zeradas, conferir investimentos fora do saldo e abrir conta.
6. Android estreito, fonte ampliada e Windows redimensionado; rolar até o fim e trocar mês.

Validação manual posterior pelo uso. A issue permanece aberta até confirmação do usuário.


## Acesso aos últimos cadastrados — v0.4.0-alpha

Tocar em um lançamento recente no Android ou Windows abre seus detalhes em uma folha rolável, sem mudar o mês selecionado. A consulta busca o registro atual pelo identificador, independentemente do mês do Resumo: descrição, valor, conta(s), categoria, datas, situação e informações complementares disponíveis. Compras no cartão mostram a compra e o vencimento da fatura, sem apresentá-las como uma despesa de conta efetivada.

O botão de navegação continua disponível para a seção correspondente; em compras, abre o Extrato do cartão e mês da fatura corretos. Fechar os detalhes mantém o Resumo. Um registro removido não abre outro lançamento nem usa os valores antigos; falha de leitura permite tentar novamente. A consulta não altera lançamentos, saldos ou sincronização.

## Realizado e previsto nos gráficos — v0.4.0-alpha

Os gráficos de categorias e de receitas/despesas compartilham a seleção **Realizado / Previsto total / Ambos**. A seleção vale para todas as moedas na sessão e permanece ao trocar o mês ou atualizar. O padrão é Previsto total, preservando o conteúdo anterior. Ambos apresenta as duas visões identificadas separadamente, com a mesma escala no histórico; não soma realizado ao previsto total.

- Realizado: efetivações até o dia atual, no mês da efetivação. Baixas parciais entram individualmente; o restante ainda aberto não é realizado.
- Previsto total: realizado mais pendências e agendamentos já registrados, pela efetivação informada ou vencimento. Não estima novos lançamentos nem recorrências não geradas.
- Rateios continuam distribuindo os centavos por categoria; transferências não são receita/despesa. As moedas e as exclusões das análises são preservadas.
- Cartões seguem a base de consumo já usada no Planejamento: compra registrada até hoje e mês da fatura até o mês atual contam no realizado, no mês do vencimento da fatura. Parcelas em meses futuros ficam no previsto; estornos/descontos reduzem os valores. Pagamento de fatura não é uma segunda despesa nos gráficos.

A seleção altera somente os gráficos analíticos. Saldo atual/projetado e recebimentos/pagamentos do consolidado continuam usando sua base de caixa, inclusive os pagamentos de fatura. Gráficos e saldos não devem ser interpretados como a mesma medida. As consultas não reconstroem o estado histórico do cadastro antes de alterações posteriores.
