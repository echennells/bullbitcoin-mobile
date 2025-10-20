import 'package:bb_mobile/core/utils/bip32_derivation.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bdk_flutter/bdk_flutter.dart' as bdk;
import 'package:bip32_keys/bip32_keys.dart' as bip32;
import 'package:bip39/bip39.dart' as bip39;
import 'package:lwk/lwk.dart' as lwk;

class DescriptorDerivation {
  static Future<String> derivePublicBitcoinDescriptorFromXpriv(
    String xprv, {
    required ScriptType scriptType,
    required bool isTestnet,
    bool isInternalKeychain = false,
  }) async {
    final secretKey = await bdk.DescriptorSecretKey.fromString(xprv);
    final network = isTestnet ? bdk.Network.testnet : bdk.Network.bitcoin;
    final keychain =
        isInternalKeychain
            ? bdk.KeychainKind.internalChain
            : bdk.KeychainKind.externalChain;
    bdk.Descriptor descriptor;

    switch (scriptType) {
      case ScriptType.bip84:
        descriptor = await bdk.Descriptor.newBip84(
          secretKey: secretKey,
          network: network,
          keychain: keychain,
        );
      case ScriptType.bip49:
        descriptor = await bdk.Descriptor.newBip49(
          secretKey: secretKey,
          network: network,
          keychain: keychain,
        );
      case ScriptType.bip44:
        descriptor = await bdk.Descriptor.newBip44(
          secretKey: secretKey,
          network: network,
          keychain: keychain,
        );
    }

    // `asString` returns the public descriptor.
    return descriptor.asString();
  }

  static Future<String> derivePublicLiquidDescriptorFromMnemonic(
    String mnemonic, {
    required ScriptType scriptType,
    required bool isTestnet,
  }) async {
    // For BIP84 (native SegWit), use LWK's built-in method
    if (scriptType == ScriptType.bip84) {
      final lwk.Descriptor confidentialDescriptor = await lwk
          .Descriptor.newConfidential(
        network: isTestnet ? lwk.Network.testnet : lwk.Network.mainnet,
        mnemonic: mnemonic,
      );
      return confidentialDescriptor.ctDescriptor;
    }

    // For BIP49 and BIP44, manually construct the descriptor
    // since LWK doesn't support custom derivation paths via newConfidential
    final network =
        isTestnet ? Network.liquidTestnet : Network.liquidMainnet;
    final seedBytes = bip39.mnemonicToSeed(mnemonic);

    // Derive the account xpub for the specified script type
    final accountXpub = await Bip32Derivation.getAccountXpub(
      seedBytes: seedBytes,
      scriptType: scriptType,
      network: network,
    );

    // Get the master fingerprint from the root key
    final masterKey = bip32.Bip32Keys.fromSeed(seedBytes);
    final masterFingerprint = masterKey.fingerprintHex;

    // Convert xpub to the appropriate format (ypub for BIP49, zpub for BIP84, etc.)
    final formattedXpub = accountXpub.convert(scriptType.getXpubType(network));

    // Construct the derivation path string
    final coinType = network.coinType;
    final derivationPath = "${scriptType.purpose}h/${coinType}h/0h";

    // Construct the descriptor based on script type
    String descriptorPrefix;
    switch (scriptType) {
      case ScriptType.bip49:
        descriptorPrefix = 'elsh(wpkh';
      case ScriptType.bip44:
        descriptorPrefix = 'elpkh';
      case ScriptType.bip84:
        // Should have been handled above, but include for completeness
        descriptorPrefix = 'elwpkh';
    }

    // Build the complete descriptor
    // Format: elsh(wpkh([fingerprint/49h/1776h/0h]ypub.../<0;1>/*))
    final descriptor =
        scriptType == ScriptType.bip49
            ? '$descriptorPrefix([$masterFingerprint/$derivationPath]$formattedXpub/<0;1>/*))'
            : '$descriptorPrefix([$masterFingerprint/$derivationPath]$formattedXpub/<0;1>/*)';

    return descriptor;
  }

  static Future<String> deriveBitcoinDescriptorFromXpub(
    String xpub, {
    required String fingerprint,
    required ScriptType scriptType,
    required bool isTestnet,
    bool isInternalKeychain = false,
  }) async {
    final publicKey = await bdk.DescriptorPublicKey.fromString(xpub);
    final network = isTestnet ? bdk.Network.testnet : bdk.Network.bitcoin;
    final keychain =
        isInternalKeychain
            ? bdk.KeychainKind.internalChain
            : bdk.KeychainKind.externalChain;

    await bdk.Descriptor.newBip84Public(
      publicKey: publicKey,
      fingerPrint: fingerprint,
      network: network,
      keychain: keychain,
    );
    bdk.Descriptor descriptor;

    switch (scriptType) {
      case ScriptType.bip84:
        descriptor = await bdk.Descriptor.newBip84Public(
          publicKey: publicKey,
          fingerPrint: fingerprint,
          network: network,
          keychain: keychain,
        );
      case ScriptType.bip49:
        descriptor = await bdk.Descriptor.newBip49Public(
          publicKey: publicKey,
          fingerPrint: fingerprint,
          network: network,
          keychain: keychain,
        );
      case ScriptType.bip44:
        descriptor = await bdk.Descriptor.newBip44Public(
          publicKey: publicKey,
          fingerPrint: fingerprint,
          network: network,
          keychain: keychain,
        );
    }

    return descriptor.asString();
  }
}
