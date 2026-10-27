/// HTTP client for the Comb sync server (docs/openapi.json).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  ApiException(this.status, this.message);
  final int status;
  final String message;

  bool get isAuth => status == 401;
  bool get isOffline => status == 0;

  @override
  String toString() => message;
}

class DeviceCredentials {
  DeviceCredentials({required this.accountId, required this.deviceId, required this.token});
  factory DeviceCredentials.fromJson(Map<String, dynamic> j) =>
      DeviceCredentials(accountId: j['account_id'] as String, deviceId: j['device_id'] as String, token: j['token'] as String);
  final String accountId;
  final String deviceId;
  final String token;
  Map<String, dynamic> toJson() => {'account_id': accountId, 'device_id': deviceId, 'token': token};
}

class RemoteDevice {
  RemoteDevice({required this.id, required this.name, required this.lastSeen, required this.revoked, required this.thisDevice});
  final String id;
  final String name;
  final DateTime? lastSeen;
  final bool revoked;
  final bool thisDevice;
}

class ChangeIn {
  ChangeIn({required this.changeId, required this.recordId, required this.baseVersion, required this.blob, this.deleted = false});
  final String changeId;
  final String recordId;
  final int baseVersion;
  final Uint8List blob;
  final bool deleted;
  Map<String, dynamic> toJson() => {
    'change_id': changeId,
    'record_id': recordId,
    'base_version': baseVersion,
    'blob': base64.encode(blob),
    'deleted': deleted,
  };
}

class StoredRecord {
  StoredRecord({
    required this.recordId,
    required this.version,
    required this.seq,
    required this.blob,
    required this.deleted,
    required this.deviceId,
  });
  factory StoredRecord.fromJson(Map<String, dynamic> j) => StoredRecord(
    recordId: j['record_id'] as String,
    version: j['version'] as int,
    seq: j['seq'] as int,
    blob: base64.decode(j['blob'] as String),
    deleted: j['deleted'] as bool,
    deviceId: j['device_id'] as String,
  );
  final String recordId;
  final int version;
  final int seq;
  final Uint8List blob;
  final bool deleted;
  final String deviceId;
}

class ChangeResult {
  ChangeResult({required this.changeId, required this.recordId, required this.status, this.version, this.seq, this.current});
  factory ChangeResult.fromJson(Map<String, dynamic> j) => ChangeResult(
    changeId: j['change_id'] as String,
    recordId: j['record_id'] as String,
    status: j['status'] as String,
    version: j['version'] as int?,
    seq: j['seq'] as int?,
    current: j['current'] == null ? null : StoredRecord.fromJson(j['current'] as Map<String, dynamic>),
  );
  final String changeId;
  final String recordId;
  final String status;
  final int? version;
  final int? seq;
  final StoredRecord? current;
  bool get ok => status == 'ok' || status == 'duplicate';
}

class ChangesPage {
  ChangesPage(this.changes, this.nextSince, this.hasMore);
  final List<StoredRecord> changes;
  final int nextSince;
  final bool hasMore;
}

class CombApi {
  CombApi(String baseUrl, {http.Client? client, this.token})
    : baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
      _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;
  String? token;

  Uri _u(String path, [Map<String, String>? query]) => Uri.parse('$baseUrl$path').replace(queryParameters: query);

  Map<String, String> get _auth => {if (token != null) 'Authorization': 'Bearer $token'};

  Future<dynamic> _send(Future<http.Response> Function() call) async {
    http.Response resp;
    try {
      resp = await call().timeout(const Duration(seconds: 30));
    } catch (e) {
      throw ApiException(0, 'Could not reach the server. Changes are saved and will sync later.');
    }
    if (resp.statusCode >= 400) {
      var message = 'Server error ${resp.statusCode}.';
      try {
        final body = jsonDecode(utf8.decode(resp.bodyBytes));
        final detail = body is Map ? body['detail'] : null;
        if (detail is String) message = detail;
      } catch (_) {}
      throw ApiException(resp.statusCode, message);
    }
    if (resp.bodyBytes.isEmpty) return null;
    final type = resp.headers['content-type'] ?? '';
    if (type.contains('application/json')) return jsonDecode(utf8.decode(resp.bodyBytes));
    return resp.bodyBytes;
  }

