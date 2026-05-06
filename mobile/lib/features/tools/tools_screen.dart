import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/fonts.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/adaptive_list_card.dart';
import '../../core/widgets/app_bar_shell_trailing_actions.dart';

class ToolsScreen extends StatelessWidget {
  const ToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Tools',
            style: AppFonts.appBarTitle,
          ),
        ),
        actions: appBarShellTrailingActions(context),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        children: [
          _ToolCard(
            icon: Icons.add_a_photo_outlined,
            title: 'Scan a Card',
            subtitle: 'Use your camera to identify and add cards',
            onTap: () => context.push('/scan'),
          ),
          const SizedBox(height: 12),
          _ToolCard(
            icon: Icons.list_alt,
            title: 'Bulk Add',
            subtitle: 'Add multiple cards from the same release at once',
            onTap: () => context.push('/bulk-add'),
          ),
          const SizedBox(height: 12),
          _ToolCard(
            icon: Icons.search,
            title: 'Comps',
            subtitle: 'Search eBay sold listings for market value',
            onTap: () => context.push('/comps'),
          ),
          const SizedBox(height: 12),
          _ToolCard(
            icon: Icons.layers_outlined,
            title: 'Lot Builder',
            subtitle: 'Group cards into lots for bulk eBay listing',
            onTap: () => context.push('/lot-builder'),
          ),
          const SizedBox(height: 12),
          _ToolCard(
            icon: Icons.trending_up,
            title: 'Market Movers',
            subtitle: 'Top trending players with biggest price swings',
            onTap: () => context.push('/market-movers'),
          ),
          const SizedBox(height: 12),
          _ToolCard(
            icon: Icons.grade_outlined,
            title: 'Grade Recommendations',
            subtitle: 'Find raw cards worth submitting to PSA or BGS',
            onTap: () => context.push('/grading'),
          ),
          const SizedBox(height: 12),
          _ToolCard(
            icon: Icons.map_outlined,
            title: 'Collection Heat Map',
            subtitle: 'Visual breakdown of your collection by sport, year, and player',
            comingSoon: true,
          ),
          const SizedBox(height: 12),
          _ToolCard(
            icon: Icons.upload_file_outlined,
            title: 'Collection Importer',
            subtitle: 'Import cards from a CSV or spreadsheet',
            comingSoon: true,
          ),
        ],
      ),
    );
  }
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.comingSoon = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool comingSoon;

  @override
  Widget build(BuildContext context) {
    final disabled = comingSoon || onTap == null;
    final colors = Theme.of(context).colorScheme;

    return AdaptiveListCard(
      margin: EdgeInsets.zero,
      child: AdaptiveListTile(
        enabled: !disabled,
        hideBottomDivider: true,
        onTap: disabled ? null : onTap,
        padding: const EdgeInsets.all(16),
        backgroundColor: colors.surface,
        leading: Container(
          width: 44,
          height: 44,
        decoration: BoxDecoration(
          color: disabled
              ? const Color(0xFFF3F4F6)
              : AppTheme.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
          child: Icon(
            icon,
            size: 22,
            color: disabled ? const Color(0xFFD1D5DB) : AppTheme.primary,
          ),
        ),
        title: Row(
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: disabled ? colors.onSurface.withValues(alpha: 0.38) : colors.onSurface,
              ),
            ),
            if (comingSoon) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Soon',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurface.withValues(alpha: 0.45),
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(fontSize: 12, color: colors.onSurface.withValues(alpha: 0.55)),
        ),
        trailing: disabled
            ? null
            : Icon(Icons.chevron_right, color: colors.outline, size: 20),
      ),
    );
  }
}
