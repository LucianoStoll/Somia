# Experiência de uso — fechamento da alpha

Entrega autorizada em 15/10/2026, relacionada à #59. Base: alpha com Resumo visual, cashback e menus/reembolsos integrados.

- Menu por Dia a dia, Planejamento, Patrimônio e Organização. Cada destino continua independente; navegação e cores preservadas.
- Resumo: blocos com ação de recolher/expandir e escolha lembrada. Ocultar contas zeradas mantém a escolha ao navegar e reiniciar; contas negativas continuam visíveis. Preferências locais em arquivo próprio, fora da base financeira e sincronização. Falhas de gravação recebem feedback; arquivo ausente/inválido retorna ao padrão.
- Receitas/despesas e transferências agrupadas por dia usando o campo de data selecionado. Total listado por moeda (receita positiva/despesa negativa); transferências mostram volume transferido, sem tratá-lo como despesa. Totais não representam saldo bancário nem fazem conversão. Dias mais recentes primeiro; ordenação dos itens dentro do grupo preservada.
- Filtros ativos em chips removíveis; limpar retorna ao mês compartilhado. Conta, situação, categoria, tags e estabelecimento visíveis conforme aplicável.
- Descrição em destaque; conta em texto secundário. Tocar descrição abre detalhes com valor, conta, situação e datas. Editar destacado; valor mantém calculadora, efetivação mantém ação rápida e menus continuam disponíveis.
- Detalhes de receitas/despesas incluem rateios com categorias e valores, acesso ao histórico de baixas, anexos e consulta dos reembolsos vinculados. Transferências também oferecem anexos. Faturas conservam o fluxo de abertura existente.
- Reembolsos indicam Previsto/Parcial/Recebido; cashback mantém origem, previsto/recebido/devolução e orientação para confirmar quando houver depósito.
- Formulários compactos existentes preservados: descrição, valor, conta e categoria primeiro; campos complementares em Mais opções.

Sem migration ou mudança de cálculos financeiros. Recolhimento usa o título do bloco como identidade e se aplica igualmente a blocos equivalentes em moedas diferentes no aparelho.

## Validação

Testes de persistência após reabertura, gravações consecutivas, leitura inválida, remontagem do Resumo e fluxo detalhe → editar. CI deve conferir análise, suíte Linux/Windows, prévias e builds. Validar pelo uso em Android e Windows: menu/retorno, fonte ampliada, teclado, filtros, detalhes/editar/calculadora/efetivação, rateios, anexos e preferências após reiniciar. A aceitação manual permanece pendente; nenhuma publicação final em main.
