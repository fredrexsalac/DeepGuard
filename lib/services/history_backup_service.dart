import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../models/history_entry.dart';
import '../models/user_profile.dart';
import 'app_log.dart' as dev;
import 'evidence_vault_service.dart';
import 'evidence_zip_codec.dart';
import 'profile_service.dart';

/// Summary returned after exporting a DeepGuard Evidence Archive (`.zip`).
class BackupExportResult {
  final String savedPath;
  final int recordsCount;
  final int evidenceFilesCount;
  final int imagesCount;
  final int videosCount;

  const BackupExportResult({
    required this.savedPath,
    required this.recordsCount,
    required this.evidenceFilesCount,
    required this.imagesCount,
    required this.videosCount,
  });

  String get fileName => savedPath.replaceAll('\\', '/').split('/').last;
}

/// In-memory build product of [HistoryBackupService.buildEvidenceZip].
class EvidenceArchivePackage {
  final Uint8List zipBytes;
  final Map<String, dynamic> manifest;
  final int recordsCount;
  final int evidenceFilesCount;
  final int imagesCount;
  final int videosCount;

  const EvidenceArchivePackage({
    required this.zipBytes,
    required this.manifest,
    required this.recordsCount,
    required this.evidenceFilesCount,
    required this.imagesCount,
    required this.videosCount,
  });
}

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

  /// Analyzed image and video evidence files extracted and linked to results.
  final int evidenceRestored;

  const BackupImportResult({
    required this.cancelled,
    required this.ok,
    required this.message,
    this.profilesAdded = 0,
    this.recordsAdded = 0,
    this.recordsSkipped = 0,
    this.evidenceRestored = 0,
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

/// HistoryBackupService — DeepGuard Portable Evidence Archive (`.zip`).
///
/// Packages every profile, its analysis history, frozen provenance / framing
/// snapshots, AND the analyzed **images and videos** (treated as retained
/// forensic evidence for previous results) into a single standard `.zip`
/// archive:
///
///   - `manifest.json` (compressed UTF-8 JSON metadata & history records)
///   - `evidence/<entryId>/<originalFileName>` (lossless raw image/video bytes)
///   - `avatars/<profileId>/<avatarFileName>` (optional custom profile photo)
///
/// Backward-compatible with legacy `schemaVersion: 1` `.json` backup files so
/// previously exported backups continue to restore cleanly.
class HistoryBackupService {
  static final HistoryBackupService _instance =
      HistoryBackupService._internal();
  factory HistoryBackupService() => _instance;
  HistoryBackupService._internal();

  /// Marker checked on import so a random ZIP/JSON file is never treated as data.
  static const String formatTag = 'deepguard-backup';

  /// Manifest file name inside a DeepGuard `.zip` Evidence Archive.
  static const String manifestFileName = 'manifest.json';

  /// Schema version 2 adds `evidenceArchivePath` and `.zip` media bundling
  /// while remaining 100% compatible with schemaVersion 1 manifests.
  static const int schemaVersion = 2;

  final ProfileService _profiles = ProfileService();
  final EvidenceVaultService _vault = EvidenceVaultService();

  // ── Export ─────────────────────────────────────────────────────────────────

  /// Builds the JSON manifest document in memory (also used by unit tests).
  Future<Map<String, dynamic>> buildBackup() async {
    final pkg = await buildEvidenceZip(includeMediaBytes: false);
    return pkg.manifest;
  }

  /// Builds the complete `.zip` Evidence Archive in memory, bundling available
  /// image and video evidence files alongside `manifest.json`.
  Future<EvidenceArchivePackage> buildEvidenceZip({
    bool includeMediaBytes = true,
  }) async {
    final now = DateTime.now();
    final profileJson = <Map<String, dynamic>>[];
    final historyJson = <String, dynamic>{};
    final zipEntries = <ZipArchiveEntry>[];
    final addedArchivePaths = <String>{};

    var totalRecords = 0;
    var evidenceFilesCount = 0;
    var imagesCount = 0;
    var videosCount = 0;
    var missingMediaRecords = 0;

    for (final profile in _profiles.profiles) {
      final pMap = Map<String, dynamic>.from(profile.toJson());
      final picPath = profile.profilePicturePath;
      if (picPath != null && picPath.trim().isNotEmpty) {
        final picFile = File(picPath);
        if (picFile.existsSync()) {
          final safeProfileId = EvidenceVaultService.sanitizeSegment(
            profile.id,
            fallback: 'profile',
          );
          final safePicName = EvidenceVaultService.sanitizeSegment(
            picPath,
            fallback: 'avatar.jpg',
          );
          final avatarRelPath = 'avatars/$safeProfileId/$safePicName';
          pMap['avatarArchivePath'] = avatarRelPath;
          if (includeMediaBytes && addedArchivePaths.add(avatarRelPath)) {
            try {
              final picBytes = picFile.readAsBytesSync();
              zipEntries.add(
                ZipArchiveEntry(
                  name: avatarRelPath,
                  bytes: picBytes,
                  compress: false,
                  modifiedAt: now,
                ),
              );
            } catch (e) {
              dev.log('[HistoryBackup] Could not read profile picture: $e',
                  name: 'DeepGuard');
            }
          }
        }
      }
      profileJson.add(pMap);

      final entries = await _profiles.getHistory(profile.id);
      totalRecords += entries.length;

      final serializedEntries = <Map<String, dynamic>>[];
      for (final entry in entries) {
        final eMap = Map<String, dynamic>.from(entry.toJson());
        eMap['originalFileName'] ??= entry.fileName;

        final path = entry.filePath;
        File? mediaFile;
        if (path != null && path.trim().isNotEmpty) {
          final candidate = File(path);
          if (candidate.existsSync()) {
            mediaFile = candidate;
          }
        }

        if (mediaFile != null) {
          final safeEntryId = EvidenceVaultService.sanitizeSegment(
            entry.id,
            fallback: 'record',
          );
          final safeMediaName = EvidenceVaultService.sanitizeSegment(
            entry.fileName,
            fallback: entry.isImage ? 'evidence_image.jpg' : 'evidence_video.mp4',
          );
          final archiveRelPath = 'evidence/$safeEntryId/$safeMediaName';
          eMap['evidenceArchivePath'] = archiveRelPath;

          if (addedArchivePaths.add(archiveRelPath)) {
            if (includeMediaBytes) {
              try {
                final rawMedia = mediaFile.readAsBytesSync();
                zipEntries.add(
                  ZipArchiveEntry(
                    name: archiveRelPath,
                    bytes: rawMedia,
                    // Media formats (JPG/PNG/WEBP/MP4/MOV) are already compressed;
                    // storing raw bytes is fast and preserves forensic integrity.
                    compress: false,
                    modifiedAt: entry.timestamp,
                  ),
                );
                evidenceFilesCount++;
                if (entry.isImage) {
                  imagesCount++;
                } else {
                  videosCount++;
                }
              } catch (e) {
                eMap.remove('evidenceArchivePath');
                missingMediaRecords++;
                dev.log(
                  '[HistoryBackup] Failed reading media for ${entry.id}: $e',
                  name: 'DeepGuard',
                );
              }
            } else {
              evidenceFilesCount++;
              if (entry.isImage) {
                imagesCount++;
              } else {
                videosCount++;
              }
            }
          }
        } else {
          missingMediaRecords++;
        }

        serializedEntries.add(eMap);
      }

      historyJson[profile.id] = serializedEntries;
    }

    final manifest = <String, dynamic>{
      'format': formatTag,
      'schemaVersion': schemaVersion,
      'exportedAt': now.toIso8601String(),
      'activeProfileId': _profiles.activeProfile?.id,
      'summary': {
        'profiles': profileJson.length,
        'records': totalRecords,
        'evidenceFiles': evidenceFilesCount,
        'imagesBundled': imagesCount,
        'videosBundled': videosCount,
        'missingMediaRecords': missingMediaRecords,
        'note': 'DeepGuard Evidence Archive (.zip). Bundles profiles, '
            'analysis records, provenance snapshots, framing geometry, and '
            'retained image/video evidence files under evidence/.',
      },
      'profiles': profileJson,
      'history': historyJson,
    };

    if (!includeMediaBytes) {
      return EvidenceArchivePackage(
        zipBytes: Uint8List(0),
        manifest: manifest,
        recordsCount: totalRecords,
        evidenceFilesCount: evidenceFilesCount,
        imagesCount: imagesCount,
        videosCount: videosCount,
      );
    }

    final manifestText = const JsonEncoder.withIndent('  ').convert(manifest);
    final allEntries = <ZipArchiveEntry>[
      ZipArchiveEntry(
        name: manifestFileName,
        bytes: Uint8List.fromList(utf8.encode(manifestText)),
        compress: true,
        modifiedAt: now,
      ),
      ...zipEntries,
    ];

    final encodedZip = EvidenceZipCodec.encode(allEntries);
    return EvidenceArchivePackage(
      zipBytes: encodedZip,
      manifest: manifest,
      recordsCount: totalRecords,
      evidenceFilesCount: evidenceFilesCount,
      imagesCount: imagesCount,
      videosCount: videosCount,
    );
  }

  /// Suggested file name for an export: `deepguard_backup_20261021_1530.zip`
  String suggestedFileName([DateTime? at]) {
    final d = at ?? DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'deepguard_backup_${d.year}${two(d.month)}${two(d.day)}'
        '_${two(d.hour)}${two(d.minute)}.zip';
  }

  /// Prompts the user to save a `.zip` Evidence Archive and returns detailed
  /// export counts, or `null` when the user cancels the save picker.
  Future<BackupExportResult?> exportEvidenceArchive() async {
    final pkg = await buildEvidenceZip();
    final fileName = suggestedFileName();

    final saved = await FilePicker.platform.saveFile(
      dialogTitle: 'Export DeepGuard Evidence Archive (.zip)',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const ['zip'],
      // Passing bytes lets Android/iOS write directly through the system SAF
      // picker without requesting broad external storage permissions.
      bytes: pkg.zipBytes,
    );
    if (saved == null) {
      dev.log('[HistoryBackup] Export cancelled by user', name: 'DeepGuard');
      return null;
    }

    // Desktop file_picker implementations return a destination path without
    // writing `bytes`; write binary ZIP bytes explicitly when needed.
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      try {
        final f = File(saved);
        if (!await f.exists() || await f.length() == 0) {
          await f.create(recursive: true);
          await f.writeAsBytes(pkg.zipBytes, flush: true);
        }
      } on FileSystemException catch (e) {
        dev.log('[HistoryBackup] Export write failed: ${e.message}',
            name: 'DeepGuard');
        throw StateError(
          'Evidence archive could not be written (${e.message}). '
          'Try choosing another folder.',
        );
      }
    }

    dev.log(
      '[HistoryBackup] Exported ZIP ${pkg.manifest['summary']} to $saved',
      name: 'DeepGuard',
    );
    return BackupExportResult(
      savedPath: saved,
      recordsCount: pkg.recordsCount,
      evidenceFilesCount: pkg.evidenceFilesCount,
      imagesCount: pkg.imagesCount,
      videosCount: pkg.videosCount,
    );
  }

  /// Convenience wrapper returning the saved `.zip` path (or `null` on cancel).
  Future<String?> exportBackup() async {
    final res = await exportEvidenceArchive();
    return res?.savedPath;
  }

  // ── Import ─────────────────────────────────────────────────────────────────

  /// Prompts the user to select a DeepGuard `.zip` Evidence Archive (or legacy
  /// `.json` backup) and restores records + media evidence additively.
  Future<BackupImportResult> importBackup() async {
    FilePickerResult? picked;
    try {
      picked = await FilePicker.platform.pickFiles(
        dialogTitle: 'Restore DeepGuard Evidence Archive',
        type: FileType.custom,
        allowedExtensions: const ['zip', 'json'],
        withData: true,
      );
    } on Exception catch (e) {
      return BackupImportResult.failure(
        'Could not open the file picker (${e.runtimeType}).',
      );
    }
    if (picked == null || picked.files.isEmpty) {
      return BackupImportResult.cancelled();
    }

    final file = picked.files.first;
    Uint8List? rawBytes;

    // Prefer reading directly from `file.path` when accessible on disk so large
    // video evidence ZIPs are read reliably even if platform picker omits bytes.
    if (file.path != null) {
      try {
        final diskFile = File(file.path!);
        if (await diskFile.exists()) {
          rawBytes = await diskFile.readAsBytes();
        }
      } on FileSystemException catch (e) {
        if (file.bytes == null) {
          return BackupImportResult.failure(
            'The selected archive could not be read '
            '(${e.osError?.message ?? e.message}).',
          );
        }
      }
    }
    rawBytes ??= file.bytes;

    if (rawBytes == null) {
      return BackupImportResult.failure(
        'The selected backup file could not be read.',
      );
    }

    return importFromBytes(rawBytes, fileName: file.name);
  }

  /// Auto-detects `.zip` Evidence Archives vs legacy `.json` backups from raw
  /// file bytes and restores them additively.
  Future<BackupImportResult> importFromBytes(
    Uint8List bytes, {
    String? fileName,
  }) async {
    final looksLikeZip = EvidenceZipCodec.isZipBytes(bytes) ||
        (fileName != null && fileName.toLowerCase().endsWith('.zip'));
    if (looksLikeZip) {
      return importFromZipBytes(bytes);
    }
    final text = utf8.decode(bytes, allowMalformed: true);
    return importFromJsonText(text);
  }

  /// Extracts a DeepGuard `.zip` Evidence Archive, writes bundled images and
  /// videos into the local Evidence Vault, and restores all profiles + history.
  Future<BackupImportResult> importFromZipBytes(Uint8List zipBytes) async {
    final Map<String, Uint8List> archiveFiles;
    try {
      archiveFiles = EvidenceZipCodec.decode(zipBytes);
    } on FormatException catch (e) {
      return BackupImportResult.failure(
        'That file is not a valid DeepGuard ZIP archive (${e.message})',
      );
    } catch (e) {
      return BackupImportResult.failure(
        'Could not unpack the selected ZIP archive ($e).',
      );
    }

    // Locate `manifest.json` at root (or one folder deep if re-zipped by user).
    String? manifestKey;
    String prefix = '';
    if (archiveFiles.containsKey(manifestFileName)) {
      manifestKey = manifestFileName;
    } else {
      for (final key in archiveFiles.keys) {
        if (key.endsWith('/$manifestFileName') &&
            key.split('/').length == 2) {
          manifestKey = key;
          prefix = key.substring(0, key.length - manifestFileName.length);
          break;
        }
      }
    }

    if (manifestKey == null) {
      return BackupImportResult.failure(
        'That ZIP archive is not a DeepGuard backup — '
        '"$manifestFileName" was not found inside.',
      );
    }

    final manifestText = utf8.decode(
      archiveFiles[manifestKey]!,
      allowMalformed: true,
    );
    return _restoreDecodedManifest(
      manifestText,
      archiveFiles: archiveFiles,
      archivePrefix: prefix,
    );
  }

  /// Restores from a standalone JSON string (supports legacy `.json` backups
  /// and direct manifest tests).
  Future<BackupImportResult> importFromJsonText(String text) async {
    return _restoreDecodedManifest(text);
  }

  Uint8List? _lookupArchivePayload(
    Map<String, Uint8List>? archiveFiles,
    String archivePrefix,
    String? rawArchivePath,
  ) {
    if (archiveFiles == null ||
        rawArchivePath == null ||
        rawArchivePath.trim().isEmpty) {
      return null;
    }
    final normalized = rawArchivePath
        .replaceAll('\\', '/')
        .replaceFirst(RegExp(r'^/+'), '');
    if (normalized.contains('..')) return null;

    return archiveFiles['$archivePrefix$normalized'] ??
        archiveFiles[normalized];
  }

  Future<BackupImportResult> _restoreDecodedManifest(
    String text, {
    Map<String, Uint8List>? archiveFiles,
    String archivePrefix = '',
  }) async {
    final dynamic decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException catch (e) {
      return BackupImportResult.failure(
        'Backup manifest is not valid JSON (${e.message}).',
      );
    }
    if (decoded is! Map) {
      return BackupImportResult.failure(
        'That file is not a DeepGuard backup (expected an object at the top '
        'level).',
      );
    }
    if (decoded['format'] != formatTag) {
      return BackupImportResult.failure(
        'That file is not a DeepGuard backup — it has no "format": '
        '"$formatTag" marker, so nothing was restored.',
      );
    }
    final version = (decoded['schemaVersion'] as num?)?.toInt() ?? 0;
    if (version > schemaVersion) {
      return BackupImportResult.failure(
        'That backup came from a newer DeepGuard version (schema $version > '
        '$schemaVersion). Update the app, then import again.',
      );
    }

    final historyJson = decoded['history'];
    if (decoded['profiles'] is! List || historyJson is! Map) {
      return BackupImportResult.failure(
        'That backup file is incomplete (no profiles or history section) — '
        'nothing was restored.',
      );
    }

    final isZipArchive = archiveFiles != null;
    var profilesAdded = 0;
    var recordsAdded = 0;
    var recordsSkipped = 0;
    var evidenceRestored = 0;

    // 1. Profiles: add missing profiles and restore bundled avatars if present.
    final restoredIds = <String>{};
    for (final item in (decoded['profiles'] as List)) {
      if (item is! Map) continue;
      try {
        final pMap = Map<String, dynamic>.from(item);
        final avatarArchivePath = pMap['avatarArchivePath'] as String?;
        final avatarBytes = _lookupArchivePayload(
          archiveFiles,
          archivePrefix,
          avatarArchivePath,
        );
        if (avatarBytes != null && pMap['id'] != null) {
          try {
            final extractedAvatar = await _vault.writeExtractedAvatar(
              profileId: pMap['id'].toString(),
              fileName: avatarArchivePath!,
              bytes: avatarBytes,
            );
            pMap['profilePicturePath'] = extractedAvatar;
          } catch (e) {
            dev.log('[HistoryBackup] Could not extract avatar: $e',
                name: 'DeepGuard');
          }
        }

        final profile = UserProfile.fromJson(pMap);
        restoredIds.add(profile.id);
        if (await _profiles.ensureProfile(profile)) profilesAdded++;
      } catch (e) {
        dev.log('[HistoryBackup] Skipped unreadable profile: $e',
            name: 'DeepGuard');
      }
    }

    // 2. History & Evidence Media: merge by entry id and extract bundled media.
    var profilesWithHistory = 0;
    for (final key in historyJson.keys) {
      final profileId = key.toString();
      final value = historyJson[key];
      if (value is! List) continue;

      final known = _profiles.profiles.any((p) => p.id == profileId) ||
          restoredIds.contains(profileId);
      if (!known) {
        recordsSkipped += value.whereType<Map>().length;
        dev.log('[HistoryBackup] Orphan history for $profileId — skipped',
            name: 'DeepGuard');
        continue;
      }

      final existingForProfile = await _profiles.getHistory(profileId);
      final existingById = <String, HistoryEntry>{
        for (final e in existingForProfile) e.id: e,
      };

      final parsedEntries = <HistoryEntry>[];
      for (final item in value) {
        if (item is! Map) continue;
        try {
          final eMap = Map<String, dynamic>.from(item);
          var entry = HistoryEntry.fromJson(eMap);
          final archiveRelPath = eMap['evidenceArchivePath'] as String?;
          final mediaBytes = _lookupArchivePayload(
            archiveFiles,
            archivePrefix,
            archiveRelPath,
          );

          final alreadyStored = existingById[entry.id];
          final wasMissingMedia =
              alreadyStored != null && !alreadyStored.fileExists;
          if (mediaBytes != null) {
            // Extract evidence when adding a new record OR when healing an
            // existing record whose local media file was previously deleted.
            if (alreadyStored == null || wasMissingMedia) {
              try {
                final extractedPath = await _vault.writeExtractedEvidence(
                  entryId: entry.id,
                  fileName: entry.fileName,
                  bytes: mediaBytes,
                );
                entry = entry.copyWith(
                  filePath: extractedPath,
                  originalFileName: entry.fileName,
                );
                if (wasMissingMedia) {
                  final healed = await _profiles.relinkHistoryMedia(
                    profileId,
                    entry.id,
                    extractedPath,
                    originalFileName: entry.fileName,
                  );
                  if (healed) evidenceRestored++;
                } else {
                  evidenceRestored++;
                }
              } catch (e) {
                dev.log(
                  '[HistoryBackup] Failed extracting evidence for ${entry.id}: $e',
                  name: 'DeepGuard',
                );
              }
            }
          }

          parsedEntries.add(entry);
        } catch (e) {
          dev.log('[HistoryBackup] Skipped unreadable record: $e',
              name: 'DeepGuard');
        }
      }

      if (parsedEntries.isEmpty) continue;
      final added = await _profiles.restoreHistory(profileId, parsedEntries);
      recordsAdded += added;
      recordsSkipped += parsedEntries.length - added;
      if (added > 0) profilesWithHistory++;
    }

    // 3. Restore active profile selection when present.
    final activeId = decoded['activeProfileId']?.toString();
    if (activeId != null) {
      await _profiles.setActiveProfileIfPresent(activeId);
    }

    final exportedAt =
        decoded['exportedAt']?.toString() ?? 'an earlier backup';
    final String message;
    if (recordsAdded == 0 && evidenceRestored == 0) {
      message = 'Nothing new to restore — every record in this backup '
          '(exported $exportedAt) is already on this device.';
    } else if (recordsAdded == 0 && evidenceRestored > 0) {
      message = 'Restored $evidenceRestored missing image/video evidence '
          'file(s) for existing history records.';
    } else if (isZipArchive) {
      message = 'Restored $recordsAdded record(s)'
          '${evidenceRestored > 0 ? ' and $evidenceRestored image/video evidence file(s)' : ''}'
          ' under $profilesWithHistory profile(s)'
          '${profilesAdded > 0 ? ', created $profilesAdded profile(s)' : ''}'
          '${recordsSkipped > 0 ? ', skipped $recordsSkipped duplicate(s)' : ''}.';
    } else {
      message = 'Restored $recordsAdded record(s) under $profilesWithHistory '
          'profile(s)'
          '${profilesAdded > 0 ? ', created $profilesAdded profile(s)' : ''}'
          '${recordsSkipped > 0 ? ', skipped $recordsSkipped duplicate(s)' : ''}'
          '. Legacy JSON backups do not contain media files; use ZIP exports '
          'to include image and video evidence.';
    }

    dev.log(
      '[HistoryBackup] Import done profiles+$profilesAdded records+$recordsAdded '
      'evidence+$evidenceRestored skipped+$recordsSkipped',
      name: 'DeepGuard',
    );

    return BackupImportResult(
      cancelled: false,
      ok: true,
      message: message,
      profilesAdded: profilesAdded,
      recordsAdded: recordsAdded,
      recordsSkipped: recordsSkipped,
      evidenceRestored: evidenceRestored,
    );
  }
}
