import 'dart:async';
import 'dart:convert';

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/scan_immersive.dart';
import '../../core/services/comps_service.dart';
import '../../core/models/cardhedge_image_search.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/chrome_metrics.dart';
import '../../core/theme/fonts.dart';
import '../../core/utils/platform_utils.dart';
import '../../core/widgets/app_bar_shell_trailing_actions.dart';
import '../../core/widgets/card_fan_loader.dart';
import '../../core/widgets/card_info_section.dart';
import '../../core/widgets/card_thumbnail.dart';
import '../../core/widgets/frosted_chrome_layer.dart';
import '../../core/widgets/glass_nav_bar.dart';
import '../../core/widgets/sliver_frosted_header.dart';
import 'scan_models.dart';
import 'widgets/scan_camera_page.dart';

/// Full-row tap (Cupertino press on iOS, [InkWell] elsewhere) for scan result rows.
Widget _wrapScanResultListTap({
  required VoidCallback onTap,
  required Widget child,
  BorderRadius? borderRadius,
}) {
  final radius = borderRadius ?? BorderRadius.circular(14);
  if (isIOS) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      pressedOpacity: 0.82,
      borderRadius: radius,
      onPressed: onTap,
      child: child,
    );
  }
  return Material(
    color: Colors.transparent,
    child: InkWell(onTap: onTap, borderRadius: radius, child: child),
  );
}

class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

enum _ScanState { sportPicker, camera, processing, result, error }

class _ScanScreenState extends ConsumerState<ScanScreen> {
  /// Height **below the toolbar** for the frosted subtitle row (see [SliverFrostedHeader]
  /// `height: navOffset + this`). Smaller = shorter strip; too small clips [maxLines].
  static const double _scanResultsSubtitleChromeExtent = 36;

  final ImagePicker _imagePicker = ImagePicker();
  final _supabase = Supabase.instance.client;
  static const _scanFunctionName = 'identify-card';
  static const _invokeTimeout = Duration(seconds: 75);

  _ScanState _state = _ScanState.sportPicker;
  String _selectedSport = '';
  List<ImageScanMatchResult> _detections = const [];

  /// Full CardHedge image-search rows (see `cardhedge_candidates` on edge).
  List<CardHedgeImageSearchHit> _mergeChCandidates = const [];

  /// Selected `card_id` for [_mergeChCandidates] (row highlight only).
  String? _selectedMergeChCardId;
  String? _errorMessage;

  void _update(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
    final hide = _state == _ScanState.camera || _state == _ScanState.processing;
    if (scanImmersiveMode.value != hide) {
      scanImmersiveMode.value = hide;
    }
  }

  double _bodyBottomInsetOverTabBar(BuildContext context) {
    return MediaQuery.paddingOf(context).bottom +
        ChromeMetrics.shellTabBarReserveHeight;
  }

  /// Bottom inset for the Scan results CTA (tighter than [_bodyBottomInsetOverTabBar]).
  double _scanAgainBottomPadding(BuildContext context) {
    return MediaQuery.paddingOf(context).bottom + 60;
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
          body: <String, dynamic>{
            'imageBase64': base64,
            'sport': _selectedSport,
            'enrichChCandidates': true,
            // CardHedge image-search only — no CardSight vision call from this screen.
            'identifyStrategy': 'cardhedge',
          },
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
    return _confidenceRank(
      b.confidence,
    ).compareTo(_confidenceRank(a.confidence));
  }

