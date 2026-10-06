# Investimentos — CDB/CDI e poupança

Primeira entrega de investimentos da v0.3.0-alpha: #62, epic #15 e experiência #59. O usuário escolheu **informar manualmente o rendimento ou o saldo do banco**. Outros tipos serão avaliados depois.

## Usar no app

Menu **Investimentos → Nova aplicação**. Informe nome, tipo (CDB, conta remunerada/CDI ou poupança), instituição, vencimento opcional e observações. CDI identifica a referência da remuneração da conta/produto; não há cotação ou cálculo automático de juros, impostos ou rentabilidade estimada.

Você pode vincular uma conta ativa em BRL já cadastrada ou criar uma conta dedicada. **Uma aplicação representa todo o saldo da conta**, e cada conta tem no máximo uma aplicação. Para cadastrar várias aplicações de uma instituição, use contas distintas. Vincular uma conta existente preserva saldo, movimentos e suas configurações, sem criar uma segunda posição financeira.

A nova conta usa tipo Investimento ou Poupança e começa fora do saldo do mês. O usuário pode alterar essa opção em Contas. “Saldo já existente” é saldo de abertura, usando a mesma regra das contas atuais: não tem data de efetivação nem gera receita/transferência. Se o dinheiro ainda vai sair de outra conta, deixe zero e registre o aporte. O vencimento é informativo e não dispara resgate nem rendimento.

## Operações manuais

| Ação | Registro | Efeito |
| --- | --- | --- |
| Aporte | Transferência da outra conta para a aplicação | Redistribui dinheiro sem criar despesa. |
| Resgate | Transferência da aplicação para outra conta | Redistribui dinheiro sem criar receita. |
| Rendimento | Receita efetivada na conta vinculada | Aumenta o saldo e as receitas realizadas. Informe o valor creditado pelo banco. |
| Saldo do banco | Ajuste positivo/negativo pelo valor da diferença | Corrige o saldo realizado sem presumir que a diferença seja rendimento ou despesa de consumo. Fica fora dos gráficos de receitas/despesas. |

Todas as operações exigem data passada ou atual e contas ativas em reais. Aporte/resgate precisam de outra conta. Resgate acima do saldo realizado **na data escolhida** é recusado. Valores usam centavos inteiros e o limite monetário existente. Aporte pode usar conta de origem negativa, como nas transferências atuais do app.

Ao informar o saldo do banco, primeiro registre aportes, resgates e demais movimentos. A confirmação mostra saldo no Somia na data escolhida, saldo informado e diferença. Cancelar não grava. Se o saldo mudar durante a confirmação, a gravação é recusada para uma nova conferência. Saldos iguais não criam lançamentos; zero é aceito. Ajustar uma data anterior não sobrescreve movimentos posteriores. O ajuste é uma movimentação incremental: alterações posteriores no histórico financeiro podem exigir nova conciliação.

Não informe o mesmo ganho em “Rendimento” e novamente como ajuste sem conferir a diferença. A conferência usa o saldo já atualizado para evitar repetir a correção.

## Saldo, histórico e patrimônio

O saldo da aplicação vem da consulta financeira compartilhada com Contas: efetivação determina o realizado, e pendências não entram no saldo atual. O botão **Ver extrato** abre os detalhes da conta, com os lançamentos e transferências existentes. A edição/exclusão desses movimentos permanece disponível nas seções próprias. Alterar nome/tipo/instituição/vencimento/observações não recria a conta nem muda os movimentos; o vínculo não pode ser trocado após o cadastro.

“Saldo atual das aplicações” soma cada conta vinculada uma vez. “Total em contas (BRL)” soma todas as contas em reais uma vez, incluindo aplicações e contas arquivadas, independentemente de “incluir no saldo do mês”. Esse total não é apresentado como patrimônio líquido: bens, financiamentos, empréstimos e demais dívidas ainda pertencem às próximas entregas da #15. Outras moedas não são convertidas neste módulo.

Arquivar/reativar uma aplicação arquiva/reativa sua conta vinculada após confirmação. Saldo e histórico permanecem; contas arquivadas recusam novas operações. Não existe exclusão destrutiva do cadastro neste fluxo.

