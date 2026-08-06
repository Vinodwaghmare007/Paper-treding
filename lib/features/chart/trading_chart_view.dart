import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../data/models/kline_tick.dart';
import '../../data/sources/binance_rest_service.dart';

/// Hosts the TradingView Lightweight Charts instance in a WebView and keeps
/// it fed with data:
///
/// 1. Loads `assets/charts/tradingview.html`.
/// 2. Waits for the page's `ready` signal on the `ChartBridge`
///    JavascriptChannel (JS -> Dart).
/// 3. Seeds the chart with the last 500 candles from the REST API
///    (Dart -> JS via `window.seedCandles`).
/// 4. Forwards live WebSocket ticks into `window.updateCandle`, so the
///    forming candle animates and closed candles are committed.
class TradingChartView extends StatefulWidget {
  const TradingChartView({
    super.key,
    required this.restService,
    required this.ticks,
    this.symbol = 'BTCUSDT',
    this.interval = '1m',
    this.seedLimit = 500,
  });

  final BinanceRestService restService;
  final Stream<KlineTick> ticks;
  final String symbol;
  final String interval;
  final int seedLimit;

  @override
  State<TradingChartView> createState() => _TradingChartViewState();
}

enum _ChartStatus { loading, ready, error }

class _TradingChartViewState extends State<TradingChartView> {
  late final WebViewController _controller;
  StreamSubscription<KlineTick>? _tickSubscription;
  _ChartStatus _status = _ChartStatus.loading;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF131722))
      ..addJavaScriptChannel('ChartBridge', onMessageReceived: _onBridgeMessage)
      ..setNavigationDelegate(
        NavigationDelegate(
          onWebResourceError: (error) {
            _fail('WebView resource error: ${error.description}');
          },
          // The chart page is self-contained; block any navigation away.
          onNavigationRequest: (_) => NavigationDecision.prevent,
        ),
      );
    _loadPage();
  }

  Future<void> _loadPage() async {
    try {
      await _controller.loadFlutterAsset('assets/charts/tradingview.html');
    } catch (e) {
      _fail('Failed to load chart page: $e');
    }
  }

  void _onBridgeMessage(JavaScriptMessage message) {
    Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(message.message) as Map<String, dynamic>;
    } catch (_) {
      debugPrint('[Chart] unparseable bridge message: ${message.message}');
      return;
    }
    switch (decoded['type']) {
      case 'ready':
        debugPrint('[Chart] JS chart ready, seeding…');
        _seedChart();
      case 'seeded':
        debugPrint('[Chart] seeded ${decoded['payload']} candles');
      case 'error':
        _fail('Chart JS error: ${decoded['payload']}');
      default:
        debugPrint('[Chart] bridge message: ${message.message}');
    }
  }

  Future<void> _seedChart() async {
    try {
      final candles = await widget.restService.fetchKlines(
        symbol: widget.symbol,
        interval: widget.interval,
        limit: widget.seedLimit,
      );
      if (!mounted) return;
      final json = jsonEncode(
        [for (final c in candles) c.toChartPoint()],
      );
      await _controller.runJavaScript('window.seedCandles($json);');
      _subscribeToTicks();
      if (mounted) setState(() => _status = _ChartStatus.ready);
    } on BinanceRestException catch (e) {
      _fail('Could not load history: ${e.message}');
    } catch (e) {
      _fail('Could not load history: $e');
    }
  }

  /// Only subscribe after the seed is applied, so live bars can never land
  /// under the historical data's last timestamp.
  void _subscribeToTicks() {
    _tickSubscription?.cancel();
    _tickSubscription = widget.ticks.listen((tick) {
      _controller
          .runJavaScript('window.updateCandle(${tick.candle.toChartJson()});')
          .catchError((Object e) {
        debugPrint('[Chart] updateCandle failed: $e');
      });
    });
  }

  void _fail(String message) {
    debugPrint('[Chart] $message');
    if (!mounted) return;
    setState(() {
      _status = _ChartStatus.error;
      _errorMessage = message;
    });
  }

  void _retry() {
    setState(() {
      _status = _ChartStatus.loading;
      _errorMessage = '';
    });
    _tickSubscription?.cancel();
    _loadPage();
  }

  @override
  void dispose() {
    _tickSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        WebViewWidget(controller: _controller),
        if (_status == _ChartStatus.loading)
          const ColoredBox(
            color: Color(0xFF131722),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (_status == _ChartStatus.error)
          ColoredBox(
            color: const Color(0xFF131722),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: Colors.redAccent, size: 40),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      _errorMessage,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _retry, child: const Text('Retry')),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
