# Recorrências e parcelamentos — #46 / epic #11

Escopo definido com o usuário em 02/10/2026. Android e Windows, offline, na branch
`v0.2.0-alpha`. As melhorias menores #37/#38 ficam para depois.

## Criação

No formulário de receita, despesa ou transferência, escolher **Único**, **Recorrente**
ou **Parcelado**. Todas as ocorrências de uma série são geradas **pendentes**, inclusive
a primeira; a efetivação continua manual, com as ações já existentes.

- Frequência diária, semanal, mensal ou anual, com intervalo personalizado (ex.: a cada
  2 semanas ou 3 meses).
- Quantidade finita, incluindo o primeiro lançamento. Por exemplo, 12 vezes = primeiro
  + 11 próximos. Esta entrega não usa término por data nem repetição infinita.
- Recorrência repete o valor informado por ocorrência.
- Parcelamento aceita valor total ou valor por parcela. Por total, divide em centavos
  inteiros e distribui o resto entre as primeiras parcelas; diferença máxima de 1
  centavo, soma exata. Por parcela, multiplica para apresentar o total.
- Resumo mostra quantidade, valores, total e último vencimento antes de salvar.
- Quantidade de 2 a 1000, intervalo de 1 a 1000 e término até 2100. Parcela mínima de
  um centavo; limites monetários existentes também se aplicam ao total.
- Cada data deriva da primeira: 31/jan → último dia de fevereiro → 31/mar. Anual em
  29/fevereiro retoma o dia 29 em anos bissextos. Datas de lançamento e vencimento
  possuem âncoras independentes e avançam com a mesma frequência.

Criação atômica: qualquer erro de valor, vínculo ou data desfaz todas as inserções.
As ocorrências entram nas consultas e projeções existentes; transferências mantêm
um registro por ocorrência, com efeito nos dois lados e compensação consolidada.

## Edição e exclusão

Pelo menu de uma ocorrência de série, escolher **Somente esta** ou **Esta e as próximas**.
A edição rápida pela calculadora também oferece esse alcance. Efetivação/desfazer
continuam individuais.

Ações em série preservam os índices anteriores, exclusões e qualquer ocorrência com
data de efetivação confirmada, inclusive agendada. A edição em série não efetiva
pendências. A opção isolada mantém os comportamentos de edição/exclusão anteriores.

A frequência e a quantidade exibidas identificam a série criada. Nesta entrega,
editar uma ocorrência altera seus campos; não reconstrói nem aumenta a série.
O valor editado é por ocorrência: ao aplicar às próximas pendentes, elas passam a
usar esse valor. O total passa a refletir os valores vigentes, preservando efetivados.

Se a data editada não mudou, conservar as datas originais de cada próxima ocorrência,
incluindo exceções individuais; isso impede transformar 31/mar em 28/mar ao editar
apenas a descrição de fevereiro. Ao mudar a data, ela vira a nova âncora para as
próximas pendentes, conforme seus índices, unidade e intervalo.

Lista identifica recorrência/parcela como 1/N, 2/N etc., sem acrescentar o número à
descrição armazenada. Excluir uma ocorrência não renumera as outras.

## Persistência e compatibilidade

Migration v9 adiciona metadados opcionais junto a cada registro, mais índice por
série/posição, nas tabelas `transactions` e `transfers`. Nenhum saldo ou registro
antigo é transformado. Operações de série usam transações SQLite; edição rápida de
valor mantém comparação do valor esperado e preserva os demais campos.

Backup e restauração existentes incluem os vínculos da série. A assinatura e o
applicationId Android continuam os mesmos, com build number crescente no CI.

## Validação

Testes cobrem calendário, centavos, ambos os modos, criação nos três tipos, projeções,
proteção de efetivados/agendados, ações isoladas/em série, atomicidade, migration
v8→v9, logos e histórico anteriores, backup, interface e confirmação de descarte.

Validação manual aprovada pelo usuário em 02/10/2026. Roteiro utilizado:

1. Criar receita recorrente mensal por 3 ocorrências e navegar entre os meses.
2. Criar despesa de R$ 100,00 em 3 parcelas; conferir R$ 33,34 + R$ 33,33 + R$ 33,33.
3. Criar por valor de parcela; conferir total e identificação.
4. Criar transferência recorrente; conferir projeções nas duas contas e consolidado.
5. Conferir frequências e intervalos, dia 31 e fevereiro/ano bissexto.
6. Efetivar uma próxima ocorrência e editar/excluir as seguintes: preservar a efetivada.
7. Alterar somente uma ocorrência; conferir que as outras continuam intactas.
8. Cancelar edição, confirmar/recusar descarte e fechar a calculadora pelo Voltar.
9. Reiniciar e restaurar backup; conferir série, histórico anterior e logos.

## Validação

Usuário confirmou “Validei” em 02/10/2026; #46 encerrada.
