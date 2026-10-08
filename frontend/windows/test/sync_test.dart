import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nme/services/sync_engine.dart';

/// Same protocol as backend/server: pairs two clients that send the same
/// 8-byte key and tells each one the other's IPv4 address and port.
Future<RawDatagramSocket> fakeServer() async {
  final srv = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
  final waiting = <String, Datagram>{};
  Uint8List addr(Datagram d) =>
      Uint8List.fromList([...d.address.rawAddress, d.port >> 8, d.port & 0xff]);
  // Windows drops a send while the previous one is pending, so retry.
  final out = <(List<int>, InternetAddress, int)>[];
  void flush() {
    while (out.isNotEmpty && srv.send(out.first.$1, out.first.$2, out.first.$3) > 0) {
      out.removeAt(0);
    }
    if (out.isNotEmpty) srv.writeEventsEnabled = true;
  }

  void send(List<int> b, InternetAddress a, int port) {
    out.add((b, a, port));
    flush();
  }

  srv.listen((e) {
    if (e == RawSocketEvent.write) flush();
    if (e != RawSocketEvent.read) return;
    for (var d = srv.receive(); d != null; d = srv.receive()) {
      if (d.data.length != 8) continue;
      final key = ascii.decode(d.data);
      final other = waiting.remove(key);
      if (other == null || other.port == d.port) {
        waiting[key] = d;
        continue;
      }
      send(addr(other), d.address, d.port);
      send(addr(d), other.address, other.port);
    }
  });
  return srv;
}

void main() {
  late Directory tmp, a, b;
  late RawDatagramSocket srv;
  final big = Uint8List.fromList(List.generate(700 * 1024 + 3, (_) => Random(1).nextInt(256)));

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('nme_sync');
    a = await Directory('${tmp.path}/a').create();
    b = await Directory('${tmp.path}/b').create();
    srv = await fakeServer();
    await File('${a.path}/only_a.mp3').writeAsString('song from a');
    await File('${a.path}/shared.mp3').writeAsString('a copy');
    await Directory('${b.path}/rock').create();
    await File('${b.path}/rock/big.flac').writeAsBytes(big);
    await File('${b.path}/shared.mp3').writeAsString('b copy');
    await File('${b.path}/deleted.mp3').writeAsString('deleted on a');
    await File('${b.path}/notes.txt').writeAsString('not audio');
    await File('${b.path}/empty.wav').writeAsBytes([]);
  });

  tearDown(() async {
    srv.close();
    await tmp.delete(recursive: true);
  });

  Future<List<String>> syncBoth({Set<String> skipOnA = const {}}) async {
    final sw = Stopwatch()..start();
    final r = await Future.wait([
        SyncSession(
          folder: a.path,
          key: '12345678',
          server: InternetAddress.loopbackIPv4,
          serverPort: srv.port,
          skip: skipOnA,
        ).run(),
        SyncSession(
          folder: b.path,
          key: '12345678',
          server: InternetAddress.loopbackIPv4,
          serverPort: srv.port,
        ).run(),
      ]);
    printOnFailure('sync took ${sw.elapsedMilliseconds}ms: $r');
    return r;
  }

  test('both devices get the songs they are missing, skipping deleted ones', () async {
    await syncBoth(skipOnA: {'deleted.mp3'});

    expect(await scanFolder(a.path), ['empty.wav', 'only_a.mp3', 'rock/big.flac', 'shared.mp3']);
    expect(await File('${a.path}/rock/big.flac').readAsBytes(), big);
    expect(await File('${a.path}/empty.wav').length(), 0);
    expect(await File('${a.path}/shared.mp3').readAsString(), 'a copy'); // not overwritten
    expect(File('${a.path}/notes.txt').existsSync(), isFalse); // only audio syncs
    expect(await File('${b.path}/only_a.mp3').readAsString(), 'song from a');
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('resync without the skip downloads the deleted song', () async {
    await syncBoth(skipOnA: {'deleted.mp3'});
    expect(File('${a.path}/deleted.mp3').existsSync(), isFalse);

    final results = await syncBoth();
    expect(await File('${a.path}/deleted.mp3').readAsString(), 'deleted on a');
    expect(results.first, contains('received 1'));
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('unsafe paths are rejected', () {
    for (final p in ['../x.mp3', '/x.mp3', 'C:/x.mp3', r'a\x.mp3', 'a//x.mp3', 'a/./x.mp3', '']) {
      expect(isSafeRelPath(p), isFalse, reason: p);
    }
    expect(isSafeRelPath('rock/Ember Light.mp3'), isTrue);
  });
}
