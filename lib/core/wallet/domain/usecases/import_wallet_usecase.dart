import 'package:bb_mobile/core/errors/bull_exception.dart';
import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/settings/data/settings_repository.dart';
import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';

class ImportWalletUsecase {
  final SeedRepository _seedRepository;
  final SettingsRepository _settingsRepository;
  final WalletRepository _wallet;

  ImportWalletUsecase({
    required SeedRepository seedRepository,
    required SettingsRepository settingsRepository,
    required WalletRepository walletRepository,
  }) : _seedRepository = seedRepository,
       _settingsRepository = settingsRepository,
       _wallet = walletRepository;

  Future<List<Wallet>> execute({
    required List<String> mnemonicWords,
    ScriptType scriptType = ScriptType.bip84,
    String passphrase = '',
    String? label,
  }) async {
    try {
      // Get the current environment to determine the network
      final settings = await _settingsRepository.fetch();
      final environment = settings.environment;
      final bitcoinNetwork =
          environment.isMainnet
              ? Network.bitcoinMainnet
              : Network.bitcoinTestnet;
      final liquidNetwork =
          environment.isMainnet ? Network.liquidMainnet : Network.liquidTestnet;

      final seed = await _seedRepository.createFromMnemonic(
        mnemonicWords: mnemonicWords,
        passphrase: passphrase,
      );

      final importedWallets = <Wallet>[];

      // Create Bitcoin wallet with user-selected script type
      final bitcoinWallet = await _wallet.createWallet(
        seed: seed,
        network: bitcoinNetwork,
        scriptType: scriptType,
        isDefault: false,
        label: label,
        sync: true,
      );
      importedWallets.add(bitcoinWallet);
      log.fine('Bitcoin wallet imported: ${bitcoinWallet.derivationPath}');

      // For Liquid, check both BIP84 (modern) and BIP49 (legacy Aqua compatibility)
      final liquidScriptTypes = [ScriptType.bip84, ScriptType.bip49];

      for (final liquidScriptType in liquidScriptTypes) {
        final liquidWallet = await _wallet.createWallet(
          seed: seed,
          network: liquidNetwork,
          scriptType: liquidScriptType,
          isDefault: false,
          label: label,
          sync: true,
        );

        final hasFunds = liquidWallet.balanceSat > BigInt.zero;

        // Only import the wallet if it has a non-zero balance
        if (hasFunds) {
          importedWallets.add(liquidWallet);
          log.fine(
            'Liquid wallet imported: ${liquidWallet.derivationPath} '
            '(${liquidScriptType.name}, balance: ${liquidWallet.balanceSat})',
          );

          // If this is a BIP49 wallet with funds, log a warning
          if (liquidScriptType == ScriptType.bip49) {
            log.warning(
              'Imported legacy BIP49 Liquid wallet. '
              'Consider migrating to BIP84 for lower transaction fees.',
            );
          }
        } else {
          // Delete empty wallet to avoid cluttering the database
          await _wallet.deleteWallet(walletId: liquidWallet.id);
          log.fine(
            'Skipping empty Liquid wallet: ${liquidWallet.derivationPath} '
            '(${liquidScriptType.name})',
          );
        }
      }

      if (importedWallets.length == 1) {
        log.warning('Only Bitcoin wallet imported - no Liquid funds found');
      }

      log.fine('Wallets imported: ${importedWallets.length} total');

      return importedWallets;
    } catch (e) {
      throw ImportWalletException(e.toString());
    }
  }
}

class ImportWalletException extends BullException {
  ImportWalletException(super.message);
}
