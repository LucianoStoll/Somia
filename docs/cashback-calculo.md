# Cashback — base de cálculo da #76

Primeira etapa técnica. O módulo de cálculo está implementado e separado de banco,
relógio e interface. **Cashback ainda não está disponível no aplicativo.** Este
documento não indica conclusão da #76, migration ou entrega de cartões de débito.

## Regras cobertas

- Valores em centavos; percentual em pontos-base: 100 representa 1%.
- Primeiro pagamento, inclusive parcial, ativa o total da compra uma vez.
- Pagamentos posteriores entram no gasto mensal das faixas, sem nova ativação.
- Pagamentos futuros ficam excluídos até o dia efetivo informado na referência.
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

## Integração ainda pendente

O chamador precisará fornecer total e estornos da compra, pagamentos alocados,
reduções elegíveis das faixas, regra vigente do mês e percentual já confirmado.
O cálculo retorna direitos; **não grava receitas nem confirma dinheiro**.

Ainda faltam cadastro de débito, seleção/persistência das compras cobertas por
pagamento, snapshots históricos de regras, ledger de confirmações e ajustes,
conta/categoria de recebimento e devolução, confirmação individual/em lote, aba
Cashback e integração com Receitas. Ajustes combinados de teto/faixa/estorno
precisam de reconciliação persistente; os métodos de baseline não substituem esse
ledger. Backup/sync/migrations e prevenção de duplicações serão verificados com
essa integração. Compras internacionais, adicionais e importação continuam como
entregas próprias previstas na #76.

## Verificação

`test/features/cards/cashback_calculator_test.dart` cobre pagamento parcial,
base distinta para faixas, parcelas entre meses, agendamentos, calendário,
rateio de teto, arredondamento, valores máximos, estornos antes/depois do
recebimento, diferenças aceitas e rejeição de entradas inconsistentes.

Verificação direta do runtime Dart: exemplo aprovado, faixas, calendário e 2.000
rateios com soma exata, proporcionalidade e invariância à ordem. Guardas Python
existentes: oito passaram. Os testes Flutter dependem da execução no CI.
