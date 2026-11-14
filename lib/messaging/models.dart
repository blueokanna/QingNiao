import 'package:qingniao/l10n/app_strings.dart';
import 'dart:typed_data';

enum MessageTransport { sms, mms }

enum DeliveryState { none, sending, sent, delivered, failed }

enum MessageCategory { personal, verification, promotion, finance }

MessageCategory categoryFrom(String? value) => switch (value) {
  'verification' => MessageCategory.verification,
  'promotion' => MessageCategory.promotion,
  'finance' => MessageCategory.finance,
  _ => MessageCategory.personal,
};

class SimCard {
  const SimCard({
    required this.id,
    required this.slot,
    required this.name,
    this.number = '',
    this.carrier = '',
  });

  final int id;
  final int slot;
  final String name;
  final String number;
  final String carrier;

  String get label =>
      number.isEmpty ? 'SIM $slot · $name' : 'SIM $slot · $number';

  factory SimCard.fromMap(Map<dynamic, dynamic> map) => SimCard(
    id: _int(map['id'], -1),
    slot: _int(map['slot'], 1),
    name: _string(map['name'], 'SIM'),
    number: _string(map['number']),
    carrier: _string(map['carrier']),
  );
}

class Attachment {
  const Attachment({
    required this.uri,
    required this.mime,
    required this.name,
    this.size = 0,
    this.id = '',
  });

  final String uri;
  final String mime;
  final String name;
  final int size;
  final String id;

  bool get isImage => mime.startsWith('image/');
  bool get isVideo => mime.startsWith('video/');
  bool get isAudio => mime.startsWith('audio/');

  factory Attachment.fromMap(Map<dynamic, dynamic> map) => Attachment(
    uri: _string(map['uri']),
    mime: _string(map['mime'], 'application/octet-stream'),
    name: _string(map['name'], tr("Attachment")),
    size: _int(map['size']),
    id: _string(map['id']),
  );
}

class ThreadSummary {
  const ThreadSummary({
    required this.threadId,
    required this.address,
    required this.displayName,
    required this.preview,
    required this.date,
    required this.unread,
    this.subscriptionId = -1,
    this.messageType = 1,
    this.pinned = false,
    this.archived = false,
    this.blocked = false,
    this.category = MessageCategory.personal,
    this.otp,
    this.recipients = const [],
    this.count = 0,
    this.hasMms = false,
    this.latestId = 0,
    this.latestBody = '',
  });

  final int threadId;
  final String address;
  final String displayName;
  final String preview;
  final int date;
  final int unread;
  final int subscriptionId;
  final int messageType;
  final bool pinned;
  final bool archived;
  final bool blocked;
  final MessageCategory category;
  final String? otp;
  final List<String> recipients;
  final int count;
  final bool hasMms;
  final int latestId;
  final String latestBody;

  bool get isGroup => recipients.length > 1;
  String get title => displayName.isNotEmpty ? displayName : address;
  bool get hasOtp => otp != null && otp!.isNotEmpty;
  bool get latestOutgoing => const {2, 4, 5, 6}.contains(messageType);

  ThreadSummary copyWith({
    bool? pinned,
    bool? archived,
    bool? blocked,
    int? unread,
  }) => ThreadSummary(
    threadId: threadId,
    address: address,
    displayName: displayName,
    preview: preview,
    date: date,
    unread: unread ?? this.unread,
    subscriptionId: subscriptionId,
    messageType: messageType,
    pinned: pinned ?? this.pinned,
    archived: archived ?? this.archived,
    blocked: blocked ?? this.blocked,
    category: category,
    otp: otp,
    recipients: recipients,
    count: count,
    hasMms: hasMms,
    latestId: latestId,
    latestBody: latestBody,
  );

  factory ThreadSummary.fromMap(Map<dynamic, dynamic> map) => ThreadSummary(
    threadId: _int(map['threadId']),
    address: _string(map['address'], tr("Unknown number")),
    displayName: _string(map['displayName']),
    preview: _string(map['body']),
    date: _int(map['date']),
    unread: _int(map['unread']),
    subscriptionId: _int(map['subscriptionId'], -1),
    messageType: _int(map['messageType'], 1),
    pinned: _bool(map['pinned']),
    archived: _bool(map['archived']),
    blocked: _bool(map['blocked']),
    category: categoryFrom(map['category'] as String?),
    otp: _otp(map['otp']),
    recipients: _strings(map['recipients']),
    count: _int(map['count']),
    hasMms: _bool(map['hasMms']),
    latestId: _int(map['latestId']),
    latestBody: _string(map['latestBody'], _string(map['body'])),
  );
}

