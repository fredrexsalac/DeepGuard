import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import '../models/history_entry.dart';
import '../models/prediction_result.dart';
import '../services/profile_service.dart';
import '../services/theme_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import 'result_screen.dart';

/// DeepGuard Simplified Homepage (Phase 5 & WCAG 2.2 Level AA).
///
/// Focuses immediately on core media detection actions (Upload Image,
/// Upload Video, Analyze Media) with readable typography, Light/Dark/System
/// theme support, and zero model accuracy metrics on the homepage.
class HomeScreen extends StatefulWidget {
  final VoidCallback onAnalyzeTap;
  final VoidCallback? onUploadImageTap;
  final VoidCallback? onUploadVideoTap;
  final VoidCallback? onOpenHistoryTap;

  const HomeScreen({
    super.key,
    required this.onAnalyzeTap,
    this.onUploadImageTap,
    this.onUploadVideoTap,
    this.onOpenHistoryTap,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isOnline = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  final ProfileService _profileService = ProfileService();
  List<HistoryEntry> _recentEntries = const [];

  @override
  void initState() {
    super.initState();
    _profileService.addListener(_loadRecentAnalyses);
    _loadRecentAnalyses();
    _initConnectivity();
    _listenConnectivity();
  }

  @override
  void dispose() {
    _connectivitySub?.cancel().catchError((_) {});
    _profileService.removeListener(_loadRecentAnalyses);
    super.dispose();
  }

  Future<void> _loadRecentAnalyses() async {
    final profile = _profileService.activeProfile;
    if (profile == null) {
      if (mounted && _recentEntries.isNotEmpty) {
        setState(() => _recentEntries = const []);
      }
      return;
    }
    final items = await _profileService.getHistory(profile.id);
    if (!mounted) return;
    setState(() {
      _recentEntries = items.take(3).toList(growable: false);
    });
  }

  Future<bool> _checkInternetConnection() async {
    try {
      final results = await Connectivity().checkConnectivity();
      final hasInterface = results.any((r) => r != ConnectivityResult.none);
      if (!hasInterface) return false;
      try {
        final lookup = await InternetAddress.lookup('example.com')
            .timeout(const Duration(milliseconds: 2500));
        return lookup.isNotEmpty && lookup[0].rawAddress.isNotEmpty;
      } catch (_) {
        try {
          final lookup2 = await InternetAddress.lookup('google.com')
              .timeout(const Duration(milliseconds: 2000));
          return lookup2.isNotEmpty && lookup2[0].rawAddress.isNotEmpty;
        } catch (_) {
          return false;
        }
      }
    } catch (_) {
      return false;
    }
  }

  Future<void> _initConnectivity() async {
    final online = await _checkInternetConnection();
    if (!mounted) return;
    setState(() => _isOnline = online);
  }

  void _listenConnectivity() {
    try {
      _connectivitySub = Connectivity().onConnectivityChanged.listen(
        (results) async {
          final hasInterface =
              results.any((r) => r != ConnectivityResult.none);
          if (!hasInterface) {
            if (mounted && _isOnline) setState(() => _isOnline = false);
            return;
          }
          final online = await _checkInternetConnection();
          if (mounted && online != _isOnline) {
            setState(() => _isOnline = online);
          }
        },
        onError: (_) {},
      );
    } catch (_) {}
  }

  void _openThemeSheet() {
    final themeService = ThemeService();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) {
        return ListenableBuilder(
          listenable: themeService,
          builder: (ctx, _) {
            final palette = DeepGuardPalette.of(ctx);
            final current = themeService.themeMode;
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        'Appearance',
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Choose how DeepGuard appears across all screens.',
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _ThemeOptionTile(
                      title: 'Light Mode',
                      subtitle: 'Bright surfaces with dark high-contrast text',
                      icon: Icons.light_mode_outlined,
                      selected: current == ThemeMode.light,
                      onTap: () {
                        themeService.setThemeMode(ThemeMode.light);
                        Navigator.of(sheetCtx).pop();
                      },
                    ),
                    const SizedBox(height: 8),
                    _ThemeOptionTile(
                      title: 'Dark Mode',
                      subtitle: 'Deep navy surfaces optimized for low-light use',
                      icon: Icons.dark_mode_outlined,
                      selected: current == ThemeMode.dark,
                      onTap: () {
                        themeService.setThemeMode(ThemeMode.dark);
                        Navigator.of(sheetCtx).pop();
                      },
                    ),
                    const SizedBox(height: 8),
                    _ThemeOptionTile(
                      title: 'System Default',
                      subtitle: 'Automatically matches your device setting',
                      icon: Icons.brightness_auto_outlined,
                      selected: current == ThemeMode.system,
                      onTap: () {
                        themeService.setThemeMode(ThemeMode.system);
                        Navigator.of(sheetCtx).pop();
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _openRecentEntry(HistoryEntry entry) {
    final result = PredictionResult(
      id: entry.id,
      filePath: entry.filePath,
      mediaType: entry.isImage ? MediaType.image : MediaType.video,
      status: PredictionStatus.completed,
      result: entry.detectionResult == 'authentic'
          ? DetectionResult.authentic
          : entry.detectionResult == 'manipulated'
              ? DetectionResult.manipulated
              : null,
      confidence: entry.confidence,
      timestamp: entry.timestamp,
      framing: entry.framing,
      gradCam: entry.gradCam,
    );
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ResultScreen(
          result: result,
          filePath: entry.filePath ?? '',
          isHistory: true,
          historyProvenance: entry.provenance,
          onAnalyzeAnother: () {
            Navigator.of(context).pop();
            widget.onAnalyzeTap();
          },
          onGoHome: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = DeepGuardPalette.of(context);

    return Scaffold(
      backgroundColor: palette.backgroundSecondary,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(palette),
              const SizedBox(height: 20),
              _buildHeroSection(palette),
              const SizedBox(height: 24),
              _buildWorkflowSummary(palette),
              if (_recentEntries.isNotEmpty) ...[
                const SizedBox(height: 24),
                _buildRecentSection(palette),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(DeepGuardPalette palette) {
    final statusIcon =
        _isOnline ? Icons.cloud_done_outlined : Icons.offline_bolt_outlined;
    final statusColor =
        _isOnline ? palette.successText : palette.textSecondary;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ExcludeSemantics(
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: palette.brandNavy,
              border: Border.all(
                color: palette.accent.withValues(alpha: 0.65),
                width: 1.5,
              ),
            ),
            child: const Center(
              child: Icon(
                Icons.shield_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Semantics(
            header: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'DEEPGUARD',
                    maxLines: 1,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
                Text(
                  'AI-Powered Deepfake Detection',
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          onPressed: () async {
            final online = await _checkInternetConnection();
            if (!mounted) return;
            setState(() => _isOnline = online);
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  online
                      ? 'Connected: Online provenance checks available.'
                      : 'Offline mode: On-device AI detection remains fully available.',
                ),
                duration: const Duration(seconds: 3),
              ),
            );
          },
          tooltip: _isOnline
              ? 'Network status: Online. Tap to refresh connection status.'
              : 'Network status: Offline Ready. Core detection works offline. Tap to refresh.',
          icon: Icon(statusIcon, color: statusColor),
        ),
        IconButton(
          onPressed: _openThemeSheet,
          tooltip: 'Change theme appearance',
          icon: Icon(
            palette.isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
            color: palette.primaryText,
          ),
        ),
      ],
    );
  }

  Widget _buildHeroSection(DeepGuardPalette palette) {
    final statusIcon =
        _isOnline ? Icons.cloud_done_outlined : Icons.offline_bolt_outlined;
    final statusText = _isOnline ? 'Online' : 'Offline Ready';
    final statusColor =
        _isOnline ? palette.successText : palette.textSecondary;

    return GlassCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: palette.processingContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ExcludeSemantics(
                      child: Icon(
                        Icons.verified_user_outlined,
                        size: 16,
                        color: palette.primaryText,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'On-Device Authenticity Check',
                        style: TextStyle(
                          color: palette.primaryText,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _isOnline
                      ? palette.successContainer
                      : palette.surfaceElevated,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ExcludeSemantics(
                      child: Icon(statusIcon, size: 15, color: statusColor),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      statusText,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Semantics(
            header: true,
            child: Text(
              'Check Media Authenticity',
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 24,
                fontWeight: FontWeight.w800,
                height: 1.22,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Analyze images and videos to assess their authenticity.',
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: 16,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),

          // Primary Actions: Upload Image & Upload Video (responsive to font scale)
          LayoutBuilder(
            builder: (context, constraints) {
              final textScale = MediaQuery.textScalerOf(context).scale(1.0);
              final stackVertically =
                  constraints.maxWidth < 275 || textScale > 1.2;

              final uploadImageBtn = FilledButton.icon(
                onPressed: widget.onUploadImageTap ?? widget.onAnalyzeTap,
                icon: const Icon(Icons.image_outlined, size: 20),
                label: const Text('Upload Image'),
              );

              final uploadVideoBtn = FilledButton.tonalIcon(
                onPressed: widget.onUploadVideoTap ?? widget.onAnalyzeTap,
                style: FilledButton.styleFrom(
                  backgroundColor: palette.secondaryButton,
                  foregroundColor: palette.onSecondaryButton,
                  minimumSize: const Size(48, 50),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  side: BorderSide(color: palette.controlBorder, width: 1.2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: Icon(
                  Icons.videocam_outlined,
                  size: 20,
                  color: palette.primaryText,
                ),
                label: const Text('Upload Video'),
              );

              if (stackVertically) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    uploadImageBtn,
                    const SizedBox(height: 10),
                    uploadVideoBtn,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: uploadImageBtn),
                  const SizedBox(width: 10),
                  Expanded(child: uploadVideoBtn),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: widget.onAnalyzeTap,
              icon: Icon(
                Icons.analytics_outlined,
                size: 20,
                color: palette.primaryText,
              ),
              label: const Text('Analyze Media'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkflowSummary(DeepGuardPalette palette) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            'How It Works',
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 19,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 12),
        _WorkflowStepTile(
          stepNumber: '1',
          title: 'Choose Image or Video',
          description: 'Select a saved file or capture a new sample.',
          icon: Icons.perm_media_outlined,
          palette: palette,
        ),
        const SizedBox(height: 10),
        _WorkflowStepTile(
          stepNumber: '2',
          title: 'Inspect Faces & Frames',
          description: 'Media is analyzed privately on your device.',
          icon: Icons.center_focus_strong_outlined,
          palette: palette,
        ),
        const SizedBox(height: 10),
        _WorkflowStepTile(
          stepNumber: '3',
          title: 'Review REAL or A.I. Result',
          description: 'View the authenticity verdict and model confidence.',
          icon: Icons.fact_check_outlined,
          palette: palette,
        ),
      ],
    );
  }

  Widget _buildRecentSection(DeepGuardPalette palette) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  'Recent Analyses',
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            if (widget.onOpenHistoryTap != null)
              TextButton(
                onPressed: widget.onOpenHistoryTap,
                child: const Text('View All'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        for (final entry in _recentEntries) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              onTap: () => _openRecentEntry(entry),
              semanticLabel:
                  '${entry.fileName}, classified as ${entry.resultLabel}, '
                  'model confidence ${entry.confidencePercent.toStringAsFixed(0)} percent, '
                  '${entry.formattedDate}. Activate to open result details.',
              child: ExcludeSemantics(
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: entry.resultContainerFor(palette),
                      ),
                      child: Icon(
                        entry.isImage
                            ? Icons.image_outlined
                            : Icons.videocam_outlined,
                        color: entry.resultTextColorFor(palette),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.fileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            entry.formattedDate,
                            style: TextStyle(
                              color: palette.textMuted,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: entry.resultContainerFor(palette),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: entry
                              .resultColorFor(palette)
                              .withValues(alpha: 0.55),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            entry.resultIcon,
                            size: 16,
                            color: entry.resultTextColorFor(palette),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            entry.resultLabel,
                            style: TextStyle(
                              color: entry.resultTextColorFor(palette),
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _WorkflowStepTile extends StatelessWidget {
  final String stepNumber;
  final String title;
  final String description;
  final IconData icon;
  final DeepGuardPalette palette;

  const _WorkflowStepTile({
    required this.stepNumber,
    required this.title,
    required this.description,
    required this.icon,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ExcludeSemantics(
            child: Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: palette.processingContainer,
                border: Border.all(
                  color: palette.primary.withValues(alpha: 0.35),
                ),
              ),
              child: Text(
                stepNumber,
                style: TextStyle(
                  color: palette.primaryText,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ExcludeSemantics(
            child: Icon(icon, color: palette.accentText, size: 22),
          ),
        ],
      ),
    );
  }
}

class _ThemeOptionTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeOptionTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = DeepGuardPalette.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: '$title. $subtitle',
      child: Material(
        color: selected ? palette.processingContainer : palette.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? palette.primaryButton : palette.border,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: ExcludeSemantics(
              child: Row(
                children: [
                  Icon(
                    icon,
                    color: selected ? palette.primaryText : palette.textSecondary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: palette.textSecondary,
                            fontSize: 13.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (selected)
                    Icon(
                      Icons.check_circle_rounded,
                      color: palette.primaryText,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
