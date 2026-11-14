import 'dart:async';
import 'dart:typed_data';

import 'message_repository.dart';
import 'models.dart';

class DemoMessageRepository extends MessageRepository {
  DemoMessageRepository() {
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
    notifications: true,
  );

  @override
  Future<void> requestAccess() async {}

  @override
  Future<List<ThreadSummary>> conversations({String query = '', String filter = 'all'}) async {
    final all = _threads();
    return all.where((thread) {
      if (filter == 'unread' && thread.unread == 0) return false;
      if (filter == 'otp' && !thread.hasOtp) return false;
      if (filter == 'pinned' && !thread.pinned) return false;
      if (filter == 'archived' && !thread.archived) return false;
      if (filter != 'archived' && thread.archived) return false;
      if (query.trim().isEmpty) return true;
      final needle = query.toLowerCase();
      return thread.title.toLowerCase().contains(needle) ||
          thread.address.contains(needle) ||
          thread.preview.toLowerCase().contains(needle);
    }).toList(growable: false);
  }

  List<ThreadSummary> _threads() {
    return _seeds.map((seed) {
      final messages = _messages[seed.id] ?? const <SmsMessage>[];
      final latest = messages.isEmpty ? null : messages.last;
      final unread = messages.where((message) => !message.read && !message.outgoing).length;
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
    }).toList(growable: false)
      ..sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        return b.date.compareTo(a.date);
      });
  }

  @override
  Future<List<SmsMessage>> messages({
    required int threadId,
    int? before,
    int limit = 80,
  }) async {
    final all = _messages[threadId] ?? const <SmsMessage>[];
    final filtered = before == null ? all : all.where((message) => message.id < before).toList();
    return filtered.length <= limit ? filtered : filtered.sublist(filtered.length - limit);
  }

  @override
  Future<int?> send({required String address, required String body, int? subscriptionId}) async {
    final thread = _seeds.firstWhere(
      (seed) => seed.address == address || seed.name == address,
      orElse: () => _Seed(-1, address, address, '', _now, const [], MessageCategory.personal, 1),
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
    _messages.putIfAbsent(item.threadId, () => []).add(
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
    final before = DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch;
    final removed = _trash.where((item) => days > 0 && item.deletedAt < before).length;
    _trash.removeWhere((item) => days > 0 && item.deletedAt < before);
    return removed;
  }

  @override
  Future<List<SimCard>> subscriptions() async => const [
    SimCard(id: 1, slot: 1, name: '移动', number: '138 0013 8000', carrier: '中国移动'),
    SimCard(id: 2, slot: 2, name: '联通', number: '186 8888 6666', carrier: '中国联通'),
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
      const ContactChoice(number: '13912345678', name: '沈知夏');

  @override
  Future<AttachmentChoice?> pickAttachment() async =>
      const AttachmentChoice(uri: 'demo://image', mime: 'image/jpeg', name: '海边的傍晚.jpg');

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
    _blocked.add(BlockedNumber(address: address, note: '来自会话', createdAt: _now));
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
      ScheduledMessage(id: id, address: address, body: body, at: at, subscriptionId: subscriptionId ?? 1),
    );
    return id;
  }

  @override
  Future<List<ScheduledMessage>> scheduled() async => List.unmodifiable(_scheduled);

  @override
  Future<void> cancelScheduled(int id) async {
    _scheduled.removeWhere((item) => item.id == id);
  }

  @override
  Future<Map<String, dynamic>> launchIntent() async => const {};

  @override
  Future<String?> systemSeed() async => '#0E7C6B';

  @override
  Future<Map<String, String>> settingsAll() async => Map.unmodifiable(_settings);

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
        'name': '小岛',
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
  Future<Map<String, dynamic>> syncPair(String pairingCode) async => syncStatus();

  @override
  Future<Map<String, dynamic>> syncNow() async => syncStatus();

  @override
  Future<void> syncReset() async {}

  @override
  Future<List<SmsMessage>> analyzeMessages(List<SmsMessage> messages) async => messages;

  @override
  Future<List<ThreadSummary>> analyzeThreads(List<ThreadSummary> threads) async => threads;

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
      message(1, 1, '95588', '您尾号 6214 的账户于 10:24 向「城市交通」支出 6.00 元，余额 18,420.55 元。', 300, read: true, category: MessageCategory.finance),
      message(2, 1, '95588', '您尾号 6214 的账户于 12:08 收到工资 12,800.00 元，余额 31,220.55 元。', 90, category: MessageCategory.finance),
      message(3, 1, '95588', '尾号 6214 信用卡本期账单 3,420.00 元，到期还款日 11 月 28 日。', 20, category: MessageCategory.finance),
    ];
    _messages[2] = [
      message(4, 2, '95338', '【顺丰速运】您的快件已到达「青枫里」驿站，凭取件码 8-3-2046 领取。', 180, read: true),
      message(5, 2, '95338', '【顺丰速运】快件已签收，感谢使用顺丰，期待再次为您服务。', 26),
    ];
    _messages[3] = [
      message(6, 3, '106903', '【华为云】验证码 482913，用于登录验证，5 分钟内有效。请勿泄露给他人。', 4, otp: '482913', category: MessageCategory.verification),
    ];
    _messages[4] = [
      message(7, 4, '+86 138 0000 1234', '你上次说的那家面包店，我找到了。就在河边的旧仓库旁边。', 260, read: true, sim: 2),
      message(8, 4, '+86 138 0000 1234', '傍晚的光很好，要不要一起去？', 240, read: true, sim: 2),
      message(9, 4, '+86 138 0000 1234', '那就周六四点，我带上相机。', 42, type: 2, read: true, sim: 2),
    ];
    _messages[5] = [
      message(
        10,
        5,
        '+86 139 0000 5678',
        '新的动效稿我放到共享盘了：徽章从圆点长成花朵的那一版。',
        120,
        read: true,
        sender: '林雾',
        sim: 2,
        attachments: const [
          Attachment(uri: 'demo://image', mime: 'image/jpeg', name: '动效分解.jpg', size: 824000),
        ],
        mms: true,
        category: MessageCategory.personal,
      ),
      message(11, 5, '+86 137 0000 9012', '看起来像呼吸一样。可以再把回弹压一点点。', 110, sender: '周岸', sim: 2, mms: true),
      message(12, 5, '+86 139 0000 5678', '收到，今晚调一版发群里。', 100, sender: '林雾', sim: 2, mms: true),
      message(13, 5, '+86 137 0000 9012', '别忘了明早十点的评审 🌿', 12, sender: '周岸', sim: 2, mms: true),
      message(15, 5, '+86 139 0000 5678', '收到，我把回弹曲线压到 0.72 了，明早一起看。', 6, type: 2, read: true, sim: 2, mms: true),
    ];
    _messages[6] = [
      message(14, 6, '106900', '【美团】您有一张满 30 减 8 的优惠券将于今日 24:00 过期，退订回 T。', 500, read: true, category: MessageCategory.promotion, otp: null),
    ];
  }

  static final List<_Seed> _seeds = [
    _Seed(1, '95588', '工商银行', '尾号 6214 信用卡本期账单 3,420.00 元', _now - 20 * 60000, const [], MessageCategory.finance, 1, pinned: true),
    _Seed(2, '95338', '顺丰速运', '快件已签收，感谢使用顺丰', _now - 26 * 60000, const [], MessageCategory.personal, 1),
    _Seed(3, '106903', '华为云', '验证码 482913，5 分钟内有效', _now - 4 * 60000, const [], MessageCategory.verification, 1, pinned: true),
    _Seed(4, '+86 138 0000 1234', '林雾', '那就周六四点，我带上相机。', _now - 42 * 60000, const [], MessageCategory.personal, 2),
    _Seed(
      5,
      '+86 139 0000 5678',
      '设计小组',
      '别忘了明早十点的评审 🌿',
      _now - 12 * 60000,
      const ['+86 139 0000 5678', '+86 137 0000 9012', '+86 138 0000 1234'],
      MessageCategory.personal,
      2,
    ),
    _Seed(6, '106900', '美团', '满 30 减 8 优惠券今日过期', _now - 500 * 60000, const [], MessageCategory.promotion, 1),
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
