import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:qingniao/messaging/message_hub.dart';
import 'package:qingniao/messaging/models.dart';

import 'support/fixture_message_repository.dart';

class _RefreshRepository extends FixtureMessageRepository {
  final events = StreamController<String>.broadcast(sync: true);
  int fullReads = 0;
  int analyses = 0;
  int simReads = 0;
  Completer<void>? readGate;
  Completer<void>? searchGate;

  @override
  Stream<String> get changes => events.stream;

  @override
  Future<List<ThreadSummary>> conversations({
    String query = '',
    String filter = 'all',
  }) async {
    if (query.isEmpty) {
      fullReads++;
      final gate = readGate;
      readGate = null;
      await gate?.future;
    } else if (searchGate != null) {
      final gate = searchGate!;
      searchGate = null;
      await gate.future;
    }
    return super.conversations(query: query, filter: filter);
  }

  @override
  Future<List<ThreadSummary>> analyzeThreads(
    List<ThreadSummary> threads,
  ) async {
    analyses++;
    return threads;
  }

  @override
  Future<List<SimCard>> subscriptions() async {
    simReads++;
    return super.subscriptions();
  }
}

void main() {
  testWidgets('Filtering and typing reuse the loaded conversation snapshot', (
    tester,
  ) async {
    final repository = _RefreshRepository();
    final hub = MessageHub(repository)..start();
    await tester.pump();
    expect(repository.fullReads, 1);
    expect(repository.analyses, 1);

    hub.setFilter('unread');
    await tester.pump();
    expect(hub.threads.every((thread) => thread.unread > 0), isTrue);
    hub.search('验证码');
    await tester.pump(const Duration(milliseconds: 250));
    hub.search('银行');
    await tester.pump(const Duration(milliseconds: 250));
    hub.search('');
    await tester.pump();
    expect(repository.fullReads, 1);
    expect(repository.analyses, 1);
    expect(repository.simReads, 1);
    hub.dispose();
    await repository.events.close();
  });

  testWidgets(
    'Provider bursts coalesce and background changes wait for resume',
    (tester) async {
      final repository = _RefreshRepository();
      final hub = MessageHub(repository)..start();
      await tester.pump();
      for (var i = 0; i < 30; i++) {
        repository.events.add('messages');
      }
      await tester.pump(const Duration(milliseconds: 119));
      expect(repository.fullReads, 1);
      await tester.pump(const Duration(milliseconds: 1));
      expect(repository.fullReads, 2);

      hub.setForeground(false);
      for (var i = 0; i < 30; i++) {
        repository.events.add('messages');
      }
      await tester.pump(const Duration(seconds: 1));
      expect(repository.fullReads, 2);
      hub.setForeground(true);
      await tester.pump();
      expect(repository.fullReads, 3);
      hub.dispose();
      await repository.events.close();
    },
  );

  testWidgets('Concurrent refresh callers await the queued newest data', (
    tester,
  ) async {
    final repository = _RefreshRepository();
    final gate = Completer<void>();
    repository.readGate = gate;
    final hub = MessageHub(repository);
    var firstFinished = false;
    var secondFinished = false;
    unawaited(hub.refresh().then((_) => firstFinished = true));
    await tester.pump();
    unawaited(hub.refresh(silent: true).then((_) => secondFinished = true));
    await tester.pump();
    expect(firstFinished, isFalse);
    expect(secondFinished, isFalse);
    gate.complete();
    await tester.pump();
    expect(repository.fullReads, 2);
    expect(firstFinished, isTrue);
    expect(secondFinished, isTrue);
    expect(hub.loading, isFalse);
    hub.dispose();
    await repository.events.close();
  });

  testWidgets('A slow search cannot overwrite a cleared search or new filter', (
    tester,
  ) async {
    final repository = _RefreshRepository();
    final hub = MessageHub(repository)..start();
    await tester.pump();
    final gate = Completer<void>();
    repository.searchGate = gate;
    hub.search('no such sender');
    await tester.pump(const Duration(milliseconds: 250));
    hub.search('');
    hub.setFilter('pinned');
    gate.complete();
    await tester.pump();
    expect(hub.threads, isNotEmpty);
    expect(hub.threads.every((thread) => thread.pinned), isTrue);
    expect(repository.fullReads, 1);
    hub.dispose();
    await repository.events.close();
  });

  testWidgets(
    'Disposal stops pending queries before analysis and subscriptions',
    (tester) async {
      final repository = _RefreshRepository();
      final gate = Completer<void>();
      repository.readGate = gate;
      final hub = MessageHub(repository)..start();
      await tester.pump();
      hub.dispose();
      gate.complete();
      await tester.pump();
      expect(repository.analyses, 0);
      expect(repository.simReads, 0);
      expect(tester.takeException(), isNull);
      await repository.events.close();
    },
  );
}
