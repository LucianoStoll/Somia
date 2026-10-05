# Backup automático local — #49, primeira entrega da #16

## Uso

O Somia verifica a cópia diária ao abrir e retomar o app. Se continuar aberto, verifica também na mudança do dia. O calendário é local ao dispositivo. Não executa trabalho com o app fechado ou suspenso; a próxima abertura faz a cópia do dia disponível.

Ajustes mostra as cópias com tipo, data/hora e tamanho. É possível criar uma cópia manual, exportar uma cópia existente ou restaurar seus dados. Exportar os dados atuais continua disponível. As cópias locais ficam no armazenamento interno do app; exportar para outro lugar permite guardá-las fora do dispositivo.

Mantemos as três cópias automáticas mais recentes. Cópias manuais não são apagadas pela rotação. As proteções anteriores à restauração possuem uma retenção separada de três cópias. Arquivos temporários não entram na lista. Uma cópia diária corrompida não bloqueia gerar outra válida no mesmo dia.

## Restauração

É necessário confirmar a substituição dos dados; não existe mesclagem. Após validar o arquivo, o app aplica os dados imediatamente (#52), mantendo a conexão operacional. Durante a aplicação, a interface bloqueia novas interações. Após sucesso, páginas, formulários e navegação são recriados em Ajustes; as demais telas consultam os dados restaurados ao abrir. Agendamentos feitos por versões antigas continuam compatíveis com o fluxo de abertura/cancelamento.

Imediatamente antes de substituir a base, o app salva uma cópia consistente do estado atual, incluindo o WAL. Essa proteção aparece como **Antes de restaurar** e pode ser exportada/restaurada. A proteção de recuperação de interrupção do mecanismo anterior também permanece disponível internamente.

Arquivos inválidos, de versão futura, com corrupção ou vínculos inválidos não são aceitos. Backups antigos compatíveis são migrados na validação, sem alterar o arquivo de origem. Se não for possível validar ou salvar a proteção, a substituição não prossegue. Falhas durante a substituição desfazem a transação e mantêm os dados anteriores.

## Implementação e limites

Snapshot SQLite por `VACUUM INTO`, incluindo WAL ativo; validação de cabeçalho, versão, integridade e chaves estrangeiras. Arquivo temporário único, escrita com flush e renomeação; retenção somente após salvar uma cópia válida. Operações no app são serializadas pelo `BackupManager`. Falhas automáticas ficam visíveis em Ajustes e não impedem usar o app. Não há migration de schema nesta entrega.

O backup contém a base completa: contas, categorias, receitas/despesas, transferências, séries, cartões, faturas, pagamentos e históricos. Anexos ainda não são uma funcionalidade do Somia; este formato continua sendo SQLite. Google Drive manual já está disponível no Android e Windows (#50/#51). Sincronização automática, conflitos e anexos seguem na #16.

## Validação manual

1. Instalar sobre a versão anterior e abrir Ajustes; conferir uma cópia automática de hoje.
2. Fechar/reabrir ou retomar no mesmo dia; não duplicar cópias automáticas.
3. Criar cópia manual, exportar pelo menu e conferir data/tamanho.
4. Selecionar uma restauração e cancelar a confirmação; dados atuais continuam iguais.
5. Criar um lançamento e restaurar uma cópia antiga; conferir imediatamente os dados da cópia. O lançamento novo fica na proteção **Antes de restaurar**.
6. Restaurar essa proteção com o app aberto; recuperar o lançamento novo e os demais registros.
7. Selecionar arquivo inválido; conferir rejeição sem substituir os dados.
8. Conferir cartões/faturas/séries e saldos após restauração; testar Android e Windows.

A aplicação imediata importa apenas as colunas do schema conhecido, dentro de uma transação SQLite na base principal. Triggers operacionais são suspensos/recriados na mesma transação para preservar históricos de contas/categorias posteriormente arquivadas. Chaves estrangeiras são diferidas até a conclusão e conferidas antes do commit. SQL de triggers do arquivo externo nunca é instalado. Falhas revertem dados e triggers; a cópia anterior permanece disponível.

Na #53, a restauração local/Drive limpa o vínculo e a fila de sincronização para não publicar dados antigos automaticamente. Receba novamente a base do Drive para retomar o vínculo. A migration v11 também preserva uma cópia **Antes de atualizar**; essas proteções não seguem a rotação diária. [Detalhes e validação](sincronizacao-drive.md).
