import 'package:flutter/material.dart';
import '../../../core/sync/sync_manager.dart';
import '../../../core/sync/sync_packet.dart';
import 'local_backups_panel.dart';

class SyncPanel extends StatelessWidget {
  const SyncPanel({super.key, required this.manager, this.enabled = true});
  final SyncManager manager;
  final bool enabled;
  Future<bool> _confirm(
          BuildContext context, String title, String text) async =>
      await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                  scrollable: true,
                  title: Text(title),
                  content: Text(text),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancelar')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Continuar')),
                  ])) ==
      true;
  String _title(SyncEntry entry) =>
      entry.data?['description'] as String? ??
      entry.data?['name'] as String? ??
      switch (entry.table) {
        'accounts' => 'Conta',
        'categories' => 'Categoria',
        'transfers' => 'Transferência',
        'credit_cards' => 'Cartão',
        'card_invoices' => 'Fatura',
        'card_payments' => 'Pagamento de fatura',
        'card_limit_history' => 'Limite do cartão',
        'card_entry_history' => 'Histórico do cartão',
        _ => 'Lançamento',
      };
  Future<void> _history(BuildContext context) async {
    await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
              scrollable: true,
              title: const Text('Versões anteriores'),
              content: SizedBox(
                  width: 540,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text(
                        'A alteração mais recente prevalece. Recuperar uma versão cria uma nova alteração e preserva uma cópia dos dados atuais.'),
                    if (manager.history.isEmpty)
                      const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Nenhum conflito registrado.')),
                    for (final entry in manager.history)
                      ListTile(
                        title: Text(_title(entry)),
                        subtitle: Text(
                            '${entry.deleted ? 'Exclusão' : 'Versão anterior'} · ${entry.clock == 0 ? 'Versão inicial' : backupDate(DateTime.fromMillisecondsSinceEpoch(entry.clock))}'),
                        trailing: TextButton(
                            onPressed: () async {
                              final description = entry.data?['description'] ??
                                  entry.data?['name'];
                              final amount =
                                  entry.data?['planned_amount_minor'] ??
                                      entry.data?['amount_minor'] ??
                                      entry.data?['initial_balance_minor'];
                              if (!await _confirm(
                                  context,
                                  'Recuperar esta versão?',
                                  '${description ?? _title(entry)}\n${amount is int ? 'Valor: ${(amount / 100).toStringAsFixed(2).replaceAll('.', ',')}\n' : ''}${entry.deleted ? 'Esta versão remove o registro.' : 'Os dados desta versão voltarão a valer.'}\nA próxima sincronização enviará a recuperação.')) {
                                return;
                              }
                              if (!context.mounted) return;
                              Navigator.pop(context);
                              await manager.recover(entry);
                            },
                            child: const Text('Recuperar')),
                      ),
                  ])),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Fechar'))
              ],
            ));
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: manager,
      builder: (context, _) {
        final ready = enabled &&
            !manager.busy &&
            !manager.drive.busy &&
            !manager.local.busy;
        final state = manager.state;
        final linked = state?.base != null;
        return Card(
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Sincronização entre dispositivos',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      const Text(
                          'Envie e receba alterações pelo Google Drive. Nesta entrega, a sincronização começa pelo botão.'),
                      const SizedBox(height: 8),
                      Text(linked
                          ? 'Base vinculada à conta ${state!.email}'
                          : 'Primeiro publique a base pelo Android. Depois receba essa base no Windows.'),
                      if (!linked)
                        const Text(
                            'Restaurar um backup desvincula a sincronização para preservar a base do Drive. Ao receber uma base, os dados deste dispositivo serão substituídos com proteção local.'),
                      if (state?.lastSync != null)
                        Text(
                            'Última sincronização: ${backupDate(state!.lastSync!)}'),
                      if (linked)
                        Text(
                            'Alterações pendentes: ${state!.pending}${state.uploads > 0 ? ' · envio em preparação' : ''}'),
                      if (manager.message != null) Text(manager.message!),
                      if (manager.error != null)
                        Text(manager.error!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)),
                      if (manager.busy) const LinearProgressIndicator(),
                      if (!linked && manager.primaryAllowed)
                        TextButton.icon(
                            onPressed: ready
                                ? () async {
                                    if (await _confirm(
                                        context,
                                        'Usar os dados deste Android?',
                                        'Esta será a base inicial compartilhada. O Windows poderá recebê-la depois de guardar uma cópia dos seus dados atuais.')) {
                                      await manager.createBase();
                                    }
                                  }
                                : null,
                            icon: const Icon(Icons.cloud_upload_outlined),
                            label: const Text('Publicar base deste Android')),
                      if (!linked)
                        TextButton.icon(
                            onPressed: ready ? manager.listBases : null,
                            icon: const Icon(Icons.cloud_download_outlined),
                            label: const Text('Buscar bases no Drive')),
                      if (!linked)
                        for (final base in manager.bases)
                          ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Base publicada pelo Android'),
                              subtitle: Text(backupDate(base.copy.createdAt)),
                              trailing: TextButton(
                                  onPressed: ready
                                      ? () async {
                                          if (await _confirm(
                                              context,
                                              'Receber esta base?',
                                              'Os dados atuais serão substituídos pela base do Drive e suas alterações. Uma cópia Antes de restaurar será salva neste dispositivo.')) {
                                            await manager.join(base);
                                          }
                                        }
                                      : null,
                                  child: const Text('Receber'))),
                      if (linked)
                        TextButton.icon(
                            onPressed: ready ? manager.synchronize : null,
                            icon: const Icon(Icons.sync),
                            label: const Text('Sincronizar agora')),
                      if (linked)
                        TextButton(
                            onPressed: ready ? () => _history(context) : null,
                            child: const Text('Ver versões anteriores')),
                    ])));
      });
}
