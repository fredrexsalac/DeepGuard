import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:deepfake_flutter_app/models/history_entry.dart';
import 'package:deepfake_flutter_app/models/provenance_snapshot.dart';
import 'package:deepfake_flutter_app/services/history_backup_service.dart';
import 'package:deepfake_flutter_app/services/profile_service.dart';

/// Covers the export → wipe → import round trip that lets a user keep their
/// analysis history across an app reinstall (SharedPreferences are deleted on
/// uninstall, so the exported JSON file is the only surviving copy).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final svc = ProfileService();
  final backup = HistoryBackupService();

  HistoryEntry entry(String id, {int minutesAgo = 0, String? model}) =>
      HistoryEntry(
        id: id,
        filePath: '/storage/emulated/0/Download/$id.jpg',
        mediaType: 'image',
        detectionResult: 'manipulated',
        confidence: 0.875,
        timestamp: DateTime(2026, 10, 21, 9).subtract(
            Duration(minutes: minutesAgo)),
        provenance: ProvenanceSnapshot(
          sourceApp: 'ChatGPT / DALL-E (OpenAI)',
          category: 'Generative AI',
          isAiGenerated: true,
          isCameraOriginal: false,
          generatorModel: model,
          generatorFamily: model == null ? null : 'Diffusion',
          forensicEvidence: ['Generator fingerprint matched'],
        ),
      );

  /// Emulates a fresh install: empty storage, then the normal boot path. Pass
  /// [freshProfileId] to plant a known brand-new profile, so a restore that is
  /// supposed to create the backed-up profile can be asserted deterministically
  /// (the auto-created default profile is keyed on a millisecond timestamp,
  /// which two runs in the same millisecond would otherwise share).
  Future<void> reinstall({String? freshProfileId}) async {
    SharedPreferences.setMockInitialValues(freshProfileId == null
        ? <String, Object>{}
        : <String, Object>{
            'dg_profiles': jsonEncode([
              <String, dynamic>{
                'id': freshProfileId,
                'name': 'Fresh Install',
                'avatarColorValue': 0xFF00D4FF,
                'avatarIconCodePoint': Icons.person.codePoint,
                'avatarIconFontFamily': 'MaterialIcons',
                'totalAnalyses': 0,
                'fakeDetections': 0,
                'createdAt': DateTime(2026, 10, 21).toIso8601String(),
                'profilePicturePath': null,
              }
            ]),
            'dg_active_profile_id': freshProfileId,
          });
    await svc.init();
  }

  setUp(() => reinstall());

  test('exported file holds every profile, record and provenance snapshot',
      () async {
    final profile = svc.activeProfile!;
    await svc.saveHistoryEntry(profile.id, entry('a', minutesAgo: 0));
    await svc.saveHistoryEntry(profile.id,
        entry('b', minutesAgo: 30, model: 'DALL·E 3 / GPT-4o image output (OpenAI)'));

    final doc = await backup.buildBackup();
    expect(doc['format'], HistoryBackupService.formatTag);
    expect(doc['summary']['records'], 2);
    expect(doc['profiles'], isNotEmpty);

    final restored = HistoryEntry.fromJson(
        (doc['history'][profile.id] as List).first as Map<String, dynamic>);
    expect(restored.provenance, isNotNull);

    // The named generative model must survive the JSON round trip.
    final withModel = HistoryEntry.fromJson(
        (doc['history'][profile.id] as List)
            .firstWhere((e) => (e as Map)['id'] == 'b')
            .cast<String, dynamic>());
    expect(withModel.provenance!.generatorModel, contains('DALL·E 3'));
    expect(withModel.provenance!.generatorFamily, 'Diffusion');
  });

  test('import after a reinstall brings the records back', () async {
    final profile = svc.activeProfile!;
    await svc.saveHistoryEntry(profile.id, entry('a'));
    await svc.saveHistoryEntry(profile.id, entry('b', minutesAgo: 5));
    final text = jsonEncode(await backup.buildBackup());
    final profileCount = svc.profiles.length;

    await reinstall(freshProfileId: 'fresh-profile-1');
    expect(await svc.getHistory(svc.activeProfile!.id), isEmpty);

    final result = await backup.importFromJsonText(text);

    expect(result.ok, isTrue);
    expect(result.recordsAdded, 2);
    expect(result.profilesAdded, 1);
    expect(svc.profiles.length, profileCount + 1);

    final restoredProfile =
        svc.profiles.firstWhere((p) => p.id == profile.id);
    final history = await svc.getHistory(restoredProfile.id);
    expect(history.length, 2);
    expect(history.first.timestamp.isAfter(history.last.timestamp), isTrue);
    expect(svc.activeProfile!.id, profile.id);
  });

  test('importing the same backup twice adds nothing', () async {
    final profile = svc.activeProfile!;
    await svc.saveHistoryEntry(profile.id, entry('a'));
    await svc.saveHistoryEntry(profile.id, entry('b', minutesAgo: 5));
    final text = jsonEncode(await backup.buildBackup());

    await reinstall(freshProfileId: 'fresh-profile-2');
    final first = await backup.importFromJsonText(text);
    final second = await backup.importFromJsonText(text);

    expect(first.recordsAdded, 2);
    expect(second.ok, isTrue);
    expect(second.recordsAdded, 0);
    expect(second.message, contains('Nothing new to restore'));

    final restored = svc.profiles.firstWhere((p) => p.id == profile.id);
    expect((await svc.getHistory(restored.id)).length, 2);
  });

  test('a foreign JSON file is rejected without touching stored data',
      () async {
    final profile = svc.activeProfile!;
    await svc.saveHistoryEntry(profile.id, entry('a'));

    final result = await backup.importFromJsonText(
        jsonEncode({'hello': 'world'}));

    expect(result.ok, isFalse);
    expect(result.message, contains('not a DeepGuard backup'));
    expect((await svc.getHistory(profile.id)).length, 1);
  });

  test('backup from a newer schema version is refused', () async {
    final text = jsonEncode({
      'format': HistoryBackupService.formatTag,
      'schemaVersion': HistoryBackupService.schemaVersion + 1,
      'profiles': <dynamic>[],
      'history': <String, dynamic>{},
    });

    final result = await backup.importFromJsonText(text);

    expect(result.ok, isFalse);
    expect(result.message, contains('newer DeepGuard version'));
  });

  test('suggested file name is stamped and json-suffixed', () {
    final name = backup.suggestedFileName(DateTime(2026, 10, 21, 15, 30));
    expect(name, 'deepguard_backup_20261021_1530.json');
  });
}
