import 'package:qingniao/l10n/app_strings.dart';
import 'package:flutter/services.dart';

import '../src/rust/api/engine.dart';
import 'models.dart';

typedef MessageRecord = Map<String, dynamic>;

class MessageRepository {
  const MessageRepository();

  static const MethodChannel _channel = MethodChannel(
    'com.blue.qingniao/messages',
  );
  static const EventChannel _events = EventChannel('com.blue.qingniao/changes');

  static final Stream<String> _changes = _events
      .receiveBroadcastStream()
      .cast<String>();
  Stream<String> get changes => _changes;

  Future<T?> invoke<T>(String method, [MessageRecord? arguments]) =>
      _channel.invokeMethod<T>(method, arguments);

  Future<List<MessageRecord>> records(
    String method, [
    MessageRecord? arguments,
  ]) => _list(method, arguments);

  Future<bool> hasAccess() async {
    final state = await _map('access');
    return state['defaultApp'] == true &&
        state['readSms'] == true &&
        state['sendSms'] == true;
  }

  Future<Map<String, dynamic>> _map(
    String method, [
    Map<String, dynamic>? args,
  ]) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      method,
      args,
    );
    return result ?? const {};
  }

  Future<List<Map<String, dynamic>>> _list(
    String method, [
    Map<String, dynamic>? args,
  ]) async {
    final result = await _channel.invokeListMethod<dynamic>(method, args);
    return (result ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Future<T?> _invoke<T>(String method, [Map<String, dynamic>? args]) =>
      _channel.invokeMethod<T>(method, args);

  Future<AccessState> access() async =>
      AccessState.fromMap(await _map('access'));

  Future<void> requestAccess() => _channel.invokeMethod<void>('requestAccess');

  Future<void> openAppSettings() => _channel.invokeMethod<void>('appSettings');

  Future<void> openNotificationSettings() =>
      _channel.invokeMethod<void>('notificationSettings');

  Future<Map<String, dynamic>> notificationCapabilities() =>
      _map('notificationCapabilities');

  Future<bool> requestBatteryUnrestricted() async =>
      await _invoke<bool>('batteryUnrestricted') ?? false;

  Future<bool> openAutoStartSettings() async =>
      await _invoke<bool>('autoStartSettings') ?? false;

  Future<void> openUrl(String url) =>
      _channel.invokeMethod<void>('openUrl', {'url': url});

  static bool _engineReady = false;

  Future<bool> initEngine() async {
    if (_engineReady) return true;
    try {
      final dir = await _invoke<String>('dataDir');
      if (dir == null || dir.isEmpty) return false;
      _engineReady = await engineInit(dataDir: dir);
    } catch (_) {
      _engineReady = false;
    }
    return _engineReady;
  }

  bool get engineReady => _engineReady;

  Future<Segmentation?> segmentBody(String body) async {
    try {
      return await segmentMessage(body: body);
    } catch (_) {
      return null;
    }
  }

  Future<List<SearchHit>> searchMessagesRust(
    String query, {
    int limit = 40,
  }) async {
    try {
      if (!await initEngine()) return const [];
      return await searchMessages(query: query, limit: limit);
    } catch (_) {
      return const [];
    }
  }

  Future<int> indexSearchCorpus() async {
    if (!await initEngine()) return 0;
    final rows = await _list('searchCorpus');
    return indexMessages(
      docs: [
        for (final row in rows)
          SearchDoc(
            id: (row['id'] as num?)?.toInt() ?? 0,
            threadId: (row['threadId'] as num?)?.toInt() ?? 0,
            address: '${row['address'] ?? ''}',
            body: '${row['body'] ?? ''}',
            date: (row['date'] as num?)?.toInt() ?? 0,
            read: row['read'] == true,
          ),
      ],
    );
  }

  Future<List<ThreadSummary>> conversations({
    String query = '',
    String filter = 'all',
  }) async {
    final rows = await _list('conversations', {
      'query': query,
      'filter': filter,
    });
    return rows.map(ThreadSummary.fromMap).toList(growable: false);
  }

  Future<List<SmsMessage>> messages({
    required int threadId,
    int? before,
    int? beforeDate,
    int limit = 80,
  }) async {
    final rows = await _list('messages', {
      'threadId': threadId,
      if (before != null) 'before': before,
      if (beforeDate != null) 'beforeDate': beforeDate,
      'limit': limit,
    });
    return rows.map(SmsMessage.fromMap).toList(growable: false);
  }

  Future<int?> send({
    required String address,
    required String body,
    int? subscriptionId,
  }) => _invoke<int>('send', {
    'address': address,
    'body': body,
    if (subscriptionId != null) 'subscriptionId': subscriptionId,
  });

  Future<int?> sendMms({
    required List<String> recipients,
    required String body,
    int? subscriptionId,
    String? attachment,
  }) => _invoke<int>('sendMms', {
    'recipients': recipients,
    'body': body,
    if (subscriptionId != null) 'subscriptionId': subscriptionId,
    if (attachment != null) 'attachment': attachment,
  });

  Future<void> markRead(int threadId) =>
      _channel.invokeMethod<void>('markRead', {'threadId': threadId});

  Future<void> markAllRead() => _channel.invokeMethod<void>('markAllRead');
  Future<void> markThreadsRead(List<int> ids) =>
      _channel.invokeMethod<void>('markThreadsRead', {'threadIds': ids});
  Future<void> trashThreads(List<int> ids) =>
      _channel.invokeMethod<void>('trashThreads', {'threadIds': ids});
  Future<String> copyThreads(List<int> ids) async =>
      await _channel.invokeMethod<String>('copyThreads', {'threadIds': ids}) ??
      '';
  Future<void> hideMessages(List<int> ids) =>
      _channel.invokeMethod<void>('hideMessages', {'ids': ids});

  Future<void> hide(int id) => _channel.invokeMethod<void>('hide', {'id': id});

  Future<void> restore(int id) =>
      _channel.invokeMethod<void>('restore', {'id': id});

  Future<void> deleteForever(int id) =>
      _channel.invokeMethod<void>('delete', {'id': id});

  Future<List<TrashItem>> trash() async =>
      (await _list('trash')).map(TrashItem.fromMap).toList(growable: false);

  Future<void> setTrashRetention(int days) =>
      _channel.invokeMethod<void>('trashRetention', {'days': days});

  Future<int> purgeTrash(int days) async =>
      await _invoke<int>('purgeTrash', {'days': days}) ?? 0;

  Future<List<SimCard>> subscriptions() async =>
      (await _list('subscriptions'))
          .map(SimCard.fromMap)
          .toList(growable: false);

  Future<String?> draft(String address) =>
      _invoke<String>('draft', {'address': address});

  Future<void> saveDraft(String address, String body) => _channel
      .invokeMethod<void>('saveDraft', {'address': address, 'body': body});

  Future<ContactChoice?> pickContact() async {
    final raw = await _channel.invokeMethod<dynamic>('pickContact');
    if (raw is String && raw.trim().isNotEmpty) {
      return ContactChoice(number: raw.trim(), name: '');
    }
    if (raw is Map) {
      final number = '${raw['number'] ?? ''}';
      if (number.isEmpty) return null;
      return ContactChoice(number: number, name: '${raw['name'] ?? ''}');
    }
    return null;
  }

  Future<AttachmentChoice?> pickAttachment() async {
    final map = await _channel.invokeMapMethod<String, dynamic>(
      'pickAttachment',
    );
    if (map == null) return null;
    final uri = '${map['uri'] ?? ''}';
    if (uri.isEmpty) return null;
    final mime = '${map['mime'] ?? map['type'] ?? 'application/octet-stream'}';
    final segments = Uri.tryParse(uri)?.pathSegments;
    final name =
        '${map['name'] ?? (segments != null && segments.isNotEmpty ? segments.last : tr('Attachment'))}';
    return AttachmentChoice(uri: uri, mime: mime, name: name);
  }

  Future<Uint8List?> attachmentData(String uri) =>
      _invoke<Uint8List>('attachmentData', {'uri': uri});

  Future<void> retryMms() => _channel.invokeMethod<void>('retryMms');

  Future<void> pin(int threadId, bool pinned) => _channel.invokeMethod<void>(
    'pin',
    {'threadId': threadId, 'pinned': pinned},
  );

  Future<void> archive(int threadId, bool archived) =>
      _channel.invokeMethod<void>('archive', {
        'threadId': threadId,
        'archived': archived,
      });

  Future<void> block(String address) =>
      _channel.invokeMethod<void>('block', {'address': address});

  Future<void> unblock(String address) =>
      _channel.invokeMethod<void>('unblock', {'address': address});

  Future<List<BlockedNumber>> blocked() async =>
      (await _list('blocked'))
          .map(BlockedNumber.fromMap)
          .toList(growable: false);

  Future<int> schedule({
    required String address,
    required String body,
    required int at,
    int? subscriptionId,
  }) async =>
      await _invoke<int>('schedule', {
        'address': address,
        'body': body,
        'at': at,
        if (subscriptionId != null) 'subscriptionId': subscriptionId,
      }) ??
      0;

  Future<List<ScheduledMessage>> scheduled() async =>
      (await _list('scheduled'))
          .map(ScheduledMessage.fromMap)
          .toList(growable: false);

  Future<void> cancelScheduled(int id) =>
      _channel.invokeMethod<void>('cancelScheduled', {'id': id});

  Future<Map<String, dynamic>> launchIntent() => _map('launchIntent');

  Future<String?> systemSeed() => _invoke<String>('systemSeed');

  Future<Map<String, String>> settingsAll() async {
    final map = await _map('settingsAll');
    return map.map((key, value) => MapEntry(key, '$value'));
  }

  Future<void> settingsSet(String key, String value) =>
      _channel.invokeMethod<void>('settingsSet', {'key': key, 'value': value});

  Future<EngineStats> stats() async => EngineStats.fromMap(await _map('stats'));

  Future<bool> exportBackup() async =>
      await _invoke<bool>('exportBackup') ?? false;

  Future<bool> importBackup() async =>
      await _invoke<bool>('importBackup') ?? false;

  Future<Map<String, dynamic>> syncStatus() => _map('syncStatus');

  Future<Map<String, dynamic>> syncConfigure({
    required String serverUrl,
    required bool enabled,
    String? deviceName,
  }) => _map('syncConfigure', {
    'serverUrl': serverUrl,
    'enabled': enabled,
    if (deviceName != null) 'deviceName': deviceName,
  });

  Future<Map<String, dynamic>> syncPair(String pairingCode) =>
      _map('syncPair', {'code': pairingCode});

  Future<Map<String, dynamic>> syncNow() => _map('syncNow');

  Future<void> syncReset() => _channel.invokeMethod<void>('syncReset');

  Future<String?> syncStateRaw() => _invoke<String>('syncState');

  Future<void> syncStateSet(String json) =>
      _channel.invokeMethod<void>('syncStateSet', {'json': json});

  Future<List<Map<String, dynamic>>> remoteMessagesSince(int since) =>
      _list('remoteMessagesSince', {'since': since});

  Future<int?> insertRemoteMessage({
    required String address,
    required String body,
    required int date,
    int subscriptionId = -1,
  }) => _invoke<int>('insertRemoteMessage', {
    'address': address,
    'body': body,
    'date': date,
    'subscriptionId': subscriptionId,
  });

  Future<List<SmsMessage>> analyzeMessages(List<SmsMessage> messages) async {
    if (messages.isEmpty) return messages;
    try {
      final insights = await analyzeMessagesRust(
        bodies: messages.map((message) => message.body).toList(growable: false),
      );
      if (insights.length != messages.length) return messages;
      return [
        for (var index = 0; index < messages.length; index++)
          messages[index].copyWith(
            category: categoryFrom(insights[index].category),
            otp: insights[index].otp,
          ),
      ];
    } catch (_) {
      return messages;
    }
  }

  Future<List<ThreadSummary>> analyzeThreads(
    List<ThreadSummary> threads,
  ) async {
    if (threads.isEmpty) return threads;
    try {
      final insights = await analyzeMessagesRust(
        bodies: threads.map((thread) => thread.preview).toList(growable: false),
      );
      if (insights.length != threads.length) return threads;
      return [
        for (var index = 0; index < threads.length; index++)
          ThreadSummary(
            threadId: threads[index].threadId,
            address: threads[index].address,
            displayName: threads[index].displayName,
            preview: threads[index].preview,
            date: threads[index].date,
            unread: threads[index].unread,
            subscriptionId: threads[index].subscriptionId,
            messageType: threads[index].messageType,
            pinned: threads[index].pinned,
            archived: threads[index].archived,
            blocked: threads[index].blocked,
            category: categoryFrom(insights[index].category),
            otp: insights[index].otp,
            recipients: threads[index].recipients,
            count: threads[index].count,
            hasMms: threads[index].hasMms,
            latestId: threads[index].latestId,
            latestBody: threads[index].latestBody,
          ),
      ];
    } catch (_) {
      return threads;
    }
  }
}

Future<List<MessageAnalysis>> analyzeMessagesRust({
  required List<String> bodies,
}) => analyzeMessages(bodies: bodies);

String messageError(Object error) => switch (error) {
  PlatformException(:final message) =>
    message ?? tr("System messaging service unavailable"),
  MissingPluginException() => tr("SMS requires an Android phone"),
  _ => tr("Could not complete the action. Try again."),
};
