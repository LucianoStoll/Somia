# Sincronização manual Google Drive — #53

Entrega inicial para Android e Windows na `v0.2.0-alpha`. Use a mesma conta Google e a mesma versão do app nos dois dispositivos. Reutiliza a autorização privada `drive.appdata` já configurada para backup; não exige outra chave API ou novo cliente OAuth.

## Primeiro vínculo

1. No Android, conecte a conta em Ajustes e escolha **Publicar base deste Android** em Sincronização entre dispositivos. Confirme que os dados deste Android serão a base inicial.
2. No Windows, conecte a mesma conta Google, escolha **Buscar bases no Drive**, depois **Receber**. A confirmação informa que os dados do Windows serão substituídos. Uma cópia **Antes de restaurar** é criada antes da substituição.
3. Quando ambos estiverem vinculados, use **Sincronizar agora**. O ciclo recebe alterações desconhecidas e envia as alterações locais. Para uma edição do Windows chegar ao Android: sincronize Windows, depois Android. Repita no outro sentido para edições do Android.

A sincronização desta fase é manual. Abrir o app, alterar lançamentos ou voltar do segundo plano não dispara envio. Automatização entra após validar este fluxo. É possível continuar lançando dados offline; a fila fica no banco e é enviada pelo botão quando houver conexão. Edições feitas durante um envio permanecem pendentes para o próximo ciclo.

## Conflitos e recuperação

A versão mais recente do mesmo registro prevalece; empate exato de tempo tem desempate estável por dispositivo. O relógio lógico avança a cada gravação e ao receber versões. O horário local é comparado com a resposta do Drive e diferenças acima de cinco minutos bloqueiam a operação, com orientação para ativar o horário automático.

Versões divergentes são preservadas no histórico local. **Ver versões anteriores** mostra até 100 conflitos mais recentes. **Recuperar** exige confirmação, protege os dados atuais e cria uma nova alteração local; o próximo envio compartilha a recuperação. Uma exclusão física mantém sua versão de remoção, impedindo que um envio antigo ressuscite o registro. Arquivamentos e exclusões lógicas também são sincronizados.

Contas, categorias, receitas, despesas, transferências, séries, cartões, faturas, compras, limites, pagamentos e histórico do cartão são enviados. Faturas novas têm uma identidade por cartão e mês, inclusive quando criadas offline nos dois dispositivos. Compras e pagamentos continuam registros separados: sincronização não recalcula nem duplica pagamentos.

## Proteção e limites

- O vínculo inclui conta Google e base; troca de conta, base divergente, arquivo corrompido, conteúdo alterado, protocolo/schema incompatível ou origem removida interrompem a operação.
- Dados financeiros, versões, histórico e confirmação de recebimento são gravados numa transação. Vínculos inválidos ou restrições financeiras incompatíveis fazem rollback, preservando os dados e as pendências. Se edições conflitantes de registros relacionados não formarem uma combinação válida, é necessário corrigir esses registros e tentar novamente.
- Pacotes imutáveis separados dos backups SQLite ficam na pasta privada do app. Tamanho, SHA-256, MD5, conteúdo e metadados são verificados. Credenciais permanecem fora do banco.
- Uma resposta perdida após upload é conciliada com o Drive no próximo ciclo. Pacotes repetidos são idempotentes; a fila só é confirmada após o envio/recebimento verificado. Não se apagam arquivos remotos nesta fase.
- Importar dados recebidos não cria uma nova fila de envio. Durante a aplicação, a barreira existente impede edições; telas e formulários recarregam após sucesso, sem reabrir o app.
- Restaurar um backup local ou remoto **desvincula a sincronização e limpa metadados operacionais**. O backup antigo não é publicado automaticamente como alterações atuais. Para continuar com a base do Drive, busque-a e receba-a novamente; essa operação substitui os dados restaurados com proteção local.
- Migration v11 cria apenas metadados e captura de alterações. A abertura de uma base publicada antiga cria uma cópia consistente **Antes de atualizar** antes de migrar. A identidade do dispositivo é persistida fora do arquivo SQLite e não é copiada ao restaurar um backup.
- Limite de 64 MB por pacote e por conjunto recebido em um ciclo, até 100 mil registros por pacote e 100 páginas de arquivos. Não há compactação/limpeza remota nesta fase; bases que ultrapassarem esses limites exigem evolução do protocolo.

## Validação manual da entrega

- Atualizar ambos sem desinstalar; conferir contas, saldos, lançamentos, cartões e backup.
- Publicar Android e receber Windows, verificando a cópia dos dados anteriores do Windows.
- Criar/editar/arquivar lançamentos nos dois sentidos; conferir atualização imediata das listas e saldos.
- Editar registros diferentes offline em ambos; sincronizar Android → Windows → Android e verificar convergência.
- Editar o mesmo registro nos dois; conferir a última edição e recuperar a versão anterior, sincronizando-a de volta.
- Fazer compras no mesmo cartão/mês offline nos dois; conferir uma fatura única, compras separadas e total correto.
- Criar parcelas/recorrências, transferências e pagamentos de cartão; repetir a sincronização e conferir ausência de duplicação.
- Desligar internet, tentar enviar, reabrir o app e tentar novamente; conferir pendências e dados preservados.
- Trocar a conta e alterar horário; conferir bloqueio sem substituição.
- Restaurar backup; conferir dados imediatos, desvinculação e ausência de envio automático do passado restaurado.
