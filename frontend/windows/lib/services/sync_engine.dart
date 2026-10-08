// Peer-to-peer song sync over UDP, using the Zig server (backend/server) only
// to pair two devices that send it the same 8-digit key.
//
// Flow:
//   1. Send the key to the server every 2s until it replies with the other
//      device's address (4 bytes IPv4 + 2 bytes big-endian port).
//   2. Punch through NAT by sending a few packets straight to the peer.
//   3. Fetch the peer's song list, then download every song we don't have
//      (and that isn't in `skip`). Both devices do this at the same time.
//   4. Tell the peer we're done and keep serving until it is done too.
//
// Packets between peers (first byte is the type):
//   'P'                                        keep-alive / NAT punch
//   'Q' u16 nameLen, name, u16 n, n x u32       request chunks of a blob
//   'D' u16 nameLen, name, u32 idx, u32 total, data   one chunk of a blob
//   'F'                                        finished downloading
// A blob is a song path, or "" for the JSON list of the sender's songs.
// Downloads are pull-based: lost packets are simply requested again.
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

const audioExtensions = {'.mp3', '.flac', '.wav', '.m4a', '.aac', '.ogg', '.opus', '.wma'};

const _tPunch = 0x50; // P
const _tRequest = 0x51; // Q
const _tData = 0x44; // D
const _tDone = 0x46; // F

const _chunk = 1024; // file bytes per data packet
const _perRequest = 64; // chunk indices per request packet
const _minWindow = 16, _maxWindow = 1024; // chunks requested per round
const _maxChunks = 1 << 20; // 1 GiB per file
const _round = Duration(milliseconds: 500); // max wait per round
const _idle = Duration(milliseconds: 60); // round ends early once data stops
const _peerTimeout = Duration(seconds: 20);
const _pairTimeout = Duration(minutes: 2);

/// True for a relative path with '/' separators that stays inside the folder.
bool isSafeRelPath(String p) {
  if (p.isEmpty || p.length > 300) return false;
  if (p.startsWith('/') || p.contains('\\') || p.contains(':')) return false;
  if (p.codeUnits.any((c) => c < 32)) return false;
  return p.split('/').every((s) => s.isNotEmpty && s != '.' && s != '..');
}

bool isAudio(String p) {
  final dot = p.lastIndexOf('.');
  return dot >= 0 && audioExtensions.contains(p.substring(dot).toLowerCase());
}

/// Audio files under [folder], as sorted relative paths with '/' separators.
Future<List<String>> scanFolder(String folder) async {
  final dir = Directory(folder.replaceAll(RegExp(r'[\\/]+$'), ''));
  if (!await dir.exists()) return [];
  final out = <String>[];
  await for (final e in dir.list(recursive: true, followLinks: false)) {
    if (e is! File) continue;
    final rel = e.path.substring(dir.path.length + 1).replaceAll('\\', '/');
    if (isAudio(rel) && isSafeRelPath(rel)) out.add(rel);
  }
  return out..sort();
}

class _Incoming {
  _Incoming(this.write);
  final void Function(int idx, Uint8List data) write;
  int? total;
  final got = <int>{};
  var pending = <int>{};
  var round = Completer<void>();
  DateTime? lastData; // last chunk received this round
}

class SyncSession {
  SyncSession({
    required this.folder,
    required this.key,
    required this.server,
    required this.serverPort,
    this.skip = const {},
    this.onStatus,
  });

  final String folder, key;
  final InternetAddress server;
  final int serverPort;

  /// Songs not to download (ones the user deleted).
  final Set<String> skip;
  final void Function(String)? onStatus;

  late RawDatagramSocket _s;
  InternetAddress? _peer;
  int _peerPort = 0;
  final _paired = Completer<void>();
  final _mine = <String>{};
  late Uint8List _list;
  final _incoming = <String, _Incoming>{};
  final _served = <String>{};
  final _readers = <String, RandomAccessFile>{};
  DateTime _lastHeard = DateTime.now();
  bool _peerDone = false;
  int _window = 128; // grows while rounds arrive intact, halves on loss
  final _out = Queue<(List<int>, InternetAddress, int)>();

