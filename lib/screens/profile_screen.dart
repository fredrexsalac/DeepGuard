import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/user_profile.dart';
import '../models/history_entry.dart';
import '../models/prediction_result.dart';
import '../services/profile_service.dart';
import '../services/history_backup_service.dart';
import '../theme/app_theme.dart';
import 'result_screen.dart';
import 'processing_screen.dart';
import 'upload_screen.dart' show MediaSource;

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with TickerProviderStateMixin {
  final _svc = ProfileService();
  List<HistoryEntry> _history = [];
  bool _loading = true;
  bool _editingName = false;
  final _nameCtrl = TextEditingController();

  late final AnimationController _hexCtrl;

  @override
  void initState() {
    super.initState();
    _hexCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 10))..repeat();
    _svc.addListener(_onServiceChanged);
    _loadHistory();
  }

  void _onServiceChanged() {
    if (mounted) {
      _loadHistory();
    }
  }

  @override
  void dispose() {
    _hexCtrl.dispose();
    _nameCtrl.dispose();
    _svc.removeListener(_onServiceChanged);
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final profile = _svc.activeProfile;
    if (profile == null) { setState(() => _loading = false); return; }
    final h = await _svc.getHistory(profile.id);
    if (mounted) setState(() { _history = h; _loading = false; });
  }

  // ── Edit name ──────────────────────────────────────────────────────────────
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
    if (newName.isEmpty) { setState(() => _editingName = false); return; }
    // Update name in profiles list
    final idx = _svc.profiles.indexWhere((p) => p.id == profile.id);
    if (idx >= 0) {
      // ProfileService doesn't expose updateProfile publicly — call saveProfile
      await _svc.updateProfileName(profile.id, newName);
    }
    if (mounted) setState(() => _editingName = false);
  }

  // ── Pick profile picture ───────────────────────────────────────────────────
  Future<void> _pickProfilePicture() async {
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
  }

  // ── History item tap ───────────────────────────────────────────────────────
  void _onHistoryTap(HistoryEntry entry) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0D1035),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _HistoryActionSheet(
        entry: entry,
        onViewResult: () { Navigator.pop(context); _viewResult(entry); },
        onReanalyse: () { Navigator.pop(context); _reanalyse(entry); },
      ),
    );
  }

  void _viewResult(HistoryEntry entry) {
    // Deliberately NOT gated on entry.fileExists. The record itself carries the
    // verdict, confidence, date and provenance snapshot, so the report must stay
    // readable after a data wipe or a restore from backup, when only the media
    // file is gone. ResultScreen degrades the preview to a placeholder in that
    // case. Re-analysis is the operation that genuinely needs the file.
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
    );
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ResultScreen(
        result: result,
        filePath: entry.filePath ?? '',
        isHistory: true,
        historyProvenance: entry.provenance,
        onAnalyzeAnother: () => Navigator.of(context).pop(),
        onGoHome: () => Navigator.of(context).pop(),
      ),
    ));
  }

  void _reanalyse(HistoryEntry entry) {
    if (!entry.fileExists) { _showFileGone(); return; }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ProcessingScreen(
        filePath: entry.filePath!,
        mediaType: entry.mediaType,
        // History does not persist the original capture method; re-analysis of
        // a stored file is treated as a gallery-sourced media item.
        source: MediaSource.gallery,
        onComplete: (result) {
          final updated = HistoryEntry(
            // Match the live result id so the ResultScreen can persist this
            // record's provenance/source-trace snapshot under the same id.
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
          );
          final profile = _svc.activeProfile;
          if (profile != null) {
            _svc.saveHistoryEntry(profile.id, updated);
            _svc.incrementStats(profile.id,
                isFake: result.result == DetectionResult.manipulated);
          }
          Navigator.of(context).pushReplacement(MaterialPageRoute(
            builder: (_) => ResultScreen(
              result: result,
              filePath: entry.filePath ?? '',
              onAnalyzeAnother: () => Navigator.of(context).pop(),
              onGoHome: () => Navigator.of(context).pop(),
            ),
          ));
        },
      ),
    ));
  }

  void _showFileGone() {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('File no longer available on this device.',
          style: TextStyle(fontFamily: 'monospace')),
      backgroundColor: DeepGuardColors.fake,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ── Data backup: export / restore ─────────────────────────────────────────
  //
  // History lives in SharedPreferences, which Android wipes on uninstall, so
  // the user can keep their records across a reinstall by exporting them to a
  // JSON file first and importing that file afterwards. Both actions only ever
  // ADD data on import (records are matched by id), so importing twice cannot
  // duplicate anything, and nothing here is uploaded or shared anywhere.
  bool _busyBackup = false;

  void _showBackupSnack(String text, Color background) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text,
          style: const TextStyle(
              color: Colors.white, fontSize: 12, fontFamily: 'monospace',
              height: 1.4)),
      // Fixed dark background + white text keeps the message readable in both
      // light and dark system themes.
      backgroundColor: background,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 5),
    ));
  }

  Future<int> _countAllRecords() async {
    var total = 0;
    for (final p in _svc.profiles) {
      total += (await _svc.getHistory(p.id)).length;
    }
    return total;
  }

  Future<void> _exportBackup() async {
    if (_busyBackup) return;
    if (_svc.profiles.isEmpty) {
      _showBackupSnack('Nothing to export yet.', const Color(0xFF14161F));
      return;
    }
    setState(() => _busyBackup = true);
    final records = await _countAllRecords();
    try {
      final path = await HistoryBackupService().exportBackup();
      if (path == null) {
        _showBackupSnack(
            'Export cancelled — no file was written.', const Color(0xFF14161F));
      } else {
        final name = path.replaceAll('\\', '/').split('/').last;
        _showBackupSnack(
            'Backup saved as $name ($records record(s), '
            '${_svc.profiles.length} profile(s)). Keep the file outside the '
            'app before uninstalling.',
            DeepGuardColors.authentic);
      }
    } on StateError catch (e) {
      _showBackupSnack(e.message, DeepGuardColors.fake);
    } catch (_) {
      _showBackupSnack('Export failed — the file could not be created.',
          DeepGuardColors.fake);
    } finally {
      if (mounted) setState(() => _busyBackup = false);
    }
  }

  Future<void> _importBackup() async {
    if (_busyBackup) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0D1035),
        title: const Text('Restore From Backup File',
            style: TextStyle(color: DeepGuardColors.textPrimary,
                fontSize: 16, fontWeight: FontWeight.w700)),
        content: const Text(
          'Pick a DeepGuard backup (.json) file.\n\n'
          'Records that are missing on this device are added back; records '
          'already here are skipped, so nothing is duplicated or overwritten.\n\n'
          'A backup stores analysis records and provenance snapshots only — '
          'the analysed photo/video files are not inside it, so their previews '
          'need re-analysis.',
          style: TextStyle(
              color: DeepGuardColors.textSecondary, fontSize: 13,
              height: 1.4)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(color: DeepGuardColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Choose File',
                style: TextStyle(color: DeepGuardColors.primary,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busyBackup = true);
    try {
      final result = await HistoryBackupService().importBackup();
      await _loadHistory();
      _showBackupSnack(
        result.message,
        result.ok
            ? (result.recordsAdded > 0
                ? DeepGuardColors.authentic
                : const Color(0xFF14161F))
            : DeepGuardColors.fake,
      );
    } catch (_) {
      _showBackupSnack('Restore failed — the backup could not be read.',
          DeepGuardColors.fake);
    } finally {
      if (mounted) setState(() => _busyBackup = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final profile = _svc.activeProfile;
    return Scaffold(
      backgroundColor: const Color(0xFF060918),
      body: Stack(children: [
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _hexCtrl,
            builder: (_, __) => CustomPaint(
                painter: _HexBgPainter(t: _hexCtrl.value)),
          ),
        ),
        SafeArea(
          child: Column(children: [
            _buildProfileCard(profile),
            _buildStatsRow(profile),
            _buildBackupRow(),
            _buildHistoryHeader(),
            Expanded(
              // History is stored locally (SharedPreferences) — always available
              // offline. Pull down to reload from disk.
              child: RefreshIndicator(
                onRefresh: _loadHistory,
                color: DeepGuardColors.primary,
                backgroundColor: const Color(0xFF0D1035),
                child: _buildHistoryBody(),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  // ── Profile card ───────────────────────────────────────────────────────────
  Widget _buildProfileCard(UserProfile? profile) {
    final picPath = profile?.profilePicturePath;
    final hasRealPic = picPath != null && File(picPath).existsSync();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        // Avatar / profile picture
        GestureDetector(
          onTap: _pickProfilePicture,
          child: Stack(children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: profile?.avatarColor.withAlpha(30) ?? Colors.transparent,
                border: Border.all(
                  color: profile?.avatarColor ?? DeepGuardColors.primary,
                  width: 2.5,
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
                      profile?.avatarIcon ?? Icons.person,
                      color: profile?.avatarColor ?? DeepGuardColors.primary,
                      size: 32,
                    ),
            ),
            // Camera badge
            Positioned(
              bottom: 0, right: 0,
              child: Container(
                width: 22, height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: DeepGuardColors.primary,
                  border: Border.all(color: const Color(0xFF060918), width: 2),
                ),
                child: const Icon(Icons.camera_alt,
                    size: 12, color: Colors.black),
              ),
            ),
          ]),
        ),
        const SizedBox(width: 16),
        // Name + edit
        Expanded(
          child: _editingName
              ? Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _nameCtrl,
                      autofocus: true,
                      style: const TextStyle(
                          color: DeepGuardColors.textPrimary,
                          fontSize: 18, fontWeight: FontWeight.w800),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 0, vertical: 4),
                        border: UnderlineInputBorder(
                          borderSide: BorderSide(
                              color: DeepGuardColors.primary)),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(
                              color: DeepGuardColors.primary, width: 2)),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(
                              color: DeepGuardColors.primary)),
                      ),
                      onSubmitted: (_) => _saveName(),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.check,
                        color: DeepGuardColors.authentic, size: 20),
                    onPressed: _saveName,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ])
              : Row(children: [
                  Expanded(
                    child: Text(
                      profile?.name ?? 'User',
                      style: const TextStyle(
                          color: DeepGuardColors.textPrimary,
                          fontSize: 20, fontWeight: FontWeight.w900),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  GestureDetector(
                    onTap: _startEditName,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Icon(Icons.edit_outlined,
                          color: DeepGuardColors.primary.withAlpha(160),
                          size: 18),
                    ),
                  ),
                ]),
        ),
      ]),
    );
  }

  // ── Stats ──────────────────────────────────────────────────────────────────
  // TOTAL / FAKE / REAL / FAKE% are derived directly from the visible history
  // records, so they always stay in sync with the list — adding, swipe-deleting
  // a single entry, or Clear All automatically recomputes the numbers. A stored
  // counter can never drift from the records it is meant to summarise.
  Widget _buildStatsRow(UserProfile? p) {
    if (p == null) return const SizedBox.shrink();
    final total = _history.length;
    final fake = _history.where((e) => e.detectionResult == 'manipulated').length;
    final real = _history.where((e) => e.detectionResult == 'authentic').length;
    final fakePct = total == 0 ? 0.0 : (fake / total) * 100;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Row(children: [
        _statTile('TOTAL', total.toString(), DeepGuardColors.primary),
        const SizedBox(width: 8),
        _statTile('FAKE', fake.toString(), DeepGuardColors.fake),
        const SizedBox(width: 8),
        _statTile('REAL', real.toString(), DeepGuardColors.authentic),
        const SizedBox(width: 8),
        _statTile('FAKE%', '${fakePct.toStringAsFixed(0)}%',
            DeepGuardColors.warning),
      ]),
    );
  }

  Future<void> _confirmClearAll() async {
    final profile = _svc.activeProfile;
    if (profile == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0D1035),
        title: const Text('Clear All History',
            style: TextStyle(color: DeepGuardColors.textPrimary,
                fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text(
          'Remove all ${_history.length} record(s) and reset your statistics '
          '(total / real / fake)?\nThis cannot be undone.',
          style: const TextStyle(
              color: DeepGuardColors.textSecondary, fontSize: 13, height: 1.4)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(color: DeepGuardColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear All',
                style: TextStyle(color: DeepGuardColors.fake,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    // Clear the records; the TOTAL/FAKE/REAL tiles are derived from history, so
    // they recompute to zero automatically on the next build.
    await _svc.clearHistory(profile.id);
    await _loadHistory();
    if (mounted) setState(() {});
  }

  /// History body — always scrollable so the RefreshIndicator can be triggered
  /// even while loading or when the list is empty.
  Widget _buildHistoryBody() {
    if (_loading) {
      return _scrollableFill(
          const CircularProgressIndicator(color: DeepGuardColors.primary));
    }
    if (_history.isEmpty) {
      return _scrollableFill(_buildEmptyHistory());
    }
    return _buildHistoryList();
  }

  Widget _scrollableFill(Widget child) => LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(child: child),
          ),
        ),
      );

  Widget _statTile(String label, String value, Color accent) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withAlpha(50)),
        color: accent.withAlpha(10),
      ),
      child: Column(children: [
        Text(value, style: TextStyle(color: accent, fontSize: 16,
            fontWeight: FontWeight.w900)),
        Text(label, style: TextStyle(color: accent.withAlpha(180),
            fontSize: 9, fontWeight: FontWeight.w700,
            letterSpacing: 1, fontFamily: 'monospace')),
      ]),
    ),
  );

  // ── Data backup row ────────────────────────────────────────────────────────
  //
  // Saves every profile + analysis record + provenance snapshot to one JSON
  // file the user can keep, and restores it later (e.g. after reinstalling the
  // app, which wipes local storage). On-device only: no upload, no server.
  Widget _buildBackupRow() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: _BackupBtn(
            icon: _busyBackup
                ? Icons.hourglass_empty_rounded
                : Icons.upload_file_rounded,
            label: 'EXPORT DATA',
            accent: DeepGuardColors.primary,
            enabled: !_busyBackup,
            onTap: _exportBackup)),
        const SizedBox(width: 8),
        Expanded(child: _BackupBtn(
            icon: _busyBackup
                ? Icons.hourglass_empty_rounded
                : Icons.restore_rounded,
            label: 'RESTORE DATA',
            accent: DeepGuardColors.secondary,
            enabled: !_busyBackup,
            onTap: _importBackup)),
      ]),
      const SizedBox(height: 6),
      Text(
        _busyBackup
            ? 'Working on the backup file…'
            : 'Export keeps your records in a file you own; restore reads it '
                'back after a reinstall. Media files are not included.',
        style: TextStyle(
            color: DeepGuardColors.textMuted.withAlpha(180),
            fontSize: 9.5, height: 1.3, fontFamily: 'monospace'),
      ),
    ]),
  );

  // ── History header ─────────────────────────────────────────────────────────
  Widget _buildHistoryHeader() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
    child: Row(children: [
      const Text('HISTORY',
          style: TextStyle(color: DeepGuardColors.textMuted,
              fontSize: 10, letterSpacing: 3,
              fontWeight: FontWeight.w700, fontFamily: 'monospace')),
      const Spacer(),
      if (_history.isNotEmpty)
        GestureDetector(
          onTap: _confirmClearAll,
          child: Text('CLEAR ALL',
              style: TextStyle(color: DeepGuardColors.fake.withAlpha(160),
                  fontSize: 9, letterSpacing: 1, fontFamily: 'monospace')),
        ),
    ]),
  );

  Widget _buildEmptyHistory() => Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(Icons.history, color: DeepGuardColors.textMuted.withAlpha(80), size: 48),
    const SizedBox(height: 12),
    const Text('No analyses yet',
        style: TextStyle(color: DeepGuardColors.textMuted, fontSize: 14)),
    const SizedBox(height: 6),
    Text('Analyse a photo or video to see history here',
        style: TextStyle(color: DeepGuardColors.textMuted.withAlpha(140),
            fontSize: 12)),
  ]);

  Widget _buildHistoryList() => ListView.separated(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
    itemCount: _history.length,
    separatorBuilder: (_, __) => const SizedBox(height: 8),
    itemBuilder: (_, i) {
      final entry = _history[i];
      return Dismissible(
        key: Key(entry.id),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: DeepGuardColors.fake.withAlpha(30),
            border: Border.all(color: DeepGuardColors.fake.withAlpha(60)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.delete_outline,
                  color: DeepGuardColors.fake, size: 20),
              SizedBox(width: 6),
              Text('DELETE',
                  style: TextStyle(
                      color: DeepGuardColors.fake, fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1, fontFamily: 'monospace')),
            ],
          ),
        ),
        confirmDismiss: (_) async {
          return await _confirmDeleteEntry(entry);
        },
        onDismissed: (_) async {
          final profile = _svc.activeProfile;
          if (profile == null) return;
          await _svc.deleteHistoryEntry(profile.id, entry.id);
        },
        child: _HistoryTile(
            entry: entry, onTap: () => _onHistoryTap(entry)),
      );
    },
  );

  Future<bool> _confirmDeleteEntry(HistoryEntry entry) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0D1035),
        title: const Text('Delete Entry',
            style: TextStyle(color: DeepGuardColors.textPrimary,
                fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text(
          'Remove "${entry.fileName}" from history?\nThis cannot be undone.',
          style: const TextStyle(
              color: DeepGuardColors.textSecondary, fontSize: 13,
              height: 1.4)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(color: DeepGuardColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete',
                style: TextStyle(color: DeepGuardColors.fake,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// History widgets
// ─────────────────────────────────────────────────────────────────────────────
class _HistoryTile extends StatelessWidget {
  final HistoryEntry entry;
  final VoidCallback onTap;
  const _HistoryTile({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: entry.resultColor.withAlpha(40)),
        color: entry.resultColor.withAlpha(8),
      ),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: DeepGuardColors.surfaceCard,
          ),
          child: Icon(
            entry.isImage ? Icons.image_outlined : Icons.videocam_outlined,
            color: DeepGuardColors.primary, size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(entry.fileName,
                style: const TextStyle(color: DeepGuardColors.textPrimary,
                    fontSize: 12, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis, maxLines: 1),
            const SizedBox(height: 3),
            Text(entry.formattedDate,
                style: TextStyle(color: DeepGuardColors.textMuted.withAlpha(160),
                    fontSize: 10, fontFamily: 'monospace')),
            if (!entry.fileExists)
              Text('File unavailable',
                  style: TextStyle(color: DeepGuardColors.warning.withAlpha(180),
                      fontSize: 9)),
          ],
        )),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            color: entry.resultColor.withAlpha(20),
            border: Border.all(color: entry.resultColor.withAlpha(80)),
          ),
          child: Column(children: [
            Text(entry.resultLabel,
                style: TextStyle(color: entry.resultColor, fontSize: 11,
                    fontWeight: FontWeight.w800, fontFamily: 'monospace')),
            Text('${entry.confidencePercent.toStringAsFixed(0)}%',
                style: TextStyle(color: entry.resultColor.withAlpha(180),
                    fontSize: 9, fontFamily: 'monospace')),
          ]),
        ),
      ]),
    ),
  );
}

