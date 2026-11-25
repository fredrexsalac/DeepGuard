import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:deepfake_flutter_app/models/analysis_framing.dart';
import 'package:deepfake_flutter_app/models/history_entry.dart';
import 'package:deepfake_flutter_app/models/prediction_result.dart';
import 'package:deepfake_flutter_app/models/provenance_snapshot.dart';
import 'package:deepfake_flutter_app/screens/result_screen.dart';
import 'package:deepfake_flutter_app/services/evidence_vault_service.dart';
import 'package:deepfake_flutter_app/services/evidence_zip_codec.dart';
import 'package:deepfake_flutter_app/services/history_backup_service.dart';
import 'package:deepfake_flutter_app/services/profile_service.dart';
import 'package:deepfake_flutter_app/theme/app_theme.dart';

/// Covers DeepGuard's portable `.zip` Evidence Archive (and backward-compatible
/// legacy `.json` backup) export -> wipe -> import round trip, verifying that
/// analyzed images and videos are retained as forensic evidence and restored
/// byte-for-byte into previous results.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final svc = ProfileService();
  final backup = HistoryBackupService();
  late Directory tempWorkspace;

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => <String>['none'],
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
      (call) async => null,
    );
  });

  HistoryEntry entry(
    String id, {
    int minutesAgo = 0,
    String? model,
    String? filePath,
    String mediaType = 'image',
  }) =>
      HistoryEntry(
        id: id,
        filePath: filePath ?? '/storage/emulated/0/Download/$id.jpg',
        mediaType: mediaType,
        detectionResult: 'manipulated',
        confidence: 0.875,
        timestamp:
            DateTime(2026, 10, 21, 9).subtract(Duration(minutes: minutesAgo)),
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

  /// Generates a valid PNG image buffer with custom trailing C2PA-like marker
  /// bytes so byte-for-byte preservation is verifiable.
  Uint8List buildSampleImageBytes() {
    final canvas = img.Image(width: 64, height: 64);
    img.fill(canvas, color: img.ColorRgb8(24, 68, 152));
    final pngBytes = img.encodePng(canvas);
    final trailer = utf8.encode('c2pa.manifest.evidence.signature');
    return Uint8List.fromList(<int>[...pngBytes, ...trailer]);
  }

  /// Generates synthetic MP4 ftyp/mdat container bytes to verify binary video
  /// evidence packaging and extraction.
  Uint8List buildSampleVideoBytes() {
    final header = <int>[
      0x00, 0x00, 0x00, 0x18,
      0x66, 0x74, 0x79, 0x70, // 'ftyp'
      0x6D, 0x70, 0x34, 0x32, // 'mp42'
      0x00, 0x00, 0x00, 0x00,
      0x6D, 0x70, 0x34, 0x32,
      0x69, 0x73, 0x6F, 0x6D,
    ];
    final payload = List<int>.generate(2048, (i) => (i * 37 + 13) & 0xFF);
    return Uint8List.fromList(<int>[...header, ...payload]);
  }

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

  setUp(() async {
    tempWorkspace = Directory.systemTemp.createTempSync('deepguard_zip_test_');
    EvidenceVaultService.overrideDirectory =
        Directory('${tempWorkspace.path}/device_a');
    await reinstall();
  });

  tearDown(() {
    EvidenceVaultService.overrideDirectory = null;
    if (tempWorkspace.existsSync()) {
      tempWorkspace.deleteSync(recursive: true);
    }
  });

  test('exported manifest holds every profile, record and provenance snapshot',
      () async {
    final profile = svc.activeProfile!;
    await svc.saveHistoryEntry(profile.id, entry('a', minutesAgo: 0));
    await svc.saveHistoryEntry(
      profile.id,
      entry(
        'b',
        minutesAgo: 30,
        model: 'DALL·E 3 / GPT-4o image output (OpenAI)',
      ),
    );

    final doc = await backup.buildBackup();
    expect(doc['format'], HistoryBackupService.formatTag);
    expect(doc['summary']['records'], 2);
    expect(doc['profiles'], isNotEmpty);

    final restored = HistoryEntry.fromJson(
        (doc['history'][profile.id] as List).first as Map<String, dynamic>);
    expect(restored.provenance, isNotNull);

    final withModel = HistoryEntry.fromJson(
        (doc['history'][profile.id] as List)
            .firstWhere((e) => (e as Map)['id'] == 'b')
            .cast<String, dynamic>());
    expect(withModel.provenance!.generatorModel, contains('DALL·E 3'));
    expect(withModel.provenance!.generatorFamily, 'Diffusion');
  });

  test(
      'ZIP Evidence Archive bundles analyzed images & videos and restores them byte-for-byte after reinstall',
      () async {
    final pickerCache = Directory('${tempWorkspace.path}/picker_cache')
      ..createSync(recursive: true);
    final imgBytes = buildSampleImageBytes();
    final vidBytes = buildSampleVideoBytes();

    final pickedImg = File('${pickerCache.path}/portrait_evidence.png')
      ..writeAsBytesSync(imgBytes);
    final pickedVid = File('${pickerCache.path}/interview_clip.mp4')
      ..writeAsBytesSync(vidBytes);

    final profile = svc.activeProfile!;
    await svc.saveHistoryEntry(
      profile.id,
      HistoryEntry(
        id: 'img-ev-1',
        filePath: pickedImg.path,
        mediaType: 'image',
        detectionResult: 'authentic',
        confidence: 0.93,
        timestamp: DateTime(2026, 11, 25, 10, 0),
        framing: const AnalysisFraming(
          frameWidth: 64,
          frameHeight: 64,
          faceCount: 1,
          faceRect: BoxRect(10, 10, 44, 44),
          note: 'face already fills the frame',
        ),
      ),
    );
    await svc.saveHistoryEntry(
      profile.id,
      entry(
        'vid-ev-2',
        filePath: pickedVid.path,
        mediaType: 'video',
        model: 'Sora / Diffusion Video',
      ),
    );

    // Delete original picker temp cache files — local Evidence Vault copy keeps them alive!
    pickerCache.deleteSync(recursive: true);
    final savedBeforeExport = await svc.getHistory(profile.id);
    expect(savedBeforeExport.every((e) => e.fileExists), isTrue);

    // Build portable .zip Evidence Archive
    final pkg = await backup.buildEvidenceZip();
    expect(EvidenceZipCodec.isZipBytes(pkg.zipBytes), isTrue);
    expect(pkg.recordsCount, 2);
    expect(pkg.evidenceFilesCount, 2);
    expect(pkg.imagesCount, 1);
    expect(pkg.videosCount, 1);

    // Simulate wiping Device A completely and restoring onto fresh Device B
    Directory('${tempWorkspace.path}/device_a').deleteSync(recursive: true);
    EvidenceVaultService.overrideDirectory =
        Directory('${tempWorkspace.path}/device_b');
    await reinstall(freshProfileId: 'fresh-device-b');

    final importRes = await backup.importFromBytes(
      pkg.zipBytes,
      fileName: backup.suggestedFileName(DateTime(2026, 11, 25, 10, 15)),
    );

    expect(importRes.ok, isTrue);
    expect(importRes.recordsAdded, 2);
    expect(importRes.evidenceRestored, 2);

    final restoredHistory = await svc.getHistory(profile.id);
    expect(restoredHistory.length, 2);

    final restoredImg =
        restoredHistory.firstWhere((e) => e.id == 'img-ev-1');
    final restoredVid =
        restoredHistory.firstWhere((e) => e.id == 'vid-ev-2');

    expect(restoredImg.fileExists, isTrue);
    expect(restoredImg.fileName, 'portrait_evidence.png');
    expect(File(restoredImg.filePath!).readAsBytesSync(), equals(imgBytes));

    expect(restoredVid.fileExists, isTrue);
    expect(restoredVid.fileName, 'interview_clip.mp4');
    expect(File(restoredVid.filePath!).readAsBytesSync(), equals(vidBytes));
  });

  testWidgets(
      'Restored ZIP evidence renders Retained Media Evidence badge in ResultScreen',
      (tester) async {
    final srcImg = File('${tempWorkspace.path}/restored_face.png')
      ..writeAsBytesSync(buildSampleImageBytes());
    final profile = svc.activeProfile!;
    await svc.saveHistoryEntry(
      profile.id,
      entry('ui-ev-1', filePath: srcImg.path, mediaType: 'image'),
    );
    final pkg = await backup.buildEvidenceZip();

    EvidenceVaultService.overrideDirectory =
        Directory('${tempWorkspace.path}/device_ui');
    await reinstall(freshProfileId: 'fresh-ui');
    await backup.importFromZipBytes(pkg.zipBytes);

    final restored = (await svc.getHistory(profile.id)).single;
    expect(restored.fileExists, isTrue);

    await tester.pumpWidget(
      MaterialApp(
        theme: DeepGuardTheme.lightTheme,
        home: ResultScreen(
          result: PredictionResult(
            id: restored.id,
            filePath: restored.filePath,
            mediaType: MediaType.image,
            status: PredictionStatus.completed,
            result: DetectionResult.manipulated,
            confidence: restored.confidence,
            timestamp: restored.timestamp,
          ),
          filePath: restored.filePath!,
          isHistory: true,
          historyProvenance: restored.provenance,
          onAnalyzeAnother: () {},
          onGoHome: () {},
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Retained Media Evidence'), findsOneWidget);
    expect(find.text('IMAGE EVIDENCE'), findsOneWidget);
    expect(
      find.textContaining('bundled inside exported DeepGuard ZIP archives'),
      findsOneWidget,
    );

    PaintingBinding.instance.imageCache.clear();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test(
      're-importing a ZIP heals missing media evidence on an already-saved record without duplicating it',
      () async {
    final srcVid = File('${tempWorkspace.path}/clip_heal.mp4')
      ..writeAsBytesSync(buildSampleVideoBytes());
    final profile = svc.activeProfile!;
    await svc.saveHistoryEntry(
      profile.id,
      entry('heal-1', filePath: srcVid.path, mediaType: 'video'),
    );

    final pkg = await backup.buildEvidenceZip();

    // Delete the retained vault file while keeping the SharedPreferences record
    final storedBeforeBreak = (await svc.getHistory(profile.id)).single;
    File(storedBeforeBreak.filePath!).deleteSync();
    expect((await svc.getHistory(profile.id)).single.fileExists, isFalse);

    final healRes = await backup.importFromZipBytes(pkg.zipBytes);
    expect(healRes.ok, isTrue);
    expect(healRes.recordsAdded, 0);
    expect(healRes.evidenceRestored, 1);

    final healed = (await svc.getHistory(profile.id)).single;
    expect(healed.fileExists, isTrue);
    expect((await svc.getHistory(profile.id)).length, 1);
  });

  test('legacy JSON import after a reinstall still brings records back',
      () async {
    final profile = svc.activeProfile!;
    await svc.saveHistoryEntry(profile.id, entry('a'));
    await svc.saveHistoryEntry(profile.id, entry('b', minutesAgo: 5));
    final text = jsonEncode(await backup.buildBackup());
    final profileCount = svc.profiles.length;

    await reinstall(freshProfileId: 'fresh-profile-1');
    expect(await svc.getHistory(svc.activeProfile!.id), isEmpty);

    final result = await backup.importFromBytes(
      Uint8List.fromList(utf8.encode(text)),
      fileName: 'legacy_backup.json',
    );

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

  test('a restored record keeps its full report even when no media was saved',
      () async {
    final profile = svc.activeProfile!;
    await svc.saveHistoryEntry(
      profile.id,
      entry('a', model: 'DALL·E 3 / GPT-4o image output (OpenAI)'),
    );
    final pkg = await backup.buildEvidenceZip();

    await reinstall(freshProfileId: 'fresh-profile-preview');
    await backup.importFromZipBytes(pkg.zipBytes);

    final restored = (await svc.getHistory(profile.id)).single;
    expect(restored.fileExists, isFalse);
    expect(restored.detectionResult, 'manipulated');
    expect(restored.confidence, 0.875);
    expect(restored.resultLabel, isNotEmpty);
    expect(restored.provenance!.generatorModel, contains('DALL·E 3'));
  });

  test('importing the same ZIP backup twice adds nothing', () async {
    final profile = svc.activeProfile!;
    await svc.saveHistoryEntry(profile.id, entry('a'));
    await svc.saveHistoryEntry(profile.id, entry('b', minutesAgo: 5));
    final pkg = await backup.buildEvidenceZip();

    await reinstall(freshProfileId: 'fresh-profile-2');
    final first = await backup.importFromZipBytes(pkg.zipBytes);
    final second = await backup.importFromZipBytes(pkg.zipBytes);

    expect(first.recordsAdded, 2);
    expect(second.ok, isTrue);
    expect(second.recordsAdded, 0);
    expect(second.message, contains('Nothing new to restore'));

    final restored = svc.profiles.firstWhere((p) => p.id == profile.id);
    expect((await svc.getHistory(restored.id)).length, 2);
  });

  test('foreign ZIP without manifest and corrupted ZIP bytes are rejected safely',
      () async {
    final profile = svc.activeProfile!;
    await svc.saveHistoryEntry(profile.id, entry('a'));

    final unrelatedZip = EvidenceZipCodec.encode([
      ZipArchiveEntry(
        name: 'notes.txt',
        bytes: Uint8List.fromList(utf8.encode('not a deepguard archive')),
        compress: true,
      ),
    ]);
    final r1 = await backup.importFromZipBytes(unrelatedZip);
    expect(r1.ok, isFalse);
    expect(r1.message, contains('not a DeepGuard backup'));

    // Tamper with payload byte inside the first ZIP entry to trigger CRC-32 / zlib rejection
    final validPkg = await backup.buildEvidenceZip();
    final tampered = Uint8List.fromList(validPkg.zipBytes);
    final firstNameLen =
        ByteData.sublistView(tampered).getUint16(26, Endian.little);
    tampered[30 + firstNameLen + 4] ^= 0xFF;
    final r2 = await backup.importFromZipBytes(tampered);
    expect(r2.ok, isFalse);

    expect((await svc.getHistory(profile.id)).length, 1);
  });

  test('a foreign JSON file is rejected without touching stored data',
      () async {
    final profile = svc.activeProfile!;
    await svc.saveHistoryEntry(profile.id, entry('a'));

    final result = await backup.importFromJsonText(
      jsonEncode({'hello': 'world'}),
    );

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

  test('suggested file name is stamped and zip-suffixed', () {
    final name = backup.suggestedFileName(DateTime(2026, 10, 21, 15, 30));
    expect(name, 'deepguard_backup_20261021_1530.zip');
  });
}
