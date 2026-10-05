import 'dart:convert';
import 'dart:typed_data';
import 'package:uuid/uuid.dart';
import '../drive/drive_backup.dart';
import 'sync_packet.dart';

class SyncRemoteFile {
  const SyncRemoteFile(this.copy,this.packet,this.base,this.device,this.kind);
  final DriveCopy copy;
  final String packet,base,device,kind;
  static SyncRemoteFile parse(Map<String,dynamic> json) {
    final copy=DriveCopy.parse(json,marker:'somiaSync');
    final p=json['appProperties'] as Map;
    if(['packet','base','device'].any((k)=>p[k] is! String ||
        !RegExp(r'^[a-zA-Z0-9-]{16,80}$').hasMatch(p[k] as String)) ||
        !['genesis','changes'].contains(p['kind'])) {
      throw const DriveFailure('Arquivo de sincronização inválido.');
    }
    return SyncRemoteFile(copy,p['packet'] as String,p['base'] as String,p['device'] as String,p['kind'] as String);
  }
}
abstract class SyncCloud {
  DateTime? get serverTime;
  Future<List<SyncRemoteFile>> list(DriveSession session);
  Future<Uint8List> download(DriveSession session,SyncRemoteFile file);
  Future<void> upload(DriveSession session,SyncPacket packet);
}
class DriveSyncApi implements SyncCloud {
  DriveSyncApi(this.api);
  final DriveBackupApi api;
  @override
  DateTime? get serverTime=>api.serverTime;
  @override
  Future<List<SyncRemoteFile>> list(DriveSession session) async {
    final result=<SyncRemoteFile>[];
    final pages=<String>{};
    String? page;
    do {
      final value=jsonDecode(utf8.decode(await api.request(session,'GET','/drive/v3/files',{
        'spaces':'appDataFolder','q':"trashed = false and appProperties has { key='somiaSync' and value='1' }",
        'fields':'nextPageToken,files(id,name,createdTime,size,md5Checksum,appProperties,spaces,trashed)',
        'pageSize':'100',if(page!=null)'pageToken':page,
      })));
      if(value is! Map || value['files'] is! List) throw const DriveFailure('Lista de sincronização inválida.');
      for(final f in value['files'] as List) {
        if(f is! Map<String,dynamic>) throw const DriveFailure('Arquivo inválido.');
        result.add(SyncRemoteFile.parse(f));
      }
      final next=value['nextPageToken'];
      if(next!=null && next is! String) throw const DriveFailure('Página inválida.');
      page=next as String?;
      if(page!=null && (!pages.add(page) || pages.length>100)) throw const DriveFailure('A lista de sincronização excede o limite.');
    } while(page!=null);
    return result;
  }
  @override
  Future<Uint8List> download(DriveSession session,SyncRemoteFile file) => api.download(session,file.copy,marker:'somiaSync');
  @override
  Future<void> upload(DriveSession session,SyncPacket packet) async {
    final bytes=packet.encode();
    if(bytes.length>maxSyncBytes) throw const DriveFailure('A sincronização excede 64 MB.');
    final boundary='somia-sync-${const Uuid().v4()}';
    final meta=jsonEncode({
      'name':'somia-sync-${packet.id}.json','parents':['appDataFolder'],
      'appProperties':{'somiaSync':'1','packet':packet.id,'base':packet.base,
        'device':packet.device,'kind':packet.kind,'sha256':packet.digest},
    });
    final body=BytesBuilder(copy:false)
      ..add(utf8.encode('--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n$meta\r\n--$boundary\r\nContent-Type: application/json\r\n\r\n'))
      ..add(bytes)..add(utf8.encode('\r\n--$boundary--\r\n'));
    await api.request(session,'POST','/upload/drive/v3/files',{'uploadType':'multipart','fields':'id'},
      body:body.takeBytes(),contentType:'multipart/related; boundary=$boundary');
  }
}
