# Baixas parciais

Entrega da epic #11 para receitas e despesas de conta na v0.3.0-alpha.

Na lista de lançamentos, abra o menu de três pontos e escolha **Baixas e histórico**. Informe o valor, a conta e a data do pagamento ou recebimento. A conta pode ser diferente da original, desde que use a mesma moeda. Datas futuras ficam previstas até o dia escolhido.

O lançamento mantém seu valor total, lançamento e vencimento. Cada baixa afeta apenas a conta escolhida; o restante continua pendente na conta original. Quando a soma das baixas realizadas atingir o total, o lançamento aparece como efetivado. A lista mostra o total baixado e o restante. O histórico permite desfazer uma baixa e recuperar a pendência correspondente.

Se o lançamento já estiver efetivado integralmente, marque-o como pendente antes de registrar baixas. Após registrar baixas, gerencie a efetivação pelo histórico. Alterações que excedam o novo total, mudem o tipo ou tornem o rateio incompatível são rejeitadas. Desfazer e registrar novamente permite corrigir valor, conta ou data de uma baixa.

Saldos, extratos, dashboard e planejamento usam as baixas e o restante sem repetir o total original. O rateio distribui centavos exatamente entre as categorias, preservando o total de cada categoria. Receitas vinculadas a reembolsos dividem os recebimentos realizados e o restante agendado.

Despesas vinculadas à amortização de dívida precisam ser desvinculadas antes de usar baixas parciais. O principal da dívida ainda segue o fluxo de amortizações integrais. Compras e faturas de cartão continuam usando seus pagamentos próprios.

Schema 19 adiciona o histórico normalizado de baixas, incluído nos backups e na sincronização. Atualize os dois dispositivos antes de sincronizar. Importações e conflitos são validados atomicamente; não podem deixar baixas acima do valor original, moedas incompatíveis ou uma efetivação integral duplicada.

Esta entrega aguarda validação manual; a epic #11 continua aberta para tags/estabelecimentos, edição em lote, lixeira/restauração e anexos.
