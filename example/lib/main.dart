import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:samsung_iap/samsung_iap.dart';

const _lifetimeId = 'online.as.safedrive.lifetime';
const _monthlyId = 'online.as.safedrive.1m';
const _productIds = {_monthlyId, _lifetimeId};

void main() => runApp(const MaterialApp(home: SpikePage()));

/// Restore-spike screen: drives [SamsungIapPlatform] directly (not
/// `InAppPurchase.instance`, which would register Google Play billing).
class SpikePage extends StatefulWidget {
  const SpikePage({super.key});

  @override
  State<SpikePage> createState() => _SpikePageState();
}

class _SpikePageState extends State<SpikePage> {
  final _scroll = ScrollController();
  final _log = <String>[];
  final _products = <ProductDetails>[];
  final _pending = <PurchaseDetails>[];

  late SamsungIapPlatform _platform;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  SamsungIapMode _mode = SamsungIapMode.test;

  @override
  void initState() {
    super.initState();
    _createPlatform();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _createPlatform() {
    _sub?.cancel();
    _platform = SamsungIapPlatform(mode: _mode);
    _sub = _platform.purchaseStream.listen(
      _onPurchases,
      onError: (Object e) => _say('stream error: $e'),
    );
    _say('platform created, mode=${_mode.wire}');
  }

  void _say(String line) {
    if (!mounted) return;
    final t = DateTime.now().toIso8601String().substring(11, 23);
    setState(() => _log.add('$t $line'));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  void _onPurchases(List<PurchaseDetails> list) {
    _say('stream: ${list.length} update(s)');
    for (final p in list) {
      final e = p.error;
      _say(
        '  productID=${p.productID} purchaseID=${p.purchaseID} '
        'status=${p.status.name} date=${p.transactionDate} '
        'pendingComplete=${p.pendingCompletePurchase} '
        'error=${e == null ? null : '${e.code}: ${e.message}'}',
      );
      if (p is SamsungPurchaseDetails) {
        final raw = p.raw;
        // The SDK's own purchase JSON: carries fields the backend cares about
        // (e.g. receipt mode) that the mapped PurchaseDetails drop.
        if (raw != null) _say('  json=${raw.jsonString}');
      }
    }
    setState(() {
      for (final p in list) {
        if (p.pendingCompletePurchase) {
          _pending.removeWhere((q) => q.purchaseID == p.purchaseID);
          _pending.add(p);
        }
      }
    });
  }

  Future<void> _run(String name, Future<Object?> Function() body) async {
    _say('$name ...');
    try {
      final r = await body();
      _say('$name done${r == null ? '' : ': $r'}');
    } catch (e) {
      _say('$name FAILED: $e');
    }
  }

  Future<void> _load() => _run('queryProductDetails', () async {
    final r = await _platform.queryProductDetails(_productIds);
    setState(() {
      _products
        ..clear()
        ..addAll(r.productDetails);
    });
    for (final p in r.productDetails) {
      _say('  ${p.id} | ${p.title} | ${p.price}');
    }
    final e = r.error;
    return 'notFound=${r.notFoundIDs} error=${e == null ? null : '${e.code}: ${e.message}'}';
  });

  // Subscription and item both use buyNonConsumable: the platform consumes
  // only on buyConsumable, and neither product is consumable.
  Future<void> _buy(ProductDetails p) => _run(
    'buy ${p.id}',
    () => _platform.buyNonConsumable(
      purchaseParam: SamsungPurchaseParam(productDetails: p),
    ),
  );

  Future<void> _restore() =>
      _run('restorePurchases', () => _platform.restorePurchases());

  Future<void> _complete(PurchaseDetails p) =>
      _run('completePurchase ${p.productID}', () async {
        await _platform.completePurchase(p);
        setState(() => _pending.remove(p));
        return null;
      });

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _log.join('\n')));
    _say('log copied (${_log.length} lines)');
  }

  void _setMode(SamsungIapMode mode) {
    setState(() {
      _mode = mode;
      _products.clear();
      _pending.clear();
    });
    _createPlatform();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('samsung_iap restore spike')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<SamsungIapMode>(
                segments: const [
                  ButtonSegment(
                    value: SamsungIapMode.production,
                    label: Text('production'),
                  ),
                  ButtonSegment(value: SamsungIapMode.test, label: Text('test')),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => _setMode(s.first),
              ),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton(
                    onPressed: _load,
                    child: const Text('Load products'),
                  ),
                  FilledButton(
                    onPressed: _restore,
                    child: const Text('Restore'),
                  ),
                  OutlinedButton(
                    onPressed: _copy,
                    child: const Text('Copy log'),
                  ),
                ],
              ),
              for (final p in _products)
                ListTile(
                  dense: true,
                  title: Text(p.id),
                  subtitle: Text('${p.title} - ${p.price}'),
                  trailing: FilledButton.tonal(
                    onPressed: () => _buy(p),
                    child: const Text('Buy'),
                  ),
                ),
              for (final p in _pending)
                ListTile(
                  dense: true,
                  title: Text('pending: ${p.productID}'),
                  subtitle: Text('${p.purchaseID} (${p.status.name})'),
                  trailing: FilledButton.tonal(
                    onPressed: () => _complete(p),
                    child: const Text('Complete'),
                  ),
                ),
              const Divider(),
              Expanded(
                child: SingleChildScrollView(
                  controller: _scroll,
                  child: SelectableText(
                    _log.join('\n'),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
