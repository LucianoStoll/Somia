# Guidelines de Desenvolvimento — Somia

Fluxo de preparação, branches e validação: [CONTRIBUTING.md](../CONTRIBUTING.md).

## Arquitetura
- features independentes com `data/domain/presentation`;
- `core/` somente para infraestrutura compartilhada;
- UI não acessa DAO/SQLite diretamente;
- domínio não depende de Flutter/Drift/provedores externos;
- integrações atrás de interfaces.

## Flutter
- BLoC/Cubit para estado;
- go_router para navegação;
- get_it para DI;
- ambientes dev/test/prod;
- componentes reutilizáveis sem concentrar regras de negócio em widgets.

## Persistência
- UUIDs;
- dinheiro em unidade mínima inteira;
- migrations versionadas;
- backup antes de migrations relevantes;
- tombstones onde sync futuro exigir;
- timestamps consistentes.

## Erros e logs
- separar erro técnico, domínio e mensagem de UI;
- mensagens localizáveis;
- logs por nível;
- nunca incluir dados financeiros sensíveis em diagnóstico por padrão.

## Git
Conventional Commits:
- `feat:`
- `fix:`
- `docs:`
- `refactor:`
- `test:`
- `chore:`
- `ci:`

A branch de trabalho pós-MVP é `v0.2.0-alpha`; `main` recebe a versão validada
por PR ao encerrar o marco. Branches auxiliares partem da versão e retornam
para ela por PR:

Branches sugeridas:
- `feature/issue-<n>-descricao`
- `fix/issue-<n>-descricao`
- `docs/issue-<n>-descricao`

PRs devem referenciar issue quando houver, descrever alterações e conter checklist de validação manual relevante.

## Qualidade
Antes de enviar mudanças:
- `dart format lib test` para aplicar a formatação;
- `dart format --output=none --set-exit-if-changed lib test` para conferir;
- `flutter analyze`;
- `flutter test`;
- testes manuais relevantes no Android/Windows.

O CI verifica formatação, análise e testes automaticamente em pushes para
`main`/`v*` e PRs com esses destinos. A suíte cobre regras financeiras,
repositories, navegação, migrations e backup/restauração. A Action também
compila Windows e, fora de PRs, gera APK assinado com chave persistente.

A suíte inclui importação CSV e sincronização manual/automática, com testes
de duplicação, conflitos, interrupções, rollback e preservação da fila.

## Releases
Semantic Versioning:
- `v0.x.x-alpha`;
- `v0.x.x-beta`;
- `v1.0.0` estável.

Cada release deve ter tag e changelog, relacionando issues/PRs relevantes.
