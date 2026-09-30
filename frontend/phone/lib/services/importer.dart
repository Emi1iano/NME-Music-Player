import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import 'app_log.dart';
import 'library.dart';

/// What happened during one import, for the "Imported 3 songs" message.
class ImportResult {
  final int imported;   // new songs copied into the Music folder
  final int skipped;    // already in the library, or not an audio file
  final int failed;     // couldn't be copied (see the debug log)

  const ImportResult(this.imported, this.skipped, this.failed);

  bool get cancelled => imported == 0 && skipped == 0 && failed == 0;
}

/// "Import songs": lets the user pick audio files from anywhere on the phone
/// (Downloads, Drive, Files app...) and copies them into the app's Music
/// folder, so nobody needs a computer to add music.
class Importer {
  Importer._();

  /// Opens the phone's file picker, copies the chosen songs, then rescans.
  /// [onCopyStart] is called with the number of picked files once copying
  /// begins (the UI uses it to show a spinner).
  static Future<ImportResult> pickAndImport({void Function(int count)? onCopyStart}) async {
    final List<PlatformFile> picked;
    try {
      // FileType.custom + extensions (instead of FileType.audio) so formats
      // like .opus and .flac aren't hidden on some phones.
      picked = await FilePicker.pickFiles(
        dialogTitle: 'Choose songs to import',
        type: FileType.custom,
        allowedExtensions: [for (final e in audioExtensions) e.substring(1)],
      );
    } catch (e, st) {
      AppLog.instance.error('Could not open the file picker', e, st);
      return const ImportResult(0, 0, 1);
    }
    if (picked.isEmpty) return const ImportResult(0, 0, 0); // user cancelled
    onCopyStart?.call(picked.length);

    final musicDir = Library.instance.musicDir;
    var imported = 0, skipped = 0, failed = 0;

    for (final file in picked) {
      final ext = p.extension(file.name).toLowerCase();
      if (!audioExtensions.contains(ext)) {
        AppLog.instance.warning('Skipped "${file.name}": not an audio file');
        skipped++;
        continue;
      }
      // Imported songs go straight into the Music folder, keeping their name.
      // A file with the same name and size is treated as already imported.
      final target = File(p.join(musicDir.path, file.name));
      if (target.existsSync() && target.lengthSync() == (await file.length())) {
        skipped++;
        continue;
      }
      final dest = target.existsSync() ? _freeName(target) : target;
      try {
        // Copy in chunks (a stream) so big files don't fill up the memory.
        final sink = dest.openWrite();
        await sink.addStream(file.readAsByteStream());
        await sink.close();
        imported++;
      } catch (e, st) {
        AppLog.instance.error('Could not import "${file.name}"', e, st);
        if (dest.existsSync()) dest.deleteSync(); // don't leave half a file
        failed++;
      }
    }

    AppLog.instance.info('Import: $imported new, $skipped skipped, $failed failed');
    if (imported > 0) await Library.instance.scan(); // show the new songs
    return ImportResult(imported, skipped, failed);
  }

  /// "song.mp3" is taken by a different file -> "song (2).mp3", "song (3).mp3"...
  static File _freeName(File taken) {
    final dir = p.dirname(taken.path);
    final base = p.basenameWithoutExtension(taken.path);
    final ext = p.extension(taken.path);
    for (var n = 2;; n++) {
      final candidate = File(p.join(dir, '$base ($n)$ext'));
      if (!candidate.existsSync()) return candidate;
    }
  }
}
