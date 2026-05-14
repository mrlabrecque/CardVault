import 'dart:async';
import 'dart:convert';

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/scan_immersive.dart';
import '../../core/services/cards_service.dart';
import '../../core/services/comps_service.dart';
import '../../core/utils/adaptive_ui.dart';
import '../../core/utils/usd_field.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/chrome_metrics.dart';
import '../../core/theme/fonts.dart';
import '../../core/widgets/app_bar_shell_trailing_actions.dart';
import '../../core/widgets/card_fan_loader.dart';
import '../../core/widgets/glass_nav_bar.dart';
import '../collection/master_card_detail_screen.dart';
import '../wishlist/card_sheet.dart';
import '../wishlist/wishlist_screen.dart' show wishlistProvider;
import 'widgets/scan_camera_page.dart';

// Catalog detection result model
class ImageScanMatchResult {
  final String confidence; // High, Medium, Low
  final ScannedCatalogCard card;
  final GradingInfo? grading;
  /// Normalized 0–1 when the API returns a numeric field; otherwise null.
  final double? matchScore;

  ImageScanMatchResult({
    required this.confidence,
    required this.card,
    this.grading,
    this.matchScore,
  });

  static double? _parseMatchScore(Map<String, dynamic> json) {
    const keys = [
      'matchScore',
      'score',
      'confidenceScore',
      'similarity',
      'probability',
    ];
    for (final k in keys) {
      final v = json[k];
      if (v is num) {
        final d = v.toDouble();
        if (d >= 0 && d <= 1) return d;
        if (d > 1 && d <= 100) return (d / 100).clamp(0.0, 1.0);
      }
    }
    return null;
  }

  factory ImageScanMatchResult.fromJson(Map<String, dynamic> json) {
    final cardRaw = json['card'];
    final cardMap = cardRaw is Map<String, dynamic>
        ? Map<String, dynamic>.from(cardRaw)
        : Map<String, dynamic>.from(cardRaw as Map? ?? {});
    // Some responses put player on the detection object instead of inside `card`.
    final hasName = cardMap['name'] != null && cardMap['name'].toString().trim().isNotEmpty;
    if (!hasName) {
      for (final k in ['name', 'player', 'playerName', 'athlete', 'subject']) {
        final v = json[k];
        if (v != null && v.toString().trim().isNotEmpty) {
          cardMap['name'] = v;
          break;
        }
      }
    }
    ScannedCatalogCard.mergeEnvelopeIntoCardMap(cardMap, json);
    return ImageScanMatchResult(
      confidence: json['confidence']?.toString() ?? 'Low',
      card: ScannedCatalogCard.fromJson(cardMap),
      grading: json['grading'] != null
          ? GradingInfo.fromJson(
              Map<String, dynamic>.from(json['grading'] as Map),
            )
          : null,
      matchScore: _parseMatchScore(json),
    );
  }

  /// Human-readable confidence for UI (prefers numeric % when available).
  String get confidenceLabel {
    final s = matchScore;
    if (s != null) return '${(s * 100).round()}%';
    return confidence;
  }

  ImageScanMatchResult copyWith({ScannedCatalogCard? card}) {
    return ImageScanMatchResult(
      confidence: confidence,
      card: card ?? this.card,
      grading: grading,
      matchScore: matchScore,
    );
  }
}

class ScannedCatalogCard {
  final String? id; // exact match only
  final String? name; // player name (exact match only)
  final String? number; // card number (exact match only)
  final String? year;
  final String? manufacturer;
  final String? releaseName;
  final String? setName;
  final String? releaseId;
  final String? setId;
  final String? segmentId;
  final ParallelInfo? parallel;
  final String? imageUrl;

  ScannedCatalogCard({
    this.id,
    this.name,
    this.number,
    this.year,
    this.manufacturer,
    this.releaseName,
    this.setName,
    this.releaseId,
    this.setId,
    this.segmentId,
    this.parallel,
    this.imageUrl,
  });

  ScannedCatalogCard copyWith({String? imageUrl}) {
    return ScannedCatalogCard(
      id: id,
      name: name,
      number: number,
      year: year,
      manufacturer: manufacturer,
      releaseName: releaseName,
      setName: setName,
      releaseId: releaseId,
      setId: setId,
      segmentId: segmentId,
      parallel: parallel,
      imageUrl: imageUrl ?? this.imageUrl,
    );
  }

  factory ScannedCatalogCard.fromJson(Map<String, dynamic> json) {
    return ScannedCatalogCard(
      id: _pickString(json, const ['id', 'cardId', 'card_id', 'masterCardId', 'master_card_id']),
      name: _pickString(json, const [
        'name',
        'player',
        'playerName',
        'player_name',
        'athlete',
        'subject',
        'playerLastName',
      ]),
      number: _pickString(json, const [
        'number',
        'cardNumber',
        'card_number',
        'cardNo',
        'card_no',
      ]),
      year: json['year']?.toString(),
      manufacturer: json['manufacturer']?.toString(),
      releaseName: _pickString(json, const [
        'releaseName',
        'release_name',
        'releaseTitle',
        'release_title',
      ]),
      setName: _pickString(json, const [
        'setName',
        'set_name',
        'checklistName',
        'checklist_name',
      ]),
      releaseId: _pickString(json, const [
        'releaseId',
        'release_id',
        'cardsightReleaseId',
        'releaseUUID',
      ]),
      setId: _pickString(json, const [
        'setId',
        'set_id',
        'checklistId',
        'checklist_id',
        'cardsightSetId',
      ]),
      segmentId: _pickString(json, const ['segmentId', 'segment_id', 'segment']),
      parallel: json['parallel'] != null
          ? ParallelInfo.fromJson(
              Map<String, dynamic>.from(json['parallel'] as Map),
            )
          : null,
      imageUrl: _pickString(json, const [
        'imageUrl',
        'image_url',
        'thumbnailUrl',
        'thumbnail',
        'image',
      ]),
    );
  }