  Future<void> _runIdentifyFromBytes(Uint8List raw) async {
    try {
      final jpeg = _encodeScanJpeg(raw) ?? Uint8List.fromList(raw);
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
        final msg =
            data['error'] ??
            data['message'] ??
            data['detail'] ??
            'Identification was not successful.';
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

      var matches = <ImageScanMatchResult>[];
      for (final e in detectionsRaw) {
        final map = Map<String, dynamic>.from(e as Map);
        matches.add(ImageScanMatchResult.fromJson(map));
      }
      matches.sort((a, b) => _detectionCompare(a, b));

      var chCandidates = const <CardHedgeImageSearchHit>[];
      final rawCh =
          data['cardhedge_candidates'] ?? data['cardhedge_hits_sample'];
      if (rawCh is List) {
        final hits = <CardHedgeImageSearchHit>[];
        for (final e in rawCh) {
          if (e is! Map) continue;
          final map = Map<String, dynamic>.from(e);
          final h = CardHedgeImageSearchHit.fromJson(map);
          if (h.cardId.isEmpty) continue;
          hits.add(h);
        }
        chCandidates = hits;
      }

      if (matches.isNotEmpty) {
        final top = matches.first;
        final topId = top.card.id?.trim();
        if (topId != null && topId.isNotEmpty) {
          final url = await ref
              .read(compsServiceProvider)
              .fetchCardImage(topId);
          if (!mounted) return;
          if (url != null && url.trim().isNotEmpty) {
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
          _mergeChCandidates = chCandidates;
          _selectedMergeChCardId = null;
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
      _mergeChCandidates = const [];
      _selectedMergeChCardId = null;
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
      _mergeChCandidates = const [];
      _selectedMergeChCardId = null;
      _errorMessage = null;
      _state = kIsWeb ? _ScanState.sportPicker : _ScanState.camera;
    });
    if (kIsWeb) {
      unawaited(_captureWithImagePicker());
    }
  }

  ({String name, Color color}) _sportDisplayMeta() {
    for (final s in _sports) {
      if (s.$2 == _selectedSport) {
        return (name: s.$1, color: s.$4);
      }
    }
    return (name: 'Scan', color: AppTheme.primary);
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
        return Scaffold(body: _buildProcessingOrError());
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
        useBlurBackground: true,
        blurSigma: 14,
        surfaceTintAlpha: 0.22,
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
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final navOffset = MediaQuery.paddingOf(context).top + kToolbarHeight;

    final subtitle = Text(
      _mergeChCandidates.isNotEmpty
          ? 'Listings ranked by match percentage. Tap a row to highlight it.'
          : '${_detections.length} possible ${_detections.length == 1 ? 'match' : 'matches'}.',
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: muted),
    );

    final headerSlivers = <Widget>[
      SliverFrostedHeader(
        height: navOffset + _scanResultsSubtitleChromeExtent,
        child: FrostedChromeLayer(
          child: Padding(
            padding: EdgeInsets.only(
              top: navOffset,
              left: 20,
              right: 20,
              bottom: 2,
            ),
            child: Align(
              alignment: Alignment.topLeft,
              child: subtitle,
            ),
          ),
        ),
      ),
      const SliverChromeGap(height: ChromeMetrics.contentTopGapTight),
    ];

    Widget scrollBody() {
      if (_mergeChCandidates.isNotEmpty) {
        return CustomScrollView(
          slivers: [
            ...headerSlivers,
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final hit = _mergeChCandidates[index];
                    final gapBottom =
                        index < _mergeChCandidates.length - 1 ? 10.0 : 0.0;
                    return Padding(
                      padding: EdgeInsets.only(bottom: gapBottom),
                      child: _ChCandidateTile(
                        hit: hit,
                        scanSport: _selectedSport,
                        selected: _selectedMergeChCardId == hit.cardId,
                        onSurface: onSurface,
                        muted: muted,
                        onTap: () {
                          setState(() => _selectedMergeChCardId = hit.cardId);
                        },
                      ),
                    );
                  },
                  childCount: _mergeChCandidates.length,
                ),
              ),
            ),
          ],
        );
      }

      final n = _detections.length;
      if (n == 0) {
        return CustomScrollView(
          slivers: [
            ...headerSlivers,
            const SliverFillRemaining(
              hasScrollBody: false,
              child: SizedBox.shrink(),
            ),
          ],
        );
      }

      final separatedCount = n <= 1 ? n : 2 * n - 1;
      return CustomScrollView(
        slivers: [
          ...headerSlivers,
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  if (n == 1) {
                    return _MatchResultTile(
                      match: _detections[0],
                      isHero: true,
                      scanSport: _selectedSport,
                      tint: _confidenceTint(_detections[0]),
                      onSurface: onSurface,
                      muted: muted,
                      onOpen: () {},
                    );
                  }
                  if (index.isOdd) {
                    return const SizedBox(height: 10);
                  }
                  final i = index ~/ 2;
                  final m = _detections[i];
                  return _MatchResultTile(
                    match: m,
                    isHero: i == 0,
                    scanSport: _selectedSport,
                    tint: _confidenceTint(m),
                    onSurface: onSurface,
                    muted: muted,
                    onOpen: () {},
                  );
                },
                childCount: separatedCount,
              ),
            ),
          ),
        ],
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: buildGlassNavBar(
        context,
        useBlurBackground: false,
        title: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Scan Results',
            style: AppFonts.appBarTitle.copyWith(color: onSurface),
          ),
        ),
        actions: appBarShellTrailingActions(context),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: scrollBody()),
          Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              16,
              20,
              _scanAgainBottomPadding(context),
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
    );
  }
}

/// One CardHedge image-search row (scan results).
class _ChCandidateTile extends StatelessWidget {
  const _ChCandidateTile({
    required this.hit,
    required this.scanSport,
    required this.selected,
    required this.onSurface,
    required this.muted,
    required this.onTap,
  });

  final CardHedgeImageSearchHit hit;
  final String scanSport;
  final bool selected;
  final Color onSurface;
  final Color muted;
  final VoidCallback onTap;

