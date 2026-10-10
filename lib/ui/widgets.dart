/// Reusable small UI components.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// Rounded gradient balance card.
class BalanceCard extends StatelessWidget {
  /// Balance string to display.
  final String balance;

  /// Currency suffix.
  final String unit;

  /// Whether the balance is hidden (privacy mode).
  final bool hidden;

  /// Candidate balance string (optional).
  final String? candidateBalance;

  /// Creates the card.
  const BalanceCard({
    super.key,
    required this.balance,
    this.unit = 'MAS',
    this.hidden = false,
    this.candidateBalance,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [PyramidsColors.deepBrand, PyramidsColors.brandLight],
        ),
        boxShadow: [
          BoxShadow(
            color: PyramidsColors.brand.withValues(alpha: 0.25),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            hidden ? '••••••' : balance,
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            unit,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          if (candidateBalance != null && !hidden) ...[
            const SizedBox(height: 8),
            Text(
              candidateBalance!,
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Address chip with copy-to-clipboard.
class AddressChip extends StatelessWidget {
  /// Full address.
  final String address;

  /// Whether to truncate in the middle.
  final bool truncate;

  /// Creates the chip.
  const AddressChip({super.key, required this.address, this.truncate = true});

  String get _display {
    if (!truncate || address.length <= 16) return address;
    return '${address.substring(0, 10)}…${address.substring(address.length - 6)}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        Clipboard.setData(ClipboardData(text: address));
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('📋 $address')));
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                _display,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  color: scheme.primary,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.copy, size: 14, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// Big icon action button for the dashboard grid.
class ActionTile extends StatelessWidget {
  /// Icon.
  final IconData icon;

  /// Label.
  final String label;

  /// Tap handler.
  final VoidCallback onTap;

  /// Accent color.
  final Color color;

  /// Creates the tile.
  const ActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = PyramidsColors.brand,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Section header.
class SectionHeader extends StatelessWidget {
  /// Title.
  final String title;

  /// Creates the header.
  const SectionHeader({super.key, required this.title});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 8),
    child: Text(
      title,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        letterSpacing: 0.5,
      ),
    ),
  );
}
