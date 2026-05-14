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
import '../../core/models/cardhedge_image_search.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/chrome_metrics.dart';
import '../../core/theme/fonts.dart';
import '../../core/widgets/app_bar_shell_trailing_actions.dart';
import '../../core/widgets/card_fan_loader.dart';
import '../../core/widgets/glass_nav_bar.dart';
import '../collection/master_card_detail_screen.dart';
import '../wishlist/card_sheet.dart';
import '../wishlist/wishlist_screen.dart' show wishlistProvider;
import 'scan_catalog_bridge.dart';
import 'scan_models.dart';
import 'widgets/scan_camera_page.dart';

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
  /// Optional: `--dart-define=SCAN_IDENTIFY_STRATEGY=cardhedge` → forwarded to `identify-card`
  /// (same values as Supabase env `SCAN_IDENTIFY_STRATEGY`).
  static const _kScanIdentifyStrategy = String.fromEnvironment(
    'SCAN_IDENTIFY_STRATEGY',
    defaultValue: '',
  );

  _ScanState _state = _ScanState.sportPicker;
  String _selectedSport = '';
  List<ImageScanMatchResult> _detections = const [];
  /// Pretty-printed JSON for each row in [_detections] (same order after sort).
  List<String> _detectionRawJson = const [];
  /// Per-row `vision_merge_debug` from `identify-card` (CardHedge ↔ CardSight).
  List<String> _detectionMergeDebugJson = const [];
  /// e.g. `merge · strategy: auto` from `identify-card` response.
  String _identifyVisionMeta = '';
  /// From `identify-card` when `identify_mode` is `merge` (empty otherwise).
  String _identifyMode = '';
  /// Full CardHedge image-search rows for merge UI (see `cardhedge_candidates` on edge).
  List<CardHedgeImageSearchHit> _mergeChCandidates = const [];
  /// Selected `card_id` for [_mergeChCandidates] (row highlight only).
  String? _selectedMergeChCardId;
  /// When set, user chose a catalog [SetParallel] not surfaced by CardHedge (clears CH guide id).
  SetParallel? _selectedCatalogParallelExtra;
  /// [set_parallels] rows for the spine [ScannedCatalogCard.setId] minus those likely covered by CH variants.
  List<SetParallel> _mergeCatalogParallelsExtras = const [];
  bool _mergeCatalogParallelsLoading = false;
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
    final body = <String, dynamic>{
      'imageBase64': base64,
      'sport': _selectedSport,
      'enrichChCandidates': true,
    };
    if (_kScanIdentifyStrategy.trim().isNotEmpty) {
      body['identifyStrategy'] = _kScanIdentifyStrategy.trim();
    }
    return _supabase.functions
        .invoke(
          _scanFunctionName,
          body: body,
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

  bool get _mergeSpinePicker =>
      _identifyMode == 'merge' &&
      _mergeChCandidates.isNotEmpty &&
      _detections.isNotEmpty;

  String? get _resolvedMergeChSelection {
    if (_selectedCatalogParallelExtra != null) return null;
    final s = _selectedMergeChCardId?.trim();
    if (s != null && s.isNotEmpty) return s;
    return null;
  }

  bool get _mergeSpineHasCatalogSetId =>
      _detections.isNotEmpty &&
      (_detections.first.card.setId?.trim().isNotEmpty ?? false);

  static String _normParallelToken(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  /// Whether a CardHedge [variant] (or description) likely refers to the same parallel as [parallelName].
  static bool _chTextCoversDbParallel(String? chText, String parallelName) {
    final v = _normParallelToken(chText ?? '');
    final p = _normParallelToken(parallelName);
    if (p.isEmpty) return false;
    if (v.isEmpty) return false;
    if (v == p) return true;
    if (v.length >= 5 && p.length >= 5 && (v.contains(p) || p.contains(v))) return true;
    return false;
  }

  static bool _chHitsCoverParallel(List<CardHedgeImageSearchHit> hits, SetParallel parallel) {
    for (final h in hits) {
      if (_chTextCoversDbParallel(h.variant, parallel.name)) return true;
      if (_chTextCoversDbParallel(h.description, parallel.name)) return true;
    }
    return false;
  }

  Future<void> _loadMergeCatalogParallelsNotInCh(
    String setId,
    List<CardHedgeImageSearchHit> chHits,
  ) async {
    try {
      final all = await ref.read(cardsServiceProvider).getParallels(setId);
      if (!mounted) return;
      final extras =
          all.where((p) => !_chHitsCoverParallel(chHits, p)).toList(growable: false);
      setState(() {
        _mergeCatalogParallelsExtras = extras;
        _mergeCatalogParallelsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _mergeCatalogParallelsExtras = const [];
        _mergeCatalogParallelsLoading = false;
      });
    }
  }

  /// CardSight spine only: no parallel, no CardHedge fields (non-interactive “Set match” panel).
  ImageScanMatchResult _spineForSetMatchPanel() {
    final spine = _detections.first;
    return spine.copyWith(
      card: spine.card.copyWith(clearParallel: true),
      clearCardHedge: true,
    );
  }

  /// CardSight often omits `card.name`; CardHedge image-search hits usually include `player`.
  String? _firstChPlayerName() {
    for (final h in _mergeChCandidates) {
      final p = h.player?.trim();
      if (p != null && p.isNotEmpty) return p;
    }
    return null;
  }

  /// Spine + one CardHedge hit for [_goToCardDetails] after the user picks a parallel row.
  ImageScanMatchResult _detectionWithChHit(CardHedgeImageSearchHit hit) {
    final spine = _detections.first;
    final v = hit.variant?.trim();
    final parallelFromCh =
        (v != null && v.isNotEmpty) ? ParallelInfo(id: '', name: v) : spine.card.parallel;
    final img = hit.image?.trim();
    final hp = hit.player?.trim();
    final sn = spine.card.name?.trim();
    final mergedName = (sn != null && sn.isNotEmpty) ? spine.card.name : (hp != null && hp.isNotEmpty ? hp : spine.card.name);
    final hCr = hit.cardsightReleaseId?.trim();
    final hCs = hit.cardsightSetId?.trim();
    return spine.copyWith(
      card: spine.card.copyWith(
        parallel: parallelFromCh,
        imageUrl: (img != null && img.isNotEmpty) ? img : spine.card.imageUrl,
        name: mergedName,
        cardsightReleaseId: (hCr != null && hCr.isNotEmpty) ? hCr : spine.card.cardsightReleaseId,
        cardsightSetId: (hCs != null && hCs.isNotEmpty) ? hCs : spine.card.cardsightSetId,
      ),
      cardHedgeCardId: hit.cardId,
      cardHedgeVariant: hit.variant,
      cardHedgeSetLabel: hit.setLabel,
      cardHedgeImageSimilarity: hit.similarityScore,
    );
  }

  Widget _buildMergeCardHedgeSection(Color onSurface, Color muted) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Parallels (CardHedge)',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: onSurface,
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          'Tap the variant that matches your card to open it in the catalog.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: muted, height: 1.3),
        ),
        const SizedBox(height: 12),
        for (final h in _mergeChCandidates) ...[
          _ChCandidateTile(
            hit: h,
            variantOnly: true,
            selected: _selectedCatalogParallelExtra == null &&
                _resolvedMergeChSelection != null &&
                _resolvedMergeChSelection == h.cardId,
            onSurface: onSurface,
            muted: muted,
            onTap: () {
              setState(() {
                _selectedMergeChCardId = h.cardId;
                _selectedCatalogParallelExtra = null;
              });
              unawaited(_goToCardDetails(_detectionWithChHit(h)));
            },
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  /// [set_parallels] extras and loading — shown below the CardHedge list, not inside the CardSight tile.
  Widget _buildMergeCatalogExtrasSection(Color onSurface, Color muted) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_mergeCatalogParallelsLoading)
          const Padding(
            padding: EdgeInsets.only(top: 4, bottom: 8),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        if (!_mergeCatalogParallelsLoading && _mergeSpinePicker && !_mergeSpineHasCatalogSetId)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Could not create catalog rows for this scan (missing CardSight linkage or ensure failed). Try again or pick another CardHedge match.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: muted, height: 1.3),
            ),
          ),
        if (!_mergeCatalogParallelsLoading && _mergeCatalogParallelsExtras.isNotEmpty) ...[
          const SizedBox(height: 8),
          Divider(height: 1, color: muted.withValues(alpha: 0.2)),
          const SizedBox(height: 12),
          Text(
            'More parallels in this set',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: onSurface,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Parallels from your catalog not shown in the CardHedge list. Tap to open the card with that parallel.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: muted, height: 1.3),
          ),
          const SizedBox(height: 10),
          for (final p in _mergeCatalogParallelsExtras) ...[
            _CatalogParallelOptionTile(
              parallel: p,
              selected: _selectedCatalogParallelExtra?.id == p.id,
              onSurface: onSurface,
              muted: muted,
              onTap: () {
                final spine = _detections.first;
                final det = spine.copyWith(
                  card: spine.card.copyWith(
                    parallel: ParallelInfo(
                      id: p.id,
                      name: p.name,
                      numberedTo: p.serialMax,
                    ),
                  ),
                  clearCardHedge: true,
                );
                setState(() {
                  _selectedCatalogParallelExtra = p;
                  _selectedMergeChCardId = null;
                });
                unawaited(_goToCardDetails(det));
              },
            ),
            const SizedBox(height: 6),
          ],
        ],
      ],
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

      final identifyMode = data['identify_mode']?.toString() ?? '';
      final identifyStrat = data['identify_strategy_requested']?.toString() ?? '';
      final orderRaw = data['vision_upstream_order'];
      String? orderStr;
      if (orderRaw is List) {
        orderStr = orderRaw.map((e) => e.toString()).join(' → ');
      }
      final visionMeta = [
        if (identifyMode.isNotEmpty) 'mode: $identifyMode',
        if (identifyStrat.isNotEmpty) 'strategy: $identifyStrat',
        if (orderStr != null && orderStr.isNotEmpty) 'order: $orderStr',
      ].join(' · ');

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
      final pairs = <({ImageScanMatchResult m, String raw, String merge})>[];
      for (final e in detectionsRaw) {
        final map = Map<String, dynamic>.from(e as Map);
        final md = map['vision_merge_debug'];
        final mergeStr = md != null ? encoder.convert(md) : '';
        pairs.add((
          m: ImageScanMatchResult.fromJson(map),
          raw: encoder.convert(map),
          merge: mergeStr,
        ));
      }
      pairs.sort((a, b) => _detectionCompare(a.m, b.m));

      var matches = pairs.map((p) => p.m).toList();
      final rawJson = pairs.map((p) => p.raw).toList();
      final mergeJson = pairs.map((p) => p.merge).toList();

      var chCandidates = const <CardHedgeImageSearchHit>[];
      if (identifyMode == 'merge') {
        final rawCh = data['cardhedge_candidates'] ?? data['cardhedge_hits_sample'];
        if (rawCh is List) {
          chCandidates = rawCh
              .map((e) {
                if (e is! Map) return null;
                return CardHedgeImageSearchHit.fromJson(
                  Map<String, dynamic>.from(e),
                );
              })
              .whereType<CardHedgeImageSearchHit>()
              .where((h) => h.cardId.isNotEmpty)
              .toList();
        }
      }

      if (identifyMode == 'merge' && matches.isNotEmpty) {
        matches = await _hydrateTopMatchVaultFromCardSight(matches, chCandidates);
      }

      if (matches.isNotEmpty) {
        final top = matches.first;
        final topId = top.card.id?.trim();
        if (topId != null && topId.isNotEmpty) {
          final url = await ref.read(compsServiceProvider).fetchCardImage(topId);
          if (!mounted) return;
          if (url != null && url.trim().isNotEmpty) {
            matches = [
              top.copyWith(card: top.card.copyWith(imageUrl: url.trim())),
              ...matches.skip(1),
            ];
          }
        }
      }

      final setIdForExtras =
          (identifyMode == 'merge' && matches.isNotEmpty) ? matches.first.card.setId?.trim() : null;
      final extrasLoading =
          setIdForExtras != null && setIdForExtras.isNotEmpty;

      if (mounted) {
        _update(() {
          _state = _ScanState.result;
          _detections = matches;
          _detectionRawJson = rawJson;
          _detectionMergeDebugJson = mergeJson;
          _identifyVisionMeta = visionMeta;
          _identifyMode = identifyMode;
          _mergeChCandidates = chCandidates;
          _selectedMergeChCardId = null;
          _selectedCatalogParallelExtra = null;
          _mergeCatalogParallelsExtras = const [];
          _mergeCatalogParallelsLoading = extrasLoading;
        });
      }
      if (mounted && extrasLoading) {
        unawaited(_loadMergeCatalogParallelsNotInCh(setIdForExtras, chCandidates));
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
      _detectionMergeDebugJson = const [];
      _identifyVisionMeta = '';
      _identifyMode = '';
      _mergeChCandidates = const [];
      _selectedMergeChCardId = null;
      _selectedCatalogParallelExtra = null;
      _mergeCatalogParallelsExtras = const [];
      _mergeCatalogParallelsLoading = false;
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
      _detectionMergeDebugJson = const [];
      _identifyVisionMeta = '';
      _identifyMode = '';
      _mergeChCandidates = const [];
      _selectedMergeChCardId = null;
      _selectedCatalogParallelExtra = null;
      _mergeCatalogParallelsExtras = const [];
      _mergeCatalogParallelsLoading = false;
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

  /// Best CardHedge row that already has a resolved CardSight release+set spine.
  static CardHedgeImageSearchHit? _bestChHitWithSpineFrom(List<CardHedgeImageSearchHit> ch) {
    if (ch.isEmpty) return null;
    CardHedgeImageSearchHit? best;
    var bestSim = -1.0;
    for (final h in ch) {
      final cr = h.cardsightReleaseId?.trim();
      final cs = h.cardsightSetId?.trim();
      if (cr == null || cr.isEmpty || cs == null || cs.isEmpty) continue;
      final s = h.similarityScore;
      if (s > bestSim) {
        bestSim = s;
        best = h;
      }
    }
    return best;
  }

  /// Prefer CardHedge-enriched `cardsightReleaseId` / `cardsightSetId` over CardSight vision
  /// (vision often mis-picks league/product; CH spine is keyed to the matched listing).
  static ImageScanMatchResult _overlayChSpineOnDetection(
    ImageScanMatchResult detection,
    List<CardHedgeImageSearchHit> chCandidates,
  ) {
    if (chCandidates.isEmpty) return detection;

    CardHedgeImageSearchHit? pick;
    final hid = detection.cardHedgeCardId?.trim();
    if (hid != null && hid.isNotEmpty) {
      for (final h in chCandidates) {
        if (h.cardId == hid) {
          pick = h;
          break;
        }
      }
    }

    if (pick != null) {
      final cr0 = pick.cardsightReleaseId?.trim();
      final cs0 = pick.cardsightSetId?.trim();
      if (cr0 == null || cr0.isEmpty || cs0 == null || cs0.isEmpty) {
        pick = _bestChHitWithSpineFrom(chCandidates);
      }
    } else {
      pick = _bestChHitWithSpineFrom(chCandidates);
    }

    if (pick == null) return detection;
    final cr = pick.cardsightReleaseId!.trim();
    final cs = pick.cardsightSetId!.trim();
    if (cr.isEmpty || cs.isEmpty) return detection;

    return detection.copyWith(
      card: detection.card.copyWith(cardsightReleaseId: cr, cardsightSetId: cs),
    );
  }

  /// Prefer CardHedge-enriched spine using current merge candidate list.
  ImageScanMatchResult _effectiveDetectionForDbResolve(ImageScanMatchResult detection) {
    return _overlayChSpineOnDetection(detection, _mergeChCandidates);
  }

  /// After identify (merge mode), create missing Vault `releases` / `sets` / `set_parallels` /
  /// `set_cards` via `catalog-ensure-from-scan-selection` so the UI has a real `set_id` for parallels.
  Future<List<ImageScanMatchResult>> _hydrateTopMatchVaultFromCardSight(
    List<ImageScanMatchResult> matches,
    List<CardHedgeImageSearchHit> chCandidates,
  ) async {
    if (matches.isEmpty) return matches;
    final top = chCandidates.isEmpty
        ? matches.first
        : _overlayChSpineOnDetection(matches.first, chCandidates);
    final rest = matches.skip(1).toList();
    final c = top.card;
    final cid = c.id?.trim();
    final sr = c.cardsightReleaseId?.trim();
    final ss = c.cardsightSetId?.trim();
    final hasVaultSet = c.setId != null && c.setId!.trim().isNotEmpty;
    final hasVaultRelease = c.releaseId != null && c.releaseId!.trim().isNotEmpty;
    if (hasVaultSet && hasVaultRelease) {
      return [top, ...rest];
    }
    if (cid == null || cid.isEmpty || sr == null || sr.isEmpty || ss == null || ss.isEmpty) {
      return [top, ...rest];
    }
    if (!mounted) return [top, ...rest];
    try {
      final svc = ref.read(cardsServiceProvider);
      final year = int.tryParse(c.year ?? '') ?? DateTime.now().year;
      final releaseName = (c.releaseName?.trim().isNotEmpty == true)
          ? c.releaseName!
          : (c.manufacturer ?? 'Unknown Release');
      final ensured = await svc.ensureCatalogFromScanSelection(
        cardsightReleaseId: sr,
        cardsightSetId: ss,
        cardsightCardId: cid,
        releaseName: releaseName,
        releaseYear: year,
        releaseSegmentId: c.segmentId ?? _selectedSport,
        cardHedgeCardId: top.cardHedgeCardId,
        cardHedgeVariant: top.cardHedgeVariant,
        parallelName: c.parallel?.name,
      );
      if (ensured == null || !mounted) return [top, ...rest];
      return [
        top.copyWith(
          card: c.copyWith(
            setId: ensured.setId,
            releaseId: ensured.releaseId,
          ),
        ),
        ...rest,
      ];
    } catch (_) {
      return [top, ...rest];
    }
  }

  Future<void> _goToCardDetails(ImageScanMatchResult detection) async {
    final det = _effectiveDetectionForDbResolve(detection);
    final card = det.card;
    final scanCatalogCardId = card.id?.trim();
    final hasCardId = scanCatalogCardId != null && scanCatalogCardId.isNotEmpty;

    final vaultRelease = card.releaseId?.trim();
    final vaultSet = card.setId?.trim();
    final hasVaultPair =
        (vaultRelease?.isNotEmpty ?? false) && (vaultSet?.isNotEmpty ?? false);

    final spineRelease = card.cardsightReleaseId?.trim();
    final spineSet = card.cardsightSetId?.trim();
    final hasSpinePair =
        (spineRelease?.isNotEmpty ?? false) && (spineSet?.isNotEmpty ?? false);

    // Need a CardSight catalog card id to import `set_cards` / variants. Release+set may be
    // vault UUIDs only, CardSight spine ids only, or both (see [CardsService]).
    if (!hasCardId) {
      if (!mounted) return;
      AdaptiveSnackBar.show(
        context,
        message:
            'This scan has no catalog card ID yet, so the app cannot load the checklist row. Try merge mode with CardSight + CardHedge, or scan again with a clearer front photo.',
        type: AdaptiveSnackBarType.error,
      );
      return;
    }
    if (!hasVaultPair && !hasSpinePair) {
      if (!mounted) return;
      AdaptiveSnackBar.show(
        context,
        message:
            'Could not resolve this product to your catalog (missing release/set linkage). Try again, or check that this release exists in your Vault.',
        type: AdaptiveSnackBarType.error,
      );
      return;
    }

    final svc = ref.read(cardsServiceProvider);
    setState(() => _openingCatalogDetail = true);
    try {
      final year = int.tryParse(card.year ?? '') ?? DateTime.now().year;
      final releaseName = (card.releaseName?.trim().isNotEmpty == true)
          ? card.releaseName!
          : (card.manufacturer ?? 'Unknown Release');

      final csR = card.cardsightReleaseId?.trim();
      final csS = card.cardsightSetId?.trim();
      if (csR != null &&
          csR.isNotEmpty &&
          csS != null &&
          csS.isNotEmpty) {
        final ensured = await svc.ensureCatalogFromScanSelection(
          cardsightReleaseId: csR,
          cardsightSetId: csS,
          cardsightCardId: scanCatalogCardId,
          releaseName: releaseName,
          releaseYear: year,
          releaseSegmentId: card.segmentId ?? _selectedSport,
          cardHedgeCardId: det.cardHedgeCardId,
          cardHedgeVariant: det.cardHedgeVariant,
          parallelName: card.parallel?.name,
        );
        if (ensured != null && mounted) {
          final rs = await svc.getReleaseAndSetForSetId(ensured.setId);
          final release = rs.release;
          final set = rs.set;
          final detailYear = release.year ?? year;
          final parallels = await svc.getParallels(ensured.setId);
          SetParallel? effectiveParallel;
          final epId = ensured.parallelId?.trim();
          if (epId != null && epId.isNotEmpty) {
            for (final p in parallels) {
              if (p.id == epId) {
                effectiveParallel = p;
                break;
              }
            }
          }
          effectiveParallel ??= pickCatalogParallel(
            parallels: parallels,
            scanParallel: card.parallel,
            cardHedgeVariant: det.cardHedgeVariant,
          );
          final parallelLabel = catalogParallelDisplayLabel(
            resolved: effectiveParallel,
            scanParallel: card.parallel,
            cardHedgeVariant: det.cardHedgeVariant,
          );
          final resolvedId = ensured.masterCardDefinitionsId;
          if (!mounted) return;
          final resolvedMaster = await svc.fetchMasterCardById(resolvedId);
          if (!mounted) return;
          final displayCard = resolvedMaster ??
              MasterCard(
                id: resolvedId,
                player: (card.name ?? '').trim(),
                cardNumber: (card.number?.trim().isNotEmpty == true) ? card.number : null,
                isRookie: false,
                isAuto: effectiveParallel?.isAuto ?? false,
                isPatch: false,
                isSSP: false,
                serialMax: effectiveParallel?.serialMax,
                imageUrl: (card.imageUrl?.trim().isNotEmpty == true) ? card.imageUrl : null,
                guidePriceCardId: det.cardHedgeCardId?.trim().isNotEmpty == true
                    ? det.cardHedgeCardId!.trim()
                    : null,
                gain: null,
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
              year: detailYear,
              sport: release.sport ?? _catalogSportFromScanSlug(_selectedSport),
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
          return;
        }
      }

      late final ({String masterCardId, String setId, List<SetParallel> parallels}) resolved;

      if (hasVaultPair) {
        final vRel = vaultRelease!;
        final vSet = vaultSet!;
        final anchor = await svc.classifyScanCatalogAnchor(
          releaseId: vRel,
          setId: vSet,
        );
        final cardsightReleaseForImport =
            (spineRelease != null && spineRelease.isNotEmpty) ? spineRelease : vRel;
        final cardsightSetForImport =
            (spineSet != null && spineSet.isNotEmpty) ? spineSet : vSet;

        resolved = anchor == ScanCatalogAnchorKind.vaultPrimaryKeys
            ? await svc.resolveVaultAnchoredScanCard(
                vaultReleaseId: vRel,
                vaultSetId: vSet,
                scanCatalogCardId: scanCatalogCardId,
                cardsightReleaseIdForImport: spineRelease,
                cardsightSetIdForImport: spineSet,
              )
            : await svc.ensureCardSightSpineAndScanCardResolved(
                cardsightReleaseId: cardsightReleaseForImport,
                cardsightSetId: cardsightSetForImport,
                cardsightCardId: scanCatalogCardId,
                releaseName: releaseName,
                releaseYear: year,
                releaseSegmentId: card.segmentId ?? '',
              );
      } else {
        resolved = await svc.ensureCardSightSpineAndScanCardResolved(
          cardsightReleaseId: spineRelease!,
          cardsightSetId: spineSet!,
          cardsightCardId: scanCatalogCardId,
          releaseName: releaseName,
          releaseYear: year,
          releaseSegmentId: card.segmentId ?? '',
        );
      }

      final rs = await svc.getReleaseAndSetForSetId(resolved.setId);
      final release = rs.release;
      final set = rs.set;
      final detailYear = release.year ?? year;
      final master = MasterCard(
        id: resolved.masterCardId,
        player: (card.name ?? '').trim(),
        cardNumber: (card.number?.trim().isNotEmpty == true) ? card.number : null,
        imageUrl: (card.imageUrl?.trim().isNotEmpty == true) ? card.imageUrl : null,
      );

      final scanParallel = card.parallel;
      final matchedParallel = pickCatalogParallel(
        parallels: resolved.parallels,
        scanParallel: scanParallel,
        cardHedgeVariant: det.cardHedgeVariant,
      );
      final parallelLabel = catalogParallelDisplayLabel(
        resolved: matchedParallel,
        scanParallel: scanParallel,
        cardHedgeVariant: det.cardHedgeVariant,
      );
      SetParallel? effectiveParallel = matchedParallel;
      if (matchedParallel != null &&
          scanParallel != null &&
          matchedParallel.serialMax == null &&
          scanParallel.numberedTo != null) {
        effectiveParallel = SetParallel(
          id: matchedParallel.id,
          name: matchedParallel.name,
          serialMax: scanParallel.numberedTo,
          isAuto: matchedParallel.isAuto,
        );
      }

      if (!mounted) return;
      final resolvedId = await svc.ensureCatalogVariant(
        catalogVariantId: master.id,
        parallelId: effectiveParallel?.id,
      );
      if (!mounted) return;

      final chId = det.cardHedgeCardId?.trim();
      if (chId != null && chId.isNotEmpty) {
        await ref.read(compsServiceProvider).persistCardHedgeHydratedFromCardId(
              masterVariantId: resolvedId,
              guidePriceCardId: chId,
            );
      }

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
          year: detailYear,
          sport: release.sport ?? _catalogSportFromScanSlug(_selectedSport),
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
    } catch (e) {
      if (!mounted) return;
      AdaptiveSnackBar.show(
        context,
        message: 'Could not load this card: $e',
        type: AdaptiveSnackBarType.error,
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _mergeSpinePicker
                          ? 'Set match is informational — pick a parallel below to open the card in the catalog.'
                          : '${_detections.length} possible ${_detections.length == 1 ? 'match' : 'matches'} · tap a row for details',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: muted,
                          ),
                    ),
                    if (_identifyVisionMeta.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        _identifyVisionMeta,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: muted.withValues(alpha: 0.85),
                              fontFamily: 'monospace',
                              fontSize: 10,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: _mergeSpinePicker
                    ? ListView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        children: [
                          _SetMatchPanel(
                            match: _spineForSetMatchPanel(),
                            fallbackPlayerName: _firstChPlayerName(),
                            rawDetectionJson: _detectionRawJson.isNotEmpty
                                ? _detectionRawJson.first
                                : '{}',
                            mergeDebugJson: _detectionMergeDebugJson.isNotEmpty
                                ? _detectionMergeDebugJson.first
                                : '',
                            tint: _confidenceTint(_detections.first),
                            onSurface: onSurface,
                            muted: muted,
                          ),
                          const SizedBox(height: 16),
                          _buildMergeCardHedgeSection(onSurface, muted),
                          const SizedBox(height: 8),
                          _buildMergeCatalogExtrasSection(onSurface, muted),
                          if (_detections.length > 1)
                            Theme(
                              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                              child: ExpansionTile(
                                tilePadding: EdgeInsets.zero,
                                childrenPadding: const EdgeInsets.only(bottom: 8),
                                title: Text(
                                  'Other CardSight matches (${_detections.length - 1})',
                                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                        color: muted,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                                children: [
                                  for (var i = 1; i < _detections.length; i++)
                                    ListTile(
                                      dense: true,
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(
                                        (_detections[i].card.name?.trim().isNotEmpty == true)
                                            ? _detections[i].card.name!.trim()
                                            : 'Match ${i + 1}',
                                        style: TextStyle(
                                          color: onSurface,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      subtitle: Text(
                                        [
                                          if (_detections[i].card.setName != null &&
                                              _detections[i].card.setName!.trim().isNotEmpty)
                                            _detections[i].card.setName!.trim(),
                                          _detections[i].confidenceLabel,
                                        ].join(' · '),
                                        style: TextStyle(color: muted, fontSize: 12),
                                      ),
                                      trailing: Icon(
                                        Icons.chevron_right_rounded,
                                        color: muted,
                                        size: 22,
                                      ),
                                      onTap: () =>
                                          unawaited(_goToCardDetails(_detections[i])),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      )
                    : ListView.separated(
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
                            mergeDebugJson: index < _detectionMergeDebugJson.length
                                ? _detectionMergeDebugJson[index]
                                : '',
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

/// One CardHedge image-search row in merge results (selectable list below the CardSight tile).
class _ChCandidateTile extends StatelessWidget {
  const _ChCandidateTile({
    required this.hit,
    this.variantOnly = false,
    required this.selected,
    required this.onSurface,
    required this.muted,
    required this.onTap,
  });

  final CardHedgeImageSearchHit hit;
  final bool variantOnly;
  final bool selected;
  final Color onSurface;
  final Color muted;
  final VoidCallback onTap;

  static String _confidenceLabel(CardHedgeImageSearchHit h) {
    final raw = h.similarityLabel?.trim();
    if (raw != null && raw.isNotEmpty) return raw;
    final s = h.similarityScore;
    if (s > 0) return '${(s * 100).round()}%';
    return '—';
  }

  static Color _confidenceColor(CardHedgeImageSearchHit h) {
    final s = h.similarityScore;
    if (s >= 0.72) return const Color(0xFF059669);
    if (s >= 0.48) return const Color(0xFFD97706);
    if (s > 0) return const Color(0xFFDC2626);
    return const Color(0xFF64748B);
  }

  Widget _buildVariantPick(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final border = selected ? AppTheme.primary : muted.withValues(alpha: 0.28);
    final bg = selected
        ? AppTheme.primary.withValues(alpha: 0.08)
        : scheme.surfaceContainerHighest.withValues(alpha: 0.35);
    final v = hit.variant?.trim();
    final d = hit.description?.trim();
    final title = (v != null && v.isNotEmpty)
        ? v
        : (d != null && d.isNotEmpty)
            ? d
            : 'Base';
    final img = hit.image?.trim();
    final confColor = _confidenceColor(hit);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border, width: selected ? 2 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                    size: 22,
                    color: selected ? AppTheme.primary : muted.withValues(alpha: 0.55),
                  ),
                  const SizedBox(width: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 40,
                      height: 56,
                      child: (img != null && img.isNotEmpty)
                          ? CachedNetworkImage(
                              imageUrl: img,
                              fit: BoxFit.cover,
                              fadeInDuration: const Duration(milliseconds: 150),
                              placeholder: (_, _) => ColoredBox(
                                color: scheme.surfaceContainerHighest,
                                child: Center(
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppTheme.primary.withValues(alpha: 0.7),
                                    ),
                                  ),
                                ),
                              ),
                              errorWidget: (_, _, _) => ColoredBox(
                                color: scheme.surfaceContainerHighest,
                                child: Icon(
                                  Icons.broken_image_outlined,
                                  size: 24,
                                  color: muted.withValues(alpha: 0.45),
                                ),
                              ),
                            )
                          : ColoredBox(
                              color: scheme.surfaceContainerHighest,
                              child: Icon(
                                Icons.image_not_supported_outlined,
                                size: 24,
                                color: muted.withValues(alpha: 0.45),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _confidenceLabel(hit),
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: confColor,
                              fontWeight: FontWeight.w800,
                              height: 1.1,
                            ),
                      ),
                      Text(
                        'confidence',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: muted,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ),
                ],
              ),
              if (hit.prices.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var i = 0; i < hit.prices.length && i < 6; i++)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHigh.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: muted.withValues(alpha: 0.22)),
                        ),
                        child: Text(
                          '${hit.prices[i].grade}  \$${hit.prices[i].price.round()}',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: onSurface,
                                fontWeight: FontWeight.w600,
                                fontSize: 11,
                              ),
                        ),
                      ),
                    if (hit.prices.length > 6)
                      Padding(
                        padding: const EdgeInsets.only(left: 2, top: 2),
                        child: Text(
                          '+${hit.prices.length - 6}',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: muted,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (variantOnly) return _buildVariantPick(context);
    final scheme = Theme.of(context).colorScheme;
    final border = selected ? AppTheme.primary : muted.withValues(alpha: 0.28);
    final bg = selected
        ? AppTheme.primary.withValues(alpha: 0.08)
        : scheme.surfaceContainerHighest.withValues(alpha: 0.35);
    final title = (hit.player?.trim().isNotEmpty == true) ? hit.player!.trim() : 'Unknown player';
    final subParts = <String>[
      if (hit.number?.trim().isNotEmpty == true) '#${hit.number!.trim()}',
      if (hit.variant?.trim().isNotEmpty == true) hit.variant!.trim(),
      if (hit.setLabel?.trim().isNotEmpty == true) hit.setLabel!.trim(),
    ];
    final img = hit.image?.trim();
    final confColor = _confidenceColor(hit);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border, width: selected ? 2 : 1),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                size: 22,
                color: selected ? AppTheme.primary : muted.withValues(alpha: 0.55),
              ),
              const SizedBox(width: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 48,
                  height: 64,
                  child: (img != null && img.isNotEmpty)
                      ? CachedNetworkImage(
                          imageUrl: img,
                          fit: BoxFit.cover,
                          fadeInDuration: const Duration(milliseconds: 150),
                          placeholder: (_, _) => ColoredBox(
                            color: scheme.surfaceContainerHighest,
                            child: Center(
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppTheme.primary.withValues(alpha: 0.7),
                                ),
                              ),
                            ),
                          ),
                          errorWidget: (_, _, _) => ColoredBox(
                            color: scheme.surfaceContainerHighest,
                            child: Icon(
                              Icons.broken_image_outlined,
                              size: 28,
                              color: muted.withValues(alpha: 0.45),
                            ),
                          ),
                        )
                      : ColoredBox(
                          color: scheme.surfaceContainerHighest,
                          child: Icon(
                            Icons.image_not_supported_outlined,
                            size: 28,
                            color: muted.withValues(alpha: 0.45),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    if (subParts.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subParts.join(' · '),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: muted,
                              height: 1.25,
                            ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      hit.cardId,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: muted,
                            fontFamily: 'monospace',
                            fontSize: 10,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _confidenceLabel(hit),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: confColor,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                        ),
                  ),
                  Text(
                    'confidence',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: muted,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One [set_parallels] row for merge UI when CardHedge did not surface that parallel name.
class _CatalogParallelOptionTile extends StatelessWidget {
  const _CatalogParallelOptionTile({
    required this.parallel,
    required this.selected,
    required this.onSurface,
    required this.muted,
    required this.onTap,
  });

  final SetParallel parallel;
  final bool selected;
  final Color onSurface;
  final Color muted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final border = selected ? AppTheme.primary : muted.withValues(alpha: 0.28);
    final bg = selected
        ? AppTheme.primary.withValues(alpha: 0.08)
        : scheme.surfaceContainerHighest.withValues(alpha: 0.45);
    final serial = parallel.serialMax;
    final sub = <String>[
      if (serial != null) '/$serial',
      if (parallel.isAuto) 'Auto',
    ];

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border, width: selected ? 2 : 1),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                size: 22,
                color: selected ? AppTheme.primary : muted.withValues(alpha: 0.55),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      parallel.name,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    if (sub.isNotEmpty)
                      Text(
                        sub.join(' · '),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: muted),
                      ),
                  ],
                ),
              ),
              Text(
                'set_parallels',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: muted,
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

/// CardSight set spine only — not tappable; parallel choice is via CardHedge rows below.
class _SetMatchPanel extends StatelessWidget {
  const _SetMatchPanel({
    required this.match,
    this.fallbackPlayerName,
    required this.rawDetectionJson,
    required this.mergeDebugJson,
    required this.tint,
    required this.onSurface,
    required this.muted,
  });

  final ImageScanMatchResult match;
  /// Used when [ScannedCatalogCard.name] is empty (e.g. from CardHedge `player` on image-search hits).
  final String? fallbackPlayerName;
  final String rawDetectionJson;
  final String mergeDebugJson;
  final Color tint;
  final Color onSurface;
  final Color muted;

  static const _mono = TextStyle(
    fontFamily: 'monospace',
    fontSize: 11,
    height: 1.35,
  );

  @override
  Widget build(BuildContext context) {
    final card = match.card;
    final fb = fallbackPlayerName?.trim();
    final title = (card.name?.trim().isNotEmpty == true)
        ? card.name!.trim()
        : (fb != null && fb.isNotEmpty)
            ? fb
            : 'Unknown player';
    final parts = <String>[
      if (card.year != null && card.year!.isNotEmpty) card.year!,
      if (card.releaseName != null && card.releaseName!.isNotEmpty) card.releaseName!,
      if (card.setName != null && card.setName!.isNotEmpty) card.setName!,
    ];
    final subtitle = parts.isEmpty ? 'No release / set text on match' : parts.join(' · ');

    final confidenceLine = match.matchScore != null
        ? '${match.confidenceLabel} · ${match.confidence}'
        : match.confidence;

    final idLines = <String>[
      if (card.releaseId?.trim().isNotEmpty == true) 'releaseId: ${card.releaseId}',
      if (card.setId?.trim().isNotEmpty == true) 'setId: ${card.setId}',
      if (card.cardsightReleaseId?.trim().isNotEmpty == true)
        'cardsightReleaseId: ${card.cardsightReleaseId}',
      if (card.cardsightSetId?.trim().isNotEmpty == true) 'cardsightSetId: ${card.cardsightSetId}',
    ];

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: tint.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Set match',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: muted,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                            ),
                      ),
                      const SizedBox(height: 4),
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
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: muted,
                              height: 1.25,
                            ),
                      ),
                      if (card.number?.trim().isNotEmpty == true) ...[
                        const SizedBox(height: 4),
                        Text(
                          '#${card.number!.trim()}',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: muted,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                      if (idLines.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          idLines.join('\n'),
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: muted,
                                fontFamily: 'monospace',
                                fontSize: 10,
                                height: 1.35,
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
              ],
            ),
          ),
          Divider(height: 1, color: muted.withValues(alpha: 0.2)),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              title: Text(
                'Vision merge (CardHedge ↔ detection)',
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
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: _RawJsonScrollBox(
                      text: mergeDebugJson.trim().isEmpty
                          ? 'No `vision_merge_debug` for this row.\n\n'
                              'Deploy the latest `identify-card` edge function for server-side CardHedge merge + debug payload.\n\n'
                              'Raw detection JSON is in the section below.'
                          : mergeDebugJson,
                      textStyle: _mono.copyWith(color: onSurface),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              title: Text(
                'Raw detection JSON (debug)',
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

class _MatchResultTile extends StatelessWidget {
  const _MatchResultTile({
    required this.match,
    this.isHero = false,
    required this.rawDetectionJson,
    required this.mergeDebugJson,
    required this.tint,
    required this.onSurface,
    required this.muted,
    required this.onOpen,
  });

  final ImageScanMatchResult match;
  final bool isHero;
  final String rawDetectionJson;
  final String mergeDebugJson;
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
                          if (match.cardHedgeCardId != null && match.cardHedgeCardId!.trim().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              'CardHedge · ${match.cardHedgeCardId}',
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: muted,
                                    fontFamily: 'monospace',
                                    fontSize: 10,
                                  ),
                            ),
                          ],
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
                'Vision merge (CardHedge ↔ detection)',
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
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: _RawJsonScrollBox(
                      text: mergeDebugJson.trim().isEmpty
                          ? 'No `vision_merge_debug` for this row.\n\n'
                              'Deploy the latest `identify-card` edge function for server-side CardHedge merge + debug payload.\n\n'
                              'Raw detection JSON is in the section below.'
                          : mergeDebugJson,
                      textStyle: _mono.copyWith(color: onSurface),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              title: Text(
                'Raw detection JSON (debug)',
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
