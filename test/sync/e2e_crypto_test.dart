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
    File('test/sync/e2e_vectors_v2.json').readAsStringSync(),
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

    test('auth key and hash', () async {
      final sub = setupV['subkeys'] as Map<String, dynamic>;
      expect(toHex(keys.authKey), sub['authKey']);
      expect(keys.authKeyB64, setupV['authKeyB64']);
      expect(keys.authKeyB64.length, 43);
      expect(keys.authHashB64, setupV['authHashB64']);
      expect(keys.authHashB64, headerJson['authHash']);
      final h = await Sha256().hash(keys.authKey);
      expect(keys.authHashB64, b64uEncode(h.bytes));
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
        final updatedAt = n['updatedAt'] as int;
        final deleted = n['deleted'] as bool;
        final sk = n['serverKey'] as String;
        expect(
          toHex(noteAad(serverKey: sk, updatedAt: updatedAt, deleted: deleted)),
          n['aad'],
        );
        final plain = encodeNotePlaintext(noteKey: key, exam: exam, text: text);
        expect(toHex(plain), n['plaintext']);
        expect(plain.length, n['paddedLength']);
        final blob = await encryptNote(
          keys,
          noteKey: key,
          exam: exam,
          text: text,
          updatedAt: updatedAt,
          deleted: deleted,
          random: queue([n['nonce'] as String]),
        );
        expect(blob, n['blob']);
        final note = await decryptNote(
          keys,
          sk,
          blob,
          updatedAt: updatedAt,
          deleted: deleted,
        );
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
        updatedAt: 1763370000000,
        deleted: false,
      );
      final sk = await serverKey(k, 'k1');
      final note = await decryptNote(
        k,
        sk,
        blob,
        updatedAt: 1763370000000,
        deleted: false,
      );
      expect((note.noteKey, note.exam, note.text), ('k1', true, 'Hallo 👋'));
      // Same note encrypts differently each time (random nonce).
      final blob2 = await encryptNote(
        k,
        noteKey: 'k1',
        exam: true,
        text: 'Hallo 👋',
        updatedAt: 1763370000000,
        deleted: false,
      );
      expect(blob2, isNot(blob));
      expect(await serverKey(setup.keys, 'k1'), sk);
      expect(k.authKeyB64, setup.keys.authKeyB64);
      expect(h.toJson()['authHash'], setup.keys.authHashB64);
    });

    test('tombstone round trip', () async {
      final sk = await serverKey(keys, 'gone');
      final blob = await encryptNote(
        keys,
        noteKey: 'gone',
        exam: false,
        text: '',
        updatedAt: 1763456400000,
        deleted: true,
      );
      final note = await decryptNote(
        keys,
        sk,
        blob,
        updatedAt: 1763456400000,
        deleted: true,
      );
      expect((note.noteKey, note.exam, note.text), ('gone', false, ''));
      // A server can't turn the tombstone back into a live note.
      await expectLater(
        decryptNote(keys, sk, blob, updatedAt: 1763456400000, deleted: false),
        throwsA(isA<E2eCorrupt>()),
      );
    });

    test('updatedAt range', () async {
      for (final t in [-1, 9007199254740992]) {
        expect(
          () => encryptNote(
            keys,
            noteKey: 'k',
            exam: false,
            text: '',
            updatedAt: t,
            deleted: false,
          ),
          throwsArgumentError,
        );
      }
      final blob = await encryptNote(
        keys,
        noteKey: 'k',
        exam: false,
        text: '',
        updatedAt: 0,
        deleted: false,
      );
      await expectLater(
        decryptNote(
          keys,
          await serverKey(keys, 'k'),
          blob,
          updatedAt: -1,
          deleted: false,
        ),
        throwsA(isA<E2eCorrupt>()),
      );
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
        updatedAt: 5,
        deleted: false,
      );
      final h2 = await changePassphrase(header, keys, 'new passphrase 123');
      expect(h2.kdf.salt, isNot(header.kdf.salt));
      expect(h2.authHash, header.authHash);
      await expectLater(
        unlockWithPassphrase(h2, passphrase),
        throwsA(isA<E2eWrongSecret>()),
      );
      final k2 = await unlockWithPassphrase(h2, 'new passphrase 123');
      expect(
        (await decryptNote(k2, sk, blob, updatedAt: 5, deleted: false)).text,
        't',
      );
      // The auth key is a function of the DEK only.
      expect(k2.authKeyB64, keys.authKeyB64);
      expect(await k2.matchesHeader(h2), isTrue);
      // Recovery code still works on the new header.
      final k3 = await unlockWithRecoveryCode(h2, recoveryCode);
      expect(k3.dekBytes, keys.dekBytes);
    });

    test('regenerating the recovery code', () async {
      final (h2, code) = await regenerateRecoveryCode(header, keys);
      expect(code, isNot(recoveryCode));
      expect(h2.toJson()['authHash'], headerJson['authHash']);
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

  group('auth hash', () {
    test('matchesHeader rejects a wrong authHash', () async {
      expect(await keys.matchesHeader(header), isTrue);
      final wrong = E2eHeader.fromJson({
        ...headerJson,
        'authHash': flip(headerJson['authHash'] as String, 0),
      });
      expect(await keys.matchesHeader(wrong), isFalse);
      await expectLater(
        unlockWithPassphrase(wrong, passphrase),
        throwsA(isA<E2eCorrupt>()),
      );
      await expectLater(
        changePassphrase(wrong, keys, 'whatever123'),
        throwsA(isA<E2eCorrupt>()),
      );
      await expectLater(
        regenerateRecoveryCode(wrong, keys),
        throwsA(isA<E2eCorrupt>()),
      );
    });
  });

  group('tampering', () {
    const t = 1763370000123;
    late String sk;
    late String blob;
    Future<E2eNote> dec(
      String b, {
      String? key,
      int updatedAt = t,
      bool deleted = false,
      E2eKeys? k,
    }) => decryptNote(
      k ?? keys,
      key ?? sk,
      b,
      updatedAt: updatedAt,
      deleted: deleted,
    );
    setUpAll(() async {
      sk = await serverKey(keys, '2026-11-17|3|MATH');
      blob = await encryptNote(
        keys,
        noteKey: '2026-11-17|3|MATH',
        exam: true,
        text: 'SA',
        updatedAt: t,
        deleted: false,
      );
    });

    test('flipped bits anywhere', () async {
      final len = b64uDecode(blob).length;
      for (final i in [1, 24, 25, 100, len - 17, len - 1]) {
        await expectLater(
          dec(flip(blob, i)),
          throwsA(isA<E2eCorrupt>()),
          reason: 'byte $i',
        );
      }
      // Version byte 0x02 -> 0x03.
      await expectLater(dec(flip(blob, 0)), throwsA(isA<E2eUnsupported>()));
    });

    test('truncated / garbage blobs', () async {
      for (final b in ['', 'Ag', blob.substring(0, 50), '!!!!', '$blob=']) {
        await expectLater(dec(b), throwsA(isA<E2eCorrupt>()), reason: b);
      }
    });

    test('blob moved to another server key (AAD)', () async {
      final other = await serverKey(keys, 'other');
      await expectLater(dec(blob, key: other), throwsA(isA<E2eCorrupt>()));
    });

    test('server-reported updatedAt / deleted must match (AAD)', () async {
      expect((await dec(blob)).text, 'SA');
      for (final u in [t - 1, t + 1, 0, t + 0x100000000]) {
        await expectLater(
          dec(blob, updatedAt: u),
          throwsA(isA<E2eCorrupt>()),
          reason: '$u',
        );
      }
      await expectLater(dec(blob, deleted: true), throwsA(isA<E2eCorrupt>()));
    });

    test('v1 blobs are rejected', () async {
      // A well-formed v1 blob (version 0x01, AAD 0x01 | server key).
      final kEnc = hex(
        (setupV['subkeys'] as Map<String, dynamic>)['noteEnc'] as String,
      );
      final nonce = Uint8List(24);
      final box = await Xchacha20.poly1305Aead().encrypt(
        encodeNotePlaintext(noteKey: '2026-11-17|3|MATH', exam: true, text: ''),
        secretKey: SecretKey(kEnc),
        nonce: nonce,
        aad: [1, ...utf8.encode(sk)],
      );
      final v1 = b64uEncode([1, ...nonce, ...box.cipherText, ...box.mac.bytes]);
      await expectLater(dec(v1), throwsA(isA<E2eUnsupported>()));
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
        aad: noteAad(serverKey: fake, updatedAt: t, deleted: false),
      );
      final blobFake = b64uEncode([
        2,
        ...nonce,
        ...box.cipherText,
        ...box.mac.bytes,
      ]);
      // Sanity: the same construction with the right key decrypts.
      final good = await Xchacha20.poly1305Aead().encrypt(
        encodeNotePlaintext(noteKey: 'fake', exam: false, text: ''),
        secretKey: SecretKey(kEnc),
        nonce: nonce,
        aad: noteAad(serverKey: fake, updatedAt: t, deleted: false),
      );
      final blobGood = b64uEncode([
        2,
        ...nonce,
        ...good.cipherText,
        ...good.mac.bytes,
      ]);
      expect((await dec(blobGood, key: fake)).noteKey, 'fake');
      await expectLater(dec(blobFake, key: fake), throwsA(isA<E2eCorrupt>()));
    });

    test('another DEK', () async {
      final other = await E2eKeys.fromDek(List.filled(32, 7));
      await expectLater(dec(blob, k: other), throwsA(isA<E2eCorrupt>()));
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
        mod((p) => p[1] = 5), // flags (unknown bit 2)
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

  group('homework', () {
    test('round trip; without homework the layout is unchanged', () {
      final plain = encodeNotePlaintext(
        noteKey: 'acc|2026-11-16|0800|1|2',
        exam: true,
        text: 'Kapitel 3',
        homework: 'S. 12 Nr. 3 – äö 🧮',
      );
      expect(plain[1], 3);
      final n = decodeNotePlaintext(plain);
      expect(n.noteKey, 'acc|2026-11-16|0800|1|2');
      expect(n.exam, isTrue);
      expect(n.text, 'Kapitel 3');
      expect(n.homework, 'S. 12 Nr. 3 – äö 🧮');

      // Empty homework: exactly the bytes older app versions write/read.
      final without = encodeNotePlaintext(noteKey: 'k', exam: false, text: 'x');
      expect(without[1], 0);
      expect(
        encodeNotePlaintext(noteKey: 'k', exam: false, text: 'x', homework: ''),
        without,
      );
      expect(decodeNotePlaintext(without).homework, '');

      final only = decodeNotePlaintext(
        encodeNotePlaintext(noteKey: 'k', exam: false, text: '', homework: 'h'),
      );
      expect((only.text, only.homework, only.exam), ('', 'h', false));
    });

    test('layout validation', () {
      final good = encodeNotePlaintext(
        noteKey: 'k',
        exam: false,
        text: 'x',
        homework: 'hw',
      );
      expect(decodeNotePlaintext(good).homework, 'hw');
      Uint8List mod(void Function(Uint8List) f) {
        final c = Uint8List.fromList(good);
        f(c);
        return c;
      }

      for (final bad in [
        mod((p) => p[10] = 255), // homework length past end
        mod((p) => p[13] = 1), // homework shorter: padding not zero
        mod((p) => p[14] = 0xff), // invalid UTF-8 in homework
        mod((p) => p[1] = 6), // unknown flag bit 2
      ]) {
        expect(() => decodeNotePlaintext(bad), throwsA(isA<E2eCorrupt>()));
      }
    });

    test('encrypt/decrypt carries homework', () async {
      final keys = await E2eKeys.fromDek(List.filled(32, 3));
      final blob = await encryptNote(
        keys,
        noteKey: 'acc|2026-11-16|0800|1|2',
        exam: false,
        text: '',
        homework: 'Essay',
        updatedAt: 42,
        deleted: false,
      );
      final n = await decryptNote(
        keys,
        await serverKey(keys, 'acc|2026-11-16|0800|1|2'),
        blob,
        updatedAt: 42,
        deleted: false,
      );
      expect(n.homework, 'Essay');
      expect(n.text, '');
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
        withKdf({'m': 65537}), // above maximum
        withKdf({'t': 9}),
        withKdf({'p': 5}),
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
        E2eHeader.fromJson(withKdf({'m': 65536, 't': 8, 'p': 4})).kdf.memoryKiB,
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
        {...headerJson}..remove('authHash'),
        {...headerJson, 'authHash': 5},
        {...headerJson, 'authHash': b64uEncode(Uint8List(31))},
        {...headerJson, 'authHash': '${headerJson['authHash']}A'},
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
        authHash: header.authHash,
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
