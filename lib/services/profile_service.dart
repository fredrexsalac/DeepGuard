import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_profile.dart';
import '../models/analysis_outcome.dart';
import '../models/history_entry.dart';
import '../models/provenance_snapshot.dart';

/// Manages user profiles and per-profile analysis history.
/// All data is stored locally using SharedPreferences (JSON).
///
/// Usage:
///   await ProfileService().init();   // call once in main()
///   ProfileService().activeProfile   // access current user
class ProfileService extends ChangeNotifier {
  static final ProfileService _instance = ProfileService._internal();
  factory ProfileService() => _instance;
  ProfileService._internal();

  static const _profilesKey = 'dg_profiles';
  static const _activeIdKey = 'dg_active_profile_id';
  static const _historyPrefix = 'dg_history_';

  SharedPreferences? _prefs;
  final List<UserProfile> _profiles = [];
  String? _activeId;

  // ── Public getters ─────────────────────────────────────────────────────────

  List<UserProfile> get profiles => List.unmodifiable(_profiles);

  UserProfile? get activeProfile {
    if (_activeId == null) return _profiles.isEmpty ? null : _profiles.first;
    try {
      return _profiles.firstWhere((p) => p.id == _activeId);
    } catch (_) {
      return _profiles.isEmpty ? null : _profiles.first;
    }
  }

  // ── Initialisation ─────────────────────────────────────────────────────────

  /// Must be called once in main() before runApp.
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    await _loadProfiles();
    _activeId = _prefs!.getString(_activeIdKey);

