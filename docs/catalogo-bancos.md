# Catálogo offline de instituições — #41

Ao criar/editar uma conta, toque em **Instituição**, busque pelo nome e selecione
um banco. O nome da conta continua livre. A opção **Sem instituição / ícone padrão**
remove a escolha e usa o ícone adequado ao tipo da conta (carteira/dinheiro ou banco).
Cancelar/Voltar no catálogo mantém a seleção anterior. Alterar somente a instituição
participa da confirmação de descarte do formulário.

Catálogo inicial: Bradesco, BTG Pactual, Inter, Itaú, Nubank, Santander, Sicoob e Sicredi.
A busca ignora maiúsculas, acentos e espaços externos. Bancos ausentes podem ser
usados com o nome personalizado e o ícone padrão.

## Persistência e exibição

Migration SQLite v8 adiciona `accounts.institution_id` opcional, sem modificar os
valores, nomes, referências ou saldos existentes. Contas antigas recebem `NULL`.
O identificador estável é preservado pela exportação/restauração SQLite e ao
incluir/excluir a conta do saldo consolidado. Identificadores desconhecidos usam
ícone padrão, permitindo abrir backups mesmo se o catálogo mudar.

As logos PNG são assets incluídos no aplicativo. Não há consultas de rede,
importação da galeria ou dependência de serviço de imagens em tempo de execução.
O fundo branco com espaço ao redor mantém contraste no tema escuro. A mesma
identidade aparece na lista de contas e nos seletores e filtros de contas de
receitas, despesas e transferências, inclusive contas arquivadas referenciadas.

## Fontes dos assets

Obtidos em 01/10/2026 dos sites oficiais. Marcas pertencem às respectivas
instituições e servem para identificar a conta; a seleção não cria conexão bancária.
Os favicons são convertidos para PNG preservando proporção e cores. Símbolos SVG
são rasterizados em 192 × 192; nenhuma logo é gerada ou redesenhada.

| Asset | Fonte oficial |
| --- | --- |
| `bradesco.png` | https://banco.bradesco/favicon.ico |
| `btg.png` | https://banking.btgpactual.com/favicon.png?v=1 |
| `inter.png` | https://inter.co/favicon.svg |
| `itau.png` | https://www.itau.com.br/media/dam/m/c5a2dcc08dba709/original/logo-192px.png |
| `nubank.png` | https://www.datocms-assets.com/120597/1741817368-favicon.ico?auto=format&h=192&w=192 — asset referenciado em https://nubank.com.br/ |
| `santander.png` | https://www.santander.com.br/sites/WPC_CMS/imagem/21-03-26_095020_M_favicon.png |
| `sicoob.png` | https://www.sicoob.com.br/o/sicoob-theme/images/favicon/android-icon-192x192.png |
| `sicredi.png` | SVG `logo-mobile` embutido em https://www.sicredi.com.br/, com os preenchimentos definidos pelo CSS oficial (`#146E37` e `#64C832`) |

## Validação manual

- Criar uma conta com nome personalizado, buscar `itau` e selecionar Itaú.
- Editar, trocar o banco e conferir a logo na lista e nos seletores dos três lançamentos.
- Cancelar/Voltar no catálogo e conferir que a seleção anterior foi mantida.
- Remover a instituição e conferir ícone de banco ou carteira conforme o tipo.
- Reiniciar e exportar/restaurar backup; conferir seleção, nome e saldos.
- Abrir uma conta antiga, usar o app sem internet e conferir logos em tema escuro.
- Conferir Android em retrato/paisagem e Windows.

Validação manual aprovada pelo usuário em 02/10/2026. Testes automatizados cobrem migration v7→v8,
reabertura, troca/remoção, backup, alternância de saldo sem perder instituição,
busca, assets locais, cancelamento, descarte e fallback de instituição ausente.
