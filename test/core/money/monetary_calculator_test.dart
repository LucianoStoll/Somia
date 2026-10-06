import 'package:finapp/core/money/monetary_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

MonetaryCalculator input(String text) {
  final calculator = MonetaryCalculator(0);
  for (final key in text.split('')) {
    if (key == ',') {
      calculator.decimal();
    } else if ('+−×÷'.contains(key)) {
      calculator.operator(key);
    } else {
      calculator.digit(key);
    }
  }
  return calculator;
}

void main() {
  for (final entry in <String, int>{
    '0,1+0,2': 30,
    '10−3,25': 675,
    '12,34×2': 2468,
    '10÷4': 250,
    '1÷3×3': 100,
    '2+3×4': 1400,
    '10−2−3': 500,
    '0,01÷2': 1,
    '0−0,01÷2': -1,
    '90000000000000,99': 9000000000000099,
  }.entries) {
    test('${entry.key} retorna centavos exatos', () {
      expect(input(entry.key).resultMinor(), entry.value);
    });
  }
  test(
    'preserva inicial; primeiro dígito substitui e operador usa inicial',
    () {
      final calculator = MonetaryCalculator(12345);
      expect(calculator.resultMinor(), 12345);
      calculator.operator('+');
      calculator.digit('1');
      expect(calculator.resultMinor(), 12445);
      calculator.equals();
      calculator.digit('2');
      expect(calculator.resultMinor(), 200);
    },
  );
  test('00, decimal, apagar, limpar e substituir operador', () {
    final calculator = MonetaryCalculator(0);
    calculator.digit('1');
    calculator.digit('00');
    calculator.decimal();
    calculator.digit('25');
    calculator.digit('9');
    expect(calculator.expression, '100,25');
    calculator.backspace();
    expect(calculator.resultMinor(), 10020);
    calculator.operator('+');
    calculator.operator('×');
    calculator.digit('2');
    expect(calculator.resultMinor(), 20040);
    calculator.clear();
    calculator.decimal();
    calculator.digit('5');
    expect(calculator.resultMinor(), 50);
  });
  test('erros não aplicam valores nem impedem corrigir expressão', () {
    final division = input('1÷0');
    expect(division.resultMinor, throwsFormatException);
    expect(division.expression, '1÷0');
    division.backspace();
    division.digit('2');
    expect(division.resultMinor(), 50);
    expect(input('1+').resultMinor, throwsFormatException);
    expect(input('90000000000001').resultMinor, throwsFormatException);
    expect(input('90000000000000×2').resultMinor, throwsFormatException);
  });
}
