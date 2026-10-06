# Bens e patrimônio — v0.3.0-alpha (#64)

## Acesso e cadastro

Menu → Investimentos → Bens e patrimônio. Novo bem permite cadastrar veículo, imóvel ou outro bem com nome, data e valor de aquisição, valor atual, data da avaliação, saldo devedor do financiamento, credor e observações. Datas são entre 1900 e hoje; a avaliação não pode anteceder a aquisição. Valores são centavos inteiros não negativos, inclusive zero, com calculadora. Credor obrigatório para dívida positiva. Dívida maior que valor do bem é permitida e aparece como patrimônio negativo.

Cadastro declara um bem que você possui; não gera despesa, receita, transferência ou segundo saldo de conta. Aquisição não é usada como valor atual automaticamente: informe a avaliação atual. Compra, venda, financiamento e pagamentos devem continuar registrados nas telas de lançamentos, quando apropriado.

Editar bem altera somente nome/tipo, aquisição e observações. Data de aquisição não pode ultrapassar avaliações existentes. Atualizar avaliação registra novo valor do bem e saldo do financiamento na data escolhida. O saldo do financiamento deve ser o informado pelo banco, sem somar juros futuros nem repetir dívida do cartão.

## Avaliações e financiamento

Cada atualização é um registro independente no histórico. O resumo usa a avaliação de data mais recente; na mesma data, o registro mais recente prevalece, com desempate determinístico. Uma avaliação retroativa complementa o histórico e não substitui uma avaliação posterior. Valores atuais desatualizados por outra alteração são rejeitados até recarregar a tela. Avaliação também pode atualizar apenas o saldo devedor mantendo o valor do bem.

Parcelas agendadas/pagas do controle de despesas não reduzem automaticamente o financiamento: nenhuma equivalência entre valor da parcela e amortização do principal é presumida. Amortização automática e gestão geral de empréstimos são entregas futuras da #15.

Retirar do patrimônio preserva o bem e avaliações, remove seu valor da soma de bens, mas mantém o financiamento na soma de dívidas até informar saldo zero. É possível atualizar a dívida de um bem retirado ou reincluí-lo. Venda não cria receita, quitação não debita conta e retirada não apaga dívida. Registre caixa separadamente.

## Resumo

Patrimônio líquido cadastrado = contas em BRL + bens ativos + créditos nos cartões − saldo de financiamento de todos os bens cadastrados − dívidas nos cartões.

Investimentos entram uma única vez pelo saldo das contas vinculadas, inclusive contas fora do saldo mensal e arquivadas com saldo. Bens não são contas. Cartões usam o compromisso total líquido dos lançamentos/pagamentos realizados, incluindo parcelas futuras e cartões arquivados; não somam saldos acumulados de cada fatura. Agendamentos não são pagamentos realizados. Outras moedas e dívidas não cadastradas ficam fora deste total; o título identifica patrimônio cadastrado.

Não repetir o financiamento do bem no saldo devedor manual se ele já está representado nas compras do cartão. O campo explica essa regra antes de salvar.

## Persistência e integridade

Migration aditiva v14: `assets` e `asset_valuations`, com IDs independentes, vínculo FK, campos de metadados/sync e índice de histórico. Valores, tipos e datas têm restrições SQL. A validação financeira de backup/sync verifica vínculos, credor obrigatório, avaliações anteriores à aquisição e ausência de avaliação de bem ativo. Operações são transacionais; falha no cadastro inicial desfaz também o bem.

Backups anteriores são migrados preservando contas, investimentos e transações. Pacotes sync v11, v12 e v13 continuam legíveis com digest histórico preservado; tabelas de bens são rejeitadas nesses protocolos antigos. Uploads ainda pendentes ganham schema 14 e nova identidade, preservando conteúdo e relógios. Atualizar Android e Windows antes de sincronizar esta entrega.

## Inventário de alterações

| Arquivos | Finalidade |
| --- | --- |
| `lib/features/assets/domain/asset.dart` | Modelos, avaliações e fórmula do patrimônio. |
| `lib/features/assets/data/sqlite_assets_repository.dart` | Cadastro, histórico, avaliação manual, retirada, totais de contas/cartões e validação transacional. |
| `lib/features/assets/presentation/asset_form.dart` | Formulários de cadastro/edição/avaliação, datas, calculadora, credor, preservação de campos e bloqueio durante gravação. |
| `lib/features/assets/presentation/assets_page.dart` | Resumo, cards dos bens, histórico, atualização e confirmação de retirada/reinclusão. |
| `lib/features/investments/presentation/investments_page.dart` | Entrada Bens e patrimônio. |
| `lib/core/routing/app_router.dart`, `somia_shell.dart`, `lib/core/di/injection.dart` | Rota, menu selecionado, voltar Android para Investimentos e injeção do repositório. |
| `lib/core/database/schema_v14.dart`, `app_database.dart`, `financial_data.dart` | Migration 14, fila pendente, captura e validação financeira de bens. |
| `lib/core/sync/sync_packet.dart` | Compatibilidade v11–v13 e rejeição de bens em pacote antigo. |
| `test/features/assets/assets_repository_test.dart`, `assets_page_test.dart`, `test/core/database/schema_v14_test.dart` | Regressões financeiras, histórico, dívida/retirada, rollback, sync idempotente, migração e layouts/formulários Android/Windows. |
| `test/core/database/schema_v13_test.dart` | Teste histórico compara com versão atual após atualizar. |
| `.github/workflows/flutter-ci.yml` | Prévia de bens Android/Windows incluída na CI e artifacts. |
| `README.md`, `CHANGELOG.md`, `docs/ciclos/v0.3.0-alpha.md`, este documento | Acesso, regras, inventário e validação. |

## Roteiro manual

1. Atualizar Android/Windows; conferir contas, investimentos, cartões e backup anteriores.
2. Em Investimentos → Bens e patrimônio, cadastrar um veículo, imóvel e outro bem. Conferir datas, calculadora, aquisição/valor atual distintos e credor obrigatório.
3. Conferir total de contas sem duplicar investimentos, valor dos bens e dívida; cadastrar bem financiado com dívida maior que valor atual.
4. Atualizar valor e financiamento, salvar duas avaliações no mesmo dia e uma retroativa; conferir histórico e resumo.
5. Retirar bem financiado: valor sai, dívida permanece. Atualizar financiamento para zero e reincluir; conferir histórico preservado.
6. Editar metadados; rejeitar aquisição posterior à avaliação. Cancelar formulário alterado e conferir proteção; erro preserva campos.
7. Exportar/restaurar backup e sincronizar; conferir bens, avaliações, dívida, status e total nos dois dispositivos.
8. Confirmar que cadastros/avaliações não geram movimentos de caixa automaticamente.

A #64 permanece aberta até aprovação do usuário. Demais pendências da #15 seguem no ciclo.
