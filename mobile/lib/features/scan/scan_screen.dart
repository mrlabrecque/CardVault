import 'package:flutter/material.dart';
import '../../core/utils/adaptive_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _controller = MobileScannerController(
    formats: [BarcodeFormat.all],
  );
  bool _scanned = false;

  void _onDetect(BarcodeCapture capture) {
    if (_scanned) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode?.rawValue == null) return;
    setState(() => _scanned = true);
    _controller.stop();
    final value = barcode!.rawValue!;
    showAdaptiveSheet(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Scanned', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(value),
            const SizedBox(height: 16),
            FilledButton(onPressed: () { Navigator.pop(context); Navigator.pop(context); }, child: const Text('Search Comps')),
            TextButton(onPressed: () { setState(() => _scanned = false); Navigator.pop(context); _controller.start(); }, child: const Text('Scan Again')),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Center(
            child: Container(
              width: 260,
              height: 360,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          Positioned(
            bottom: 48,
            left: 0,
            right: 0,
            child: Text('Point at a card or barcode', textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: 0.8))),
          ),
        ],
      ),
    );
  }
}
