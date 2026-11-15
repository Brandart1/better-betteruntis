import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:better_betteruntis/sync/e2e_crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List hex(String s) => Uint8List.fromList([
  for (var i = 0; i < s.length; i += 2)
    int.parse(s.substring(i, i + 2), radix: 16),
]);

String toHex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

E2eRandomBytes queue(List<String> hexValues) {
  var i = 0;
  return (n) {
    final v = hex(hexValues[i++]);
    expect(v.length, n, reason: 'random call $i');
    return v;
  };
}

/// Flips one bit of byte [index] in a base64url string.
String flip(String b64, int index) {
  final b = b64uDecode(b64);
  b[index] ^= 1;
  return b64uEncode(b);
}

void main() {
  final v = jsonDecode(
    File('test/sync/e2e_vectors_v1.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final setupV = v['setup'] as Map<String, dynamic>;
  final rnd = setupV['random'] as Map<String, dynamic>;
  final passphrase = setupV['passphrase'] as String;
  final headerJson = setupV['header'] as Map<String, dynamic>;
  final header = E2eHeader.fromJson(headerJson);
  final recoveryCode = setupV['recoveryCode'] as String;
  late E2eKeys keys;

  setUpAll(() async {
    keys = await E2eKeys.fromDek(hex(rnd['dek'] as String));
  });

  group('vectors', () {
    test('KEK derivation', () async {
      for (final k in (v['kdf'] as List).cast<Map<String, dynamic>>()) {
        final kek = await deriveKek(
          k['passphrase'] as String,
          E2eKdfParams(
            salt: hex(k['salt'] as String),
            memoryKiB: k['m'] as int,
            iterations: k['t'] as int,
            parallelism: k['p'] as int,
          ),
        );
        expect(toHex(kek), k['kek']);
      }
    });

    test('createE2e reproduces header and recovery code', () async {
      final setup = await createE2e(
        passphrase,
        random: queue(
          [
            rnd['salt'],
            rnd['dek'],
            rnd['wrapNonce'],
            rnd['checkNonce'],
            rnd['recoveryKey'],
            rnd['recoveryNonce'],
          ].cast<String>(),
        ),
      );
      expect(setup.header.toJson(), headerJson);
      expect(setup.recoveryCode, recoveryCode);
      expect(toHex(setup.keys.dekBytes), rnd['dek']);
    });

    test('changePassphrase reproduces header', () async {
      final c = v['changePassphrase'] as Map<String, dynamic>;
      final r = c['random'] as Map<String, dynamic>;
      final h2 = await changePassphrase(
        header,
        keys,
        c['newPassphrase'] as String,
        random: queue([r['salt'] as String, r['wrapNonce'] as String]),
      );
      expect(h2.toJson(), c['header']);
    });

    test('server keys', () async {
      for (final s in (v['serverKeys'] as List).cast<Map<String, dynamic>>()) {
        expect(await serverKey(keys, s['noteKey'] as String), s['serverKey']);
      }
    });

    test('note plaintexts, blobs and decryption', () async {
      for (final n in (v['notes'] as List).cast<Map<String, dynamic>>()) {
        final key = n['noteKey'] as String;
        final exam = n['exam'] as bool;
        final text = n['text'] as String;
        final plain = encodeNotePlaintext(noteKey: key, exam: exam, text: text);
        expect(toHex(plain), n['plaintext']);
        expect(plain.length, n['paddedLength']);
        final blob = await encryptNote(
          keys,
          noteKey: key,
          exam: exam,
          text: text,
          random: queue([n['nonce'] as String]),
        );
        expect(blob, n['blob']);
        final note = await decryptNote(keys, n['serverKey'] as String, blob);
        expect(note.noteKey, key);
        expect(note.exam, exam);
        expect(note.text, text);
      }
    });

    test('unlock with passphrase and recovery code', () async {
      final k1 = await unlockWithPassphrase(header, passphrase);
      expect(toHex(k1.dekBytes), rnd['dek']);
      final k2 = await unlockWithRecoveryCode(header, recoveryCode);
      expect(toHex(k2.dekBytes), rnd['dek']);
    });
  });

  group('round trips', () {
    test('create, unlock, encrypt, decrypt with real randomness', () async {
      final setup = await createE2e('ein langes Passwort');
      final h = E2eHeader.fromJson(
        jsonDecode(jsonEncode(setup.header.toJson())),
      );
      final k = await unlockWithPassphrase(h, 'ein langes Passwort');
      expect(k.dekBytes, setup.keys.dekBytes);
      expect(await k.matchesHeader(h), isTrue);
      final blob = await encryptNote(
        setup.keys,
        noteKey: 'k1',
        exam: true,
        text: 'Hallo 👋',
      );
      final sk = await serverKey(k, 'k1');
      final note = await decryptNote(k, sk, blob);
      expect((note.noteKey, note.exam, note.text), ('k1', true, 'Hallo 👋'));
      // Same note encrypts differently each time (random nonce).
      final blob2 = await encryptNote(
        k,
        noteKey: 'k1',
        exam: true,
        text: 'Hallo 👋',
      );
      expect(blob2, isNot(blob));
      expect(await serverKey(setup.keys, 'k1'), sk);
    });

    test('without recovery', () async {
      final setup = await createE2e('passphrase!', withRecovery: false);
      expect(setup.recoveryCode, isNull);
      expect(setup.header.hasRecovery, isFalse);
      expect(setup.header.toJson().containsKey('wrappedDekRecovery'), isFalse);
      await expectLater(
        unlockWithRecoveryCode(setup.header, recoveryCode),
        throwsA(isA<E2eWrongSecret>()),
      );
    });

    test('changing the passphrase keeps notes decryptable', () async {
      final sk = await serverKey(keys, 'n');
      final blob = await encryptNote(
        keys,
        noteKey: 'n',
        exam: false,
        text: 't',
      );
      final h2 = await changePassphrase(header, keys, 'new passphrase 123');
      expect(h2.kdf.salt, isNot(header.kdf.salt));
      await expectLater(
        unlockWithPassphrase(h2, passphrase),
        throwsA(isA<E2eWrongSecret>()),
      );
      final k2 = await unlockWithPassphrase(h2, 'new passphrase 123');
      expect((await decryptNote(k2, sk, blob)).text, 't');
      // Recovery code still works on the new header.
      final k3 = await unlockWithRecoveryCode(h2, recoveryCode);
      expect(k3.dekBytes, keys.dekBytes);
    });

    test('regenerating the recovery code', () async {
      final (h2, code) = await regenerateRecoveryCode(header, keys);
      expect(code, isNot(recoveryCode));
      expect((await unlockWithRecoveryCode(h2, code)).dekBytes, keys.dekBytes);
      await expectLater(
        unlockWithRecoveryCode(h2, recoveryCode),
        throwsA(isA<E2eWrongSecret>()),
      );
    });

    test('short new passphrases are refused', () async {
      expect(() => createE2e('1234567'), throwsArgumentError);
      expect(() => changePassphrase(header, keys, 'kurz'), throwsArgumentError);
      // 8 code points, more UTF-16 units / bytes.
      expect((await createE2e('🔐🔐🔐🔐🔐🔐🔐🔐')).header.version, 1);
    });
  });

  group('wrong secrets', () {
    test('wrong passphrase', () async {
      await expectLater(
        unlockWithPassphrase(header, '${passphrase}x'),
        throwsA(isA<E2eWrongSecret>()),
      );
    });

    test('wrong or malformed recovery code', () async {
      final other = formatRecoveryCode(Uint8List(16));
      await expectLater(
        unlockWithRecoveryCode(header, other),
        throwsA(isA<E2eWrongSecret>()),
      );
      await expectLater(
        unlockWithRecoveryCode(header, 'too short'),
        throwsA(isA<E2eWrongSecret>()),
      );
    });

    test('check mismatch is corrupt, not a wrong secret', () async {
      // A header whose check belongs to another DEK.
      final other = await createE2e(passphrase, withRecovery: false);
      final mixed = E2eHeader.fromJson({
        ...headerJson,
        'check': other.header.toJson()['check'],
      });
      await expectLater(
        unlockWithPassphrase(mixed, passphrase),
        throwsA(isA<E2eCorrupt>()),
      );
      expect(await other.keys.matchesHeader(header), isFalse);
      await expectLater(
        changePassphrase(header, other.keys, 'whatever123'),
        throwsA(isA<E2eCorrupt>()),
      );
    });
  });

  group('tampering', () {
    late String sk;
    late String blob;
    setUpAll(() async {
      sk = await serverKey(keys, '2026-11-17|3|MATH');
      blob = await encryptNote(
        keys,
        noteKey: '2026-11-17|3|MATH',
        exam: true,
        text: 'SA',
      );
    });

    test('flipped bits anywhere', () async {
      final len = b64uDecode(blob).length;
      for (final i in [0, 1, 24, 25, 100, len - 17, len - 1]) {
        await expectLater(
          decryptNote(keys, sk, flip(blob, i)),
          throwsA(isA<E2eCorrupt>()),
          reason: 'byte $i',
        );
      }
    });

    test('truncated / garbage blobs', () async {
      for (final b in ['', 'AQ', blob.substring(0, 50), '!!!!', '$blob=']) {
        await expectLater(decryptNote(keys, sk, b), throwsA(isA<E2eCorrupt>()));
      }
    });

    test('blob moved to another server key (AAD)', () async {
      final other = await serverKey(keys, 'other');
      await expectLater(
        decryptNote(keys, other, blob),
        throwsA(isA<E2eCorrupt>()),
      );
    });

    test('valid AEAD for server key A but note key B inside', () async {
      // Only possible with K_enc (e.g. a client bug); the HMAC check in
      // decryptNote must still refuse it. Built by hand from the vector
      // subkey so the AEAD itself verifies.
      final kEnc = hex(
        (setupV['subkeys'] as Map<String, dynamic>)['noteEnc'] as String,
      );
      final fake = await serverKey(keys, 'fake');
      final plain = encodeNotePlaintext(noteKey: 'real', exam: false, text: '');
      final nonce = Uint8List(24);
      final box = await Xchacha20.poly1305Aead().encrypt(
        plain,
        secretKey: SecretKey(kEnc),
        nonce: nonce,
        aad: [1, ...utf8.encode(fake)],
      );
      final blobFake = b64uEncode([
        1,
        ...nonce,
        ...box.cipherText,
        ...box.mac.bytes,
      ]);
      // Sanity: the same construction with the right key decrypts.
      final good = await Xchacha20.poly1305Aead().encrypt(
        encodeNotePlaintext(noteKey: 'fake', exam: false, text: ''),
        secretKey: SecretKey(kEnc),
        nonce: nonce,
        aad: [1, ...utf8.encode(fake)],
      );
      final blobGood = b64uEncode([
        1,
        ...nonce,
        ...good.cipherText,
        ...good.mac.bytes,
      ]);
      expect((await decryptNote(keys, fake, blobGood)).noteKey, 'fake');
      await expectLater(
        decryptNote(keys, fake, blobFake),
        throwsA(isA<E2eCorrupt>()),
      );
    });

    test('another DEK', () async {
      final other = await E2eKeys.fromDek(List.filled(32, 7));
      await expectLater(
        decryptNote(other, sk, blob),
        throwsA(isA<E2eCorrupt>()),
      );
    });

    test('plaintext layout validation', () {
      final good = encodeNotePlaintext(noteKey: 'k', exam: true, text: 'x');
      expect(decodeNotePlaintext(good).text, 'x');
      Uint8List mod(void Function(Uint8List) f) {
        final c = Uint8List.fromList(good);
        f(c);
        return c;
      }

      for (final bad in [
        mod((p) => p[0] = 2), // version
        mod((p) => p[1] = 3), // flags
        mod((p) => p[3] = 250), // key length past end
        mod((p) => p[8] = 255), // text length past end
        mod((p) => p[255] = 1), // padding not zero
        good.sublist(0, 255), // not a multiple of 256
        Uint8List.fromList([...good, ...Uint8List(256)]), // excess padding
        mod((p) => p[4] = 0xff), // invalid UTF-8 in key
      ]) {
        expect(() => decodeNotePlaintext(bad), throwsA(isA<E2eCorrupt>()));
      }
    });
  });

  group('padding', () {
    int size(String key, String text) =>
        encodeNotePlaintext(noteKey: key, exam: false, text: text).length;

    test('multiples of 256', () {
      expect(size('', ''), 256);
      expect(size('k', 'x' * 247), 256); // 8 + 1 + 247 = 256
      expect(size('k', 'x' * 248), 512);
      expect(size('k', 'ü' * 1000), 2048); // 2009 bytes
      expect(size('k', '🧮' * 64), 512); // 4-byte code points
    });
  });

  group('recovery code', () {
    test('format: 26 characters in 5 groups', () {
      expect(
        recoveryCode,
        matches(RegExp(r'^([0-9A-HJKMNP-TV-Z]{5}-){4}[0-9A-HJKMNP-TV-Z]{6}$')),
      );
      expect(toHex(parseRecoveryCode(recoveryCode)), rnd['recoveryKey']);
      expect(
        formatRecoveryCode(Uint8List(16)),
        '00000-00000-00000-00000-000000',
      );
      expect(
        formatRecoveryCode(Uint8List(16)..fillRange(0, 16, 255)),
        'ZZZZZ-ZZZZZ-ZZZZZ-ZZZZZ-ZZZZZW',
      );
    });

    test('tolerant parsing', () async {
      final plain = recoveryCode.replaceAll('-', '');
      final variants = [
        recoveryCode.toLowerCase(),
        plain,
        ' ${plain.substring(0, 13)}  ${plain.substring(13)} ',
        recoveryCode.replaceAll('-', '_'),
        plain.split('').join('.'),
      ];
      for (final c in variants) {
        expect(toHex(parseRecoveryCode(c)), rnd['recoveryKey'], reason: c);
      }
      // Confusables: 0 <-> O/o, 1 <-> I/i/L/l.
      final key = Uint8List(16)..[0] = 0x08; // code starts with "10"
      final code = formatRecoveryCode(key);
      expect(code.substring(0, 2), '10');
      for (final c in ['IO', 'io', 'LO', 'lo', 'lO', 'iO']) {
        expect(parseRecoveryCode(c + code.substring(2)), key, reason: c);
      }
      expect(
        (await unlockWithRecoveryCode(
          header,
          recoveryCode.toLowerCase(),
        )).dekBytes,
        keys.dekBytes,
      );
    });

    test('rejects bad codes', () {
      for (final c in [
        '',
        recoveryCode.substring(1),
        '${recoveryCode}0',
        recoveryCode.replaceFirst(RegExp('.'), 'U'), // U is not Crockford
        '${recoveryCode.substring(0, recoveryCode.length - 1)}1', // trailing bits
      ]) {
        expect(() => parseRecoveryCode(c), throwsFormatException, reason: c);
      }
    });
  });

  group('header JSON', () {
    test('round trip', () {
      expect(
        E2eHeader.fromJson(jsonDecode(jsonEncode(headerJson))).toJson(),
        headerJson,
      );
    });

    Map<String, dynamic> withKdf(Map<String, Object?> changes) => {
      ...headerJson,
      'kdf': {...headerJson['kdf'] as Map, ...changes},
    };

    test('unsupported versions, algorithms and parameters', () {
      for (final j in <Object?>[
        {...headerJson, 'version': 2},
        {...headerJson, 'version': 0},
        withKdf({'alg': 'argon2i'}),
        withKdf({'alg': 'scrypt'}),
        withKdf({'m': 19455}), // below default
        withKdf({'t': 1}),
        withKdf({'p': 0}),
        withKdf({'m': 262145}), // above maximum
        withKdf({'t': 17}),
        withKdf({'p': 17}),
        withKdf({'salt': b64uEncode(Uint8List(8))}),
      ]) {
        expect(
          () => E2eHeader.fromJson(j),
          throwsA(isA<E2eUnsupported>()),
          reason: '$j',
        );
      }
      // Stronger parameters are accepted.
      expect(
        E2eHeader.fromJson(withKdf({'m': 65536, 't': 3, 'p': 2})).kdf.memoryKiB,
        65536,
      );
    });

    test('malformed headers', () {
      for (final j in <Object?>[
        null,
        'x',
        {...headerJson, 'version': '1'},
        {...headerJson}..remove('wrappedDek'),
        {...headerJson}..remove('check'),
        {...headerJson}..remove('kdf'),
        {...headerJson, 'wrappedDek': 'not base64!'},
        {...headerJson, 'wrappedDek': '${headerJson['wrappedDek']}='},
        {
          ...headerJson,
          'wrappedDek': (headerJson['wrappedDek'] as String).substring(4),
        },
        {...headerJson, 'wrappedDekRecovery': 5},
        {...headerJson, 'check': headerJson['wrappedDek']},
        withKdf({'m': '19456'}),
      ]) {
        expect(
          () => E2eHeader.fromJson(j),
          throwsA(isA<E2eCorrupt>()),
          reason: '$j',
        );
      }
    });

    test('unlock refuses weak headers built in code', () async {
      final weak = E2eHeader(
        kdf: E2eKdfParams(
          salt: header.kdf.salt,
          memoryKiB: 1024,
          iterations: 1,
        ),
        wrappedDek: header.wrappedDek,
        check: header.check,
      );
      await expectLater(
        unlockWithPassphrase(weak, passphrase),
        throwsA(isA<E2eUnsupported>()),
      );
    });
  });

  test('base64url is strict and unpadded', () {
    expect(b64uEncode([0xfb, 0xff]), '-_8');
    expect(b64uDecode('-_8'), [0xfb, 0xff]);
    for (final s in ['-_8=', '+/8', 'A', '-_9']) {
      expect(() => b64uDecode(s), throwsFormatException, reason: s);
    }
  });
}