  /// CardHedge image similarity as a whole-number percent (no decimals / raw label).
  static String _confidenceLabel(CardHedgeImageSearchHit h) {
    double? pct;
    final s = h.similarityScore;
    if (s > 0) {
      pct = s <= 1 ? s * 100 : s;
    } else {
      final raw = h.similarityLabel?.trim();
      if (raw != null && raw.isNotEmpty) {
        final n = double.tryParse(raw.replaceAll('%', '').trim());
        if (n != null) {
          pct = n <= 1 ? n * 100 : n;
        } else {
          return raw;
        }
      }
    }
    if (pct == null) return '—';
    final r = pct.round().clamp(0, 100);
    return '$r%';
  }

  static Color _confidenceColor(CardHedgeImageSearchHit h) {
    final s = h.similarityScore;
    if (s >= 0.72) return const Color(0xFF059669);
    if (s >= 0.48) return const Color(0xFFD97706);
    if (s > 0) return const Color(0xFFDC2626);
    return const Color(0xFF64748B);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final border = selected ? AppTheme.primary : muted.withValues(alpha: 0.28);
    final bg = selected
        ? AppTheme.primary.withValues(alpha: 0.08)
        : scheme.surfaceContainerHighest.withValues(alpha: 0.35);
    final confColor = _confidenceColor(hit);
    final sportKey = scanSport.trim().isEmpty ? 'Unknown' : scanSport;

    final inner = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CardThumbnail(
                imageUrl: hit.image,
                sport: sportKey,
                width: 56,
                height: 78,
                borderRadius: 8,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 2, 0, 0),
                  child: CardInfoSection.fromCardHedgeHit(hit, sport: sportKey),
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
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
                    'MATCH',
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
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 0; i < hit.prices.length && i < 8; i++)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
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
                if (hit.prices.length > 8)
                  Padding(
                    padding: const EdgeInsets.only(left: 2, top: 2),
                    child: Text(
                      '+${hit.prices.length - 8}',
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
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border, width: selected ? 2 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: _wrapScanResultListTap(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: inner,
      ),
    );
  }
}

class _MatchResultTile extends StatelessWidget {
  const _MatchResultTile({
    required this.match,
    this.isHero = false,
    required this.scanSport,
    required this.tint,
    required this.onSurface,
    required this.muted,
    required this.onOpen,
  });

  final ImageScanMatchResult match;
  final bool isHero;
  final String scanSport;
  final Color tint;
  final Color onSurface;
  final Color muted;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final card = match.card;
    final player = (card.name?.trim().isNotEmpty == true)
        ? card.name!.trim()
        : 'Partial match';
    final year = int.tryParse(card.year ?? '');
    final releaseLine = (card.releaseName?.trim().isNotEmpty == true)
        ? card.releaseName!.trim()
        : card.manufacturer?.trim();
    final setLine = card.setName?.trim();
    final parallelName =
        (match.cardHedgeVariant != null &&
            match.cardHedgeVariant!.trim().isNotEmpty)
        ? match.cardHedgeVariant!.trim()
        : card.parallel?.name;
    final serialMax = card.parallel?.numberedTo;
    final sportKey = scanSport.trim().isEmpty ? 'Unknown' : scanSport;
    final graded = match.grading != null;
    final gradeLine = match.grading?.slabSummary;

    final confidenceLine = match.matchScore != null
        ? '${match.confidenceLabel} · ${match.confidence}'
        : match.confidence;

    final tapRadius = isHero
        ? const BorderRadius.only(
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(16),
          )
        : BorderRadius.circular(16);

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isHero
              ? tint.withValues(alpha: 0.55)
              : tint.withValues(alpha: 0.35),
          width: isHero ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isHero) _ScanHeroImage(match: match),
          _wrapScanResultListTap(
            onTap: onOpen,
            borderRadius: tapRadius,
            child: Padding(
              padding: EdgeInsets.fromLTRB(14, isHero ? 12 : 14, 14, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isHero) ...[
                    CardThumbnail(
                      imageUrl: card.imageUrl,
                      sport: sportKey,
                      width: 56,
                      height: 78,
                      borderRadius: 8,
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CardInfoSection(
                          player: player,
                          cardNumber: card.number?.trim().isNotEmpty == true
                              ? card.number!.trim()
                              : null,
                          year: year,
                          releaseName: releaseLine,
                          setName:
                              (setLine != null &&
                                  setLine.isNotEmpty &&
                                  setLine != releaseLine)
                              ? setLine
                              : null,
                          parallelName: parallelName,
                          serialMax: serialMax,
                          sport: sportKey,
                          isGraded: graded,
                          gradeLabel: gradeLine,
                        ),
                        if (match.cardHedgeCardId != null &&
                            match.cardHedgeCardId!.trim().isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            'CardHedge · ${match.cardHedgeCardId}',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: muted,
                                  fontFamily: 'monospace',
                                  fontSize: 10,
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: tint.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: tint.withValues(alpha: 0.65),
                          ),
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
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_maybeFetch()),
    );
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
