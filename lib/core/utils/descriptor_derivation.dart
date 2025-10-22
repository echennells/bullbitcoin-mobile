import 'dart:convert';
import 'dart:typed_data';

import 'package:bb_mobile/core/utils/bip32_derivation.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bdk_flutter/bdk_flutter.dart' as bdk;
import 'package:bip32_keys/bip32_keys.dart' as bip32;
import 'package:bip39_mnemonic/bip39_mnemonic.dart' as bip39;
import 'package:crypto/crypto.dart';
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

    // Convert mnemonic string to list of words and then to seed bytes
    final mnemonicWords = mnemonic.split(' ');
    final seedBytes = Uint8List.fromList(
      bip39.Mnemonic.fromWords(
        words: mnemonicWords,
        passphrase: '',
      ).seed,
    );

    // Derive SLIP77 master blinding key for confidential transactions
    final slip77Key = deriveSlip77MasterBlindingKey(seedBytes);

    // Derive the account xpub for the specified script type
    final accountXpub = await Bip32Derivation.getAccountXpub(
      seedBytes: seedBytes,
      scriptType: scriptType,
      network: network,
    );

    // Get the master fingerprint from the root key
    final masterKey = bip32.Bip32Keys.fromSeed(seedBytes);
    final masterFingerprint = masterKey.fingerprintHex;

    // For Liquid, always use standard xpub format (LWK doesn't support ypub/zpub)
    final xpubString = accountXpub.toBase58();

    // Construct the derivation path string
    final coinType = network.coinType;
    final derivationPath = "${scriptType.purpose}h/${coinType}h/0h";

    // Build inner descriptor based on script type
    String innerDescriptor;
    switch (scriptType) {
      case ScriptType.bip49:
        innerDescriptor =
            'elsh(wpkh([$masterFingerprint/$derivationPath]$xpubString/<0;1>/*))';
      case ScriptType.bip44:
        innerDescriptor =
            'elpkh([$masterFingerprint/$derivationPath]$xpubString/<0;1>/*)';
      case ScriptType.bip84:
        // Should have been handled above, but include for completeness
        innerDescriptor =
            'elwpkh([$masterFingerprint/$derivationPath]$xpubString/<0;1>/*)';
    }

    // Wrap with ct(slip77(...), ...) for confidential transactions
    final ctDescriptor = 'ct(slip77($slip77Key),$innerDescriptor)';
    return ctDescriptor;
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

  /// Derives the SLIP77 master blinding key from a BIP39 seed
  /// according to the SLIP-0077 specification
  static String deriveSlip77MasterBlindingKey(Uint8List seedBytes) {
    // Step 1: HMAC-SHA512(key="Symmetric key seed", msg=seed)
    final domain = utf8.encode('Symmetric key seed');
    final hmac1 = Hmac(sha512, domain);
    final root = hmac1.convert(seedBytes).bytes;

    // Step 2: HMAC-SHA512(key=root[0:32], msg="\x00" + "SLIP-0077")
    final label = Uint8List.fromList([0x00] + utf8.encode('SLIP-0077'));
    final hmac2 = Hmac(sha512, root.sublist(0, 32));
    final node = hmac2.convert(label).bytes;

    // Step 3: master_blinding_key = node[32:64]
    final masterBlindingKey = node.sublist(32, 64);

    // Return as 64-character hex string
    return masterBlindingKey
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
