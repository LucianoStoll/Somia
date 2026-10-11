# Cartões de débito e cashback — #76

## Cadastro e compras

Em Cartões, o botão Cartões de débito abre o cadastro (também acessível pelo
menu Débito). Nome, conta em BRL, instituição e cor. Editar a conta muda somente
novas compras. Arquivar/reativar e excluir preservam despesas e histórico.
Em Despesas, escolher Cartão de débito no lançamento preenche sua conta; a
despesa segue as datas/baixas normais. Não há fatura, passivo ou despesa duplicada.

## Configuração

Na aba Cashback, selecionar um cartão de crédito/débito e Configurar.
Habilitar, conta de recebimento independente, categoria/subcategoria de receita,
percentual fixo e modo de previsão: primeiro pagamento ou dia do mês seguinte.
Opções avançadas: faixas de valores pagos, teto mensal e categoria/subcategoria
de despesa para devoluções. Percentuais até 100%, com duas casas; limites de
faixas crescentes. BRL nesta entrega; não converter moedas silenciosamente.

Dias 29–31 usam o último dia disponível. Todas as compras com cobertura de
pagamento participam. Pagamentos futuros contam quando chegam à data efetiva.

## Crédito e cobertura

Ao pagar uma fatura, expandir Compras cobertas por este pagamento. Informar a
parte paga de cada compra. A soma não pode exceder o pagamento nem o saldo de
cada parcela. O restante pode cobrir dívida anterior ou encargos e não ativa
compras por suposição. Preencher saldos é um atalho, sujeito à mesma validação.
Na quitação integral, a cobertura disponível pode ser atribuída automaticamente.
O atalho de pagamento parcial com cashback pede para abrir a fatura e selecionar
as compras. Pagamentos antigos sem cobertura não são reinterpretados silenciosamente.

Compra de R$1.000 com primeiro pagamento de R$100 e 1% gera R$10 previstos;
somente R$100 entram nas faixas daquele mês. Parcelas/pagamentos posteriores não
geram outro cashback sobre o total. Desfazer cobertura/pagamento remove previsões
não recebidas; se houve confirmação, gera ajuste previsto conservando o depósito.

## Recebimento

Cashback aparece em Receitas e na aba própria, com compra e cartão de origem.
Previsto afeta projeção, nunca saldo atual. Confirmar permite conta, valor, data
e categoria/subcategoria. Em Receitas, Editar/valor abre a aba Cashback; o atalho
de efetivação usa os valores padrão e a data escolhida.

Confirmar em lote ativa seleção. Receitas e devoluções são lotes separados.
O depósito/devolução total é distribuído proporcionalmente com centavos exatos.
Uma seleção desatualizada é rejeitada inteira. Total zero registra recebimento
zero sem transação monetária. Valor real diferente é definitivo: a diferença
aceita não aparece novamente por mero recálculo.

Desfazer confirmação é explícito; em compra com ajustes, desfazer primeiro o
mais recente. Não alterar/excluir recebimentos por edição em lote ou lixeira;
esses atalhos direcionam ao controle próprio para preservar os vínculos.

## Ajustes e histórico

- Faixa maior após recebido: complemento previsto.
- Estorno antes de receber: reduz/cancela previsão e reduz gasto elegível das
  faixas. A redução é atribuída aos pagamentos mais antigos da compra, limitada
  ao valor já pago. Nenhum pagamento ou despesa bancária é apagado por isso.
- Estorno após recebido: devolução prevista do valor realmente recebido,
  proporcional à compra estornada. Percentuais das outras compras recebidas não
  caem por redução retroativa da faixa.
- Teto: proporcional entre compras do mesmo mês de primeiro pagamento. Novas
  compras podem gerar devoluções/complementos em vez de editar depósitos.
- Devolução usa por padrão a última conta que recebeu dinheiro daquela compra;
  a confirmação permite escolher a conta que efetivamente devolveu. Categoria
  deve ser de despesa; a de receita não é reutilizada.
- Regras alteradas: previsões não recebidas do mês atual usam a nova regra.
  Compras já confirmadas e meses anteriores conservam o snapshot anterior; novos
  pagamentos/compras/estornos podem produzir ajustes calculados nesse snapshot.
- Desabilitar suspende novas previsões e cancela as ainda não recebidas; mantém
  confirmações e a reconciliação de seus estornos. Reativar restaura previsões
  elegíveis com a mesma identidade.

Complementos/devoluções mensais vencem no próximo dia configurado, incluindo
hoje se ainda é esse dia. Históricos permanecem nas confirmações originais.
Backup e sync incluem configurações, cobertura, direitos, receitas e histórico.
Confirmação parcial ou contraditória recebida pelo sync é rejeitada para revisão.

## Validação manual Android/Windows

- [ ] Criar/editar/arquivar/reativar/excluir débito; conferir histórico e conta antiga.
- [ ] Despesa no débito pendente, realizada, futura e com primeira baixa parcial.
- [ ] Crédito à vista/parcelado, pagamento parcial com cobertura, saldo e limite.
- [ ] Configurar imediato/mensal, dias 29–31, conta diferente e subcategorias.
- [ ] Confirmar individual/em lote, valor diferente/zero e desfazer.
- [ ] Faixa maior, teto com nova compra, estorno parcial/integral antes/depois.
- [ ] Conferir que ajustes não repetem e depósitos permanecem intactos.
- [ ] Receitas, saldo previsto/atual, gráficos e extratos sem duplicação.
- [ ] Backup/restauração, sync offline e conflito de confirmação entre plataformas.

Internacionais, adicionais e importação são entregas específicas ainda abertas
na #76; esta documentação descreve a integração de débito/cashback.
