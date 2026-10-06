# Cartões e faturas — #47 / epic #12

Regras aprovadas em 03/10/2026. Branch `v0.2.0-alpha`; Android e Windows; offline. Validação manual pendente.

## Cadastro e começo do controle

Menu Cartões: nome personalizado, instituição do catálogo, conta padrão de pagamento em BRL, dias de fechamento/vencimento e limite opcional. Limite independente e histórico de alterações. Arquivar impede novas compras; faturas/pagamentos/histórico continuam acessíveis. Reativação disponível.

Saldo inicial da fatura é o valor **ainda não pago**. Aceita crédito negativo, compromete o limite e projeta a conta, mas não repete gastos antigos nos relatórios. Parcelas futuras são cadastradas como compras em Despesas, informando quantidade restante, número da primeira parcela restante e fatura de início. Não colocar a mesma dívida no saldo inicial e nas compras detalhadas.

## Compras e faturas

Formulário de Despesas escolhe Conta ou Cartão, mantendo descrição, calculadora, categoria/subcategoria. Compra no cartão não debita a conta. À vista ou parcelas mensais, por total ou valor individual; divisão exata em centavos, 2 a 1000 parcelas e datas até 2100. Recorrências gerais continuam nas contas; cartão recebe compras à vista/parceladas nesta entrega.

Fatura é identificada pelo **mês do vencimento**. Fechamento anterior ao vencimento; quando dia do vencimento <= fechamento, fecha no mês anterior. Dias inexistentes usam último dia disponível. Compra no próprio dia de fechamento entra na próxima fatura. Datas reais podem ser ajustadas por fatura, mantendo a ordem dos ciclos; ajustes não redistribuem automaticamente compras já registradas. Compra pode mudar de fatura manualmente.

Editar/excluir somente esta ou esta e próximas preserva anteriores e faturas com pagamentos, inclusive agendados. Para corrigir compra numa fatura paga/parcial, use estorno. Compras com estorno ou antecipação registrada também preservam o histórico na exclusão; cancele seu saldo restante por estorno. Não converter um lançamento de conta existente em compra de cartão; crie a compra correta para manter histórico. Alterar dias do cadastro vale para faturas ainda não materializadas; existentes conservam datas reais.

## Fatura na lista de despesas

Despesas mostra uma linha “Cartão - nome” por cartão e fatura, com etiqueta azul de fechamento e vencimento, com o total completo e o saldo restante após pagamentos parciais. Tocar no nome ou valor abre o cartão no mês correspondente; os lançamentos ficam separados nessa tela. O filtro de categoria encontra faturas com aquela categoria e mantém o total completo, indicado na etiqueta. Conta filtra pela conta padrão de pagamento.

O ícone pendente paga o saldo restante hoje pela conta padrão. Pagamentos futuros da mesma fatura são antecipados para hoje, sem criar débito duplicado. O feedback de 5 segundos permite desfazer exatamente essa ação (restaurando os agendamentos) ou ajustar a data. Uma fatura efetivada permite desfazer seu último pagamento com confirmação; os pagamentos anteriores ficam preservados. Crédito sem pagamento não oferece desfazer. Totais derivados da fatura são alterados pelos lançamentos dentro do cartão.

Validar: duas compras no mesmo mês aparecem em uma linha; abrir pelo valor mostra ambas; pagamento parcial mantém total e mostra restante; efetivar quita somente restante; desfazer restaura parcial/agendamentos; após expirar o feedback, desfazer último pagamento pede confirmação. Saldo da conta e relatórios não duplicam gastos.

## Limite, liquidações, crédito e antecipação

Compromisso = soma de todas as parcelas/encargos/créditos ativos − pagamentos realizados. Comprometido mínimo zero; negativo é saldo credor separado. Disponível = limite − comprometido; crédito não altera o valor cadastrado do limite. Exceder limite avisa e permite continuar. Pagamento futuro não libera limite atual.

Pagamento registra conta de origem, valor efetivamente debitado e data real; juros/multa/acréscimos e desconto são ajustes separados da dívida. É possível pagar parcial, antecipado ou a maior. A conta padrão é só referência; outra conta pode pagar. Desfazer pagamento restaura saldo da conta/dívida e desfaz encargos/desconto vinculados.