  /// Runs one full sync and returns a summary. Throws on timeout.
  Future<String> run() async {
    _mine.addAll(await scanFolder(folder));
    _list = utf8.encode(jsonEncode(_mine.toList()));
    _s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    _growBuffers();
    _s.listen((ev) {
      if (ev == RawSocketEvent.write) _flush();
      if (ev != RawSocketEvent.read) return;
      for (var d = _s.receive(); d != null; d = _s.receive()) {
        _onPacket(d);
      }
    });
    Timer? keepAlive;
    try {
      await _pair();
      keepAlive = Timer.periodic(const Duration(seconds: 1), (_) => _send([_tPunch]));

      _status('Connected - exchanging song lists...');
      final theirs = jsonDecode(utf8.decode(await _fetchBytes(''))) as List;
      final want = [
        for (final p in theirs)
          if (p is String && isSafeRelPath(p) && isAudio(p) && !_mine.contains(p) && !skip.contains(p)) p
      ];
      for (var i = 0; i < want.length; i++) {
        _status('Downloading ${i + 1}/${want.length}: ${want[i]}');
        await _fetchFile(want[i]);
      }

      _status('Finishing up...');
      await _finish();
      return 'Synced: received ${want.length}, sent ${_served.length} song(s)';
    } finally {
      keepAlive?.cancel();
      _s.close();
      for (final r in _readers.values) {
        r.closeSync();
      }
    }
  }

  // Default UDP buffers (64 KB on Windows) drop most of a burst; ask for 2 MB.
  void _growBuffers() {
    final bsd = Platform.isWindows || Platform.isMacOS || Platform.isIOS;
    for (final opt in [bsd ? 0x1002 : 8, bsd ? 0x1001 : 7]) { // SO_RCVBUF, SO_SNDBUF
      try {
        _s.setRawOption(RawSocketOption.fromInt(RawSocketOption.levelSocket, opt, 2 << 20));
      } catch (_) {}
    }
  }

  void _status(String m) => onStatus?.call(m);

  void _send(List<int> b) => _sendTo(b, _peer!, _peerPort);

  // On Windows send() returns 0 while an earlier send is still pending, which
  // silently drops back-to-back packets. Queue them and retry when writable.
  void _sendTo(List<int> b, InternetAddress to, int port) {
    _out.add((b, to, port));
    _flush();
  }

  void _flush() {
    while (_out.isNotEmpty) {
      final (b, to, port) = _out.first;
      if (_s.send(b, to, port) == 0) {
        _s.writeEventsEnabled = true;
        return;
      }
      _out.removeFirst();
    }
  }

