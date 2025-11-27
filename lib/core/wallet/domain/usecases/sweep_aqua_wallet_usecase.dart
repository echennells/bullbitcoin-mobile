import 'package:bb_mobile/core/blockchain/domain/usecases/broadcast_liquid_transaction_usecase.dart';
import 'package:bb_mobile/core/errors/bull_exception.dart';
import 'package:bb_mobile/core/fees/domain/fees_entity.dart';
import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/core/wallet/data/repositories/liquid_wallet_repository.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/get_receive_address_usecase.dart';
import 'package:bb_mobile/features/send/domain/usecases/sign_liquid_tx_usecase.dart';

/// Sweeps funds from a legacy Aqua wallet (BIP49) to the current Liquid wallet (BIP84).
///
/// This usecase:
/// 1. Creates a temporary BIP49 Liquid wallet from the same seed
/// 2. Syncs it to check for on-chain balance
/// 3. If funds exist, creates a drain transaction to the BIP84 wallet
/// 4. Signs and broadcasts the transaction
/// 5. Cleans up the temporary wallet
///
/// Returns the transaction ID if successful, or null if no funds found.
class SweepAquaWalletUsecase {
  final WalletRepository _walletRepository;
  final LiquidWalletRepository _liquidWalletRepository;
  final SeedRepository _seedRepository;
  final SignLiquidTxUsecase _signLiquidTxUsecase;
  final BroadcastLiquidTransactionUsecase _broadcastLiquidTransactionUsecase;
  final GetReceiveAddressUsecase _getReceiveAddressUsecase;

  SweepAquaWalletUsecase({
    required WalletRepository walletRepository,
    required LiquidWalletRepository liquidWalletRepository,
    required SeedRepository seedRepository,
    required SignLiquidTxUsecase signLiquidTxUsecase,
    required BroadcastLiquidTransactionUsecase broadcastLiquidTransactionUsecase,
    required GetReceiveAddressUsecase getReceiveAddressUsecase,
  })  : _walletRepository = walletRepository,
        _liquidWalletRepository = liquidWalletRepository,
        _seedRepository = seedRepository,
        _signLiquidTxUsecase = signLiquidTxUsecase,
        _broadcastLiquidTransactionUsecase = broadcastLiquidTransactionUsecase,
        _getReceiveAddressUsecase = getReceiveAddressUsecase;

  Future<SweepResult> execute({
    required String liquidWalletId,
    required NetworkFee networkFee,
  }) async {
    try {
      // Get the current BIP84 Liquid wallet
      final bip84Wallet = await _walletRepository.getWallet(liquidWalletId);

      if (bip84Wallet == null) {
        throw SweepAquaWalletException('Wallet not found');
      }

      if (!bip84Wallet.isLiquid) {
        throw SweepAquaWalletException('Wallet must be a Liquid wallet');
      }

      if (bip84Wallet.scriptType != ScriptType.bip84) {
        throw SweepAquaWalletException(
          'Wallet must be BIP84. Current type: ${bip84Wallet.scriptType}',
        );
      }

      // Get the seed for this wallet
      final seed = await _seedRepository.get(bip84Wallet.masterFingerprint);

      log.info('Creating temporary BIP49 wallet to check for Aqua funds...');

      // Create a temporary BIP49 wallet from the same seed
      final bip49Wallet = await _walletRepository.createWallet(
        seed: seed,
        network: bip84Wallet.network,
        scriptType: ScriptType.bip49,
        isDefault: false,
        sync: true, // Must sync to detect on-chain funds
      );

      log.info('BIP49 wallet balance: ${bip49Wallet.balanceSat} sats');

      // Check if there are any funds to sweep
      if (bip49Wallet.balanceSat == BigInt.zero) {
        log.info('No funds found in BIP49 wallet');
        await _walletRepository.deleteWallet(walletId: bip49Wallet.id);
        return SweepResult(success: false, message: 'No Aqua funds found');
      }

      log.info(
        'Found ${bip49Wallet.balanceSat} sats in BIP49 wallet. Starting sweep...',
      );

      // Get a receive address from the BIP84 wallet
      final receiveAddress = await _getReceiveAddressUsecase.execute(
        walletId: bip84Wallet.id,
      );

      log.info('Sweeping to address: ${receiveAddress.address}');

      // Build a drain transaction from BIP49 to BIP84
      final pset = await _liquidWalletRepository.buildPset(
        walletId: bip49Wallet.id,
        address: receiveAddress.address,
        amountSat: null, // drain uses all funds
        networkFee: networkFee,
        drain: true,
      );

      log.info('Built PSET for sweep transaction');

      // Sign the transaction
      final signedPset = await _signLiquidTxUsecase.execute(
        walletId: bip49Wallet.id,
        pset: pset,
      );

      log.info('Signed PSET');

      // Broadcast the transaction
      final txId = await _broadcastLiquidTransactionUsecase.execute(signedPset);

      log.info('Sweep transaction broadcast successfully: $txId');

      // Clean up the temporary BIP49 wallet
      await _walletRepository.deleteWallet(walletId: bip49Wallet.id);

      return SweepResult(
        success: true,
        txId: txId,
        amountSwept: bip49Wallet.balanceSat,
        message: 'Successfully swept ${bip49Wallet.balanceSat} sats from Aqua wallet',
      );
    } catch (e) {
      log.severe('Error sweeping Aqua wallet: $e');
      throw SweepAquaWalletException(e.toString());
    }
  }
}

class SweepResult {
  final bool success;
  final String? txId;
  final BigInt? amountSwept;
  final String message;

  SweepResult({
    required this.success,
    this.txId,
    this.amountSwept,
    required this.message,
  });
}

class SweepAquaWalletException extends BullException {
  SweepAquaWalletException(super.message);
}
