# Estabelecimentos — #11

- Campo opcional em Mais opções das receitas, despesas e compras de cartão. Um nome por lançamento, até 100 caracteres; salvar também cadastra o nome no histórico para reutilização.
- Sugestões compactas (até seis), com busca pelo nome digitado e sem duplicar sugestões por diferença de maiúsculas/minúsculas.
- Nome aparece na lista de lançamentos. Filtro exato por estabelecimento, sem diferenciar maiúsculas/minúsculas, combinável com tag, conta, categoria e período.
- Compras parceladas preservam o estabelecimento em cada parcela. Ao filtrar compras, a lista de despesas continua mostrando a fatura completa, identificada na tela.
- Alterar ou limpar o nome não muda tags, valores, datas, saldos ou baixas. Em séries, aplica o escopo escolhido.
- Schema 21: coluna establishment nas transações/compras; backup, sync e migração de registros locais/outbox/histórico/uploads. Dados anteriores ficam sem estabelecimento e mantêm as tags. Atualizar Android e Windows antes do sync.

## Validação manual

1. Cadastrar despesa com estabelecimento; salvar e editar para conferir o nome.
2. Digitar parte do mesmo nome em outro lançamento e escolher a sugestão.
3. Filtrar pelo nome e por uma tag; limpar os filtros.
4. Alterar e limpar estabelecimento; conferir preservação das tags e baixas.
5. Testar compra parcelada e filtro da fatura.
6. Exportar/restaurar backup e conferir o nome.

## Verificações técnicas

Testes de normalização/limites, cadastro/edição/filtros combinados, backup/sync histórico, seleção e limpeza do editor, parcelas e migração com tags/uploads pendentes. O CI confirma formatação, análise estática, suíte Linux/Windows e compila os pacotes. Validação manual permanece pendente.

Edição em lote, lixeira/restauração e anexos continuam pendentes da #11.
