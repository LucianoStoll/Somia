# Cadastros de contas e categorias — #40

Na v0.2.0-alpha, criação/edição de contas, categorias e subcategorias usa
MovementFormFrame, o mesmo componente dos lançamentos. No Android abre tela
cheia com Voltar, título, campos roláveis e Salvar no rodapé da área ajustada
pelo teclado e pelas áreas seguras. No Windows abre janela central adaptada.
O nome ganha foco ao criar no Android; os diálogos de edição preservam os dados.

Os formulários mantêm os campos, validadores, filtros de referências arquivadas
e a confirmação de descarte da #39. Salvar continua passando o mesmo draft ao
Cubit e repositório existentes. Nenhuma regra de arquivamento, saldo ou análise
foi alterada, e não há migration ou nova dependência.

O saldo inicial usa MonetaryCalculatorField com o rótulo Saldo inicial,
permitindo zero e valores negativos. A moeda acompanha o campo do cadastro.
As contas e categorias existentes e seus dados permanecem compatíveis.
O catálogo de bancos/logos continua na entrega #41.

## Validação manual

- Criar/editar conta no Android: nome, tipo, moeda, saldo inicial e opções.
- Salvar saldo inicial zero/negativo e conferir valores e opções após reiniciar.
- Criar categoria principal e subcategoria; conferir vínculo, tipo, ícone e cor.
- Editar subcategoria com categoria principal arquivada; manter vínculo histórico.
- Conferir nome obrigatório e validação de moeda.
- Alterar um campo e Voltar: continuar mantém tudo, descartar não grava.
- Salvar após continuar editando: confirmar os valores persistidos na lista.
- Conferir rolagem e Salvar com teclado aberto em tela pequena/paisagem/texto ampliado.
- No Windows, conferir janela central, rolagem, Salvar e Cancelar.

Validação manual aprovada pelo usuário em 01/10/2026.
