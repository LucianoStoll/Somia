# Voltar e alterações não salvas — #39

Entrega pós-MVP em v0.2.0-alpha.

No Android, o botão/gesto Voltar fecha primeiro a sobreposição ativa:
menu lateral, menu +, filtros, painel, calculadora, seletor ou formulário.
Nas seções Receitas, Despesas, Transferências, Contas, Categorias, Configurações
e na rota legada Lançamentos, sem sobreposição ativa, retorna diretamente ao
Resumo. No Resumo, a saída fica a cargo do comportamento padrão do Android.
A regra considera a plataforma, inclusive Android em paisagem com sidebar;
Windows mantém sua navegação anterior. A proteção está também no navegador
principal, mantendo o sinal nativo de tratamento do Voltar ao alternar as seções.

Receitas, despesas, transferências, contas e categorias/subcategorias com
campos alterados pedem confirmação antes de voltar ou cancelar. Continuar
editando, tocar fora ou voltar na confirmação mantém os campos e o formulário.
Descartar fecha sem gravar. Salvar segue as validações e persistência existentes.
A comparação inclui textos, valores, contas, categorias, datas, tipo e opções;
foco e seleção do cursor não contam como alteração. Reverter todos os campos
remove a necessidade de confirmação. A calculadora e os seletores têm suas
próprias rotas e fecham sem descartar o formulário por baixo.

## Validação manual

- Em cada seção, usar botão e gesto Voltar: retornar ao Resumo; repetir: sair.
- Abrir drawer no Resumo e em outra seção; Voltar fecha só o drawer.
- Abrir +, filtros e ajuda de saldos; Voltar fecha só a sobreposição.
- Abrir formulário sem alterar nada; Voltar fecha sem perguntar.
- Alterar texto, valor, conta/categoria, data ou opção; Voltar pede confirmação.
- Continuar editando: conferir campos preservados; repetir e Descartar: não gravar.
- Voltar na confirmação mantém o formulário; Cancelar/back do cabeçalho segue a mesma regra.
- Abrir calculadora ou data dentro de formulário alterado; Voltar fecha só o seletor.
- Salvar receita/despesa/transferência/conta/categoria e conferir persistência.
- Testar Android em paisagem e Windows, incluindo Cancelar nos diálogos.

Não há migration, novas dependências ou alteração das regras financeiras.
Validação manual aprovada pelo usuário em 01/10/2026, incluindo as correções em Transferências.
