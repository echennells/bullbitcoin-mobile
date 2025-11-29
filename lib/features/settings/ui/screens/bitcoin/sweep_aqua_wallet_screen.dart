import 'package:bb_mobile/core/fees/domain/fees_entity.dart';
import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/sweep_aqua_wallet_usecase.dart';
import 'package:bb_mobile/core/widgets/buttons/button.dart';
import 'package:bb_mobile/core/widgets/inputs/copy_input.dart';
import 'package:bb_mobile/core/widgets/loading/fading_linear_progress.dart';
import 'package:bb_mobile/core/widgets/navbar/top_bar.dart';
import 'package:bb_mobile/core/widgets/text/text.dart';
import 'package:bb_mobile/features/transactions/ui/transactions_router.dart';
import 'package:bb_mobile/features/wallet/presentation/bloc/wallet_bloc.dart';
import 'package:bb_mobile/features/wallet/ui/wallet_router.dart';
import 'package:bb_mobile/generated/flutter_gen/assets.gen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:get_it/get_it.dart';
import 'package:gif/gif.dart';
import 'package:go_router/go_router.dart';

enum SweepStep {
  initial,
  checking,
  confirm,
  sweeping,
  success,
}

class SweepAquaWalletScreen extends StatefulWidget {
  const SweepAquaWalletScreen({super.key, required this.walletId});

  final String walletId;

  @override
  State<SweepAquaWalletScreen> createState() => _SweepAquaWalletScreenState();
}

class _SweepAquaWalletScreenState extends State<SweepAquaWalletScreen> {
  final SweepAquaWalletUsecase _sweepUsecase = GetIt.I<SweepAquaWalletUsecase>();

  SweepStep _step = SweepStep.initial;
  String? _errorMessage;
  SweepResult? _result;
  BigInt? _detectedBalance;

