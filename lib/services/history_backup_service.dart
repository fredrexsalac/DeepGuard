import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:file_picker/file_picker.dart';

import '../models/history_entry.dart';
import '../models/user_profile.dart';
import 'profile_service.dart';

/// Outcome of a backup import, worded so it can be shown to the user verbatim.
class BackupImportResult {
  /// True when the user dismissed the file picker without choosing anything.
  final bool cancelled;

  /// True when the file was accepted and restored (even if partially).
  final bool ok;

  /// Short human sentence describing what happened.
  final String message;

  /// Profiles created by the restore.
  final int profilesAdded;

  /// History records restored.
  final int recordsAdded;

  /// Records that were already on the device and skipped (no duplicates).
  final int recordsSkipped;

  const BackupImportResult({
    required this.cancelled,
    required this.ok,
    required this.message,
    this.profilesAdded = 0,
    this.recordsAdded = 0,
    this.recordsSkipped = 0,
  });

  factory BackupImportResult.cancelled() => const BackupImportResult(
        cancelled: true,
        ok: false,
        message: 'Import cancelled — nothing was changed.',
      );

  factory BackupImportResult.failure(String why) => BackupImportResult(
        cancelled: false,
        ok: false,
        message: why,
      );
}

/// HistoryBackupService
///
/// Exports every profile, its analysis history and the frozen provenance /
/// source-trace snapshots into ONE readable JSON file, and restores them again.
///
/// WHY THIS EXISTS
/// All app data lives in SharedPreferences, which Android deletes on uninstall.
/// So a user who removes the app loses the whole analysis history. The export
/// keeps a copy outside the app, and the import puts it back after a reinstall —
/// additively, so importing twice can never duplicate or overwrite records.
///
/// WHAT A BACKUP DOES NOT CONTAIN
/// The analysed photo/video files themselves are NOT embedded (that would make
/// the file huge and would copy media the app does not own). After a fresh
/// install the restored records therefore show their verdict, confidence, date
/// and provenance snapshot, but their media preview needs re-analysis. This is
/// stated in the file itself and in the import message, never glossed over.
class HistoryBackupService {
  static final HistoryBackupService _instance =
      HistoryBackupService._internal();
  factory HistoryBackupService() => _instance;
  HistoryBackupService._internal();

  /// Marker checked on import so a random JSON file is never treated as data.
  static const String formatTag = 'deepguard-backup';

  /// Bump when the backup layout changes incompatibly.
  static const int schemaVersion = 1;

  final ProfileService _profiles = ProfileService();

  // ── Export ─────────────────────────────────────────────────────────────────

  /// Builds the backup document in memory (also used by tests).
  Future<Map<String, dynamic>> buildBackup() async {
    final profileJson = <Map<String, dynamic>>[];
    final historyJson = <String, dynamic>{};
    var totalRecords = 0;

    for (final profile in _profiles.profiles) {
      profileJson.add(profile.toJson());
      final entries = await _profiles.getHistory(profile.id);
      totalRecords += entries.length;
      historyJson[profile.id] = entries.map((e) => e.toJson()).toList();
    }

    return <String, dynamic>{
      'format': formatTag,
      'schemaVersion': schemaVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'activeProfileId': _profiles.activeProfile?.id,
      // Human-readable tally, so the file can be eyeballed without a parser.
      'summary': {
        'profiles': profileJson.length,
        'records': totalRecords,
        'note': 'Analysis records and provenance snapshots only. The media '
            'files themselves are NOT included; after restoring on a new '
            'install their previews must be re-analysed.',
      },
      'profiles': profileJson,
      'history': historyJson,
    };
  }

  /// Suggested file name for an export: deepguard_backup_20261021_1530.json
  String suggestedFileName([DateTime? at]) {
    final d = at ?? DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'deepguard_backup_${d.year}${two(d.month)}${two(d.day)}'
        '_${two(d.hour)}${two(d.minute)}.json';
  }

  /// Asks the user where to save, writes the backup, and returns the path.
  /// Returns null when the user cancels. Throws [StateError] with a readable
  /// message when the write could not be completed.
  Future<String?> exportBackup() async {
    final doc = await buildBackup();
    // Indented so the exported file doubles as a readable report of the data.
    final text = const JsonEncoder.withIndent('  ').convert(doc);
    final fileName = suggestedFileName();

    final saved = await FilePicker.platform.saveFile(
      dialogTitle: 'Export DeepGuard data',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const ['json'],
      // Passing bytes lets the plugin write the file directly through the
      // system picker on Android, which needs no storage permission.
      bytes: utf8.encode(text),
    );
    if (saved == null) {
      dev.log('[HistoryBackup] Export cancelled by user', name: 'DeepGuard');
      return null;
    }

    // Some platforms return a destination without writing the bytes, so the
    // file is written here for those. On Android/iOS the plugin already wrote
    // the bytes supplied above, and the string it returns can be a content://
    // URI that File() cannot open — poking at it would report a save that
    // actually succeeded as a failure.
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      try {
        final f = File(saved);
        if (!await f.exists()) {
          await f.create(recursive: true);
          await f.writeAsString(text);
        }
      } on FileSystemException catch (e) {
        dev.log('[HistoryBackup] Export write failed: ${e.message}',
            name: 'DeepGuard');
        throw StateError('Backup was not written to a readable location '
            '(${e.message}). Try a different folder.');
      }
    }

