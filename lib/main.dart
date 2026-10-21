import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme/app_theme.dart';
import 'screens/home_screen.dart';
import 'screens/upload_screen.dart';
import 'screens/processing_screen.dart';
import 'screens/result_screen.dart';
import 'screens/about_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/profile_screen.dart';
import 'models/prediction_result.dart';
import 'models/history_entry.dart';
import 'services/profile_service.dart';

@pragma('vm:entry-point')
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  await ProfileService().init();
  runApp(const DeepGuardApp());
}

class DeepGuardApp extends StatelessWidget {
  const DeepGuardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DeepGuard',
      debugShowCheckedModeBanner: false,
      theme: DeepGuardTheme.darkTheme,
      // Use a Navigator key so MainShell can push routes from callbacks
      home: const _IntroGate(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Intro gate: Splash → Onboarding → MainShell (every launch)
// ─────────────────────────────────────────────────────────────────────────────

class _IntroGate extends StatefulWidget {
  const _IntroGate();
  @override
  State<_IntroGate> createState() => _IntroGateState();
}

class _IntroGateState extends State<_IntroGate> {
  bool _splashDone = false;

  void _onSplashDone() => setState(() => _splashDone = true);

  void _onOnboardingDone() {
    // pushReplacement here is intentional — the intro should not be in the
    // back stack. Pressing back from MainShell exits the app (correct).
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const MainShell(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_splashDone) return SplashScreen(onDone: _onSplashDone);
    return OnboardingScreen(onDone: _onOnboardingDone);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Main navigation shell — bottom nav only, no screen stack
// ─────────────────────────────────────────────────────────────────────────────

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  // Bumped to force UploadScreen to rebuild with a fresh state. IndexedStack
  // keeps every tab alive, so without this the previously picked media would
  // still be shown when returning to the Analyze tab. "Analyze Another" bumps
  // it so the user lands back on the media-selection step.
  int _uploadSession = 0;

  // ── Navigate to ProcessingScreen via Navigator.push ────────────────────────
  void _onFileSelected(String filePath, String mediaType, MediaSource source) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProcessingScreen(
          filePath: filePath,
          mediaType: mediaType,
          source: source,
          onComplete: (result) => _onProcessingComplete(result),
        ),
      ),
    );
  }

  void _onProcessingComplete(PredictionResult result) {
    // Save to profile history
    final service = ProfileService();
    final profile = service.activeProfile;
    if (profile != null) {
      final isFake = result.result == DetectionResult.manipulated;
      final entry = HistoryEntry(
        id: result.id,
        filePath: result.filePath,
        mediaType: result.mediaType == MediaType.video ? 'video' : 'image',
        detectionResult: result.result == DetectionResult.authentic
            ? 'authentic'
            : 'manipulated',
        confidence: result.confidence,
        timestamp: result.timestamp,
      );
      service.saveHistoryEntry(profile.id, entry);
      service.incrementStats(profile.id, isFake: isFake);
    }

    // Replace the ProcessingScreen with ResultScreen in the Navigator stack
    // so pressing back from ResultScreen goes back to MainShell (not Processing)
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ResultScreen(
          result: result,
          filePath: result.filePath ?? '',
          onAnalyzeAnother: () {
            // Pop ResultScreen → back to the Analyze tab, and reset
            // UploadScreen so it shows the media-selection step again instead
            // of the previously uploaded file.
            Navigator.of(context).pop();
            setState(() {
              _currentIndex = 1;
              _uploadSession++;
            });
          },
          onGoHome: () {
            // Pop ResultScreen → back to Home tab
            Navigator.of(context).pop();
            setState(() => _currentIndex = 0);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Allow back button to exit app when on MainShell (correct behaviour)
      canPop: true,
      child: Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: [
            HomeScreen(
              onAnalyzeTap: () => setState(() => _currentIndex = 1),
            ),
            UploadScreen(
              key: ValueKey(_uploadSession),
              onFileSelected: _onFileSelected,
            ),
            const AboutScreen(),
            const ProfileScreen(),
          ],
        ),
        bottomNavigationBar: _buildNav(),
      ),
    );
  }

  Widget _buildNav() {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: DeepGuardColors.glassBorder, width: 0.5),
        ),
      ),
      child: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        backgroundColor: DeepGuardColors.surfaceDark,
        selectedItemColor: DeepGuardColors.primary,
        unselectedItemColor: DeepGuardColors.textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedFontSize: 11,
        unselectedFontSize: 11,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.shield_outlined),
            activeIcon: Icon(Icons.shield),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.add_photo_alternate_outlined),
            activeIcon: Icon(Icons.add_photo_alternate),
            label: 'Analyze',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.info_outline),
            activeIcon: Icon(Icons.info),
            label: 'About',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
