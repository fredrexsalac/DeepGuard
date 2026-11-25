import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import '../theme/app_theme.dart';
import '../services/preprocessing_service.dart';
import '../widgets/deepguard_app_bar.dart';
import '../widgets/glass_card.dart';
import '../widgets/upload_confirmation_sheet.dart';

/// Tracks whether a media file came from the hardware camera or the gallery.
/// Threaded through the processing pipeline for diagnostic logging only.
enum MediaSource {
  camera,
  gallery,
}

/// Optional direct picker trigger when navigating from the Homepage shortcuts.
enum UploadInitialAction {
  none,
  pickImage,
  pickVideo,
}

class UploadScreen extends StatefulWidget {
  final void Function(String filePath, String mediaType, MediaSource source)
      onFileSelected;
  final UploadInitialAction initialAction;
  final VoidCallback? onInitialActionHandled;

  const UploadScreen({
    super.key,
    required this.onFileSelected,
    this.initialAction = UploadInitialAction.none,
    this.onInitialActionHandled,
  });

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final _preprocessing = PreprocessingService();
  String? _filePath;
  String? _mediaType;
  MediaSource _source = MediaSource.gallery;

  VideoPlayerController? _videoCtrl;
  bool _videoReady = false;
  bool _videoLoadFailed = false;
  bool _isSubmitting = false;
  bool _isPicking = false;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    if (widget.initialAction != UploadInitialAction.none) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final action = widget.initialAction;
        widget.onInitialActionHandled?.call();
        if (action == UploadInitialAction.pickImage) {
          _pickImage();
        } else if (action == UploadInitialAction.pickVideo) {
          _pickVideo();
        }
      });
    }
  }

  @override
  void dispose() {
    _videoCtrl?.dispose();
    super.dispose();
  }

  void _notify(String message, {bool isError = false}) {
    if (!mounted) return;
    final palette = DeepGuardPalette.of(context);
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: isError ? palette.aiText : palette.brandNavy,
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline_rounded : Icons.info_outline_rounded,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontSize: 14.5),
              ),
            ),
          ],
        ),
        duration: Duration(seconds: isError ? 4 : 2),
      ),
    );
  }

  Future<void> _pickImage() async {
    if (_isPicking) return;
    setState(() {
      _isPicking = true;
      _validationError = null;
    });
    try {
      final x = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (!mounted) return;
      if (x == null) {
        _notify('No image selected.');
        return;
      }
      _setFile(x.path, source: MediaSource.gallery);
    } on PlatformException catch (e) {
      _setError(_friendlyPickerError(e, 'gallery images'));
    } on MissingPluginException {
      // Safe fallback in unit/widget test environments without native picker
    } catch (_) {
      _setError('Could not open the image picker. Please try again.');
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  Future<void> _pickVideo() async {
    if (_isPicking) return;
    setState(() {
      _isPicking = true;
      _validationError = null;
    });
    try {
      final x = await ImagePicker().pickVideo(source: ImageSource.gallery);
      if (!mounted) return;
      if (x == null) {
        _notify('No video selected.');
        return;
      }
      _setFile(x.path, source: MediaSource.gallery);
    } on PlatformException catch (e) {
      _setError(_friendlyPickerError(e, 'gallery videos'));
    } on MissingPluginException {
      // Safe fallback in unit/widget test environments without native picker
    } catch (_) {
      _setError('Could not open the video picker. Please try again.');
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  Future<void> _captureFromCamera() async {
    if (_isPicking) return;
    setState(() {
      _isPicking = true;
      _validationError = null;
    });
    try {
      // imageQuality intentionally omitted to preserve raw pixels without JPEG
      // re-compression artifacts (matches training preprocessing).
      final x = await ImagePicker().pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
      );
      if (!mounted) return;
      if (x == null) {
        _notify('Photo capture cancelled.');
        return;
      }
      _setFile(x.path, source: MediaSource.camera);
    } on PlatformException catch (e) {
      _setError(_friendlyPickerError(e, 'the camera'));
    } on MissingPluginException {
      // Safe fallback in unit/widget test environments
    } catch (_) {
      _setError('Could not launch the camera. Please check camera permissions.');
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  Future<void> _recordShortVideo() async {
    if (_isPicking) return;
    setState(() {
      _isPicking = true;
      _validationError = null;
    });
    try {
      final x = await ImagePicker().pickVideo(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        maxDuration: const Duration(seconds: 60),
      );
      if (!mounted) return;
      if (x == null) {
        _notify('Video recording cancelled.');
        return;
      }
      _setFile(x.path, source: MediaSource.camera);
    } on PlatformException catch (e) {
      _setError(_friendlyPickerError(e, 'video recording'));
    } on MissingPluginException {
      // Safe fallback in unit/widget test environments
    } catch (_) {
      _setError('Could not record video. Please check camera permissions.');
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  String _friendlyPickerError(PlatformException e, String resource) {
    final code = e.code.toLowerCase();
    if (code.contains('denied') || code.contains('access')) {
      return 'Permission to access $resource was denied. Enable access in your device Settings and try again.';
    }
    if (code.contains('camera_access') || code.contains('no_available_camera')) {
      return 'No camera is available on this device. Please upload an image or video from your gallery instead.';
    }
    return 'Unable to access $resource right now. Please try selecting another file.';
  }

  void _setError(String msg) {
    if (!mounted) return;
    setState(() => _validationError = msg);
    _notify(msg, isError: true);
  }

  void _setFile(String path, {required MediaSource source}) {
    final file = File(path);
    if (!file.existsSync()) {
      _setError('The selected file could not be found on this device.');
      return;
    }
    if (!_preprocessing.isValidMedia(path)) {
      _setError(
        'Unsupported media format. Supported formats: JPG, PNG, BMP, WEBP, MP4, MOV, AVI, MKV, and WEBM.',
      );
      return;
    }
    final length = file.lengthSync();
    if (length == 0) {
      _setError('The selected file is empty or corrupted. Please choose a valid file.');
      return;
    }
    if (!_preprocessing.isValidFileSize(length)) {
      final mb = (length / (1024 * 1024)).toStringAsFixed(1);
      _setError(
        'File size ($mb MB) exceeds the 100 MB limit. Please choose a smaller image or shorter video.',
      );
      return;
    }

    final mediaType = _preprocessing.getMediaType(path);
    setState(() {
      _filePath = path;
      _mediaType = mediaType;
      _source = source;
      _videoReady = false;
      _videoLoadFailed = false;
      _validationError = null;
    });
    if (mediaType == 'video') {
      _initVideoPlayer(path);
    }
  }

  /// Guarded against duplicate taps while confirmation sheet or analysis starts.
  Future<void> _submit() async {
    if (_isSubmitting || _filePath == null || _mediaType == null) return;
    setState(() => _isSubmitting = true);
    _videoCtrl?.pause();

    try {
      final confirmed = await UploadConfirmationSheet.show(
        context: context,
        filePath: _filePath!,
      );
      if (confirmed == true && mounted) {
        widget.onFileSelected(_filePath!, _mediaType!, _source);
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _initVideoPlayer(String path) async {
    await _videoCtrl?.dispose();
    final ctrl = VideoPlayerController.file(File(path));
    _videoCtrl = ctrl;
    bool ok = false;
    try {
      await ctrl.initialize();
      await ctrl.setLooping(true);
      await ctrl.seekTo(Duration.zero);
      ok = ctrl.value.isInitialized;
    } catch (_) {
      ok = false;
    }
    if (mounted) {
      setState(() {
        _videoReady = ok;
        _videoLoadFailed = !ok;
      });
    }
  }

  void _clear() {
    _videoCtrl?.dispose();
    _videoCtrl = null;
    setState(() {
      _filePath = null;
      _mediaType = null;
      _source = MediaSource.gallery;
      _videoReady = false;
      _videoLoadFailed = false;
      _validationError = null;
    });
    _notify('Selected media removed.');
  }

  @override
  Widget build(BuildContext context) {
    final palette = DeepGuardPalette.of(context);

    return Scaffold(
      backgroundColor: palette.backgroundSecondary,
      appBar: const DeepGuardAppBar(title: 'Analyze Media'),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_validationError != null) ...[
                _ValidationAlertBanner(
                  message: _validationError!,
                  onDismiss: () => setState(() => _validationError = null),
                ),
                const SizedBox(height: 16),
              ],
              if (_filePath != null)
                _buildPreview(palette)
              else
                _buildSelectZone(palette),
            ],
          ),
        ),
      ),
    );
  }

  // ── Media selection workspace ──────────────────────────────────────────────
  Widget _buildSelectZone(DeepGuardPalette palette) {
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            'Choose Image or Video',
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Select a photo or video from your device, or capture a new sample using your camera.',
          style: TextStyle(
            color: palette.textSecondary,
            fontSize: 15.5,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 20),

        // Primary Gallery Upload Actions
        Semantics(
          header: true,
          child: Text(
            'Upload from Device',
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final useSingleColumn =
                constraints.maxWidth < 340 || textScale > 1.3;
            final imageTile = _MediaActionCard(
              title: 'Upload Image',
              subtitle: 'JPG, PNG, BMP, WEBP',
              icon: Icons.photo_library_outlined,
              accentColor: palette.primaryButton,
              iconColor: palette.primaryText,
              enabled: !_isPicking,
              onTap: _pickImage,
              semanticLabel:
                  'Upload Image from device gallery. Supports JPG, PNG, BMP, and WEBP up to 100 megabytes.',
            );
            final videoTile = _MediaActionCard(
              title: 'Upload Video',
              subtitle: 'MP4, MOV, AVI, MKV',
              icon: Icons.video_library_outlined,
              accentColor: palette.accent,
              iconColor: palette.accentText,
              enabled: !_isPicking,
              onTap: _pickVideo,
              semanticLabel:
                  'Upload Video from device gallery. Supports MP4, MOV, AVI, MKV, and WEBM up to 100 megabytes.',
            );
            if (useSingleColumn) {
              return Column(
                children: [
                  imageTile,
                  const SizedBox(height: 10),
                  videoTile,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: imageTile),
                const SizedBox(width: 12),
                Expanded(child: videoTile),
              ],
            );
          },
        ),

        const SizedBox(height: 20),

        // Camera Capture Actions
        Semantics(
          header: true,
          child: Text(
            'Capture with Camera',
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final useSingleColumn =
                constraints.maxWidth < 340 || textScale > 1.3;
            final photoTile = _MediaActionCard(
              title: 'Take Photo',
              subtitle: 'Capture uncompressed photo',
              icon: Icons.camera_alt_outlined,
              accentColor: palette.primaryButton,
              iconColor: palette.primaryText,
              enabled: !_isPicking,
              onTap: _captureFromCamera,
              semanticLabel:
                  'Take Photo with device camera for authenticity analysis.',
            );
            final recordTile = _MediaActionCard(
              title: 'Record Video',
              subtitle: 'Up to 60 seconds clip',
              icon: Icons.videocam_outlined,
              accentColor: palette.accent,
              iconColor: palette.accentText,
              enabled: !_isPicking,
              onTap: _recordShortVideo,
              semanticLabel:
                  'Record Video up to 60 seconds with device camera for authenticity analysis.',
            );
            if (useSingleColumn) {
              return Column(
                children: [
                  photoTile,
                  const SizedBox(height: 10),
                  recordTile,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: photoTile),
                const SizedBox(width: 12),
                Expanded(child: recordTile),
              ],
            );
          },
        ),

        const SizedBox(height: 22),
        _buildRequirementsCard(palette),
      ],
    );
  }

  Widget _buildRequirementsCard(DeepGuardPalette palette) {
    final imgExts = PreprocessingService.allowedImageExtensions
        .map((e) => e.toUpperCase())
        .join(', ');
    final vidExts = PreprocessingService.allowedVideoExtensions
        .map((e) => e.toUpperCase())
        .join(', ');

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
                    Icons.checklist_rtl_rounded,
                    size: 19,
                    color: palette.primaryText,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Upload Requirements',
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _RequirementRow(
            icon: Icons.image_outlined,
            label: 'Image formats',
            detail: imgExts,
            palette: palette,
          ),
          const SizedBox(height: 10),
          _RequirementRow(
            icon: Icons.movie_outlined,
            label: 'Video formats',
            detail: vidExts,
            palette: palette,
          ),
          const SizedBox(height: 10),
          _RequirementRow(
            icon: Icons.sd_storage_outlined,
            label: 'Size & duration',
            detail: 'Up to 100 MB · Camera video up to 60 seconds',
            palette: palette,
          ),
          const SizedBox(height: 10),
          _RequirementRow(
            icon: Icons.face_outlined,
            label: 'Best results',
            detail: 'Clear, well-lit subject face without heavy cropping',
            palette: palette,
          ),
        ],
      ),
    );
  }

  // ── Selected media preview ─────────────────────────────────────────────────
  Widget _buildPreview(DeepGuardPalette palette) {
    final isImg = _mediaType == 'image';
    final file = File(_filePath!);
    final normalized = _filePath!.replaceAll('\\', '/');
    final name = normalized.split('/').last;
    final sizeMb = file.existsSync()
        ? (file.lengthSync() / (1024 * 1024)).toStringAsFixed(1)
        : '0.0';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: palette.successContainer,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: palette.success.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check_circle_outline_rounded,
                    size: 16,
                    color: palette.successText,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isImg ? 'Image Selected' : 'Video Selected',
                    style: TextStyle(
                      color: palette.successText,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _isSubmitting ? null : _clear,
              icon: Icon(
                Icons.delete_outline_rounded,
                size: 18,
                color: palette.errorText,
              ),
              label: Text(
                'Remove',
                style: TextStyle(color: palette.errorText),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Media preview viewport
        Container(
          height: 240,
          decoration: BoxDecoration(
            color: palette.brandNavy,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: palette.border, width: 1.2),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: isImg
                ? Semantics(
                    image: true,
                    label: 'Selected image preview: $name',
                    child: Image.file(
                      file,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => _PreviewPlaceholder(
                        icon: Icons.broken_image_outlined,
                        label: 'Image preview unavailable',
                        palette: palette,
                      ),
                    ),
                  )
                : (_videoReady && _videoCtrl != null)
                    ? _VideoPreview(controller: _videoCtrl!, fileName: name)
                    : _PreviewPlaceholder(
                        icon: _videoLoadFailed
                            ? Icons.videocam_off_outlined
                            : Icons.videocam_outlined,
                        label: _videoLoadFailed
                            ? 'Video preview unavailable — analysis is still supported'
                            : 'Loading video preview…',
                        loading: !_videoLoadFailed,
                        palette: palette,
                      ),
          ),
        ),
        const SizedBox(height: 14),

        // File metadata summary card
        GlassCard(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: palette.processingContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isImg ? Icons.image_outlined : Icons.videocam_outlined,
                  color: palette.primaryText,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
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
                      '${isImg ? 'Image' : 'Video'} · $sizeMb MB · '
                      '${_source == MediaSource.camera ? 'Camera Capture' : 'Gallery Upload'}',
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 13.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Action Controls (responsive to text scaling)
        LayoutBuilder(
          builder: (context, constraints) {
            final textScale = MediaQuery.textScalerOf(context).scale(1.0);
            final stackVertically =
                constraints.maxWidth < 340 || textScale > 1.3;

            final cancelBtn = OutlinedButton.icon(
              onPressed: _isSubmitting ? null : _clear,
              icon: const Icon(Icons.close_rounded, size: 18),
              label: const Text('Choose Another'),
            );

            final startBtn = FilledButton.icon(
              onPressed: _isSubmitting ? null : _submit,
              icon: _isSubmitting
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: palette.onPrimaryButton,
                      ),
                    )
                  : const Icon(Icons.fact_check_outlined, size: 20),
              label: Text(_isSubmitting ? 'Verifying…' : 'Start Analysis'),
            );

            if (stackVertically) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  startBtn,
                  const SizedBox(height: 10),
                  cancelBtn,
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: cancelBtn),
                const SizedBox(width: 12),
                Expanded(flex: 2, child: startBtn),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ValidationAlertBanner extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;

  const _ValidationAlertBanner({
    required this.message,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final palette = DeepGuardPalette.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        decoration: BoxDecoration(
          color: palette.errorContainer,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: palette.error.withValues(alpha: 0.65)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                Icons.error_outline_rounded,
                color: palette.errorText,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
            ),
            IconButton(
              onPressed: onDismiss,
              tooltip: 'Dismiss message',
              icon: Icon(
                Icons.close_rounded,
                size: 18,
                color: palette.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MediaActionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accentColor;
  final Color iconColor;
  final bool enabled;
  final VoidCallback onTap;
  final String semanticLabel;

  const _MediaActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    required this.iconColor,
    required this.enabled,
    required this.onTap,
    required this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final palette = DeepGuardPalette.of(context);
    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel,
      child: Material(
        color: palette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: palette.controlBorder, width: 1.15),
        ),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(14),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 104),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: accentColor.withValues(
                          alpha: palette.isDark ? 0.18 : 0.10,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, color: iconColor, size: 24),
                    ),
                    const SizedBox(height: 12),
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
                      subtitle,
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 13.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RequirementRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String detail;
  final DeepGuardPalette palette;

  const _RequirementRow({
    required this.icon,
    required this.label,
    required this.detail,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
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
          child: Text.rich(
            TextSpan(
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 14,
                height: 1.45,
              ),
              children: [
                TextSpan(
                  text: '$label: ',
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextSpan(text: detail),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PreviewPlaceholder extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool loading;
  final DeepGuardPalette palette;

  const _PreviewPlaceholder({
    required this.icon,
    required this.label,
    this.loading = false,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: palette.brandNavy,
      padding: const EdgeInsets.all(20),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
            else
              Icon(icon, color: Colors.white70, size: 40),
            const SizedBox(height: 12),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoPreview extends StatefulWidget {
  final VideoPlayerController controller;
  final String fileName;

  const _VideoPreview({
    required this.controller,
    required this.fileName,
  });

  @override
  State<_VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<_VideoPreview> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTick);
  }

  @override
  void didUpdateWidget(covariant _VideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTick);
      widget.controller.addListener(_onTick);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTick);
    super.dispose();
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  void _togglePlay() {
    final ctrl = widget.controller;
    if (!ctrl.value.isInitialized) return;
    if (ctrl.value.isPlaying) {
      ctrl.pause();
    } else {
      ctrl.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    if (!ctrl.value.isInitialized) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: Icon(Icons.videocam_off, color: Colors.white70, size: 40),
        ),
      );
    }

    final isPlaying = ctrl.value.isPlaying;
    String fmt(Duration d) =>
        '${d.inMinutes.toString().padLeft(2, '0')}:'
        '${(d.inSeconds % 60).toString().padLeft(2, '0')}';

    return Semantics(
      button: true,
      label: isPlaying
          ? 'Pause video preview for ${widget.fileName}'
          : 'Play video preview for ${widget.fileName}',
      child: GestureDetector(
        onTap: _togglePlay,
        behavior: HitTestBehavior.opaque,
        child: ColoredBox(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: AspectRatio(
                  aspectRatio: ctrl.value.aspectRatio > 0
                      ? ctrl.value.aspectRatio
                      : 16 / 9,
                  child: VideoPlayer(ctrl),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: ExcludeSemantics(
                  child: VideoProgressIndicator(
                    ctrl,
                    allowScrubbing: true,
                    colors: const VideoProgressColors(
                      playedColor: Color(0xFF35C9E2),
                      bufferedColor: Colors.white38,
                      backgroundColor: Colors.white24,
                    ),
                    padding: const EdgeInsets.symmetric(
                      vertical: 6,
                      horizontal: 10,
                    ),
                  ),
                ),
              ),
              Center(
                child: ExcludeSemantics(
                  child: AnimatedOpacity(
                    opacity: isPlaying ? 0.0 : 1.0,
                    duration: const Duration(milliseconds: 180),
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withValues(alpha: 0.68),
                        border: Border.all(color: Colors.white70, width: 1.5),
                      ),
                      child: Icon(
                        isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 10,
                right: 10,
                child: ExcludeSemantics(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.78),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${fmt(ctrl.value.position)} / ${fmt(ctrl.value.duration)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
