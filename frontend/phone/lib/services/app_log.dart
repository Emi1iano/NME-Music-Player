import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum LogLevel { info, warning, error }

/// One line in the debug log.
class LogEntry {
  final DateTime time;
  final LogLevel level;
  final String message;
  final String? details; // e.g. the error and stack trace

  LogEntry(this.level, this.message, [this.details]) : time = DateTime.now();

  // Turns an entry into text like "14:05:09 ERROR  Could not play ..."
  String format() {
    String two(int n) => n.toString().padLeft(2, '0');
    final t = '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
    final tag = switch (level) {
      LogLevel.info => 'INFO ',
      LogLevel.warning => 'WARN ',
      LogLevel.error => 'ERROR',
    };
    return details == null ? '$t $tag $message' : '$t $tag $message\n$details';
  }
}

/// The in-app debug log (Settings → Debug log).
///
/// Records what the app is doing plus any errors or crashes, so a tester can
/// tap "Share" and send it to the team. It's saved to a file after every
/// error, so even if the app crashes the log from that run is still there
/// the next time the app opens.
class AppLog extends ChangeNotifier {
  // Singleton: one shared log (AppLog.instance).
  AppLog._();
  static final AppLog instance = AppLog._();

  static const _maxEntries = 500; // older lines are dropped

  final List<LogEntry> _entries = [];
  List<String> _previousRun = []; // log text saved by the last time the app ran
  File? _file;
  Timer? _saveTimer;
  String _appInfo = '';

  List<LogEntry> get entries => List.unmodifiable(_entries);
  List<String> get previousRun => _previousRun;
  int get errorCount => _entries.where((e) => e.level == LogLevel.error).length;

  /// Loads the last run's log, then starts a new one.
  Future<void> init() async {
    try {
      final dir = await getApplicationSupportDirectory();
      _file = File(p.join(dir.path, 'debug_log.txt'));
      if (await _file!.exists()) {
        _previousRun = await _file!.readAsLines();
      }
      final info = await PackageInfo.fromPlatform();
      _appInfo = '${info.appName} ${info.version} (build ${info.buildNumber})';
    } catch (e) {
      _appInfo = 'unknown version';
    }
    info('App started: $_appInfo on ${Platform.operatingSystem} '
        '${Platform.operatingSystemVersion}');
  }

  void info(String message) => _add(LogEntry(LogLevel.info, message));

  void warning(String message, [Object? error]) =>
      _add(LogEntry(LogLevel.warning, message, error?.toString()));

  void error(String message, Object error, [StackTrace? stack]) {
    // Keep stack traces short; the top lines are the useful part.
    final trace = stack?.toString().split('\n').take(12).join('\n');
    _add(LogEntry(LogLevel.error, message, trace == null ? '$error' : '$error\n$trace'));
    _save(); // save errors right away in case the app is about to crash
  }

  void clear() {
    _entries.clear();
    _previousRun = [];
    notifyListeners();
    _save();
  }

  /// The whole log as text, with device info at the top: what gets shared.
  String export() {
    final buffer = StringBuffer()
      ..writeln('NME Music debug log')
      ..writeln('App: $_appInfo')
      ..writeln('Device: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}')
      ..writeln('Exported: ${DateTime.now()}')
      ..writeln('Errors this run: $errorCount')
      ..writeln();
    if (_previousRun.isNotEmpty) {
      buffer
        ..writeln('--- Previous run ---')
        ..writeln(_previousRun.join('\n'))
        ..writeln()
        ..writeln('--- This run ---');
    }
    for (final e in _entries) {
      buffer.writeln(e.format());
    }
    return buffer.toString();
  }

  void _add(LogEntry entry) {
    _entries.add(entry);
    if (_entries.length > _maxEntries) _entries.removeAt(0);
    // Also print to the console, so `flutter run` / adb logcat show it live.
    debugPrint('[NME] ${entry.format()}');
    notifyListeners();
    // Normal events are saved in batches, at most every 5 seconds.
    _saveTimer ??= Timer(const Duration(seconds: 5), _save);
  }

  /// Save to disk now (used before risky calls like native backend code).
  Future<void> flush() => _save();

  Future<void> _save() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    final file = _file;
    if (file == null) return;
    try {
      await file.writeAsString(_entries.map((e) => e.format()).join('\n'));
    } catch (_) {
      // Nowhere left to report a failure to save the log itself.
    }
  }
}
