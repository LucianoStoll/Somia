# Backup automático local — #49, primeira entrega da #16

## Uso

O Somia verifica a cópia diária ao abrir e retomar o app. Se continuar aberto, verifica também na mudança do dia. O calendário é local ao dispositivo. Não executa trabalho com o app fechado ou suspenso; a próxima abertura faz a cópia do dia disponível.

Ajustes mostra as cópias com tipo, data/hora e tamanho. É possível criar uma cópia manual, exportar uma cópia existente ou preparar sua restauração. Exportar os dados atuais continua disponível. As cópias locais ficam no armazenamento interno do app; exportar para outro lugar permite guardá-las fora do dispositivo.

Mantemos as três cópias automáticas mais recentes. Cópias manuais não são apagadas pela rotação. As proteções anteriores à restauração possuem uma retenção separada de três cópias. Arquivos temporários não entram na lista. Uma cópia diária corrompida não bloqueia gerar outra válida no mesmo dia.

## Restauração

É necessário confirmar a substituição dos dados; não existe mesclagem. O arquivo é validado e preparado para a próxima abertura. Enquanto não reiniciar, a base atual continua em uso. Ajustes informa a pendência e permite cancelá-la.

Imediatamente antes de substituir a base, o app salva uma cópia consistente do estado atual, incluindo alterações posteriores ao agendamento. Essa proteção aparece como **Antes de restaurar** e pode ser exportada/restaurada. A proteção de recuperação de interrupção do mecanismo anterior também permanece disponível internamente.

Arquivos inválidos, de versão futura, com corrupção ou vínculos inválidos não são aceitos. Backups antigos compatíveis são migrados na validação, sem alterar o arquivo de origem. Se não for possível validar ou salvar a proteção, a substituição não prossegue. Quando a base atual permanece disponível, o app a abre e informa a falha em Ajustes; é possível cancelar/preparar outra restauração.

## Implementação e limites

Snapshot SQLite por `VACUUM INTO`, incluindo WAL ativo; validação de cabeçalho, versão, integridade e chaves estrangeiras. Arquivo temporário único, escrita com flush e renomeação; retenção somente após salvar uma cópia válida. Operações no app são serializadas pelo `BackupManager`. Falhas automáticas ficam visíveis em Ajustes e não impedem usar o app. Não há migration de schema nesta entrega.

O backup contém a base completa: contas, categorias, receitas/despesas, transferências, séries, cartões, faturas, pagamentos e históricos. Anexos ainda não são uma funcionalidade do Somia; este formato continua sendo SQLite. Google Drive, OAuth, sincronização, conflitos e pacote com anexos seguem na #16 para entregas posteriores.

## Validação manual

1. Instalar sobre a versão anterior e abrir Ajustes; conferir uma cópia automática de hoje.
2. Fechar/reabrir ou retomar no mesmo dia; não duplicar cópias automáticas.
3. Criar cópia manual, exportar pelo menu e conferir data/tamanho.
4. Preparar restauração e cancelar; dados atuais continuam iguais.
5. Preparar uma cópia antiga, fazer um lançamento e reiniciar. A cópia antiga é aplicada e o lançamento novo fica na proteção **Antes de restaurar**.
6. Restaurar essa proteção e reiniciar; recuperar o lançamento novo e os demais registros.
7. Selecionar arquivo inválido; conferir rejeição sem substituir os dados.
8. Conferir cartões/faturas/séries e saldos após restauração; testar Android e Windows.
