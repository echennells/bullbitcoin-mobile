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
      const scriptType = ScriptType.bip84;

      // Get the current environment to determine the network
      final settings = await _settingsRepository.fetch();
      final environment = settings.environment;
      final bitcoinNetwork =
          environment.isMainnet
              ? Network.bitcoinMainnet
              : Network.bitcoinTestnet;
      final liquidNetwork =
          environment.isMainnet ? Network.liquidMainnet : Network.liquidTestnet;

      // The default wallets should be 1 Bitcoin and 1 Liquid wallet.
      final defaultWallets = await Future.wait([
        _wallet.createWallet(
          seed: seed,
          network: bitcoinNetwork,
          scriptType: scriptType,
          isDefault: true,
          birthday: birthday,
        ),
        _wallet.createWallet(
          seed: seed,
          network: liquidNetwork,
          scriptType: scriptType,
          isDefault: true,
          birthday: birthday,
        ),
      ]);

      final allWallets = List<Wallet>.from(defaultWallets);

      // For Liquid, also check BIP49 (legacy Aqua compatibility)
      // Only check if this is a wallet recovery (mnemonicWords provided)
      if (mnemonicWords != null) {
        Wallet? legacyLiquidWallet;
        try {
          // Create as non-default first to avoid conflict with BIP84 wallet
          legacyLiquidWallet = await _wallet.createWallet(
            seed: seed,
            network: liquidNetwork,
            scriptType: ScriptType.bip49,
            isDefault: false,
            birthday: birthday,
            sync: true,
          );

          // Only keep the wallet if it has a non-zero balance
          if (legacyLiquidWallet.balanceSat > BigInt.zero) {
            // User has funds in BIP49 - delete BIP84 and recreate BIP49 as default
            final bip84LiquidWallet = defaultWallets[1]; // Index 1 is Liquid
            await _wallet.deleteWallet(walletId: bip84LiquidWallet.id);

            // Delete the non-default BIP49 wallet
            await _wallet.deleteWallet(walletId: legacyLiquidWallet.id);

            // Recreate BIP49 as the default Liquid wallet
            final defaultBip49Wallet = await _wallet.createWallet(
              seed: seed,
              network: liquidNetwork,
              scriptType: ScriptType.bip49,
              isDefault: true,
              birthday: birthday,
              sync: true,
            );

            allWallets[1] = defaultBip49Wallet;

            log.fine(
              'Legacy BIP49 Liquid wallet found: ${defaultBip49Wallet.derivationPath} '
              '(balance: ${defaultBip49Wallet.balanceSat})',
            );
            log.warning(
              'Imported legacy BIP49 Liquid wallet. '
              'Consider migrating to BIP84 for lower transaction fees.',
            );
          } else {
            // Delete empty wallet to avoid cluttering the database
            await _wallet.deleteWallet(walletId: legacyLiquidWallet.id);
            log.fine('No funds found in BIP49 Liquid wallet');
          }
        } catch (e) {
          log.warning('Failed to check BIP49 Liquid wallet: $e');
          // Clean up the wallet if it was created but failed later
          if (legacyLiquidWallet != null) {
            try {
              await _wallet.deleteWallet(walletId: legacyLiquidWallet.id);
            } catch (deleteError) {
              log.warning('Failed to delete failed wallet: $deleteError');
            }
          }
        }
      }

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
