# Identidade visual dos módulos — 15/10/2026

Solicitação: aplicar a identidade do Resumo às telas Pessoas e reembolsos, Cashback, Planejamento, Análises, Investimentos, Bens e patrimônio e Dívidas e empréstimos, conforme as sete capturas enviadas pelo usuário.

A paleta grafite/pastel agora é compartilhada em `core/theme/app_theme.dart`; o Resumo referencia os mesmos tokens, evitando duas identidades no app. Campos deixam de ter bordas claras excessivas. Botões de adição, barras, abas, menus e títulos usam a mesma hierarquia.

Componentes comuns: ModuleSurface (largura limitada no desktop e separação de cards), ModuleHero (indicador principal, ícone e valor pastel), ModuleStat (indicador compacto), ModuleValueRow (rótulo/valor responsivo) e ModuleDetails (informações complementares expansíveis).

- Pessoas: gestão do cadastro recolhível; total a receber separado por moeda; busca/filtro preservados e reembolsos com ícones/estados e cards separados.
- Cashback: previsto/recebido em indicadores, cards compactos com origem, valor e situação em destaque; regras explicativas sob demanda e confirmação próxima ao valor.
- Planejamento: abas e barras pastéis, limite em destaque, valores organizado em grupos e instruções recolhíveis.
- Análises: instruções em Como interpretar, total destacado e barras pastéis alternadas, mantendo escala e valores reais.
- Investimentos: saldo principal no mesmo padrão do Resumo; ações de aporte/resgate/rendimento/conferência em Movimentar; extrato acessível e gestão/observações recolhíveis.
- Patrimônio: indicador principal e composição expansível; dados de aquisição/contrato/observações no detalhe de cada bem.
- Dívidas: saldo/projeção destacados, explicação e dados complementares expansíveis; vínculos e histórico continuam disponíveis.

Não há migration ou alteração dos cálculos, datas, saldos, CRUD, backup ou sincronização. A nova organização mantém ações e dados acessíveis. Preferências do Resumo já entregues são preservadas.

Validar CI Linux/Windows, responsividade/fonte ampliada, prévias Android/Windows e ações de cada módulo. A aprovação manual permanece pendente após a entrega técnica.
