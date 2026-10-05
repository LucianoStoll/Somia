# Backup manual no Google Drive (Android)

Entrega #50 da #16. O Android pode conectar uma conta Google, enviar uma cópia consistente do banco local, listar as cópias privadas e preparar uma restauração. Windows continua com backup local. Não há envio automático, mesclagem ou sincronização de lançamentos nesta etapa.

## Configuração do projeto Google

- Habilitar Google Drive API no mesmo projeto do cliente OAuth.
- Configurar o consentimento e adicionar a conta aos usuários de teste enquanto o projeto estiver em teste.
- Cliente OAuth Android: `160874973954-qrjodl5rnss1oopgip284l1pn2s9n5pj.apps.googleusercontent.com`.
- Pacote: `com.example.finapp`.
- SHA-1 do APK com assinatura persistente: `F5:87:0F:D2:52:A5:6E:C3:6F:C5:80:D8:97:A7:13:C4:D9:6E:66:C5`.
- O AuthorizationClient identifica o cliente Android pelo pacote e certificado. Não é necessário colocar esse ID em um serverClientId nem usar chave API. Nenhuma chave privada ou segredo deve ser colocado no aplicativo.

O seletor nativo escolhe a conta; a autorização usa explicitamente essa conta e pede apenas `https://www.googleapis.com/auth/drive.appdata`. Requer Google Play Services. O e-mail fica nas preferências privadas Android. Tokens de acesso são obtidos para as operações, mantidos apenas em memória; não gravamos refresh token ou credenciais no banco financeiro. Desconectar esquece a conta localmente; não revoga o consentimento Google nem apaga arquivos. O usuário pode revogar o acesso na conta Google.

## Arquivos e restauração

Os arquivos ficam em `appDataFolder`, invisíveis na lista comum do Drive. Cada envio cria uma cópia separada, identificada por metadados do Somia, com SHA-256. Não há exclusão ou retenção remota automática nesta entrega; as cópias consomem espaço da conta. Limite por cópia: 64 MB.

Downloads conferem metadados atuais, pasta privada, tamanho, MD5 do Drive e SHA-256 registrado. Depois, a validação SQLite verifica integridade, chaves estrangeiras e compatibilidade. A restauração é preparada para a próxima abertura; o fluxo local da #49 salva proteção antes da substituição. Uma conta diferente invalida a lista. Erros não substituem o banco em uso.

Requisições têm limite de tempo e tamanho; não há repetição automática de envios, evitando cópias duplicadas após uma resposta perdida. Se um envio der erro de conexão, atualizar a lista antes de reenviar. Permissão negada, token expirado e limites do Drive são informados em Ajustes.

## Validação real pendente

1. Instalar APK assinado e abrir Ajustes → Backup no Google Drive.
2. Conectar a conta de teste, aceitar a permissão, enviar backup e atualizar lista.
3. Cancelar uma restauração e confirmar que nada mudou.
4. Restaurar a cópia, fechar e reabrir o Somia; conferir lançamentos e proteção local.
5. Desconectar, conectar outra conta e conferir que as cópias anteriores não aparecem.
6. Cancelar o seletor/consentimento e testar sem rede. O uso financeiro offline deve continuar.

Os testes automatizados usam autorização e transporte substituídos. Não enviam dados reais ao Google. Consentimento, certificado cadastrado, Drive API habilitada e acesso real dependem da validação no Android.

Referências: https://developer.android.com/identity/authorization e https://developers.google.com/workspace/drive/api/guides/appdata.
