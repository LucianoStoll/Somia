# Transferências em Movimentos e no Resumo

Movimentos inclui transferências uma única vez, com origem → destino, ícone próprio, valor sem sinal de receita/despesa e situação. Elas ficam nos grupos de pendentes ou de dias realizados. Entradas, saídas e resultado diário continuam considerando somente receitas/despesas.

Filtros de conta aceitam origem ou destino; situação e período também se aplicam às transferências. Categoria, subcategoria, tag, estabelecimento ou tipo Receita/Despesa excluem transferências, que não possuem esses atributos. As áreas Receitas e Despesas permanecem específicas. A edição reutiliza o formulário de transferência e respeita o escopo de séries. Efetivação rápida mantém desfazer e ajuste de data.

O card Transferências aparece no Resumo mobile e desktop, por moeda. Apresenta quantidade, valores realizados e pendentes/agendados, além dos atalhos Ver transferências e Nova transferência. Cada registro é contado uma vez, sem somar os dois lados do movimento. Meses sem transferências mantêm os atalhos e um estado vazio.

O período padrão das transferências segue a data de atividade: efetivação para realizadas e vencimento para pendentes/agendadas. As opções explícitas de lançamento, vencimento e efetivação permanecem disponíveis nos filtros. Resumo, Movimentos e a tela de Transferências usam a mesma referência mensal. Valores futuros agendados permanecem separados dos realizados.

Sem migration ou alteração nos cálculos de renda, despesa e saldos. As consultas excluem transferências removidas; o card também exclui contas removidas e mantém moedas separadas.

## Totais de Movimentos na mesma base do Resumo

O cabeçalho de Movimentos mostra Recebido no mês e Pago no mês usando a mesma consulta do detalhamento do Resumo: valores efetivos, datas de efetivação, contas incluídas no saldo e registros que não ignoram saldo. Pago inclui despesas liquidadas e pagamentos efetivos de cartão; não inclui a compra/fatura novamente, pendências nem transferências. Baixas parciais seguem seus valores, datas e contas reais.

Esse cartão é mensal e acompanha o mês do topo; filtros de tipo, conta, categoria e período personalizam a lista, sem mudar o consolidado mensal do cartão. A legenda identifica a referência ao Resumo. A lista e seus valores previstos continuam disponíveis para edição. A consulta é compartilhada entre as telas para evitar divergência de critérios, sem migrations ou alterações de registros.
