import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/nearby_sighting.dart';
import '../models/temporary_id.dart';
import '../theme/app_theme.dart';
import '../widgets/shapes.dart';

/// Shows this phone's backend-issued ID and other Kharcha IDs heard over BLE.
class NearbyScreen extends StatelessWidget {
  const NearbyScreen({
    super.key,
    required this.supported,
    required this.running,
    required this.canAdvertise,
    required this.ownId,
    required this.nearby,
    required this.onStart,
    required this.onStop,
    this.error,
  });

  final bool supported;
  final bool running;
  final bool canAdvertise;
  final TemporaryID? ownId;
  final List<NearbySighting> nearby;
  final String? error;
  final Future<void> Function() onStart;
  final Future<void> Function() onStop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inRange = nearby.where((s) => s.inRange).toList();
    final farther = nearby.where((s) => !s.inRange).toList();

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
          children: [
            Text('Nearby', style: theme.textTheme.headlineMedium),
            const SizedBox(height: 4),
            Text(
              'Find other Kharcha users around you. Each phone broadcasts a rotating ID over Bluetooth — not a name.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: 20),
            _NearbyBanner(
              running: running,
              supported: supported,
              inRange: inRange.length,
            ),
            const SizedBox(height: 16),
            _OwnIdCard(id: ownId),
            if (!canAdvertise && running) ...[
              const SizedBox(height: 12),
              const _Message(
                icon: Icons.campaign_outlined,
                text:
                    'This phone can hear others but cannot broadcast its own ID.',
              ),
            ],
            if (error != null) ...[
              const SizedBox(height: 12),
              _Message(
                key: const Key('nearby-error'),
                icon: Icons.error_outline_rounded,
                text: error!,
              ),
            ],
            const SizedBox(height: 16),
            if (!supported)
              const _Message(
                key: Key('nearby-unsupported'),
                icon: Icons.bluetooth_disabled_rounded,
                text: 'Nearby discovery works on Android phones with Bluetooth.',
              )
            else
              FilledButton.icon(
                key: Key(running ? 'nearby-stop-button' : 'nearby-find-button'),
                onPressed: running ? onStop : onStart,
                icon: Icon(
                  running
                      ? Icons.bluetooth_disabled_rounded
                      : Icons.bluetooth_searching_rounded,
                ),
                label: Text(running ? 'Stop finding' : 'Find nearby'),
              ),
            if (running && nearby.isEmpty) ...[
              const SizedBox(height: 28),
              const _Message(
                key: Key('nearby-empty'),
                icon: Icons.radar_rounded,
                text:
                    'Listening for Kharcha phones. Ask a friend to open Nearby and tap Find nearby too.',
              ),
            ],
            if (inRange.isNotEmpty) ...[
              const SizedBox(height: 28),
              const _SectionTitle('In range'),
              const SizedBox(height: 12),
              for (final sighting in inRange) ...[
                _SightingCard(sighting: sighting),
                const SizedBox(height: 10),
              ],
            ],
            if (farther.isNotEmpty) ...[
              const SizedBox(height: 28),
              const _SectionTitle('Further away'),
              const SizedBox(height: 12),
              for (final sighting in farther) ...[
                _SightingCard(sighting: sighting),
                const SizedBox(height: 10),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _NearbyBanner extends StatelessWidget {
  const _NearbyBanner({
    required this.running,
    required this.supported,
    required this.inRange,
  });

  final bool running;
  final bool supported;
  final int inRange;

  @override
  Widget build(BuildContext context) {
    final title = !supported
        ? 'Android only'
        : running
        ? (inRange == 0
              ? 'Listening…'
              : '$inRange in range')
        : 'Find people nearby';
    final body = !supported
        ? 'Bluetooth discovery is not available on this device.'
        : running
        ? 'Your temporary ID is on the air. Others with Kharcha can hear it.'
        : 'Turn Bluetooth on and both of you tap Find nearby.';

    return Container(
      key: const Key('nearby-banner'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.lavender,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Stack(
        children: [
          const Positioned(
            right: -24,
            top: -24,
            child: FlowerShape(size: 110, color: AppColors.pink, petals: 6),
          ),
          const Positioned(
            right: 50,
            bottom: -16,
            child: TargetShape(
              size: 52,
              color: AppColors.ink,
              background: AppColors.lavender,
              rings: 2,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: const TextStyle(color: AppColors.ink, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OwnIdCard extends StatelessWidget {
  const _OwnIdCard({required this.id});

  final TemporaryID? id;

  @override
  Widget build(BuildContext context) {
    final value = id?.id;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your temporary ID',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    value ?? 'Not loaded yet',
                    key: const Key('nearby-own-id'),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                if (value != null)
                  IconButton(
                    key: const Key('nearby-copy-id'),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: value));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Copied temporary ID')),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy_rounded, size: 18),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SightingCard extends StatelessWidget {
  const _SightingCard({required this.sighting});

  final NearbySighting sighting;

  @override
  Widget build(BuildContext context) {
    final inRange = sighting.inRange;
    return Material(
      key: Key('nearby-device-${sighting.ephemeralId}'),
      color: AppColors.card,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: inRange ? AppColors.lime : AppColors.surfaceHigh,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.bluetooth_rounded,
                color: inRange ? AppColors.ink : AppColors.muted,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sighting.displayName,
                    style: TextStyle(
                      color: AppColors.ink,
                      fontFamily: sighting.userId == null ? 'monospace' : null,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      inRange ? 'In range' : 'Far',
                      sighting.signalLabel,
                      'heard ${sighting.seen}×',
                      if (sighting.sharedGroups.isNotEmpty)
                        sighting.sharedGroups.map((g) => g.name).join(', '),
                    ].join(' · '),
                    style: const TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            Text(
              '${sighting.rssi} dBm',
              style: TextStyle(
                color: inRange ? AppColors.ink : AppColors.muted,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.titleLarge,
  );
}

class _Message extends StatelessWidget {
  const _Message({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: AppColors.outline),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.muted),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
          ),
        ),
      ],
    ),
  );
}
