# Calculadora monetária — #34 / v0.2.0-alpha

Funcionalidade pós-MVP. A versão v0.1.0-alpha permanece o marco já concluído.

## Uso

Nos formulários de receitas, despesas e transferências, toque em Valor ou
pressione Enter na descrição. A calculadora abre com o valor atual e substitui
o teclado numérico nativo. O primeiro número substitui o valor anterior;
um operador continua a partir dele. `00`, vírgula, C e apagar aceleram a entrada.

`=` mostra o resultado e permite continuar a conta. Confirmar valor calcula e
aplica os centavos ao formulário; o lançamento é salvo pelo botão do formulário.
Fechar, voltar ou dispensar o painel conserva o valor que estava no campo.
No Windows, números e operadores do teclado físico funcionam; Enter confirma,
Escape cancela, Backspace apaga e Delete limpa.

## Precisão e reutilização

`core/money/monetary_calculator.dart` não depende de Flutter, banco ou telas.
A expressão admite duas casas em cada operando e respeita multiplicação/divisão
antes de soma/subtração. Frações de BigInt preservam os intermediários (por
exemplo, `1 ÷ 3 × 3 = 1,00`). O resultado é arredondado uma única vez para
centavos, com metade para fora de zero. `=` encerra a expressão, arredonda e
inicia uma nova conta a partir desse valor monetário.

`showMonetaryCalculator` retorna `int?`: centavos confirmados ou null no
cancelamento. `MonetaryCalculatorField` liga o componente a um controller,
FocusNode e moeda. Os formulários exigem valor positivo; a API independente
aceita outros limites para futuros usos. Os valores seguem o teto existente
do MoneyMinor. Divisão por zero, contas incompletas e valores fora dos limites
mantêm a calculadora aberta e permitem correção. Não há dependência nova ou
migration. A edição rápida da lista (#43) poderá usar a mesma API; ela não faz
parte desta implementação.

## Validação manual antes do fechamento do ciclo

- Android: criar/editar receita, despesa e transferência; tocar Valor e avançar
  com Enter na descrição; conferir ausência do teclado nativo no painel.
- Confirmar entrada direta e as quatro operações; salvar e reabrir o lançamento.
- Abrir um valor existente, alterar e cancelar/voltar; conferir valor preservado.
- Verificar divisão por zero, resultado zero/negativo e conta incompleta.
- Verificar tela estreita/paisagem, texto ampliado e rolagem até Confirmar valor.
- Windows: repetir confirmação/cancelamento e testar teclado físico.
- Atualizar o APK sobre a instalação atual e conferir os dados existentes.
