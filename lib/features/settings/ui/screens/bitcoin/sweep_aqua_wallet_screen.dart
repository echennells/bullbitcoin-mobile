import 'package:bb_mobile/core/fees/domain/fees_entity.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/sweep_aqua_wallet_usecase.dart';
import 'package:bb_mobile/features/wallet/presentation/bloc/wallet_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

class SweepAquaWalletScreen extends StatefulWidget {
  const SweepAquaWalletScreen({super.key, required this.walletId});

  final String walletId;

  @override
  State<SweepAquaWalletScreen> createState() => _SweepAquaWalletScreenState();
}

class _SweepAquaWalletScreenState extends State<SweepAquaWalletScreen> {
  final SweepAquaWalletUsecase _sweepUsecase = GetIt.I<SweepAquaWalletUsecase>();

  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _executeSweep() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Use a reasonable default network fee (1 sat/vB)
      const networkFee = NetworkFee.relative(1.0);

      final result = await _sweepUsecase.execute(
        liquidWalletId: widget.walletId,
        networkFee: networkFee,
      );

      setState(() {
        _isLoading = false;
      });

      if (result.success && mounted) {
        _showSuccessDialog(result);
      } else if (!result.success && mounted) {
        setState(() {
          _errorMessage = result.message;
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  void _showSuccessDialog(SweepResult result) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sweep Successful'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(result.message),
            const SizedBox(height: 16),
            if (result.txId != null) ...[
              const Text('Transaction ID:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                result.txId!,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              context.pop(); // Close dialog
              context.pop(); // Go back to wallet options
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Wallet? wallet = context.select(
      (WalletBloc bloc) =>
          bloc.state.wallets.where((w) => w.id == widget.walletId).firstOrNull,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Sweep from Aqua Wallet')),
      body: SafeArea(
        child: wallet == null
            ? const Center(child: Text('Wallet not found'))
            : Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.sync_alt,
                      size: 64,
                      color: Colors.blue,
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Sweep from Aqua Wallet',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'This will check for funds in your legacy Aqua wallet (BIP49) '
                      'and transfer them to your current Liquid wallet (BIP84).',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Both wallets use the same seed phrase, but different address formats.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                    ),
                    const SizedBox(height: 24),
                    if (_errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red),
                        ),
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    const Spacer(),
                    if (_isLoading)
                      const Center(child: CircularProgressIndicator())
                    else
                      ElevatedButton(
                        onPressed: _executeSweep,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text(
                          'Sweep Funds',
                          style: TextStyle(fontSize: 16),
                        ),
                      ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => context.pop(),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
