# Exportação das análises — #14

Primeira etapa da epic #14 na v0.3.0-alpha. Disponível em **Análises → Exportar análise** (ícone na barra superior), em Android e Windows.

Escolha o mês, a análise e a moeda antes de exportar. Excel (.xlsx) e PDF usam a mesma captura dos dados que está na tela. A geração funciona offline em segundo plano. Escolha o destino no seletor do sistema; cancelar não grava nem anuncia sucesso. Nenhum lançamento é alterado.

## Conteúdo e regras

| Análise | Resumo | Detalhes |
|---|---|---|
| Despesas por categoria | Categorias e total líquido | Lançamentos do mês, incluindo partes dos rateios e estornos |
| Comparação mensal | Mês escolhido, anterior, média dos três anteriores, diferença e variação | Lançamentos dos quatro meses |
| Compromissos futuros | Despesas, cartões e totais dos seis meses seguintes | Despesas pendentes e faturas não liquidadas |
| Saldo por tipo de conta | Tipos e total de contas ativas | Contas e indicação de inclusão no saldo do mês |

Data de referência das despesas: efetivação quando existe, senão vencimento. Cartões seguem o vencimento da fatura. Saldos seguem o fim do mês selecionado, incluindo contas excluídas do saldo mensal, sem contas arquivadas. Compromissos refletem pendências existentes na consulta, sem estimar recorrências não geradas. Moedas são exportadas separadamente, sem conversão implícita. Média global é arredondada uma vez, como na tela.

Excel inclui aba de informações, critérios e geração; valores monetários numéricos com duas casas, datas nativas e descrições como texto (inclusive se começarem com `=`). Identificadores permitem rastrear rateios repetidos. PDF inclui critérios, fonte Roboto incorporada e paginação com cabeçalhos; textos longos continuam em linhas seguintes, sem truncamento. PDF é um relatório tabular, sem captura dos gráficos. Ambos incluem dados pessoais dos lançamentos conforme o conteúdo local.

Não substitui backup SQLite e não é formato de restauração. Nenhuma alteração de schema ou sincronização. Bibliotecas Dart `excel` e `pdf`; fontes Roboto distribuídas com sua licença Apache 2.0 em `assets/fonts/`.

## Validação no uso

- Atualizar Android e Windows; abrir Análises e exportar cada uma das quatro visões.
- Selecionar outro mês/moeda e conferir totais com a tela, incluindo estornos, rateios, saldos negativos e contas excluídas do saldo mensal.
- Abrir XLSX no Excel/LibreOffice; conferir datas e somar a coluna de valores.
- Abrir PDF; conferir acentos, cabeçalhos e continuação dos detalhes.
- Cancelar o salvamento, repetir e testar destino indisponível; conferir retorno à tela e mensagem correta.

Importação além do CSV, conciliação e demais complementos da epic continuam pendentes. A melhoria opcional de reutilizar coluna de data do CSV continua futura. #14 permanece aberta até as demais etapas e validação do usuário.
