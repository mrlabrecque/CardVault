import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/market_movers_service.dart';
import '../../core/theme/fonts.dart';
import '../../core/widgets/app_bar_shell_trailing_actions.dart';

class AdminMarketMoversScreen extends ConsumerStatefulWidget {
  const AdminMarketMoversScreen({super.key});

  @override
  ConsumerState<AdminMarketMoversScreen> createState() =>
      _AdminMarketMoversScreenState();
}

class _AdminMarketMoversScreenState
    extends ConsumerState<AdminMarketMoversScreen> {
  bool _running = false;
  String? _statusText;
  DateTime? _lastRunAt;

  Future<void> _runRefresh() async {
    setState(() {
      _running = true;
      _statusText = null;
    });

    try {
      final result = await ref.read(marketMoversServiceProvider).runRefreshNow();
      final playersSynced = result['playersSynced'] ?? 0;
      final snapshotsWritten = result['snapshotsWritten'] ?? 0;
      final failed = result['failed'] ?? 0;
      final durationMs = result['duration'] ?? 0;

      setState(() {
        _statusText =
            'Refresh complete. Players synced: $playersSynced. Snapshots: $snapshotsWritten. Failed: $failed. Duration: ${durationMs}ms.';
        _lastRunAt = DateTime.now();
      });

      if (mounted) {
        AdaptiveSnackBar.show(
          context,
          message: 'Market Movers refresh completed.',
          type: AdaptiveSnackBarType.success,
        );
      }
    } catch (e) {
      setState(() {
        _statusText = 'Refresh failed: $e';
      });
      if (mounted) {
        AdaptiveSnackBar.show(
          context,
          message: 'Market Movers refresh failed.',
          type: AdaptiveSnackBarType.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _running = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: Text('Market Movers Admin', style: AppFonts.appBarTitle),
        actions: appBarShellTrailingActions(context),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFED7AA)),
            ),
            child: const Text(
              'Run this utility to refresh top players and write new market mover snapshots immediately.',
              style: TextStyle(
                color: Color(0xFF9A3412),
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 14),
          AdaptiveButton.child(
            onPressed: _running ? null : _runRefresh,
            style: AdaptiveButtonStyle.filled,
            child: _running
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Run Market Movers Refresh Now'),
          ),
          if (_lastRunAt != null) ...[
            const SizedBox(height: 10),
            Text(
              'Last run: ${_lastRunAt!.toLocal()}',
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF6B7280),
              ),
            ),
          ],
          if (_statusText != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Text(
                _statusText!,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF111827),
                  height: 1.35,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
