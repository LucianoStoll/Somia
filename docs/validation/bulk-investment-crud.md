# Edição em lote e CRUD de investimentos — 09/10/2026

## Lançamentos
Receitas/despesas, transferências e compras individuais: abrir os três pontinhos → Editar em lote. A ocorrência inicia selecionada; selecionar outros itens ou todos e usar Editar em lote/Mover para lixeira. Cancelar seleção ou concluir a operação devolve a lista normal, sem checkboxes nem contador. Trocar filtros/mês encerra a seleção. Faturas agregadas continuam sem edição em lote.

## Investimentos
Criar, consultar, editar e excluir aplicações. Editar permite trocar a conta vinculada por outra conta ativa em reais ainda livre. Saldos, aportes, resgates, rendimentos e ajustes anteriores permanecem na conta original; a mudança representa correção de cadastro, sem transferência de dinheiro.

Excluir aplicação exige confirmação e remove apenas o cadastro da aplicação. A conta, seu saldo e todas as movimentações continuam disponíveis em Contas. O vínculo fica livre para cadastrar outra aplicação. A exclusão não altera o estado arquivado da conta: reativar em Contas quando necessário. Arquivar/reativar continua disponível para conservar uma aplicação desativada.

Schema 24 mantém todos os registros e troca a unicidade total do vínculo por unicidade das aplicações ativas. Cadastros excluídos continuam como tombstones para backup/sync. Pacotes pendentes são reidentificados; pacotes históricos até schema 23 continuam aceitos. Atualizar Android e Windows antes de sincronizar. Não aplicar esta versão em clientes antigos com novas alterações.

## Verificações
Testes de preservação de saldo/histórico na troca e exclusão, reutilização do vínculo, duplicidade, backup/sync, migração v23 com fila e triggers; tela da seleção e confirmação de exclusão. CI analisa e testa Linux/Windows e gera os dois pacotes.

## Roteiro manual pendente
- Lista normal sem checkboxes; iniciar pelos três pontinhos, selecionar outros, cancelar, aplicar edição e lixeira nas três listas.
- Cancelar o editor mantém a seleção; cancelar a seleção não altera registros; trocar mês/filtros não mantém itens ocultos selecionados.
- Editar nome/tipo/instituição/vencimento/notas e corrigir conta; conferir extratos e saldos de ambas as contas.
- Cancelar/confirmar exclusão; reutilizar conta em nova aplicação; conferir conta e movimentos preservados.
- Arquivar e reativar, backup/restauração e sincronizar com Android/Windows atualizados.
