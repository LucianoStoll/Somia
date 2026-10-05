# Roadmap — Somia

## Estratégia

O primeiro marco é um MVP pequeno e utilizável. Recursos avançados já têm requisitos definidos, mas entram incrementalmente.

## Controle de versões e branches

Cada ciclo de desenvolvimento deve possuir uma branch principal com o **nome exato da versão**, por exemplo `v0.1.0-alpha`, `v0.2.0-alpha` ou `v0.5.0-beta`.

Todas as issues previstas para aquela versão devem ser implementadas e validadas nessa branch. Evitar branches paralelas desnecessárias; quando uma branch auxiliar for indispensável, ela deve retornar para a branch da versão, nunca diretamente para `main`.

A branch `main` representa somente versões concluídas/estáveis dentro do marco planejado. **A Pull Request da branch da versão para `main` só deve ser aberta quando todo o escopo daquela versão estiver concluído e validado.** Depois do merge, a versão recebe tag/release/changelog e inicia-se uma nova branch com o nome da próxima versão.

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

Branch ativa: `v0.2.0-alpha`, iniciada a partir do MVP validado em `main`.
A #34 foi validada pelo usuário e concluída em 01/10/2026.
As #42 e #43 foram validadas pelo usuário e concluídas em 01/10/2026.
As #39 e #40 foram validadas pelo usuário e concluídas em 01/10/2026.
A #41 foi validada pelo usuário e concluída em 02/10/2026.
A #46 é a entrega atual autorizada: recorrências e parcelamentos, primeira entrega da #11.
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
- [ ] Análises avançadas de previsto x realizado (saldo básico já disponível)
- [x] Recorrências e parcelamentos — #46 validada.
- [ ] Liquidações parciais
- [ ] Rateio
- [ ] Reembolsos/pessoas
- [ ] Tags/estabelecimentos
- [ ] Regras automáticas
- [ ] Autocompletar/modelos
- [ ] Edição em lote, desfazer/refazer, lixeira
- [ ] Agendamentos/projeções

## Fase 4 — Cartões

Entrega ativa: #47 (epic #12). Cadastro, compras, faturas, limite e liquidações implementados; CI e validação manual pendentes. Regras e roteiro em `docs/cartoes-faturas.md`. Compras internacionais, adicionais e importação ficam para entregas próprias.

- [ ] Cartões/limites
- [ ] Faturas
- [ ] Compras parceladas
- [ ] Pagamentos/antecipações
- [ ] Saldo credor/estornos
- [ ] Compras internacionais
- [ ] Competência x caixa

## Fase 5 — Planejamento
- [ ] Orçamentos/versionamento/acúmulo
- [ ] Metas e objetivos
- [ ] Reserva de emergência/grupos
- [ ] Essencial x não essencial
- [ ] Renda e taxa de poupança
- [ ] Plano financeiro
- [ ] Saúde financeira
- [ ] Alertas progressivos

## Fase 6 — Dívidas e patrimônio
- [ ] Empréstimos/financiamentos
- [ ] Juros/encargos
- [ ] Renegociação/amortização/simulações
- [ ] Bens e avaliações
- [ ] Patrimônio líquido
- [ ] Investimentos e PriceProvider

## Fase 7 — Relatórios/importação/produtividade
- [ ] Dashboard customizável
- [ ] Relatórios/gráficos
- [ ] Relatórios salvos/filtros globais
- [ ] Fechamento/snapshots
- [ ] CSV/Excel/PDF
- [ ] OFX futuro
- [ ] Conciliação
- [ ] Pacote portátil
- [ ] Favoritos/atalhos
- [ ] Ampliar ajuda contextual (explicação dos saldos disponível no MVP)

## Fase 8 — Robustez
- [ ] Anexos (20 MB)
- [ ] Backup diário/3 versões
- [x] Restauração local validada no MVP; evoluir proteção e automação nos próximos ciclos
- [ ] Logs/diagnóstico
- [ ] Telemetria opt-in
- [ ] Cache/agregações
- [ ] Evoluir testes automatizados

## Fase 9 — Sync Engine
- [ ] SyncProvider/change tracking
- [ ] Sync com app aberto
- [ ] Sync ao abrir/após mudanças
- [ ] Last Write Wins + histórico
- [ ] Status/pendências/histórico
- [ ] Anexos Automático/Wi-Fi/Manual
- [ ] Primeira sincronização
- [ ] Bloqueio de merge de bases independentes
- [ ] Migração entre provedores

## Fase 10 — Google Drive e integrações
- [ ] Google OAuth
- [ ] GoogleDriveSyncProvider
- [ ] Android ↔ Windows
- [ ] Central de privacidade
- [ ] Provedores futuros
- [ ] APIs de cotações
- [ ] Assistente de ajuda futuro

## Antes do 1.0
- [ ] Identidade visual final
- [ ] Testes automatizados críticos
- [ ] CI ampliado
- [ ] Definir licença
- [ ] Revisar documentação
- [ ] Changelog e v1.0.0

## Releases

Semantic Versioning: 0.x-alpha para desenvolvimento inicial, 0.x-beta para estabilização e 1.0.0 para primeira versão estável. Cada release terá tag, changelog e issues/PRs relacionados.

## Fechamento da v0.2.0-alpha — #54

- [x] Backups local/Drive Android/Windows e restauração com app aberto (#49–#52), validados.
- [ ] Sincronização #53: botão manual nesta entrega; automatização depois da validação manual.
- [ ] Importação CSV #14 com prévia, mapeamento, conta, duplicatas e sugestões de categoria.
- [ ] Revisão final de atualização, dados, saldos, datas, séries, cartões, backup, rede e conflitos.
- [ ] Documentação final, pacotes e validação; somente então PR para main e release.

Rateio/reembolso (#11) permanece para ciclo posterior. [Fluxo e validação da sincronização](sincronizacao-drive.md).
