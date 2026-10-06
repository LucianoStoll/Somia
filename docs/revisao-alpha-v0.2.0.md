# Revisão técnica da v0.2.0-alpha — #54

Solicitada em 05/10/2026. A #53 foi validada pelo usuário e encerrada; #55 já validada. A importação CSV #56 segue aberta para validação posterior, com sugestão de reutilizar a coluna de data registrada. Nenhum merge/release faz parte desta revisão.

## Correções encontradas

1. A restauração verificava integridade SQLite, estrutura e chaves estrangeiras, mas não o conjunto de regras financeiras usado no recebimento remoto. Agora ambos compartilham `validateFinancial`. O candidato é verificado antes da restauração e os dados são revalidados antes do commit operacional.
2. A troca de moeda de uma conta considerava apenas transações/transferências ativas. Agora inclui históricos excluídos, cartões e pagamentos de fatura, preservando a unidade monetária dos registros relacionados.
3. A documentação ainda citava schema 7 e testes de sincronização/importação como futuros. Atualizada para schema 11 e cobertura existente.

A verificação compartilhada confere hierarquia/tipos de categorias, moedas de transferências, vínculo de compra/fatura do mesmo cartão, categoria de despesa em compras, contas BRL para cartões/pagamentos e sinais de compras/encargos versus créditos. Contas/categorias arquivadas permanecem aceitas em registros históricos; valores e datas existentes não são reescritos. Sem alteração de schema.

## Evidências automatizadas

- Migrations v1 até v11, cópia antes de atualizar, persistência após reabrir e saldo em centavos: testes em `test/core/database/schema_v*_test.dart`, `app_database_test.dart` e `test/features/accounts/accounts_repository_test.dart`.
- Três datas, saldo realizado/previsto por conta e consolidado, transferências, extrato diário e resumo: suítes de balances, dashboard e account statement.
- Séries: último dia, anos bissextos, parcelas exatas e proteção de efetivados.
- Cartões: parcelas, estorno, pagamento parcial/agendado, encargos/descontos, saldo credor, carry-over, quitação/desfazer e ausência de duplicação no caixa.
- Backups: WAL, dados de todas as dez tabelas, históricos arquivados, SQL externo não instalado, rollback integral, falta de espaço e sucesso mesmo se a listagem falhar após commit.
- Novos testes rejeitam oito inconsistências financeiras em backups sem gravar/restaurar/agendar dados inválidos nem alterar triggers e revisão da base operacional.
- Novo teste compara as dez tabelas e saldos após restauração e recebimento remoto repetido, com fila remota vazia e retry idempotente.
- Novos testes bloqueiam troca de moeda por vínculo com cartão, pagamento ou lançamento excluído, mantendo edição na mesma moeda.
- Sincronização: mudanças independentes, conflitos determinísticos, histórico/recuperação, exclusões, repetição, perda de resposta, corrupção, conta/base/relógio divergentes, fila persistente, rollback e proteção de formulários.
- CSV: prévia sem gravação, cancelamento, centavos/datas, classificação, duplicados e lote atômico; sugestão de reutilização de coluna não implementada.

## Limites e fechamento

A execução automatizada verifica lógica e builds; não substitui instalação física em Android/Windows, autorização Google real, suspensão do sistema ou interrupção elétrica. #53 e #55 contam com validação real do usuário. Em 06/10/2026 o usuário aprovou #54 e #56, incluindo as correções nos dispositivos e a importação CSV. A preparação final parametriza a publicação pela versão; PR/tag/release são autorizados depois dessa aprovação.

Checklist restante:

- [x] Atualizar o APK sem desinstalar e conferir os dados anteriores.
- [x] Conferir restauração válida e rejeição de arquivo inconsistente nos dispositivos.
- [x] Importação #56 validada em 06/10/2026; sugestão de reutilizar data segue no backlog da #14.
- [ ] Após aprovação final, preparar PR para main e release da versão correta.
