# Detalhamento do saldo (#38)

Os cards de saldo no Resumo abrem o detalhamento da moeda selecionada. Android: painel inferior rolável; Windows: diálogo adaptado. Voltar, toque externo e botão Fechar dispensam o painel. Apenas consulta, sem orçamentos.

O painel é carregado na mesma transação e snapshot do dashboard e acompanha atualizações do resumo e do mês. Abrir novamente atualiza os dados locais. O corte é o fim do mês selecionado, inclusive efetivações agendadas até esse dia; esta é a regra do card, distinta do corte de hoje do Realizado no extrato individual.

Saldo efetivado = saldo inicial realizado anterior ao mês + receitas efetivadas − despesas pagas + transferências recebidas − enviadas − pagamentos de cartão do mês. Saldo previsto = saldo efetivado + receitas pendentes − despesas pendentes + transferências a receber − enviar − dívida restante dos cartões até o corte. Pendências anteriores ao mês continuam incluídas. Efetivações em meses posteriores ficam fora do período.

Somente contas não excluídas do saldo consolidado, incluindo arquivadas, compõem esses valores. A flag de análises não interfere. Cada lado incluído de uma transferência aparece uma vez; transferências internas se compensam e transferências com contas excluídas afetam apenas o lado incluído. Moedas nunca se somam. Ignorados para saldo e registros apagados ficam fora.

Compras e estornos integram a previsão líquida de fatura; pagamentos debitam apenas a conta pagadora. O saldo restante previsto segue a regra financeira compartilhada: cobranças com vencimento até o corte menos pagamentos do cartão até o corte, com mínimo zero, inclusive pagamentos por outra conta. Não repetir compras como despesas de caixa.

## Validação manual

- Tocar no saldo atual e previsto, conferir mês/moeda e reconciliar os dois totais com os cards.
- Testar meses passados, atual/futuros, pendências antigas e efetivações agendadas.
- Testar contas excluídas/arquivadas, transferências internas e externas e saldos negativos.
- Testar cartão parcialmente pago, estornado, agendado e pago noutra conta.
- Conferir rolagem, texto ampliado e fechamento por Voltar/toque externo/Fechar, no Android e Windows.
