import 'dart:async';
import 'dart:typed_data';

import 'package:qingniao/messaging/message_repository.dart';
import 'package:qingniao/messaging/models.dart';

class FixtureMessageRepository extends MessageRepository {
  FixtureMessageRepository() {
    _seed();
  }

  final StreamController<String> _events = StreamController<String>.broadcast();
  final Map<int, List<SmsMessage>> _messages = {};
  final List<TrashItem> _trash = [];
  final List<BlockedNumber> _blocked = [];
  final Map<int, bool> _pinned = {};
  final Map<int, bool> _archived = {};
  final Map<String, String> _drafts = {};
  final Map<String, String> _settings = {};
  final List<ScheduledMessage> _scheduled = [];
  int _nextId = 9000;

  static final int _now = DateTime.now().millisecondsSinceEpoch;

  @override
  Stream<String> get changes => _events.stream;

  @override
  Future<AccessState> access() async => const AccessState(
    defaultApp: true,
    readSms: true,
    sendSms: true,
    receiveSms: true,
    readContacts: true,
    readPhoneState: true,
    readPhoneNumbers: true,
    notifications: true,
  );

  @override
  Future<void> requestAccess() async {}

  @override
  Future<List<ThreadSummary>> conversations({
    String query = '',
    String filter = 'all',
  }) async {
    final all = _threads();
    return all
        .where((thread) {
          if (filter == 'unread' && thread.unread == 0) return false;
          if (filter == 'otp' && !thread.hasOtp) return false;
          if (filter == 'pinned' && !thread.pinned) return false;
          if (filter == 'archived' && !thread.archived) return false;
          if (filter != 'archived' &&
              filter != 'everything' &&
              thread.archived) {
            return false;
          }
          if (query.trim().isEmpty) return true;
          final needle = query.toLowerCase();
          return thread.title.toLowerCase().contains(needle) ||
              thread.address.contains(needle) ||
              thread.preview.toLowerCase().contains(needle);
        })
        .toList(growable: false);
  }