  Map<String, String> get _json => {'Content-Type': 'application/json', ..._auth};

  Future<Map<String, dynamic>> health() async => (await _send(() => _client.get(_u('/v1/health')))) as Map<String, dynamic>;

  Future<DeviceCredentials> setup(String setupCode, String deviceName) async {
    final j = await _send(
      () => _client.post(_u('/v1/setup'), headers: _json, body: jsonEncode({'setup_code': setupCode, 'device_name': deviceName})),
    );
    return DeviceCredentials.fromJson(j as Map<String, dynamic>);
  }

  Future<({String code, DateTime expires})> startPairing() async {
    final j = await _send(() => _client.post(_u('/v1/pairing'), headers: _json)) as Map<String, dynamic>;
    return (code: j['code'] as String, expires: DateTime.fromMillisecondsSinceEpoch(((j['expires_at'] as num) * 1000).round()));
  }

  Future<DeviceCredentials> claimPairing(String code, String deviceName) async {
    final j = await _send(
      () => _client.post(_u('/v1/pairing/claim'), headers: _json, body: jsonEncode({'code': code, 'device_name': deviceName})),
    );
    return DeviceCredentials.fromJson(j as Map<String, dynamic>);
  }

  Future<List<RemoteDevice>> devices() async {
    final list = await _send(() => _client.get(_u('/v1/devices'), headers: _auth)) as List<dynamic>;
    return list.map((e) {
      final m = e as Map<String, dynamic>;
      final seen = m['last_seen_at'] as num?;
      return RemoteDevice(
        id: m['id'] as String,
        name: m['name'] as String,
        lastSeen: seen == null ? null : DateTime.fromMillisecondsSinceEpoch((seen * 1000).round()),
        revoked: m['revoked'] as bool,
        thisDevice: m['this_device'] as bool,
      );
    }).toList();
  }

  Future<void> revokeDevice(String id) => _send(() => _client.delete(_u('/v1/devices/$id'), headers: _auth));

  Future<List<ChangeResult>> push(List<ChangeIn> changes) async {
    final j = await _send(
      () => _client.post(_u('/v1/records'), headers: _json, body: jsonEncode({'changes': changes.map((c) => c.toJson()).toList()})),
    ) as Map<String, dynamic>;
    return (j['results'] as List).map((e) => ChangeResult.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<ChangesPage> pull(int since, {int limit = 500}) async {
    final j =
        await _send(() => _client.get(_u('/v1/changes', {'since': '$since', 'limit': '$limit'}), headers: _auth)) as Map<String, dynamic>;
    return ChangesPage(
      (j['changes'] as List).map((e) => StoredRecord.fromJson(e as Map<String, dynamic>)).toList(),
      j['next_since'] as int,
      j['has_more'] as bool,
    );
  }

  Future<void> putBlob(String id, Uint8List data) =>
      _send(() => _client.put(_u('/v1/blobs/$id'), headers: {..._auth, 'Content-Type': 'application/octet-stream'}, body: data));

  Future<Uint8List> getBlob(String id) async => (await _send(() => _client.get(_u('/v1/blobs/$id'), headers: _auth))) as Uint8List;
}

/// The QR link one device shows so another can join. The key travels in the
/// QR (screen to camera) and is never sent to the server.
String pairingLink(String serverUrl, String code, String recoveryKey) {
  final q = {'server': serverUrl, 'code': code, 'key': recoveryKey};
  return Uri(scheme: 'comb', host: 'pair', queryParameters: q).toString();
}

({String server, String code, String recoveryKey}) parsePairingLink(String link) {
  final uri = Uri.parse(link.trim());
  if (uri.scheme != 'comb' || uri.host != 'pair') throw const FormatException('Not a Comb pairing link.');
  final q = uri.queryParameters;
  final server = q['server'], code = q['code'], key = q['key'];
  if (server == null || code == null || key == null) throw const FormatException('The pairing link is incomplete.');
  return (server: server, code: code, recoveryKey: key);
}
