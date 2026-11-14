import 'dart:io';

import 'package:flutter/services.dart';

abstract final class SensitiveClipboard {
  static const _channel = MethodChannel('com.blue.qingniao/messages');

  static Future<void> copy(String text) async {
    if (Platform.isAndroid) {
      await _channel.invokeMethod<void>('copySensitive', {'text': text});
    } else {
      await Clipboard.setData(ClipboardData(text: text));
    }
  }
}
