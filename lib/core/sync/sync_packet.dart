import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import '../database/app_database.dart';

const syncProtocol = 1;
const maxSyncBytes = 64 * 1024 * 1024;
final _identity = RegExp(r'^[a-zA-Z0-9-]{16,80}$');

class SyncEntry {
  const SyncEntry(
      this.table, this.id, this.clock, this.device, this.deleted, this.data);
  final String table, id, device;
  final int clock;
  final bool deleted;
  final Map<String, Object?>? data;
  String get key => '$table/$id';
  Map<String, Object?> toJson() => {
        'table': table,
        'id': id,
        'clock': clock,
        'device': device,
        'deleted': deleted,
        'data': data,
      };
  int compare(SyncEntry other) {
    final order = clock.compareTo(other.clock);
    return order != 0 ? order : device.compareTo(other.device);
  }

  bool sameData(SyncEntry other) =>
      deleted == other.deleted && jsonEncode(data) == jsonEncode(other.data);
  static SyncEntry parse(
      Object? raw, Map<String, Map<String, String>> columns) {
    if (raw is! Map ||
        raw['table'] is! String ||
        raw['id'] is! String ||
        raw['clock'] is! int ||
        (raw['clock'] as int) < 0 ||
        raw['device'] is! String ||
        !_identity.hasMatch(raw['device'] as String) ||
        raw['deleted'] is! bool) {
      throw const FormatException('Alteração de sincronização inválida.');
    }
    final table = raw['table'] as String;
    final id = raw['id'] as String;
    final expected = columns[table];
    if (expected == null || id.isEmpty || id.length > 256) {
      throw const FormatException('Registro de sincronização incompatível.');
    }
    Map<String, Object?>? data;
    if (raw['deleted'] == true) {
      if (raw['data'] != null) {
        throw const FormatException('Exclusão inválida.');
      }
    } else {
      final value = raw['data'];
      if (value is! Map ||
          value.length != expected.length ||
          value['id'] != id) {
        throw const FormatException('Registro de sincronização incompleto.');
      }
      data = {};
      for (final column in expected.entries) {
        final v = value[column.key];
        if (!value.containsKey(column.key) ||
            (v != null &&
                (column.value == 'INTEGER' ? v is! int : v is! String))) {
          throw const FormatException('Tipo de dado incompatível.');
        }
        data[column.key] = v;
      }
    }
    return SyncEntry(table, id, raw['clock'] as int, raw['device'] as String,
        raw['deleted'] as bool, data);
  }
}

