# Edição em lote e lixeira — #11

## Comportamento

- Seleção por checkbox e Selecionar todos nas receitas, despesas, transferências e compras das faturas de cartão. O lote altera somente as ocorrências selecionadas, preservando outras parcelas da série.
- Campos opcionais: descrição, valor por lançamento, conta (origem/destino nas transferências), categoria/subcategoria, datas de lançamento/vencimento, efetivação/data, estabelecimento, adicionar/remover tags. Nas compras, conta/datas/efetivação permanecem sob gestão da fatura. Transferências não possuem categoria, tags ou estabelecimento.
- Campos não escolhidos são preservados. Estabelecimento marcado e vazio limpa o nome. Trocar categoria de um lançamento com rateio exige edição individual. Troca de conta exige conta ativa da mesma moeda.
- Operação atômica: erro, seleção desatualizada ou vínculos financeiros incompatíveis cancelam todo o lote. Baixas parciais, reembolsos, amortizações e cobertura dos estornos seguem as validações existentes.
- Exclusões manuais de lançamentos, transferências, compras e ajustes permitidos vão à Lixeira. Exclusões internas anteriores não aparecem nela. Desfazer pagamento de cartão continua sendo uma operação própria.
- Lixeira no menu: seleção, restaurar e excluir definitivamente, com confirmação. Restauração mantém dados, fatura original, série e baixas; saldos/relatórios voltam a considerar os movimentos. Contas arquivadas são aceitas para restaurar históricos; contas/cartões excluídos e vínculos inconsistentes bloqueiam a ação.
- Excluir definitivamente impede restauração pela lixeira e recuperação via histórico de sync. Um marcador é mantido no banco para preservar relações e impedir ressuscitação por restauração offline concorrente. Não há limpeza automática por prazo.
- Schema 22 e sincronização/backup: trash_state em transactions/transfers/card_entries; migração conserva tags e estabelecimentos, adapta histórico/outbox/uploads e renova identidade de pacotes pendentes. Pacotes antigos recebem estado active e continuam respeitando deleted_at. Atualizar ambos os dispositivos antes de sincronizar.

## Validação manual

1. Selecionar duas receitas/despesas; alterar apenas estabelecimento/tags e conferir os campos restantes.
2. Alterar valor, categoria/subcategoria, conta e datas em lote; testar também marcar pendente/efetivar.
3. Selecionar somente uma parcela; conferir que as outras não mudam.
4. Selecionar movimentos incompatíveis (moedas diferentes, valor abaixo de baixas, reembolso vinculado); conferir que nenhum muda.
5. Mover para lixeira um lançamento com baixa parcial; conferir saldo antes/depois e após restaurar.
6. Excluir/restaurar transferência e compra; conferir destino, fatura e parcelas.
7. Excluir definitivamente, sincronizar Android/Windows e conferir ausência da lixeira; testar conflito offline de restauração versus purga.
8. Exportar/restaurar backup e conferir lixeira, tags e estabelecimento.

## Verificações técnicas

Cobertura de edição seletiva/atômica, revisão antiga, moeda, séries, baixas e saldos, restauração, exclusões internas, purga, transferências, fatura original, formulário, tela da lixeira, migração e concorrência de sync. CI: formatação, análise estática, testes Linux/Windows, previews e pacotes Android/Windows. Validação manual do usuário permanece pendente. Anexos continuam pendentes na #11.
