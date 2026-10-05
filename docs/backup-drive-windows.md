# Backup no Google Drive — Windows

Entrega #51 da #16, após a validação Android da #50. Mesmo fluxo manual: conectar, enviar backup, atualizar lista e restaurar com confirmação. Não sincroniza nem mescla lançamentos automaticamente.

## Configuração inicial

1. No mesmo projeto Google do Android, abrir Google Auth Platform → Clientes → Criar cliente.
2. Tipo **App para computador** (Desktop app), nome Somia Windows. Não usar Android, Web ou UWP. Não pede SHA-1.
3. Baixar o JSON do cliente. A Drive API e os usuários de teste são configurados no projeto já utilizado no Android.
4. No Somia Windows, Ajustes → Backup no Google Drive → Configurar Google Drive, selecionar esse JSON.
5. Conectar conta Google, escolher a mesma conta do Android e autorizar no navegador padrão. Voltar ao Somia.

A importação é feita uma vez por instalação. Alterar o cliente desconecta a conta deste computador, preservando dados e cópias. O arquivo importado não precisa ser enviado ao desenvolvedor nem incluído no repositório. Nunca usar chave de API, credenciais de conta de serviço, senha Google ou cliente Web nessa configuração.

## Autorização e dados locais

Fluxo Authorization Code com PKCE S256, state aleatório e callback em `127.0.0.1` numa porta dinâmica. Servidor somente loopback, espera de três minutos e cancelamento pelo Somia. Não usa navegador embutido, entrada manual de código ou listener na rede local. Endpoints Google fixos; o JSON não define destinos de rede.

Permissões: pasta privada `drive.appdata` e identificação pelo e-mail (`userinfo.email`). As permissões concedidas são conferidas antes de persistir uma sessão. O token de acesso permanece em memória; é renovado quando necessário. O refresh token, configuração e e-mail são protegidos com DPAPI, vinculados ao usuário Windows, em `somia-drive.dpapi` na pasta de suporte. Não entram na base SQLite nem no backup financeiro. Copiar esse arquivo para outro usuário/computador não migra a autorização; reconectar no novo dispositivo.

Desconectar apaga a sessão local e mantém o cliente configurado. Não exclui cópias do Drive ou revoga o consentimento Google. A revogação pode ser feita na conta Google. Configuração inválida, cancelamento ou autorização incompleta não substituem a sessão anterior.

## Compatibilidade e validação

Use cliente Desktop e Android **do mesmo projeto Google**, e a mesma conta Google, para consultar as cópias privadas do aplicativo entre dispositivos. A autorização de cada dispositivo é independente. A recuperação reutiliza metadados, tamanho, MD5/SHA-256 e validação SQLite da #50, com proteção local da #49. Aplicação da restauração na próxima abertura.

Validar no Windows:
- Importar JSON, conectar, cancelar e reconectar pelo navegador.
- Listar cópia criada no Android e restaurar no Windows; fechar/reabrir e conferir dados.
- Enviar cópia do Windows e consultá-la no Android.
- Reabrir Windows e confirmar renovação sem novo consentimento; desconectar e trocar conta.
- Sem rede, manter o uso financeiro offline e mensagem de erro na operação Drive.

Testes usam transporte e armazenamento substituídos; não enviam dados reais ao Google. Compilação Windows verifica o bridge DPAPI/navegador. Acesso real e visibilidade Android ↔ Windows dependem da validação manual com o cliente Desktop configurado.

Referência: https://developers.google.com/identity/protocols/oauth2/native-app.