  /// Copies release/set (and related) fields from the detection envelope or nested
  /// `release` / `set` objects into [card] when those keys are missing on `card`.
  static void mergeEnvelopeIntoCardMap(
    Map<String, dynamic> card,
    Map<String, dynamic> detection,
  ) {
    void putIfEmpty(String key, String? value) {
      if (value == null || value.isEmpty) return;
      final cur = card[key];
      if (cur != null && cur.toString().trim().isNotEmpty) return;
      card[key] = value;
    }

    void pickFrom(Map<String, dynamic> src, String dest, List<String> keys) {
      putIfEmpty(dest, _pickString(src, keys));
    }

    pickFrom(detection, 'releaseId', const [
      'releaseId',
      'release_id',
      'cardsightReleaseId',
      'releaseUUID',
    ]);
    pickFrom(detection, 'setId', const [
      'setId',
      'set_id',
      'checklistId',
      'checklist_id',
      'cardsightSetId',
    ]);
    pickFrom(detection, 'releaseName', const [
      'releaseName',
      'release_name',
      'releaseTitle',
    ]);
    pickFrom(detection, 'setName', const [
      'setName',
      'set_name',
      'checklistName',
    ]);
    pickFrom(detection, 'segmentId', const ['segmentId', 'segment_id', 'segment']);

    final rel = detection['release'];
    if (rel is Map) {
      final m = Map<String, dynamic>.from(rel);
      pickFrom(m, 'releaseId', const ['id', 'releaseId', 'uuid']);
      pickFrom(m, 'releaseName', const ['name', 'title', 'displayName']);
    }
    final st = detection['set'];
    if (st is Map) {
      final m = Map<String, dynamic>.from(st);
      pickFrom(m, 'setId', const ['id', 'setId', 'checklistId', 'uuid']);
      pickFrom(m, 'setName', const ['name', 'title', 'displayName']);
    }
  }

  /// Identify APIs use inconsistent keys; use the first non-empty string.
  static String? _pickString(Map<String, dynamic> json, List<String> keys) {
    for (final k in keys) {
      final v = json[k];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return null;
  }
}

class ParallelInfo {
  final String id;
  final String name;
  final int? numberedTo;

  ParallelInfo({required this.id, required this.name, this.numberedTo});

  factory ParallelInfo.fromJson(Map<String, dynamic> json) {
    return ParallelInfo(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Base',
      numberedTo: json['numberedTo'],
    );
  }
}

class GradingInfo {
  final String confidence;
  final GradingCompany company;
  /// e.g. PSA numeric label from `grading.grade.value`
  final String? gradeValue;
  /// e.g. "GEM MINT" from `grading.grade.condition`
  final String? gradeCondition;

  GradingInfo({
    required this.confidence,
    required this.company,
    this.gradeValue,
    this.gradeCondition,
  });

  /// One line for UI: `PSA · 10 · GEM MINT`
  String get slabSummary {
    final parts = <String>[company.name];
    final v = gradeValue?.trim();
    final c = gradeCondition?.trim();
    if (v != null && v.isNotEmpty) parts.add(v);
    if (c != null && c.isNotEmpty) parts.add(c);
    return parts.join(' · ');
  }

  factory GradingInfo.fromJson(Map<String, dynamic> json) {
    String? gradeValue;
    String? gradeCondition;
    final gradeRaw = json['grade'];
    if (gradeRaw is Map) {
      final g = Map<String, dynamic>.from(gradeRaw);
      final v = g['value']?.toString().trim();
      final cond = g['condition']?.toString().trim();
      if (v != null && v.isNotEmpty) gradeValue = v;
      if (cond != null && cond.isNotEmpty) gradeCondition = cond;
    }
    return GradingInfo(
      confidence: json['confidence']?.toString() ?? 'Low',
      company: GradingCompany.fromJson(
        Map<String, dynamic>.from(json['company'] as Map? ?? {}),
      ),
      gradeValue: gradeValue,
      gradeCondition: gradeCondition,
    );
  }
}

class GradingCompany {
  final String? id;
  final String name;

  GradingCompany({this.id, required this.name});

  factory GradingCompany.fromJson(Map<String, dynamic> json) {
    return GradingCompany(id: json['id'], name: json['name'] ?? 'Unknown');
  }
}

class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

enum _ScanState { sportPicker, camera, processing, result, error }

class _ScanScreenState extends ConsumerState<ScanScreen> {
  final ImagePicker _imagePicker = ImagePicker();
  final _supabase = Supabase.instance.client;
  static const _scanFunctionName = 'identify-card';
  static const _invokeTimeout = Duration(seconds: 75);