## Dados, atualização e sincronização

Migration aditiva **v13** adiciona `investments` e vínculo único com `accounts`. Não altera valores nem os campos de rateio existentes. A aplicação participa da captura automática de alterações, backups e restauração validada. A troca de moeda de contas vinculadas é bloqueada mesmo sem movimentação.

Pacotes históricos v11/v12 continuam legíveis, preservando o digest original. A fila de upload anterior é reencaminhada para v13 com novas identidades, mantendo dados, relógios e histórico. Pacotes antigos não podem conter a tabela nova. Atualize **Android e Windows** antes de sincronizar esta entrega. Integridade financeira valida moeda, vínculos e duplicação; operações e rollback incluem as entidades envolvidas.

## Telas e campos

Novo item no drawer/sidebar; resumo e lista de aplicações; cadastro/edição; aporte; resgate; rendimento; saldo do banco com confirmação; arquivamento/reativação e acesso ao extrato. Android usa formulário em tela cheia; Windows usa diálogo. Campos monetários abrem a calculadora; cancelar preserva valores. Erros mantêm o formulário preenchido. Campos têm espaçamento, rolagem e proteção de alterações não salvas.

## Validação

Testes novos cobrem vínculo sem duplicação, transferências, rendimentos, ajustes positivos/negativos/zero, repetição e concorrência, datas passadas/futuras, pendências, limites, arquivamento, câmbio bloqueado, rollback, backup/restauração, sync e migration v12 → v13. Testes de interface cobrem confirmação/cancelamento, erros sem perda dos campos, conta existente e telas Android/Windows, incluindo fonte ampliada. A CI gera prévias e pacotes.

### Roteiro manual

1. Atualizar Android/Windows preservando dados e conferir contas/rateios anteriores.
2. Vincular uma conta de aplicação já existente: saldo não deve mudar nem duplicar.
3. Criar aplicação com saldo zero, fazer aporte de R$ 100,01 e resgate de R$ 33,33; total em contas deve permanecer igual.
4. Registrar R$ 1,23 de rendimento; conferir conta, receitas e extrato.
5. Informar o saldo bancário com diferença positiva e negativa, cancelar uma confirmação e conferir saldo zero/igual; ajustes não devem aparecer como consumo/rendimento nos gráficos.
6. Ajustar uma data passada com movimentos posteriores e conferir saldo histórico/atual.
7. Arquivar/reativar; conferir formulário com teclado, calculadora, texto ampliado e janela estreita.
8. Exportar/restaurar backup e sincronizar os cadastros e movimentos entre os dispositivos atualizados.

A #62 permanece aberta até validação manual. Esta entrega não encerra toda a epic #15 nem publica a release do ciclo.

## Inventário da entrega

- `.github/workflows/flutter-ci.yml`
- `CHANGELOG.md`
- `README.md`
- `docs/ciclos/v0.3.0-alpha.md`
- `docs/investimentos.md`
- `lib/core/database/app_database.dart`
- `lib/core/database/financial_data.dart`
- `lib/core/database/schema_v13.dart`
- `lib/core/di/injection.dart`
- `lib/core/routing/app_router.dart`
- `lib/core/routing/somia_shell.dart`
- `lib/core/sync/sync_packet.dart`
- `lib/features/accounts/data/sqlite_accounts_repository.dart`
- `lib/features/investments/data/sqlite_investments_repository.dart`
- `lib/features/investments/domain/investment.dart`
- `lib/features/investments/presentation/investment_forms.dart`
- `lib/features/investments/presentation/investments_cubit.dart`
- `lib/features/investments/presentation/investments_page.dart`
- `test/core/database/schema_v12_test.dart`
- `test/core/database/schema_v13_test.dart`
- `test/features/investments/investments_page_test.dart`
- `test/features/investments/investments_repository_test.dart`

A conferência integrada também ajusta os testes existentes de fechamento do detalhamento de saldo para comparar o número de barreiras com a tela inicial, preservando as verificações de fechamento/reabertura e ausência da rota do painel. Arquivo: `test/features/dashboard/balance_details_panel_test.dart`.
