# Dívidas e empréstimos — #65

Entrega da v0.3.0-alpha, autorizada em 06/10/2026 após validação de Bens e patrimônio. Usuário escolheu informar manualmente quanto de cada parcela amortiza o principal.

## Uso e cálculo

Acesso: **Investimentos → Dívidas e empréstimos**. Cadastre nome, credor, tipo (empréstimo, financiamento ou outra dívida), saldo inicial, data de referência e observações. BRL nesta entrega. Cadastro não gera entrada do empréstimo nem despesas; registre os movimentos de caixa nas telas habituais quando aplicável.

O saldo inicial é o principal ainda devido na referência, sem somar juros futuros. Vincule somente pagamentos não descontados desse saldo, com data igual ou posterior à referência. Para financiar um bem já cadastrado, selecione-o na criação: o saldo inicial é sugerido a partir de seu financiamento manual, mas deve ser conferido na data escolhida. O vínculo é permanente nesta entrega e cada bem aceita uma dívida cadastrada. Não cadastre novamente a mesma dívida em outra ficha ou cartão.

**Vincular parcela / despesa** permite buscar despesas existentes em BRL, inclusive parcelas e recorrências. A parcela mantém seu valor integral no caixa e relatórios. Exemplo: parcela R$ 500, amortização R$ 350, juros/encargos R$ 150. Vincular não cria nem efetiva uma despesa. Cadastre uma nova parcela na tela Despesas e depois vincule-a. Cartões e transferências não são elegíveis. Cada despesa pode ter um único vínculo ativo; amortização zero é permitida para pagamento somente de encargos.

- Saldo atual = saldo inicial − principal de despesas vinculadas, não excluídas e efetivadas até hoje.
- Saldo projetado = saldo inicial − principal de todas as despesas vinculadas não excluídas, incluindo previstas e efetivações futuras. É projeção das parcelas cadastradas, não cotação bancária nem cronograma automático.
- A soma das amortizações vinculadas não pode exceder o saldo inicial; cada amortização não pode exceder o valor da despesa. Não estimar automaticamente juros, SAC, Price, IOF ou desconto por antecipação.
- Efetivar, desfazer efetivação, mudar data e excluir despesa reflete no saldo sem gravar uma segunda movimentação. Vínculo com despesa excluída fica visível, mas não amortiza nem reserva principal.
- **Desvincular parcela** mantém a despesa e guarda o vínculo antigo como histórico, com valor, descrição e data registrados no vínculo; edições posteriores não reescrevem esse registro. Para corrigir amortização, desvincule e vincule novamente.
- Alterações incompatíveis da despesa (valor menor que principal, receita, outra moeda ou data anterior à referência) são rejeitadas com rollback. Desvincule antes de alterar.
- Saldo inicial e referência ficam imutáveis após o primeiro vínculo, mesmo desvinculado; metadados podem ser editados. Não há exclusão de dívida nesta entrega, preservando seus vínculos históricos. Saldo atual zero indica quitação.

## Patrimônio e bens

Contas BRL (inclui investimentos uma vez) + bens ativos + créditos dos cartões − financiamentos dos bens − outras dívidas cadastradas − dívidas dos cartões.

Uma dívida vinculada ao bem **substitui** o financiamento manual de sua última avaliação. Os valores manuais históricos continuam intactos. Novas avaliações alteram somente o valor do bem e orientam atualizar financiamento em Dívidas e empréstimos. Retirar o bem do patrimônio mantém a dívida até quitação. Empréstimos sem bem entram no resumo como outras dívidas. O resumo exclui moedas estrangeiras e dívidas não cadastradas.

## Dados, backup e sincronização

Migration aditiva **15**, tabelas `debts` e `debt_payments`, UUIDs, centavos inteiros, tombstones e índices únicos para bem/despesa. Backup antes de migration já integra o fluxo padrão. Nenhum dado existente é convertido em dívida automaticamente. Uploads pendentes v11–v14 recebem schema 15 e novas identidades; pacotes históricos continuam legíveis com digest preservado. Dívidas em pacotes de schema anterior a 15 são rejeitadas. Restore/sync validam integridade, valores, moedas, referência e principal com rollback.

Atualize **Android e Windows antes de sincronizar**. Formulários usam calculadora, proteção de alterações não salvas, bloqueio durante gravação e preservação dos campos em erros; Android em tela cheia e Windows em diálogo.

## Validação manual

1. Atualizar ambos os dispositivos; cadastrar empréstimo e conferir que caixa não muda.
2. Vincular despesa prevista de R$ 500 com R$ 350 de principal; atual não muda e projetado cai R$ 350.
3. Efetivar e desfazer em Despesas, voltando à tela de dívidas; principal acompanha e caixa muda somente pelo valor integral.
4. Excluir despesa, conferir saldo recomposto e vínculo histórico; desvincular e vincular outra parcela.
5. Tentar principal acima da parcela/saldo, despesa repetida e data anterior; confirmar bloqueios e dados preservados.
6. Vincular financiamento a bem e conferir que patrimônio não duplica seu saldo anterior; retirar/reincluir bem e atualizar avaliação.
7. Quitação exata e parcela só de encargos (principal zero).
8. Backup/restauração e sync Android↔Windows: valores e vínculos iguais sem duplicação.

## Inventário da implementação

- `lib/features/debts/domain/debt.dart`: modelos e contratos; cálculo separado de principal/encargos e atual/projetado.
- `lib/features/debts/data/sqlite_debts_repository.dart`: cadastro, seleção/vínculo de despesas e histórico.
- `lib/features/debts/presentation/debts_page.dart`, `debt_forms.dart`: lista, resumo, cadastro e vínculo pesquisável.
- `lib/core/database/schema_v15.dart`, `debt_integrity.dart`, `app_database.dart`, `financial_data.dart`: migration, integridade, snapshots e captura sync.
- `lib/core/sync/sync_packet.dart`: compatibilidade v11–v14 e bloqueio de dívidas legadas.
- `lib/core/di/injection.dart`, `lib/core/routing/app_router.dart`, `somia_shell.dart`: DI, rota e voltar Android.
- `lib/features/investments/presentation/investments_page.dart`: acesso à feature.
- `lib/features/transactions/data/sqlite_transactions_repository.dart`: validação atômica de alterações nas parcelas vinculadas.
- `lib/features/assets/domain/asset.dart`, `data/sqlite_assets_repository.dart`, `presentation/asset_form.dart`, `assets_page.dart`: dívida controlada e patrimônio sem repetição.
- `test/features/debts/debts_repository_test.dart`, `debts_page_test.dart`, `test/core/database/schema_v15_test.dart`: amortização, reversões, datas, rollback, patrimônio, restore/sync, migration e formulários Android/Windows.
- `test/core/database/schema_v14_test.dart`: expectativa da versão atual ao abrir legado.
- `.github/workflows/flutter-ci.yml`: geração e publicação de prévias de dívidas/formulários.
- `README.md`, `CHANGELOG.md`, `docs/ciclos/v0.3.0-alpha.md` e este documento: regras, inventário e validação.

A #65 permanece aberta até validação manual. Demais dívidas avançadas, moedas e cotações seguem na #15; nenhuma release antecipada.
