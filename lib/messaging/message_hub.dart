import 'dart:async';

import 'package:flutter/foundation.dart';

import 'message_repository.dart';
import 'models.dart';

class MessageHub extends ChangeNotifier {
  MessageHub(this.repository);

  final MessageRepository repository;

  AccessState access = const AccessState();
  List<ThreadSummary> threads = const [];
  List<ThreadSummary> allThreads = const [];
  bool _markingRead = false;
  List<SimCard> sims = const [];
  String query = '';
  String filter = 'all';
  bool loading = true;
  String? error;
  int intentTick = 0;
  int syncTick = 0;
  bool _disposed = false;
  DateTime? lastLoaded;

  StreamSubscription<String>? _subscription;
  Timer? _debounce;
  bool _refreshing = false;
  bool _again = false;
  bool _indexDirty = true;

  int get unread => allThreads.fold(0, (sum, thread) => sum + thread.unread);
  int get otpCount => allThreads.where((thread) => thread.hasOtp).length;
  int get otpUnread =>
      allThreads.where((thread) => thread.hasOtp && thread.unread > 0).length;

  Future<void> markAllRead({bool verificationOnly = false}) async {
    if (_markingRead) return;
    _markingRead = true;
    try {
      if (verificationOnly) {
        final latest = await repository.analyzeThreads(
          await repository.conversations(filter: 'everything'),
        );
        final ids = latest
            .where((t) => t.hasOtp && t.unread > 0)
            .map((t) => t.threadId)
            .toList(growable: false);
        if (ids.isNotEmpty) await repository.markThreadsRead(ids);
      } else {
        await repository.markAllRead();
      }
      await refresh(silent: true);
    } finally {
      _markingRead = false;
    }
  }

  int countFor(String value) => switch (value) {
    'unread' =>
      allThreads
          .where((thread) => !thread.archived && thread.unread > 0)
          .length,
    'otp' =>
      allThreads.where((thread) => !thread.archived && thread.hasOtp).length,
    'pinned' =>
      allThreads.where((thread) => !thread.archived && thread.pinned).length,
    'archived' => allThreads.where((thread) => thread.archived).length,
    _ => allThreads.where((t) => !t.archived).length,
  };

  void start() {
    repository.initEngine();
    _subscription ??= repository.changes.listen(
      (event) {
        if (event == 'intent') intentTick++;
        if (event == 'sync') syncTick++;
        _indexDirty = true;
        refresh(silent: true);
      },
      onError: (Object value) {
        error = messageError(value);
        notifyListeners();
      },
    );
    refresh();
  }

  void search(String value) {
    query = value;
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 240),
      () => refresh(silent: true),
    );
    notifyListeners();
  }

  void setFilter(String value) {
    if (filter == value) return;
    filter = value;
    refresh(silent: true);
    notifyListeners();
  }

  Future<void> refresh({bool silent = false}) async {
    if (_disposed) return;
    if (_refreshing) {
      _again = true;
      return;
    }
    _refreshing = true;
    if (!silent) {
      loading = true;
      notifyListeners();
    }
    try {
      final nextAccess = await repository.access();
      access = nextAccess;
      if (!nextAccess.ready) {
        threads = const [];
        allThreads = const [];
        sims = const [];
        error = null;
        loading = false;
        notifyListeners();
        return;
      }
      allThreads = await repository.analyzeThreads(
        await repository.conversations(query: '', filter: 'everything'),
      );
      if (query.trim().isEmpty) {
        threads = allThreads
            .where(
              (t) => switch (filter) {
                'archived' => t.archived,
                'unread' => !t.archived && t.unread > 0,
                'otp' => !t.archived && t.hasOtp,
                'pinned' => !t.archived && t.pinned,
                _ => !t.archived,
              },
            )
            .toList(growable: false);
      } else {
        threads = await repository.analyzeThreads(await _searchThreads());
        if (filter == 'otp') {
          threads = threads.where((t) => t.hasOtp).toList(growable: false);
        }
      }
      sims = await repository.subscriptions();
      error = null;
      lastLoaded = DateTime.now();
    } catch (value) {
      error = messageError(value);
    } finally {
      _refreshing = false;
      loading = false;
      if (_again) {
        _again = false;
        unawaited(refresh(silent: true));
      }
      notifyListeners();
    }
  }

  Future<List<ThreadSummary>> _searchThreads() async {
    final direct = await repository.conversations(query: query, filter: filter);
    try {
      if (!await repository.initEngine()) return direct;
      if (_indexDirty) {
        final indexed = await repository.indexSearchCorpus();
        _indexDirty = false;
        if (indexed == 0) return direct;
      }
      final hits = await repository.searchMessagesRust(query, limit: 200);
      if (hits.isEmpty) return direct;
      final rank = <int, int>{};
      for (var index = 0; index < hits.length; index++) {
        rank.putIfAbsent(hits[index].threadId.toInt(), () => index);
      }
      final all = await repository.conversations(query: '', filter: filter);
      final merged = <ThreadSummary>[];
      final seen = <int>{};
      for (final thread in all) {
        if (rank.containsKey(thread.threadId)) {
          merged.add(thread);
          seen.add(thread.threadId);
        }
      }

      for (final thread in direct) {
        if (seen.add(thread.threadId)) merged.add(thread);
      }
      merged.sort((a, b) {
        final left = rank[a.threadId];
        final right = rank[b.threadId];
        if (left != null && right != null) return left.compareTo(right);
        if (left != null) return -1;
        if (right != null) return 1;
        return b.date.compareTo(a.date);
      });
      return merged;
    } catch (_) {
      return direct;
    }
  }

  Future<void> pin(int threadId, bool pinned) async {
    await repository.pin(threadId, pinned);
    await refresh(silent: true);
  }

  Future<void> archive(int threadId, bool archived) async {
    await repository.archive(threadId, archived);
    await refresh(silent: true);
  }

  Future<void> markRead(int threadId) async {
    await repository.markRead(threadId);
    await refresh(silent: true);
  }

  Future<void> hide(int messageId) async {
    await repository.hide(messageId);
    await refresh(silent: true);
  }

  Future<void> block(String address) async {
    await repository.block(address);
    await refresh(silent: true);
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _subscription?.cancel();
    super.dispose();
  }
}
