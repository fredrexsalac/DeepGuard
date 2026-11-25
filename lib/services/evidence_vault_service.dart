import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'app_log.dart' as dev;

/// Manages DeepGuard's local persistent **Evidence Vault**.
///
/// Analyzed images and videos are copied into a dedicated per-record directory
/// (`<appSupportDir>/deepguard_evidence/<entryId>/<fileName>`) when saved to
/// history or restored from a `.zip` Evidence Archive.
class EvidenceVaultService {
  static final EvidenceVaultService _instance =
      EvidenceVaultService._internal();
  factory EvidenceVaultService() => _instance;
  EvidenceVaultService._internal();

  /// Optional test hook allowing unit/widget tests to isolate evidence storage
  /// in a temporary directory without touching host AppData or platform channels.
  @visibleForTesting
  static Directory? overrideDirectory;

  static const String _vaultFolderName = 'deepguard_evidence';
  Directory? _cachedSupportRoot;

  bool get _isRunningUnderFlutterTest {
    try {
      final typeName = WidgetsBinding.instance.runtimeType.toString();
      return typeName.contains('TestWidgetsFlutterBinding') ||
          typeName.contains('AutomatedTestWidgetsFlutterBinding');
    } catch (_) {
      return false;
    }
  }

  /// Sanitizes a single path segment so archive extraction or malformed IDs can
  /// never escape the vault directory (Zip-Slip protection) or violate Windows,
  /// Android, or iOS filename rules.
  static String sanitizeSegment(String raw, {String fallback = 'evidence'}) {
    final trimmed = raw.trim().replaceAll('\\', '/').split('/').last;
    final cleaned = trimmed
        .replaceAll('..', '_')
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .trim();
    if (cleaned.isEmpty || cleaned == '.' || cleaned == '_') {
      return fallback;
    }
    return cleaned;
  }

  /// Resolves the root evidence vault directory.
  ///
  /// Uses synchronous filesystem checks after resolving the base path so this
  /// remains safe inside both real app isolates and `FakeAsync` widget tests.
  Future<Directory?> resolveVaultRoot({bool allowTempFallback = false}) async {
    if (overrideDirectory != null) {
      final dir = Directory(
        '${overrideDirectory!.path}${Platform.pathSeparator}$_vaultFolderName',
      );
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      return dir;
    }

    // Never pollute host OS AppData or invoke async path_provider_windows I/O
    // inside FakeAsync widget tests when no test overrideDirectory is set.
    if (_isRunningUnderFlutterTest) {
      if (!allowTempFallback) return null;
      final fallback = Directory(
        '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'deepguard_evidence_fallback',
      );
      if (!fallback.existsSync()) {
        fallback.createSync(recursive: true);
      }
      return fallback;
    }

    if (_cachedSupportRoot != null && _cachedSupportRoot!.existsSync()) {
      return _cachedSupportRoot;
    }

    try {
      final supportDir = await getApplicationSupportDirectory();
      final dir = Directory(
        '${supportDir.path}${Platform.pathSeparator}$_vaultFolderName',
      );
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      _cachedSupportRoot = dir;
      return dir;
    } on MissingPluginException {
      if (!allowTempFallback) return null;
      final fallback = Directory(
        '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'deepguard_evidence_fallback',
      );
      if (!fallback.existsSync()) {
        fallback.createSync(recursive: true);
      }
      return fallback;
    } catch (e) {
      dev.log('[EvidenceVault] Could not resolve vault root: $e',
          name: 'DeepGuard');
      return null;
    }
  }

  /// Copies an analyzed image or video into the persistent Evidence Vault under
  /// `<vault>/<safeEntryId>/<safeFileName>`.
  Future<String> retainFileForEntry({
    required String entryId,
    required String sourcePath,
    String? preferredFileName,
  }) async {
    final src = File(sourcePath);
    if (!src.existsSync()) return sourcePath;

    final root = await resolveVaultRoot(allowTempFallback: false);
    if (root == null) return sourcePath;

    final safeId = sanitizeSegment(entryId, fallback: 'record');
    final rawName = (preferredFileName != null &&
            preferredFileName.trim().isNotEmpty)
        ? preferredFileName
        : sourcePath;
    final safeName = sanitizeSegment(rawName, fallback: 'media_sample');

    final entryDir = Directory('${root.path}${Platform.pathSeparator}$safeId');
    final targetPath = '${entryDir.path}${Platform.pathSeparator}$safeName';

    if (src.absolute.path == File(targetPath).absolute.path) {
      return targetPath;
    }

    try {
      if (!entryDir.existsSync()) {
        entryDir.createSync(recursive: true);
      }
      src.copySync(targetPath);
      return targetPath;
    } catch (e) {
      dev.log(
        '[EvidenceVault] Failed to copy $sourcePath into vault: $e',
        name: 'DeepGuard',
      );
      return sourcePath;
    }
  }

  /// Writes extracted `.zip` evidence bytes into `<vault>/<safeEntryId>/<safeName>`
  /// and returns the resulting local file path.
  Future<String> writeExtractedEvidence({
    required String entryId,
    required String fileName,
    required Uint8List bytes,
  }) async {
    final root = await resolveVaultRoot(allowTempFallback: true);
    if (root == null) {
      throw StateError('Evidence storage directory is unavailable.');
    }

    final safeId = sanitizeSegment(entryId, fallback: 'record');
    final safeName = sanitizeSegment(fileName, fallback: 'evidence_media');
    final entryDir = Directory('${root.path}${Platform.pathSeparator}$safeId');
    if (!entryDir.existsSync()) {
      entryDir.createSync(recursive: true);
    }

    final outFile = File('${entryDir.path}${Platform.pathSeparator}$safeName');
    outFile.writeAsBytesSync(bytes, flush: true);
    return outFile.path;
  }

  /// Writes an extracted profile avatar from a `.zip` archive into `<vault>/avatars/`.
  Future<String> writeExtractedAvatar({
    required String profileId,
    required String fileName,
    required Uint8List bytes,
  }) async {
    final root = await resolveVaultRoot(allowTempFallback: true);
    if (root == null) {
      throw StateError('Evidence storage directory is unavailable.');
    }

    final safeProfile = sanitizeSegment(profileId, fallback: 'profile');
    final safeName = sanitizeSegment(fileName, fallback: 'avatar.jpg');
    final avatarDir = Directory(
      '${root.path}${Platform.pathSeparator}avatars'
      '${Platform.pathSeparator}$safeProfile',
    );
    if (!avatarDir.existsSync()) {
      avatarDir.createSync(recursive: true);
    }

    final outFile = File('${avatarDir.path}${Platform.pathSeparator}$safeName');
    outFile.writeAsBytesSync(bytes, flush: true);
    return outFile.path;
  }

  /// Deletes retained evidence for [entryId] when no longer referenced.
  Future<void> deleteEntryEvidence(String entryId) async {
    final root = await resolveVaultRoot(allowTempFallback: false);
    if (root == null) return;

    final safeId = sanitizeSegment(entryId, fallback: 'record');
    final entryDir = Directory('${root.path}${Platform.pathSeparator}$safeId');
    try {
      if (entryDir.existsSync()) {
        entryDir.deleteSync(recursive: true);
      }
    } catch (e) {
      dev.log('[EvidenceVault] Could not delete evidence $safeId: $e',
          name: 'DeepGuard');
    }
  }
}
