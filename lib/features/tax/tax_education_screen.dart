import 'package:flutter/material.dart';

import '../../domain/usecases/illustrative_tax_calculator.dart';

/// Static educational content about India's crypto tax rules (Section
/// 115BBH's flat 30% tax on gains, Section 194S's 1% TDS on trade value)
/// plus a non-personalized illustrative calculator.
///
/// This screen is general information, not personalized filing advice —
/// every section carries that disclaimer, and the calculator is
/// deliberately NOT wired to this app's own paper-trading P&L (see
/// IllustrativeTaxCalculator's doc comment): every trade in this app is
/// simulated, so no real transfer of a Virtual Digital Asset ever
/// happens here and none of this tax law actually applies to anything a
/// user does inside the app itself.
class TaxEducationScreen extends StatefulWidget {
  const TaxEducationScreen({super.key});

  @override
  State<TaxEducationScreen> createState() => _TaxEducationScreenState();
}

class _TaxEducationScreenState extends State<TaxEducationScreen> {
  final _profitController = TextEditingController(text: '10000');
  final _tradeValueController = TextEditingController(text: '100000');
  IllustrativeTaxResult? _result;

  @override
  void initState() {
    super.initState();
    _recalculate();
  }

  @override
  void dispose() {
    _profitController.dispose();
    _tradeValueController.dispose();
    super.dispose();
  }

  void _recalculate() {
    final profit = double.tryParse(_profitController.text) ?? 0;
    final tradeValue = double.tryParse(_tradeValueController.text) ?? 0;
    setState(() {
      _result = IllustrativeTaxCalculator.calculate(
        hypotheticalProfit: profit,
        hypotheticalTradeValue: tradeValue,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E222D),
        title: const Text('Crypto Tax in India'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _DisclaimerBanner(),
          const SizedBox(height: 20),
          const _SectionTitle('The basics'),
          const _BodyText(
            'India taxes gains from Virtual Digital Assets (VDAs, which '
            'includes cryptocurrency) under two separate rules:',
          ),
          const SizedBox(height: 8),
          const _BulletPoint(
            'Flat 30% tax on gains (Section 115BBH) — applied to the net '
            'profit on each transfer, with no deduction allowed other than '
            'the cost of acquiring the asset. There is no lower tax slab '
            'for smaller gains.',
          ),
          const _BulletPoint(
            '1% TDS (Section 194S) — withheld by the exchange/buyer on the '
            'full trade value at the time of the transaction, whether that '
            'trade turns out to be a profit or a loss. This is an upfront '
            'withholding, not the final tax bill.',
          ),
          const SizedBox(height: 20),
          const _SectionTitle('Common misconceptions'),
          const _BulletPoint(
            "\"I don't owe tax unless I withdraw to my bank.\" — Not "
            'true. Tax applies at the time of each taxable transfer (e.g. '
            'selling or swapping), not when you move money to a bank '
            'account.',
          ),
          const _BulletPoint(
            '"I can offset crypto losses against my salary or other '
            'income." — Not true. Losses from VDAs cannot be set off '
            'against any other type of income, and cannot be carried '
            'forward to future years.',
          ),
          const _BulletPoint(
            '"The 1% TDS is my total tax bill." — Not true. TDS is just '
            "withheld upfront; your actual 30% liability on net gains is "
            'computed separately when you file, with the TDS already paid '
            'credited against it.',
          ),
          const _BulletPoint(
            "\"Swapping one coin for another isn't taxable since I never "
            'touched INR." — Not true. A crypto-to-crypto trade is still a '
            'transfer, and triggers both the 30% tax on any gain and the '
            '1% TDS.',
          ),
          const SizedBox(height: 20),
          const _SectionTitle('How paper trading avoids all of this'),
          const _BodyText(
            'Every trade you make in this app is simulated — no real '
            'Virtual Digital Asset ever changes hands, and no real money is '
            'ever at risk. Because nothing here is a real "transfer" under '
            'Indian tax law, none of the above — the 30% tax, the 1% TDS, '
            "the loss set-off restriction — ever applies to your activity "
            'in this app. Your paper P&L is a practice tool, not a taxable '
            'event.',
          ),
          const SizedBox(height: 24),
          const _SectionTitle('Illustrative calculator'),
          const _BodyText(
            'Enter any hypothetical numbers to see how the math works — '
            "this is not connected to your paper-trading portfolio, and "
            "doesn't imply any real tax liability.",
          ),
          const SizedBox(height: 12),
          _CalculatorCard(
            profitController: _profitController,
            tradeValueController: _tradeValueController,
            result: _result,
            onChanged: _recalculate,
          ),
          const SizedBox(height: 24),
          const _DisclaimerBanner(),
        ],
      ),
    );
  }
}

class _DisclaimerBanner extends StatelessWidget {
  const _DisclaimerBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E222D),
        border: Border.all(color: Colors.white24),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text(
        'This is general educational information, not tax advice. Tax '
        'rules can change, and your specific situation may differ. '
        'Consult a qualified tax professional before making any real '
        'financial or filing decisions.',
        style: TextStyle(color: Colors.white70, fontSize: 12),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleLarge),
    );
  }
}

class _BodyText extends StatelessWidget {
  const _BodyText(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: const TextStyle(color: Colors.white70, height: 1.4));
  }
}

class _BulletPoint extends StatelessWidget {
  const _BulletPoint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('•  ', style: TextStyle(color: Color(0xFF6FD3C7))),
          Expanded(
            child: Text(text, style: const TextStyle(color: Colors.white70, height: 1.4)),
          ),
        ],
      ),
    );
  }
}

class _CalculatorCard extends StatelessWidget {
  const _CalculatorCard({
    required this.profitController,
    required this.tradeValueController,
    required this.result,
    required this.onChanged,
  });

  final TextEditingController profitController;
  final TextEditingController tradeValueController;
  final IllustrativeTaxResult? result;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final r = result;
    return Card(
      color: const Color(0xFF1E222D),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: profitController,
              keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
              decoration: const InputDecoration(
                labelText: 'Hypothetical profit (₹)',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => onChanged(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: tradeValueController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Hypothetical total trade value (₹)',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => onChanged(),
            ),
            if (r != null) ...[
              const Divider(height: 32, color: Colors.white24),
              _ResultLine('Tax on gains (30%)', r.taxOnGains),
              _ResultLine('TDS withheld (1% of trade value)', r.tds),
              const Divider(height: 24, color: Colors.white24),
              _ResultLine('Total cost', r.totalCost, emphasize: true),
              _ResultLine('Net after costs', r.netAfterCosts, emphasize: true),
            ],
          ],
        ),
      ),
    );
  }
}

class _ResultLine extends StatelessWidget {
  const _ResultLine(this.label, this.amount, {this.emphasize = false});
  final String label;
  final double amount;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: emphasize ? Colors.white : Colors.white70,
              fontWeight: emphasize ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          Text(
            '₹${amount.toStringAsFixed(2)}',
            style: TextStyle(
              color: emphasize ? const Color(0xFF6FD3C7) : Colors.white70,
              fontWeight: emphasize ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}
