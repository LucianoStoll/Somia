# Análises de despesas e saldos — #75

Acesso: **Análises** no menu lateral ou em Configurações → Finanças. Selecione o mês compartilhado, o gráfico e a moeda. Toque nas barras para abrir o detalhamento. Implementação de leitura, sem migration, movimentação de dinheiro ou mudanças no backup/sync.

## Categorias e comparação

Despesas por categoria em barras ordenadas por valor líquido, incluindo subcategorias, rateios e estornos. Detalhes mostram a parcela de cada lançamento atribuída à categoria; um rateio pode aparecer em mais de uma categoria sem duplicar o total. A comparação mostra mês selecionado, anterior e média dos três meses anteriores completos, incluindo zeros; diferenças por categoria em centavos e percentual. Sem valor anterior, o percentual mostra “Sem base percentual”, sem divisão por zero. Média em centavos truncada; média total calculada sobre o total do trimestre, independentemente do arredondamento por categoria.

Base financeira igual ao Resumo: efetivação, ou vencimento quando pendente; baixas parciais entram no pagamento e o restante no vencimento. Cartões usam vencimento da fatura e valores das parcelas, com estornos negativos; abertura de dívida e pagamentos de fatura não são novas despesas. Transferências não são despesas. Contas/lançamentos excluídos ou fora das análises não entram. Não há conversão nem soma de moedas distintas. Meses atuais podem estar incompletos.

## Compromissos futuros

Seis meses após o selecionado, com despesas pendentes/agendadas e encargos de cartão não liquidados **no estado atual do banco**, independentemente de quando o mês histórico foi selecionado. Baixas já pagas são deduzidas. Créditos antecipados de cartão reduzem os próximos encargos; pagamentos apenas agendados continuam sendo compromisso de caixa. Cada encargo entra uma vez; dívida vencida não é repetida nos seis meses. Não é um extrato completo de dívida atrasada. Não estima recorrências ainda não geradas e não projeta despesas novas. Despesas e cartões têm cores distintas, valores explícitos e detalhe por mês.

## Saldo por tipo de conta

Corrente, poupança, carteira/dinheiro, investimento e outras contas, separados por moeda. Saldo efetivado acumulado até o fim do mês selecionado. Todas as contas ativas entram, inclusive investimentos desmarcados em “incluir no saldo do mês”; por isso este total pode diferir do card de saldo do Resumo. Arquivadas não entram; não representa o estado histórico do arquivamento/tipo da conta. Aplicações usam somente o saldo da conta, sem somar novamente o cadastro de investimento. Saldos negativos são vermelhos à esquerda do zero, positivos à direita. Toque mostra as contas do grupo.

## Verificação manual

1. Conferir categorias/subcategorias e tocar em uma categoria com rateio.
2. Conferir mês anterior e média de três meses; testar categoria nova e mês sem despesa.
3. Conferir uma baixa parcial e um estorno de cartão sem duplicar a liquidação.
4. Verificar próximos meses e comparar com parcelas/faturas cadastradas; confirmar que uma pendência não é repetida como saldo anterior.
5. Conferir corrente, investimento excluído do saldo mensal e carteira negativa; trocar moeda.
6. Trocar mês, atualizar, usar texto ampliado e navegar no Android/Windows.

Testes automatizados cobrem cálculos, flags, exclusões, rateios, estornos, pagamentos, crédito antecipado, moedas, corte de saldo e telas em ambas as plataformas. CI gera prévias dos quatro gráficos. A issue permanece aberta até validação manual.
