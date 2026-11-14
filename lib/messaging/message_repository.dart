import 'package:flutter/services.dart';

typedef MessageRecord = Map<String, dynamic>;

class MessageRepository {
  const MessageRepository();
  static const _channel = MethodChannel('dev.qingniao/messages');
  static const _events = EventChannel('dev.qingniao/changes');
  Stream<String> get changes => _events.receiveBroadcastStream().cast<String>();
  Future<T?> invoke<T>(String method, [MessageRecord? arguments]) =>
      _channel.invokeMethod<T>(method, arguments);
  Future<List<MessageRecord>> records(
    String method, [
    MessageRecord? arguments,
  ]) async {
    final result = await _channel.invokeListMethod<dynamic>(method, arguments);
    return (result ?? [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<bool> hasAccess() async {
    final result = await _channel.invokeMapMethod<String, dynamic>('access');
    return result != null && result.values.every((value) => value == true);
  }
}

String messageError(Object error) => switch (error) {
  PlatformException(:final message) => message ?? '系统消息服务不可用',
  MissingPluginException() => '短信功能需要在 Android 手机上运行',
  _ => '操作未完成，请重试',
};
