import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/deepguard_app_bar.dart';

/// DeepGuard About Screen.
///
/// A formal, informational About page presenting DeepGuard as a thesis-based
/// mobile deepfake-detection application. This screen is explanatory only:
/// it does NOT run or alter any detection, inference, preprocessing, or
/// navigation logic.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const DeepGuardAppBar(title: 'About DeepGuard'),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: DeepGuardColors.backgroundGradient,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 12),
                _header(),
                const SizedBox(height: 24),

                // ── 1. About DeepGuard ───────────────────────────────────────
                _sectionHeading(1, 'About DeepGuard'),
                _body(
                  'DeepGuard is a mobile-based deepfake detection application '
                  'designed to analyze image and video media and classify '
                  'submitted content as either Authentic or Manipulated. All '
                  'detection is performed on-device using a Hybrid CNN–RNN model '
                  'deployed with TensorFlow Lite.',
                ),
                const SizedBox(height: 12),
                _capabilitiesCard(),
                const SizedBox(height: 24),

                // ── 2. How It Works ──────────────────────────────────────────
                _sectionHeading(2, 'How It Works'),
                _body(
                  'Each submission follows the same processing pipeline, from '
                  'media input to the final result.',
                ),
                const SizedBox(height: 12),
                _pipelineCard(),
                const SizedBox(height: 24),

                // ── 3. Detection ─────────────────────────────────────────────
                _sectionHeading(3, 'Detection'),
                _detectionCard(),
                const SizedBox(height: 24),

                // ── 4. Digital Provenance ────────────────────────────────────
                _sectionHeading(4, 'Digital Provenance'),
                _provenanceCard(),
                const SizedBox(height: 24),

                // ── 5. Technology ────────────────────────────────────────────
                _sectionHeading(5, 'Technology'),
                _technologyCard(),
                const SizedBox(height: 24),

                // ── 6. Disclaimer ────────────────────────────────────────────
                _sectionHeading(6, 'Disclaimer'),
                _disclaimerCard(),
                const SizedBox(height: 24),
                Center(
                  child: Text(
                    'DeepGuard v1.1.0',
                    style: TextStyle(
                      color: DeepGuardColors.textMuted.withValues(alpha: 0.5),
                      fontSize: 11,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────
  Widget _header() {
    return GlassCard(
      padding: const EdgeInsets.all(24),
      gradient: const [DeepGuardColors.surfaceCard, DeepGuardColors.surfaceDark],
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(colors: DeepGuardColors.primaryGradient),
              boxShadow: [
                BoxShadow(
                  color: DeepGuardColors.primary.withValues(alpha: 0.3),
                  blurRadius: 20,
                  spreadRadius: 3,
                ),
              ],
            ),
            child: const Icon(Icons.visibility, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 12),
          const Text(
            'DeepGuard',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: DeepGuardColors.textPrimary,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'A Hybrid CNN–RNN for Media Deepfake Detection',
            style: TextStyle(color: DeepGuardColors.primary, fontSize: 12, letterSpacing: 1.5),
          ),
        ],
      ),
    );
  }

  // ── 1. Capabilities ───────────────────────────────────────────────────────
  Widget _capabilitiesCard() {
    const caps = <(IconData, String)>[
      (Icons.photo_camera_outlined, 'Capture image'),
      (Icons.videocam_outlined, 'Capture video'),
      (Icons.image_outlined, 'Upload image'),
      (Icons.movie_outlined, 'Upload video'),
      (Icons.analytics_outlined, 'Deepfake analysis'),
      (Icons.fact_check_outlined, 'View result'),
      (Icons.speed_outlined, 'Prediction confidence'),
      (Icons.inventory_2_outlined, 'Provenance info'),
      (Icons.travel_explore_outlined, 'Trace source'),
      (Icons.history_outlined, 'Analysis history'),
    ];
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle('What you can do'),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in caps) _capabilityChip(c.$1, c.$2),
            ],
          ),
        ],
      ),
    );
  }

  Widget _capabilityChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: DeepGuardColors.primary.withValues(alpha: 0.06),
        border: Border.all(
          color: DeepGuardColors.primary.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: DeepGuardColors.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: DeepGuardColors.textSecondary,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }

  // ── 2. How It Works pipeline ──────────────────────────────────────────────
  Widget _pipelineCard() {
    const stages = [
      'Media Input',
      'Validation & Confirmation',
      'Preprocessing',
      'Hybrid CNN–RNN',
      'Parallel Fusion',
      'Neuro-Symbolic Reasoning',
      'Classification',
      'Result Display',
    ];
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < stages.length; i++) ...[
            _pipelineStage(stages[i], i),
            if (i != stages.length - 1) _pipelineArrow(),
          ],
        ],
      ),
    );
  }

  Widget _pipelineStage(String label, int index) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: DeepGuardColors.surfaceLight.withValues(alpha: 0.5),
        border: Border.all(
          color: DeepGuardColors.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: DeepGuardColors.primary.withValues(alpha: 0.15),
            ),
            child: Text(
              '${index + 1}',
              style: const TextStyle(
                color: DeepGuardColors.primary,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: DeepGuardColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pipelineArrow() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 12),
      child: Icon(
        Icons.arrow_drop_down,
        color: DeepGuardColors.textMuted.withValues(alpha: 0.6),
        size: 22,
      ),
    );
  }

  // ── 3. Detection ──────────────────────────────────────────────────────────
  Widget _detectionCard() {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle('Classification'),
          const SizedBox(height: 10),
          _body(
            'DeepGuard classifies supported image and video media as either '
            'Authentic or Manipulated and reports the corresponding prediction '
            'confidence. Prediction confidence is the model\'s probability for '
            'its prediction on that individual file — it is not the overall '
            'accuracy of the system.',
            pad: false,
          ),
          const SizedBox(height: 12),
          _note(
            Icons.movie_filter_outlined,
            'Video analysis uses extracted frames rather than continuous '
            'live-stream detection.',
          ),
          const SizedBox(height: 8),
          _note(
            Icons.label_outline_rounded,
            'Model classes are Real / Fake; the app presents results as '
            'Authentic / Manipulated.',
          ),
        ],
      ),
    );
  }

  // ── 4. Digital Provenance ─────────────────────────────────────────────────
  Widget _provenanceCard() {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle('Supplementary provenance'),
          const SizedBox(height: 10),
          _bullet(
            Icons.folder_open_rounded,
            'DeepGuard may display metadata and filename information read '
            'on-device from the local file.',
          ),
          _bullet(
            Icons.travel_explore_rounded,
            'It can optionally perform online source tracing when the user '
            'requests it.',
          ),
          _bullet(
            Icons.info_outline_rounded,
            'Source tracing and C2PA/digital-provenance information are '
            'supplementary and do NOT determine the Authentic / Manipulated '
            'classification.',
          ),
        ],
      ),
    );
  }

  // ── 5. Technology ─────────────────────────────────────────────────────────
  Widget _technologyCard() {
    const techs = [
      'Flutter',
      'TensorFlow Lite',
      'EfficientNetB0',
      'RNN/LSTM',
      'Python',
      'TensorFlow',
      'Keras',
      'OpenCV',
    ];
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle('Built with'),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in techs) _techChip(t),
            ],
          ),
        ],
      ),
    );
  }

  Widget _techChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: DeepGuardColors.secondary.withValues(alpha: 0.08),
        border: Border.all(
          color: DeepGuardColors.secondary.withValues(alpha: 0.3),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: DeepGuardColors.textPrimary,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // ── 6. Disclaimer ─────────────────────────────────────────────────────────
  Widget _disclaimerCard() {
    return GlassCard(
      gradient: [
        DeepGuardColors.warning.withValues(alpha: 0.05),
        Colors.transparent,
      ],
      borderColor: DeepGuardColors.warning.withValues(alpha: 0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: DeepGuardColors.warning, size: 18),
              const SizedBox(width: 10),
              const Text(
                'Disclaimer',
                style: TextStyle(
                  color: DeepGuardColors.warning,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _body(
            '\u201CDeepGuard provides AI-based detection results and prediction '
            'confidence based on its trained model. Results should not be '
            'interpreted as absolute proof of authenticity or manipulation, '
            'particularly for media types or generation techniques not '
            'represented in the model\'s training and evaluation data.\u201D',
            pad: false,
          ),
          const SizedBox(height: 10),
          _body(
            'A high confidence score does not guarantee that a media is '
            'authentic or manipulated. DeepGuard is not a web application or a '
            'cloud-based detection service.',
            pad: false,
          ),
        ],
      ),
    );
  }

  // ── Small building blocks ──────────────────────────────────────────────────
  Widget _sectionHeading(int n, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              gradient: const LinearGradient(colors: DeepGuardColors.primaryGradient),
            ),
            child: Text(
              '$n',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w900,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: DeepGuardColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: DeepGuardColors.textPrimary,
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _body(String text, {bool pad = true}) => Padding(
        padding: EdgeInsets.only(bottom: pad ? 12 : 0),
        child: Text(
          text,
          style: TextStyle(
            color: DeepGuardColors.textSecondary.withValues(alpha: 0.85),
            fontSize: 13,
            height: 1.6,
          ),
        ),
      );

  Widget _note(IconData icon, String text) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: DeepGuardColors.info),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: DeepGuardColors.textSecondary,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ),
        ],
      );

  Widget _bullet(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: DeepGuardColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  color: DeepGuardColors.textSecondary,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      );
}