  Future<void> _pair() async {
    _status('Waiting for your other device to sync with key $key...');
    final deadline = DateTime.now().add(_pairTimeout);
    while (!_paired.isCompleted) {
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('no other device synced with this key');
      }
      _sendTo(ascii.encode(key), server, serverPort);
      await _paired.future.timeout(const Duration(seconds: 2), onTimeout: () {});
    }
    for (var i = 0; i < 5; i++) {
      _send([_tPunch]);
      await Future.delayed(const Duration(milliseconds: 100));
    }
    _lastHeard = DateTime.now();
  }

  void _onPacket(Datagram d) {
    final b = d.data;
    if (_peer == null) {
      if (d.address.address == server.address && d.port == serverPort && b.length == 6) {
        _peer = InternetAddress.fromRawAddress(b.sublist(0, 4));
        _peerPort = (b[4] << 8) | b[5];
        _paired.complete();
      }
      return;
    }
    if (d.address.address != _peer!.address || d.port != _peerPort || b.isEmpty) return;
    _lastHeard = DateTime.now();
    try {
      switch (b[0]) {
        case _tRequest:
          _onRequest(b);
        case _tData:
          _onData(b);
        case _tDone:
          _peerDone = true;
      }
    } on RangeError {
      // Truncated or malformed packet: ignore it.
    }
  }

  Uint8List _packet(int type, String name, int extra) {
    final n = utf8.encode(name);
    final out = Uint8List(3 + n.length + extra);
    out[0] = type;
    out[1] = n.length >> 8;
    out[2] = n.length & 0xff;
    out.setRange(3, 3 + n.length, n);
    return out;
  }

  (String, int) _readName(Uint8List b) {
    final len = (b[1] << 8) | b[2];
    return (utf8.decode(b.sublist(3, 3 + len), allowMalformed: true), 3 + len);
  }

  void _sendRequest(String name, List<int> idx) {
    final out = _packet(_tRequest, name, 2 + 4 * idx.length);
    final bd = ByteData.sublistView(out);
    final o = out.length - 4 * idx.length - 2;
    bd.setUint16(o, idx.length);
    for (var i = 0; i < idx.length; i++) {
      bd.setUint32(o + 2 + 4 * i, idx[i]);
    }
    _send(out);
  }

  void _onRequest(Uint8List b) {
    final (name, o) = _readName(b);
    RandomAccessFile? f;
    int size;
    if (name.isEmpty) {
      size = _list.length;
    } else {
      // Only serve files from our own list, never an arbitrary path.
      if (!_mine.contains(name)) return;
      _served.add(name);
      f = _readers[name] ??= File('$folder/$name').openSync();
      size = f.lengthSync();
    }
    final total = max(1, (size + _chunk - 1) ~/ _chunk);
    final bd = ByteData.sublistView(b);
    final count = bd.getUint16(o);
    for (var i = 0; i < count; i++) {
      final idx = bd.getUint32(o + 2 + 4 * i);
      if (idx >= total) continue;
      final start = idx * _chunk, end = min(size, start + _chunk);
      final Uint8List data;
      if (f == null) {
        data = _list.sublist(start, end);
      } else {
        f.setPositionSync(start);
        data = f.readSync(end - start);
      }
      final out = _packet(_tData, name, 8 + data.length);
      final p = out.length - 8 - data.length;
      ByteData.sublistView(out)
        ..setUint32(p, idx)
        ..setUint32(p + 4, total);
      out.setRange(p + 8, out.length, data);
      _send(out);
    }
  }

  void _onData(Uint8List b) {
    final (name, o) = _readName(b);
    final inc = _incoming[name];
    if (inc == null) return;
    final bd = ByteData.sublistView(b);
    final idx = bd.getUint32(o), total = bd.getUint32(o + 4);
    final data = b.sublist(o + 8);
    if (total == 0 || total > _maxChunks || idx >= total || data.length > _chunk) return;
    inc.total ??= total;
    if (inc.total != total || !inc.got.add(idx)) return;
    inc.write(idx, data);
    inc.lastData = DateTime.now();
    inc.pending.remove(idx);
    if (inc.pending.isEmpty && !inc.round.isCompleted) inc.round.complete();
  }

  /// Requests every chunk of [name] until all have arrived.
  Future<void> _fetch(String name, void Function(int idx, Uint8List data) write) async {
    final inc = _incoming[name] = _Incoming(write);
    try {
      while (true) {
        if (DateTime.now().difference(_lastHeard) > _peerTimeout) {
          throw TimeoutException('lost connection to the other device');
        }
        final t = inc.total;
        final ask = <int>[];
        if (t == null) {
          ask.add(0); // first chunk tells us the total
        } else {
          for (var i = 0; i < t && ask.length < _window; i++) {
            if (!inc.got.contains(i)) ask.add(i);
          }
          if (ask.isEmpty) return;
        }
        inc.pending = ask.toSet();
        inc.round = Completer();
        inc.lastData = null;
        final start = DateTime.now();
        for (var i = 0; i < ask.length; i += _perRequest) {
          _sendRequest(name, ask.sublist(i, min(i + _perRequest, ask.length)));
        }
        // Wait for the round, but stop early if data arrived and then dried up
        // (the rest was lost and will be requested again).
        while (!inc.round.isCompleted) {
          await inc.round.future.timeout(const Duration(milliseconds: 20), onTimeout: () {});
          final now = DateTime.now(), last = inc.lastData;
          if (now.difference(start) > _round) break;
          if (last != null && now.difference(last) > _idle) break;
        }
        if (t != null) {
          final lost = inc.pending.length;
          _window = lost * 10 > ask.length
              ? max(_minWindow, _window ~/ 2)
              : min(_maxWindow, _window + 64);
        }
      }
    } finally {
      _incoming.remove(name);
    }
  }

  Future<Uint8List> _fetchBytes(String name) async {
    final parts = <int, Uint8List>{};
    await _fetch(name, (i, d) => parts[i] = d);
    final out = BytesBuilder(copy: false);
    for (var i = 0; i < parts.length; i++) {
      out.add(parts[i]!);
    }
    return out.takeBytes();
  }

  /// Downloads [path] to a .part file, then renames it into place.
  Future<void> _fetchFile(String path) async {
    final dest = File('$folder/$path');
    final part = File('${dest.path}.part');
    await part.parent.create(recursive: true);
    final raf = part.openSync(mode: FileMode.write);
    try {
      await _fetch(path, (i, d) {
        raf.setPositionSync(i * _chunk);
        raf.writeFromSync(d);
      });
    } catch (_) {
      raf.closeSync();
      await part.delete();
      rethrow;
    }
    raf.closeSync();
    await part.rename(dest.path);
  }

  /// Sends 'F' until the peer is done too, serving its requests meanwhile.
  Future<void> _finish() async {
    final start = DateTime.now();
    while (true) {
      _send([_tDone]);
      final now = DateTime.now();
      if (_peerDone && now.difference(start) > const Duration(seconds: 2)) return;
      // Peer already gone: our downloads are complete, so that's fine.
      if (now.difference(_lastHeard) > _peerTimeout) return;
      await Future.delayed(const Duration(milliseconds: 300));
    }
  }
}
