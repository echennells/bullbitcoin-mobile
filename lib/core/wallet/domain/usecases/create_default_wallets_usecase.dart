import 'package:bb_mobile/core/errors/bull_exception.dart';
import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/seed/data/services/mnemonic_generator.dart';
import 'package:bb_mobile/core/settings/data/settings_repository.dart';
import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';

class CreateDefaultWalletsUsecase {
  final SeedRepository _seedRepository;
  final SettingsRepository _settingsRepository;
  final MnemonicGenerator _mnemonicGenerator;
  final WalletRepository _wallet;

  CreateDefaultWalletsUsecase({
    required SeedRepository seedRepository,
    required SettingsRepository settingsRepository,
    required MnemonicGenerator mnemonicGenerator,
    required WalletRepository walletRepository,
  }) : _seedRepository = seedRepository,
       _settingsRepository = settingsRepository,
       _mnemonicGenerator = mnemonicGenerator,
       _wallet = walletRepository;

  Future<List<Wallet>> execute({
    List<String>? mnemonicWords,
    String? passphrase,
  }) async {
    try {
      final isGenerated = mnemonicWords == null;

      // Generate a mnemonic seed if the user creates a new wallet
      //  or use the provided mnemonic words in case of recovery.
      final mnemonic = mnemonicWords ?? await _mnemonicGenerator.generate();

      // The wallet birthday will be useful to optimize syncs.
      DateTime? birthday;
      if (isGenerated) birthday = DateTime.now().toUtc();

      // Create and store the seed
      final seed = await _seedRepository.createFromMnemonic(
        mnemonicWords: mnemonic,
        passphrase: passphrase,
      );

      // The current default script type for the wallets is BIP84
      const bitcoinScriptType = ScriptType.bip84;

      // Get the current environment to determine the network
      final settings = await _settingsRepository.fetch();
      final environment = settings.environment;
      final bitcoinNetwork =
          environment.isMainnet
              ? Network.bitcoinMainnet
              : Network.bitcoinTestnet;
      final liquidNetwork =
          environment.isMainnet ? Network.liquidMainnet : Network.liquidTestnet;

      // For Liquid wallets during recovery, check if user has legacy BIP49 (Aqua) funds
      ScriptType liquidScriptType = ScriptType.bip84;
      if (mnemonicWords != null) {
        // Wallet recovery - check BIP49 first for Aqua compatibility
        Wallet? testBip49Wallet;
        try {
          testBip49Wallet = await _wallet.createWallet(
            seed: seed,
            network: liquidNetwork,
            scriptType: ScriptType.bip49,
            isDefault: false,
            birthday: birthday,
            sync: true,
          );

          if (testBip49Wallet.balanceSat > BigInt.zero) {
            // User has funds in BIP49 - use it as the default Liquid wallet type
            liquidScriptType = ScriptType.bip49;
            log.fine(
              'Detected BIP49 Liquid wallet with balance: ${testBip49Wallet.balanceSat}',
            );
            log.warning(
              'Importing legacy BIP49 Liquid wallet (Aqua compatibility). '
              'Consider migrating to BIP84 for lower transaction fees.',
            );
          } else {
            log.fine('No funds in BIP49 Liquid wallet, using BIP84');
          }

          // Clean up test wallet
          await _wallet.deleteWallet(walletId: testBip49Wallet.id);
        } catch (e) {
          log.warning('Failed to check BIP49 Liquid wallet: $e');
          if (testBip49Wallet != null) {
            try {
              await _wallet.deleteWallet(walletId: testBip49Wallet.id);
            } catch (deleteError) {
              log.warning('Failed to delete test wallet: $deleteError');
            }
          }
          // Fall back to BIP84 if check fails
          liquidScriptType = ScriptType.bip84;
        }
      }

      // Create default wallets with the determined script types
      final allWallets = await Future.wait([
        _wallet.createWallet(
          seed: seed,
          network: bitcoinNetwork,
          scriptType: bitcoinScriptType,
          isDefault: true,
          birthday: birthday,
        ),
        _wallet.createWallet(
          seed: seed,
          network: liquidNetwork,
          scriptType: liquidScriptType,
          isDefault: true,
          birthday: birthday,
        ),
      ]);

      log.fine('Wallets created: ${allWallets.length} total');

      return allWallets;
    } catch (e) {
      throw CreateDefaultWalletsException(e.toString());
    }
  }
}

class CreateDefaultWalletsException extends BullException {
  CreateDefaultWalletsException(super.message);
}
