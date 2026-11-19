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
  bool _foreground = true;
  DateTime? lastLoaded;

  StreamSubscription<String>? _subscription;
  Timer? _debounce;
  Timer? _changeTimer;
  Future<void>? _refreshFuture;
  bool _reloadRequested = true;
  bool _viewRequested = false;
  bool _indexDirty = true;
  int _dataRevision = 0;

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

  bool _matchesFilter(ThreadSummary thread, String value) => switch (value) {
    'everything' => true,
    'archived' => thread.archived,
    'unread' => !thread.archived && thread.unread > 0,
    'otp' => !thread.archived && thread.hasOtp,
    'pinned' => !thread.archived && thread.pinned,
    _ => !thread.archived,
  };

  int countFor(String value) =>
      allThreads.where((thread) => _matchesFilter(thread, value)).length;

  void start() {
    if (_disposed || _subscription != null) return;
    unawaited(repository.initEngine());
    _subscription = repository.changes.listen(
      (event) {
        if (_disposed) return;
        if (event == 'intent') {
          intentTick++;
          notifyListeners();
          return;
        }
        if (event == 'sync') {
          syncTick++;
          notifyListeners();
          return;
        }
        _indexDirty = true;
        _dataRevision++;
        _reloadRequested = true;
        if (!_foreground) return;
        // A fixed window merges provider bursts without starving live updates.
        _changeTimer ??= Timer(const Duration(milliseconds: 120), () {
          _changeTimer = null;
          unawaited(refresh(silent: true));
        });
      },
      onError: (Object value) {
        error = messageError(value);
        notifyListeners();
      },
    );
    unawaited(refresh());
  }

  void setForeground(bool value) {
    if (_disposed || _foreground == value) return;
    _foreground = value;
    if (!value) {
      _changeTimer?.cancel();
      _changeTimer = null;
      _debounce?.cancel();
      _reloadRequested = true;
    } else {
      // Also catches messages received while the activity/event sink was gone.
      unawaited(refresh(silent: true));
    }
  }

  void search(String value) {
    if (_disposed || query == value) return;
    query = value;
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      _applyLocalFilter();
      unawaited(_requestRefresh(reload: false));
    } else {
      _debounce = Timer(const Duration(milliseconds: 240), () {
        unawaited(_requestRefresh(reload: false));
      });
    }
    notifyListeners();
  }

  void setFilter(String value) {
    if (_disposed || filter == value) return;
    filter = value;
    if (query.trim().isEmpty) _applyLocalFilter();
    unawaited(_requestRefresh(reload: false));
    notifyListeners();
  }

  void _applyLocalFilter() {
    threads = allThreads
        .where((thread) => _matchesFilter(thread, filter))
        .toList(growable: false);
  }

  Future<void> refresh({bool silent = false}) {
    _indexDirty = true;
    _dataRevision++;
    _changeTimer?.cancel();
    _changeTimer = null;
    return _requestRefresh(reload: true, silent: silent);
  }

  Future<void> _requestRefresh({required bool reload, bool silent = true}) {
    if (_disposed) return Future<void>.value();
    _reloadRequested |= reload;
    _viewRequested = true;
    if (!_foreground) return Future<void>.value();
    if (!silent) {
      loading = true;
      notifyListeners();
    }
    // Every caller awaits the same drain, including changes queued mid-query.
    if (_refreshFuture != null) return _refreshFuture!;
    final completion = Completer<void>();
    _refreshFuture = completion.future;
    unawaited(_drainRefreshes(completion));
    return completion.future;
  }

  Future<void> _drainRefreshes(Completer<void> completion) async {
    try {
      while (_viewRequested && !_disposed && _foreground) {
        _viewRequested = false;
        final reload = _reloadRequested || lastLoaded == null;
        _reloadRequested = false;
        try {
          if (reload) {
            final nextAccess = await repository.access();
            if (_disposed || !_foreground) break;
            access = nextAccess;
            if (!nextAccess.ready) {
              threads = const [];
              allThreads = const [];
              sims = const [];
              lastLoaded = null;
              error = null;
              continue;
            }
            final rows = await repository.conversations(filter: 'everything');
            if (_disposed || !_foreground) break;
            final analyzed = await repository.analyzeThreads(rows);
            if (_disposed || !_foreground) break;
            final nextSims = await repository.subscriptions();
            if (_disposed || !_foreground) break;
            allThreads = analyzed;
            sims = nextSims;
            lastLoaded = DateTime.now();
          }
          final requestedQuery = query.trim();
          final requestedFilter = filter;
          final next = requestedQuery.isEmpty
              ? allThreads
                    .where((thread) => _matchesFilter(thread, requestedFilter))
                    .toList(growable: false)
              : await _searchThreads(requestedQuery, requestedFilter);
          if (_disposed || !_foreground) break;
          // A slow previous search must never overwrite a newer selection.
          if (requestedQuery != query.trim() || requestedFilter != filter) {
            _viewRequested = true;
            continue;
          }
          threads = next;
          error = null;
        } catch (value) {
          if (!_disposed) error = messageError(value);
        }
      }
    } finally {
      _refreshFuture = null;
      loading = false;
      completion.complete();
      notifyListeners();
    }
  }

  Future<List<ThreadSummary>> _searchThreads(
    String requestedQuery,
    String requestedFilter,
  ) async {
    // Native search covers message bodies; use analyzed snapshot objects when
    // available instead of analyzing the same preview for every keystroke.
    final rows = await repository.conversations(
      query: requestedQuery,
      filter: requestedFilter == 'otp' ? 'all' : requestedFilter,
    );
    if (_disposed || !_foreground) return const [];
    final byId = {for (final thread in allThreads) thread.threadId: thread};
    final direct = rows
        .map((thread) => byId[thread.threadId] ?? thread)
        .where((thread) => _matchesFilter(thread, requestedFilter))
        .toList(growable: false);
    try {
      if (!await repository.initEngine()) return direct;
      if (_disposed || !_foreground) return const [];
      if (_indexDirty) {
        final revision = _dataRevision;
        final indexed = await repository.indexSearchCorpus();
        _indexDirty = revision != _dataRevision;
        if (indexed == 0 || _disposed || !_foreground) return direct;
      }
      final hits = await repository.searchMessagesRust(
        requestedQuery,
        limit: 200,
      );
      if (hits.isEmpty || _disposed) return direct;
      final rank = <int, int>{};
      for (var index = 0; index < hits.length; index++) {
        rank.putIfAbsent(hits[index].threadId.toInt(), () => index);
      }
      final merged = <ThreadSummary>[];
      final seen = <int>{};
      for (final thread in allThreads) {
        if (rank.containsKey(thread.threadId) &&
            _matchesFilter(thread, requestedFilter)) {
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
    _changeTimer?.cancel();
    _subscription?.cancel();
    threads = const [];
    allThreads = const [];
    sims = const [];
    super.dispose();
  }
}
