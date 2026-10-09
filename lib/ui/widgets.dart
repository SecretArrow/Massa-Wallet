/// Reusable small UI components.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
          colors: [Color(0xFF0B6E6E), Color(0xFF18C8C8)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF18C8C8).withValues(alpha: 0.25),
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
              color: const Color(0xFF062A2A),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            unit,
            style: TextStyle(
              color: const Color(0xFF062A2A).withValues(alpha: 0.7),
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
                color: const Color(0xFF062A2A).withValues(alpha: 0.6),
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
          color: const Color(0xFF21262D),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                _display,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  color: Color(0xFF18C8C8),
                ),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.copy, size: 14, color: Color(0xFF8B949E)),
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
    this.color = const Color(0xFF18C8C8),
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF1C2330),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF21262D)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Color(0xFF8B949E)),
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
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Color(0xFF8B949E),
        letterSpacing: 0.5,
      ),
    ),
  );
}
