# Somia — Identidade visual e interface do MVP

Versão do documento: 1.3 • 30/09/2026  
Projeto: FinApp • Marco: v0.1.0-alpha  
Origem: chat “Definir identidade visual”, de 28/09/2026.

## 1. Decisões aprovadas

| Item | Decisão |
| --- | --- |
| Nome do produto | Somia; substitui FinApp como nome apresentado ao usuário. O repositório continua FinApp. |
| Direção visual | Interface simples, leve e pouco densa, com espaço entre os elementos. |
| Cor principal | Azul acinzentado. |
| Tema do MVP | Somente escuro. Tema claro e seguir o sistema ficam para o futuro. |
| Tela inicial | Resumo do mês, gráficos e lançamentos recentes. |
| Ação principal | Botão + abre um pequeno balão flutuante com Receita, Despesa e Transferência. |
| Navegação mobile | Remover a barra inferior e usar drawer/menu lateral recolhível. |
| Organização | Receitas e Despesas são áreas independentes no menu principal. |
| Navegação Windows | Mesma arquitetura de informação, adaptada para sidebar/NavigationRail em telas largas. |
| Tema claro futuro | Direção visual clara aprovada para evolução posterior, mantendo a mesma estrutura e hierarquia do tema escuro. |
| Dashboard no MVP | Composição básica e fixa. |
| Dashboard futuro | Usuário poderá escolher quais informações aparecem e alterar a ordem. |
| Plataformas | Android e Windows, com layout adaptativo e funcionamento offline. |

A decisão mais recente de usar apenas tema escuro substitui, para o MVP, o planejamento anterior de claro/escuro/sistema.

## 2. Referência visual aprovada

O protótipo “Somia, quatro telas de finanças pessoais.png” recebeu a aprovação “Está bom”. Ele mostra Resumo, Lançamentos, Contas e Nova despesa.

