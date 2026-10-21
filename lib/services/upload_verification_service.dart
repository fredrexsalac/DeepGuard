import 'dart:io';
import 'package:flutter/material.dart';
import '../services/preprocessing_service.dart';
import '../theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Validation result types
// ─────────────────────────────────────────────────────────────────────────────

enum ValidationStatus { pass, warn, fail }

class ValidationCheck {
  final String label;
  final String detail;
  final ValidationStatus status;

  const ValidationCheck({
    required this.label,
    required this.detail,
    required this.status,
  });

  Color get color {
    switch (status) {
      case ValidationStatus.pass: return DeepGuardColors.authentic;
      case ValidationStatus.warn: return DeepGuardColors.warning;
      case ValidationStatus.fail: return DeepGuardColors.fake;
    }
  }

  IconData get icon {
    switch (status) {
      case ValidationStatus.pass: return Icons.check_circle_outline;
      case ValidationStatus.warn: return Icons.warning_amber_outlined;
      case ValidationStatus.fail: return Icons.cancel_outlined;
    }
  }
}

class ValidationResult {
  final bool canProceed;       // false = at least one FAIL check
  final String? fatalMessage;  // non-null when canProceed == false
  final List<ValidationCheck> checks;
  final String mediaType;      // 'image' or 'video'
  final String fileName;
  final double fileSizeMb;