class SyncPacket {
  const SyncPacket(
    this.id,
    this.base,
    this.device,
    this.kind,
    this.entries, {
    this.sourceSchema = AppDatabase.currentSchemaVersion,
  });
  final int sourceSchema;
  final String id, base, device, kind;
  final List<SyncEntry> entries;
  Uint8List encode() => Uint8List.fromList(utf8.encode(jsonEncode({
        'protocol': syncProtocol,
        'schema': sourceSchema,
        'id': id,
        'base': base,
        'device': device,
        'kind': kind,
        'entries': entries.map((e) {
          final value = e.toJson();
          if (sourceSchema < 16 &&
              e.table == 'credit_cards' &&
              e.data != null) {
            value['data'] = Map<String, Object?>.of(e.data!)
              ..remove('color_argb');
          }
          if (sourceSchema == 11 && e.data != null) {
            value['data'] = Map<String, Object?>.from(value['data'] as Map)
              ..remove('allocations_json');
          }
          if (sourceSchema < 20 &&
              ['transactions', 'card_entries'].contains(e.table) &&
              e.data != null) {
            value['data'] = Map<String, Object?>.from(value['data'] as Map)
              ..remove('tags_json');
          }
          if (sourceSchema < 21 &&
              ['transactions', 'card_entries'].contains(e.table) &&
              e.data != null) {
            value['data'] = Map<String, Object?>.from(value['data'] as Map)
              ..remove('establishment');
          }
          return value;
        }).toList(),
      })));
  String get digest => sha256.convert(encode()).toString();
  static SyncPacket decode(
      Uint8List bytes, Map<String, Map<String, String>> columns) {
    if (bytes.isEmpty || bytes.length > maxSyncBytes) {
      throw const FormatException('A sincronização deve ter até 64 MB.');
    }
    final v = jsonDecode(utf8.decode(bytes));
    if (v is! Map ||
        v['protocol'] != syncProtocol ||
        (v['schema'] != AppDatabase.currentSchemaVersion &&
            v['schema'] != 11 &&
            v['schema'] != 12 &&
            v['schema'] != 13 &&
            v['schema'] != 14 &&
            v['schema'] != 15 &&
            v['schema'] != 16 &&
            v['schema'] != 17 &&
            v['schema'] != 18 &&
            v['schema'] != 19 &&
            v['schema'] != 20) ||
        !['genesis', 'changes'].contains(v['kind']) ||
        [
          'id',
          'base',
          'device'
        ].any((k) => v[k] is! String || !_identity.hasMatch(v[k] as String)) ||
        v['entries'] is! List ||
        (v['entries'] as List).length > 100000) {
      throw const FormatException(
          'Versão de sincronização incompatível. Atualize os dois dispositivos.');
    }
    if (v['schema'] < 19 &&
        (v['entries'] as List)
            .any((e) => e is Map && e['table'] == 'transaction_settlements')) {
      throw const FormatException(
          'Baixas parciais exigem a versão atual do aplicativo.');
    }
    if (v['schema'] < 18 &&
        (v['entries'] as List).any((e) =>
            e is Map &&
            ['budget_limits', 'planning_goals', 'goal_accounts']
                .contains(e['table']))) {
      throw const FormatException(
          'Planejamento em pacote histórico incompatível.');
    }
    if (v['schema'] < 17 &&
        (v['entries'] as List).any((e) =>
            e is Map &&
            ['people', 'reimbursements', 'reimbursement_receipts']
                .contains(e['table']))) {
      throw const FormatException(
          'Reembolso em pacote histórico incompatível.');
    }
    if (v['schema'] < 15 &&
        (v['entries'] as List).any((e) =>
            e is Map && ['debts', 'debt_payments'].contains(e['table']))) {
      throw const FormatException('Dívida em pacote histórico incompatível.');
    }
    if (v['schema'] < 14 &&
        (v['entries'] as List).any((e) =>
            e is Map && ['assets', 'asset_valuations'].contains(e['table']))) {
      throw const FormatException('Bem em pacote histórico incompatível.');
    }
    if (v['schema'] < 13 &&
        (v['entries'] as List)
            .any((e) => e is Map && e['table'] == 'investments')) {
      throw const FormatException(
          'Aplicação em pacote histórico incompatível.');
    }
    // Historical v11/v12 packets remain readable after both apps are upgraded.
    if (v['schema'] == 11) {
      for (final e in v['entries'] as List) {
        if (e is Map &&
            ['transactions', 'card_entries'].contains(e['table']) &&
            e['data'] is Map) {
          if ((e['data'] as Map).containsKey('allocations_json')) {
            throw const FormatException('Registro v11 incompatível.');
          }
          (e['data'] as Map)['allocations_json'] = '[]';
        }
      }
    }
    if (v['schema'] < 16) {
      for (final e in v['entries'] as List) {
        if (e is Map && e['table'] == 'credit_cards' && e['data'] is Map) {
          if ((e['data'] as Map).containsKey('color_argb')) {
            throw const FormatException(
                'Cor em pacote histórico incompatível.');
          }
          (e['data'] as Map)['color_argb'] = null;
        }
      }
    }
    if (v['schema'] < 20) {
      for (final e in v['entries'] as List) {
        if (e is Map &&
            ['transactions', 'card_entries'].contains(e['table']) &&
            e['data'] is Map) {
          if ((e['data'] as Map).containsKey('tags_json')) {
            throw const FormatException(
                'Tags em pacote histórico incompatível.');
          }
          (e['data'] as Map)['tags_json'] = '[]';
        }
      }
    }
    if (v['schema'] < 21) {
      for (final e in v['entries'] as List) {
        if (e is Map &&
            ['transactions', 'card_entries'].contains(e['table']) &&
            e['data'] is Map) {
          if ((e['data'] as Map).containsKey('establishment')) {
            throw const FormatException(
                'Estabelecimento em pacote histórico incompatível.');
          }
          (e['data'] as Map)['establishment'] = '';
        }
      }
    }
    final entries =
        (v['entries'] as List).map((e) => SyncEntry.parse(e, columns)).toList();
    if (entries.map((e) => e.key).toSet().length != entries.length ||
        entries.any((e) =>
            e.device != v['device'] ||
            (v['kind'] == 'changes' && e.clock == 0) ||
            (v['kind'] == 'genesis' && (e.clock != 0 || e.deleted)))) {
      throw const FormatException('Pacote de sincronização inválido.');
    }
    return SyncPacket(
      v['id'] as String,
      v['base'] as String,
      v['device'] as String,
      v['kind'] as String,
      entries,
      sourceSchema: v['schema'] as int,
    );
  }
}
