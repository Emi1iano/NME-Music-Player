// Picks the FFI implementation on desktop and a stub on web.
export 'sync_outcome.dart';
export 'sync_stub.dart' if (dart.library.io) 'sync_io.dart';
