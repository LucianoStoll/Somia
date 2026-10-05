# Importação CSV — #56 / epic #14

Primeira etapa da importação no fechamento #54 da v0.2.0-alpha. A entrada fica em **Ajustes → Importar extrato CSV** e funciona offline no Android e Windows.

## Arquivo e mapeamento

CSV com cabeçalho, até 2 MB, 5.000 linhas de dados, 50 colunas e 4.096 caracteres por campo. Aceita UTF-8/BOM e Windows-1252, separadores `;`, `,` ou tabulação, diretiva `sep=`, aspas escapadas e campos multilinha. O separador é detectado e pode ser corrigido antes da prévia.

Escolha uma conta ativa. Cada campo usa uma coluna distinta. Descrição, valor e data de lançamento são obrigatórios; vencimento, efetivação, tipo, categoria e subcategoria são opcionais. Cabeçalhos comuns são sugeridos, mas a seleção pode ser alterada. O valor usa a moeda da conta; não há conversão de moedas.

O formato decimal é explícito: brasileiro `1.234,56` ou internacional `1,234.56`. Valores são convertidos diretamente em centavos inteiros, sem ponto flutuante, arredondamento ou troca automática de separadores. Zero e valores fora do limite financeiro são inválidos.

Datas usam DD/MM/AAAA, AAAA-MM-DD ou MM/DD/AAAA, conforme a escolha. Datas inexistentes e fora de 1900–2100 são inválidas. Sem vencimento, usa-se o lançamento. **Sem efetivação, o lançamento fica pendente**, conforme decisão do usuário em 05/10/2026. Uma data explícita de efetivação é mantida, inclusive uma contabilização programada no futuro.

O tipo pode vir de uma coluna (receita/despesa ou crédito/débito), do sinal (+ receita, − despesa), ou ser fixado em Todas receitas/Todas despesas. Para despesas exportadas com valores positivos, escolha Todas despesas ou mapeie o tipo. Uma receita não pode ter valor negativo.

## Prévia e categorias

A prévia não grava dados. Mostra linha, descrição, tipo, valor, lançamento, vencimento, efetivação/pendência, erros, categoria e possíveis duplicados. Linhas válidas novas vêm selecionadas; erros e duplicados ficam desmarcados. É possível desmarcar linhas e escolher/remover uma categoria antes de confirmar.

Categorias/subcategorias já cadastradas são associadas por nome e tipo, ignorando caixa e acentuação. Nomes inexistentes ou ambíguos geram aviso e não criam categorias automaticamente. Sem classificação no arquivo, uma categoria ativa do histórico de mesmo texto/tipo é sugerida. A sugestão pode ser alterada na prévia.

Duplicidade considera conta, descrição normalizada, receita/despesa, valor, lançamento e vencimento. Categoria e efetivação não tornam um lançamento existente novo. Há sinalização no arquivo e contra receitas/despesas já cadastradas; nunca se substituem registros existentes. Pode haver lançamentos legítimos iguais: selecionar um duplicado e confirmar o aviso adiciona outra ocorrência intencionalmente.

## Confirmação e segurança dos dados

A confirmação informa a quantidade e os duplicados selecionados. O lote é gravado numa única transação, com UUIDs e os mesmos repositórios/regras das entradas manuais. Qualquer falha reverte todo o lote, incluindo alterações capturadas para sincronização. Conta/categoria são revalidadas; duplicados surgidos após a prévia são ignorados, exceto os selecionados explicitamente como duplicados.

A gravação é serializada com manutenção local. A tela de importação protege a prévia contra aplicação automática de dados remotos. Depois de concluir e fechar a prévia, as seções atualizam com o app aberto; a sincronização existente captura o lote confirmado. Cancelar ou voltar antes da confirmação mantém o banco intacto.

Esta etapa adiciona receitas/despesas em uma conta por importação. Não cria transferências, compras/faturas de cartão, séries, categorias ou contas; não altera saldo inicial. Excel, PDF, OFX, conciliação e demais relatórios da epic #14 ficam para entregas futuras.

## Validação manual

1. Atualizar Android e Windows sem desinstalar; abrir Ajustes → Importar extrato CSV.
2. Selecionar arquivo e conta; conferir separador, colunas, formatos e exemplos.
3. Conferir centavos, sinais, vencimento/efetivação e pendências na prévia. Ajustar categoria; desmarcar uma linha.
4. Cancelar a confirmação e conferir ausência de novos lançamentos; confirmar e conferir receitas/despesas, saldo e extrato atualizados.
5. Reimportar o mesmo arquivo e verificar duplicados desmarcados. Selecionar intencionalmente um duplicado e conferir o aviso antes de adicionar.
6. Testar arquivo com aspas/acentos e uma linha inválida; somente as linhas válidas escolhidas podem entrar.
7. Importar sem internet; conferir lote na sincronização quando reconectar e consulta no outro dispositivo com o app aberto.
