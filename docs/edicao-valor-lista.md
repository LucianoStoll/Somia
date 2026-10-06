# Edição de valor pela lista — #43

Entrega pós-MVP em v0.2.0-alpha, com ajustes de efetivação solicitados junto da #43.

Tocar o valor abre a calculadora integrada já preenchida. Digitação direta e operações
usam centavos inteiros. Confirmar grava apenas o valor e os metadados de atualização;
receitas/despesas mantêm o valor efetivo consistente quando há data de efetivação.
Transferências usam um único registro para os saldos de origem e destino.
Os totais e contas são recarregados após salvar; outras telas consultam os valores
persistidos ao abrir. Cancelar ou voltar não grava. Confirmar sem mudar não grava.

A gravação rejeita valor zero, negativo, acima de 9000000000000000 centavos,
registro excluído ou valor alterado por outra ação enquanto a calculadora estava
aberta. Não regrava descrição, categorias, contas, datas ou status, inclusive em
históricos com conta/categoria arquivadas. Uma linha ocupada bloqueia ações repetidas.
Não há alteração de schema, dependência ou necessidade de rede.

## Validação manual

- Em receita, despesa e transferência, tocar no valor e conferir o valor atual.
- Somar 1, confirmar e conferir a lista, totais, saldo das contas e gráficos ao abrir.
- Conferir descrição, categorias, contas, lançamento, vencimento e efetivação preservados.
- Digitar outro valor, cancelar; repetir usando voltar/Escape: manter o valor original.
- Tocar na descrição: abrir edição completa; tocar no valor: abrir só a calculadora.
- Efetivar receita/despesa; esperar 5 segundos: Desfazer/Ajustar data desaparecem.
- Tocar no ícone efetivado: voltar a pendente e atualizar saldo e posição na lista.
- Conferir efetivados no topo, pendentes/agendados abaixo, inclusive após salvar e reiniciar.
- Na transferência efetivada, alterar o valor e conferir débito e crédito iguais.
- Testar Android estreito, texto ampliado, paisagem e Windows com teclado.

Validação automatizada executada pelo Flutter CI em Linux e Windows antes da entrega.
Validação manual aprovada pelo usuário em 01/10/2026.
