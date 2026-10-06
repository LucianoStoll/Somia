# Changelog

## v0.3.0-alpha — em desenvolvimento

- #61: corrigir/excluir compras em faturas com pagamentos reais/agendados, inclusive mudança de data/fatura, preservando caixa e liquidações. Confirmação, histórico de exclusão e proteção de estornos. Validação conjunta com #60 pendente.

- #60: rateio por categoria/subcategoria, por valor ou percentual, em receitas/despesas/compras; centavos exatos, séries/parcelas/estornos, gráficos e filtros sem duplicação. Migration v12 com validação de backup/sync e preservação de pacotes históricos. [Regras e validação](docs/rateio-categorias.md); validação manual pendente.

Ciclo criado em 06/10/2026 a partir da v0.2.0-alpha integrada pelo [PR #57](https://github.com/LucianoStoll/Somia/pull/57). Planejamento e acompanhamento na [#58](https://github.com/LucianoStoll/Somia/issues/58) e no [documento do ciclo](docs/ciclos/v0.3.0-alpha.md).

- Versão atualizada no pubspec e na identificação local do app.
- README, fluxo de contribuição, guidelines e roadmap atualizados para a nova branch.
- Escopo aprovado em 06/10/2026: conclusão das epics #11–#16 e frente de experiência/telas/campos #59. Sequência, dependências e critérios documentados; funcionalidades ainda em planejamento. A base preserva todas as entregas validadas da v0.2.0-alpha.

## v0.2.0-alpha — 2026-10-06 (pós-MVP)

Escopo validado pelo usuário, incluindo #54 e #56 em 06/10/2026. [Notas consolidadas](docs/releases/v0.2.0-alpha.md) e [inventário de arquivos/commits](docs/releases/v0.2.0-alpha-files.md). Publicação por versão, com notas próprias, pacotes verificados e proteção contra sobrescrever releases publicadas ou tags de outro commit.

- #54: restauração e sincronização compartilham a verificação de consistência financeira; backups com tipos, hierarquia, moedas ou vínculos de cartão inválidos são rejeitados sem substituir os dados atuais.
- #54: troca de moeda também bloqueada para contas vinculadas a cartões, pagamentos e lançamentos excluídos, preservando o histórico.
- #53 validada pelo usuário em 05/10/2026.

- #56 / #14: importação CSV por conta com mapeamento, prévia, seleção e identificação de duplicados, categorias pelo nome/histórico, datas e centavos validados e gravação atômica. Lançamentos sem efetivação entram pendentes; nenhum dado é substituído.

- Ajustes: escolha entre sincronizar a cada alteração salva ou agrupar alterações, com preferência persistente e notificações após commit.

- #55: sincronização automática após vínculo explícito, ao abrir/retomar e após alterações agrupadas; consulta remota enquanto aberto, repetição com espera crescente, preferência persistente, proteção de formulários e manutenção da seção após atualização. Botão manual e fluxo de backup continuam disponíveis.

- #49 validada pelo usuário em 05/10/2026; fechamento da alpha acompanhado na #54: sincronização, importação CSV #14 e revisão final.
- #53 / #16: sincronização manual privada Google Drive Android ↔ Windows, base inicial Android e recebimento confirmado com proteção local; fila persistente, conflitos pela alteração mais recente, recuperação de versões, relógio/conta verificados e telas atualizadas com o app aberto. Migration v11 com cópia antes de atualizar; restauração desvincula a sincronização. Faturas novas têm identidade comum por cartão/mês para compras offline nos dois dispositivos.

- #52 / #16: restauração local e Google Drive aplicada com o app aberto, substituição atômica e proteção dos dados atuais; telas e formulários recarregados após sucesso, sem reiniciar.
- #51 validada pelo usuário em 05/10/2026.
- #50 validada pelo usuário em 05/10/2026.
- #51 / #16: backup no Google Drive para Windows, autorização no navegador com PKCE e callback local, configuração por JSON Desktop, renovação de autorização e credenciais protegidas por DPAPI fora do banco financeiro; mantém envio/restauração manuais e proteção local.

- #50 / #16: backup manual privado no Google Drive para Android, seleção e autorização nativas da conta, envio/listagem/restauração confirmada com verificação de tamanho, hashes e SQLite; desconexão local, proteção contra troca de conta e preservação de backup local. Windows e sincronização entre dispositivos ficam para entregas seguintes.

- #49 / #16: backup automático diário com três versões, lista de cópias locais, criação manual, exportação/restauração e cancelamento de restauração preparada; proteção consistente dos dados atuais antes de restaurar, retenção separada e erro visível sem bloquear o uso financeiro.
- #44 validada pelo usuário em 05/10/2026.

- #44: escala monetária e linhas alinhadas no gráfico Windows, intervalos legíveis, indicação da moeda e barras zeradas vazias; suporta janela estreita e texto ampliado.
- #37 validada pelo usuário em 05/10/2026.

- #37: tocar/clicar num mês do gráfico Receitas × Despesas mostra mês/ano, receitas, despesas e resultado do mês; balão adapta posição/tamanho, troca de mês e atualização de dados, fecha ao tocar fora ou rolar. Android e Windows, offline.
- #38 validada pelo usuário em 05/10/2026.
- #38: tocar no saldo abre sua composição consolidada e prevista, por moeda, com saldo inicial, receitas/despesas, transferências e cartões; painel inferior no Android e diálogo no Windows, usando o mesmo corte mensal do dashboard.
- #45 validada pelo usuário em 05/10/2026.
- #45: detalhes da conta ao tocar na lista, abas Realizado/Previsto, saldos e totais mensais, gráficos e extrato agrupado por dia com saldo diário; somente consulta, incluindo transferências e pagamentos de cartão sem duplicar compras.
- #48: lista de sugestões ao digitar trechos da descrição, com conta/cartão e valor; escolher reutiliza descrição, classificação, origem e valor, mantendo datas/efetivação independentes.
- #48: categoria/subcategoria preenchidas pela descrição de lançamentos anteriores ao criar receitas/despesas e compras no cartão; escolha manual e edição preservadas. Histórico offline, classificação válida mais recente e separação por tipo.
- #47: linha de fatura no estilo da referência, com nome “Cartão - nome”, total, vencimento e etiqueta azul de fechamento.
- #47: Despesas agrupa por fatura, abre detalhes no cartão e permite pagar o saldo restante pelo ícone, com desfazer/ajustar data e preservação de pagamentos parciais e agendados.
- #47: cartões e faturas offline, compras integradas às despesas, parcelamentos e limite total comprometido, liquidações parciais/antecipadas com encargos/desconto, carry-over derivado sem duplicação, estornos e saldo credor. Migration v10 e histórico de mudanças.
- #46 validada pelo usuário em 02/10/2026.

- #46: recorrências e parcelamentos em receitas, despesas e transferências, por quantidade e sempre pendentes; frequências/intervalos, parcelamento por total ou valor individual, centavos exatos, calendário com último dia disponível e ações isoladas/em série protegendo efetivados. Migration v9 e backup compatível.
- #41 validada pelo usuário em 02/10/2026.

- #41: catálogo offline com busca e logos de instituições na criação/edição de contas, lista e seletores dos lançamentos; nome personalizado independente, opção de ícone padrão e migration v8 preservando contas antigas e backups.
- #39 e #40 validadas pelo usuário em 01/10/2026, incluindo as correções em Transferências.

- #40: cadastros de contas, categorias e subcategorias no mesmo formulário dos lançamentos, tela cheia no Android e janela adaptada no Windows; saldo inicial usa calculadora com suporte a zero e valores negativos.

- Correção após teste da #39: proteção do Voltar também no navegador principal; ícone de transferência efetivada permite retornar a pendente, atualizando os dois saldos.

- #39: Voltar no Android fecha primeiro sobreposições, retorna das seções ao Resumo e só permite saída padrão no Resumo. Formulários alterados pedem confirmação de descarte.

- #43: tocar no valor de receitas, despesas ou transferências abre a calculadora com o valor atual; confirmar atualiza apenas o valor e os totais, cancelar mantém o original.
- Ajustes #42: feedback de efetivação desaparece em 5 segundos; ícone de receita/despesa efetivada permite voltar a pendente; efetivados ficam no topo.

- #42: listas compactas de receitas, despesas e transferências com status à esquerda, conta, descrição, datas, valor e etiquetas de categoria/subcategoria.
- Efetivar hoje pelo ícone; desfazer conserva a data anterior (inclusive agendamento), e ajustar data está disponível no feedback e no menu.
- Alteração restrita à efetivação, proteção contra repetição e comparação da data esperada para rejeitar ações antigas. Os dois saldos de transferências continuam calculados a partir do mesmo registro.
- #34 validada pelo usuário em 01/10/2026.

- #34: calculadora monetária reutilizável como entrada de valores em receitas, despesas e transferências, incluindo avanço da descrição por Enter.
- Entrada direta, `00`, vírgula, limpar/apagar, soma, subtração, multiplicação, divisão, resultado e confirmação; cancelar/voltar preserva o valor anterior.
- Operações com precedência convencional e frações exatas de `BigInt`; arredondamento final para centavos, metade para fora de zero. Divisão por zero, operações incompletas, valores fora do limite e valores não positivos nos lançamentos são rejeitados.
- Painel rolável no Android, janela no Windows e suporte a teclado físico. Sem mudança no banco de dados.


## 0.1.0-alpha — 2026-10-01

Primeiro MVP do Somia, validado pelo usuário nas issues #30, #31, #32, #35 e no checklist final #33. Fechamento acompanhado pela #10.

### Funcionalidades
- Contas, categorias e subcategorias com cadastro, edição e arquivamento.
- Receitas, despesas e transferências com valores monetários inteiros.
- Lançamento, vencimento e efetivação separados; confirmação para contabilizar hoje ou no vencimento em compromissos passados/futuros.
- Saldo acumulado efetivado e projeção individual/consolidada até o fim do mês escolhido.
- Participação no saldo do mês independente das análises, permitindo separar aplicações.
- Dashboard mensal com receitas/despesas, histórico de seis meses, gastos por categoria e transações recentes, também no celular.
- Seletor mensal compartilhado, navegação por setas, seleção de mês/ano e filtros avançados nas listas.
- Tema escuro e identidade Somia, drawer mobile e sidebar no PC.
- Formulários Android em tela cheia, fluxo Descrição → Valor, teclado decimal e controles responsivos; janelas no Windows.
- Descrição de transferências persistida e exibida nas listas.
- Backup SQLite com exportação, validação e restauração ao reiniciar; migrations até o schema v7.
- Ajuda sobre saldos e identificação da versão/compilação nos Ajustes.

### Correções e distribuição
- Resumo e gráficos usam efetivação quando preenchida, ou vencimento nos movimentos previstos, incluindo lançamentos registrados em outro mês.
- Ajustes de espaçamento, paisagem, telas estreitas e texto ampliado.
- APK release com chave persistente, verificação de certificado/package e número crescente de compilação.
- Pacote Windows x64 em modo release; pré-release GitHub com APK, ZIP Windows, relatório de assinatura e SHA-256.
- CI com formatação, análise, 57 testes, testes no Windows, prévias mobile e builds de ambas as plataformas.

### Instalação e limites
Instale o APK sobre a versão anterior, sem desinstalar. No Windows, extraia todo o ZIP e abra `finapp.exe`. Faça backup pelos Ajustes; a restauração é aplicada após fechar e abrir o app.

Esta versão é offline e mantém dados locais. Sincronização, cartões, recorrências, calculadora integrada, tema claro e backup automático ficam para os próximos ciclos.
