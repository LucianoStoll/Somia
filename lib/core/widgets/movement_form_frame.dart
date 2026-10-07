import 'package:flutter/material.dart';

bool usesFullScreenMovementForm(BuildContext context) =>
    Theme.of(context).platform == TargetPlatform.android;

Future<T?> showMovementForm<T>(BuildContext context, WidgetBuilder builder) =>
    usesFullScreenMovementForm(context)
        ? Navigator.of(context, rootNavigator: true).push<T>(
            MaterialPageRoute(builder: builder, fullscreenDialog: true))
        : showDialog<T>(context: context, builder: builder);

/// O rodapé participa da área redimensionada pelo teclado, sem cobrir campos.
class MovementFormFrame extends StatelessWidget {
  const MovementFormFrame(
      {super.key,
      required this.title,
      required this.child,
      required this.onSave,
      this.onCancel,
      this.saveLabel = 'Salvar lançamento',
      this.compact = false});
  final String title, saveLabel;
  final Widget child;
  final bool compact;
  final VoidCallback onSave;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final mobile = usesFullScreenMovementForm(context);
    final form = Theme(
      data: Theme.of(context).copyWith(
          listTileTheme: compact
              ? const ListTileThemeData(
                  contentPadding: EdgeInsets.zero, dense: true)
              : null,
          inputDecorationTheme: Theme.of(context).inputDecorationTheme.copyWith(
                isDense: true,
                filled: compact ? false : null,
                border: compact ? const UnderlineInputBorder() : null,
                enabledBorder: compact
                    ? const UnderlineInputBorder(
                        borderSide: BorderSide(color: Color(0xFF293746)))
                    : null,
                focusedBorder: compact
                    ? UnderlineInputBorder(
                        borderSide: BorderSide(
                            color: Theme.of(context).colorScheme.primary))
                    : null,
                contentPadding: EdgeInsets.symmetric(
                    horizontal: compact ? 0 : 14, vertical: compact ? 10 : 16),
              )),
      child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.all(mobile ? 16 : 0),
          child: child),
    );
    if (!mobile) {
      return AlertDialog(
        title: Text(title),
        content: SizedBox(width: 480, child: form),
        actions: [
          TextButton(
              onPressed: onCancel ?? () => Navigator.maybePop(context),
              child: const Text('Cancelar')),
          FilledButton(onPressed: onSave, child: Text(saveLabel)),
        ],
      );
    }
    return Scaffold(
      key: const ValueKey('movement-full-screen'),
      appBar: AppBar(
          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          leading: BackButton(
              onPressed: onCancel ?? () => Navigator.maybePop(context))),
      body: SafeArea(
        top: false,
        child: Column(children: [
          Expanded(child: form),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SizedBox(
                width: double.infinity,
                child: FilledButton(onPressed: onSave, child: Text(saveLabel))),
          ),
        ]),
      ),
    );
  }
}

class MovementDateFields extends StatelessWidget {
  const MovementDateFields(
      {super.key,
      required this.posted,
      required this.due,
      required this.onPosted,
      required this.onDue});
  final DateTime posted;
  final DateTime due;
  final VoidCallback onPosted;
  final VoidCallback onDue;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final first = _field(context, 'Lançamento', posted, onPosted);
        final second = _field(context, 'Vencimento', due, onDue);
        if (box.maxWidth >= 340 &&
            MediaQuery.textScalerOf(context).scale(14) < 21) {
          return Row(children: [
            Expanded(child: first),
            const SizedBox(width: 12),
            Expanded(child: second),
          ]);
        }
        return Column(children: [first, const SizedBox(height: 12), second]);
      });

  Widget _field(BuildContext context, String label, DateTime date,
          VoidCallback onTap) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: InputDecorator(
          decoration: InputDecoration(labelText: label),
          child: Row(children: [
            Expanded(
                child: Text(
                    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}')),
            const SizedBox(width: 6),
            const Icon(Icons.calendar_today_outlined, size: 18),
          ]),
        ),
      );
}
