# Pessoas e reembolsos — v0.3.0-alpha

Entrega #67, epic #11. A escolha aprovada mantém a despesa integral e contabiliza o recebimento como receita separada. Exemplo: despesa de R$ 100, obrigação de R$ 40, recebimentos de R$ 15 e R$ 25. A lista de despesas mostra R$ 100; receitas mostram os dois recebimentos; o histórico mostra R$ 40 recebido e zero a receber.

## Uso

Em **Mais opções** da despesa, habilitar **Reembolso**, selecionar/cadastrar pessoas e informar os valores a receber. É possível adicionar várias linhas. Recolher as opções preserva o preenchimento. Salvar a obrigação não cria receita nem modifica saldo. O total combinado não pode superar a despesa. Na compra no cartão, o vínculo corresponde à compra e ao total das parcelas cadastradas; não é um estorno do cartão.

**Pessoas e reembolsos** no menu lateral e em Configurações reúne cadastro, edição, outros nomes, arquivamento/reativação, mesclagem e histórico filtrado por pessoa. Registrar recebimento cria uma receita na conta/moeda escolhida; a categoria de receita é opcional. Para dinheiro já registrado, usar **Vincular receita existente**: não cria outro lançamento. Uma receita só pode estar vinculada a uma obrigação.

Recebido considera somente receitas efetivadas até hoje. Receitas pendentes ou com efetivação futura aparecem separadamente e reservam o valor para impedir recebimentos acima do combinado. Pendência = combinado menos recebido. Disponível para novo recebimento = pendência menos pendentes/agendados. Moedas são acompanhadas separadamente.

Receitas vinculadas podem ser editadas, efetivadas, desfeitas ou excluídas nas listas normais. Excluir uma receita faz o valor voltar a ficar a receber; o vínculo histórico permanece. Desvincular mantém a receita e seu efeito no saldo, mas deixa de considerá-la recebimento da obrigação. Remover uma obrigação com receitas ativas exige antes desvinculá-las. Reduzir valores abaixo do já vinculado, trocar tipo/moeda incompatível ou excluir a despesa original é rejeitado atomicamente. Ajustar os vínculos primeiro. Mesclar pessoas transfere vínculos e preserva o nome anterior como outro nome.

Recorrências e séries de despesas por conta: cadastrar primeiro a série e vincular reembolsos a um lançamento individual; uma obrigação não é replicada automaticamente. No escopo de edição de próximas despesas, editar o reembolso somente neste lançamento. Compras parceladas no cartão podem vincular uma obrigação ao total da compra. Empréstimos e demais valores a pagar/receber não são automaticamente convertidos em reembolsos; a integração futura com esses módulos será detalhada separadamente.

## Persistência

Schema 17 aditivo: `people`, `reimbursements`, `reimbursement_receipts`. Sem alteração do valor da despesa e sem netear relatórios. Integração ao conjunto financeiro, validação de vínculos, backup/restore e triggers de sync; pacotes financeiros históricos 11–16 continuam legíveis, sem aceitar entidades de reembolso em schemas antigos. Fila pendente recebe novo identificador/schema; cores de cartão já presentes em schema 16 são preservadas. Atualizar os dois dispositivos antes de sincronizar.

## Arquivos

Migration/integridade em `lib/core/database`; domínio, repositório e telas em `lib/features/reimbursements`; integração ao draft/formulário e repos de transações/cartões; DI, rotas, menu e Configurações; workflow de prévias. Testes em `test/features/reimbursements`.

## Validação conjunta

1. Despesa de R$ 100 com uma pessoa devendo R$ 40: salvar, conferir a despesa integral e saldo sem entrada adicional.
2. Receber R$ 15 e R$ 25: conferir receitas separadas, saldo, recebido e pendência.
3. Vincular uma receita existente: conferir que nada é duplicado; tentar vincular novamente.
4. Agendar recebimento futuro, efetivar hoje, desfazer e excluir: conferir realizado e valores a receber.
5. Tentar exceder a obrigação, reduzir a despesa abaixo dos vínculos ou excluir sua origem: erro e dados preservados.
6. Mais de uma pessoa, arquivamento/reativação, outros nomes, mesclagem e filtro do histórico.
7. Compra parcelada no cartão: obrigação sobre a compra, fatura inalterada e receita creditada na conta.
8. Backup/restauração, sync após atualização de ambos, Android/Windows, teclado e opções recolhidas.

Verificação técnica e pacotes serão registrados na #67; validação manual pendente.
