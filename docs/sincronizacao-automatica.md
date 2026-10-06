# Sincronização automática com app aberto — #55

Continuação da [sincronização manual #53](sincronizacao-drive.md), no fechamento #54 da `v0.2.0-alpha`. O primeiro vínculo continua explícito: publicar a base no Android e receber no Windows com a mesma conta Google e uma cópia de proteção dos dados anteriores.

## Comportamento

**Sincronização automática** fica nos Ajustes e vem ativada. A escolha é salva fora do banco financeiro e permanece após reabrir ou restaurar um backup. Pode ser desativada; o botão **Sincronizar agora** continua disponível.

**Quando sincronizar** permite escolher **Alterações agrupadas** (padrão existente, espera três segundos após detectar a última alteração) ou **A cada alteração** (inicia o ciclo após salvar, sem essa espera). O modo também é salvo fora do banco e permanece após reabrir ou restaurar. Somente transações concluídas disparam a observação; gravações parciais e operações revertidas não iniciam envio.

Após o vínculo, o app sincroniza ao abrir e retomar. Enquanto está em primeiro plano, recebe notificações de alterações financeiras confirmadas; a verificação a cada dois segundos continua como apoio. Novas alterações durante um envio permanecem pendentes e geram outro ciclo. O app consulta alterações remotas a cada minuto, mesmo sem edição local.

Nenhuma base é publicada ou substituída automaticamente ao conectar a conta. Uma restauração de backup continua limpando o vínculo; sem base vinculada, não há sincronização automática.

Ao ir para segundo plano, novos ciclos e timers são suspensos. Uma requisição iniciada pode terminar; a aplicação ainda não iniciada espera o app retornar. Não há serviço de execução com o aplicativo fechado. Consultas remotas e envios usam a autorização já concedida: falhas de autorização exigem reconexão manual e não abrem seletor/login por conta própria.

## Concorrência e interface

Sincronização manual, autorização e operações locais ocupadas adiam o agendador. Formulários e sobreposições nos navegadores principal e da seção também adiam a operação. Se um formulário abrir durante o download, os dados recebidos não são aplicados nem confirmados; o ciclo é tentado novamente depois. A verificação ocorre novamente na fila local imediatamente antes de aplicar os dados.

Após aplicação automática, as telas recarregam mantendo a seção/URI atual. Recebimentos sem alteração financeira não recriam as telas. A restauração manual mantém seu comportamento de retornar aos Ajustes. O histórico e a recuperação de conflitos da #53 continuam disponíveis.

Em falhas, dados e pendências são preservados. As novas tentativas esperam 15 segundos, 30 segundos, um minuto, dois minutos e depois cinco minutos entre tentativas. O erro e o horário da nova tentativa aparecem nos Ajustes; o botão manual permite tentar imediatamente. Retomar o app também inicia uma nova tentativa. Alterações locais durante a espera não provocam repetição contínua de chamadas.

Os limites de tamanho, schema/protocolo, integridade e compactação são os mesmos da #53. Desativar a opção impede iniciar novos ciclos; não desfaz uma gravação já aplicada ou um envio já iniciado.

## Validação manual

1. Atualizar Android e Windows preservando a instalação e vínculo existentes.
2. Abrir ambos: conferir última sincronização, pendências e escolha automática nos Ajustes.
3. Criar um lançamento no Android, aguardar envio agrupado; conferir no Windows após a consulta automática. Repetir no sentido contrário.
4. Fazer várias edições seguidas e conferir envio final sem duplicação; testar cartões, parcelas, transferências e pagamentos.
5. Abrir um formulário e digitar. Fazer uma mudança no outro dispositivo: o formulário deve continuar intacto. Fechar/salvar e conferir atualização sem trocar de seção.
6. Pausar e retomar: conferir ausência de novos ciclos no segundo plano e sincronização ao retornar.
7. Desligar a internet: conferir erro, pendências e repetição com espera. Reconectar e conferir convergência.
8. Selecionar A cada alteração e conferir envio após salvar; alternar para Alterações agrupadas e conferir a espera. Fechar/reabrir e verificar o modo escolhido. Desativar a opção, fechar/reabrir: a escolha deve permanecer. O botão manual deve continuar funcionando.
9. Restaurar um backup: conferir desvinculação e ausência de publicação automática dos dados restaurados.
10. Desconectar/trocar a conta: não abrir login automaticamente nem substituir dados. Reconectar manualmente a conta vinculada.
