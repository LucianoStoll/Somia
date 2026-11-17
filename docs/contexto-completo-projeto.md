# Somia — contexto completo do projeto

> Documento de continuidade do projeto. Fotografia do estado em **14/10/2026**. Resume decisões, funcionalidades, entregas, validações e trabalho planejado a partir da documentação e das issues do repositório e do histórico de trabalho do projeto. Quando o status de uma entrega divergir entre este resumo e a issue/CI mais recente, prevalecem a issue e os artefatos atuais.

## 1. Visão do produto

**Somia** é um aplicativo de finanças pessoais para Android e Windows, criado inicialmente para uso offline e controle financeiro claro. O projeto prioriza uso local, privacidade, consistência dos saldos e uma experiência simples para registrar receitas, despesas, transferências, cartões, investimentos e compromissos.

Objetivos e princípios:

- Funcionar offline e manter os dados no dispositivo.
- Manter Android e Windows com as mesmas regras financeiras.
- Apresentar valores realizados e previstos sem duplicar movimentações.
- Preservar dados em atualizações, migrations, backup e sincronização.
- Manter valores monetários com precisão de centavos.
- Evoluir em ciclos pequenos, documentados e validados pelo usuário.
- A versão alpha 3 não deve ser publicada nem integrada à branch `main` antes de concluir e validar seu escopo.

