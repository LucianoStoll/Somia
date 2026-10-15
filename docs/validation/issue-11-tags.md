# Tags nos lançamentos — #11

Entrega na branch v0.3.0-alpha. Estabelecimentos, edição em lote, lixeira e anexos continuam pendentes.

- Receitas e despesas: em Mais opções, digitar uma tag e tocar em + ou confirmar no teclado. Várias etiquetas, remoção individual e sugestões do histórico (até seis).
- Nomes de até 40 caracteres, no máximo 20 por lançamento. Espaços externos removidos e duplicatas ignoradas sem distinguir maiúsculas/minúsculas.
- Etiquetas aparecem nos lançamentos. Em Filtros, informar a etiqueta e confirmar no teclado; combinação com conta, categoria e período.
- Compras de cartão mantêm etiquetas por parcela. O filtro encontra a fatura que contém a etiqueta; o valor continua sendo o da fatura completa, como no filtro de categoria.
- Série criada/alterada propaga tags conforme o escopo escolhido.
- Schema 20 adiciona tags_json às transações e compras, sem alterar valores, datas, baixas ou saldos. Backup e sync preservam etiquetas. Pacotes históricos recebem lista vazia; uploads antigos são reidentificados durante a migração. Atualizar Android e Windows antes de sincronizar.

## Validação manual

1. Criar despesa com duas tags; fechar e editar, verificando persistência.
2. Reutilizar uma etiqueta com outra capitalização: não deve duplicar.
3. Remover uma etiqueta, salvar e conferir filtro.
4. Filtrar por tag e mês, depois limpar filtro.
5. Cadastrar compra parcelada com tag e verificar as parcelas/fatura.
6. Exportar e restaurar backup; conferir etiquetas e saldos.

## Verificações

Testes adicionados para normalização/limites, persistência/edição/filtro com acentos, backup, compatibilidade de sync e adicionar/remover no editor. Execução completa fica a cargo do CI; ambiente local não dispõe do cache de dependências Flutter. Não registrar aprovação da suíte antes de conferir o CI.
