# Contribuindo com o Somia

## Preparação

Instale Flutter no canal stable e os requisitos da plataforma desejada.
Na raiz do repositório:

```sh
flutter pub get
```

## Branches e integração

O MVP `v0.1.0-alpha` está concluído. O ciclo pós-MVP é desenvolvido em
`v0.2.0-alpha`. A branch `main` recebe a versão validada por pull request ao
final do marco.

Para uma contribuição isolada, crie uma branch a partir da versão atual:

```sh
git switch v0.2.0-alpha
git pull --ff-only
git switch -c feature/issue-<numero>-descricao
```

Use `fix/issue-<numero>-descricao` para correções e
`docs/issue-<numero>-descricao` para documentação. Abra o PR para a branch
da versão, mantendo o contexto da versão no destino. Não integre em `main`
antes da validação final do marco. Exclua branches auxiliares após a integração.

## Commits

Use Conventional Commits, com descrição objetiva:

- `feat: adiciona filtro por vencimento`
- `fix: preserva saldo em efetivação futura`
- `docs: descreve restauração de backup`
- `test: cobre atualização de base legada`
- `refactor:`, `chore:` e `ci:` para os respectivos tipos de mudança.

Relacione a issue no PR. Use `Refs #numero` quando houver pendências e
`Closes #numero` somente depois de concluir os critérios de aceite.

## Verificação antes do PR

```sh
dart format lib test
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

O CI executa a checagem de formatação sem modificar os arquivos, análise e
testes em pushes para `main` e branches `v*`, e em PRs com esses destinos.
Uma diferença de formatação faz a verificação falhar; rode o primeiro comando
localmente e inclua os arquivos formatados no commit.

A Action também testa e compila Windows. APKs release assinados são gerados
nas execuções que não são PR, usando os secrets existentes. PRs não recebem
o material de assinatura. Consulte [atualização do APK](docs/atualizacao-apk.md).

Preencha o [template de PR](.github/PULL_REQUEST_TEMPLATE.md), descreva a
validação realizada e indique testes manuais ou plataformas ainda pendentes.

## Regras do projeto

- Consulte as [guidelines](docs/guidelines-desenvolvimento.md).
- Mudanças de UI seguem a [identidade visual](docs/identidade-visual.md).
- Migrations preservam a base existente e incluem teste relevante.
- Não versionar keystore, senhas, arquivos de backup nem dados privados.
- Ao preparar a release, revisar documentação, changelog, tag e critérios
  da issue de fechamento do marco.
