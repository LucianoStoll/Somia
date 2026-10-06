# Listas compactas e efetivação rápida — #42

Entrega pós-MVP na branch v0.2.0-alpha. Referência visual: imagem
1790865117604.jpeg fornecida pelo usuário em 01/10/2026.

## Comportamento

Receitas, despesas e transferências usam linhas com divisória fina, ícone de
status à esquerda, conta em texto menor, descrição, valor e datas. Receitas e
despesas mostram etiquetas de categoria e subcategoria; transferências mostram
origem e destino. Telas estreitas ou texto ampliado distribuem os detalhes em
mais linhas para manter controles separados e valores legíveis.

O ícone pendente/agendado efetiva com a data local de hoje: recebe, paga ou
transfere, sem alterar lançamento, vencimento, valor ou outros vínculos.
Em receitas, despesas e transferências, tocar o ícone efetivado remove a efetivação
e volta a pendente. O retorno também está disponível pelo menu. Uma ação em andamento desativa os controles da
linha. O feedback oferece Desfazer e Ajustar data por 5 segundos. Ajustar data
também fica no menu de três pontos, junto da edição, exclusão e retorno a pendente.

Desfazer restaura a efetivação anterior (null ou data agendada). A troca/restauração
altera só efetivação e os metadados de atualização, verificando a data esperada
antes de gravar para evitar que uma ação antiga sobrescreva uma mais recente.
Transferências preservam um registro único, usado no cálculo de ambas as contas.
A categoria, a descrição, as contas e demais datas não são regravadas nesse fluxo.
Não há migration ou nova dependência.

Os itens efetivados ficam no topo, preservando a ordem por vencimento dentro
de cada grupo. Agendamentos futuros permanecem junto dos pendentes.

Ícone, descrição, valor e menu têm áreas independentes. Com a #43, tocar o valor
abre a calculadora diretamente com o valor atual. O formulário completo mantém seu fluxo anterior de datas.

## Validação manual

- Criar uma receita, despesa e transferência pendentes com vencimento diferente
  de hoje. Tocar o ícone e conferir status, data de hoje e saldos das contas.
- Em receitas/despesas/transferências, tocar novamente: deve remover a efetivação, sem abrir edição.
- Aguardar 5 segundos: o feedback desaparece; a ação continua disponível na linha/menu.
- Desfazer: conferir volta ao estado anterior e saldos; repetir com agendamento.
- Ajustar para uma data passada/futura pelo feedback e pelo menu; conferir saldos.
- Cancelar o seletor de data: manter efetivação atual.
- Com filtro de pendentes, efetivar e desfazer mesmo após a linha sair da lista.
- Conferir edição, valor e menu sem acionar status; conferir etiquetas de categoria.
- Testar descrição longa, valor grande, texto ampliado, celular em paisagem e PC.
- Reiniciar o app e confirmar persistência; atualizar APK preservando os dados.

Validação manual, incluindo os ajustes junto da #43, aprovada pelo usuário em 01/10/2026.