class _HistoryActionSheet extends StatelessWidget {
  final HistoryEntry entry;
  final VoidCallback onViewResult;
  final VoidCallback onReanalyse;
  const _HistoryActionSheet({
    required this.entry,
    required this.onViewResult,
    required this.onReanalyse,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 36, height: 4,
          decoration: BoxDecoration(color: DeepGuardColors.textMuted.withAlpha(80),
              borderRadius: BorderRadius.circular(2))),
      const SizedBox(height: 16),
      Text(entry.fileName,
          style: const TextStyle(color: DeepGuardColors.textPrimary,
              fontSize: 14, fontWeight: FontWeight.w700),
          overflow: TextOverflow.ellipsis),
      const SizedBox(height: 6),
      Text(entry.formattedDate,
          style: const TextStyle(color: DeepGuardColors.textMuted, fontSize: 11)),
      const SizedBox(height: 20),
      _SheetBtn(icon: Icons.analytics_outlined,
          label: 'View Stored Result',
          accent: DeepGuardColors.primary, onTap: onViewResult),
      const SizedBox(height: 10),
      _SheetBtn(icon: Icons.refresh_outlined,
          label: 'Re-Analyse File',
          accent: DeepGuardColors.secondary, onTap: onReanalyse),
      const SizedBox(height: 8),
    ]),
  );
}

