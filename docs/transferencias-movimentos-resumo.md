# Transferências em Movimentos e no Resumo

Movimentos inclui transferências uma única vez, com origem → destino, ícone próprio, valor sem sinal de receita/despesa e situação. Elas ficam nos grupos de pendentes ou de dias realizados. Entradas, saídas e resultado diário continuam considerando somente receitas/despesas.

Filtros de conta aceitam origem ou destino; situação e período também se aplicam às transferências. Categoria, subcategoria, tag, estabelecimento ou tipo Receita/Despesa excluem transferências, que não possuem esses atributos. As áreas Receitas e Despesas permanecem específicas. A edição reutiliza o formulário de transferência e respeita o escopo de séries. Efetivação rápida mantém desfazer e ajuste de data.

O card Transferências aparece no Resumo mobile e desktop, por moeda. Apresenta quantidade, valores realizados e pendentes/agendados, além dos atalhos Ver transferências e Nova transferência. Cada registro é contado uma vez, sem somar os dois lados do movimento. Meses sem transferências mantêm os atalhos e um estado vazio.

O período padrão das transferências segue a data de atividade: efetivação para realizadas e vencimento para pendentes/agendadas. As opções explícitas de lançamento, vencimento e efetivação permanecem disponíveis nos filtros. Resumo, Movimentos e a tela de Transferências usam a mesma referência mensal. Valores futuros agendados permanecem separados dos realizados.

Sem migration ou alteração nos cálculos de renda, despesa e saldos. As consultas excluem transferências removidas; o card também exclui contas removidas e mantém moedas separadas.
