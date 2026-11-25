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
import 'services/theme_service.dart';

@pragma('vm:entry-point')
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await ProfileService().init();
  await ThemeService().init();
  runApp(const DeepGuardApp());
}

class DeepGuardApp extends StatelessWidget {
  const DeepGuardApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeService = ThemeService();
    return ListenableBuilder(
      listenable: themeService,
      builder: (context, _) {
        return MaterialApp(
          title: 'DeepGuard',
          debugShowCheckedModeBanner: false,
          theme: DeepGuardTheme.lightTheme,
          darkTheme: DeepGuardTheme.darkTheme,
          themeMode: themeService.themeMode,
          builder: (context, child) {
            final brightness = Theme.of(context).brightness;
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: DeepGuardTheme.overlayStyleFor(brightness),
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: const _IntroGate(),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Intro gate: Splash → Onboarding (first launch) → MainShell
// ─────────────────────────────────────────────────────────────────────────────

class _IntroGate extends StatefulWidget {
  const _IntroGate();
  @override
  State<_IntroGate> createState() => _IntroGateState();
}

class _IntroGateState extends State<_IntroGate> {
  bool _splashDone = false;

  void _onSplashDone() {
    if (!mounted) return;
    if (ThemeService().onboardingCompleted) {
      _enterMainShell();
    } else {
      setState(() => _splashDone = true);
    }
  }

  Future<void> _onOnboardingDone() async {
    await ThemeService().setOnboardingCompleted(true);
    if (!mounted) return;
    _enterMainShell();
  }

  void _enterMainShell() {
    final reduceMotion = shouldReduceMotion(context);
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const MainShell(),
        transitionsBuilder: (_, anim, __, child) => reduceMotion
            ? child
            : FadeTransition(opacity: anim, child: child),
        transitionDuration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 280),
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
// Main navigation shell — accessible Material 3 NavigationBar
// ─────────────────────────────────────────────────────────────────────────────

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;
  int _uploadSession = 0;
  UploadInitialAction _pendingUploadAction = UploadInitialAction.none;

  void _openUploadWithAction(UploadInitialAction action) {
    setState(() {
      _currentIndex = 1;
      _pendingUploadAction = action;
      if (action != UploadInitialAction.none) {
        _uploadSession++;
      }
    });
  }

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
    final service = ProfileService();
    final profile = service.activeProfile;
    if (profile != null && result.status == PredictionStatus.completed) {
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
        framing: result.framing,
        gradCam: result.gradCam,
      );
      service.saveHistoryEntry(profile.id, entry);
      service.incrementStats(profile.id, isFake: isFake);
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ResultScreen(
          result: result,
          filePath: result.filePath ?? '',
          onAnalyzeAnother: () {
            Navigator.of(context).pop();
            setState(() {
              _currentIndex = 1;
              _pendingUploadAction = UploadInitialAction.none;
              _uploadSession++;
            });
          },
          onGoHome: () {
            Navigator.of(context).pop();
            setState(() => _currentIndex = 0);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = DeepGuardPalette.of(context);
    return PopScope(
      canPop: _currentIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _currentIndex != 0) {
          setState(() => _currentIndex = 0);
        }
      },
      child: Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: [
            HomeScreen(
              onAnalyzeTap: () =>
                  _openUploadWithAction(UploadInitialAction.none),
              onUploadImageTap: () =>
                  _openUploadWithAction(UploadInitialAction.pickImage),
              onUploadVideoTap: () =>
                  _openUploadWithAction(UploadInitialAction.pickVideo),
              onOpenHistoryTap: () => setState(() => _currentIndex = 3),
            ),
            UploadScreen(
              key: ValueKey('$_uploadSession-${_pendingUploadAction.name}'),
              initialAction: _pendingUploadAction,
              onInitialActionHandled: () {
                _pendingUploadAction = UploadInitialAction.none;
              },
              onFileSelected: _onFileSelected,
            ),
            const AboutScreen(),
            const ProfileScreen(),
          ],
        ),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: palette.border, width: 1),
            ),
          ),
          child: NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (i) => setState(() => _currentIndex = i),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.shield_outlined),
                selectedIcon: Icon(Icons.shield_rounded),
                label: 'Home',
                tooltip: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.add_photo_alternate_outlined),
                selectedIcon: Icon(Icons.add_photo_alternate_rounded),
                label: 'Analyze',
                tooltip: 'Analyze Media',
              ),
              NavigationDestination(
                icon: Icon(Icons.info_outline_rounded),
                selectedIcon: Icon(Icons.info_rounded),
                label: 'About',
                tooltip: 'About DeepGuard',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline_rounded),
                selectedIcon: Icon(Icons.person_rounded),
                label: 'Settings',
                tooltip: 'Profile, History, and Theme Settings',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