class _SheetBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;
  const _SheetBtn({required this.icon, required this.label,
      required this.accent, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: double.infinity, height: 50,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withAlpha(80)),
        color: accent.withAlpha(15),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, color: accent, size: 18),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(color: accent, fontSize: 13,
            fontWeight: FontWeight.w700, letterSpacing: 0.5)),
      ]),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Compact action button used by the data-backup row (export / restore).
// ─────────────────────────────────────────────────────────────────────────────
class _BackupBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;
  final bool enabled;
  final VoidCallback onTap;

  const _BackupBtn({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final alpha = enabled ? 1.0 : 0.45;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: accent.withAlpha((80 * alpha).round())),
          color: accent.withAlpha((15 * alpha).round()),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: accent.withAlpha((220 * alpha).round()),
                size: 15),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    color: accent.withAlpha((230 * alpha).round()),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    fontFamily: 'monospace')),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hex background painter
// ─────────────────────────────────────────────────────────────────────────────
class _HexBgPainter extends CustomPainter {
  final double t;
  const _HexBgPainter({required this.t});
  @override
  void paint(Canvas canvas, Size s) {
    const r = 26.0;
    const h = r * 1.7320508;
    const colW = r * 1.5;
    final cols = (s.width / colW).ceil() + 2;
    final rows = (s.height / h).ceil() + 2;
    final p = Paint()..style = PaintingStyle.stroke..strokeWidth = 0.6;
    for (int col = -1; col < cols; col++) {
      for (int row = -1; row < rows; row++) {
        final cx = col * colW;
        final cy = row * h + (col.isOdd ? h / 2 : 0);
        final phase = cx * 0.007 + cy * 0.005 + t * 2 * 3.14159;
        final alpha = (sin(phase) * 0.5 + 0.5) * 16 + 4;
        p.color = DeepGuardColors.primary.withAlpha(alpha.toInt());
        final path = Path();
        for (int i = 0; i < 6; i++) {
          final a = 3.14159 / 3 * i - 3.14159 / 6;
          final x = cx + r * cos(a);
          final y = cy + r * sin(a);
          i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
        }
        path.close();
        canvas.drawPath(path, p);
      }
    }
  }
  @override
  bool shouldRepaint(_HexBgPainter o) => o.t != t;
}
