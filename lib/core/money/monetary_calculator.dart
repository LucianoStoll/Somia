/// Calculadora decimal exata. Intermediários são frações de BigInt;
/// apenas o resultado confirmado é arredondado para centavos (metade para fora).
class MonetaryCalculator {
  MonetaryCalculator(int initialMinor) {
    expression = _plain(initialMinor);
  }

  late String expression;
  bool _replaceOnDigit = true;
  static final _operators = RegExp(r'[+−×÷]');

  void clear() {
    expression = '0';
    _replaceOnDigit = true;
  }

  void backspace() {
    expression = expression.length > 1
        ? expression.substring(0, expression.length - 1)
        : '0';
    _replaceOnDigit = false;
  }

  void digit(String digit) {
    if (!RegExp(r'^\d{1,2}$').hasMatch(digit)) return;
    if (_replaceOnDigit) {
      expression = '0';
      _replaceOnDigit = false;
    }
    final operand = expression.split(_operators).last;
    if (operand.contains(',') &&
        operand.split(',').last.length + digit.length > 2) {
      return;
    }
    if (expression.length + digit.length > 120) return;
    if (operand == '0') {
      expression = expression.substring(0, expression.length - 1);
    }
    expression += digit == '00' && operand == '0' ? '0' : digit;
  }

  void decimal() {
    if (_replaceOnDigit) {
      expression = '0';
      _replaceOnDigit = false;
    }
    final operand = expression.split(_operators).last;
    if (operand.contains(',') || expression.length >= 120) return;
    expression += operand.isEmpty ? '0,' : ',';
  }

  void operator(String operator) {
    if (!['+', '−', '×', '÷'].contains(operator)) return;
    _replaceOnDigit = false;
    if (_operators.hasMatch(expression[expression.length - 1])) {
      expression = expression.substring(0, expression.length - 1);
    }
    if (expression.endsWith(',')) expression += '0';
    if (expression.length < 120) expression += operator;
  }

  int resultMinor() {
    final tokens = RegExp(r'-?\d+(?:,\d{0,2})?|[+−×÷]')
        .allMatches(expression)
        .map((match) => match.group(0)!)
        .toList();
    if (tokens.join() != expression || tokens.length.isEven) {
      throw const FormatException('Complete a operação.');
    }
    var total = _Fraction(BigInt.zero, BigInt.one);
    var term = _Fraction.parse(tokens.first);
    var sign = '+';
    for (var i = 1; i < tokens.length; i += 2) {
      final next = _Fraction.parse(tokens[i + 1]);
      switch (tokens[i]) {
        case '×':
          term = term.multiply(next);
        case '÷':
          term = term.divide(next);
        case '+':
        case '−':
          total = sign == '+' ? total.add(term) : total.subtract(term);
          sign = tokens[i];
          term = next;
      }
    }
    total = sign == '+' ? total.add(term) : total.subtract(term);
    final scaled = total.numerator.abs() * BigInt.from(100);
    var minor = scaled ~/ total.denominator;
    if ((scaled % total.denominator) * BigInt.two >= total.denominator) {
      minor += BigInt.one;
    }
    // Mesmo teto aceito pelo conversor monetário do app.
    if (minor > BigInt.parse('9000000000000099')) {
      throw const FormatException('Valor acima do limite permitido.');
    }
    return (total.numerator.isNegative ? -minor : minor).toInt();
  }

  void equals() {
    expression = _plain(resultMinor());
    _replaceOnDigit = true;
  }

  static String _plain(int minor) =>
      '${minor < 0 ? '-' : ''}${minor.abs() ~/ 100},${(minor.abs() % 100).toString().padLeft(2, '0')}';
}

class _Fraction {
  factory _Fraction(BigInt numerator, BigInt denominator) {
    final divisor = numerator.gcd(denominator);
    return _Fraction._(numerator ~/ divisor, denominator ~/ divisor);
  }
  const _Fraction._(this.numerator, this.denominator);
  final BigInt numerator;
  final BigInt denominator;

  factory _Fraction.parse(String text) {
    if (!RegExp(r'^-?\d+(?:,\d{0,2})?$').hasMatch(text)) {
      throw const FormatException('Complete a operação.');
    }
    final parts = text.split(',');
    final scale = parts.length == 1 ? 0 : parts.last.length;
    return _Fraction(BigInt.parse(parts.join()), BigInt.from(10).pow(scale));
  }

  _Fraction add(_Fraction other) => _Fraction(
        numerator * other.denominator + other.numerator * denominator,
        denominator * other.denominator,
      );
  _Fraction subtract(_Fraction other) => _Fraction(
        numerator * other.denominator - other.numerator * denominator,
        denominator * other.denominator,
      );
  _Fraction multiply(_Fraction other) =>
      _Fraction(numerator * other.numerator, denominator * other.denominator);
  _Fraction divide(_Fraction other) {
    if (other.numerator == BigInt.zero) {
      throw const FormatException('Não é possível dividir por zero.');
    }
    final sign = other.numerator.isNegative ? -BigInt.one : BigInt.one;
    return _Fraction(
      numerator * other.denominator * sign,
      denominator * other.numerator.abs(),
    );
  }
}
