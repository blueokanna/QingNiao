import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../messaging/message_repository.dart';
import '../src/rust/api/engine.dart';

/// 同步失败时携带可读信息与 HTTP 状态，UI 直接展示。
class SyncException implements Exception {
  SyncException(this.message, {this.status});

  final String message;
  final int? status;

  @override
  String toString() => message;
}

/// 同步状态的本地快照。只保存路由与游标，不保存任何明文。
class SyncState {
  String serverUrl = '';
  String token = '';
  String spaceId = '';
  String deviceId = '';
  String pairingCode = '';
  bool enabled = false;
  int cursor = 0;
  int lastPush = 0;
  int lastSync = 0;
  List<String> seen = const [];

  bool get registered => token.isNotEmpty && spaceId.isNotEmpty && deviceId.isNotEmpty;

  Map<String, dynamic> toJson() => {
    'serverUrl': serverUrl,
    'token': token,
    'spaceId': spaceId,
    'deviceId': deviceId,
    'pairingCode': pairingCode,
    'enabled': enabled,
    'cursor': cursor,
    'lastPush': lastPush,
    'lastSync': lastSync,
    'seen': seen,
  };

  static SyncState fromJson(Map<String, dynamic> json) => SyncState()
    ..serverUrl = '${json['serverUrl'] ?? ''}'
    ..token = '${json['token'] ?? ''}'
    ..spaceId = '${json['spaceId'] ?? ''}'
    ..deviceId = '${json['deviceId'] ?? ''}'
    ..pairingCode = '${json['pairingCode'] ?? ''}'
    ..enabled = json['enabled'] == true
    ..cursor = (json['cursor'] as num?)?.toInt() ?? 0
    ..lastPush = (json['lastPush'] as num?)?.toInt() ?? 0
    ..lastSync = (json['lastSync'] as num?)?.toInt() ?? 0
    ..seen = (json['seen'] as List? ?? const []).whereType<String>().toList(growable: false);
}

class SyncResult {
  const SyncResult({required this.pushed, required this.pulled, required this.cursor});

  final int pushed;
  final int pulled;
  final int cursor;

  String get message => '已同步 · 发出 $pushed 条 · 接收 $pulled 条';
}

/// 端到端加密同步客户端。
///
/// 密码学由 Rust 完成（X25519 + HKDF + AES-256-GCM）；这里只负责
/// HTTP 传输、游标、去重与把解出的消息写回系统短信库。
class SyncEngine {
  SyncEngine(this.repository);