Repositório: [LucianoStoll/Somia](https://github.com/LucianoStoll/Somia). A branch `main` contém a v0.2.0-alpha publicada; o ciclo ativo é a **v0.3.0-alpha**, com branches auxiliares de funcionalidades. Este documento foi gravado na branch de trabalho `v0.3.0-alpha-cashback-crud`.

## 2. Regras financeiras e decisões que devem ser preservadas

### Lançamentos, datas e saldos

- Receitas e despesas têm data de lançamento, vencimento e efetivação.
- Um movimento efetivado afeta o realizado pela data de efetivação. Se ainda não estiver efetivado, a projeção usa o vencimento.
- Ao efetivar compromisso de outra data, oferecer contabilizar hoje ou no vencimento.
- Transferências são um único registro que afeta duas contas; não duplicar a movimentação.
- O saldo de uma conta soma seu saldo inicial e movimentos até o fim do mês consultado.
- A projeção também considera compromissos não efetivados até a data de corte.
- O saldo é acumulado entre meses; meses futuros usam o saldo anterior mais movimentos previstos.
- A exclusão de uma conta do saldo consolidado não deve ocultar a conta nem apagar seu extrato.
- Receitas/despesas e gráficos usam efetivação, quando existe, e vencimento quando pendente. Filtros de lista podem começar pelo vencimento e ser refinados.
- Multimoeda deve manter cada moeda separada; não converter silenciosamente para BRL.
- Valores monetários são armazenados em unidades menores inteiras, nunca em ponto flutuante como fonte de verdade.

### Cartões e faturas

- Compras no cartão são despesas vinculadas à compra/fatura; pagamento de fatura é liquidação de caixa e não deve contabilizar as compras como despesa uma segunda vez.
- Limite considera o total comprometido das compras parceladas e libera conforme a liquidação.
- Fatura do mês, dívida total, saldo anterior e saldo credor são conceitos diferentes.
- Preservar pagamentos parciais, antecipações, estornos, histórico de fechamento e edição de compras ligadas a faturas já pagas.
- Em pagamento parcial de fatura, permitir indicar quais compras foram cobertas quando essa informação for necessária ao cálculo do cashback.
- Cartão de débito, compras internacionais, cartões adicionais e importação de faturas ainda têm decisões/etapas específicas; consultar #76 e #12.

### Cashback definido para o módulo de cartões

Decisões de produto registradas na #76 e refinamentos solicitados em 14/10:

- Configuração por cartão pode usar percentual fixo ou faixas de gasto mensal, com teto mensal opcional.
- A faixa mensal considera o valor efetivamente pago no mês. A base do cashback pode ser o valor total da compra, conforme a regra final aprovada para cada modalidade.
- **Compra parcelada gera o cashback integral uma única vez no primeiro pagamento da compra; parcelas posteriores não geram novamente cashback.** Não ratear o cashback proporcionalmente às parcelas.
- Cashback é receita separada, prevista até confirmação. Não efetivar automaticamente nem reduzir o valor original da despesa.
- Permitir escolher conta de recebimento e categoria/subcategoria; preservar os valores já confirmados e o histórico.
- Estão definidos modos de crédito no primeiro pagamento e em dia mensal configurado. Previsões do modo mensal vencem no próximo dia configurado.
- Alterar configuração recalcula previsões ainda não recebidas sem reescrever confirmações anteriores.
- Estorno antes do recebimento recalcula/cancela a previsão; após recebimento, qualquer devolução deve ficar pendente para confirmação.
- Complementos de faixa e ajustes de teto devem ser novos registros rastreáveis, sem mutar valores recebidos e sem duplicação por recálculo/sync.
- O trabalho mais recente pediu CRUD para a configuração, possibilidade de excluir a configuração/valores configurados e proteção para não editar/excluir valores já lançados/recebidos. Interpretar “excluir valores” no contexto da configuração com cautela: não apagar receitas confirmadas nem histórico financeiro.
- Branch auxiliar atual: `v0.3.0-alpha-cashback-crud`. Verificar a CI e os artefatos mais recentes antes de marcar a implementação e APK como prontos para validação. O nome da branch, isoladamente, não significa que o usuário validou a funcionalidade.

## 3. Plataforma e arquitetura

- Flutter e Dart; suporte a Android e Windows.
- Persistência local Drift/SQLite; migrations incrementais e não destrutivas.
- Organização por `core` e `features`; BLoC/Cubit, go_router e get_it.
- Uso offline-first; sincronização Android/Windows por Google Drive foi adicionada no ciclo anterior.
- O app identifica o pacote Android como `com.example.finapp`; manter identificador e chave de assinatura persistente para atualizar sem desinstalar e preservar os dados.
- Windows é distribuído como ZIP completo em modo release; manter executável, DLLs e diretório de dados juntos.
- Fluxo técnico usual: `flutter pub get`, formatação Dart, `flutter analyze` e `flutter test`.
- A CI do GitHub executa formatação/análise, testes Linux e Windows, guardas de publicação, prévias Android/Windows, build Windows e APK Android assinado. O número de testes varia entre commits.
- Atualizar Android e Windows antes de sincronizar quando uma migration mudar o schema.
- Não publicar ou sobrescrever uma release já publicada. Alpha de desenvolvimento só recebe release depois da validação do escopo.

## 4. Linha do tempo das versões

### MVP — v0.1.0-alpha — concluído e validado

Validado pelo usuário em 01/10/2026. Inclui:

- CRUD de contas, categorias e subcategorias.
- Receitas, despesas e transferências.
- Datas de lançamento, vencimento e efetivação.
- Dashboard mensal com receitas/despesas, categorias e transações recentes.
- Filtro de mês compartilhado entre Resumo, Receitas, Despesas, Transferências e Contas.
- Saldo efetivado e projetado por conta e consolidado.
- Tema escuro Somia e adaptação para celular e computador.
- Formulários de lançamentos em tela cheia no Android.
- Backup local, migrations não destrutivas e APK atualizável com assinatura persistente.
- Fechamento documentado pelas issues #30–#35, incluindo checklist #33 e ajustes #35. A publicação da versão foi consolidada na sequência #10.

### Pós-MVP — v0.2.0-alpha — publicada e validada em 06/10/2026

A release está em [GitHub Releases](https://github.com/LucianoStoll/Somia/releases/tag/v0.2.0-alpha). Principais entregas:

- Calculadora monetária reutilizável, entrada por teclado e edição do valor pela lista.
- Linhas compactas e efetivação/desfazer com feedback.
- Voltar no Android retorna pelas seções e só permite sair do Resumo.
- Formulários unificados de contas/categorias e catálogo de bancos com logos locais.
- Recorrências e parcelamentos de receitas, despesas e transferências.
- Cartões de crédito, compras, faturas, limite, pagamentos parciais/antecipados, estornos e saldo credor.
- Autocomplete e sugestão de classificação a partir do histórico.
- Consulta de valores no gráfico e detalhamento do saldo; detalhe/extrato diário por conta.
- Backups automáticos locais, backups manuais no Google Drive em Android e Windows, restauração sem reiniciar e sincronização Android ↔ Windows, manual e automática com app aberto.
- Importação CSV com mapeamento, prévia, duplicados e gravação atômica.
- Ajustes de integridade, migrations, backups e publicação por versão.
- Issues #34, #37–#56 e #54/#57 registram entregas, validações e fechamento do ciclo.

### Desenvolvimento — v0.3.0-alpha — em andamento

Ciclo aberto em 06/10/2026 a partir da v0.2.0-alpha. O usuário incluiu as pendências das epics #11–#16 e uma revisão ampla de UX (#59). Não publicar a alpha 3 antes de concluir e validar o ciclo (#58).

Entregas concluídas e validadas pelo usuário:

- **#60/#61:** rateio interno de receitas, despesas e compras por categoria/subcategoria, por percentual ou valor; correção da edição/exclusão de compras em faturas com pagamentos. Validadas em 06/10/2026.
- **#62:** investimentos iniciais CDB/CDI e poupança, com aportes, resgates e rendimento/saldo informado manualmente. Validada em 06/10/2026.
- **#63/#64:** melhorias de fatura e bens/patrimônio com avaliações manuais. #64 validada em 06/10/2026.
- **#65:** dívidas/empréstimos e financiamento ligados a despesas existentes, principal separado de juros/encargos, amortização manual e reflexo no patrimônio. Validada em 07/10/2026.
- **#67:** pessoas e reembolsos vinculados a despesas, com recebimentos parciais e histórico. Validada em 08/10/2026.

Entregas tecnicamente implementadas, mas com validação de uso ainda pendente ou acompanhamento aberto:

- **#68:** separar menus de patrimônio e dívidas e organizar reembolsos como receitas previstas, com definição de categoria ao efetivar.
- **#70:** anexos locais de lançamentos com hash/integridade e inclusão no backup; issue aguardando validação manual.
- **#71/#72:** fluxo para substituir uma base desatualizada do Drive pela atual do Android, com proteção de versões/conflitos. A implementação está registrada; #71 deve permanecer até validação manual.
- **#73/#74:** edição em lote iniciada pelo menu de três pontos e CRUD de investimentos/correção da conta vinculada. Implementação técnica entregue; validação manual pendente.
- **#75:** análises por categoria, comparação mensal, compromissos futuros e saldo por tipo de conta. Validação manual pendente.
- **#77/#78:** resumo com visão de caixa, vencimentos, curva diária e adaptação Android/Windows; CI e pacotes gerados, aguardando avaliação pelo uso.
- **#79:** transporte/sincronização de anexos Android/Windows pelo Drive, com hashes, retomada e deduplicação; implementação validada tecnicamente, acompanhamento da epic ainda aberto para validação de uso.
- **#80:** exportação das análises em Excel/PDF para Android e Windows; CI 329 aprovou 601 testes em Linux e 601 em Windows, além de análise, guardas e pacotes. Validação manual pelo uso permanece como pendência da epic #14.
- **#81:** novo layout visual do Resumo aprovado em 13/10, em branch separada `v0.3.0-alpha-dashboard-visual`; ainda requer CI/prévias e validação do usuário em Android e Windows.

O módulo de cashback está detalhado na #76 e tem trabalho recente na branch `v0.3.0-alpha-cashback-crud`. Documentar a conclusão só após confirmar CI, APK assinado/pacote Windows e validação manual.

## 5. Escopo restante do ciclo v0.3.0-alpha

Consultar sempre a [issue #58](https://github.com/LucianoStoll/Somia/issues/58), a epic relacionada e o status atualizado das issues antes de iniciar uma tarefa.

### #11 — transações avançadas

- Concluir e validar baixas parciais de receitas/despesas (#69), com conta/data por pagamento, saldo restante previsto, histórico e desfazer sem duplicação.
- Validar anexos (#70) e o transporte entre dispositivos (#79).
- Continuar a revisão das telas e fluxos (#59); edição em lote implementada em #74 aguarda avaliação.
- Completar a separação de menus/previsões de reembolso (#68).
- Tags, estabelecimentos, lixeira e demais pendências devem seguir as issues, sem presumir que itens não detalhados já estão implementados.

### #12 — cartões e faturas

- Consolidar as regras de cashback e CRUD conforme #76 e branch atual.
- Implementar e detalhar por etapa: cartão de débito, compras internacionais, cartões adicionais e importação de faturas.
- Preservar regras do crédito já validadas; evitar criar passivos/faturas de crédito em compras de débito.
- Não incluir pontos/milhas, resgate de recompensas, cashback como crédito em fatura ou conexão bancária automática sem decisão explícita.

### #13 — orçamento, metas e educação financeira

Decisões já aprovadas: orçamento mensal por categoria com **previsto e realizado**; metas e reserva ligadas a contas existentes, usando saldos para atualizar progresso sem duplicar patrimônio. Escopo planejado inclui limites por categoria/subcategoria, histórico mensal, metas com valor-alvo/prazo, reserva, indicadores de renda/taxa de poupança e alertas explicáveis. Separar moedas e respeitar rateios e pagamentos de cartão.

### #14 — relatórios, importação e conciliação

- CSV de receitas/despesas já implementado e validado na v0.2; sugestão de reutilizar uma coluna de data permanece opcional/futura.
- Exportação Excel/PDF das análises entregue tecnicamente em #80.
- OFX, conciliação e outras rotinas de importação/exportação ainda estão abertas e exigem detalhamento.
- #75 implementa análises e aguarda validação manual.

### #15 — patrimônio, dívidas e investimentos

- Bens/patrimônio, dívidas/amortização e CDB/CDI/poupança já implementados e validados.
- CRUD de investimentos e correção de conta em #74 aguardam validação.
- Outros tipos de investimentos, moedas, cotações e demais itens da epic precisam de decisão detalhada; não presumir integração de cotações nem conversões.

### #16 — backup e sincronização

- Backup local e Drive, restauração e sincronização manual/automática entre Android e Windows foram implementados na v0.2.
- Substituição protegida da base remota atualizada, #71/#72, aguarda validação de uso.
- Anexos sincronizados, #79, devem ser conferidos na validação integrada.
- Manter proteções contra perda de dados, versões concorrentes, incompatibilidade de schema e duplicação de registros.

### #59 — experiência de uso

Revisar Android e Windows durante cada entrega e ao final do ciclo: navegação, formulários, ordem/foco de campos, teclado/Enter/Tab, calculadora, seletores, mensagens de erro, feedback/desfazer, estados vazios, rolagem, texto ampliado, acessibilidade e retorno ao contexto de origem. Melhorias de UX devem preservar regras financeiras já validadas.

## 6. Resumo visual do dashboard e dados de referência

O dashboard em evolução busca combinar visão de caixa, valores a receber/pagar, previsão final, curva diária de saldo, categorias, tipos de conta e vencimentos. A #77 registra componentes funcionais; a #81 registra a proposta visual aprovada, com tema grafite e pastéis. Preservar:

- filtro de mês e corte de saldo existentes;
- realizado distinto de previsto e do resultado mensal;
- moedas separadas;
- contas fora do consolidado visíveis em seus próprios contextos;
- cartões sem duplicar compras e liquidações;
- consulta por dia e efetivação conforme regras atuais;
- responsividade no Android, Windows e com fonte ampliada.

Imagens de referência são orientação visual, não fonte de cálculo. A validação final deve ocorrer com dados reais do usuário no aparelho e no Windows.

## 7. Histórico de testes e entregas verificadas

Os números abaixo pertencem a builds específicas e não descrevem necessariamente a branch mais recente:

- MVP e release v0.2 passaram por testes de CI e validação de uso; documentação detalhada em `CHANGELOG.md`, `docs/releases/` e issues.
- #60/#61: CI 215, 379 testes Linux e 379 Windows; pacote Android e Windows revisados; validados pelo usuário.
- #62: entrega de investimentos validada pelo usuário.
- #65: build 231 aprovada e validação manual confirmada.
- #67: build 246, 465 testes Linux e 465 Windows, pacotes Android/Windows revisados e validação manual confirmada.
- #77/#78: CI 313, 580 testes Linux e 580 Windows; prévias e pacote Windows conferidos; APK assinado disponível; uso aguardando avaliação.
- #79: CI 323, 590 testes Linux e 590 Windows, com testes de transporte/hash/retomada/deduplicação e backups.
- #80: CI 329, 601 testes Linux e 601 Windows, Excel/PDF reabertos/inspecionados e prévias revisadas.
- Os builds de CI devem ser conferidos no commit/branch da tarefa antes de reutilizar links ou marcar uma issue como validada.

## 8. Documentos e fontes principais no repositório

- [README](../README.md) — visão geral, versões e instalação.
- [Roadmap](roadmap.md) — estratégia de versões e marcos.
- [Arquitetura](arquitetura.md) e [requisitos](requisitos.md) — base técnica e escopo.
- [Especificação do produto](especificacao-produto.md).
- [Guidelines de desenvolvimento](guidelines-desenvolvimento.md).
- [Identidade visual](identidade-visual.md).
- [Changelog](../CHANGELOG.md) e [notas v0.2.0-alpha](releases/v0.2.0-alpha.md).
- [Ciclo v0.3.0-alpha](ciclos/v0.3.0-alpha.md).
- Issues principais: [#58 ciclo](https://github.com/LucianoStoll/Somia/issues/58), [#59 UX](https://github.com/LucianoStoll/Somia/issues/59), [#76 cartões/cashback](https://github.com/LucianoStoll/Somia/issues/76), [#77 resumo](https://github.com/LucianoStoll/Somia/issues/77) e [#81 layout do resumo](https://github.com/LucianoStoll/Somia/issues/81).

## 9. Como continuar o trabalho

1. Conferir a branch de versão ativa e evitar desenvolver em uma branch antiga ou divergente.
2. Ler a issue e a documentação do módulo antes de alterar comportamento; decisões registradas do usuário prevalecem sobre suposições.
3. Separar claramente implementado, CI aprovado, entregue para teste e validado manualmente.
4. Testar cálculos e integridade de dados, além da interface; cobrir migrations, backup/sync e Android/Windows quando a mudança os afetar.
5. Gerar os pacotes do mesmo commit da implementação, conferir assinatura persistente/versionCode e fornecer ZIP Windows completo.
6. Registrar resultados, limitações e roteiro de validação na documentação/issue.
7. Só encerrar issue quando a validação exigida estiver concluída; só integrar e publicar v0.3.0-alpha após validar o ciclo completo.

## 10. Limites deste resumo

Este arquivo é um mapa para continuidade, não substitui especificações, commits, CI ou decisões detalhadas nas issues. Evita incluir lançamentos, saldos, documentos financeiros pessoais ou dados de teste privados do usuário. Não considerar uma ideia futura como escopo autorizado até que esteja documentada e aprovada.
