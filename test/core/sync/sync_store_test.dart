import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:finapp/core/database/app_database.dart';
import 'package:finapp/core/database/backup_service.dart';
import 'package:finapp/core/database/financial_data.dart';
import 'package:finapp/core/database/local_backup_store.dart';
import 'package:finapp/core/sync/sync_packet.dart';
import 'package:finapp/core/sync/sync_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main(){
  late AppDatabase a,b;
  late SyncStore sa,sb;
  late Directory dir;
  late SyncPacket genesis;
  Future<void> account(AppDatabase db,String id,String name)=>db.customStatement("INSERT INTO accounts(id,name,type,currency_code,initial_balance_minor,created_at,updated_at) VALUES (?,?,'cash','BRL',10000,1,1)",[id,name]);
  Future<SyncPacket> outgoing(SyncStore store)async{
    await store.prepareUpload();
    final p=(await store.uploads()).single;
    return SyncPacket.decode(p.encode(),await store.columns());
  }
  Future<void> apply(SyncStore from,SyncStore to)async{
    final p=await outgoing(from);
    await to.apply([p]);
    await from.ack(p);
  }
  setUp(()async{
    dir=await Directory.systemTemp.createTemp('somia-sync-');
    a=AppDatabase(NativeDatabase.memory());b=AppDatabase(NativeDatabase.memory());
    sa=SyncStore(a,LocalBackupStore(Directory('${dir.path}/android')),device:'android-device-0001');
    sb=SyncStore(b,LocalBackupStore(Directory('${dir.path}/windows')),device:'windows-device-0001');
    await account(a,'a','Android');await account(a,'b','Reserva');
    await account(b,'old','Somente Windows');
    genesis=await sa.createBase('same@example.com');
    await sa.ack(genesis);
    await sb.apply([SyncPacket.decode(genesis.encode(),await sb.columns())],joinEmail:'same@example.com');
  });
  tearDown(()async{await a.close();await b.close();await dir.delete(recursive:true);});
  test('vínculo inicial protege Windows, preserva identidade e não reenvia importação',()async{
    expect(await readFinancial(a),await readFinancial(b));
    expect((await sb.state()).device,'windows-device-0001');
    expect((await sb.state()).base,genesis.base);
    expect((await sb.state()).pending,0);
    final previous=AppDatabase(NativeDatabase((await sb.backups.list()).single.file));
    try{
      expect((await previous.customSelect('SELECT name FROM accounts').getSingle()).read<String>('name'),'Somente Windows');
    }finally{await previous.close();}
  });
  test('alterações offline independentes nos dois sentidos e retry idempotente',()async{
    await account(a,'aa','Novo Android');await account(b,'bb','Novo Windows');
    final packetA=await outgoing(sa),packetB=await outgoing(sb);
    await sb.apply([packetA,packetA]);await sa.apply([packetB]);
    expect(await readFinancial(a),await readFinancial(b));
    final count=(await b.customSelect('SELECT count(*) n FROM accounts').getSingle()).read<int>('n');
    expect(await sb.apply([packetA]),isFalse);
    expect((await b.customSelect('SELECT count(*) n FROM accounts').getSingle()).read<int>('n'),count);
    await sa.ack(packetA);await sb.ack(packetB);
    expect((await sa.state()).pending,0);expect((await sb.state()).pending,0);
  });
  test('conflito converge pela versão mais recente em qualquer ordem e permite recuperação',()async{
    await a.customStatement("UPDATE accounts SET name='Edição Android' WHERE id='a'");
    final pa=await outgoing(sa);
    await b.customStatement('UPDATE sync_state SET clock=? WHERE id=1',[pa.entries.single.clock+100]);
    await b.customStatement("UPDATE accounts SET name='Edição Windows' WHERE id='a'");
    final pb=await outgoing(sb);
    await sa.apply([pb]);await sb.apply([pa]);
    expect(await readFinancial(a),await readFinancial(b));
    expect((await a.customSelect("SELECT name FROM accounts WHERE id='a'").getSingle()).read<String>('name'),'Edição Windows');
    final old=(await sa.history()).firstWhere((e)=>e.data?['name']=='Edição Android');
    await sa.recover(old);await sa.ack(pa);await sb.ack(pb);
    await apply(sa,sb);
    expect(await readFinancial(a),await readFinancial(b));
    expect((await b.customSelect("SELECT name FROM accounts WHERE id='a'").getSingle()).read<String>('name'),'Edição Android');
  });
  test('remoção física vence reenvio antigo e empate tem desempate determinístico',()async{
    await account(a,'extra','Temporária');await apply(sa,sb);
    await a.customStatement("UPDATE accounts SET name='Antiga' WHERE id='extra'");
    final old=await outgoing(sa);await sa.ack(old);
    await a.customStatement("DELETE FROM accounts WHERE id='extra'");
    final removed=await outgoing(sa);
    await sb.apply([removed,old]);
    expect(await b.customSelect("SELECT * FROM accounts WHERE id='extra'").get(),isEmpty);
    await sb.apply([old]);
    expect(await b.customSelect("SELECT * FROM accounts WHERE id='extra'").get(),isEmpty);
    final data=(await readFinancial(a))['accounts']!['a']!;
    final now=DateTime.now().millisecondsSinceEpoch;
    final low=SyncPacket('packet-identity-low',genesis.base,'android-device-0001','changes',[
      SyncEntry('accounts','a',now,'android-device-0001',false,{...data,'name':'A'})]);
    final high=SyncPacket('packet-identity-high',genesis.base,'windows-device-0001','changes',[
      SyncEntry('accounts','a',now,'windows-device-0001',false,{...data,'name':'B'})]);
    await sa.apply([low,high]);await sb.apply([high,low]);
    expect((await a.customSelect("SELECT name FROM accounts WHERE id='a'").getSingle()).read<String>('name'),'B');
    expect((await b.customSelect("SELECT name FROM accounts WHERE id='a'").getSingle()).read<String>('name'),'B');
  });
  test('operação composta captura transação inteira e vínculos inválidos fazem rollback',()async{
    await a.transaction(()async{
      await a.customStatement("INSERT INTO transfers(id,source_account_id,destination_account_id,amount_minor,created_at,updated_at) VALUES ('t','a','b',500,1,1)");
      await account(a,'new','Conta vinculada');
      await a.customStatement("INSERT INTO transactions(id,description,type,planned_amount_minor,competence_at,account_id,created_at,updated_at) VALUES ('tx','Compra','expense',100,1,'new',1,1)");
    });
    final p=await outgoing(sa);
    expect(p.entries,hasLength(3));
    await sb.apply([p]);
    expect(await readFinancial(a),await readFinancial(b));
    final before=await readFinancial(b),seen=await sb.applied();
    final data=(await readFinancial(a))['transactions']!['tx']!;
    final invalid=SyncPacket('invalid-packet-0001',genesis.base,'android-device-0001','changes',[
      SyncEntry('transactions','tx',p.entries.map((e)=>e.clock).reduce((a,b)=>a>b?a:b)+100,'android-device-0001',false,{...data,'account_id':'missing'})]);
    await expectLater(sb.apply([invalid]),throwsFormatException);
    expect(await readFinancial(b),before);expect(await sb.applied(),seen);
    expect((await sb.state()).pending,0);
  });
  test('restaurar backup desvincula, preserva dispositivo e não publica exclusões',()async{
    final bytes=await BackupService.export(a,dir);
    await account(a,'later','Posterior');
    await BackupService.restoreOpen(a,sa.backups,bytes);
    expect((await sa.state()).base,isNull);expect((await sa.state()).pending,0);
    expect(await sa.device(),'android-device-0001');
    await account(a,'standalone','Independente');
    expect((await sa.state()).pending,0);
    expect((await sb.state()).base,genesis.base);
  });
  test('fila imutável persiste e ack não remove nova alteração',()async{
    await a.customStatement("UPDATE accounts SET name='Primeira' WHERE id='a'");
    final p=await outgoing(sa);
    await a.customStatement("UPDATE accounts SET name='Segunda' WHERE id='a'");
    expect((await sa.uploads()).single.digest,p.digest);
    await sa.ack(p);
    expect((await sa.state()).pending,1);
    expect((await outgoing(sa)).entries.single.data?['name'],'Segunda');
  });
  test('base diferente, relógio futuro e pacote corrompido preservam dados',()async{
    final before=await readFinancial(b);
    final entry=SyncEntry('accounts','a',DateTime.now().millisecondsSinceEpoch+600000,'android-device-0001',false,before['accounts']!['a']);
    await expectLater(sb.apply([SyncPacket('future-packet-0001',genesis.base,'android-device-0001','changes',[entry])]),throwsFormatException);
    await expectLater(sb.apply([SyncPacket('other-packet-00001','other-base-identity','android-device-0001','changes',[])]),throwsFormatException);
    expect(()=>SyncPacket.decode(Uint8List.fromList(utf8.encode('{}')),{}),throwsFormatException);
    expect(await readFinancial(b),before);
  });
}
