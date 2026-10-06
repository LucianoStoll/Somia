# Detalhamento do saldo: fechamento por arraste

Relato de 06/10/2026: no Android, ao segurar o título “Detalhamento do saldo” e arrastar para baixo, o painel desaparecia e o dashboard permanecia coberto por uma camada clara.

## Alteração

O cabeçalho e a alça reconhecem o gesto de fechamento sem manipular o controlador de animação do BottomSheet. Arrastar pelo menos 48 pixels para baixo ou fazer um gesto rápido para baixo fecha a rota pelo mesmo Navigator.pop usado pelo botão X. Um arraste curto ou para cima mantém o painel aberto. A rolagem dos dados segue independente. A superfície do painel e a barreira escura têm cores explícitas. Desktop mantém diálogo e botão X.

## Validação

Testes de widget adicionados para Android e iOS: fechar pelo título, reabrir três vezes, ausência de BottomSheet e ModalBarrier após fechamento, arraste curto sem fechar e rolagem até o saldo previsto. Formatação Dart e git diff --check conferidos. Execução dos testes Flutter pendente: o SDK local não contém os artefatos necessários.

No aparelho: abrir pelo card de saldo, arrastar o título/alça para baixo, conferir que o dashboard continua utilizável, reabrir, rolar os valores e fechar pelo X, toque externo e Voltar. A correção mitiga o caminho de animação do arraste nativo; a causa específica de renderização no aparelho ainda depende desta validação.
