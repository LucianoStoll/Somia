# Somia — nova apresentação do Resumo

Proposta visual aprovada em 13/10/2026. Implementação na linha v0.3.0-alpha.

![Conceito aprovado](assets/dashboard-visual-conceito.webp)

A imagem é uma referência visual, com dados ilustrativos. Valores, datas, proporções e categorias do aplicativo sempre vêm do banco real; não reproduzir os dados fictícios do desenho.

## Objetivo e organização

Reduzir a distância entre o topo e as análises, usando grafite, azul acinzentado e tons pastéis. Manter menu lateral, mês ao lado da marca no Android e botão flutuante de lançamento.

1. Um cartão com saldo atual/efetivado/previsto conforme período, previsão no fechamento, recebido e pago, e resultado mensal separado do saldo.
2. A receber e a pagar compactos, com acesso às listas existentes.
3. Evolução diária, consultável ao tocar ou arrastar horizontalmente. Preservar duas séries cumulativas (efetivado e previsto), inclusive atrasados: esconder a projeção histórica perderia informação. Marcador Hoje apenas no mês atual; tracejado com tamanho em pixels para evitar grandes lacunas em quedas.
4. Gastos por categoria em rosca. Mostrar até cinco grupos; acima disso, quatro maiores mais Outras. Legenda sempre com nome, valor e percentual.
5. Receitas e despesas mensais com barras e consulta já existente.
6. Saldo por tipo de conta, incluindo contas excluídas do saldo principal. Valores negativos destacados e barras proporcionais à magnitude, sem apresentar saldo negativo como positivo. Moedas separadas.
7. Três próximos vencimentos; Ver todos expande a lista, Ver menos recolhe. Descrição completa no detalhe. Ações Abrir/Efetivar preservadas.
8. Detalhes por conta e últimos cadastrados continuam acessíveis abaixo.

No Windows, evolução e categorias ficam lado a lado quando há largura; histórico e tipos de conta em uma segunda linha. Android usa uma coluna. Texto ampliado empilha elementos.

## Escopo e regras

- Paleta local ao dashboard: fundo #141518, cartões #202226, azul #A5BCD0, receitas #A8C5B0, despesas #D6A3A3, lavanda #B8B3D9 e areia #D8C49E.
- Não modificar cálculos, efetivação, vencimentos, pagamentos de faturas, contas incluídas ou conversão de moedas nesta revisão visual.
- Ajuda sobre previsão disponível por tooltip; detalhamento de saldo preservado ao tocar no cartão.
- A primeira implementação mantém o histórico de seis meses existente. Alternância 6/12 meses, personalização dos blocos e ocultação global de valores ficam para evolução própria; o ícone de olho do conceito não é incluído como controle sem função.
- A cor da legenda deve coincidir com o respectivo segmento, corrigindo a inconsistência ilustrativa do conceito.

## Validação

- Testes existentes de layout responsivo: 320 px com fonte 2x, 360/390/520 px e desktop.
- Verificar a nova ordem, navegação mensal, abertura de detalhes, contas excluídas e consulta por gesto.
- Revisar previews Android/desktop geradas pela CI.
- Validar no aparelho: rolagem vertical versus arraste horizontal do gráfico, efetivação, expansão de vencimentos e legibilidade.

Sem migração do banco de dados.

## Estado da entrega

Issue #81 criada. Código e referência visual registrados localmente. Formatação Dart e `git diff --check` executados. Análise Flutter, testes e previews ainda não executados: cache de dependências indisponível e inicialização do Flutter não concluiu a recuperação das dependências. Publicação autorizada pelo usuário em 13/10/2026. Base conferida após fetch: `bf0d32a`, última integração disponível em `v0.3.0-alpha` (exportação de análises). CI e APK serão verificados após o push. Não considerar esta revisão validada ou integrada à alpha.
