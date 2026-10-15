import 'package:flutter/material.dart';

class CompactMovementDate extends StatelessWidget {
  const CompactMovementDate(
      {super.key,
      required this.label,
      required this.date,
      required this.onTap});
  final String label;
  final DateTime date;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(children: [
            const Icon(Icons.calendar_today_outlined, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(label)),
            const SizedBox(width: 8),
            Flexible(
                child: Text(
                    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}',
                    textAlign: TextAlign.right))
          ])));
}
