import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/deepguard_app_bar.dart';
import 'onboarding_screen.dart';

/// Release label shown in the About footer (synced with `pubspec.yaml`).
const String kDeepGuardVersion = '1.3.0';

/// DeepGuard About Screen — accessible Light & Dark mode technical reference.
///
/// Preserves complete research documentation (Hybrid CNN–RNN architecture,
/// EfficientNetB0, LSTM, Parallel Fusion, Neuro-Symbolic Reasoning, dataset
/// evaluation reference, provenance scope, and responsible-use disclaimer) off
/// the ordinary user homepage.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  void _replayWalkthrough(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => OnboardingScreen(
          onDone: () => Navigator.of(ctx).pop(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = DeepGuardPalette.of(context);

    return Scaffold(
      backgroundColor: palette.backgroundSecondary,
      appBar: const DeepGuardAppBar(title: 'About DeepGuard'),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context, palette),
              const SizedBox(height: 24),

              _sectionHeading(1, 'About DeepGuard', palette),
              _body(
                'DeepGuard is a mobile deepfake detection application designed '
                'to analyze images and videos and classify submitted media as '
                'either REAL or A.I. All inference runs locally on your device '
                'using a Hybrid CNN–RNN model deployed with TensorFlow Lite.',
                palette,
              ),
              _capabilitiesCard(palette),
              const SizedBox(height: 24),

              _sectionHeading(2, 'Detection Architecture', palette),
              _body(
                'Each submission passes through a structured on-device pipeline '
                'from input validation to authenticity classification.',
                palette,
              ),
              _pipelineCard(palette),
              const SizedBox(height: 24),

              _sectionHeading(3, 'Classification & Model Confidence', palette),
              _detectionCard(palette),
              const SizedBox(height: 24),

              _sectionHeading(4, 'Digital Provenance', palette),
              _provenanceCard(palette),
              const SizedBox(height: 24),

              _sectionHeading(5, 'Core Technologies', palette),
              _technologyCard(palette),
              const SizedBox(height: 24),

              _sectionHeading(6, 'Disclaimer', palette),
              _disclaimerCard(palette),
              const SizedBox(height: 20),

              OutlinedButton.icon(
                onPressed: () => _replayWalkthrough(context),
                icon: const Icon(Icons.menu_book_outlined, size: 19),
                label: const Text('Replay App Walkthrough'),
              ),
              const SizedBox(height: 20),

              Center(
                child: Text(
                  'DeepGuard v$kDeepGuardVersion',
                  style: TextStyle(
                    color: palette.textMuted,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, DeepGuardPalette palette) {
    return GlassCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          ExcludeSemantics(
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: palette.accent, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: palette.brandNavy.withValues(alpha: 0.16),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.asset(
                  'assets/images/deepguard_logo.png',
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Semantics(
            header: true,
            child: Text(
              'DeepGuard',
              style: TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.w800,
                color: palette.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'A Hybrid CNN–RNN for Media Deepfake Detection',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: palette.primaryText,
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _capabilitiesCard(DeepGuardPalette palette) {
    const caps = <(IconData, String)>[
      (Icons.photo_camera_outlined, 'Capture photo'),
      (Icons.videocam_outlined, 'Record video'),
      (Icons.image_outlined, 'Upload image'),
      (Icons.movie_outlined, 'Upload video'),
      (Icons.face_retouching_natural, 'Face framing'),
      (Icons.fact_check_outlined, 'REAL / A.I. verdict'),
      (Icons.insights_outlined, 'Model confidence'),
      (Icons.fingerprint_rounded, 'Provenance check'),
      (Icons.history_outlined, 'Saved history'),
    ];
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle('Key Capabilities', palette),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in caps) _capabilityChip(c.$1, c.$2, palette),
            ],
          ),
        ],
      ),
    );
  }

  Widget _capabilityChip(
    IconData icon,
    String label,
    DeepGuardPalette palette,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: palette.processingContainer,
        border: Border.all(color: palette.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: Icon(icon, size: 16, color: palette.primaryText),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pipelineCard(DeepGuardPalette palette) {
    const stages = [
      'Media Selection & Validation',
      'Preprocessing & Face Framing (Image) / 10-Frame Sampling (Video)',
      'EfficientNetB0 Spatial Feature Extraction',
      'Hybrid CNN–RNN / LSTM Sequence Modeling',
      'Parallel Fusion',
      'Neuro-Symbolic Reasoning',
      'REAL / A.I. Classification & Result Presentation',
    ];
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < stages.length; i++) ...[
            _pipelineStage(stages[i], i, palette),
            if (i != stages.length - 1)
              ExcludeSemantics(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Icon(
                    Icons.arrow_downward_rounded,
                    color: palette.textMuted,
                    size: 18,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _pipelineStage(String label, int index, DeepGuardPalette palette) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: palette.backgroundSecondary,
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: palette.processingContainer,
            ),
            child: Text(
              '${index + 1}',
              style: TextStyle(
                color: palette.primaryText,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detectionCard(DeepGuardPalette palette) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle('Understanding Results', palette),
          const SizedBox(height: 10),
          _body(
            'DeepGuard classifies supported media into internal model classes '
            '(Real / Fake) and presents clear user-facing verdicts as REAL or '
            'A.I. alongside Model Confidence. Model Confidence is the model\'s '
            'probability for that single file and is distinct from dataset '
            'benchmark evaluation metrics (84.82% Image · 71.67% Video) '
            'documented in the research evaluation.',
            palette,
            pad: false,
          ),
          const SizedBox(height: 12),
          _note(
            Icons.movie_filter_outlined,
            'Video detection samples 10 uniformly spaced frames across the clip rather than continuous live-stream video.',
            palette,
          ),
          const SizedBox(height: 8),
          _note(
            Icons.label_outline_rounded,
            'Internal classes: 0 = Real (displayed as REAL) and 1 = Fake (displayed as A.I.).',
            palette,
          ),
        ],
      ),
    );
  }

  Widget _provenanceCard(DeepGuardPalette palette) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle('Supplementary Provenance', palette),
          const SizedBox(height: 10),
          _bullet(
            Icons.folder_open_rounded,
            'Inspects local EXIF and file-header metadata directly on your device.',
            palette,
          ),
          _bullet(
            Icons.verified_user_outlined,
            'Optionally checks C2PA Content Credentials when an internet connection is active.',
            palette,
          ),
          _bullet(
            Icons.info_outline_rounded,
            'Provenance metadata is supplementary context only and never overrides the Hybrid CNN–RNN classification.',
            palette,
          ),
        ],
      ),
    );
  }

  Widget _technologyCard(DeepGuardPalette palette) {
    const techs = [
      'Flutter',
      'TensorFlow Lite',
      'EfficientNetB0',
      'LSTM / RNN',
      'Parallel Fusion',
      'Neuro-Symbolic Reasoning',
      'ML Kit Face Detection',
      'Python / TensorFlow / Keras',
    ];
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle('Built With', palette),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in techs)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: palette.surfaceElevated,
                    border: Border.all(color: palette.border),
                  ),
                  child: Text(
                    t,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _disclaimerCard(DeepGuardPalette palette) {
    return GlassCard(
      backgroundColor: palette.warningContainer,
      borderColor: palette.warning.withValues(alpha: 0.55),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.warning_amber_rounded,
                  color: palette.warningText,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Responsible Use Disclaimer',
                  style: TextStyle(
                    color: palette.warningText,
                    fontWeight: FontWeight.w700,
                    fontSize: 15.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'DeepGuard provides AI-assisted authenticity assessments and model '
            'confidence based on its trained neural architecture. Results '
            'should not be treated as definitive forensic proof, especially '
            'for heavily compressed media or novel generation methods outside '
            'the training distribution.',
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 14.5,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeading(int n, String title, DeepGuardPalette palette) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        header: true,
        child: Row(
          children: [
            ExcludeSemantics(
              child: Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: palette.primaryButton,
                ),
                child: Text(
                  '$n',
                  style: TextStyle(
                    color: palette.onPrimaryButton,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardTitle(String title, DeepGuardPalette palette) {
    return Text(
      title,
      style: TextStyle(
        color: palette.textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _body(String text, DeepGuardPalette palette, {bool pad = true}) =>
      Padding(
        padding: EdgeInsets.only(bottom: pad ? 12 : 0),
        child: Text(
          text,
          style: TextStyle(
            color: palette.textSecondary,
            fontSize: 15,
            height: 1.55,
          ),
        ),
      );

  Widget _note(IconData icon, String text, DeepGuardPalette palette) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: ExcludeSemantics(
              child: Icon(icon, size: 18, color: palette.primaryText),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 14,
                height: 1.45,
              ),
            ),
          ),
        ],
      );

  Widget _bullet(IconData icon, String text, DeepGuardPalette palette) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: ExcludeSemantics(
                child: Icon(icon, size: 18, color: palette.primaryText),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      );
}
