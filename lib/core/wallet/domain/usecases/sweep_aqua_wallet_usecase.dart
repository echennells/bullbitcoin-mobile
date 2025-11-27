import 'package:bb_mobile/core/blockchain/domain/usecases/broadcast_liquid_transaction_usecase.dart';
import 'package:bb_mobile/core/errors/bull_exception.dart';
import 'package:bb_mobile/core/fees/domain/fees_entity.dart';
import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/seed/domain/entity/seed.dart';
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
      log.info('=== SWEEP AQUA WALLET START ===');
      log.info('liquidWalletId: $liquidWalletId');
      log.info('networkFee: $networkFee');

      // Get the current BIP84 Liquid wallet
      final bip84Wallet = await _walletRepository.getWallet(liquidWalletId);
      log.info('Got BIP84 wallet: ${bip84Wallet?.id}');

      if (bip84Wallet == null) {
        log.severe('Wallet not found for ID: $liquidWalletId');
        throw SweepAquaWalletException('Wallet not found');
      }

      log.info('Wallet isLiquid: ${bip84Wallet.isLiquid}');
      log.info('Wallet scriptType: ${bip84Wallet.scriptType}');
      log.info('Wallet network: ${bip84Wallet.network}');
      log.info('Wallet masterFingerprint: ${bip84Wallet.masterFingerprint}');
      log.info('BIP84 wallet descriptor: ${bip84Wallet.externalPublicDescriptor}');

      if (!bip84Wallet.isLiquid) {
        log.severe('Wallet is not a Liquid wallet');
        throw SweepAquaWalletException('Wallet must be a Liquid wallet');
      }

      if (bip84Wallet.scriptType != ScriptType.bip84) {
        log.severe('Wallet scriptType is ${bip84Wallet.scriptType}, expected bip84');
        throw SweepAquaWalletException(
          'Wallet must be BIP84. Current type: ${bip84Wallet.scriptType}',
        );
      }

      // Get the seed for this wallet
      log.info('Getting seed for masterFingerprint: ${bip84Wallet.masterFingerprint}');
      final seed = await _seedRepository.get(bip84Wallet.masterFingerprint);
      final seedType = seed is MnemonicSeed ? 'mnemonic (${seed.mnemonicWords.length} words)' : 'bytes';
      log.info('Got seed, type: $seedType');

      log.info('Creating temporary BIP49 wallet to check for Aqua funds...');
      log.info('Creating WITHOUT sync to keep invisible to UI layer');

      final startTime = DateTime.now();
      // Create a temporary BIP49 wallet WITHOUT syncing
      // This prevents WalletSyncFinished event from firing and keeps wallet invisible to UI
      final bip49Wallet = await _walletRepository.createWallet(
        seed: seed,
        network: bip84Wallet.network,
        scriptType: ScriptType.bip49,
        isDefault: false,
        sync: false, // ✅ Don't sync! Prevents UI from seeing this wallet
      );
      log.info('BIP49 wallet created with ID: ${bip49Wallet.id}');
      log.info('Wallet is invisible to UI layer - no sync event triggered');
      log.info('BIP49 wallet scriptType: ${bip49Wallet.scriptType}');
      log.info('BIP49 wallet network: ${bip49Wallet.network}');
      log.info('BIP49 wallet xpub: ${bip49Wallet.xpub}');
      log.info('BIP49 wallet externalDescriptor: ${bip49Wallet.externalPublicDescriptor}');

      // Manually sync the wallet using direct repository call (bypasses event streams)
      log.info('Manually syncing BIP49 wallet (bypasses UI layer)...');
      await _walletRepository.sync(bip49Wallet);
      final syncDuration = DateTime.now().difference(startTime);
      log.info('Manual sync completed in ${syncDuration.inMilliseconds}ms');

      // Manually get balance using direct repository call (bypasses event streams)
      final updatedBip49Wallet = await _walletRepository.getWallet(bip49Wallet.id, sync: false);
      final finalBalance = updatedBip49Wallet?.balanceSat ?? BigInt.zero;
      log.info('BIP49 wallet balance: $finalBalance sats');

      // Check if there are any funds to sweep
      if (finalBalance == BigInt.zero) {
        log.info('No funds found in BIP49 wallet, deleting temporary wallet');
        await _walletRepository.deleteWallet(walletId: bip49Wallet.id);
        log.info('=== SWEEP AQUA WALLET END (no funds) ===');
        return SweepResult(success: false, message: 'No Aqua funds found');
      }

      log.info(
        'Found $finalBalance sats in BIP49 wallet. Starting sweep...',
      );

      // Get a receive address from the BIP84 wallet
      log.info('Getting receive address from BIP84 wallet ID: ${bip84Wallet.id}');
      final receiveAddress = await _getReceiveAddressUsecase.execute(
        walletId: bip84Wallet.id,
      );

      log.info('Sweeping to address: ${receiveAddress.address}');
      log.info('Receive address wallet ID: ${receiveAddress.walletId}');

      // Build a drain transaction from BIP49 to BIP84
      log.info('Building PSET:');
      log.info('  From wallet: ${bip49Wallet.id}');
      log.info('  To address: ${receiveAddress.address}');
      log.info('  Address belongs to wallet: ${receiveAddress.walletId}');
      log.info('  BIP84 wallet ID (should match): ${bip84Wallet.id}');
      log.info('  Drain: true');

      final pset = await _liquidWalletRepository.buildPset(
        walletId: bip49Wallet.id,
        address: receiveAddress.address,
        amountSat: null, // drain uses all funds
        networkFee: networkFee,
        drain: true,
      );

      log.info('Built PSET for sweep transaction');
      log.info('PSET details: ${pset.substring(0, 100)}...');

      // Sign the transaction
      final signedPset = await _signLiquidTxUsecase.execute(
        walletId: bip49Wallet.id,
        pset: pset,
      );

      log.info('Signed PSET');

      // Broadcast the transaction
      log.info('Broadcasting signed PSET...');
      final txId = await _broadcastLiquidTransactionUsecase.execute(signedPset);

      log.info('Sweep transaction broadcast successfully: $txId');
      log.info('Transaction should send $finalBalance sats from:');
      log.info('  Source: BIP49 wallet ${bip49Wallet.id}');
      log.info('  Destination: ${receiveAddress.address}');
      log.info('  Destination wallet: ${receiveAddress.walletId}');
      log.info('  Expected destination: BIP84 wallet ${bip84Wallet.id}');

      // Clean up the temporary BIP49 wallet
      log.info('Checking BIP49 wallet balance before deletion...');
      // Manually sync to get updated balance (bypasses UI layer)
      await _walletRepository.sync(bip49Wallet);
      final bip49WalletAfterSweep = await _walletRepository.getWallet(bip49Wallet.id, sync: false);
      log.info('BIP49 wallet balance after sweep: ${bip49WalletAfterSweep?.balanceSat ?? 0} sats (should be 0)');

      log.info('Checking BIP84 wallet balance after sweep...');
      // For BIP84, we DO want to trigger a sync event so UI updates
      final bip84WalletAfterSweep = await _walletRepository.getWallet(bip84Wallet.id, sync: true);
      log.info('BIP84 wallet balance after sweep: ${bip84WalletAfterSweep?.balanceSat ?? 0} sats (should have increased)');

      await _walletRepository.deleteWallet(walletId: bip49Wallet.id);
      log.info('Deleted temporary BIP49 wallet (never appeared in UI)');

      log.info('=== SWEEP AQUA WALLET END (success) ===');
      log.info('Successfully swept $finalBalance sats');
      log.info('Transaction ID: $txId');

      return SweepResult(
        success: true,
        txId: txId,
        amountSwept: finalBalance,
        message: 'Successfully swept $finalBalance sats from Aqua wallet',
      );
    } catch (e, stackTrace) {
      log.severe('=== SWEEP AQUA WALLET ERROR ===');
      log.severe('Error sweeping Aqua wallet: $e');
      log.severe('Stack trace: $stackTrace');
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