  final MessageRepository repository;
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 12)
    ..idleTimeout = const Duration(seconds: 20);

  SyncState? _cached;
  DeviceIdentity? _identity;

  Future<DeviceIdentity> identity() async {
    if (_identity != null) return _identity!;
    final ready = await repository.initEngine();
    if (!ready) throw SyncException('本地引擎尚未就绪，请稍后再试');
    final value = await syncInit();
    if (value == null) throw SyncException('无法生成设备密钥');
    _identity = value;
    return value;
  }

  Future<SyncState> state() async {
    if (_cached != null) return _cached!;
    try {
      final raw = await repository.syncStateRaw();
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          _cached = SyncState.fromJson(decoded);
          return _cached!;
        }
      }
    } catch (_) {
      // 状态损坏时从头开始，避免阻塞同步入口。
    }
    _cached = SyncState();
    return _cached!;
  }

  Future<void> _save(SyncState value) async {
    _cached = value;
    await repository.syncStateSet(jsonEncode(value.toJson()));
  }

  Future<Map<String, dynamic>> status({bool refresh = true}) async {
    final value = await state();
    DeviceIdentity? identityValue;
    try {
      identityValue = await identity();
    } catch (_) {
      identityValue = null;
    }
    var devices = <Map<String, dynamic>>[];
    String? error;
    if (refresh && value.registered && value.serverUrl.isNotEmpty) {
      try {
        devices = await _peers(value);
      } catch (failure) {
        error = '$failure';
      }
    }
    return {
      'enabled': value.enabled,
      'serverUrl': value.serverUrl,
      'deviceName': _deviceName(value),
      'deviceId': value.deviceId,
      'fingerprint': identityValue?.fingerprint ?? '',
      'pairingCode': value.pairingCode,
      'lastSync': value.lastSync,
      'cursor': value.cursor,
      'pending': 0,
      'devices': devices,
      'error': error,
    };
  }

  String _deviceName(SyncState value) {
    final id = value.deviceId.isEmpty ? '未注册' : value.deviceId.substring(0, 6);
    try {
      final host = Platform.localHostname;
      if (host.isNotEmpty && host != 'localhost') return host;
    } catch (_) {}
    return '青鸟 · $id';
  }

  Future<void> configure({required String serverUrl, required bool enabled}) async {
    final value = await state();
    final normalized = _normalizeServer(serverUrl);
    if (enabled && normalized.isEmpty) {
      throw SyncException('请先填写同步服务器地址');
    }
    value.serverUrl = normalized;
    value.enabled = enabled;
    if (enabled && normalized.isNotEmpty) {
      if (!value.registered) {
        await _register(value);
      } else {
        // 验证令牌；服务器重置后旧令牌会失效，自动重建空间。
        try {
          await _peers(value);
        } catch (failure) {
          if (failure is SyncException && failure.status == 401) {
            value
              ..token = ''
              ..spaceId = ''
              ..deviceId = ''
              ..cursor = 0
              ..lastPush = 0
              ..seen = const [];
            await _register(value);
          } else {
            rethrow;
          }
        }
      }
    }
    await _save(value);
  }

  Future<void> _register(SyncState value) async {
    final id = await identity();
    final response = await _request(
      'POST',
      '/v1/spaces',
      value,
      body: {'name': _deviceName(value), 'publicKey': id.publicKey},
      auth: false,
    );
    value
      ..spaceId = '${response['spaceId'] ?? ''}'
      ..deviceId = '${response['deviceId'] ?? ''}'
      ..token = '${response['token'] ?? ''}'
      ..pairingCode = '${response['pairingCode'] ?? ''}'
      ..cursor = 0
      ..lastPush = 0
      ..seen = const [];
    if (!value.registered) throw SyncException('服务器未返回有效的设备令牌');
  }

  Future<String> rotatePairingCode() async {
    final value = await state();
    if (!value.registered) throw SyncException('请先启用同步');
    final response = await _request('POST', '/v1/pairing-code', value, body: const {});
    value.pairingCode = '${response['pairingCode'] ?? ''}';
    await _save(value);
    return value.pairingCode;
  }

  Future<void> join(String pairingCode) async {
    final value = await state();
    if (value.serverUrl.isEmpty) throw SyncException('请先填写同步服务器地址');
    final id = await identity();
    final response = await _request(
      'POST',
      '/v1/spaces/join',
      value,
      body: {
        'pairingCode': pairingCode.trim(),
        'name': _deviceName(value),
        'publicKey': id.publicKey,
      },
      auth: false,
    );
    value
      ..spaceId = '${response['spaceId'] ?? ''}'
      ..deviceId = '${response['deviceId'] ?? ''}'
      ..token = '${response['token'] ?? ''}'
      ..pairingCode = ''
      ..enabled = true
      ..cursor = 0
      ..lastPush = 0
      ..seen = const [];
    if (!value.registered) throw SyncException('配对失败：服务器未返回令牌');
    await _save(value);
  }

  Future<List<Map<String, dynamic>>> _peers(SyncState value) async {
    final response = await _request('GET', '/v1/space', value);
    final devices = (response['devices'] as List? ?? const []).whereType<Map>();
    final result = <Map<String, dynamic>>[];
    for (final device in devices) {
      final id = '${device['id'] ?? ''}';
      final publicKey = '${device['publicKey'] ?? ''}';
      String fingerprint = '';
      try {
        if (publicKey.isNotEmpty) {
          fingerprint = await syncFingerprint(publicKeyBase64: publicKey);
        }
      } catch (_) {}
      result.add({
        'id': id,
        'name': '${device['name'] ?? '设备'}',
        'publicKey': publicKey,
        'fingerprint': fingerprint,
        'thisDevice': id == value.deviceId,
        'lastSeen': (device['lastSeen'] as num?)?.toInt() ?? 0,
      });
    }
    return result;
  }

  Future<SyncResult> syncNow() async {
    final value = await state();
    if (!value.enabled) throw SyncException('同步未启用');
    if (!value.registered) {
      await _register(value);
      await _save(value);
    }
    final peers = (await _peers(value)).where((peer) => peer['thisDevice'] != true).toList();
    var pushed = 0;
    var pulled = 0;

    if (peers.isNotEmpty) {
      final since = value.lastPush == 0
          ? DateTime.now().subtract(const Duration(days: 7)).millisecondsSinceEpoch
          : value.lastPush;
      final local = await repository.remoteMessagesSince(since);
      var newest = since;
      for (final message in local) {
        final date = (message['date'] as num?)?.toInt() ?? 0;
        if (date > newest) newest = date;
        final body = '${message['body'] ?? ''}';
        if (body.isEmpty) continue;
        final messageId = '${value.deviceId}:${message['id']}';
        final payload = jsonEncode({
          'v': 1,
          'id': messageId,
          'address': '${message['address'] ?? ''}',
          'body': body,
          'date': date,
          'type': (message['type'] as num?)?.toInt() ?? 1,
          'sub': (message['subscriptionId'] as num?)?.toInt() ?? -1,
        });
        if (utf8.encode(payload).length > 2600) continue;
        for (final peer in peers) {
          final publicKey = '${peer['publicKey'] ?? ''}';
          if (publicKey.isEmpty) continue;
          final envelope = await syncEncrypt(
            targetPublicKeyBase64: publicKey,
            plaintext: payload,
          );
          if (envelope == null) continue;
          await _request(
            'POST',
            '/v1/envelopes',
            value,
            body: {
              'to': peer['id'],
              'ephemeralPublicKey': envelope.ephemeralPublicKey,
              'nonce': envelope.nonce,
              'ciphertext': envelope.ciphertext,
              'messageId': messageId,
            },
          );
          pushed += 1;
        }
      }
      value.lastPush = newest;
    }

    final response = await _request('GET', '/v1/envelopes?after=${value.cursor}&wait=0', value);
    final envelopes = (response['envelopes'] as List? ?? const []).whereType<Map>();
    final seen = [...value.seen];
    final seenSet = seen.toSet();
    var cursor = value.cursor;
    for (final envelope in envelopes) {
      final id = (envelope['id'] as num?)?.toInt() ?? 0;
      if (id > cursor) cursor = id;
      final from = '${envelope['from'] ?? ''}';
      if (from == value.deviceId) continue;
      final plaintext = await syncDecrypt(
        ephemeralPublicKeyBase64: '${envelope['ephemeralPublicKey'] ?? ''}',
        nonceBase64: '${envelope['nonce'] ?? ''}',
        ciphertextBase64: '${envelope['ciphertext'] ?? ''}',
      );
      if (plaintext == null) continue;
      Map<String, dynamic> payload;
      try {
        final decoded = jsonDecode(plaintext);
        if (decoded is! Map<String, dynamic>) continue;
        payload = decoded;
      } catch (_) {
        continue;
      }
      final messageId = '${payload['id'] ?? ''}';
      if (messageId.isEmpty || seenSet.contains(messageId)) continue;
      final address = '${payload['address'] ?? ''}';
      final body = '${payload['body'] ?? ''}';
      final date = (payload['date'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch;
      if (address.isEmpty || body.isEmpty) continue;
      await repository.insertRemoteMessage(
        address: address,
        body: body,
        date: date,
        subscriptionId: (payload['sub'] as num?)?.toInt() ?? -1,
      );
      seenSet.add(messageId);
      seen.add(messageId);
      pulled += 1;
    }
    value
      ..cursor = cursor
      ..seen = seen.length > 2000 ? seen.sublist(seen.length - 2000) : seen
      ..lastSync = DateTime.now().millisecondsSinceEpoch;
    await _save(value);
    return SyncResult(pushed: pushed, pulled: pulled, cursor: cursor);
  }

  Future<void> reset() async {
    try {
      await syncReset();
    } catch (_) {}
    _identity = null;
    await _save(SyncState());
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path,
    SyncState value, {
    Map<String, dynamic>? body,
    bool auth = true,
  }) async {
    final base = value.serverUrl;
    if (base.isEmpty) throw SyncException('未配置同步服务器');
    final uri = Uri.tryParse('$base$path');
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw SyncException('服务器地址无效');
    }
    try {
      final request = await _client.openUrl(method, uri).timeout(const Duration(seconds: 15));
      request.headers.contentType = ContentType('application', 'json', charset: 'utf-8');
      if (auth) {
        if (value.token.isEmpty) throw SyncException('设备未注册', status: 401);
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${value.token}');
      }
      if (body != null) request.write(jsonEncode(body));
      final response = await request.close().timeout(const Duration(seconds: 20));
      final text = await utf8.decoder.bind(response).join();
      if (response.statusCode >= 400) {
        String message = '同步服务器返回 ${response.statusCode}';
        try {
          final decoded = jsonDecode(text);
          if (decoded is Map && decoded['error'] is String) {
            message = decoded['error'] as String;
          }
        } catch (_) {}
        throw SyncException(message, status: response.statusCode);
      }
      if (text.isEmpty) return const {};
      final decoded = jsonDecode(text);
      return decoded is Map<String, dynamic> ? decoded : const {};
    } on SyncException {
      rethrow;
    } on SocketException catch (error) {
      throw SyncException('无法连接同步服务器：${error.message}');
    } on TimeoutException {
      throw SyncException('同步请求超时');
    } catch (error) {
      throw SyncException('同步失败：$error');
    }
  }

  String _normalizeServer(String raw) {
    var value = raw.trim();
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    if (value.isEmpty) return '';
    final uri = Uri.tryParse(value);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https') || uri.host.isEmpty) {
      throw SyncException('服务器地址必须以 http:// 或 https:// 开头');
    }
    return value;
  }

  void dispose() => _client.close(force: true);
}
