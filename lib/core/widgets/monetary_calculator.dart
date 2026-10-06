import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../money/monetary_calculator.dart';
import '../../features/accounts/domain/money_minor.dart';

/// Retorna centavos ao confirmar e null ao cancelar, voltar ou tocar fora.
Future<int?> showMonetaryCalculator(BuildContext context,
    {required int initialMinor,
    String currencyCode = 'BRL',
    int? minimumMinor}) async {
  final panel = _CalculatorPanel(
      initialMinor: initialMinor,
      currencyCode: currencyCode,
      minimumMinor: minimumMinor);
  final navigator = Navigator.of(context, rootNavigator: true);
  final mobile = Theme.of(context).platform == TargetPlatform.android ||
      Theme.of(context).platform == TargetPlatform.iOS;
  final TransitionRoute<int> route = mobile
      ? ModalBottomSheetRoute<int>(
          builder: (_) => panel,
          capturedThemes:
              InheritedTheme.capture(from: context, to: navigator.context),
          barrierLabel:
              MaterialLocalizations.of(context).modalBarrierDismissLabel,
          isScrollControlled: true,
          useSafeArea: true)
      : DialogRoute<int>(
          context: context,
          builder: (_) => Dialog(child: SizedBox(width: 420, child: panel)));
  final result = await navigator.push<int>(route);
  // A restauração de foco ocorre durante a animação de saída. Só liberar
  // a próxima abertura quando a rota tiver sido removida por completo.
  await route.completed;
  return result;
}

/// Campo global: teclado nativo desativado e calculadora também no avanço
/// por Enter/Tab. O controller só recebe o resultado confirmado.
class MonetaryCalculatorField extends StatefulWidget {
  const MonetaryCalculatorField({
    super.key,
    required this.controller,
    this.focusNode,
    this.currencyCode = 'BRL',
    this.labelText = 'Valor',
    this.minimumMinor = 1,
  });
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String currencyCode, labelText;
  final int? minimumMinor;

  @override
  State<MonetaryCalculatorField> createState() =>
      _MonetaryCalculatorFieldState();
}

class _MonetaryCalculatorFieldState extends State<MonetaryCalculatorField> {
  late FocusNode _focus;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _focus = widget.focusNode ?? FocusNode();
    _focus.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(MonetaryCalculatorField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      _focus.removeListener(_onFocus);
      if (oldWidget.focusNode == null) _focus.dispose();
      _focus = widget.focusNode ?? FocusNode();
      _focus.addListener(_onFocus);
    }
  }

  void _onFocus() {
    if (_focus.hasFocus) _open();
  }

  Future<void> _open() async {
    if (_opening || !mounted) return;
    _opening = true;
    FocusManager.instance.primaryFocus?.unfocus();
    final result = await showMonetaryCalculator(
      context,
      initialMinor: MoneyMinor.parse(widget.controller.text),
      currencyCode: widget.currencyCode,
      minimumMinor: widget.minimumMinor,
    );
    if (!mounted) return;
    if (result != null) {
      widget.controller.text = MoneyMinor.plain(result);
    }
    _focus.unfocus();
    _opening = false;
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    if (widget.focusNode == null) _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: widget.controller,
        focusNode: _focus,
        readOnly: true,
        keyboardType: TextInputType.none,
        enableInteractiveSelection: false,
        onTapAlwaysCalled: true,
        onTap: _open,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          labelText: widget.labelText,
          suffixIcon: const Icon(Icons.calculate_outlined),
        ),
        validator: (value) {
          try {
            final minor = MoneyMinor.parse(value ?? '');
            return widget.minimumMinor != null && minor < widget.minimumMinor!
                ? 'O valor deve ser maior que zero.'
                : null;
          } on FormatException catch (error) {
            return error.message;
          }
        },
      );
}

class _CalculatorPanel extends StatefulWidget {
  const _CalculatorPanel({
    required this.initialMinor,
    required this.currencyCode,
    this.minimumMinor,
  });
  final int initialMinor;
  final String currencyCode;
  final int? minimumMinor;

  @override
  State<_CalculatorPanel> createState() => _CalculatorPanelState();
}

class _CalculatorPanelState extends State<_CalculatorPanel> {
  late final _calculator = MonetaryCalculator(widget.initialMinor);
  String? _error;

  void _press(String key) {
    setState(() {
      _error = null;
      try {
        switch (key) {
          case 'C':
            _calculator.clear();
          case '⌫':
            _calculator.backspace();
          case ',':
            _calculator.decimal();
          case '=':
            _calculator.equals();
          case '+':
          case '−':
          case '×':
          case '÷':
            _calculator.operator(key);
          default:
            _calculator.digit(key);
        }
      } on FormatException catch (error) {
        _error = error.message;
      }
    });
  }

  void _confirm() {
    try {
      final result = _calculator.resultMinor();
      if (widget.minimumMinor != null && result < widget.minimumMinor!) {
        throw const FormatException('O valor deve ser maior que zero.');
      }
      Navigator.pop(context, result);
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.pop(context);
    } else if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _confirm();
    } else if (event.logicalKey == LogicalKeyboardKey.backspace) {
      _press('⌫');
    } else if (event.logicalKey == LogicalKeyboardKey.delete) {
      _press('C');
    } else {
      final key = switch (event.character) {
        '.' => ',',
        '-' => '−',
        '*' => '×',
        '/' => '÷',
        final value => value,
      };
      if (key == null || !RegExp(r'^[0-9,+−×÷=]$').hasMatch(key)) {
        return KeyEventResult.ignored;
      }
      _press(key);
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child:
                          Text('Calculadora', style: TextStyle(fontSize: 20)),
                    ),
                    IconButton(
                      tooltip: 'Cancelar',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    widget.currencyCode,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  child: Text(
                    _calculator.expression,
                    key: const ValueKey('calculator-expression'),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (_error != null)
                  Text(
                    _error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                const SizedBox(height: 16),
                for (final row in [
                  ['C', '⌫', '÷', '×'],
                  ['7', '8', '9', '−'],
                  ['4', '5', '6', '+'],
                  ['1', '2', '3', '='],
                  ['00', '0', ','],
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        for (final key in row)
                          Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 3),
                              child: FilledButton.tonal(
                                key: ValueKey('calculator-key-$key'),
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size(48, 52),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                ),
                                onPressed: () => _press(key),
                                child: Semantics(
                                  label: switch (key) {
                                    'C' => 'Limpar',
                                    '⌫' => 'Apagar último dígito',
                                    '÷' => 'Dividir',
                                    '×' => 'Multiplicar',
                                    '−' => 'Subtrair',
                                    '+' => 'Somar',
                                    '=' => 'Calcular resultado',
                                    ',' => 'Separador decimal',
                                    _ => key,
                                  },
                                  child: Text(
                                    key,
                                    style: const TextStyle(fontSize: 22),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _confirm,
                    child: const Text('Confirmar valor'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
