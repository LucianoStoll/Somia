# Planejamento — v0.3.0-alpha, #13

Acesso: Planejamento no menu lateral e em Configurações. Três abas: Orçamentos, Metas e Indicadores. O mês compartilhado controla orçamento e indicadores; metas e reserva mostram o saldo atual, independente desse filtro.

## Orçamentos

Limite por categoria ou subcategoria, moeda e mês. Categoria principal inclui suas filhas; não se pode criar limites sobrepostos de principal e filha na mesma moeda/mês. Histórico versionado por mês: editar outubro não altera setembro; Copiar mês anterior preenche somente limites inexistentes, sem sobrescrever os atuais. Excluir limite mantém os lançamentos. Não há replicação automática para todos os meses.

Realizado: despesa por conta efetivada até hoje no mês da efetivação. Previsto total: realizado mais movimentos pendentes ou com efetivação futura, atribuídos à efetivação quando informada e ao vencimento quando pendentes. Rateios distribuem o valor sem duplicar. Movimentos excluídos/ignorados para análise e contas fora das análises não entram.

Cartões: parcelas, taxas, descontos e estornos entram no mês da fatura. Compras registradas até hoje são realizadas nos meses até o atual; parcelas em meses futuros aparecem no previsto. Pagamento de fatura não entra novamente como despesa. Saldo de abertura do cartão não é consumo por categoria. Reembolsos são receitas separadas, preservando despesa integral. Transferências não entram nos indicadores de renda/despesa. Moedas permanecem separadas, sem conversão presumida.

Alertas internos: previsto a partir de 80% do limite e ultrapassagem, sem bloquear lançamentos ou enviar notificações ao sistema.

## Metas e reserva

Meta: nome, moeda, valor objetivo, prazo opcional e uma ou mais contas vinculadas. Progresso usa o saldo realizado atual dessas contas, inclusive contas fora do resumo de saldo. Vincular não cria transferência, não bloqueia dinheiro e não soma patrimônio. Uma conta pode financiar somente uma meta/reserva ativa; arquivar libera esse vínculo para outra, e reativação com conflito é rejeitada. Excluir/arquivar a meta não altera o saldo. Contas vinculadas não podem trocar de moeda.

Reserva: 1–36 meses de cobertura, com seis como valor inicial editável, e categorias essenciais escolhidas. Objetivo = cobertura × média de gastos realizados nos três meses completos anteriores a hoje. Divisor sempre três, incluindo meses sem gastos; não usa o mês ainda em andamento. Principal e filha não são somadas duas vezes. A base é dinâmica: corrigir gastos anteriores ou avançar o mês atual atualiza o objetivo. Sem base de gastos, mostrar aviso e objetivo zero, sem declarar reserva completa. Histórico incompleto pode subestimar a necessidade: conferir a média exibida e as categorias antes de usar o objetivo como referência.

Prazo vencido e valor restante ficam visíveis. Referência mensal = restante dividido pelos meses de calendário até o prazo (inclui o mês atual), arredondada para cima. É uma referência simples, sem prever rendimentos, inflação ou garantir sucesso.

## Indicadores e educação

Receita/despesa realizada, resultado realizado, resultado previsto e taxa de poupança por moeda. Taxa = (receita − despesa) / receita × 100; sem renda positiva é indisponível, pode ser negativa quando gastos excedem renda. Sobra financeira não significa aporte efetivo. Alertar déficit previsto, prazo vencido e ausência de base da reserva. Orientações curtas explicam transferências, cartão, reserva e comparação com metas; nenhum escore arbitrário de saúde financeira.

## Persistência e validação

Schema 18 aditivo: budget_limits, planning_goals, goal_accounts. Metadados, triggers de sync, snapshots e validação de categoria/moeda/vínculos. Pacotes históricos 11–17 permanecem legíveis; entidades de planejamento não são aceitas em schemas antigos. Fila pendente reidentificada. Atualizar os dois dispositivos antes do sync.

Testes cobrem previsto/realizado, rateio, cartão sem duplicação, meses independentes/cópia, metas sem alteração de caixa, exclusividade/arquivamento, reserva média/sem base, moedas, snapshot/sync/migration e formulários Android/Windows. Pacotes e resultado final registrados na #13. Validação manual pendente.

Roteiro: criar limite, despesa paga e pendente; conferir principal/filhas e rateio; copiar mês sem alterar anterior; cadastrar meta e vincular conta; transferir para a conta e conferir progresso; tentar mesma conta em outra meta; arquivar e reativar; escolher essenciais e cobertura da reserva; conferir média, prazo e indicadores; testar backup/sync e retorno/teclado no Android e Windows.