  Future<void> _checkForFunds() async {
    setState(() {
      _step = SweepStep.checking;
      _errorMessage = null;
    });

    try {
      // Run the sweep usecase in check-only mode to detect balance
      const networkFee = NetworkFee.relative(0.1);

      final result = await _sweepUsecase.execute(
        liquidWalletId: widget.walletId,
        networkFee: networkFee,
        checkOnly: true,
      );

      setState(() {
        if (result.success && result.amountSwept != null) {
          // Funds were found - show confirmation screen
          _detectedBalance = result.amountSwept;
          _step = SweepStep.confirm;
        } else {
          // No funds found
          _step = SweepStep.initial;
          _errorMessage = result.message;
        }
      });
    } catch (e) {
      setState(() {
        _step = SweepStep.initial;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _executeSweep() async {
    setState(() {
      _step = SweepStep.sweeping;
      _errorMessage = null;
    });

    try {
      // Use standard Liquid network fee (0.1 sat/vB)
      const networkFee = NetworkFee.relative(0.1);

      final result = await _sweepUsecase.execute(
        liquidWalletId: widget.walletId,
        networkFee: networkFee,
      );

      setState(() {
        _result = result;
        if (result.success) {
          _step = SweepStep.success;
        } else {
          _step = SweepStep.initial;
          _errorMessage = result.message;
        }
      });
    } catch (e) {
      setState(() {
        _step = SweepStep.initial;
        _errorMessage = e.toString();
      });
    }
  }

  void _goBack() {
    if (_step == SweepStep.confirm) {
      setState(() => _step = SweepStep.initial);
    } else {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_step) {
      case SweepStep.initial:
      case SweepStep.checking:
        return _InitialScreen(
          walletId: widget.walletId,
          isChecking: _step == SweepStep.checking,
          errorMessage: _errorMessage,
          onSweep: _checkForFunds,
          onBack: () => context.pop(),
        );
      case SweepStep.confirm:
        return _ConfirmScreen(
          walletId: widget.walletId,
          detectedBalance: _detectedBalance!,
          onConfirm: _executeSweep,
          onBack: _goBack,
        );
      case SweepStep.sweeping:
        return _SweepingScreen(onBack: _goBack);
      case SweepStep.success:
        return _SuccessScreen(
          walletId: widget.walletId,
          result: _result!,
        );
    }
  }
}

class _InitialScreen extends StatelessWidget {
  const _InitialScreen({
    required this.walletId,
    required this.isChecking,
    required this.errorMessage,
    required this.onSweep,
    required this.onBack,
  });

  final String walletId;
  final bool isChecking;
  final String? errorMessage;
  final VoidCallback onSweep;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final Wallet? wallet = context.select(
      (WalletBloc bloc) =>
          bloc.state.wallets.where((w) => w.id == walletId).firstOrNull,
    );

    return Scaffold(
      appBar: AppBar(
        forceMaterialTransparency: true,
        automaticallyImplyLeading: false,
        flexibleSpace: TopBar(
          title: 'Sweep from Aqua Wallet',
          onBack: onBack,
        ),
      ),
      body: Column(
        children: [
          FadingLinearProgress(
            height: 3,
            trigger: isChecking,
            backgroundColor: context.colour.onPrimary,
            foregroundColor: context.colour.primary,
          ),
          Expanded(
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
                        if (errorMessage != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.red),
                            ),
                            child: Text(
                              errorMessage!,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        const Spacer(),
                        if (isChecking)
                          const Center(child: CircularProgressIndicator())
                        else
                          BBButton.big(
                            label: 'Check for Funds',
                            onPressed: onSweep,
                            bgColor: context.colour.primary,
                            textColor: context.colour.onPrimary,
                          ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: onBack,
                          child: const Text('Cancel'),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ConfirmScreen extends StatelessWidget {
  const _ConfirmScreen({
    required this.walletId,
    required this.detectedBalance,
    required this.onConfirm,
    required this.onBack,
  });

  final String walletId;
  final BigInt detectedBalance;
  final VoidCallback onConfirm;
  final VoidCallback onBack;

  Widget _divider(BuildContext context) {
    return Container(height: 1, color: context.colour.secondaryFixedDim);
  }

  @override
  Widget build(BuildContext context) {
    final Wallet? wallet = context.select(
      (WalletBloc bloc) =>
          bloc.state.wallets.where((w) => w.id == walletId).firstOrNull,
    );

    return Scaffold(
      appBar: AppBar(
        forceMaterialTransparency: true,
        automaticallyImplyLeading: false,
        flexibleSpace: TopBar(
          title: 'Sweep from Aqua Wallet',
          onBack: onBack,
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 24),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Top icon area
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          alignment: Alignment.center,
                          height: 72,
                          width: 72,
                          decoration: BoxDecoration(
                            color: context.colour.secondaryFixedDim,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.sync_alt,
                            size: 32,
                            color: Colors.blue,
                          ),
                        ),
                        const Gap(16),
                        BBText(
                          'Confirm Sweep',
                          style: context.font.displaySmall,
                          maxLines: 2,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                    const Gap(40),
                    // Info section
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _InfoRow(
                            title: 'From',
                            details: BBText(
                              'Aqua Wallet (BIP49)',
                              style: context.font.bodyLarge,
                              textAlign: TextAlign.end,
                            ),
                          ),
                          _divider(context),
                          _InfoRow(
                            title: 'To',
                            details: BBText(
                              wallet?.displayLabel ?? '',
                              style: context.font.bodyLarge,
                              textAlign: TextAlign.end,
                            ),
                          ),
                          _divider(context),
                          _InfoRow(
                            title: 'Amount',
                            details: BBText(
                              '$detectedBalance sats',
                              style: context.font.bodyLarge,
                              textAlign: TextAlign.end,
                            ),
                          ),
                          _divider(context),
                          _InfoRow(
                            title: 'Network Fee',
                            details: BBText(
                              '0.1 sat/vB (estimated)',
                              style: context.font.bodyLarge,
                              textAlign: TextAlign.end,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Gap(40),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: BBButton.big(
                        label: 'Confirm Sweep',
                        onPressed: onConfirm,
                        bgColor: context.colour.primary,
                        textColor: context.colour.onPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.title, required this.details});

  final String title;
  final Widget details;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          BBText(
            title,
            style: context.font.bodySmall,
            color: context.colour.surfaceContainer,
          ),
          const Gap(24),
          Expanded(child: details),
        ],
      ),
    );
  }
}

class _SweepingScreen extends StatelessWidget {
  const _SweepingScreen({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        forceMaterialTransparency: true,
        automaticallyImplyLeading: false,
        flexibleSpace: const TopBar(title: 'Sweep'),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Align(
          child: Column(
            children: [
              const Gap(192),
              Gif(
                autostart: Autostart.loop,
                height: 123,
                image: AssetImage(Assets.animations.cubesLoading.path),
              ),
              const Gap(8),
              BBText('Sweeping', style: context.font.headlineLarge),
              const Gap(8),
              BBText(
                'Broadcasting the transaction.',
                style: context.font.bodyMedium,
                maxLines: 4,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SuccessScreen extends StatelessWidget {
  const _SuccessScreen({
    required this.walletId,
    required this.result,
  });

  final String walletId;
  final SweepResult result;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        forceMaterialTransparency: true,
        automaticallyImplyLeading: false,
        flexibleSpace: TopBar(
          title: 'Sweep Complete',
          onBack: () => context.goNamed(WalletRoute.walletHome.name),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  Gif(
                    image: AssetImage(Assets.animations.successTick.path),
                    autostart: Autostart.once,
                    height: 100,
                    width: 100,
                  ),
                  const Gap(20),
                  BBText(
                    'Successfully Swept',
                    style: context.font.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const Gap(8),
                  if (result.amountSwept != null) ...[
                    BBText(
                      '${result.amountSwept} sats',
                      style: context.font.displaySmall,
                      maxLines: 4,
                      textAlign: TextAlign.center,
                    ),
                  ] else ...[
                    BBText(
                      result.message,
                      style: context.font.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
            const Spacer(flex: 2),
            if (result.txId != null)
              BBButton.big(
                label: 'View Details',
                onPressed: () {
                  // Use goNamed to replace the success screen, not push on top
                  context.goNamed(
                    TransactionsRoute.transactionDetails.name,
                    pathParameters: {'txId': result.txId!},
                    queryParameters: {'walletId': walletId},
                  );
                },
                bgColor: context.colour.secondary,
                textColor: context.colour.onSecondary,
              ),
            const Gap(32),
          ],
        ),
      ),
    );
  }
}