[Consultar o protótipo aprovado](https://chatgpt.com/api/library/files/libfile_700dcbc0194c8191b160a6f7c864bd8d/download)

As referências enviadas no chat estão preservadas nos links abaixo. Esses links exigem acesso aos arquivos no ChatGPT; não são imagens públicas hospedadas no GitHub.

- [1000066877.jpg](https://chatgpt.com/api/library/files/libfile_d748dff3dd3081919deef8899caa7ba7/download)
- [1000066774.jpg](https://chatgpt.com/api/library/files/libfile_4d00ea461f8c8191a69d091c7144a766/download)
- [1000066875.jpg](https://chatgpt.com/api/library/files/libfile_cd146d8edfb48191a3e6ed22ad9089b1/download)
- [1000066880.jpg](https://chatgpt.com/api/library/files/libfile_4141097250fc81919c0ca2404f4deac8/download)
- [1000066879.jpg](https://chatgpt.com/api/library/files/libfile_45862f927ed081918f98fbe728fd168c/download)
- [1000066876.jpg](https://chatgpt.com/api/library/files/libfile_a34821b1cd408191baf036a989185ded/download)

Os valores, nomes de contas e datas do protótipo são ilustrativos. Não devem ser inseridos como dados reais ou fixos no aplicativo.
### Referência visual de polimento aprovada em 29/09/2026

A imagem [Somia — dashboard desktop](https://chatgpt.com/api/library/files/libfile_82b14d5505cc8191b345810285984adc/download) orienta o acabamento da interface: fundo azul quase preto, superfícies azul acinzentadas com bordas discretas, ícones coloridos por tipo, sidebar com item ativo, cartões de saldo/receitas/despesas/projeção, barras de seis meses, gráfico circular de categorias e painéis de lançamentos recentes e saldos por conta. Em janela intermediária a sidebar pode ficar compacta; no mobile, permanece o drawer aprovado, e o dashboard passa a seguir a composição mobile fixa especificada abaixo.

Os bancos, valores, percentuais e comparações da imagem são ilustrativos. Exibir dados reais do aplicativo, sem inserir marcas de bancos ou tendências calculadas sem histórico.

### Referências mobile aprovadas em 29/09/2026

Foi aprovada uma nova direção mobile com três vistas principais: dashboard, drawer aberto e tela dedicada de Receitas. A composição aprovada remove a navegação inferior, usa menu lateral e mantém o botão flutuante +.

Também foi aprovada uma variação **clara/branca** dessa mesma estrutura para implementação futura. Ela não altera o escopo do MVP, que continua somente escuro, mas passa a ser referência para a futura implementação de tema claro.

Os mockups foram gerados/aprovados durante a conversa de revisão do MVP em 29/09/2026. Enquanto os arquivos binários não estiverem versionados no repositório, este documento é a fonte textual das decisões de navegação e tema.


## 3. Navegação e telas

### Resumo

- Identificação Somia no cabeçalho.
- Mês de referência visível, com navegação entre meses.
- No mês atual e nos anteriores, saldo total em destaque no primeiro cartão, com saldo projetado identificado logo abaixo.
- Em meses futuros, saldo previsto em destaque e saldo já efetivado como referência secundária.
- Resultado do mês em cartão próprio, com receitas e despesas do mesmo período.
- Gráfico básico de gastos por categoria, com legenda e valores/percentuais.
- Lançamentos recentes e acesso à listagem completa.
- Os saldos do resumo usam o último dia do mês selecionado como corte, sem incorporar lançamentos de meses posteriores.
- Atualização após criar, editar ou excluir movimentos, sem reiniciar o aplicativo.

Resultado mensal significa receitas menos despesas do período. Não deve ser confundido com o saldo acumulado das contas. Transferências entre contas não entram como receita/despesa nem no gráfico de gastos.

### Composição do dashboard no Android — referência de 29/09/2026

Referência: [1000067034.png](https://chatgpt.com/api/library/files/libfile_252f52e1e7d4819182c295e9cecbc831/download), enviada pelo usuário nesta revisão.

Ordem e geometria mobile:
1. Cabeçalho compacto com menu e marca Somia; seletor do mês e setas em uma linha própria.
2. Saudação e título “Resumo do mês”.
3. Saldo do mês em cartão de largura total; projeção como informação secundária. Em mês futuro, o previsto continua em destaque.
4. Receitas e Despesas na mesma linha, cada uma com metade da largura disponível.
5. Gráfico “Receitas vs Despesas” em largura total, com seis meses, eixos, grade e legenda.
6. “Gastos por categoria”, com gráfico circular, total mensal e legenda adaptada à largura.
7. “Transações recentes”, com ícones por tipo, descrição, data/conta, valor e acesso à listagem completa.

No mobile, o gráfico por categoria acompanha o histórico de receitas/despesas. Não intercalar cartões extras de projeção ou saldos por conta entre esses blocos. Contas e categorias continuam disponíveis no menu; o desktop mantém sua composição atual, incluindo esses painéis. O botão + permanece acessível e o conteúdo pode rolar sem ser coberto por ele.

O seletor de mês permanece no cabeçalho durante a rolagem, com mês anterior, próximo mês e retorno ao mês atual. Espaçamentos, cartões arredondados e cores seguem a imagem. Percentuais ilustrativos não são copiados para dados reais. A composição deve suportar telas estreitas, valores grandes e texto ampliado.

### Receitas

- Área independente no menu principal.
- Período de referência visível.
- Lista organizada com descrição, conta, valor, categoria e situação.
- Acesso aos fluxos existentes de criação, edição, exclusão e efetivação.
- Ação Efetivar visível em pendências sem exigir abrir a edição completa.
- Filtros e ordenação essenciais sem depender da tela de Despesas.

### Despesas

- Área independente no menu principal, com a mesma linguagem visual de Receitas.
- Período de referência visível.
- Lista organizada com descrição, conta, valor, categoria e situação.
- Acesso aos fluxos existentes de criação, edição, exclusão e efetivação.
- Diferenciação por texto/sinal/ícone, sem depender apenas da cor.
- Botão + acessível sem cobrir conteúdo ou comandos importantes.

Receitas e Despesas podem compartilhar componentes internos, mas **não devem depender de uma aba única de “Lançamentos” como navegação principal**.

### Contas

- Saldo total e lista de contas com nome, ícone e saldo.
- Ação para adicionar conta.
- Acesso às ações existentes de gerenciamento.
- Preservar regras de conta inativa, saldo inicial e histórico.

### Nova receita / Nova despesa

- Valor com maior destaque.
- Descrição, conta, data, categoria e subcategoria.
- Categoria e subcategoria em seletores distintos.
- Subcategorias coerentes com a categoria escolhida; limpar seleção incompatível ao trocar a categoria.
- Campos adicionais existentes podem ficar em “Mais detalhes”, mantendo os obrigatórios acessíveis.
- Botão “Salvar lançamento” claramente identificado.
- Manter validações e persistência offline existentes.

### Transferência

A opção no balão deve abrir o fluxo específico de transferência, com contas de origem/destino e valor. Reutilizar a operação financeira existente e preservar a consistência entre os dois lados.

### Navegação principal

No mobile, a barra inferior deve ser removida. O cabeçalho apresenta um botão de menu que abre o drawer lateral Somia.

Ordem base do menu:
1. Dashboard/Resumo;
2. Receitas;
3. Despesas;
4. Transferências;
5. Contas;
6. Categorias;
7. Configurações.

A seção atual deve possuir destaque claro no drawer. No Windows, a estrutura pode permanecer visível como sidebar/NavigationRail em telas largas.

### Ajustes

No MVP, Ajustes/Configurações deve apresentar apenas funcionalidades disponíveis. Não incluir controles de tema claro nem personalização do dashboard nesta entrega.

## 4. Comportamento do botão +

1. Ao tocar/clicar no +, abrir um pequeno menu flutuante próximo ao botão.
2. Exibir Receita, Despesa e Transferência, cada uma com ícone e texto.
3. Ao selecionar uma opção, fechar o menu e abrir o formulário correspondente.
4. Fechar também ao tocar fora, voltar ou pressionar Escape no desktop.
5. Manter foco de teclado e semântica acessível; evitar múltiplos menus sobrepostos.

Os três tipos de ação são fixos no MVP. Personalização das ações rápidas é evolução futura.

## 5. Sistema visual

### Diretrizes aprovadas

- Fundo escuro e superfícies discretamente diferenciadas.
- Azul acinzentado como destaque principal.
- Poucos elementos concorrendo por atenção.
- Hierarquia clara entre título, informação principal, rótulos e informações secundárias.
- Cards e listas com respiro, sem excesso de bordas, sombras ou efeitos.

### Recomendações técnicas para implementação

Estas recomendações operacionalizam a direção aprovada; não são escolhas adicionais explicitamente aprovadas no chat.

- Centralizar cores, tipografia, espaçamentos e raios no tema Flutter.
- Utilizar tipografia sem serifa legível e consistente com o projeto.
- Dar destaque aos valores principais e manter rótulos discretos, porém legíveis.
- Usar uma escala consistente de espaçamento e componentes compartilhados.
- Usar cores semânticas discretas para receita, despesa e erro.
- Conferir contraste, escala de texto e áreas de toque nas plataformas alvo.
- Em telas largas, aproveitar colunas e navegação lateral sem esticar cartões indefinidamente.
- Evitar adicionar dependências apenas para reproduzir efeitos decorativos.

A logo oficial, seus códigos HEX e os arquivos vetoriais estão definidos na seção “Logo oficial — 30/09/2026”. Para os demais componentes, consultar o tema implementado e as medidas documentadas; decisões futuras devem respeitar as referências aprovadas.

## 6. Estados e regras de dados

- Sem lançamentos: mensagem objetiva e ação para adicionar o primeiro.
- Sem gastos no mês: gráfico vazio informativo, sem divisão por zero.
- Sem contas: orientar criação de conta antes do lançamento.
- Erro ao salvar: manter os dados digitados e apresentar feedback compreensível.
- Valores negativos, nomes longos e texto ampliado não podem quebrar o layout.
- Totais e gráficos devem vir das consultas e regras financeiras do projeto.
- Mudanças visuais não devem alterar banco, saldos, transferências ou histórico sem necessidade explícita.

## 7. Escopo e evolução

| MVP v0.1.0-alpha | Pós-MVP |
| --- | --- |
| Tema escuro | Tema claro aprovado e opção de seguir o sistema |
| Drawer mobile; sidebar/rail adaptativa no Windows | Refinamentos de navegação e personalização futura |
| Receitas e Despesas independentes | Filtros/visões avançadas configuráveis |
| Dashboard básico com composição fixa | Mostrar/ocultar e reordenar blocos |
| Resumo mensal e gráfico básico por categoria | Relatórios e gráficos avançados/personalizáveis |
| + com três ações fixas | Ações rápidas personalizáveis |
| Formulários essenciais e seletores separados | Autocomplete, modelos e fluxos avançados |
| Android/Windows offline | Integrações opcionais previstas no roadmap |

Preparar componentes independentes para facilitar evolução, sem implementar agora um editor de dashboard ou persistência de preferências que não serão utilizadas.

## 8. Plano de implementação

1. Conferir a versão atual da branch v0.1.0-alpha e os componentes existentes.
2. Consolidar o tema escuro Somia e os componentes reutilizáveis.
3. Remover a barra inferior no mobile, implementar drawer Somia, separar Receitas/Despesas na navegação e manter o balão do +.
4. Aplicar a composição aprovada em Resumo, Lançamentos, Contas e formulários.
5. Conectar o resumo e o gráfico aos dados locais.
6. Validar Android/Windows, acessibilidade básica e uso offline.
7. Rodar análise, testes e build Windows pelo GitHub Actions. APKs são assinados com a chave persistente já configurada na #31.
8. Após validação do usuário, concluir a issue e seguir o fluxo de PR para main.

Usar branch identificada pela versão. A entrega desta documentação não significa que a interface já foi implementada ou validada.

## 9. Relação com as issues existentes

- #24 e #8: dashboard básico; complementar com resumo mensal, gráfico por categoria e composição Somia.
- #25: manter tema escuro no MVP, acessibilidade e validação Android/Windows.
- #32: implementar drawer/menu lateral, remover barra inferior e separar Receitas/Despesas.
- #30: incorporar as três datas e a regra de efetivação ao fluxo visual.
- #31: validar que APKs de teste atualizam sem perda de dados antes do fechamento do MVP.
- #21 e #5: preservar receitas/despesas e seletores separados.
- #22 e #6: reutilizar transferências no menu +.
- #19 e #3: aplicar identidade à área de Contas.
- #14: manter relatórios avançados no pós-MVP.
- #10: incluir verificação visual na validação final do MVP.

As referências acima não declaram essas issues abertas, fechadas ou implementadas; registram a relação de escopo.

## 10. Critérios de aceite da interface

- [ ] Nome Somia apresentado ao usuário nas telas alteradas.
- [ ] Tema exclusivamente escuro no MVP, com destaque azul acinzentado; tema claro permanece referência aprovada para evolução futura.
- [ ] Composição leve e coerente com o protótipo aprovado.
- [ ] Mobile sem barra inferior, usando drawer/menu lateral.
- [ ] Drawer contém Dashboard/Resumo, Receitas, Despesas, Transferências, Contas, Categorias e Configurações.
- [ ] Receitas e Despesas são telas/seções independentes na navegação principal.
- [ ] Windows usa adaptação coerente da mesma arquitetura de informação.
- [ ] Resumo mensal e gráfico básico usam dados reais e atualizam após alterações.
- [ ] Resultado do mês claramente distinto do saldo total.
- [ ] Saldo total em destaque no topo do resumo, com corte no mês selecionado.
- [ ] Lançamento pendente pode ser efetivado pela lista sem abrir a edição.
- [ ] Transferências excluídas das receitas/despesas e dos gastos por categoria.
- [ ] + abre balão com Receita, Despesa e Transferência.
- [ ] Categoria e subcategoria em campos distintos.
- [ ] Dashboard permanece fixo nesta versão.
- [ ] Estados vazios, erros e valores extremos tratados.
- [ ] Layout funcional em Android e Windows, offline.
- [ ] Análise, testes e build Windows aprovados; APK somente após retomada da #31.
- [ ] Validação visual e funcional do usuário antes do encerramento.


### Mês de referência e filtros de movimentos

O mês de referência é compartilhado durante a sessão entre Resumo, Receitas,
Despesas e Transferências. Tocar no mês abre uma grade com os doze meses e
controles de ano, permitindo saltar de setembro para dezembro diretamente.
Nas listas e no desktop, as setas também permitem avançar ou voltar um mês.
A opção “Mês atual” retorna ao mês corrente.

As listas abrem limitadas ao mês escolhido, usando a data de vencimento.
O botão “Filtros” abre os controles detalhados: contas, categorias/subcategorias
(nos lançamentos), estado e campo de data. Um período personalizado ou
“Todos os meses” pode ampliar a consulta; essa exceção aparece na página.
Escolher um mês novamente restaura o período mensal, mantendo os demais
filtros. “Limpar filtros” restaura vencimento e mês de referência.

Em paisagem, a barra lateral compacta tem 104 pixels de largura útil, além
do espaço seguro do Android, com navegação rolável para telas baixas.


### Ajustes de conforto no mobile

No dashboard, as setas de mês anterior/próximo acompanham a seleção direta
de mês e ano. O controle ocupa uma segunda linha no cabeçalho mobile,
preservando espaço para Somia, os alvos de toque e o nome completo do mês.
Os formulários de contas, categorias, lançamentos e transferências usam
16 pixels entre os campos, evitando sobreposição dos rótulos flutuantes.
Os formulários continuam roláveis quando o teclado está aberto.

Os cards das listas de contas, categorias, lançamentos e transferências
têm 12 pixels de separação vertical.


## Logo oficial — 30/09/2026

O monograma S em azul acinzentado substitui a folha usada provisoriamente.
A assinatura horizontal combina o símbolo com Somia em branco suave.
As versões finais foram reconstruídas em vetor, com cor sólida, transparência
limpa e tipografia convertida em contornos (URW Gothic Demi).

![Símbolo e assinatura horizontal oficiais](assets/somia-logos.png)

| Uso | Arquivo |
| --- | --- |
| Ícone, menu recolhido e aplicações pequenas | [Símbolo SVG](../assets/branding/somia_symbol.svg) · [PNG transparente](../assets/branding/somia_symbol.png) |
| Cabeçalho e menu aberto | [Logo horizontal SVG](../assets/branding/somia_horizontal.svg) · [PNG transparente](../assets/branding/somia_horizontal.png) |

Cores: símbolo `#9FBFD6`, nome `#F1F3F6` e fundo do ícone `#10161D`.
O fundo escuro da imagem acima é apenas de apresentação; os arquivos da marca
têm transparência. Manter as proporções, respiro e contraste; não distorcer,
aplicar sombras, textura ou contorno branco.

No app, `SomiaBrand` centraliza o uso da identidade. O Flutter usa PNGs
transparentes locais, sem rede ou dependência adicional. Os SVGs são as
fontes escaláveis. Android inclui ícone adaptativo com fundo e símbolo
separados e versões de fallback em todas as densidades. Windows utiliza
ICO com tamanhos de 16 a 256 pixels. O identificador de instalação e a
assinatura do APK permanecem os mesmos para permitir atualização.


### Datas usadas no resumo mensal

Receitas, despesas, distribuição por categoria e gráfico dos últimos seis meses
usam a data de efetivação quando preenchida. Sem efetivação, usam a data de
vencimento e o valor previsto. A data de lançamento serve como registro e não
como referência desses totais. Pagamentos antecipados ou atrasados pertencem ao
mês da efetivação. Assim, os totais incluem movimentos efetivados e previstos.

O saldo efetivado permanece acumulado por conta, incluindo saldo inicial e
movimentos efetivados até o fim do mês. O saldo projetado acrescenta os pendentes
até esse corte, pela efetivação agendada quando houver, ou pelo vencimento.
Transferências entre contas não entram como receita ou despesa. Contas e
movimentos excluídos das análises continuam fora dos gráficos e totais mensais.
As listas mantêm o filtro padrão por vencimento; os filtros avançados permitem
consultar lançamento, vencimento ou efetivação.


### Contas: mês e participação no saldo consolidado

A aba Contas compartilha o mês do Resumo, com setas, seleção direta de mês/ano
e retorno ao mês atual. Cada conta mostra seu saldo efetivado até o último dia
do mês e sua projeção até esse mesmo corte.

O menu da conta permite “Excluir do saldo do mês” e “Incluir no saldo do mês”.
A opção também aparece no formulário. Ela controla apenas a soma consolidada
do Resumo e de Contas; a conta mantém seu saldo individual e seus movimentos.
“Incluir em análises” continua independente e controla receitas, despesas e
gráficos. Aplicações podem ficar fora do consolidado, permanecendo na lista.

Contas existentes e novas começam incluídas. A migration v6 adiciona a
preferência sem alterar registros financeiros. Backups v1 a v6 são aceitos;
restaurar um backup antigo preserva os dados e aplica a migration.


### Gráficos disponíveis no celular — 01/10/2026

O dashboard Android também apresenta “Gastos por categoria”, logo abaixo de
“Receitas vs Despesas” e antes das transações recentes. O gráfico circular usa
o mesmo componente e os mesmos dados do desktop, separados por moeda e mês.
Em telas estreitas ou com texto ampliado, a legenda fica abaixo do gráfico.
Sem despesas, exibe uma mensagem; os filtros e cálculos financeiros permanecem
os mesmos. A inclusão deste gráfico atualiza a composição mobile anterior.


## Revisão #35 — cabeçalho e formulários Android (01/10/2026)

Esta revisão substitui a linha exclusiva do mês no dashboard: menu, marca e seletor compacto `‹ Out 2026 ›` ficam na mesma linha. Mantém setas e seleção direta de mês/ano; em telas estreitas ou com texto ampliado utiliza o símbolo Somia para preservar espaço e alvos de toque. O mês continua compartilhado entre seções.

Receitas, despesas e transferências passam a abrir uma rota em tela cheia no Android, na criação e edição, com voltar, título específico, formulário rolável e botão “Salvar lançamento” no rodapé da área disponível. O teclado redimensiona essa área, mantendo campos e ação acessíveis. No Windows permanece uma janela central.

Ordem: Descrição → Valor → Conta (ou origem/destino) → Categoria → Subcategoria → Lançamento/Vencimento → Pago/Recebido/Efetivada → data de efetivação. As datas ficam em duas colunas quando couberem e empilhadas em telas estreitas/texto ampliado. Descrição recebe foco ao criar; Próximo vai para Valor com teclado decimal, sem salvar. O valor recebe destaque visual.

“Mais detalhes” reúne o seletor de tipo no formulário genérico de lançamentos. Nos formulários com tipo fixo e nas transferências, não há outros campos opcionais existentes para apresentar, portanto a seção não é exibida vazia. A descrição de transferências é persistida e aparece na lista e nas transações recentes.

Referências consultadas: `1000067405.jpg` e `1000067409.jpg`, além dos requisitos completos na issue #35. Calculadora integrada permanece pós-MVP.


## Revisão da navegação — 23/10/2026

No Android em telas estreitas, a barra inferior passa a exibir Resumo,
Movimentos, Relatórios e Cartões. Relatórios abre a área existente de Análises.
O botão + fica flutuante em Resumo e Movimentos, com Receita, Despesa e
Transferência. O menu é aberto pelo cabeçalho e ocupa parte da largura,
preservando o contexto da página. Suas seções Finanças, Planejamento e
Aplicativo ficam abertas e roláveis; as funções existentes são preservadas,
incluindo acesso direto à sincronização. O perfil é genérico enquanto não
houver cadastro de usuário. Não exibir nomes ou saldos ilustrativos.

Esta revisão substitui as decisões antigas de navegação mobile deste
documento. Mantém tema escuro, monograma S oficial, azul acinzentado, cores
semânticas e componentes atuais. A sidebar de telas largas permanece.