class SmsMessage {
  const SmsMessage({
    required this.id,
    required this.threadId,
    required this.address,
    required this.body,
    required this.date,
    required this.type,
    required this.read,
    this.subscriptionId = -1,
    this.status = -1,
    this.transport = MessageTransport.sms,
    this.attachments = const [],
    this.sender = '',
    this.category = MessageCategory.personal,
    this.otp,
    this.subject = '',
    this.pending = false,
  });

  final int id;
  final int threadId;
  final String address;
  final String body;
  final int date;
  final int type;
  final bool read;
  final int subscriptionId;
  final int status;
  final MessageTransport transport;
  final List<Attachment> attachments;
  final String sender;
  final MessageCategory category;
  final String? otp;
  final String subject;
  final bool pending;

  bool get isMms => transport == MessageTransport.mms;
  bool get outgoing => const {2, 4, 5, 6}.contains(type);
  bool get isFailed => type == 5 || status == 64;
  bool get hasOtp => otp != null && otp!.isNotEmpty;
  bool get hasAttachments => attachments.isNotEmpty;

  DeliveryState get delivery {
    if (type == 5) return DeliveryState.failed;
    if (type == 4 || type == 6) return DeliveryState.sending;
    if (type != 2) return DeliveryState.none;
    if (status == 0) return DeliveryState.delivered;
    if (status == 64) return DeliveryState.failed;
    return DeliveryState.sent;
  }

  SmsMessage copyWith({
    int? id,
    bool? read,
    int? type,
    int? status,
    String? body,
    MessageCategory? category,
    String? otp,
  }) => SmsMessage(
    id: id ?? this.id,
    threadId: threadId,
    address: address,
    body: body ?? this.body,
    date: date,
    type: type ?? this.type,
    read: read ?? this.read,
    subscriptionId: subscriptionId,
    status: status ?? this.status,
    transport: transport,
    attachments: attachments,
    sender: sender,
    category: category ?? this.category,
    otp: otp ?? this.otp,
    subject: subject,
    pending: pending,
  );

  factory SmsMessage.fromMap(Map<dynamic, dynamic> map) {
    final transport = _bool(map['mms'])
        ? MessageTransport.mms
        : MessageTransport.sms;
    return SmsMessage(
      id: _int(map['id']),
      threadId: _int(map['threadId']),
      address: _string(map['address'], tr("Unknown number")),
      body: _string(map['body']),
      date: _int(map['date']),
      type: _int(map['type'], 1),
      read: _bool(map['read']),
      subscriptionId: _int(map['subscriptionId'], -1),
      status: _int(map['status'], -1),
      transport: transport,
      attachments: (map['attachments'] as List? ?? const [])
          .whereType<Map>()
          .map(Attachment.fromMap)
          .toList(growable: false),
      sender: _string(map['sender']),
      category: categoryFrom(map['category'] as String?),
      otp: _otp(map['otp']),
      subject: _string(map['subject']),
      pending: _bool(map['pending']),
    );
  }
}

class TrashItem {
  const TrashItem({
    required this.id,
    required this.threadId,
    required this.address,
    required this.body,
    required this.date,
    required this.deletedAt,
    this.kind = 0,
  });

  final int id;
  final int threadId;
  final String address;
  final String body;
  final int date;
  final int deletedAt;
  final int kind;

  factory TrashItem.fromMap(Map<dynamic, dynamic> map) => TrashItem(
    id: _int(map['id']),
    threadId: _int(map['threadId']),
    address: _string(map['address'], tr("Unknown number")),
    body: _string(map['body']),
    date: _int(map['date']),
    deletedAt: _int(map['deletedAt']),
    kind: _int(map['kind']),
  );
}

class BlockedNumber {
  const BlockedNumber({
    required this.address,
    this.note = '',
    this.createdAt = 0,
  });

  final String address;
  final String note;
  final int createdAt;

  factory BlockedNumber.fromMap(Map<dynamic, dynamic> map) => BlockedNumber(
    address: _string(map['address']),
    note: _string(map['note']),
    createdAt: _int(map['createdAt']),
  );
}

class ScheduledMessage {
  const ScheduledMessage({
    required this.id,
    required this.address,
    required this.body,
    required this.at,
    this.subscriptionId = -1,
  });

