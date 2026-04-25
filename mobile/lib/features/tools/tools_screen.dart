import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';

class ToolsScreen extends StatelessWidget {
  const ToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
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

    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFF3F4F6)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
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
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: disabled ? const Color(0xFF9CA3AF) : Colors.black87,
                        ),
                      ),
                      if (comingSoon) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Soon',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF9CA3AF)),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                  ),
                ],
              ),
            ),
            if (!disabled)
              const Icon(Icons.chevron_right, color: Color(0xFFD1D5DB), size: 20),
          ],
        ),
      ),
    );
  }
}