    // Auto-create default profile if none exist
    if (_profiles.isEmpty) {
      await createProfile(
        'Default User',
        kAvatarColors[0],
        kAvatarIcons[0],
      );
    }
  }

  Future<void> _loadProfiles() async {
    final raw = _prefs!.getString(_profilesKey);
    if (raw == null) return;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      _profiles.clear();
      for (final item in list) {
        _profiles.add(UserProfile.fromJson(item as Map<String, dynamic>));
      }
    } catch (_) {
      _profiles.clear();
    }
  }

  Future<void> _saveProfiles() async {
    final encoded = jsonEncode(_profiles.map((p) => p.toJson()).toList());
    await _prefs!.setString(_profilesKey, encoded);
  }

  // ── Profile CRUD ───────────────────────────────────────────────────────────

  /// Creates a new profile. Returns the created profile.
  Future<UserProfile> createProfile(
    String name,
    Color color,
    IconData icon,
  ) async {
    final profile = UserProfile(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name.trim().isEmpty ? 'User' : name.trim(),
      avatarColor: color,
      avatarIcon: icon,
      createdAt: DateTime.now(),
    );
    _profiles.add(profile);
    await _saveProfiles();

    // If this is the first profile, make it active
    if (_profiles.length == 1) {
      await setActiveProfile(profile.id);
    } else {
      notifyListeners();
    }
    return profile;
  }

  Future<void> setActiveProfile(String id) async {
    _activeId = id;
    await _prefs!.setString(_activeIdKey, id);
    notifyListeners();
  }

  Future<void> updateProfileName(String id, String newName) async {
    final idx = _profiles.indexWhere((p) => p.id == id);
    if (idx == -1) return;
    _profiles[idx] = _profiles[idx].copyWith(name: newName);
    await _saveProfiles();
    notifyListeners();
  }

  Future<void> updateProfilePicture(String id, String picturePath) async {
    final idx = _profiles.indexWhere((p) => p.id == id);
    if (idx == -1) return;
    _profiles[idx] = _profiles[idx].copyWith(profilePicturePath: picturePath);
    await _saveProfiles();
    notifyListeners();
  }

  Future<void> deleteProfile(String id) async {
    if (_profiles.length <= 1) return; // never delete the last profile
    _profiles.removeWhere((p) => p.id == id);
    await _saveProfiles();
    // Clear history for this profile
    await _prefs!.remove('$_historyPrefix$id');
    // If deleted profile was active, switch to first available
    if (_activeId == id) {
      await setActiveProfile(_profiles.first.id);
    } else {
      notifyListeners();
    }
  }

  Future<void> _updateProfile(UserProfile updated) async {
    final idx = _profiles.indexWhere((p) => p.id == updated.id);
    if (idx == -1) return;
    _profiles[idx] = updated;
    await _saveProfiles();
    notifyListeners();
  }

  // ── Stats ──────────────────────────────────────────────────────────────────

  Future<void> incrementStats(
    String profileId, {
    required bool isFake,
  }) async {
    final profile = _profiles.firstWhere(
      (p) => p.id == profileId,
      orElse: () => throw StateError('Profile $profileId not found'),
    );
    await _updateProfile(profile.copyWith(
      totalAnalyses: profile.totalAnalyses + 1,
      fakeDetections: profile.fakeDetections + (isFake ? 1 : 0),
    ));
  }

  // ── History ────────────────────────────────────────────────────────────────

  String _historyKey(String profileId) => '$_historyPrefix$profileId';

  Future<void> saveHistoryEntry(
      String profileId, HistoryEntry entry) async {
    final existing = await getHistory(profileId);
    existing.insert(0, entry); // newest first
    final encoded = jsonEncode(existing.map((e) => e.toJson()).toList());
    await _prefs!.setString(_historyKey(profileId), encoded);
    notifyListeners();
  }

  Future<List<HistoryEntry>> getHistory(String profileId) async {
    final raw = _prefs!.getString(_historyKey(profileId));
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final entries = <HistoryEntry>[];
      for (final item in list) {
        try {
          if (item is Map<String, dynamic>) {
            entries.add(HistoryEntry.fromJson(item));
          } else if (item is Map) {
            entries.add(HistoryEntry.fromJson(Map<String, dynamic>.from(item)));
          }
        } catch (_) {}
      }
      return entries;
    } catch (_) {
      return [];
    }
  }

  Future<void> clearHistory(String profileId) async {
    await _prefs!.remove(_historyKey(profileId));
    notifyListeners();
  }

  Future<void> deleteHistoryEntry(String profileId, String entryId) async {
    final entries = await getHistory(profileId);
    entries.removeWhere((e) => e.id == entryId);
    final encoded = jsonEncode(entries.map((e) => e.toJson()).toList());
    await _prefs!.setString(_historyKey(profileId), encoded);
    notifyListeners();
  }

  /// Attaches a provenance/source-trace snapshot to an existing history entry
  /// (matched by [entryId]) without creating a duplicate. Called after a live
  /// analysis's source trace settles, so the record can later be replayed
  /// offline. No-op if the entry no longer exists.
  Future<void> updateHistoryProvenance(
    String profileId,
    String entryId,
    ProvenanceSnapshot provenance,
  ) async {
    final entries = await getHistory(profileId);
    final idx = entries.indexWhere((e) => e.id == entryId);
    if (idx == -1) return;
    entries[idx] = entries[idx].copyWith(provenance: provenance);
    final encoded = jsonEncode(entries.map((e) => e.toJson()).toList());
    await _prefs!.setString(_historyKey(profileId), encoded);
    notifyListeners();
  }

  /// Records (or clears) the user's own declaration of what a saved record's
  /// media actually is, so a verdict can be scored as TP / TN / FP / FN.
  ///
  /// [declaredTruth] is 'authentic', 'manipulated', or null to remove an
  /// annotation the user took back. The replacement entry is rebuilt field by
  /// field rather than through copyWith precisely because copyWith cannot
  /// express "set to null". Nothing here touches [HistoryEntry.detectionResult]:
  /// disagreeing with the model never rewrites the model's answer.
  Future<void> updateHistoryDeclaration(
    String profileId,
    String entryId,
    String? declaredTruth, {
    String source = DeclaredTruthSource.user,
  }) async {
    final entries = await getHistory(profileId);
    final idx = entries.indexWhere((e) => e.id == entryId);
    if (idx == -1) return;
    final e = entries[idx];
    entries[idx] = HistoryEntry(
      id: e.id,
      filePath: e.filePath,
      mediaType: e.mediaType,
      detectionResult: e.detectionResult,
      confidence: e.confidence,
      timestamp: e.timestamp,
      provenance: e.provenance,
      framing: e.framing,
      declaredTruth: declaredTruth,
      declaredTruthSource: declaredTruth == null ? null : source,
    );
    final encoded = jsonEncode(entries.map((e) => e.toJson()).toList());
    await _prefs!.setString(_historyKey(profileId), encoded);
    notifyListeners();
  }

  /// Applies the provenance-derived declaration rule to one record, once.
  ///
  /// Called when a live analysis's provenance settles. It writes nothing when
  /// the rule does not fire, and it never touches a record that already carries
  /// a declaration: a human who has answered the question outranks the
  /// inference, in both directions, permanently.
  ///
  /// The stored source is [DeclaredTruthSource.autoProvenance] so these records
  /// can be filtered out of any tally that claims to rest on ground truth.
  Future<void> applyAutoDeclaration(
    String profileId,
    String entryId,
    ProvenanceSnapshot snapshot,
  ) async {
    final entries = await getHistory(profileId);
    final idx = entries.indexWhere((e) => e.id == entryId);
    if (idx == -1) return;
    final e = entries[idx];
    if (e.declaredTruth != null) return;
    final truth = autoTruthFromProvenance(snapshot, e.detectionResult);
    if (truth == null) return;
    await updateHistoryDeclaration(profileId, entryId, truth,
        source: DeclaredTruthSource.autoProvenance);
  }

  // ── Stats reset ────────────────────────────────────────────────────────────

  Future<void> resetStats(String profileId) async {
    final idx = _profiles.indexWhere((p) => p.id == profileId);
    if (idx == -1) return;
    _profiles[idx] = _profiles[idx].copyWith(
      totalAnalyses: 0,
      fakeDetections: 0,
    );
    await _saveProfiles();
    notifyListeners();
  }

  // ── Backup / restore ───────────────────────────────────────────────────────
  //
  // All app data lives in SharedPreferences, which the OS deletes on
  // uninstall. These two methods are the merge primitives used by
  // HistoryBackupService to rebuild that data from an exported file after a
  // fresh install. Both are ADDITIVE: an existing profile is never overwritten
  // and an existing history record (matched by id) is never duplicated, so
  // importing the same backup twice cannot corrupt or double-count anything.

  /// Inserts [profile] only when no profile with the same id exists yet.
  /// Returns true when it was added, false when it was already present.
  Future<bool> ensureProfile(UserProfile profile) async {
    if (_profiles.any((p) => p.id == profile.id)) return false;
    _profiles.add(profile);
    await _saveProfiles();
    notifyListeners();
    return true;
  }

  /// Merges restored history into [profileId]'s records, newest first, skipping
  /// entries whose id is already stored. Returns how many entries were added.
  Future<int> restoreHistory(
      String profileId, List<HistoryEntry> entries) async {
    if (entries.isEmpty) return 0;
    final existing = await getHistory(profileId);
    final ids = existing.map((e) => e.id).toSet();
    final additions =
        entries.where((e) => !ids.contains(e.id)).toList(growable: false);
    if (additions.isEmpty) return 0;
    final merged = <HistoryEntry>[...existing, ...additions]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final encoded = jsonEncode(merged.map((e) => e.toJson()).toList());
    await _prefs!.setString(_historyKey(profileId), encoded);
    notifyListeners();
    return additions.length;
  }

  /// Makes [profileId] active when it names a profile that exists, so a restore
  /// can put the user back on the profile they were using when they exported.
  Future<void> setActiveProfileIfPresent(String profileId) async {
    if (_profiles.any((p) => p.id == profileId)) {
      await setActiveProfile(profileId);
    }
  }
}
