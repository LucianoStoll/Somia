# Anexos locais — #70

Primeira entrega da #11, na v0.3.0-alpha. Sincronização individual de arquivos permanece na #16.

## Uso
Salvar o lançamento e abrir seu menu → Anexos. Receitas/despesas, transferências e registros individuais do cartão permitem adicionar arquivos, visualizar imagens, salvar cópia e excluir com confirmação. PDFs e outros documentos são abertos pelo aplicativo escolhido após salvar cópia. Cancelar o seletor não altera os arquivos.

Limite de 20 MB por arquivo, sem arquivos vazios. Nome normalizado, UUID, tamanho e SHA-256. Arquivos são copiados para armazenamento interno SQLite (BLOB), não dependem da permanência do original. Anexos pertencem somente à ocorrência escolhida; não são propagados para outras parcelas nem pela edição em lote.

## Dados e compatibilidade
Migration aditiva 23; backup anterior automático. Arquivos acompanham backup completo SQLite local e Drive, inclusive restauração com app aberto. Backups anteriores migram com tabela vazia. Hash inválido bloqueia restauração antes da substituição. O crescimento dos arquivos aumenta o tamanho dos backups e continua sujeito aos limites do provedor.

Tabela local separada do conjunto sincronizado: sync financeiro não transporta bytes/metadados nem apaga arquivos locais ao substituir linhas financeiras. Atualizar os dois dispositivos antes de sincronizar schema 23; pacotes históricos até 22 continuam aceitos. A sincronização individual, escolha automático/Wi-Fi/manual e limpeza remota serão implementadas na #16.

Excluir movimento para lixeira preserva anexo; restaurar devolve acesso. Exclusão definitiva local remove seus anexos. Backups anteriores continuam contendo as cópias antigas. Exclusão remota torna o anexo inacessível pelo movimento, mas a limpeza física remota fica para #16. Não há acesso automático a arquivos originais nem execução de documentos.

## Validação
- [ ] Android e Windows: adicionar imagem/PDF, cancelar seletor, visualizar imagem, salvar cópia, cancelar/confirmar exclusão.
- [ ] Receitas/despesas, transferências e compras da fatura: verificar vínculo individual.
- [ ] Limites, arquivo vazio, nome longo e falha de leitura com mensagem.
- [ ] Lixeira/restauração/exclusão definitiva do lançamento.
- [ ] Backup completo em outro dispositivo e restauração de backup antigo.
- [ ] Sync financeiro mantém os anexos locais, sem prometer transporte de arquivos.

Testes automatizados cobrem conteúdo/hash, limite, vínculo inexistente, lixeira, backup/restauração atômica, migration v22 e isolamento do sync; teste de tela cobre listagem e confirmação. Validação técnica em andamento; aprovação manual pendente.
