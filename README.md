# Somia

Seu dinheiro, mais claro. Aplicativo de finanças pessoais para Android e Windows, com dados locais e funcionamento offline.

## v0.2.0-alpha — ciclo validado

O ciclo pós-MVP foi validado pelo usuário em 06/10/2026. Inclui calculadora, séries, cartões/faturas, sugestões pelo histórico, extrato diário, detalhamento de saldo, backups local/Google Drive Android/Windows, [sincronização manual](docs/sincronizacao-drive.md) e [automática com app aberto](docs/sincronizacao-automatica.md), e [importação CSV](docs/importacao-csv.md). Consulte as [notas da versão](docs/releases/v0.2.0-alpha.md) e o [inventário completo de alterações](docs/releases/v0.2.0-alpha-files.md).

O próximo ciclo será `v0.3.0-alpha`, criado a partir do merge desta versão em `main`. Funcionalidades futuras precisam de escopo aprovado; não estão incluídas automaticamente.

## MVP — v0.1.0-alpha

Primeiro ciclo implementado e validado pelo usuário em 01/10/2026, incluindo o checklist final #33 e os ajustes #35. A versão é uma pré-release para uso e evolução do MVP.

- Contas com saldo inicial, arquivamento e opções independentes para participação no saldo consolidado e nas análises.
- Categorias e subcategorias; receitas, despesas e transferências com descrição.
- Datas de lançamento, vencimento e efetivação, com escolha entre contabilizar hoje ou no vencimento ao efetivar em outra data.
- Dashboard com consulta mensal, receitas versus despesas, gastos por categoria e transações recentes.
- Mês compartilhado entre Resumo, Receitas, Despesas, Transferências e Contas; setas, seleção direta de mês/ano e filtros avançados nas listas.
- Saldo efetivado e projetado por conta e consolidado até o fim do mês selecionado.
- Interface escura Somia, navegação adaptada ao celular e PC, formulários de movimentos em tela cheia no Android.
- Exportação e restauração de backup local, migrations não destrutivas e atualização Android com assinatura persistente.

### Como os saldos funcionam

O saldo do mês é acumulado: saldo inicial das contas incluídas mais movimentos efetivados até o fim do mês selecionado. A projeção considera também compromissos até essa data. Cada conta tem seu cálculo individual; excluir uma aplicação do consolidado não esconde sua conta nem seus movimentos.

Os totais de receitas/despesas e os gráficos usam a data de efetivação quando preenchida e, caso contrário, o vencimento. Incluem efetivados e previstos. As listas mantêm vencimento como filtro mensal inicial e permitem ajustar os critérios no menu de filtros. A ajuda do Resumo e dos Ajustes explica essas diferenças.

## Instalação

Baixe os pacotes em [Releases](https://github.com/LucianoStoll/Somia/releases).

**Android:** instale o APK assinado sobre a instalação existente, sem desinstalar. O identificador permanece `com.example.finapp`; a chave persistente e o número crescente da compilação permitem atualizar preservando os dados. Versão e compilação aparecem nos Ajustes. Consulte o [guia de atualização e backup](docs/atualizacao-apk.md).

**Windows:** extraia todo o ZIP e execute `finapp.exe`. Mantenha as DLLs e a pasta `data` junto do executável. O pacote é compilado em modo release para Windows x64.

Os dados ficam no dispositivo. Na v0.2.0-alpha, restaure em **Ajustes → Restaurar backup**; os dados são aplicados com o app aberto. A sincronização Android/Windows da #53 usa o botão **Sincronizar agora** e a mesma conta Google. Restaurar um backup desvincula a sincronização. A versão publicada v0.1.0-alpha ainda aplica restauração ao reiniciar e não possui sincronização.

## Desenvolvimento

Flutter/Dart, Drift/SQLite, BLoC/Cubit, go_router e get_it, organizados em `core` e `features`. Valores monetários são armazenados como inteiros em unidades menores. O pacote técnico Flutter permanece `finapp`; o repositório é `LucianoStoll/Somia`.

```sh
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

A CI executa formatação, análise, testes no Linux e Windows, prévias de interface, build Windows release e APK assinado. Após merge do ciclo validado em `main`, publica a pré-release correspondente ao `pubspec.yaml`, com notas próprias, pacotes e checksums. Releases publicadas não são sobrescritas. Cada pacote usa o número da execução como compilação.

## Documentação

- [Changelog](CHANGELOG.md)
- [Roadmap e próximos ciclos](docs/roadmap.md)
- [Visão e escopo](docs/requisitos.md)
- [Especificações funcionais](docs/especificacao-produto.md)
- [Arquitetura offline-first](docs/arquitetura.md)
- [Guidelines de desenvolvimento](docs/guidelines-desenvolvimento.md)
- [Identidade visual](docs/identidade-visual.md)
- [Atualização Android e backup](docs/atualizacao-apk.md)

Cartões, recorrências, calculadora, backup automático, sincronização e CSV já foram entregues nesta versão. Planejamento, rateio/reembolsos, anexos, relatórios avançados e conciliação continuam no backlog.