  _ScanState _state = _ScanState.sportPicker;
  String _selectedSport = '';
  List<ImageScanMatchResult> _detections = const [];
  /// Pretty-printed JSON for each row in [_detections] (same order after sort).
  List<String> _detectionRawJson = const [];
  String? _errorMessage;
  bool _openingCatalogDetail = false;

  void _update(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
    final hide = _state == _ScanState.camera || _state == _ScanState.processing;
    if (scanImmersiveMode.value != hide) {
      scanImmersiveMode.value = hide;
    }
  }

  double _bodyBottomInsetOverTabBar(BuildContext context) {
    return MediaQuery.paddingOf(context).bottom + ChromeMetrics.shellTabBarReserveHeight;
  }

  @override
  void dispose() {
    scanImmersiveMode.value = false;
    super.dispose();
  }

  Uint8List? _encodeScanJpeg(
    Uint8List raw, {
    int maxSide = 1200,
    int quality = 82,
  }) {
    final decoded = img.decodeImage(raw);
    if (decoded == null) return null;
    var im = decoded;
    if (im.width > maxSide || im.height > maxSide) {
      im = img.copyResize(
        im,
        width: im.width >= im.height ? maxSide : null,
        height: im.height > im.width ? maxSide : null,
        interpolation: img.Interpolation.linear,
      );
    }
    return Uint8List.fromList(img.encodeJpg(im, quality: quality));
  }

  Future<FunctionResponse> _invokeIdentify(String base64) {
    return _supabase.functions
        .invoke(
          _scanFunctionName,
          body: {'imageBase64': base64, 'sport': _selectedSport},
        )
        .timeout(_invokeTimeout);
  }

  static const _sports = [
    ('Baseball', 'baseball', '⚾', Color(0xFFB45309)),
    ('Basketball', 'basketball', '🏀', Color(0xFFF97316)),
    ('Football', 'football', '🏈', Color(0xFF8B5CF6)),
    ('Hockey', 'hockey', '🏒', Color(0xFF2563EB)),
  ];

  Future<void> _selectSport(String sport) async {
    _update(() => _selectedSport = sport);
    await Future.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;
    if (kIsWeb) {
      await _captureWithImagePicker();
    } else {
      _update(() => _state = _ScanState.camera);
    }
  }

  void _exitCameraToSportPicker() {
    if (!mounted) return;
    _update(() {
      _state = _ScanState.sportPicker;
      _selectedSport = '';
    });
  }

  void _onCameraCaptured(Uint8List raw) {
    if (!mounted) return;
    _update(() => _state = _ScanState.processing);
    _runIdentifyFromBytes(raw);
  }

  /// Web (no custom camera): system picker → identify.
  Future<void> _captureWithImagePicker() async {
    final file = await _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 70,
      maxWidth: 1600,
      maxHeight: 1600,
    );

    if (file == null) {
      if (mounted) {
        _update(() {
          _state = _ScanState.sportPicker;
        });
      }
      return;
    }

    if (mounted) _update(() => _state = _ScanState.processing);

    try {
      final raw = await file.readAsBytes();
      await _runIdentifyFromBytes(Uint8List.fromList(raw));
    } on FunctionException catch (e) {
      _setIdentifyFunctionError(e);
    } on TimeoutException {
      if (mounted) {
        _update(() {
          _state = _ScanState.error;
          _errorMessage =
              'Scan timed out. Try again on Wi‑Fi, or retake with the card closer and less glare.';
        });
      }
    } catch (e) {
      if (mounted) {
        _update(() {
          _state = _ScanState.error;
          _errorMessage = 'Error: ${e.toString()}';
        });
      }
    }
  }

  void _setIdentifyFunctionError(FunctionException e) {
    final message = e.status == 404
        ? 'Scan service is unavailable. Edge Function `$_scanFunctionName` was not found for this Supabase project. Deploy it with `supabase functions deploy $_scanFunctionName` and try again.'
        : e.status == 504
        ? 'Identification took too long (upstream timeout). Try Wi‑Fi or a simpler shot of the card front.'
        : 'Scan failed (${e.status}). Please try again.';
    if (mounted) {
      _update(() {
        _state = _ScanState.error;
        _errorMessage = message;
      });
    }
  }

  int _confidenceRank(String c) {
    switch (c.toLowerCase()) {
      case 'high':
        return 3;
      case 'medium':
        return 2;
      default:
        return 1;
    }
  }

  int _detectionCompare(ImageScanMatchResult a, ImageScanMatchResult b) {
    final sa = a.matchScore;
    final sb = b.matchScore;
    if (sa != null || sb != null) {
      if (sa == null) return 1;
      if (sb == null) return -1;
      final cmp = sb.compareTo(sa);
      if (cmp != 0) return cmp;
    }
    return _confidenceRank(b.confidence).compareTo(
      _confidenceRank(a.confidence),
    );
  }

