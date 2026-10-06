import 'package:flutter/material.dart';

/// Uma única ação por feedback, inclusive ao tocar rapidamente nos dois botões.
void showEffectuationFeedback(
  BuildContext context, {
  required String message,
  required Future<void> Function() undo,
  required Future<void> Function() adjustDate,
}) {
  var used = false;
  final messenger = ScaffoldMessenger.of(context);
  void run(Future<void> Function() action) {
    if (used) return;
    used = true;
    messenger.hideCurrentSnackBar();
    action();
  }

  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(
      duration: const Duration(seconds: 5),
      content: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          children: [
            Text(message),
            Wrap(spacing: 8, children: [
              TextButton(
                  onPressed: () => run(undo), child: const Text('Desfazer')),
              TextButton(
                  onPressed: () => run(adjustDate),
                  child: const Text('Ajustar data')),
            ]),
          ])));
}
