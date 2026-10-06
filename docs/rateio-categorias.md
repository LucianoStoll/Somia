# Rateio por categoria — #60

Entrega da `v0.3.0-alpha`, epic #11; melhorias de formulário relacionadas à #59.

## Uso

Ao criar ou editar uma receita, despesa ou compra no cartão, ative **Dividir entre categorias**. Escolha pelo menos duas categorias/subcategorias distintas, do mesmo tipo do lançamento. Use **Por valor** ou **Por percentual** e adicione/remova partes conforme necessário, até 100 partes.

Por valor, as partes devem somar exatamente o total. **Redistribuir pelo total** ajusta os valores proporcionalmente quando o total mudar. Por percentual, a soma precisa ser 100%, com até duas casas decimais. O app converte para unidades monetárias menores e distribui os centavos restantes pelas maiores frações; empates seguem a ordem das partes.

Salvar mantém um único lançamento. O rateio aparece na edição, nas etiquetas da lista, nos detalhes das compras e no extrato. Categoria/subcategoria única continuam disponíveis quando o rateio estiver desativado. Cancelar mantém os dados originais; alterações de partes participam da proteção de formulário não salvo.

## Regras financeiras

- Rateio é classificação interna, sem nova movimentação de caixa.
- Saldo, totais mensais e pagamento da fatura continuam usando o valor do lançamento original uma única vez.
- O gráfico de despesas por categoria distribui os valores; subcategorias são agrupadas na categoria principal. Filtros de categoria encontram também partes do rateio. A lista de despesas mantém uma linha por fatura de cartão.
- Percentuais são preservados ao reabrir a edição, alterar o total pela lista e criar parcelas. Rateios por valor usam proporção das partes existentes em alterações rápidas de total.
- Recorrências repetem a classificação em cada ocorrência; parcelas redistribuem as partes por valor da parcela, mantendo a soma exata de cada ocorrência. Edição em série segue a proteção já existente de efetivados/faturas com pagamento.
- Em valores muito pequenos, algumas partes podem ficar com zero centavos, preservando categorias/percentuais e a soma total.
- Estornos de cartão recebem distribuição proporcional e valores de classificação com sinal negativo nos gráficos; antecipação preserva as partes da compra.
- Categorias arquivadas do histórico podem ser mantidas ao editar. Novos vínculos exigem categorias ativas. Trocar o tipo de uma categoria usada em rateios é bloqueado.
- Rateio de categorias não cria pessoas nem recebimentos de reembolso; esses são as próximas entregas da #11.

## Persistência e atualização

Migration **v12** adiciona `allocations_json` em `transactions` e `card_entries`, com `[]` como padrão. Cada parte guarda categoria, valor inteiro e, quando aplicável, percentual em centésimos de ponto percentual. O payload pertence ao registro principal, para edição e conflito de sincronização atômicos. Dinheiro usa unidades menores inteiras; multiplicações proporcionais usam BigInt para evitar overflow.

Backup/restauração e sincronização financeira incluem os novos campos. A validação compartilhada rejeita JSON inválido, somas divergentes, categorias ausentes/de outro tipo e uso simultâneo de categoria única/rateio, preservando os dados atuais no rollback.

Na atualização, os snapshots da fila/histórico de sincronização ganham o campo vazio; pacotes locais ainda não confirmados são preparados na nova versão com nova identidade e clocks preservados. Triggers são recriados para capturar os novos campos. Pacotes remotos históricos v11 continuam legíveis com classificação vazia e digest original; novos pacotes usam v12. **Atualize Android e Windows antes de usar rateio com sincronização**, pois a alpha anterior não lê o schema novo. As migrations possuem cópia de proteção anterior à atualização.

## Arquivos alterados

| Área | Arquivos / finalidade |
| --- | --- |
| Rateio | `lib/core/allocations/category_allocation.dart`, `allocation_store.dart`, `allocation_editor.dart`: modelo, precisão, validação de vínculos e formulário. |
| Banco | `lib/core/database/schema_v12.dart`, `app_database.dart`, `financial_data.dart`: migration, migração da fila, captura e consistência financeira. |
| Sync | `lib/core/sync/sync_packet.dart`: leitura dos pacotes históricos sem alterar digest. |
| Lançamentos | Modelo `financial_transaction.dart`, repository SQLite e `transactions_page.dart`: salvar/editar, séries, filtros, edição rápida e formulário. |
| Cartões | `credit_card.dart`, `cards_repository.dart`, `cards_page.dart`: partes nas compras/parcelas, edição, estorno e exibição. |
| Análises | `sqlite_dashboard_repository.dart`, `account_statement_repository.dart`: distribuição dos gráficos e identificação no extrato. |
| Categorias | `sqlite_categories_repository.dart`: proteção do tipo das categorias já usadas em rateios. |
| Testes / CI | `category_allocations_test.dart`, `schema_v12_test.dart`, `allocation_editor_test.dart` e workflow: regressões financeiras, migration/fila, formulários e prévias mobile/desktop. |
| Documentação | Este roteiro, changelog, README e documento do ciclo. |

## Validação manual pendente

- [ ] Atualizar Android e Windows sobre as instalações existentes; conferir dados anteriores.
- [ ] Receita/despesa: distribuir por valor e por percentual, salvar, reabrir e conferir partes.
- [ ] Conferir soma inválida, percentual diferente de 100%, categorias repetidas e subcategorias.
- [ ] Alterar total pelo formulário e pela calculadora da lista; conferir proporções/centavos.
- [ ] Efetivar/desfazer e conferir saldo/totais sem duplicação, gráfico e filtro de categoria.
- [ ] Criar recorrência e parcelamento; editar somente esta/próximas e conferir ocorrências.
- [ ] Cartão: compra parcelada rateada, detalhes, estorno, antecipação e pagamento da fatura.
- [ ] Cancelar alteração de partes e conferir proteção de formulário.
- [ ] Backup/restaurar com app aberto e sync Android ↔ Windows, incluindo edição offline de partes.
- [ ] Conferir layout/rolagem no Android e Windows, teclado de percentual e texto ampliado.

Resultados automatizados e links dos builds são registrados na #60. A aprovação do CI não encerra a validação manual.