  Future<void> _runIdentifyFromBytes(Uint8List raw) async {
    try {
      final jpeg =
          _encodeScanJpeg(raw) ?? Uint8List.fromList(raw);
      var base64String = base64Encode(jpeg);

      FunctionResponse res;
      try {
        res = await _invokeIdentify(base64String);
      } on TimeoutException {
        final smaller =
            _encodeScanJpeg(jpeg, maxSide: 900, quality: 78) ??
            _encodeScanJpeg(raw, maxSide: 900, quality: 78) ??
            jpeg;
        base64String = base64Encode(smaller);
        res = await _invokeIdentify(base64String);
      }

      if (res.status != 200) {
        final body = res.data;
        if (body is Map && body['error'] != null) {
          throw Exception(body['error']);
        }
        throw Exception('Identification failed (${res.status})');
      }

      final data = res.data as Map<String, dynamic>;

      if (data['error'] != null) {
        throw Exception(data['error']);
      }

      final success = data['success'];
      if (success == false) {
        final msg = data['error'] ?? data['message'] ?? data['detail'] ?? 'Identification was not successful.';
        throw Exception(msg is String ? msg : msg.toString());
      }

      final detectionsRaw = data['detections'] as List<dynamic>? ?? [];

      if (detectionsRaw.isEmpty) {
        if (mounted) {
          _update(() {
            _state = _ScanState.error;
            _errorMessage =
                'No cards detected. Try again with a clearer photo.';
          });
        }
        return;
      }

      final encoder = JsonEncoder.withIndent('  ');
      final pairs = <({ImageScanMatchResult m, String raw})>[];
      for (final e in detectionsRaw) {
        final map = Map<String, dynamic>.from(e as Map);
        pairs.add((
          m: ImageScanMatchResult.fromJson(map),
          raw: encoder.convert(map),
        ));
      }
      pairs.sort((a, b) => _detectionCompare(a.m, b.m));

      var matches = pairs.map((p) => p.m).toList();
      final rawJson = pairs.map((p) => p.raw).toList();
      if (matches.isNotEmpty) {
        final topId = matches.first.card.id;
        if (topId != null && topId.isNotEmpty) {
          final url = await ref.read(compsServiceProvider).fetchCardImage(topId);
          if (!mounted) return;
          if (url != null && url.trim().isNotEmpty) {
            final top = matches.first;
            matches = [
              top.copyWith(card: top.card.copyWith(imageUrl: url.trim())),
              ...matches.skip(1),
            ];
          }
        }
      }

      if (mounted) {
        _update(() {
          _state = _ScanState.result;
          _detections = matches;
          _detectionRawJson = rawJson;
        });
      }
    } on FunctionException catch (e) {
      _setIdentifyFunctionError(e);
    } on TimeoutException {
      if (mounted) {
        _update(() {
          _state = _ScanState.error;
          _errorMessage =
              'Scan timed out. Try again on Wi‑Fi, or retake with the card closer and less glare.';
        });
      }
    } catch (e) {
      if (mounted) {
        _update(() {
          _state = _ScanState.error;
          _errorMessage = 'Error: ${e.toString()}';
        });
      }
    }
  }

  void _resetToSportPicker() {
    _update(() {
      _state = _ScanState.sportPicker;
      _selectedSport = '';
      _detections = const [];
      _detectionRawJson = const [];
      _errorMessage = null;
    });
  }

  /// Clear results and scan again in the same sport (camera on mobile; picker on web).
  void _onScanAgain() {
    if (_selectedSport.isEmpty) {
      _resetToSportPicker();
      return;
    }
    _update(() {
      _detections = const [];
      _detectionRawJson = const [];
      _errorMessage = null;
      _state = kIsWeb ? _ScanState.sportPicker : _ScanState.camera;
    });
    if (kIsWeb) {
      unawaited(_captureWithImagePicker());
    }
  }

  /// Scan slugs (e.g. `basketball`) → labels used in [ReleaseRecord.sport] / browse.
  String _catalogSportFromScanSlug(String scanSport) {
    switch (scanSport.trim().toLowerCase()) {
      case 'baseball':
        return 'Baseball';
      case 'basketball':
        return 'Basketball';
      case 'football':
        return 'Football';
      case 'hockey':
        return 'Hockey';
      case 'soccer':
        return 'Soccer';
      default:
        if (scanSport.isEmpty) return scanSport;
        return '${scanSport[0].toUpperCase()}${scanSport.substring(1).toLowerCase()}';
    }
  }

