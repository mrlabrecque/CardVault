import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth/auth_service.dart';
import '../../core/models/wishlist_item.dart';

final wishlistProvider = FutureProvider<List<WishlistItem>>((ref) async {
  final supabase = ref.watch(supabaseProvider);
  final data = await supabase.from('wishlist').select().order('created_at', ascending: false);
  return (data as List).map((r) => WishlistItem.fromJson(r as Map<String, dynamic>)).toList();
});

class WishlistScreen extends ConsumerWidget {
  const WishlistScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final wishlistAsync = ref.watch(wishlistProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Wishlist')),
      body: wishlistAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Text('Your wishlist is empty.\nSearch for a card and add it from Comps.', textAlign: TextAlign.center, style: TextStyle(color: colors.onSurface.withValues(alpha: 0.5))),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(wishlistProvider),
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 100),
              itemCount: items.length,
              itemBuilder: (_, i) => _WishlistTile(item: items[i], onDelete: () async {
                await ref.read(supabaseProvider).from('wishlist').delete().eq('id', items[i].id);
                ref.invalidate(wishlistProvider);
              }),
            ),
          );
        },
      ),
    );
  }
}

class _WishlistTile extends StatelessWidget {
  const _WishlistTile({required this.item, required this.onDelete});
  final WishlistItem item;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isActive = item.alertStatus == 'active';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        title: Text(item.player, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: item.description.isNotEmpty ? Text(item.description, maxLines: 1, overflow: TextOverflow.ellipsis) : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (item.targetPrice != null)
                  Text('Target \$${item.targetPrice!.toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.w600, color: colors.primary)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isActive ? Colors.green.withValues(alpha: 0.15) : colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(isActive ? 'Watching' : 'Inactive', style: TextStyle(fontSize: 11, color: isActive ? Colors.green : colors.onSurface.withValues(alpha: 0.5))),
                ),
              ],
            ),
            IconButton(icon: Icon(Icons.delete_outline, color: colors.error, size: 20), onPressed: onDelete),
          ],
        ),
      ),
    );
  }
}
