# Roadmap — Somia

## Estratégia

O MVP e as versões v0.2.0-alpha/v0.3.0-alpha foram concluídos. O ciclo ativo é **v0.4.0-alpha**, em prévia, com importação/conciliação e melhorias de interface.

Atualização: **03/11/2026**. Neste documento, `[x]` indica implementação disponível na versão indicada; validação manual e publicação são acompanhadas separadamente. Recursos futuros não passam a integrar o ciclo apenas por constarem no roadmap.

## Situação atual

| Área | Estado | Referência |
| --- | --- | --- |
| Versão publicada em `main` | v0.3.0-alpha, schema 26 | [Notas](releases/v0.3.0-alpha.md) |
| Ciclo ativo | v0.4.0-alpha, schema 27; PR de fechamento em rascunho | [PR #89](https://github.com/LucianoStoll/Somia/pull/89) |
| Importação e conciliação | CSV/XLSX, perfis, prévia, conciliação assistida, lotes e desfazer implementados na alpha | [Importação](importacao-csv.md) |
| Interface integrada na alpha | Movimentos/transferências, Cartões, Planejamento, menu e Dívidas | PRs #90–#94 |
| Refinamento da lista de Cartões | PR aberto; aguarda integração | [PR #95](https://github.com/LucianoStoll/Somia/pull/95) |
| Cards detalhados de Contas, sem saldo consolidado no topo | PR aberto; aguarda integração | [PR #96](https://github.com/LucianoStoll/Somia/pull/96) |
| Acesso direto aos recentes | Implementado nesta contribuição; aguarda integração à alpha e validação em aparelho | [Resumo](resumo-dashboard.md) |

A integração das prévias não autoriza merge em `main` nem publicação de uma release.

## Controle de versões e branches

Cada ciclo de desenvolvimento deve possuir uma branch principal com o **nome exato da versão**, por exemplo `v0.1.0-alpha`, `v0.2.0-alpha` ou `v0.5.0-beta`.

Todas as issues previstas para aquela versão devem ser implementadas e validadas nessa branch. Evitar branches paralelas desnecessárias; quando uma branch auxiliar for indispensável, ela deve retornar para a branch da versão, nunca diretamente para `main`.

A branch `main` representa somente versões concluídas/estáveis dentro do marco planejado. **O merge da Pull Request da versão para `main` só deve ocorrer quando o escopo estiver concluído e validado.** Um PR em rascunho pode acompanhar a prévia, como o #89. Depois do merge, a versão recebe tag/release/changelog e inicia-se uma nova branch com o nome da próxima versão.

Antes de qualquer implementação, verificar qual é a branch de versão ativa e manter controle das branches existentes para evitar trabalho divergente ou abandonado.

## Situação do MVP

O ciclo `v0.1.0-alpha` foi aprovado em 01/10/2026, sem bugs relatados no checklist #33. #30, #31, #32 e #35 estão concluídas. A #10 consolida documentação, PR para `main` e publicação dos pacotes Android/Windows.

## Fase 0 — Fundação
- [x] Visão, questionário e escopo
- [x] Offline-first e preparação para sync
- [x] Stack e arquitetura alvo
- [x] Criar branch de versão `v0.1.0-alpha`
- [x] Reorganizar Flutter em core + features
- [x] Configurar Drift, BLoC/Cubit, go_router e get_it
- [ ] Ambientes dev/test/prod (próximo ciclo)
- [x] GitHub Actions: formatação, análise, testes, prévias mobile, builds e publicação
- [x] Guidelines, branches/commits e PR template

## Fase 1 — Persistência do núcleo
- [x] Drift/SQLite
- [x] UUID e metadados sync-ready
- [x] Valores monetários inteiros
- [x] Migrations versionadas
- [x] Conta
- [x] Categoria/Subcategoria
- [x] Transação
- [x] Transferência
- [x] Arquivamento/soft delete
- [x] Saldo atual/projetado

## Fase 2 — MVP / v0.1.0-alpha
- [x] CRUD e arquivamento de contas
- [x] CRUD e arquivamento de categorias/subcategorias
- [x] Receitas e despesas
- [x] Transferências sem duplicidade
- [x] Lista/filtros essenciais
- [x] Dashboard básico
- [x] UI Android/Windows
- [x] Tema escuro aprovado; tema claro/sistema nos próximos ciclos
- [x] 100% offline
- [x] Validação manual

### Revisão final antes da conclusão do MVP
- [x] receitas, despesas e transferências com data de lançamento, vencimento e efetivação;
- [x] saldo realizado baseado na data de efetivação e projeções baseadas no vencimento;
- [x] aviso ao efetivar compromisso passado ou futuro: contabilizar hoje ou no vencimento;
- [x] migration Drift/SQLite não destrutiva para preservar bases já usadas;
- [x] APK Android atualizável sobre a instalação anterior, com assinatura persistente e build number crescente;
- [x] teste de atualização preservando os dados locais;
- [x] backup/exportação e importação simples como proteção durante os testes;
- [x] remover barra inferior no mobile e adotar drawer/menu lateral;
- [x] Receitas e Despesas como áreas independentes no menu;
- [x] manter tema escuro no MVP e preparar os componentes para tema claro futuro.

Issues de acompanhamento concluídas: #30, #31, #32, #35 e #33. Fechamento/release: #10.

## Pós-MVP — UX financeira / v0.2.0-alpha

Ciclo `v0.2.0-alpha` iniciado a partir do MVP em `main` e validado integralmente em 06/10/2026.
A #34 foi validada pelo usuário e concluída em 01/10/2026.
As #42 e #43 foram validadas pelo usuário e concluídas em 01/10/2026.
As #39 e #40 foram validadas pelo usuário e concluídas em 01/10/2026.
A #41 foi validada pelo usuário e concluída em 02/10/2026.
A #46 foi concluída e validada, assim como as entregas #47–#56 deste ciclo.
O fechamento do ciclo e a PR para `main` acontecem após concluir e validar o escopo da versão.
- [x] Calculadora monetária integrada como entrada padrão para campos de valor
- [x] Operações básicas: soma, subtração, multiplicação e divisão
- [x] Teclas numéricas, `00`, separador decimal, limpar, apagar e confirmar
- [x] Preservar valor anterior ao cancelar/voltar
- [x] Precisão monetária sem erros de ponto flutuante
- [x] Componente global reutilizável em lançamentos e módulos futuros

### Entrega #42 — listas e efetivação rápida
- [x] Linhas compactas com status, conta, descrição, valor, datas e etiquetas
- [x] Receber/pagar/transferir hoje pelo ícone
- [x] Desfazer restaura a efetivação anterior, incluindo agendamentos
- [x] Ajustar data pelo feedback ou menu
- [x] Áreas independentes e proteção contra repetição/ação antiga
- [x] Validação manual pelo usuário em 01/10/2026

### Entrega #43 — editar valor na lista

- [x] Calculadora integrada ao toque no valor de receita, despesa e transferência.
- [x] Atualização isolada do valor, preservando vínculos, datas e efetivação.
- [x] Cancelar/voltar mantém o original; ações de valor e status independentes.
- [x] Ajustes #42: feedback por 5 segundos, remover efetivação pelo ícone de receita/despesa e efetivados no topo.
- [x] Validação manual aprovada pelo usuário em 01/10/2026 — roteiro em `docs/edicao-valor-lista.md`.

### Entrega #39 — Voltar no Android

- [x] Voltar fecha sobreposições antes de sair da seção.
- [x] Seções retornam ao Resumo; somente o Resumo libera saída padrão.
- [x] Confirmação de descarte em receitas, despesas, transferências, contas e categorias.
- [x] Cancelar descarte mantém os campos; salvar mantém o fluxo de persistência.
- [x] Validação manual Android/Windows aprovada em 01/10/2026 — `docs/voltar-android.md`.

### Entrega #40 — formulários de contas e categorias

- [x] Componente compartilhado com os lançamentos, incluindo rolagem e rodapé.
- [x] Android em tela cheia; Windows com janela adaptada.
- [x] Preservar campos, validações e confirmação de descarte da #39.
- [x] Calculadora no saldo inicial, permitindo zero e valores negativos.
- [x] Validação manual aprovada em 01/10/2026 — `docs/formularios-contas-categorias.md`.

### Entrega #41 — instituições e logos offline

- [x] Busca e seleção de banco na criação/edição, com nome personalizado.
- [x] Assets locais e ícone padrão para dinheiro/carteira/banco ausente.
- [x] Logo na lista de contas e nos seletores de receitas, despesas e transferências.
- [x] Migration v8 e backup preservando a instituição escolhida.
- [x] Validação manual aprovada em 02/10/2026 — `docs/catalogo-bancos.md`.

### Entrega #46 — recorrências e parcelamentos

- [x] Frequências diária/semanal/mensal/anual e intervalos personalizados.
- [x] Séries por quantidade, geradas pendentes nos três tipos de lançamento.
- [x] Parcelamento por total ou valor da parcela, centavos exatos e calendário ancorado.
- [x] Editar/excluir isolado ou próximos, preservando anteriores e efetivados/agendados.
- [x] Migration v9, atomicidade e backup compatível.
- [x] Validação manual aprovada em 02/10/2026 — #46 encerrada.

## Fase 3 — Núcleo financeiro avançado
- [ ] Competência e regras contábeis avançadas (lançamento/vencimento/efetivação já disponíveis no MVP)
- [x] Previsto x realizado em orçamentos e indicadores; visão mensal e comparação por categoria ampliadas na v0.4.0-alpha.
- [x] Recorrências e parcelamentos — #46 validada.
- [x] Liquidações parciais — [regras](baixas-parciais.md), v0.3.0-alpha.
- [x] Rateio por valor/percentual — [regras](rateio-categorias.md), v0.3.0-alpha.
- [x] Reembolsos/pessoas — [regras](pessoas-reembolsos.md), v0.3.0-alpha.
- [x] Tags/estabelecimentos e filtros, v0.3.0-alpha.
- [ ] Regras automáticas
- [x] Sugestões por descrição e categorias (#48); modelos avançados futuros
- [x] Edição em lote e lixeira, v0.3.0-alpha.
- [ ] Desfazer/refazer global (o desfazer específico de baixas/importações não cobre todas as operações).
- [x] Agendamentos e projeções de movimentos; datas futuras permanecem previstas até a efetivação.

## Fase 4 — Cartões

Entrega #47 (epic #12) concluída e validada. Cadastro, compras, faturas, limite e liquidações implementados. Regras e roteiro em `docs/cartoes-faturas.md`. Compras internacionais, adicionais e importação ficam para entregas próprias.

- [x] Cartões/limites
- [x] Faturas
- [x] Compras parceladas
- [x] Pagamentos/antecipações
- [x] Saldo credor/estornos
- [ ] Compras internacionais
- [x] Competência x caixa

## Fase 5 — Planejamento
- [x] Orçamentos por categoria/subcategoria e mês, histórico e cópia do mês anterior.
- [ ] Acúmulo automático de sobras do orçamento.
- [x] Metas e objetivos vinculados a contas.
- [x] Reserva de emergência com contas vinculadas e meses de cobertura.
- [x] Seleção de categorias essenciais para a base da reserva.
- [ ] Classificação essencial/não essencial em todas as análises.
- [x] Renda, resultado e taxa de poupança por moeda.
- [ ] Plano financeiro
- [ ] Saúde financeira
- [x] Alertas internos de orçamento (80% e ultrapassagem); notificações do sistema futuras.

## Fase 6 — Dívidas e patrimônio
- [x] Empréstimos/financiamentos com amortização manual vinculada a despesas.
- [x] Separação manual de principal e juros/encargos nas amortizações.
- [ ] Cálculo automático de juros/encargos.
- [x] Amortização manual e saldo atual/projetado.
- [ ] Renegociação e simulações.
- [x] Bens e avaliações manuais.
- [x] Patrimônio com contas, bens e dívidas, sem duplicar financiamentos vinculados.
- [x] Investimentos com aportes, resgates, rendimentos e ajustes manuais.
- [ ] PriceProvider/cotações automáticas.

## Fase 7 — Relatórios/importação/produtividade
- [x] Recolhimento dos blocos e preferência de ocultar contas zeradas.
- [ ] Escolha livre e reordenação dos blocos do dashboard.
- [x] Análises por categoria, comparação mensal, compromissos e saldos; exportação Excel/PDF.
- [ ] Relatórios adicionais e filtros salvos.
- [ ] Relatórios salvos/filtros globais
- [ ] Fechamento/snapshots
- [x] Importação CSV de receitas/despesas (#56).
- [x] XLSX, perfis bancários, histórico de lotes, diagnóstico e desfazer seletivo na v0.4.0-alpha.
- [ ] Importação de PDF e faturas.
- [ ] OFX futuro
- [x] Conciliação assistida de extrato e conferência opcional de saldo atual na v0.4.0-alpha.
- [ ] Conferência de saldo histórico.
- [ ] Pacote portátil
- [ ] Favoritos/atalhos
- [ ] Ampliar ajuda contextual (explicação dos saldos disponível no MVP)

## Fase 8 — Robustez
- [x] Anexos locais e sincronizados — [regras](anexos-sincronizados.md).
- [x] Backup diário/3 versões
- [x] Restauração local validada no MVP; evoluir proteção e automação nos próximos ciclos
- [x] Diagnóstico de importação sem dados financeiros na v0.4.0-alpha.
- [ ] Diagnóstico geral do aplicativo.
- [ ] Telemetria opt-in
- [ ] Cache/agregações
- [x] Suítes de regras financeiras, interface, migrações, backup, sync e importação.
- [ ] Ampliar testes conforme novos recursos e cenários de aparelho.

## Fase 9 — Sync Engine
- [x] SyncProvider/change tracking
- [x] Sync com app aberto
- [x] Sync ao abrir/após mudanças
- [x] Last Write Wins + histórico
- [x] Status/pendências/histórico
- [x] Envio/recebimento de anexos na sincronização manual e automática com app aberto.
- [ ] Política específica de anexos por Wi-Fi.
- [x] Primeira sincronização
- [x] Bloqueio de merge de bases independentes
- [ ] Migração entre provedores

## Fase 10 — Google Drive e integrações
- [x] Google OAuth
- [x] GoogleDriveSyncProvider
- [x] Android ↔ Windows
- [ ] Central de privacidade
- [ ] Provedores futuros
- [ ] APIs de cotações
- [ ] Assistente de ajuda futuro

## Antes do 1.0
- [ ] Identidade visual final
- [x] Testes automatizados dos fluxos críticos existentes; ampliar conforme novos recursos.
- [x] CI com formatação, análise, testes Linux/Windows, prévias e builds.
- [ ] Definir licença
- [ ] Revisar documentação
- [ ] Changelog e v1.0.0

## Releases

Semantic Versioning: 0.x-alpha para desenvolvimento inicial, 0.x-beta para estabilização e 1.0.0 para primeira versão estável. Cada release terá tag, changelog e issues/PRs relacionados.

## Fechamento da v0.2.0-alpha — #54

- [x] Backups local/Drive Android/Windows e restauração com app aberto (#49–#52), validados.
- [x] Sincronização #53 manual e #55 automática, validadas.
- [x] Importação CSV #56/#14 com prévia, mapeamento, conta, duplicatas e categorias, validada em 06/10/2026.
- [x] Revisão final #54, correções da build 202 e validação do usuário em 06/10/2026.
- [x] Documentação final, pacotes e validação; publicação autorizada em 06/10/2026.
- [x] Integração pelo [PR #57](https://github.com/LucianoStoll/Somia/pull/57), [release v0.2.0-alpha](https://github.com/LucianoStoll/Somia/releases/tag/v0.2.0-alpha) e conclusão da #54.

Rateio/reembolso (#11) integra agora o ciclo v0.3.0-alpha. [Fluxo e validação da sincronização](sincronizacao-drive.md).


## Histórico do ciclo — v0.3.0-alpha

Branch `v0.3.0-alpha` criada a partir do commit integrado de `main` (`8eca99824e0b506d0791c15239adb51cfd480201`), com pubspec, identificação do app, changelog e documentação atualizados. Acompanhamento na [#58](https://github.com/LucianoStoll/Somia/issues/58) e no [documento do ciclo](ciclos/v0.3.0-alpha.md). CI segue gerando pacotes; publicação somente ao integrar o próximo ciclo validado em main.

Escopo aprovado pelo usuário em 06/10/2026: concluir todas as pendências das epics #11–#16 e melhorar experiência, telas e campos no Android/Windows (#59). Sequência de entregas: transações avançadas → cartões → planejamento → patrimônio/dívidas/investimentos → relatórios/importação/conciliação → anexos sincronizados. A melhoria de experiência acompanha cada etapa e recebe revisão integrada ao fim. Dependências e critérios estão no [documento do ciclo](ciclos/v0.3.0-alpha.md).


## Fechamento da v0.3.0-alpha — 15/10/2026

Publicação autorizada pelo usuário. Entregas e limites nas [notas da versão](releases/v0.3.0-alpha.md). O escopo vigente de fechamento prevalece sobre o planejamento inicial: relatórios adicionais/importação/conciliação ficam para a próxima alpha, assim como internacionais/adicionais/importação de faturas. O ciclo seguinte é a v0.4.0-alpha, descrito abaixo.

## Ciclo atual de prévia — v0.4.0-alpha

Branch `v0.4.0-alpha` a partir da v0.3.0-alpha integrada em `main`; [PR #89](https://github.com/LucianoStoll/Somia/pull/89) em rascunho. Cinco etapas sequenciais: (1) perfis CSV e datas compartilhadas; (2) prévia, filtros, totais e identidade dos lotes; (3) conciliação assistida e saldo atual; (4) XLSX, cópias de proteção, desfazer seletivo e diagnóstico; (5) CI Android/Windows, documentação e APK assinado de teste. Não publicar tag nem mesclar antes da validação final. [Regras da importação](importacao-csv.md) e [notas de prévia](releases/v0.4.0-alpha.md).


### Interface e navegação da v0.4.0-alpha

- [x] Movimentos com transferências e totais de caixa compartilhados com o Resumo; transferências não são receita/despesa.
- [x] Planejamento com saldo previsto por conta, categorias → subcategorias → lançamentos e comparação mensal.
- [x] Cartões com itens somente no Extrato e navegação no histórico das faturas.
- [x] Menu lateral e navegação inferior reorganizados; Dívidas com novo resumo e parcelas.
- [ ] Integrar e validar o refinamento de Cartões (#95).
- [ ] Integrar e validar os cards detalhados de Contas (#96).
- [ ] Integrar e validar a abertura direta dos detalhes de recentes em Android e Windows, incluindo compras no cartão e registros de outro mês.

### Fechamento ainda pendente

- [ ] Validação em aparelhos Android/Windows da importação, conciliação, desfazer e sincronização entre os dispositivos atualizados.
- [ ] Revisão integrada das telas e das contribuições pendentes.
- [ ] Atualizar notas da v0.4.0-alpha e documentação de uso para o escopo final validado.
- [ ] Autorizar o fechamento, concluir o PR #89 e publicar a release do ciclo.

### Próximas melhorias sugeridas, fora do escopo atual

- Seletor Realizado / Previsto / Ambos nos gráficos do Resumo.
- Sincronização com status, última atualização e pendências em destaque; operações avançadas em uma área própria.
- Avaliar a hierarquia dos blocos do Resumo usando as opções de recolhimento já existentes.

Essas sugestões dependem de definição de escopo; não representam funcionalidades já aprovadas ou entregues.
