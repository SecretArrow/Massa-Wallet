/// Seed-phrase wallet creation: generate → reveal → verify → derive.
///
/// High-security flow:
///  * the 12 words are shown ONCE, hidden until individually tapped
///    (tap-to-reveal per word + explicit "reveal all");
///  * clipboard copy is deliberately DISABLED — the words must touch
///    paper, not a clipboard that other apps can read;
///  * the user must pass a 3-position word quiz before the wallet is
///    created — proves the paper backup is correct;
///  * the phrase itself is NEVER persisted: only the SLIP-0010-derived
///    ed25519 key goes into the encrypted secure store.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/crypto/bip39.dart';
import '../../core/crypto/bip39_wordlist.dart';
import '../../core/i18n/app_i18n.dart';
import '../../core/services/wallet_provider.dart';
import '../../ui/theme.dart';

/// Create-wallet-via-seed-phrase flow.
class SeedCreateScreen extends StatefulWidget {
  /// Creates the screen.
  const SeedCreateScreen({super.key});

  @override
  State<SeedCreateScreen> createState() => _SeedCreateScreenState();
}

class _SeedCreateScreenState extends State<SeedCreateScreen> {
  late final String _mnemonic;
  late final List<String> _words;
  final Set<int> _revealed = {};
  bool _busy = false;
  bool _step2 = false;

  // Quiz state.
  late final List<_QuizSlot> _quiz;
  final Map<int, String> _answers = {};

  @override
  void initState() {
    super.initState();
    _mnemonic = generateMnemonic(strength: 128);
    _words = _mnemonic.split(' ');
    _quiz = _buildQuiz();
  }

  List<_QuizSlot> _buildQuiz() {
    final rng = Random.secure();
    final positions = (_words.indexed.toList()..shuffle(rng))
        .take(3)
        .map((e) => e.$1)
        .toList();
    return positions.map((pos) {
      final distractors = <String>{};
      while (distractors.length < 5) {
        final candidate = bip39EnglishWordlist[rng.nextInt(2048)];
        if (candidate != _words[pos]) distractors.add(candidate);
      }
      final options = [...distractors, _words[pos]]..shuffle(rng);
      return _QuizSlot(position: pos, options: options);
    }).toList();
  }

  Future<void> _finish() async {
    setState(() => _busy = true);
    try {
      final wallet = context.read<WalletProvider>();
      await wallet.createWalletFromSeedPhrase(_mnemonic);
      if (!mounted) return;
      unawaited(Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${context.t('common.error')}: $e'),
            backgroundColor: const Color(0xFFF85149),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _checkQuiz() {
    final allAnswered = _quiz.every((s) => _answers[s.position] != null);
    if (!allAnswered) return;
    final correct = _quiz.every((s) => _answers[s.position] == _words[s.position]);
    if (correct) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t('seed.verify.done'))),
      );
      _finish();
    } else {
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.t('seed.verify.wrong')),
          backgroundColor: const Color(0xFFF85149),
        ),
      );
      setState(() {
        _answers.clear();
        _quiz
          ..clear()
          ..addAll(_buildQuiz());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(context.t('seed.generate.title'))),
      body: SafeArea(
        // SingleChildScrollView (not a lazy ListView) so every widget is
        // built up-front — the flow is short and tests/automation can
        // always find elements below the fold.
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            if (!_step2) ...[
              _WarningRow(
                icon: Icons.shield_outlined,
                text: context.t('seed.generate.body'),
              ),
              const SizedBox(height: 8),
              _WarningRow(
                icon: Icons.block,
                text: context.t('seed.generate.warn.share'),
              ),
              const SizedBox(height: 8),
              _WarningRow(
                icon: Icons.note_alt_outlined,
                text: context.t('seed.generate.warn.digital'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.screenshot_monitor, size: 16, color: cs.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      context.t('seed.generate.screenshotBlocked'),
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 2.6,
                ),
                itemCount: _words.length,
                itemBuilder: (context, i) {
                  final revealed = _revealed.contains(i);
                  return InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _revealed.add(i));
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: revealed
                            ? cs.surfaceContainerHighest
                            : cs.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: revealed
                              ? PyramidsColors.brand.withValues(alpha: 0.4)
                              : cs.outlineVariant,
                        ),
                      ),
                      child: Center(
                        child: revealed
                            ? RichText(
                                text: TextSpan(
                                  style: DefaultTextStyle.of(context).style,
                                  children: [
                                    TextSpan(
                                      text: '${i + 1}. ',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: PyramidsColors.brand,
                                      ),
                                    ),
                                    TextSpan(
                                      text: _words[i],
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.visibility_off,
                                      size: 14, color: cs.onSurfaceVariant),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${i + 1}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton.icon(
                  onPressed: () => setState(() {
                    if (_revealed.length == _words.length) {
                      _revealed.clear();
                    } else {
                      _revealed.addAll(List.generate(_words.length, (i) => i));
                    }
                  }),
                  icon: Icon(
                    _revealed.length == _words.length
                        ? Icons.visibility_off
                        : Icons.visibility,
                    size: 18,
                  ),
                  label: Text(
                    _revealed.length == _words.length
                        ? context.t('seed.generate.hideAll')
                        : context.t('seed.generate.revealAll'),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Copy deliberately unavailable — show why when users try the
              // standard affordance anyway (long-press on the grid).
              GestureDetector(
                onLongPress: () => ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(context.t('seed.generate.copyBlocked')),
                  ),
                ),
                child: Text(
                  context.t('seed.generate.reveal'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _revealed.length == _words.length && !_busy
                    ? () => setState(() => _step2 = true)
                    : null,
                child: Text(context.t('seed.generate.confirmRead')),
              ),
              const SizedBox(height: 24),
            ] else ...[
              _WarningRow(
                icon: Icons.fact_check_outlined,
                text: context.t('seed.verify.body'),
              ),
              const SizedBox(height: 16),
              for (final slot in _quiz) ...[
                Text(
                  '${context.t('seed.verify.title')} — #${slot.position + 1}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final option in slot.options)
                      ChoiceChip(
                        label: Text(option),
                        selected: _answers[slot.position] == option,
                        onSelected: (sel) => setState(() {
                          if (sel) {
                            _answers[slot.position] = option;
                          } else {
                            _answers.remove(slot.position);
                          }
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _busy ||
                        _quiz.any((s) => _answers[s.position] == null)
                    ? null
                    : _checkQuiz,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(context.t('seed.verify.check')),
              ),
              const SizedBox(height: 24),
            ],
          ],
          ),
        ),
      ),
    );
  }
}

/// Quiz slot: a hidden word position with shuffled candidate options.
class _QuizSlot {
  final int position;
  final List<String> options;

  const _QuizSlot({required this.position, required this.options});
}

/// Icon + body-text warning row.
class _WarningRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _WarningRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PyramidsColors.orange.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: PyramidsColors.orange),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
