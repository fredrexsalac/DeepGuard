import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../models/user_profile.dart';
import '../models/analysis_outcome.dart';
import '../models/history_entry.dart';
import '../models/prediction_result.dart';
import '../services/profile_service.dart';
import '../services/history_backup_service.dart';
import '../services/theme_service.dart';
import '../theme/app_theme.dart';
import '../widgets/deepguard_app_bar.dart';
import '../widgets/glass_card.dart';
import 'result_screen.dart';
import 'processing_screen.dart';
import 'upload_screen.dart' show MediaSource;

/// DeepGuard Settings, Profile & History Screen.
///
/// Provides:
///   1. Accessible Light / Dark / System Default theme selector with instant
///      application and persistent storage.
///   2. Profile customization (avatar & display name).
///   3. Local backup export & restore.
///   4. Accessible analysis history with REAL / A.I. badges, provenance
///      cross-check tally, and both swipe + non-swipe record management.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _svc = ProfileService();
  final _themeSvc = ThemeService();
  List<HistoryEntry> _history = [];
  bool _loading = true;
  bool _editingName = false;
  bool _busyBackup = false;
  final _nameCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _svc.addListener(_onServiceChanged);
    _loadHistory();
  }

  void _onServiceChanged() {
    if (mounted) _loadHistory();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _svc.removeListener(_onServiceChanged);
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final profile = _svc.activeProfile;
    if (profile == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final h = await _svc.getHistory(profile.id);
    if (mounted) {
      setState(() {
        _history = h;
        _loading = false;
      });
    }
  }

  void _startEditName() {
    final profile = _svc.activeProfile;
    if (profile == null) return;
    _nameCtrl.text = profile.name;
    setState(() => _editingName = true);
  }

  Future<void> _saveName() async {
    final profile = _svc.activeProfile;
    if (profile == null) return;
    final newName = _nameCtrl.text.trim();
    if (newName.isNotEmpty) {
      await _svc.updateProfileName(profile.id, newName);
    }
    if (mounted) setState(() => _editingName = false);
  }

  Future<void> _pickProfilePicture() async {
    try {
      final x = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 400,
      );
      if (x == null) return;
      final profile = _svc.activeProfile;
      if (profile == null) return;
      await _svc.updateProfilePicture(profile.id, x.path);
      if (mounted) setState(() {});
    } on MissingPluginException {
      // Safe fallback in test environment
    } catch (_) {
      _showSnack('Could not update profile picture.', isError: true);
    }
  }

  void _onHistoryTap(HistoryEntry entry) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) => _HistoryActionSheet(
        entry: entry,
        onViewResult: () {
          Navigator.pop(sheetCtx);
          _viewResult(entry);
        },
        onReanalyse: () {
          Navigator.pop(sheetCtx);
          _reanalyse(entry);
        },
        onDelete: () async {
          Navigator.pop(sheetCtx);
          final confirmed = await _confirmDeleteEntry(entry);
          if (confirmed && mounted) {
            final profile = _svc.activeProfile;
            if (profile != null) {
              await _svc.deleteHistoryEntry(profile.id, entry.id);
            }
          }
        },
      ),
    );
  }

  void _viewResult(HistoryEntry entry) {
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
          onAnalyzeAnother: () => Navigator.of(context).pop(),
          onGoHome: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  void _reanalyse(HistoryEntry entry) {
    if (!entry.fileExists) {
      _showSnack(
        'Original media file is no longer available on this device.',
        isError: true,
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProcessingScreen(
          filePath: entry.filePath!,
          mediaType: entry.mediaType,
          source: MediaSource.gallery,
          onComplete: (result) {
            final updated = HistoryEntry(
              id: result.id,
              filePath: entry.filePath,
              mediaType: entry.mediaType,
              detectionResult: result.result == DetectionResult.authentic
                  ? 'authentic'
                  : result.result == DetectionResult.manipulated
                      ? 'manipulated'
                      : null,
              confidence: result.confidence,
              timestamp: DateTime.now(),
              framing: result.framing,
              gradCam: result.gradCam,
            );
            final profile = _svc.activeProfile;
            if (profile != null && result.status == PredictionStatus.completed) {
              _svc.saveHistoryEntry(profile.id, updated);
              _svc.incrementStats(
                profile.id,
                isFake: result.result == DetectionResult.manipulated,
              );
            }
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => ResultScreen(
                  result: result,
                  filePath: entry.filePath ?? '',
                  onAnalyzeAnother: () => Navigator.of(context).pop(),
                  onGoHome: () => Navigator.of(context).pop(),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _showSnack(String text, {bool isError = false, bool isSuccess = false}) {
    if (!mounted) return;
    final palette = DeepGuardPalette.of(context);
    final bg = isError
        ? palette.dangerButton
        : isSuccess
            ? const Color(0xFF117A50)
            : palette.brandNavy;
    final fg = isError ? palette.onDangerButton : Colors.white;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: bg,
        content: Text(
          text,
          style: TextStyle(color: fg, fontSize: 14.5),
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _exportBackup() async {
    if (_busyBackup) return;
    if (_svc.profiles.isEmpty) {
      _showSnack('Nothing to export yet.');
      return;
    }
    setState(() => _busyBackup = true);
    try {
      final exportRes = await HistoryBackupService().exportEvidenceArchive();
      if (exportRes == null) {
        _showSnack('Export cancelled — no archive was written.');
      } else {
        _showSnack(
          'Evidence archive saved as ${exportRes.fileName} '
          '(${exportRes.recordsCount} record(s), '
          '${exportRes.evidenceFilesCount} image/video evidence file(s)).',
          isSuccess: true,
        );
      }
    } on StateError catch (e) {
      _showSnack(e.message, isError: true);
    } catch (_) {
      _showSnack(
        'Export failed — the ZIP evidence archive could not be created.',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _busyBackup = false);
    }
  }

  Future<void> _importBackup() async {
    if (_busyBackup) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: const Text('Restore Evidence Archive'),
        content: const Text(
          'Select a DeepGuard Evidence Archive (.zip) or legacy backup (.json).\n\n'
          'Restores saved records, provenance snapshots, and bundled image or '
          'video evidence for previous results without duplicating entries.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dlgCtx, true),
            child: const Text('Choose Archive'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busyBackup = true);
    try {
      final result = await HistoryBackupService().importBackup();
      await _loadHistory();
      _showSnack(
        result.message,
        isError: !result.ok && !result.cancelled,
        isSuccess:
            result.ok && (result.recordsAdded > 0 || result.evidenceRestored > 0),
      );
    } catch (_) {
      _showSnack('Restore failed — the archive could not be read.', isError: true);
    } finally {
      if (mounted) setState(() => _busyBackup = false);
    }
  }

  Future<void> _confirmClearAll() async {
    final profile = _svc.activeProfile;
    if (profile == null) return;
    final palette = DeepGuardPalette.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: const Text('Clear All History'),
        content: Text(
          'Remove all ${_history.length} saved record(s) and reset your summary counts? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dlgCtx, true),
            style: FilledButton.styleFrom(
              backgroundColor: palette.dangerButton,
              foregroundColor: palette.onDangerButton,
            ),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _svc.clearHistory(profile.id);
    await _loadHistory();
    if (mounted) setState(() {});
  }

  Future<bool> _confirmDeleteEntry(HistoryEntry entry) async {
    final palette = DeepGuardPalette.of(context);
    final result = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: const Text('Delete Record'),
        content: Text(
          'Remove "${entry.fileName}" from your history? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dlgCtx, true),
            style: FilledButton.styleFrom(
              backgroundColor: palette.dangerButton,
              foregroundColor: palette.onDangerButton,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final palette = DeepGuardPalette.of(context);
    final profile = _svc.activeProfile;
    final showTally = _history.isNotEmpty;
    final tally = OutcomeTally.from(_history.map((e) => e.outcome));

    return Scaffold(
      backgroundColor: palette.backgroundSecondary,
      appBar: const DeepGuardAppBar(title: 'Settings & History'),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadHistory,
          color: palette.primaryButton,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _buildThemeCard(palette),
                    const SizedBox(height: 16),
                    _buildProfileCard(profile, palette),
                    const SizedBox(height: 16),
                    if (profile != null) ...[
                      _buildStatsSection(palette),
                      const SizedBox(height: 16),
                    ],
                    _buildBackupCard(palette),
                    const SizedBox(height: 20),
                    _buildHistoryHeader(palette),
                    if (showTally) ...[
                      const SizedBox(height: 8),
                      _OutcomeTallyCard(tally: tally),
                      const SizedBox(height: 10),
                    ],
                  ]),
                ),
              ),
              if (_loading)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: CircularProgressIndicator(
                      color: palette.processingStatus,
                    ),
                  ),
                )
              else if (_history.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                    child: _buildEmptyHistory(palette),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                  sliver: SliverList.separated(
                    itemCount: _history.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, index) => _historyTile(
                      _history[index],
                      palette,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Theme Selector Card (Light / Dark / System Default) ────────────────────
  Widget _buildThemeCard(DeepGuardPalette palette) {
    return ListenableBuilder(
      listenable: _themeSvc,
      builder: (context, _) {
        final mode = _themeSvc.themeMode;
        return GlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Row(
                  children: [
                    ExcludeSemantics(
                      child: Icon(
                        Icons.palette_outlined,
                        color: palette.primaryText,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Appearance Theme',
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Updates immediately and saves your preference across sessions.',
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  final textScale =
                      MediaQuery.textScalerOf(context).scale(1.0);
                  final useVerticalChoices =
                      constraints.maxWidth < 275 || textScale > 1.25;

                  if (useVerticalChoices) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _ThemeChoiceButton(
                          label: 'Light Mode',
                          icon: Icons.light_mode_outlined,
                          selected: mode == ThemeMode.light,
                          onTap: () => _themeSvc.setThemeMode(ThemeMode.light),
                          palette: palette,
                        ),
                        const SizedBox(height: 8),
                        _ThemeChoiceButton(
                          label: 'Dark Mode',
                          icon: Icons.dark_mode_outlined,
                          selected: mode == ThemeMode.dark,
                          onTap: () => _themeSvc.setThemeMode(ThemeMode.dark),
                          palette: palette,
                        ),
                        const SizedBox(height: 8),
                        _ThemeChoiceButton(
                          label: 'System Default',
                          icon: Icons.brightness_auto_outlined,
                          selected: mode == ThemeMode.system,
                          onTap: () => _themeSvc.setThemeMode(ThemeMode.system),
                          palette: palette,
                        ),
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Expanded(
                        child: _ThemeChoiceButton(
                          label: 'Light',
                          semanticLabel: 'Light Mode',
                          icon: Icons.light_mode_outlined,
                          selected: mode == ThemeMode.light,
                          onTap: () => _themeSvc.setThemeMode(ThemeMode.light),
                          palette: palette,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _ThemeChoiceButton(
                          label: 'Dark',
                          semanticLabel: 'Dark Mode',
                          icon: Icons.dark_mode_outlined,
                          selected: mode == ThemeMode.dark,
                          onTap: () => _themeSvc.setThemeMode(ThemeMode.dark),
                          palette: palette,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _ThemeChoiceButton(
                          label: 'System',
                          semanticLabel: 'System Default',
                          icon: Icons.brightness_auto_outlined,
                          selected: mode == ThemeMode.system,
                          onTap: () => _themeSvc.setThemeMode(ThemeMode.system),
                          palette: palette,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Profile Card ───────────────────────────────────────────────────────────
  Widget _buildProfileCard(UserProfile? profile, DeepGuardPalette palette) {
    final picPath = profile?.profilePicturePath;
    final hasRealPic = picPath != null && File(picPath).existsSync();

    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Semantics(
            button: true,
            label: 'Change profile picture',
            child: InkWell(
              onTap: _pickProfilePicture,
              customBorder: const CircleBorder(),
              child: ExcludeSemantics(
                child: Stack(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: palette.processingContainer,
                        border: Border.all(
                          color: palette.primaryButton,
                          width: 2,
                        ),
                        image: hasRealPic
                            ? DecorationImage(
                                image: FileImage(File(picPath)),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: hasRealPic
                          ? null
                          : Icon(
                              profile?.avatarIcon ?? Icons.person_rounded,
                              color: palette.primaryText,
                              size: 30,
                            ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: palette.primaryButton,
                          border: Border.all(color: palette.surface, width: 2),
                        ),
                        child: Icon(
                          Icons.camera_alt_rounded,
                          size: 13,
                          color: palette.onPrimaryButton,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: _editingName
                ? Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _nameCtrl,
                          autofocus: true,
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Profile Name',
                            isDense: true,
                          ),
                          onSubmitted: (_) => _saveName(),
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: Icon(
                          Icons.check_rounded,
                          color: palette.successText,
                        ),
                        tooltip: 'Save profile name',
                        onPressed: _saveName,
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              profile?.name ?? 'User',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: palette.textPrimary,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Local Device Profile',
                              style: TextStyle(
                                color: palette.textMuted,
                                fontSize: 13.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: _startEditName,
                        tooltip: 'Edit profile name',
                        icon: Icon(
                          Icons.edit_outlined,
                          color: palette.primaryText,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // ── Summary Statistics ─────────────────────────────────────────────────────
  Widget _buildStatsSection(DeepGuardPalette palette) {
    final total = _history.length;
    final aiCount =
        _history.where((e) => e.detectionResult == 'manipulated').length;
    final realCount =
        _history.where((e) => e.detectionResult == 'authentic').length;
    final aiPct = total == 0 ? 0.0 : (aiCount / total) * 100;

    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1.0);
        final useTwoByTwo = constraints.maxWidth < 360 || textScale > 1.2;

        final tiles = [
          _StatTile(
            label: 'Total',
            value: '$total',
            color: palette.primaryText,
            palette: palette,
          ),
          _StatTile(
            label: 'REAL',
            value: '$realCount',
            color: palette.realText,
            palette: palette,
          ),
          _StatTile(
            label: 'A.I.',
            value: '$aiCount',
            color: palette.aiText,
            palette: palette,
          ),
          _StatTile(
            label: 'A.I. Share',
            value: '${aiPct.toStringAsFixed(0)}%',
            color: palette.warningText,
            palette: palette,
          ),
        ];

        if (useTwoByTwo) {
          return Column(
            children: [
              Row(
                children: [
                  Expanded(child: tiles[0]),
                  const SizedBox(width: 8),
                  Expanded(child: tiles[1]),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: tiles[2]),
                  const SizedBox(width: 8),
                  Expanded(child: tiles[3]),
                ],
              ),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: tiles[0]),
            const SizedBox(width: 8),
            Expanded(child: tiles[1]),
            const SizedBox(width: 8),
            Expanded(child: tiles[2]),
            const SizedBox(width: 8),
            Expanded(child: tiles[3]),
          ],
        );
      },
    );
  }

  // ── Backup Card ────────────────────────────────────────────────────────────
  Widget _buildBackupCard(DeepGuardPalette palette) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              'Evidence Backup & Restore (ZIP)',
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _busyBackup
                ? 'Packaging or extracting ZIP evidence archive…'
                : 'Export saved results with their analyzed image and video evidence as a portable ZIP archive, or restore them on any device.',
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: 13.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final textScale = MediaQuery.textScalerOf(context).scale(1.0);
              final stackButtons =
                  constraints.maxWidth < 275 || textScale > 1.25;

              final exportBtn = OutlinedButton.icon(
                onPressed: _busyBackup ? null : _exportBackup,
                icon: const Icon(Icons.folder_zip_outlined, size: 18),
                label: const Text('Export ZIP'),
              );
              final restoreBtn = OutlinedButton.icon(
                onPressed: _busyBackup ? null : _importBackup,
                icon: const Icon(Icons.restore_rounded, size: 18),
                label: const Text('Restore ZIP'),
              );

              if (stackButtons) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    exportBtn,
                    const SizedBox(height: 8),
                    restoreBtn,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: exportBtn),
                  const SizedBox(width: 10),
                  Expanded(child: restoreBtn),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryHeader(DeepGuardPalette palette) {
    return Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              'Analysis History',
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        if (_history.isNotEmpty)
          TextButton.icon(
            onPressed: _confirmClearAll,
            icon: Icon(
              Icons.delete_sweep_outlined,
              size: 18,
              color: palette.errorText,
            ),
            label: Text(
              'Clear All',
              style: TextStyle(color: palette.errorText),
            ),
          ),
      ],
    );
  }

  Widget _buildEmptyHistory(DeepGuardPalette palette) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: Icon(
              Icons.history_rounded,
              color: palette.textMuted,
              size: 46,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'No saved analyses yet',
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Analyze an image or video to build your local history.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _historyTile(HistoryEntry entry, DeepGuardPalette palette) {
    return Dismissible(
      key: Key(entry.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: palette.errorContainer,
          border: Border.all(color: palette.error),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline_rounded, color: palette.errorText),
            const SizedBox(width: 6),
            Text(
              'Delete',
              style: TextStyle(
                color: palette.errorText,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
      confirmDismiss: (_) => _confirmDeleteEntry(entry),
      onDismissed: (_) async {
        final profile = _svc.activeProfile;
        if (profile == null) return;
        await _svc.deleteHistoryEntry(profile.id, entry.id);
      },
      child: _HistoryTile(
        entry: entry,
        onTap: () => _onHistoryTap(entry),
      ),
    );
  }
}

class _ThemeChoiceButton extends StatelessWidget {
  final String label;
  final String? semanticLabel;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final DeepGuardPalette palette;

  const _ThemeChoiceButton({
    required this.label,
    this.semanticLabel,
    required this.icon,
    required this.selected,
    required this.onTap,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel ?? label,
      child: Material(
        color: selected ? palette.primaryButton : palette.backgroundSecondary,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? palette.primaryButton : palette.controlBorder,
                width: selected ? 1.5 : 1.1,
              ),
            ),
            child: ExcludeSemantics(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: selected
                        ? palette.onPrimaryButton
                        : palette.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected
                            ? palette.onPrimaryButton
                            : palette.textPrimary,
                        fontSize: 14,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w600,
                      ),
                    ),
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

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final DeepGuardPalette palette;

  const _StatTile({
    required this.label,
    required this.value,
    required this.color,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      child: Semantics(
        label: '$label: $value',
        child: ExcludeSemantics(
          child: Column(
            children: [
              Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OutcomeTallyCard extends StatelessWidget {
  final OutcomeTally tally;
  const _OutcomeTallyCard({required this.tally});

  static const _cells = [
    ('TP', 'True Positive'),
    ('TN', 'True Negative'),
    ('FP', 'False Positive'),
    ('FN', 'False Negative'),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = DeepGuardPalette.of(context);
    final values = [
      tally.truePositive,
      tally.trueNegative,
      tally.falsePositive,
      tally.falseNegative,
    ];
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Provenance Cross-Check Summary',
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            tally.isEmpty
                ? 'No saved records contain embedded generator or camera tags for cross-checking yet.'
                : '${tally.evidenced} saved record(s) contained embedded metadata for comparison.',
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: 13.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var i = 0; i < _cells.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: Semantics(
                    label: '${_cells[i].$2}: ${values[i]}',
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: palette.backgroundSecondary,
                        border: Border.all(color: palette.border),
                      ),
                      child: ExcludeSemantics(
                        child: Column(
                          children: [
                            Text(
                              '${values[i]}',
                              style: TextStyle(
                                color: values[i] > 0
                                    ? palette.textPrimary
                                    : palette.textMuted,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _cells[i].$1,
                              style: TextStyle(
                                color: palette.textSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final HistoryEntry entry;
  final VoidCallback onTap;
  const _HistoryTile({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final palette = DeepGuardPalette.of(context);
    final badgeText = entry.resultTextColorFor(palette);
    final badgeBg = entry.resultContainerFor(palette);
    final badgeBorder = entry.resultColorFor(palette);

    return GlassCard(
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      semanticLabel:
          '${entry.fileName}, ${entry.isImage ? "Image" : "Video"}, '
          'classified as ${entry.resultLabel}, '
          'model confidence ${entry.confidencePercent.toStringAsFixed(0)} percent, '
          '${entry.formattedDate}. Activate for options.',
      child: ExcludeSemantics(
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: badgeBg,
              ),
              child: Icon(
                entry.isImage ? Icons.image_outlined : Icons.videocam_outlined,
                color: badgeText,
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
                  const SizedBox(height: 3),
                  Text(
                    entry.formattedDate,
                    style: TextStyle(
                      color: palette.textMuted,
                      fontSize: 13,
                    ),
                  ),
                  if (entry.fileExists)
                    Text(
                      '${entry.isImage ? "Image" : "Video"} evidence retained',
                      style: TextStyle(
                        color: palette.accentText,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  else
                    Text(
                      'Media evidence unavailable',
                      style: TextStyle(
                        color: palette.warningText,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  if (entry.outcome != null)
                    Text(
                      '${entry.outcome!.shortCode} · ${entry.outcome!.uiTag}',
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: badgeBg,
                border: Border.all(color: badgeBorder.withValues(alpha: 0.55)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(entry.resultIcon, size: 15, color: badgeText),
                      const SizedBox(width: 4),
                      Text(
                        entry.resultLabel,
                        style: TextStyle(
                          color: badgeText,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${entry.confidencePercent.toStringAsFixed(0)}%',
                    style: TextStyle(
                      color: badgeText,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryActionSheet extends StatelessWidget {
  final HistoryEntry entry;
  final VoidCallback onViewResult;
  final VoidCallback onReanalyse;
  final VoidCallback onDelete;

  const _HistoryActionSheet({
    required this.entry,
    required this.onViewResult,
    required this.onReanalyse,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final palette = DeepGuardPalette.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                entry.fileName,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${entry.resultLabel} · ${entry.formattedDate}',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 13.5,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onViewResult,
              icon: const Icon(Icons.fact_check_outlined, size: 19),
              label: const Text('View Saved Result'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: onReanalyse,
              icon: const Icon(Icons.refresh_rounded, size: 19),
              label: const Text('Re-Analyze Media'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: onDelete,
              style: OutlinedButton.styleFrom(
                foregroundColor: palette.errorText,
                side: BorderSide(color: palette.error, width: 1.2),
              ),
              icon: Icon(
                Icons.delete_outline_rounded,
                size: 19,
                color: palette.errorText,
              ),
              label: const Text('Delete Record'),
            ),
          ],
        ),
      ),
    );
  }
}