Saldo da fatura = saldo anterior + itens ativos − pagamentos realizados da fatura. O restante segue à próxima como saldo derivado, **sem criar outra despesa ou copiar a dívida**. Fatura anterior mantém histórico e pagamentos associados. Crédito segue entre faturas. Pagamentos futuros aparecem separados como agendados.

Antecipar permite selecionar parcelas futuras sem pagamentos do mesmo cartão, trazer para fatura sem pagamentos e informar desconto menor que o total selecionado. Mudança de fatura preserva índice, vínculo da compra e histórico; desconto é crédito separado. Estorno pode ser parcial e ir à fatura escolhida, limitado ao total não estornado da compra.

## Contas, dashboard e visões

Conta atual debita somente pagamentos realizados até a referência. Projeção inclui agendamentos e dívida restante até o período escolhido na conta padrão, reduzindo o previsto pelos pagamentos do cartão; cada valor aparece uma única vez. Antecipação muda o mês da projeção. Contas excluídas do consolidado mantêm os valores individuais.

Dashboard mantém o critério mensal atual para lançamentos de conta. Para cartão, despesas por categoria são itens líquidos do mês de vencimento/competência da parcela, excluindo saldo inicial. Pagamento de fatura não é nova despesa. Cartões exibe **Competência / fatura** (itens, saldo anterior e liquidações vinculadas) e **Caixa / pagamentos** (débitos pela data real no mês, mesmo se vinculados a fatura diferente). Dívida carregada não entra novamente nos gráficos.

## Persistência

Migration aditiva v10: cartões, histórico de limite, faturas, itens, liquidações e histórico de edição/mudança de fatura. Compras e liquidações são tabelas próprias; vínculos com contas/categorias preservados. Operações de série, antecipação, pagamento com ajustes e desfazimento são transacionais. Backup SQLite inclui todas as entidades; restauração migra backups anteriores.

Importação, compras internacionais e adicionais permanecem na epic #12 para entregas futuras.

## Validação manual

1. Atualizar APK sobre anterior e conferir contas, logos e séries existentes.
2. Cadastrar dois cartões; editar limite, conferir histórico, arquivar e reativar.
3. Cadastrar saldo inicial da fatura atual e só as parcelas restantes de uma compra antiga, evitando repetir valores.
4. Em Despesas, criar compra à vista e R$100,01 em 3 parcelas; verificar soma, índice, faturas e limite total.
5. Conferir compra antes/no/depois do fechamento, dias 29/30/31, ajuste real de fechamento e mudança manual de fatura.
6. Conferir conta sem débito ao comprar, previsão correta e despesa uma vez no dashboard.
7. Pagar parte, com encargos/desconto, por outra conta; conferir histórico, saldo restante na próxima, limite e caixa.
8. Agendar pagamento futuro: atual e limite não mudam; previsão evita duplicação. Desfazer e conferir restauração.
9. Antecipar parcelas selecionadas com desconto; verificar novas faturas e histórico.
10. Estornar parcialmente uma compra paga e pagar a maior; conferir crédito e próximas faturas.
11. Editar/excluir isolado/próximos, preservando os pagamentos registrados; cancelar/Voltar sem alterações.
12. Exportar/restaurar backup e conferir cartões, faturas, parcelas, pagamentos e limite.

## Correção de compras em faturas com pagamentos — 06/10/2026

Uma compra cadastrada no mês errado pode ser editada, movida para outra fatura ou excluída mesmo quando a fatura possui pagamentos. A correção altera apenas a compra: os pagamentos mantêm identificador, valor, conta e data. Os saldos das faturas e as projeções são recalculados; eventual pagamento excedente permanece como crédito. Edições e exclusões são registradas no histórico. Estornos e antecipações vinculados continuam impedindo exclusão para preservar seus vínculos.

Ao escolher fatura automática na edição, o mês é recalculado pela data da compra e pelo fechamento do cartão. A opção de editar esta e as próximas aplica a correção às parcelas seguintes, preservando as anteriores e todos os pagamentos. Para devolução/reembolso real, permanece a ação Estornar.

Regressão: compra inserida indevidamente após a quitação, mudança de data/valor/fatura, exclusão do lançamento errado, preservação do pagamento e do saldo realizado da conta; edição das próximas com pagamento agendado.