  List<ThreadSummary> _threads() {
    return _seeds
        .map((seed) {
          final messages = _messages[seed.id] ?? const <SmsMessage>[];
          final latest = messages.isEmpty ? null : messages.last;
          final unread = messages
              .where((message) => !message.read && !message.outgoing)
              .length;
          final codes = messages.reversed.where((message) => message.hasOtp);
          return ThreadSummary(
            threadId: seed.id,
            address: seed.address,
            displayName: seed.name,
            preview: latest?.body ?? seed.preview,
            date: latest?.date ?? seed.date,
            unread: unread,
            subscriptionId: seed.sim,
            messageType: latest?.type ?? 1,
            pinned: _pinned[seed.id] ?? seed.pinned,
            archived: _archived[seed.id] ?? seed.archived,
            category: latest?.category ?? seed.category,
            otp: codes.isEmpty ? null : codes.first.otp,
            recipients: seed.recipients,
            count: messages.length,
            hasMms: messages.any((message) => message.isMms),
            latestId: latest?.id ?? 0,
            latestBody: latest?.body ?? seed.preview,
          );
        })
        .toList(growable: false)
      ..sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        return b.date.compareTo(a.date);
      });
  }

  @override
  Future<List<SmsMessage>> messages({
    required int threadId,
    int? before,
    int? beforeDate,
    int limit = 80,
  }) async {
    final all = _messages[threadId] ?? const <SmsMessage>[];
    final filtered = before == null
        ? all
        : all.where((message) => message.id < before).toList();
    return filtered.length <= limit
        ? filtered
        : filtered.sublist(filtered.length - limit);
  }

  @override
  Future<int?> send({
    required String address,
    required String body,
    int? subscriptionId,
  }) async {
    final thread = _seeds.firstWhere(
      (seed) => seed.address == address || seed.name == address,
      orElse: () => _Seed(
        -1,
        address,
        address,
        '',
        _now,
        const [],
        MessageCategory.personal,
        1,
      ),
    );
    final id = _nextId++;
    final message = SmsMessage(
      id: id,
      threadId: thread.id,
      address: thread.address,
      body: body,
      date: DateTime.now().millisecondsSinceEpoch,
      type: 2,
      read: true,
      subscriptionId: subscriptionId ?? thread.sim,
      status: 0,
    );
    _messages.putIfAbsent(thread.id, () => []).add(message);
    _events.add('messages');
    return id;
  }

  @override
  Future<void> markRead(int threadId) async {
    final list = _messages[threadId];
    if (list == null) return;
    for (var index = 0; index < list.length; index++) {
      if (!list[index].read) list[index] = list[index].copyWith(read: true);
    }
    _events.add('messages');
  }

  @override
  Future<void> markAllRead() async {
    for (final id in _messages.keys.toList()) {
      await markRead(id);
    }
  }

  @override
  Future<void> markThreadsRead(List<int> ids) async {
    for (final id in ids) {
      await markRead(id);
    }
  }

  @override
  Future<void> hideMessages(List<int> ids) async {
    for (final id in ids) {
      await hide(id);
    }
  }

  @override
  Future<void> trashThreads(List<int> ids) async {
    final messages = [for (final id in ids) ...?_messages[id]];
    for (final message in messages) {
      await hide(message.id);
    }
  }

  @override
  Future<String> copyThreads(List<int> ids) async =>
      [for (final id in ids) ...?_messages[id]].map((m) => m.body).join('\n\n');

  @override
  Future<void> hide(int id) async {
    for (final entry in _messages.entries) {
      final index = entry.value.indexWhere((message) => message.id == id);
      if (index >= 0) {
        final message = entry.value.removeAt(index);
        _trash.add(
          TrashItem(
            id: message.id,
            threadId: message.threadId,
            address: message.address,
            body: message.body,
            date: message.date,
            deletedAt: DateTime.now().millisecondsSinceEpoch,
            kind: message.isMms ? 1 : 0,
          ),
        );
        _events.add('messages');
        return;
      }
    }
  }

  @override
  Future<List<TrashItem>> trash() async => List.unmodifiable(_trash);

  @override
  Future<void> restore(int id) async {
    final index = _trash.indexWhere((item) => item.id == id);
    if (index < 0) return;
    final item = _trash.removeAt(index);
    _messages
        .putIfAbsent(item.threadId, () => [])
        .add(
          SmsMessage(
            id: item.id,
            threadId: item.threadId,
            address: item.address,
            body: item.body,
            date: item.date,
            type: 1,
            read: true,
          ),
        );
    _events.add('messages');
  }

  @override
  Future<void> deleteForever(int id) async {
    _trash.removeWhere((item) => item.id == id);
  }

  @override
  Future<int> purgeTrash(int days) async {
    final before = DateTime.now()
        .subtract(Duration(days: days))
        .millisecondsSinceEpoch;
    final removed = _trash
        .where((item) => days > 0 && item.deletedAt < before)
        .length;
    _trash.removeWhere((item) => days > 0 && item.deletedAt < before);
    return removed;
  }

  @override
  Future<List<SimCard>> subscriptions() async => const [
    SimCard(
      id: 1,
      slot: 1,
      name: '\u79fb\u52a8',
      number: '138 0013 8000',
      carrier: '\u4e2d\u56fd\u79fb\u52a8',
    ),
    SimCard(
      id: 2,
      slot: 2,
      isEmbedded: true,
      name: '\u8054\u901a',
      number: '186 8888 6666',
      carrier: '\u4e2d\u56fd\u8054\u901a',
    ),
  ];

  @override
  Future<String?> draft(String address) async => _drafts[address];

  @override
  Future<void> saveDraft(String address, String body) async {
    if (body.isEmpty) {
      _drafts.remove(address);
    } else {
      _drafts[address] = body;
    }
  }

  @override
  Future<ContactChoice?> pickContact() async =>
      const ContactChoice(number: '13912345678', name: '\u6c88\u77e5\u590f');

  @override
  Future<AttachmentChoice?> pickAttachment() async => const AttachmentChoice(
    uri: 'demo://image',
    mime: 'image/jpeg',
    name: '\u6d77\u8fb9\u7684\u508d\u665a.jpg',
  );

  @override
  Future<Uint8List?> attachmentData(String uri) async => null;

  @override
  Future<void> pin(int threadId, bool pinned) async {
    _pinned[threadId] = pinned;
    _events.add('messages');
  }

  @override
  Future<void> archive(int threadId, bool archived) async {
    _archived[threadId] = archived;
    _events.add('messages');
  }

  @override
  Future<void> block(String address) async {
    _blocked.add(
      BlockedNumber(
        address: address,
        note: '\u6765\u81ea\u4f1a\u8bdd',
        createdAt: _now,
      ),
    );
  }

  @override
  Future<void> unblock(String address) async {
    _blocked.removeWhere((item) => item.address == address);
  }

  @override
  Future<List<BlockedNumber>> blocked() async => List.unmodifiable(_blocked);

  @override
  Future<int> schedule({
    required String address,
    required String body,
    required int at,
    int? subscriptionId,
  }) async {
    final id = _nextId++;
    _scheduled.add(
      ScheduledMessage(
        id: id,
        address: address,
        body: body,
        at: at,
        subscriptionId: subscriptionId ?? 1,
      ),
    );
    return id;
  }

  @override
  Future<List<ScheduledMessage>> scheduled() async =>
      List.unmodifiable(_scheduled);

  @override
  Future<void> cancelScheduled(int id) async {
    _scheduled.removeWhere((item) => item.id == id);
  }

  @override
  Future<Map<String, dynamic>> launchIntent() async => const {};

  @override
  Future<String?> systemSeed() async => '#0E7C6B';

  @override
  Future<Map<String, String>> settingsAll() async =>
      Map.unmodifiable(_settings);

  @override
  Future<void> settingsSet(String key, String value) async {
    _settings[key] = value;
  }

  @override
  Future<EngineStats> stats() async => EngineStats(
    threads: _seeds.length,
    messages: _messages.values.fold(0, (sum, list) => sum + list.length),
    indexed: 0,
    trash: _trash.length,
    frameMs: 8.4,
    quality: 'full',
    storageBytes: 2_684_354,
    otpCount: _threads().where((thread) => thread.hasOtp).length,
  );

  @override
  Future<bool> exportBackup() async => true;

  @override
  Future<bool> importBackup() async => true;

  @override
  Future<Map<String, dynamic>> syncStatus() async => {
    'enabled': true,
    'serverUrl': 'https://sync.qingniao.dev',
    'deviceName': 'Pale Blue',
    'fingerprint': 'A3F1-88C2-4D0E-9B77',
    'lastSync': _now - 120000,
    'pending': 2,
    'devices': [
      {
        'id': 'a',
        'name': 'Pale Blue',
        'fingerprint': 'A3F1-88C2-4D0E-9B77',
        'thisDevice': true,
        'lastSeen': _now,
      },
      {
        'id': 'b',
        'name': '\u5c0f\u5c9b',
        'fingerprint': '91BE-0C44-7AA2-36F0',
        'lastSeen': _now - 3600000,
      },
    ],
  };

  @override
  Future<Map<String, dynamic>> syncConfigure({
    required String serverUrl,
    required bool enabled,
    String? deviceName,
  }) async => syncStatus();

  @override
  Future<Map<String, dynamic>> syncPair(String pairingCode) async =>
      syncStatus();

  @override
  Future<Map<String, dynamic>> syncNow() async => syncStatus();

  @override
  Future<void> syncReset() async {}

  @override
  Future<List<SmsMessage>> analyzeMessages(List<SmsMessage> messages) async =>
      messages;

  @override
  Future<List<ThreadSummary>> analyzeThreads(
    List<ThreadSummary> threads,
  ) async => threads;

  void _seed() {
    final now = DateTime.now().millisecondsSinceEpoch;
    SmsMessage message(
      int id,
      int thread,
      String address,
      String body,
      int minutesAgo, {
      int type = 1,
      bool read = false,
      String? otp,
      MessageCategory category = MessageCategory.personal,
      List<Attachment> attachments = const [],
      bool mms = false,
      String sender = '',
      int sim = 1,
      String subject = '',
    }) => SmsMessage(
      id: id,
      threadId: thread,
      address: address,
      body: body,
      date: now - minutesAgo * 60000,
      type: type,
      read: read,
      otp: otp,
      category: category,
      attachments: attachments,
      transport: mms ? MessageTransport.mms : MessageTransport.sms,
      sender: sender,
      subscriptionId: sim,
      subject: subject,
    );

    _messages[1] = [
      message(
        1,
        1,
        '95588',
        '\u60a8\u5c3e\u53f7 6214 \u7684\u8d26\u6237\u4e8e 10:24 \u5411「\u57ce\u5e02\u4ea4\u901a」\u652f\u51fa 6.00 \u5143，\u4f59\u989d 18,420.55 \u5143。',
        300,
        read: true,
        category: MessageCategory.finance,
      ),
      message(
        2,
        1,
        '95588',
        '\u60a8\u5c3e\u53f7 6214 \u7684\u8d26\u6237\u4e8e 12:08 \u6536\u5230\u5de5\u8d44 12,800.00 \u5143，\u4f59\u989d 31,220.55 \u5143。',
        90,
        category: MessageCategory.finance,
      ),
      message(
        3,
        1,
        '95588',
        '\u5c3e\u53f7 6214 \u4fe1\u7528\u5361\u672c\u671f\u8d26\u5355 3,420.00 \u5143，\u5230\u671f\u8fd8\u6b3e\u65e5 11 \u6708 28 \u65e5。',
        20,
        category: MessageCategory.finance,
      ),
    ];
    _messages[2] = [
      message(
        4,
        2,
        '95338',
        '【\u987a\u4e30\u901f\u8fd0】\u60a8\u7684\u5feb\u4ef6\u5df2\u5230\u8fbe「\u9752\u67ab\u91cc」\u9a7f\u7ad9，\u51ed\u53d6\u4ef6\u7801 8-3-2046 \u9886\u53d6。',
        180,
        read: true,
      ),
      message(
        5,
        2,
        '95338',
        '【\u987a\u4e30\u901f\u8fd0】\u5feb\u4ef6\u5df2\u7b7e\u6536，\u611f\u8c22\u4f7f\u7528\u987a\u4e30，\u671f\u5f85\u518d\u6b21\u4e3a\u60a8\u670d\u52a1。',
        26,
      ),
    ];
    _messages[3] = [
      message(
        6,
        3,
        '106903',
        '【\u534e\u4e3a\u4e91】\u9a8c\u8bc1\u7801 482913，\u7528\u4e8e\u767b\u5f55\u9a8c\u8bc1，5 \u5206\u949f\u5185\u6709\u6548。\u8bf7\u52ff\u6cc4\u9732\u7ed9\u4ed6\u4eba。',
        4,
        otp: '482913',
        category: MessageCategory.verification,
      ),
    ];
    _messages[4] = [
      message(
        7,
        4,
        '+86 138 0000 1234',
        '\u4f60\u4e0a\u6b21\u8bf4\u7684\u90a3\u5bb6\u9762\u5305\u5e97，\u6211\u627e\u5230\u4e86。\u5c31\u5728\u6cb3\u8fb9\u7684\u65e7\u4ed3\u5e93\u65c1\u8fb9。',
        260,
        read: true,
        sim: 2,
      ),
      message(
        8,
        4,
        '+86 138 0000 1234',
        '\u508d\u665a\u7684\u5149\u5f88\u597d，\u8981\u4e0d\u8981\u4e00\u8d77\u53bb？',
        240,
        read: true,
        sim: 2,
      ),
      message(
        9,
        4,
        '+86 138 0000 1234',
        '\u90a3\u5c31\u5468\u516d\u56db\u70b9，\u6211\u5e26\u4e0a\u76f8\u673a。',
        42,
        type: 2,
        read: true,
        sim: 2,
      ),
    ];
    _messages[5] = [
      message(
        10,
        5,
        '+86 139 0000 5678',
        '\u65b0\u7684\u52a8\u6548\u7a3f\u6211\u653e\u5230\u5171\u4eab\u76d8\u4e86：\u5fbd\u7ae0\u4ece\u5706\u70b9\u957f\u6210\u82b1\u6735\u7684\u90a3\u4e00\u7248。',
        120,
        read: true,
        sender: '\u6797\u96fe',
        sim: 2,
        attachments: const [
          Attachment(
            uri: 'demo://image',
            mime: 'image/jpeg',
            name: '\u52a8\u6548\u5206\u89e3.jpg',
            size: 824000,
          ),
        ],
        mms: true,
        category: MessageCategory.personal,
      ),
      message(
        11,
        5,
        '+86 137 0000 9012',
        '\u770b\u8d77\u6765\u50cf\u547c\u5438\u4e00\u6837。\u53ef\u4ee5\u518d\u628a\u56de\u5f39\u538b\u4e00\u70b9\u70b9。',
        110,
        sender: '\u5468\u5cb8',
        sim: 2,
        mms: true,
      ),
      message(
        12,
        5,
        '+86 139 0000 5678',
        '\u6536\u5230，\u4eca\u665a\u8c03\u4e00\u7248\u53d1\u7fa4\u91cc。',
        100,
        sender: '\u6797\u96fe',
        sim: 2,
        mms: true,
      ),
      message(
        13,
        5,
        '+86 137 0000 9012',
        '\u522b\u5fd8\u4e86\u660e\u65e9\u5341\u70b9\u7684\u8bc4\u5ba1 🌿',
        12,
        sender: '\u5468\u5cb8',
        sim: 2,
        mms: true,
      ),
      message(
        15,
        5,
        '+86 139 0000 5678',
        '\u6536\u5230，\u6211\u628a\u56de\u5f39\u66f2\u7ebf\u538b\u5230 0.72 \u4e86，\u660e\u65e9\u4e00\u8d77\u770b。',
        6,
        type: 2,
        read: true,
        sim: 2,
        mms: true,
      ),
    ];
    _messages[6] = [
      message(
        14,
        6,
        '106900',
        '【\u7f8e\u56e2】\u60a8\u6709\u4e00\u5f20\u6ee1 30 \u51cf 8 \u7684\u4f18\u60e0\u5238\u5c06\u4e8e\u4eca\u65e5 24:00 \u8fc7\u671f，\u9000\u8ba2\u56de T。',
        500,
        read: true,
        category: MessageCategory.promotion,
        otp: null,
      ),
    ];
  }

  static final List<_Seed> _seeds = [
    _Seed(
      1,
      '95588',
      '\u5de5\u5546\u94f6\u884c',
      '\u5c3e\u53f7 6214 \u4fe1\u7528\u5361\u672c\u671f\u8d26\u5355 3,420.00 \u5143',
      _now - 20 * 60000,
      const [],
      MessageCategory.finance,
      1,
      pinned: true,
    ),
    _Seed(
      2,
      '95338',
      '\u987a\u4e30\u901f\u8fd0',
      '\u5feb\u4ef6\u5df2\u7b7e\u6536，\u611f\u8c22\u4f7f\u7528\u987a\u4e30',
      _now - 26 * 60000,
      const [],
      MessageCategory.personal,
      1,
    ),
    _Seed(
      3,
      '106903',
      '\u534e\u4e3a\u4e91',
      '\u9a8c\u8bc1\u7801 482913，5 \u5206\u949f\u5185\u6709\u6548',
      _now - 4 * 60000,
      const [],
      MessageCategory.verification,
      1,
      pinned: true,
    ),
    _Seed(
      4,
      '+86 138 0000 1234',
      '\u6797\u96fe',
      '\u90a3\u5c31\u5468\u516d\u56db\u70b9，\u6211\u5e26\u4e0a\u76f8\u673a。',
      _now - 42 * 60000,
      const [],
      MessageCategory.personal,
      2,
    ),
    _Seed(
      5,
      '+86 139 0000 5678',
      '\u8bbe\u8ba1\u5c0f\u7ec4',
      '\u522b\u5fd8\u4e86\u660e\u65e9\u5341\u70b9\u7684\u8bc4\u5ba1 🌿',
      _now - 12 * 60000,
      const ['+86 139 0000 5678', '+86 137 0000 9012', '+86 138 0000 1234'],
      MessageCategory.personal,
      2,
    ),
    _Seed(
      6,
      '106900',
      '\u7f8e\u56e2',
      '\u6ee1 30 \u51cf 8 \u4f18\u60e0\u5238\u4eca\u65e5\u8fc7\u671f',
      _now - 500 * 60000,
      const [],
      MessageCategory.promotion,
      1,
    ),
  ];
}

class _Seed {
  const _Seed(
    this.id,
    this.address,
    this.name,
    this.preview,
    this.date,
    this.recipients,
    this.category,
    this.sim, {
    this.pinned = false,
    // ignore: unused_element_parameter
    this.archived = false,
  });

  final int id;
  final String address;
  final String name;
  final String preview;
  final int date;
  final List<String> recipients;
  final MessageCategory category;
  final int sim;
  final bool pinned;
  final bool archived;
}
