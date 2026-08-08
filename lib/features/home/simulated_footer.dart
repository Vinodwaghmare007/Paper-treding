import 'package:flutter/material.dart';

/// Persistent "this is not real money" reminder, shown on every signed-in
/// screen via [HomeShell] (which wraps all tabs in the same [Scaffold], so
/// this one instance covers every screen that could show a dollar figure —
/// see the manual QA checklist for why a single shared placement was
/// chosen over duplicating similar text into each screen individually).
class SimulatedFooter extends StatelessWidget {
  const SimulatedFooter({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFF1E222D),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: const Text(
        'SIMULATED — Educational only, no real money',
        textAlign: TextAlign.center,
        // white70, not the more common white38/54 "secondary text" tone
        // elsewhere in the app — this line is safety-relevant copy, not
        // decorative de-emphasis, and needs to clear WCAG AA contrast
        // (4.5:1) against this dark background, which white38 does not.
        style: TextStyle(color: Colors.white70, fontSize: 10, letterSpacing: 0.3),
      ),
    );
  }
}
