# Substituir a base do Drive — issue #71

Quando a base correta está no Android e já existe outra no Drive, abra Configurações → Sincronização → Buscar bases no Drive. Escolha **Substituir base do Drive pela deste Android** e confirme a conta e o aviso. A publicação inicial também mostra essa alternativa ao encontrar uma base existente.

Atualize Android e Windows juntos antes de usar. No Windows, a sincronização detectará a substituição e preservará as pendências locais, sem enviá-las. Clique em **Receber** e confirme para substituir os dados locais com uma cópia Antes de restaurar. Alterações exclusivas do Windows não são mescladas automaticamente.

## Proteção e recuperação

- Antes de preparar a nova publicação, o Android salva um backup manual validado, sem rotação automática. Os pacotes imutáveis da base anterior continuam no Drive, incluindo as alterações, e são validados antes do envio. Nenhum backup independente é apagado.
- A publicação usa uma nova identidade e um pacote `replacement`, contendo as identidades anteriores e a revisão remota confirmada. Clientes anteriores rejeitam esse tipo e precisam ser atualizados; não conseguem escrever na nova geração. Uma operação antiga já em trânsito pode terminar na geração antiga; isso é detectado e interrompe o fluxo, preservando todos os pacotes.
- O pacote pendente é persistido antes da rede. Se houver falha ou perda da resposta, use **Retomar publicação pendente**. O app confirma o mesmo pacote no Drive antes de mudar o vínculo local, sem gerar outra base. Os dados financeiros locais permanecem no Android; alterações durante o envio são registradas para a nova geração.
- Se o Drive mudar antes do envio, o app recusa a operação. Use **Cancelar publicação pendente**, busque novamente e confirme. Cancelar só é permitido quando o pacote não foi encontrado na mesma conta do Drive; uma publicação já enviada precisa ser retomada.
- Publicações concorrentes ou alterações tardias em uma geração substituída interrompem a sincronização. Não há decisão automática por horário: as versões permanecem recuperáveis. A recuperação desses conflitos excepcionais exige análise dos pacotes preservados; ainda não há uma interface de seleção de ramo concorrente.
- A API de arquivos do Drive não oferece uma transação entre vários dispositivos. A solução usa pacotes imutáveis, revisão antes do envio, verificação posterior e interrupção em divergências; não promete exclusão mútua distribuída.
- Restauração de backup continua desvinculando a sincronização e não republica automaticamente. Depois de conferir os dados restaurados, o usuário pode escolher a substituição.
- Mantidos os limites existentes de 64 MB por operação. Anexos locais não passam a ser sincronizados por esta correção; seguem o suporte e as limitações da implementação de anexos. Backups locais mantêm sua proteção existente.

## Roteiro de validação

1. Atualizar os dois dispositivos preservando instalação e dados. Exportar uma cópia manual se desejar conferir a recuperação.
2. No Android com dados atuais, buscar a base antiga, abrir a substituição e cancelar. Conferir que nada mudou.
3. Confirmar a substituição. Conferir contas, valores e lançamentos locais.
4. No Windows com alterações offline, sincronizar: deve bloquear o envio antigo e oferecer recebimento. Cancelar mantém os dados locais. Confirmar salva proteção e recebe a nova base.
5. Criar, editar e excluir após o novo vínculo em ambos os dispositivos; conferir sync normal sem duplicação.
6. Simular falha/perda de resposta e retomar a publicação; deve existir apenas um pacote da operação.
7. Confirmar que mudanças no Drive depois da listagem exigem nova confirmação e que outra conta Google não retoma a publicação pendente.

A issue permanece aberta até validação manual. Esta documentação não significa substituição da base real do usuário.

## Integração com edição em lote e investimentos — 09/10/2026

Esta integração inclui o CRUD/correção de contas e a seleção em lote pelo menu da #73. Schema atual 24; leitura financeira histórica até 23 preservada junto ao protocolo replacement. Publicações replacement v23 pendentes mantêm bytes, hash e identidade durante a migração, permitindo confirmar uma publicação já enviada sem duplicar a base. Testes cobrem essa atualização e retomada junto da exclusão/reutilização de uma aplicação durante o envio.

A suíte Windows usa duas execuções paralelas para reduzir disputa de I/O nos testes de migração/backup. Nenhum teste foi removido. Os três cenários de migração/backup que apresentaram timeout (v6, v7 e planejamento v17) têm limite pontual de dois minutos no Windows e mantêm 30 segundos nos demais sistemas; as verificações de conteúdo, integridade e filas continuam intactas. Os outros testes mantêm o limite padrão. Esta mudança não altera os dados do usuário nem substitui a base do Drive automaticamente.