  Future<void> _goToCardDetails(ImageScanMatchResult detection) async {
    final card = detection.card;
    final hasId = card.id != null && card.id!.trim().isNotEmpty;
    final hasRelease = card.releaseId != null && card.releaseId!.trim().isNotEmpty;
    final hasSet = card.setId != null && card.setId!.trim().isNotEmpty;

    if (!hasId || !hasRelease || !hasSet) {
      if (!mounted) return;
      context.push(
        '/catalog',
        extra: <String, dynamic>{
          'detection': detection,
          'sport': _selectedSport,
        },
      );
      return;
    }

    setState(() => _openingCatalogDetail = true);
    try {
      final svc = ref.read(cardsServiceProvider);
      final scanId = card.id!.trim();
      final year = int.tryParse(card.year ?? '') ?? DateTime.now().year;
      final releaseName = (card.releaseName?.trim().isNotEmpty == true)
          ? card.releaseName!
          : (card.manufacturer ?? 'Unknown Release');

      final csResult = CatalogSearchCardResult(
        id: scanId,
        name: card.name ?? '',
        number: card.number,
        setId: card.setId!.trim(),
        setName: card.setName ?? '',
        releaseId: card.releaseId!.trim(),
        attributes: const [],
      );

      final resolved = await svc.resolveCardFromCatalog(
        card: csResult,
        releaseName: releaseName,
        releaseYear: year,
        releaseSegmentId: card.segmentId ?? '',
      );

      final release = ReleaseRecord(
        id: card.releaseId!.trim(),
        name: releaseName,
        year: year,
        sport: _catalogSportFromScanSlug(_selectedSport),
      );
      final set = SetRecord(
        id: resolved.setId,
        name: (card.setName?.trim().isNotEmpty == true) ? card.setName!.trim() : 'Set',
      );
      final master = MasterCard(
        id: resolved.masterCardId,
        player: (card.name ?? '').trim(),
        cardNumber: (card.number?.trim().isNotEmpty == true) ? card.number : null,
        imageUrl: (card.imageUrl?.trim().isNotEmpty == true) ? card.imageUrl : null,
      );

      final scanParallel = card.parallel;
      String normalizeParallelName(String name) =>
          name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      SetParallel? matchedParallel;
      if (scanParallel != null && scanParallel.name.isNotEmpty) {
        final target = normalizeParallelName(scanParallel.name);
        for (final p in resolved.parallels) {
          final candidate = normalizeParallelName(p.name);
          if (candidate == target || candidate.contains(target) || target.contains(candidate)) {
            matchedParallel = p;
            break;
          }
        }
      }
      final parallelLabel = scanParallel?.name ?? 'Base';
      final effectiveParallel = switch ((matchedParallel, scanParallel)) {
        (SetParallel p, ParallelInfo s) when p.serialMax == null && s.numberedTo != null => SetParallel(
            id: p.id,
            name: p.name,
            serialMax: s.numberedTo,
            isAuto: p.isAuto,
          ),
        (SetParallel p, _) => p,
        (_, ParallelInfo s) when s.name.isNotEmpty => SetParallel(
            id: s.id.isNotEmpty ? s.id : '__scan_parallel__',
            name: s.name,
            serialMax: s.numberedTo,
          ),
        _ => null,
      };

      if (!mounted) return;
      final resolvedId = await svc.ensureCatalogVariant(
        catalogVariantId: master.id,
        parallelId: effectiveParallel?.id,
      );
      if (!mounted) return;
      final resolvedMaster = await svc.fetchMasterCardById(resolvedId);
      if (!mounted) return;
      final displayCard = resolvedMaster ??
          MasterCard(
            id: resolvedId,
            player: master.player,
            cardNumber: master.cardNumber,
            isRookie: master.isRookie,
            isAuto: master.isAuto || (effectiveParallel?.isAuto ?? false),
            isPatch: master.isPatch,
            isSSP: master.isSSP,
            serialMax: effectiveParallel?.serialMax ?? master.serialMax,
            imageUrl: master.imageUrl,
            gain: master.gain,
          );

      unawaited(ref.read(compsServiceProvider).fetchCardImage(displayCard.id));

      await context.push<void>(
        '/catalog/master',
        extra: MasterCardDetailArgs(
          masterCard: MasterCard(
            id: displayCard.id,
            player: displayCard.player,
            cardNumber: displayCard.cardNumber,
            isRookie: displayCard.isRookie,
            isAuto: displayCard.isAuto || (effectiveParallel?.isAuto ?? false),
            isPatch: displayCard.isPatch,
            isSSP: displayCard.isSSP,
            serialMax: effectiveParallel?.serialMax ?? displayCard.serialMax,
            imageUrl: displayCard.imageUrl,
            guidePriceCardId: displayCard.guidePriceCardId,
            gain: displayCard.gain,
          ),
          parallelName: parallelLabel,
          parallelSerialMax: effectiveParallel?.serialMax,
          parallelIsAuto: effectiveParallel?.isAuto ?? false,
          releaseName: release.name,
          setName: set.name,
          year: release.year,
          sport: release.sport,
          onAddToCollection: () => _showScanAddToCollectionSheet(
                displayCard: displayCard,
                resolvedVariantId: resolvedId,
                parallel: effectiveParallel,
                parallelLabel: parallelLabel,
                set: set,
                release: release,
              ),
          onAddToWishlist: () => _showScanAddToWishlistSheet(
                displayCard: displayCard,
                resolvedVariantId: resolvedId,
                parallel: effectiveParallel,
                parallelLabel: parallelLabel,
                set: set,
                release: release,
              ),
          openedFromScanResults: false,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      AdaptiveSnackBar.show(
        context,
        message: 'Could not open this card. Try the catalog.',
        type: AdaptiveSnackBarType.error,
      );
      context.push(
        '/catalog',
        extra: <String, dynamic>{
          'detection': detection,
          'sport': _selectedSport,
        },
      );
    } finally {
      if (mounted) setState(() => _openingCatalogDetail = false);
    }
  }

  void _showScanAddToCollectionSheet({
    required MasterCard displayCard,
    required String resolvedVariantId,
    required SetParallel? parallel,
    required String parallelLabel,
    required SetRecord set,
    required ReleaseRecord release,
  }) {
    final pricePaidCtrl = TextEditingController();
    final serialNumberCtrl = TextEditingController();
    final gradeValueCtrl = TextEditingController();
    var isGraded = false;
    var grader = 'PSA';

    showAdaptiveSheet<void>(
      context: context,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (context, setModal) {
          return CardSheet(
            title: 'Add to Your Collection',
            card: displayCard,
            setName: set.name,
            releaseName: release.displayName,
            previewParallelName: parallelLabel,
            previewParallelSerialMax: parallel?.serialMax,
            previewParallelIsAuto: parallel?.isAuto ?? false,
            showPricePaid: true,
            pricePaidCtrl: pricePaidCtrl,
            showSerialNumber: parallel?.serialMax != null,
            serialNumberCtrl: serialNumberCtrl,
            showGraded: true,
            isGraded: isGraded,
            grader: grader,
            gradeValueCtrl: gradeValueCtrl,
            onGradedChanged: (v) => setModal(() => isGraded = v),
            onGraderChanged: (g) => setModal(() => grader = g ?? 'PSA'),
            onSave: (_) async {
              try {
                final variantId = await ref.read(cardsServiceProvider).ensureCatalogVariant(
                      catalogVariantId: resolvedVariantId,
                      parallelId: parallel?.id,
                    );
                final form = AddCardFormData(
                  masterCardId: variantId,
                  setId: set.id,
                  player: displayCard.player,
                  cardNumber: displayCard.cardNumber,
                  serialMax: displayCard.serialMax,
                  isRookie: displayCard.isRookie,
                  isAuto: displayCard.isAuto,
                  isPatch: displayCard.isPatch,
                  isSSP: displayCard.isSSP,
                  parallelId: parallel?.id,
                  parallelName: parallelLabel,
                  pricePaid: parseUsdInput(pricePaidCtrl.text),
                  serialNumber: serialNumberCtrl.text.trim().isEmpty ? null : serialNumberCtrl.text.trim(),
                  isGraded: isGraded,
                  grader: isGraded ? grader : 'PSA',
                  gradeValue: isGraded && gradeValueCtrl.text.trim().isNotEmpty ? gradeValueCtrl.text.trim() : null,
                );
                final created = await ref.read(cardsServiceProvider).addCard(form);
                await ref.read(compsServiceProvider).syncMasterCatalogPricingForVariant(created.masterCardId);
                ref.invalidate(userCardsProvider);
                await ref.read(userCardsProvider.future);
                unawaited(ref.read(compsServiceProvider).fetchCardImage(created.masterCardId));
                if (!mounted || !context.mounted) return null;
                pricePaidCtrl.clear();
                serialNumberCtrl.clear();
                gradeValueCtrl.clear();
                isGraded = false;
                grader = 'PSA';
                AdaptiveSnackBar.show(
                  context,
                  message: 'Card added!',
                  type: AdaptiveSnackBarType.success,
                  duration: const Duration(seconds: 2),
                );
                return null;
              } catch (e) {
                return e.toString();
              }
            },
          );
        },
      ),
    ).whenComplete(() {
      pricePaidCtrl.dispose();
      serialNumberCtrl.dispose();
      gradeValueCtrl.dispose();
    });
  }

  void _showScanAddToWishlistSheet({
    required MasterCard displayCard,
    required String resolvedVariantId,
    required SetParallel? parallel,
    required String parallelLabel,
    required SetRecord set,
    required ReleaseRecord release,
  }) {
    final targetPriceCtrl = TextEditingController();

    showAdaptiveSheet<void>(
      context: context,
      builder: (_) => CardSheet(
        title: 'Add to Wishlist',
        card: displayCard,
        setName: set.name,
        releaseName: release.displayName,
        previewParallelName: parallelLabel,
        previewParallelSerialMax: parallel?.serialMax,
        previewParallelIsAuto: parallel?.isAuto ?? false,
        showTargetPrice: true,
        targetPriceCtrl: targetPriceCtrl,
        showGraded: false,
        onSave: (_) async {
          try {
            final variantId = await ref.read(cardsServiceProvider).ensureCatalogVariant(
                  catalogVariantId: resolvedVariantId,
                  parallelId: parallel?.id,
                );
            await ref.read(wishlistProvider.notifier).add({
              'player': displayCard.player.trim(),
              'year': release.year,
              'set_name': release.name,
              'card_number': (displayCard.cardNumber ?? '').trim(),
              'parallel': parallelLabel,
              'is_rookie': displayCard.isRookie,
              'is_auto': displayCard.isAuto,
              'is_patch': displayCard.isPatch,
              'serial_max': displayCard.serialMax,
              'grade': null,
              'ebay_query': null,
              'exclude_terms': [],
              'target_price': parseUsdInput(targetPriceCtrl.text),
              'master_card_id': variantId,
              'release_id': release.id,
              'set_id': set.id,
              'sport': release.sport,
            });
            ref.invalidate(wishlistProvider);
            targetPriceCtrl.clear();
            if (!mounted || !context.mounted) return null;
            AdaptiveSnackBar.show(
              context,
              message: 'Added to Wishlist!',
              type: AdaptiveSnackBarType.success,
              duration: const Duration(seconds: 2),
            );
            return null;
          } catch (e) {
            return e.toString();
          }
        },
      ),
    ).whenComplete(targetPriceCtrl.dispose);
  }

  ({String name, Color color}) _sportDisplayMeta() {
    for (final s in _sports) {
      if (s.$2 == _selectedSport) {
        return (name: s.$1, color: s.$4);
      }
    }
    return (name: 'Scan', color: AppTheme.primary);
  }

  /// Inset scroll content below [buildGlassNavBar] + status bar when using
  /// [extendBodyBehindAppBar].
  EdgeInsets _paddingBelowGlassAppBar(
    BuildContext context, {
    double horizontal = 16,
    double bottom = 24,
    double extraTop = 8,
  }) {
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight + extraTop;
    return EdgeInsets.fromLTRB(horizontal, top, horizontal, bottom);
  }

  Color _confidenceTint(ImageScanMatchResult m) {
    final s = m.matchScore;
    if (s != null) {
      if (s >= 0.72) return const Color(0xFF10B981);
      if (s >= 0.42) return const Color(0xFFF59E0B);
      return const Color(0xFFEF4444);
    }
    switch (m.confidence.toLowerCase()) {
      case 'high':
        return const Color(0xFF10B981);
      case 'medium':
        return const Color(0xFFF59E0B);
      case 'low':
      default:
        return const Color(0xFFEF4444);
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case _ScanState.sportPicker:
        return _buildSportPicker();
      case _ScanState.camera:
        if (kIsWeb) {
          return _buildSportPicker();
        }
        final meta = _sportDisplayMeta();
        return ScanCameraPage(
          accentColor: meta.color,
          sportLabel: meta.name,
          onCaptured: _onCameraCaptured,
          onClose: _exitCameraToSportPicker,
        );
      case _ScanState.processing:
      case _ScanState.error:
        return Scaffold(
          body: _buildProcessingOrError(),
        );
      case _ScanState.result:
        return _buildResultScaffold();
    }
  }

  Widget _buildSportPicker() {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: buildGlassNavBar(
        context,
        title: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Scan Card',
            style: AppFonts.appBarTitle.copyWith(color: colors.onSurface),
          ),
        ),
        actions: appBarShellTrailingActions(context),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                24 + _bodyBottomInsetOverTabBar(context),
              ),
              child: Column(
                children: [
                  GridView.count(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: 1.2,
                    children: _sports.map((sport) {
                      final (name, value, emoji, tintColor) = sport;
                      final selected =
                          _selectedSport.isNotEmpty && _selectedSport == value;
                      return GestureDetector(
                        onTap: () => _selectSport(value),
                        child: Container(
                          decoration: BoxDecoration(
                            color: tintColor.withValues(alpha: 0.15),
                            border: Border.all(
                              color: selected
                                  ? tintColor
                                  : tintColor.withValues(alpha: 0.3),
                              width: selected ? 3 : 1.5,
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(emoji, style: const TextStyle(fontSize: 48)),
                              const SizedBox(height: 12),
                              Text(
                                name,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProcessingOrError() {
    final bottom = _bodyBottomInsetOverTabBar(context);
    if (_state == _ScanState.processing) {
      return Center(
        child: Padding(
          padding: EdgeInsets.only(bottom: bottom),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CardFanLoader(size: 72),
              const SizedBox(height: 20),
              Text(
                'Identifying card…',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, 0, 24, bottom),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Color(0xFFEF4444)),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? 'An error occurred',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            AdaptiveButton.child(
              onPressed: _resetToSportPicker,
              style: AdaptiveButtonStyle.filled,
              color: const Color(0xFF800020),
              child: const Text(
                'Try Again',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultScaffold() {
    final colors = Theme.of(context).colorScheme;
    final onSurface = colors.onSurface;
    final muted = colors.onSurfaceVariant;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: buildGlassNavBar(
        context,
        title: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Scan Results',
            style: AppFonts.appBarTitle.copyWith(color: onSurface),
          ),
        ),
        actions: appBarShellTrailingActions(context),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: _paddingBelowGlassAppBar(
                  context,
                  horizontal: 20,
                  bottom: 8,
                ),
                child: Text(
                  '${_detections.length} possible ${_detections.length == 1 ? 'match' : 'matches'} · tap a row for details',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: muted,
                      ),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  itemCount: _detections.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final m = _detections[index];
                    return _MatchResultTile(
                      match: m,
                      isHero: index == 0,
                      rawDetectionJson: index < _detectionRawJson.length
                          ? _detectionRawJson[index]
                          : '{}',
                      tint: _confidenceTint(m),
                      onSurface: onSurface,
                      muted: muted,
                      onOpen: () => unawaited(_goToCardDetails(m)),
                    );
                  },
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  0,
                  20,
                  24 + _bodyBottomInsetOverTabBar(context),
                ),
                child: AdaptiveButton.child(
                  onPressed: _onScanAgain,
                  style: AdaptiveButtonStyle.bordered,
                  color: const Color(0xFF800020),
                  padding: ChromeMetrics.adaptiveBorderedButtonPadding,
                  child: const Text(
                    'Scan again',
                    style: TextStyle(
                      color: Color(0xFF800020),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_openingCatalogDetail)
            Positioned.fill(
              child: AbsorbPointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surface.withValues(alpha: 0.92),
                  ),
                  child: const Center(
                    child: CardFanLoader(size: 72),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// JSON debug panel: [Scrollbar.thumbVisibility] requires a [ScrollController] when
/// there is no [PrimaryScrollController] (e.g. inside [ExpansionTile] children).
class _RawJsonScrollBox extends StatefulWidget {
  const _RawJsonScrollBox({
    required this.text,
    required this.textStyle,
  });

  final String text;
  final TextStyle textStyle;

  @override
  State<_RawJsonScrollBox> createState() => _RawJsonScrollBoxState();
}

class _RawJsonScrollBoxState extends State<_RawJsonScrollBox> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _scrollController,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.all(10),
        child: SelectableText(
          widget.text,
          style: widget.textStyle,
        ),
      ),
    );
  }
}

class _MatchResultTile extends StatelessWidget {
  const _MatchResultTile({
    required this.match,
    this.isHero = false,
    required this.rawDetectionJson,
    required this.tint,
    required this.onSurface,
    required this.muted,
    required this.onOpen,
  });

  final ImageScanMatchResult match;
  final bool isHero;
  final String rawDetectionJson;
  final Color tint;
  final Color onSurface;
  final Color muted;
  final VoidCallback onOpen;

  static const _mono = TextStyle(
    fontFamily: 'monospace',
    fontSize: 11,
    height: 1.35,
  );

  @override
  Widget build(BuildContext context) {
    final card = match.card;
    final title = (card.name?.trim().isNotEmpty == true)
        ? card.name!.trim()
        : 'Partial match';
    final parts = <String>[
      if (card.year != null && card.year!.isNotEmpty) card.year!,
      if (card.releaseName != null && card.releaseName!.isNotEmpty)
        card.releaseName!,
      if (card.setName != null && card.setName!.isNotEmpty) card.setName!,
      if (card.parallel != null && card.parallel!.name.isNotEmpty) card.parallel!.name,
    ];
    final subtitle = parts.isEmpty ? 'Open to search catalog' : parts.join(' · ');

    final confidenceLine = match.matchScore != null
        ? '${match.confidenceLabel} · ${match.confidence}'
        : match.confidence;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isHero ? tint.withValues(alpha: 0.55) : tint.withValues(alpha: 0.35),
          width: isHero ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isHero) _ScanHeroImage(match: match),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onOpen,
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            14,
                            isHero ? 12 : 14,
                            14,
                            14,
                          ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: onSurface,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: muted,
                                  height: 1.25,
                                ),
                          ),
                          if (card.parallel != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              card.parallel!.numberedTo != null
                                  ? '${card.parallel!.name} /${card.parallel!.numberedTo}'
                                  : card.parallel!.name,
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: AppTheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ],
                          if (match.grading != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              'Slab: ${match.grading!.slabSummary}',
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: muted,
                                  ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: tint.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: tint.withValues(alpha: 0.65)),
                          ),
                          child: Text(
                            confidenceLine,
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              color: tint,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Icon(Icons.chevron_right_rounded, color: muted, size: 22),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          Divider(height: 1, color: muted.withValues(alpha: 0.2)),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              title: Text(
                'Raw detection (debug)',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: muted,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: muted.withValues(alpha: 0.25)),
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: _RawJsonScrollBox(
                      text: rawDetectionJson,
                      textStyle: _mono.copyWith(color: onSurface),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Large catalog image for the top-ranked scan match (API URL or lazy fetch).
class _ScanHeroImage extends ConsumerStatefulWidget {
  const _ScanHeroImage({required this.match});

  final ImageScanMatchResult match;

  @override
  ConsumerState<_ScanHeroImage> createState() => _ScanHeroImageState();
}

class _ScanHeroImageState extends ConsumerState<_ScanHeroImage> {
  String? _url;

  @override
  void initState() {
    super.initState();
    _url = _initialUrl();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_maybeFetch()));
  }

  @override
  void didUpdateWidget(covariant _ScanHeroImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.match.card.id != widget.match.card.id ||
        oldWidget.match.card.imageUrl != widget.match.card.imageUrl) {
      _url = _initialUrl();
      unawaited(_maybeFetch());
    }
  }

  String? _initialUrl() {
    final u = widget.match.card.imageUrl?.trim();
    if (u != null && u.isNotEmpty) return u;
    return null;
  }

  Future<void> _maybeFetch() async {
    if (_url != null && _url!.isNotEmpty) return;
    final id = widget.match.card.id;
    if (id == null || id.isEmpty) return;
    final fetched = await ref.read(compsServiceProvider).fetchCardImage(id);
    if (!mounted || fetched == null || fetched.isEmpty) return;
    setState(() => _url = fetched);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final u = _url;
    final mq = MediaQuery.sizeOf(context);
    // Short enough that the top match + text stay comfortably above the fixed
    // "Scan again" bar without treating the hero like a full slab scroll.
    final h = (mq.height * 0.2).clamp(132.0, 176.0);

    return SizedBox(
      height: h,
      width: double.infinity,
      child: ColoredBox(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
        child: u == null || u.isEmpty
            ? Center(
                child: Icon(
                  Icons.image_not_supported_outlined,
                  size: 36,
                  color: colors.onSurfaceVariant.withValues(alpha: 0.45),
                ),
              )
            : CachedNetworkImage(
                imageUrl: u,
                fit: BoxFit.contain,
                width: double.infinity,
                height: h,
                fadeInDuration: const Duration(milliseconds: 200),
                placeholder: (_, _) => Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.primary.withValues(alpha: 0.85),
                    ),
                  ),
                ),
                errorWidget: (_, _, _) => Center(
                  child: Icon(
                    Icons.broken_image_outlined,
                    size: 36,
                    color: colors.onSurfaceVariant.withValues(alpha: 0.45),
                  ),
                ),
              ),
      ),
    );
  }
}