    dev.log(
      '[HistoryBackup] Exported ${doc['summary']} to $saved',
      name: 'DeepGuard',
    );
    return saved;
  }

  // ── Import ─────────────────────────────────────────────────────────────────

  /// Asks the user for a backup file and restores it additively.
  Future<BackupImportResult> importBackup() async {
    FilePickerResult? picked;
    try {
      picked = await FilePicker.platform.pickFiles(
        dialogTitle: 'Restore DeepGuard data',
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
      );
    } on Exception catch (e) {
      return BackupImportResult.failure('Could not open the file picker '
          '(${e.runtimeType}).');
    }
    if (picked == null || picked.files.isEmpty) {
      return BackupImportResult.cancelled();
    }

    final file = picked.files.first;
    String text;
    if (file.bytes != null) {
      text = utf8.decode(file.bytes!, allowMalformed: true);
    } else if (file.path != null) {
      try {
        text = await File(file.path!).readAsString();
      } on FileSystemException catch (e) {
        return BackupImportResult.failure(
            'The selected file could not be read (${e.osError?.message ?? e.message}).');
      }
    } else {
      return BackupImportResult.failure(
          'The selected file could not be read.');
    }

    return importFromJsonText(text);
  }

  /// Restores from already-read JSON (kept separate so it is testable).
  Future<BackupImportResult> importFromJsonText(String text) async {
    final dynamic decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException catch (e) {
      return BackupImportResult.failure(
          'That file is not valid JSON (${e.message}).');
    }
    if (decoded is! Map) {
      return BackupImportResult.failure(
          'That file is not a DeepGuard backup (expected an object at the top '
          'level).');
    }
    if (decoded['format'] != formatTag) {
      return BackupImportResult.failure(
          'That file is not a DeepGuard backup — it has no "format": '
          '"$formatTag" marker, so nothing was restored.');
    }
    final version = (decoded['schemaVersion'] as num?)?.toInt() ?? 0;
    if (version > schemaVersion) {
      return BackupImportResult.failure(
          'That backup came from a newer DeepGuard version (schema $version > '
          '$schemaVersion). Update the app, then import again.');
    }

    final historyJson = decoded['history'];
    if (decoded['profiles'] is! List || historyJson is! Map) {
      return BackupImportResult.failure(
          'That backup file is incomplete (no profiles or history section) — '
          'nothing was restored.');
    }

    var profilesAdded = 0;
    var recordsAdded = 0;
    var recordsSkipped = 0;

    // 1. Profiles: add only the ones this device does not already have.
    final restoredIds = <String>{};
    for (final item in (decoded['profiles'] as List)) {
      if (item is! Map) continue;
      try {
        final profile =
            UserProfile.fromJson(Map<String, dynamic>.from(item));
        restoredIds.add(profile.id);
        if (await _profiles.ensureProfile(profile)) profilesAdded++;
      } catch (e) {
        dev.log('[HistoryBackup] Skipped unreadable profile: $e',
            name: 'DeepGuard');
      }
    }

    // 2. History: merge by entry id, so re-importing is a no-op.
    var profilesWithHistory = 0;
    for (final key in historyJson.keys) {
      final profileId = key.toString();
      final value = historyJson[key];
      if (value is! List) continue;
      final entries = <HistoryEntry>[];
      for (final item in value) {
        if (item is! Map) continue;
        try {
          entries.add(HistoryEntry.fromJson(Map<String, dynamic>.from(item)));
        } catch (e) {
          dev.log('[HistoryBackup] Skipped unreadable record: $e',
              name: 'DeepGuard');
        }
      }
      if (entries.isEmpty) continue;
      // A profile whose own entry was unreadable would leave these records
      // orphaned, so they are reported as skipped instead of being invented
      // onto some other profile.
      final known = _profiles.profiles.any((p) => p.id == profileId) ||
          restoredIds.contains(profileId);
      if (!known) {
        recordsSkipped += entries.length;
        dev.log('[HistoryBackup] Orphan history for $profileId — skipped',
            name: 'DeepGuard');
        continue;
      }
      final added = await _profiles.restoreHistory(profileId, entries);
      recordsAdded += added;
      recordsSkipped += entries.length - added;
      if (added > 0) profilesWithHistory++;
    }

    // 3. Put the user back on the profile they were using when exporting.
    final activeId = decoded['activeProfileId']?.toString();
    if (activeId != null) {
      await _profiles.setActiveProfileIfPresent(activeId);
    }

    final exportedAt = decoded['exportedAt']?.toString() ?? 'an earlier backup';
    final message = recordsAdded == 0
        ? 'Nothing new to restore — every record in this backup (exported '
            '$exportedAt) is already on this device.'
        : 'Restored $recordsAdded record(s) under $profilesWithHistory '
            'profile(s)'
            '${profilesAdded > 0 ? ', created $profilesAdded profile(s)' : ''}'
            '${recordsSkipped > 0 ? ', skipped $recordsSkipped duplicate(s)' : ''}'
            '. A backup holds records only, not the analysed media files, so '
            'previews need re-analysis.';

    dev.log(
      '[HistoryBackup] Import done profiles+$profilesAdded records+$recordsAdded '
      'skipped+$recordsSkipped',
      name: 'DeepGuard',
    );

    return BackupImportResult(
      cancelled: false,
      ok: true,
      message: message,
      profilesAdded: profilesAdded,
      recordsAdded: recordsAdded,
      recordsSkipped: recordsSkipped,
    );
  }
}