  const ValidationResult({
    required this.canProceed,
    this.fatalMessage,
    required this.checks,
    required this.mediaType,
    required this.fileName,
    required this.fileSizeMb,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Service
// ─────────────────────────────────────────────────────────────────────────────

/// Runs all pre-submission validation checks on a media file.
///
/// Validation layers (in order):
///   1. File existence
///   2. Extension whitelist (image/video)
///   3. MIME-like content check (file headers)
///   4. File size (max 100 MB)
///   5. Quality advisory (very small files may produce unreliable results)
class UploadVerificationService {
  static final UploadVerificationService _i =
      UploadVerificationService._();
  factory UploadVerificationService() => _i;
  UploadVerificationService._();

  static const int _smallImageBytes = 20 * 1024;   // < 20 KB = quality warn
  static const int _smallVideoBytes = 500 * 1024;  // < 500 KB = quality warn

  final _pre = PreprocessingService();

  /// Validates [filePath] and returns a [ValidationResult].
  /// This method never throws — all errors are encoded in the result.
  Future<ValidationResult> validate(String filePath) async {
    final checks = <ValidationCheck>[];
    final file = File(filePath);
    final fileName = filePath.split(Platform.pathSeparator).last;

    // ── Check 1: File exists ──────────────────────────────────────────────
    if (!file.existsSync()) {
      checks.add(const ValidationCheck(
        label: 'File Exists',
        detail: 'The selected file could not be found on device.',
        status: ValidationStatus.fail,
      ));
      return ValidationResult(
        canProceed: false,
        fatalMessage: 'File not found on this device.',
        checks: checks,
        mediaType: 'unknown',
        fileName: fileName,
        fileSizeMb: 0,
      );
    }

    final bytes = file.lengthSync();
    final sizeMb = bytes / (1024 * 1024);

    checks.add(ValidationCheck(
      label: 'File Exists',
      detail: fileName,
      status: ValidationStatus.pass,
    ));

    // ── Check 2: Format / extension ───────────────────────────────────────
    final ext = filePath.split('.').last.toLowerCase();
    final isValidFormat = _pre.isValidMedia(filePath);
    final mediaType = _pre.getMediaType(filePath);

    if (!isValidFormat || mediaType == 'unknown') {
      checks.add(ValidationCheck(
        label: 'File Format',
        detail: '".$ext" is not supported. Use JPG, PNG, MP4, MOV or AVI.',
        status: ValidationStatus.fail,
      ));
      return ValidationResult(
        canProceed: false,
        fatalMessage: 'Unsupported file format: .$ext',
        checks: checks,
        mediaType: mediaType,
        fileName: fileName,
        fileSizeMb: sizeMb,
      );
    }

    checks.add(ValidationCheck(
      label: 'File Format',
      detail: '.${ext.toUpperCase()} — ${mediaType == 'image' ? 'Image' : 'Video'}',
      status: ValidationStatus.pass,
    ));

    // ── Check 3: File size ────────────────────────────────────────────────
    if (!_pre.isValidFileSize(bytes)) {
      checks.add(ValidationCheck(
        label: 'File Size',
        detail:
            '${sizeMb.toStringAsFixed(1)} MB exceeds the 100 MB limit.',
        status: ValidationStatus.fail,
      ));
      return ValidationResult(
        canProceed: false,
        fatalMessage: 'File is too large (${sizeMb.toStringAsFixed(1)} MB). Max: 100 MB.',
        checks: checks,
        mediaType: mediaType,
        fileName: fileName,
        fileSizeMb: sizeMb,
      );
    }

    checks.add(ValidationCheck(
      label: 'File Size',
      detail: '${sizeMb.toStringAsFixed(1)} MB  (max 100 MB)',
      status: ValidationStatus.pass,
    ));

    // ── Check 4: Quality advisory ─────────────────────────────────────────
    final isSmall = mediaType == 'image'
        ? bytes < _smallImageBytes
        : bytes < _smallVideoBytes;

    if (isSmall) {
      checks.add(ValidationCheck(
        label: 'Quality Advisory',
        detail:
            'File is very small (${sizeMb.toStringAsFixed(2)} MB). '
            'Results may be less reliable.',
        status: ValidationStatus.warn,
      ));
    } else {
      checks.add(ValidationCheck(
        label: 'Quality Advisory',
        detail: 'File size is adequate for analysis.',
        status: ValidationStatus.pass,
      ));
    }

    // ── Check 5: Content type (magic bytes) ───────────────────────────────
    final magicOk = await _checkMagicBytes(file, mediaType);
    if (!magicOk) {
      checks.add(ValidationCheck(
        label: 'Content Verification',
        detail:
            'File content does not match its extension. '
            'The file may be corrupt or mislabelled.',
        status: ValidationStatus.warn,
      ));
    } else {
      checks.add(ValidationCheck(
        label: 'Content Verification',
        detail: 'File content matches expected format.',
        status: ValidationStatus.pass,
      ));
    }

    return ValidationResult(
      canProceed: true,
      checks: checks,
      mediaType: mediaType,
      fileName: fileName,
      fileSizeMb: sizeMb,
    );
  }

  /// Reads the first few bytes of the file and checks magic numbers.
  Future<bool> _checkMagicBytes(File file, String mediaType) async {
    try {
      final bytes = await file.openRead(0, 16).first;
      if (mediaType == 'image') {
        // JPEG: FF D8 FF
        if (bytes.length >= 3 &&
            bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
          return true;
        }
        // PNG: 89 50 4E 47
        if (bytes.length >= 4 &&
            bytes[0] == 0x89 && bytes[1] == 0x50 &&
            bytes[2] == 0x4E && bytes[3] == 0x47) {
          return true;
        }
        // BMP: 42 4D
        if (bytes.length >= 2 && bytes[0] == 0x42 && bytes[1] == 0x4D) {
          return true;
        }
        // WebP: 52 49 46 46 ... 57 45 42 50
        if (bytes.length >= 12 &&
            bytes[0] == 0x52 && bytes[1] == 0x49 &&
            bytes[8] == 0x57 && bytes[9] == 0x45) {
          return true;
        }
        return false;
      } else {
        // MP4 / MOV: ftyp at offset 4 (66 74 79 70)
        if (bytes.length >= 8 &&
            bytes[4] == 0x66 && bytes[5] == 0x74 &&
            bytes[6] == 0x79 && bytes[7] == 0x70) {
          return true;
        }
        // AVI: RIFF at offset 0
        if (bytes.length >= 4 &&
            bytes[0] == 0x52 && bytes[1] == 0x49 &&
            bytes[2] == 0x46 && bytes[3] == 0x46) {
          return true;
        }
        // MKV / WebM: EBML header 1A 45 DF A3
        if (bytes.length >= 4 &&
            bytes[0] == 0x1A && bytes[1] == 0x45 &&
            bytes[2] == 0xDF && bytes[3] == 0xA3) {
          return true;
        }
        // If we can't detect but extension is valid, give benefit of doubt
        return true;
      }
    } catch (_) {
      return true; // can't read = treat as OK, don't block
    }
  }
}
