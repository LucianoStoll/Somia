# Experiência de uso — v0.3.0-alpha (#59)

Entrega conjunta dos seis ajustes solicitados em 07/10/2026. Mantém tema escuro, regras financeiras, schema 15 e identidade de instalação. A aprovação manual desta entrega não encerra automaticamente toda a revisão de experiência da alpha.

## Navegação e ícones

O balão do “+” compartilha ícones e cores com o menu lateral: Receita, Despesa e Transferência. Também está disponível em Cartões, tanto na lista como nos detalhes. Novo cartão continua como ação própria no cabeçalho. Os cards de Receitas e Despesas do resumo abrem as respectivas abas, mantendo o mês selecionado no filtro global.

## Cartões

A lista apresenta cada cartão em um bloco inspirado nas referências: instituição/nome, limite disponível (ou comprometido quando não houver controle de limite), fechamento e vencimento. Tocar abre os detalhes do cartão. Voltar retorna à lista; no Android, o retorno seguinte leva ao Resumo.

Os detalhes mostram limite total, comprometido, disponível, utilização, crédito quando houver, fechamento, vencimento e fatura do mês. Os valores continuam obedecendo às regras existentes: fatura do mês, saldo anterior e total a pagar têm identificação distinta. Pagamento, compra, edição, estorno, antecipação, histórico de limite, saldo inicial e ajustes de datas continuam disponíveis.

A opção **Extrato** mostra os itens da fatura selecionada, agrupados pela data da compra/registro; pagamentos desta fatura são agrupados pela sua data. Dias mais recentes aparecem primeiro. Não representa um filtro de compras por mês civil: uma fatura pode conter compras de meses diferentes e parcelas com a data original da compra. A opção Caixa/pagamentos mantém a visão por mês do débito da conta.

## Listas de lançamentos

Receitas, Despesas e Transferências usam linhas mais compactas: situação à esquerda, conta/descrição, data e valor à direita, etiquetas abaixo. Categoria e subcategoria reutilizam a mesma apresentação de cor do cadastro (cor armazenada clareada para leitura no tema escuro). Metadados como parcelas e rateio usam etiquetas discretas. Descrições longas são abreviadas na linha; edição contém o texto completo. Valores continuam clicáveis para calculadora; situação, descrição e menu têm ações independentes.

A data principal é a de efetivação quando informada, senão vencimento. A dica da data informa vencimento e efetivação para consultar os dois sem ocupar linhas adicionais. Em telas estreitas e com fonte ampliada, valor e descrição podem se distribuir verticalmente.

## Formulários

Criação/edição de receita, despesa e transferência usa campos sem preenchimento ou caixas arredondadas, com linhas discretas e espaçamento compacto. Descrição e valor vêm primeiro, depois conta/cartão (ou origem/destino), categorias quando aplicáveis, vencimento e efetivação. Recorrência/parcelamento, primeira parcela do cartão, rateio e data de lançamento ficam abaixo, em Mais opções. Ajuda específica aparece quando necessária. Tipo permanece em Mais detalhes nos formulários sem tipo fixo.

Mantém descrição com foco inicial Android, Enter para calculadora, validação, seleção de datas, três datas distintas, preenchimento e proteção ao cancelar. O botão Salvar permanece acessível com teclado aberto. Outros cadastros não recebem essa mudança de decoração automaticamente.

## Roteiro de validação conjunta

1. Comparar os ícones e cores do “+” com o menu lateral; testar as três opções em Cartões.
2. Escolher um mês futuro no Resumo, tocar Receitas/Despesas e conferir a mesma seleção mensal.
3. Conferir a nova lista de cartões, abrir detalhes de cartões diferentes e voltar à lista.
4. Conferir limites e fatura contra os valores anteriores; alternar fatura, Extrato e Caixa/pagamentos.
5. No Extrato, conferir agrupamento de compras e pagamentos por dia, incluindo parcelas e compras de outro mês.
6. Conferir cards compactos com categorias/subcategorias de cores diferentes e nomes longos.
7. Criar/editar os três tipos de lançamento; testar calculadora, vencimento, efetivação, recorrência, parcelas e rateio.
8. Cancelar um formulário preenchido, continuar editando e conferir que os dados permaneceram.
9. Conferir Android com teclado/fonte ampliada e Windows com Enter/Tab; sincronizar as alterações financeiras normalmente.

## Inventário

- Shell: identidade compartilhada de ícones, balão e retorno do detalhe de cartão.
- Dashboard mobile/desktop: links dos cards de receitas/despesas.
- CardsPage: lista visual, detalhe e extrato diário.
- MovementListRow: densidade, data e etiquetas coloridas.
- CategoryVisuals: apresentação compartilhada da cor de cadastro.
- MovementFormFrame/CompactMovementDate e formulários: linhas compactas e hierarquia.
- Testes de navegação, cartão, lista e formulário; prévias Android/Windows na CI.
