# Anexos sincronizados — #16

Anexos de receitas/despesas, transferências e compras individuais acompanham a sincronização manual e automática com o app aberto, Android ↔ Windows. Cada arquivo continua limitado a 20 MB. Atualizar os dois dispositivos antes de sincronizar (schema 26).

## Transporte e integridade

Os vínculos, nomes, tamanhos e SHA-256 entram no mesmo protocolo dos dados financeiros. O conteúdo vai em objetos binários separados na pasta privada do app no Drive, identificados por base e hash. Arquivos iguais usam o mesmo conteúdo na mesma base; os vínculos permanecem individuais. Os objetos não aparecem na lista de backups SQLite.

O remetente envia e confirma os binários antes de publicar as referências. Uma resposta perdida mantém o pacote financeiro pendente e a tentativa seguinte concilia os hashes já enviados. O receptor baixa apenas os arquivos necessários ao estado final, verifica tamanho, SHA-256 e MD5 e só então aplica os vínculos juntamente com os dados financeiros. Uma falha mantém os dados atuais e a fila. Downloads completos ficam no cache para retomada; arquivos incompletos não são gravados.

As transferências são sequenciais, um arquivo por vez. O limite de 64 MB continua nos pacotes financeiros e no backup SQLite completo enviado ao Drive; os arquivos separados não entram no tamanho desses pacotes. O backup local completo inclui o conteúdo dos anexos.

## Exclusões, lixeira e recuperação

Excluir um anexo propaga uma marca definitiva de exclusão, sem ressuscitar o vínculo por um pacote antigo ou edição offline. Adicionar novamente cria um novo vínculo. A lixeira do lançamento preserva os anexos; restaurar reabre seu acesso. Exclusão definitiva do lançamento também exclui os vínculos e impede restauração por conflitos.

O cache local sem referência é removido quando não há envio imutável pendente que ainda precise dele. Os objetos e pacotes remotos antigos são preservados para recuperação das bases e backups; excluir um vínculo não apaga imediatamente o objeto histórico no Drive. Não há limpeza destrutiva automática do histórico remoto nesta entrega.

Publicação inicial e substituição de base enviam os anexos antes de ativar a base. Gerações anteriores e seus objetos ficam preservados. Receber outra base substitui os vínculos após backup de proteção; não mescla anexos de bases independentes.

## Migração e conferência

A migração mantém IDs, nomes, vínculos e conteúdo dos anexos locais existentes, valida os hashes e captura seus metadados quando a base já está vinculada. Uploads financeiros v25 pendentes mantêm identidade e conteúdo; pacotes antigos permanecem legíveis. Clientes antigos recusam pacotes com o novo schema; é necessário atualizar ambos.

Conferir no uso: adicionar no Android e abrir/salvar no Windows; adicionar no Windows e receber no Android; repetir sync sem duplicatas; excluir offline e sincronizar; mandar lançamento à lixeira/restaurar; excluir definitivamente; interromper o envio e repetir; receber/substituir base; exportar/restaurar backup. A #16 permanece aberta para validação manual do usuário.
