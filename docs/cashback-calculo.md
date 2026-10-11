# Cashback — base de cálculo da #76

A base de cálculo está integrada ao cadastro de débito, pagamentos de crédito,
Receitas e à aba Cashback no schema 25. Uso e políticas de histórico em
`docs/cashback-uso.md`. A #76 permanece aberta até validação manual.

## Regras cobertas

- Valores em centavos; percentual em pontos-base: 100 representa 1%.
- Primeiro pagamento, inclusive parcial, ativa o total da compra uma vez.
- Pagamentos posteriores entram no gasto mensal das faixas, sem nova ativação.
- Pagamentos futuros ficam excluídos até o dia efetivo informado na referência.
- Validação de compras selecionadas exige parcelas elegíveis, valores positivos,
  cobertura dentro do saldo de cada parcela e soma dentro do pagamento. A parte
  não atribuída pode pagar dívida anterior/encargos; não ativa compras por suposição.
- Faixa retroativa determinada pelo total efetivamente pago no mês.
- Uma previsão por compra, na data do primeiro pagamento ou no mês seguinte.
- Dias inexistentes usam o último dia do mês; dezembro avança para janeiro.
- Teto por mês de primeiro pagamento, proporcional entre as compras.
- Rateio do teto e do total informado em lote usa maiores restos, com desempate
  pelo identificador estável. A ordem de leitura/sync não altera os centavos.
- Produtos e somas intermediárias usam `BigInt`, evitando overflow e perda de
  precisão. Limite de cada valor monetário: 9.000.000.000.000.000 centavos.
- Estorno reduz a base da compra. A redução do gasto pago das faixas é recebida
  separadamente, já atribuída ao mês do pagamento, e validada contra seus limites.
  O módulo não escolhe implicitamente qual pagamento uma devolução cobre.
- Percentual de compras recebidas não cai por redução retroativa da faixa; uma
  faixa superior pode elevar seu direito e produzir complemento na integração.
- A confirmação guarda o valor teórico aceito separado do depósito real. Um
  recálculo idêntico gera diferença zero, mesmo se o depósito tiver outro valor.
- Devolução proporcional usa o depósito realmente recebido, incluindo a
  diferença aceita pelo usuário.

## Integração

O repositório persiste regras, compras cobertas por pagamentos, direitos e
recebimentos. Previsões são lançamentos normais de receita; devoluções são
lançamentos de despesa. Os valores não entram em outro ledger de saldo.
Confirmações preservam valor teórico, diferença aceita e base remanescente.
A diferença aceita acompanha proporcionalmente um estorno; ajustes de faixa e
teto são explicitamente previstos. Repetir um cálculo idêntico não grava nada.

Identificadores de direitos e previsões são derivados do cartão/compra e da
sequência de confirmações. Snapshot financeiro e sync incluem seis novas
tabelas. Confirmações têm snapshot imutável; uma alteração parcial/conflitante
é rejeitada durante a validação, antes de comprometer saldos. A reconciliação
não edita recebimentos anteriores. Confirmação de valor zero preserva histórico
sem lançar dinheiro. Há validação de revisão na confirmação em lote.

Compras internacionais, adicionais e importação continuam como entregas próprias
previstas na #76, fora da integração de débito/cashback desta entrega.

## Verificação

`test/features/cards/cashback_calculator_test.dart` cobre pagamento parcial,
base distinta para faixas, parcelas entre meses, agendamentos, calendário,
rateio de teto, arredondamento, valores máximos, estornos antes/depois do
recebimento, diferenças aceitas e rejeição de entradas inconsistentes.

Verificação direta do runtime Dart: exemplo aprovado, faixas, calendário e 2.000
rateios com soma exata, proporcionalidade e invariância à ordem. Guardas Python
existentes: oito passaram. Os testes Flutter dependem da execução no CI.
