# Categorias pelo histórico — #48 / epic #11

Ao criar receita, despesa ou compra no cartão, a descrição completa preenche categoria e subcategoria a partir da classificação válida mais recentemente cadastrada/alterada. A comparação ignora maiúsculas/minúsculas e espaços extras; acentos e palavras diferentes continuam distintos. Não há preenchimento por trecho parcial.

Usa todos os meses, contas e cartões; receitas e despesas são separadas. Ignora lançamentos excluídos, ajustes/faturas e categorias/subcategorias ou pais arquivados/excluídos. Descrição sem correspondência remove a classificação sugerida anteriormente. Se o último lançamento estiver sem categoria, usa a classificação anterior válida.

A sugestão é identificada no campo Descrição. Escolher categoria ou subcategoria manualmente, inclusive Sem categoria/Nenhuma, preserva a escolha durante o formulário. Trocar o tipo reavalia o histórico correspondente. Editar um lançamento mantém a categoria existente; não consulta sugestões.

Só categoria/subcategoria são sugeridas. Valores, contas, datas, efetivação, cartão, fatura e séries mantêm as regras existentes. Transferências não possuem categorias. Funciona offline; sem migration ou alteração de backup. O histórico é carregado ao abrir cada novo formulário, refletindo as últimas alterações salvas. Falha de leitura não impede o cadastro manual.

## Validação manual

1. Cadastre Jantar com Alimentação / Restaurante.
2. Abra nova despesa, digite JANTAR e confira os dois campos e a indicação do histórico.
3. Digite descrição desconhecida e confira que a sugestão foi removida.
4. Digite Jantar novamente, escolha outra categoria (ou Sem categoria), depois mude a descrição: a escolha manual deve permanecer.
5. Salve e abra novo formulário: a classificação salva mais recentemente será usada.
6. Teste também uma compra no cartão e uma receita com a mesma descrição; receitas devem usar seu próprio histórico.
7. Edite um lançamento existente e mude sua descrição: categoria preservada.
8. Arquive uma categoria/pai e confira que não é sugerida.

Validação manual pendente, Android e Windows.

## Sugestões por trecho — ajuste de 04/10/2026

Ao digitar parte da descrição, mostrar até oito lançamentos anteriores com descrição, conta/cartão e valor. Uma sugestão por descrição e conta/cartão, mantendo a versão mais recente. Somente origens ativas; receitas e despesas separadas. O botão X oculta a sugestão neste formulário e não apaga o histórico.

Ao escolher, preencher descrição, categoria/subcategoria válida, conta/cartão e valor, conforme escolha expressa do usuário. Datas, efetivação e séries não são copiadas. Compra mantém fatura automática pelo fechamento atual. Sugestão explícita tem prioridade sobre preenchimento anterior; todos os campos continuam editáveis. A lista não é exibida em edição de lançamento existente.

Validar: digitar Ren, conferir lista e valores; escolher uma sugestão em outra conta e conferir os campos; ocultar uma linha e conferir que o lançamento original permanece. Depois salvar e conferir datas/estado definidos no novo formulário.