  final int id;
  final String address;
  final String body;
  final int at;
  final int subscriptionId;

  factory ScheduledMessage.fromMap(Map<dynamic, dynamic> map) =>
      ScheduledMessage(
        id: _int(map['id']),
        address: _string(map['address']),
        body: _string(map['body']),
        at: _int(map['at']),
        subscriptionId: _int(map['subscriptionId'], -1),
      );
}

class AccessState {
  const AccessState({
    this.defaultApp = false,
    this.readSms = false,
    this.sendSms = false,
    this.receiveSms = false,
    this.readContacts = false,
    this.notifications = false,
    this.roleAvailable = true,
  });

  final bool defaultApp;
  final bool readSms;
  final bool sendSms;
  final bool receiveSms;
  final bool readContacts;
  final bool notifications;
  final bool roleAvailable;

  bool get ready => defaultApp && readSms && sendSms && receiveSms;

  factory AccessState.fromMap(Map<dynamic, dynamic>? map) => AccessState(
    defaultApp: _bool(map?['defaultApp']),
    readSms: _bool(map?['readSms']),
    sendSms: _bool(map?['sendSms']),
    receiveSms: _bool(map?['receiveSms']),
    readContacts: _bool(map?['readContacts']),
    notifications: _bool(map?['notifications']),
    roleAvailable: map?['roleAvailable'] != false,
  );
}

class ContactChoice {
  const ContactChoice({required this.number, required this.name});

  final String number;
  final String name;

  factory ContactChoice.fromMap(Map<dynamic, dynamic> map) =>
      ContactChoice(number: _string(map['number']), name: _string(map['name']));
}

class AttachmentChoice {
  const AttachmentChoice({
    required this.uri,
    required this.mime,
    required this.name,
  });

  final String uri;
  final String mime;
  final String name;

  factory AttachmentChoice.fromMap(Map<dynamic, dynamic> map) =>
      AttachmentChoice(
        uri: _string(map['uri']),
        mime: _string(map['mime'], 'application/octet-stream'),
        name: _string(map['name'], tr("Attachment")),
      );
}

class SyncDevice {
  const SyncDevice({
    required this.id,
    required this.name,
    required this.fingerprint,
    this.publicKey = '',
    this.lastSeen = 0,
    this.thisDevice = false,
  });

  final String id;
  final String name;
  final String fingerprint;
  final String publicKey;
  final int lastSeen;
  final bool thisDevice;

  factory SyncDevice.fromMap(Map<dynamic, dynamic> map) => SyncDevice(
    id: _string(map['id']),
    name: _string(map['name']),
    fingerprint: _string(map['fingerprint']),
    publicKey: _string(map['publicKey']),
    lastSeen: _int(map['lastSeen']),
    thisDevice: _bool(map['thisDevice']),
  );
}

class EngineStats {
  const EngineStats({
    this.threads = 0,
    this.messages = 0,
    this.indexed = 0,
    this.trash = 0,
    this.frameMs = 0,
    this.quality = 'full',
    this.storageBytes = 0,
    this.otpCount = 0,
  });

  final int threads;
  final int messages;
  final int indexed;
  final int trash;
  final double frameMs;
  final String quality;
  final int storageBytes;
  final int otpCount;

  factory EngineStats.fromMap(Map<dynamic, dynamic>? map) => EngineStats(
    threads: _int(map?['threads']),
    messages: _int(map?['messages']),
    indexed: _int(map?['indexed']),
    trash: _int(map?['trash']),
    frameMs: (map?['frameMs'] as num?)?.toDouble() ?? 0,
    quality: _string(map?['quality'], 'full'),
    storageBytes: _int(map?['storageBytes']),
    otpCount: _int(map?['otpCount']),
  );
}

Uint8List? bytesOf(Object? value) => value is Uint8List ? value : null;

int _int(Object? value, [int fallback = 0]) => switch (value) {
  int v => v,
  num v => v.toInt(),
  String v => int.tryParse(v) ?? fallback,
  _ => fallback,
};

bool _bool(Object? value) => switch (value) {
  bool v => v,
  num v => v != 0,
  String v => v == 'true' || v == '1',
  _ => false,
};

String _string(Object? value, [String fallback = '']) =>
    value is String ? value : fallback;

String? _otp(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

List<String> _strings(Object? value) => value is List
    ? value.whereType<String>().toList(growable: false)
    : const [];
