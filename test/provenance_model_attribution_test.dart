import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:deepfake_flutter_app/services/media_provenance_service.dart';

/// Verifies that the provenance layer NAMES the generative model behind a
/// matched fingerprint (auxiliary metadata attribution only — it never touches
/// the CNN-RNN verdict, so nothing here asserts Authentic/Manipulated).
void main() {
  final service = MediaProvenanceService();
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('deepguard_provenance');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  File write(String name, String headerText) {
    final f = File('${tmp.path}${Platform.pathSeparator}$name');
    f.writeAsStringSync(headerText);
    return f;
  }

  test('ChatGPT-edited image is attributed to the OpenAI image model', () async {
    final f = write(
      'edited_photo.png',
      'PNG\x01\x00 Software: ChatGPT gpt-image-1 (DALL-E 3 diffusion) \x00\x00',
    );

    final r = await service.analyzeFile(f.path);

    expect(r.isAiGenerated, isTrue);
    expect(r.category, 'Generative AI');
    expect(r.generatorModel, contains('DALL·E 3'));
    expect(r.generatorFamily, 'Diffusion');
    expect(
      r.forensicEvidence.any((e) => e.contains('Generative model named by')),
      isTrue,
    );
  });

  test('Stable Diffusion parameters block names the SD pipeline', () async {
    final f = write(
      'sd_render.jpg',
      'JPEG\xff\x00 parameters: a castle, comfyui, negative prompt: blur \x00',
    );

    final r = await service.analyzeFile(f.path);

    expect(r.isAiGenerated, isTrue);
    expect(r.generatorModel, contains('Stable Diffusion'));
    expect(r.generatorFamily, 'Diffusion');
  });

  test('StyleGAN asset named only by filename still gets the model + family',
      () async {
    final f = write('thispersondoesnotexist_0142.jpg', 'JPEG\xff\x00 \x00');

    final r = await service.analyzeFile(f.path);

    expect(r.isAiGenerated, isTrue);
    expect(r.generatorModel, contains('StyleGAN'));
    expect(r.generatorFamily, contains('GAN'));
    expect(
      r.forensicEvidence.any((e) => e.contains('Filename evidence only')),
      isTrue,
    );
  });

  test('C2PA block written at the END of a large file is still read',
      () async {
    // ChatGPT / DALL-E exports append the C2PA Content Credentials AFTER the
    // image payload, so the attribution string sits in the file tail. The
    // scanner must read the last window too, otherwise a real ChatGPT image
    // would report "No Recognizable Metadata".
    final f = File('${tmp.path}${Platform.pathSeparator}chatgpt_export.jpg');
    final marker = 'c2pa claim_generator="ChatGPT" tool=gpt-image-1';
    final bytes = <int>[
      ...List<int>.filled(1100000, 0x00),
      ...marker.codeUnits,
    ];
    f.writeAsBytesSync(bytes);

    final r = await service.analyzeFile(f.path);

    expect(r.isAiGenerated, isTrue);
    expect(r.generatorModel, contains('DALL·E 3'));
    expect(r.generatorFamily, 'Diffusion');
    expect(
      r.forensicEvidence.any((e) => e.contains('C2PA')),
      isTrue,
    );
  });

  test('unmarked media names no model and stays neutral', () async {
    final f =
        write('IMG_0007.jpg', 'JPEG\xff\x00 nothing interesting here \x00');

    final r = await service.analyzeFile(f.path);

    expect(r.isAiGenerated, isFalse);
    expect(r.generatorModel, isNull);
    expect(r.generatorFamily, isNull);
  });
}