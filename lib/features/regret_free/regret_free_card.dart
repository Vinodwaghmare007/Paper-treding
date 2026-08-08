import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/order.dart';
import '../../domain/usecases/alternate_outcome_simulator.dart';
import 'regret_free_providers.dart';

/// Shown at most once per completed sell, and only once that sell's real
/// post-sale price path actually exists (see
/// [AlternateOutcomeSimulator.revealDelay]). Purely a comfort feature —
/// "the uncertainty was real, other things could have happened too" — not
/// a nudge to trade more or a "you missed out" callout, so it never blocks
/// anything: no modal, no required action, closable at every step.
class RegretFreeCard extends ConsumerWidget {
  const RegretFreeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingRegretFreeOrderProvider).valueOrNull;
    if (pending == null) return const SizedBox.shrink();
    return _RegretFreeCardBody(sellOrder: pending);
  }
}

class _RegretFreeCardBody extends ConsumerStatefulWidget {
  const _RegretFreeCardBody({required this.sellOrder});
  final Order sellOrder;

  @override
  ConsumerState<_RegretFreeCardBody> createState() => _RegretFreeCardBodyState();
}

class _RegretFreeCardBodyState extends ConsumerState<_RegretFreeCardBody> {
  bool _revealed = false;

  Future<void> _dismiss() async {
    await ref.read(regretFreeProvider.notifier).dismiss(widget.sellOrder);
  }

  @override
  Widget build(BuildContext context) {
    final outcomeState = ref.watch(regretFreeProvider);

    return Card(
      color: const Color(0xFF1E222D),
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_graph, size: 18, color: Color(0xFF6FD3C7)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'What could have happened after your ${widget.sellOrder.coinSymbol} sell?',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Dismiss',
                  color: Colors.white54,
                  onPressed: _dismiss,
                ),
              ],
            ),
            const SizedBox(height: 4),
            outcomeState.when(
              data: (outcome) {
                if (outcome == null) return _prompt();
                return _result(outcome);
              },
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
              error: (_, __) => const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  "Couldn't load this — not enough price history yet.",
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _prompt() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Price could have moved several different ways after you sold. '
          "See a few possibilities — including what actually happened.",
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed: () =>
                ref.read(regretFreeProvider.notifier).generate(widget.sellOrder),
            child: const Text('Show me'),
          ),
        ),
      ],
    );
  }

  Widget _result(RegretFreeOutcome outcome) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 120,
          child: _PathsChart(
            paths: outcome.paths,
            highlightIndex: _revealed ? outcome.actualPathIndex : null,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          children: [
            for (var i = 0; i < outcome.paths.length; i++)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _colorFor(i, _revealed ? outcome.actualPathIndex : null),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _revealed && i == outcome.actualPathIndex
                        ? 'What actually happened'
                        : 'Possibility ${i + 1}',
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (!_revealed)
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: () => setState(() => _revealed = true),
              child: const Text('Reveal what actually happened'),
            ),
          )
        else ...[
          Text(
            outcome.disclaimer,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: _dismiss, child: const Text('Got it')),
          ),
        ],
      ],
    );
  }
}

const _pathPalette = [
  Color(0xFF6FD3C7),
  Color(0xFFEF9A9A),
  Color(0xFFFFD54F),
  Color(0xFF90A4AE),
];

Color _colorFor(int index, int? highlightIndex) {
  if (highlightIndex == null) return _pathPalette[index % _pathPalette.length];
  return index == highlightIndex ? const Color(0xFF26A69A) : Colors.white24;
}

/// Overlays every path on one shared price scale so they're visually
/// comparable — deliberately unlabeled by color meaning until
/// [highlightIndex] is set, so nothing before the reveal hints at which
/// line is real.
class _PathsChart extends StatelessWidget {
  const _PathsChart({required this.paths, required this.highlightIndex});

  final List<List<PricePoint>> paths;
  final int? highlightIndex;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PathsPainter(paths: paths, highlightIndex: highlightIndex),
      size: Size.infinite,
    );
  }
}

class _PathsPainter extends CustomPainter {
  _PathsPainter({required this.paths, required this.highlightIndex});

  final List<List<PricePoint>> paths;
  final int? highlightIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final allPrices = [
      for (final path in paths) for (final point in path) point.price,
    ];
    if (allPrices.isEmpty) return;
    final minPrice = allPrices.reduce((a, b) => a < b ? a : b);
    final maxPrice = allPrices.reduce((a, b) => a > b ? a : b);
    final range = (maxPrice - minPrice).abs() < 1e-9 ? 1.0 : maxPrice - minPrice;

    double yFor(double price) => size.height - ((price - minPrice) / range) * size.height;
    double xFor(int index, int total) => total <= 1 ? 0 : (index / (total - 1)) * size.width;

    for (var i = 0; i < paths.length; i++) {
      final points = paths[i];
      if (points.isEmpty) continue;
      final path = Path()..moveTo(xFor(0, points.length), yFor(points[0].price));
      for (var j = 1; j < points.length; j++) {
        path.lineTo(xFor(j, points.length), yFor(points[j].price));
      }
      final isHighlighted = highlightIndex == null || highlightIndex == i;
      canvas.drawPath(
        path,
        Paint()
          ..color = _colorFor(i, highlightIndex)
          ..style = PaintingStyle.stroke
          ..strokeWidth = isHighlighted ? 2.5 : 1.5
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PathsPainter oldDelegate) =>
      oldDelegate.paths != paths || oldDelegate.highlightIndex != highlightIndex;
}
