import 'package:ecommerce_int2/app_properties.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Page showing creative, modern list of partner stores / locations
/// that customers can visit to buy now. Inspired by the Notifications
/// page style but focused on actionable store cards.
class BuyNowStoresPage extends StatelessWidget {
  const BuyNowStoresPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final stores = _demoStores;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Buy Now',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: darkGrey,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Choose a nearby shop and get your order today.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.grey[700],
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4),
                itemCount: stores.length,
                itemBuilder: (context, index) {
                  final store = stores[index];
                  return _StoreCard(store: store);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoreCard extends StatelessWidget {
  const _StoreCard({required this.store});

  final _StoreLocation store;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            offset: Offset(0, 4),
            blurRadius: 10,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Store "${store.name}" selected'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: const LinearGradient(
                      colors: [
                        mediumYellow,
                        darkYellow,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: const Icon(
                    Icons.store_mall_directory_outlined,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              store.name,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: darkGrey,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _TagChip(label: store.tag),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.location_on_outlined,
                            size: 16,
                            color: Colors.grey,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              store.address,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.grey[700],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(
                            Icons.schedule_outlined,
                            size: 16,
                            color: Colors.grey,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            store.openingHours,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.grey[700],
                            ),
                          ),
                          const Spacer(),
                          Icon(
                            Icons.directions_walk_outlined,
                            size: 16,
                            color: Colors.grey[600],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            store.distance,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.star_rounded,
                                size: 18,
                                color: Colors.amber,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${store.rating.toStringAsFixed(1)}',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '(${store.reviewCount} reviews)',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                          TextButton(
                            onPressed: () async {
                              final query = Uri.encodeComponent(
                                '${store.name}, ${store.address}',
                              );
                              final uri = Uri.parse(
                                'https://www.google.com/maps/search/?api=1&query=$query',
                              );

                              if (!await launchUrl(
                                uri,
                                mode: LaunchMode.externalApplication,
                              )) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Could not open Google Maps'),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: mediumYellow,
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            child: const Text('View on map'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: transparentYellow,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: darkGrey,
        ),
      ),
    );
  }
}

class _StoreLocation {
  final String name;
  final String address;
  final String openingHours;
  final String distance;
  final double rating;
  final int reviewCount;
  final String tag;

  const _StoreLocation({
    required this.name,
    required this.address,
    required this.openingHours,
    required this.distance,
    required this.rating,
    required this.reviewCount,
    required this.tag,
  });
}

const List<_StoreLocation> _demoStores = [
  _StoreLocation(
    name: 'T-Work Flagship Store',
    address: 'No. 123, Downtown Street, Yangon',
    openingHours: '09:00 AM - 08:00 PM',
    distance: '1.2 km',
    rating: 4.8,
    reviewCount: 210,
    tag: 'Recommended',
  ),
  _StoreLocation(
    name: 'T-Work City Mall',
    address: '3rd Floor, City Mall, Mandalay',
    openingHours: '10:00 AM - 09:00 PM',
    distance: '3.5 km',
    rating: 4.6,
    reviewCount: 145,
    tag: 'Popular',
  ),
  _StoreLocation(
    name: 'T-Work Express Pickup',
    address: 'Corner of Main Road & 5th Street, Yangon',
    openingHours: '08:30 AM - 07:30 PM',
    distance: '0.8 km',
    rating: 4.5,
    reviewCount: 98,
    tag: 'Express',
  ),
];
