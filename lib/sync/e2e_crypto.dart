/// End-to-end encryption for synced notes (see docs/SYNC-PLAN.md,
/// "End-to-end encryption (optional)").
///
/// Pure Dart (no Flutter imports); uses package:cryptography, which runs on
/// Android, iOS and the web with the same algorithms.
///
/// ## Keys
///
/// * **DEK** – random 256-bit data key. Everything else is derived from it.
/// * **KEK** – `Argon2id(passphrase UTF-8 bytes, salt)`, m = 19 MiB
///   (19456 KiB), t = 2, p = 1, 16-byte salt, 32-byte output, Argon2 version
///   0x13. The passphrase is used exactly as typed (no trimming or Unicode
///   normalisation). The KEK wraps the DEK.
/// * **Recovery key** (optional) – random 128-bit key, shown once as a
///   26-character Crockford base32 code. Its wrapping key is
///   `HKDF-SHA256(ikm = recovery key, salt = none, info = "bbu-recovery-kek-v1",
///   L = 32)` (no Argon2: the key already has 128 bits of entropy).
/// * **Subkeys** of the DEK, each `HKDF-SHA256(ikm = DEK, salt = none,
///   info, L = 32)`:
///   * `bbu-note-key-v1` – HMAC-SHA256 key hiding note keys from the server,
///   * `bbu-note-enc-v1` – XChaCha20-Poly1305 key for note contents,
///   * `bbu-check-v1` – XChaCha20-Poly1305 key for the header `check` value,
///   * `bbu-header-auth-v1` – the **auth key**. The header stores
///     `authHash = base64url(SHA-256(auth key))`; changing (PATCH) or
///     deleting the header on the server requires presenting the auth key
///     itself (base64url, 43 chars), which proves possession of the DEK
///     without revealing it. The auth key never changes for a DEK (passphrase
///     changes and new recovery codes keep it).
///
/// ## Binary formats (all base64url without padding on the wire)
///
/// **Sealed box** (wrapped DEKs, `check`, note blobs):
/// `version (1 byte) | nonce (24 bytes) | ciphertext | tag (16 bytes)`,
/// XChaCha20-Poly1305 with a random 192-bit nonce. The version byte is `0x01`
/// for the header boxes and `0x02` for note blobs (v1 note blobs, which only
/// bound the server key, are refused with [E2eUnsupported]).
///
/// | box                   | key            | plaintext                 | AAD (bytes)                          |
/// |-----------------------|----------------|---------------------------|--------------------------------------|
/// | `wrappedDek`          | KEK            | DEK (32 bytes)            | UTF-8 `"bbu-dek-wrap-v1"`            |
/// | `wrappedDekRecovery`  | recovery KEK   | DEK (32 bytes)            | UTF-8 `"bbu-dek-wrap-v1"`            |
/// | `check`               | check subkey   | UTF-8 `"bbu-e2e-check-v1"`| UTF-8 `"bbu-check-v1"`               |
/// | note blob (v2)         | note-enc subkey| note plaintext (below)    | note AAD v2 (below)                  |
///
/// So `wrappedDek` is 73 bytes (98 chars) and `check` 57 bytes (76 chars).
///
/// **Note AAD v2** (binds the blob to the record metadata the server reports,
/// so the server can't move a blob to another note, flip a deletion or pass
/// off an old version as newer):
///
/// ```text
/// 0x02 | updatedAt (u64 big-endian, ms since epoch) | deleted (u8: 0 or 1)
///      | UTF-8 of the server key
/// ```
///
/// Tombstones (deleted notes) are encrypted records too: `deleted = 1`,
/// plaintext with `exam = false`, empty text and no homework.
///
/// **Server key:** `base64url(HMAC-SHA256(note-key subkey, UTF-8 note key))`,
/// 43 characters.
///
/// **Note plaintext, layout v1** (big-endian integers):
///
/// ```text
/// offset  size  field
/// 0       1     layout version = 0x01
/// 1       1     flags: bit 0 = exam, bit 1 = homework follows,
///               all other bits must be 0
/// 2       2     n = UTF-8 length of the note key (u16)
/// 4       n     note key (UTF-8)
/// 4+n     4     m = UTF-8 length of the text (u32)
/// 8+n     m     text (UTF-8)
/// only with flag bit 1:
/// 8+n+m   4     h = UTF-8 length of the homework (u32)
/// 12+n+m  h     homework (UTF-8)
/// ...     ...   zero bytes up to the next multiple of 256 (min. 256 total)
/// ```
///
/// Notes without homework are encoded without the homework part and flag
/// bit 1, exactly as before homework existed, so older app versions keep
/// reading them; notes with homework are unreadable for them (refused as
/// "bad flags", so they are never overwritten by such a device).
///
/// Decryption checks the AEAD tag (with the AAD built from the server key and
/// the server-reported `updatedAt` / `deleted`), the layout,
/// that the padding is all zeros and is shorter than 256 bytes, and that
/// `HMAC(note key) == server key` (constant time), so a blob can't be moved
/// to another note.
///
/// ## Header policy
///
/// Headers are accepted only with `version == 1`, `alg == "argon2id"`,
/// a 43-character `authHash`, a 16-byte salt and KDF parameters at least the defaults (m ≥ 19456,
/// t ≥ 2, p ≥ 1) and at most m ≤ 65536 (64 MiB), t ≤ 8, p ≤ 4. Weaker
/// parameters are refused (a malicious server must not be able to downgrade
/// new devices); absurdly high ones are refused so a server can't freeze the
/// app. Violations throw [E2eUnsupported]. The server enforces the same
/// KDF range.
///
/// ## Performance
///
/// Argon2id is the only slow step (once per unlock / passphrase change). All
/// functions are async. On native platforms package:cryptography runs the
/// Argon2 memory loop in a helper isolate; on the web it runs in chunks that
/// yield to the event loop, so the UI stays responsive (show a spinner).
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Source of random bytes. The default is [Random.secure]. Only tests should
/// pass their own (to reproduce test vectors).
typedef E2eRandomBytes = Uint8List Function(int length);

// ---------------------------------------------------------------- constants

/// Current header / header box / note plaintext layout version.
const int e2eVersion = 1;

/// Current note blob version (sealed box version byte and first AAD byte).
const int e2eNoteBlobVersion = 2;

/// Default (and minimum accepted) Argon2id memory in KiB (19 MiB).
const int e2eDefaultMemoryKiB = 19456;

/// Default (and minimum accepted) Argon2id iterations.
const int e2eDefaultIterations = 2;

/// Default (and minimum accepted) Argon2id parallelism.
const int e2eDefaultParallelism = 1;

/// Maximum accepted Argon2id memory in KiB (64 MiB).
const int e2eMaxMemoryKiB = 65536;

/// Maximum accepted Argon2id iterations.
const int e2eMaxIterations = 8;

/// Maximum accepted Argon2id parallelism.
const int e2eMaxParallelism = 4;

/// Minimum passphrase length (Unicode code points) for new passphrases.
const int e2eMinPassphraseLength = 8;

/// Plaintext padding block size in bytes.
const int e2ePadBlock = 256;

const int _saltLength = 16;
const int _keyLength = 32;
const int _recoveryKeyLength = 16;
const int _nonceLength = 24;
const int _tagLength = 16;
const int _maxSafeInt = 9007199254740991; // 2^53 - 1

const String _infoNoteKey = 'bbu-note-key-v1';
const String _infoNoteEnc = 'bbu-note-enc-v1';
const String _infoCheck = 'bbu-check-v1';
const String _infoRecovery = 'bbu-recovery-kek-v1';
const String _infoHeaderAuth = 'bbu-header-auth-v1';
const String _aadDekWrap = 'bbu-dek-wrap-v1';
const String _aadCheck = 'bbu-check-v1';
const String _checkPlaintext = 'bbu-e2e-check-v1';

// --------------------------------------------------------------- exceptions

/// Base class of all errors thrown by this library.
sealed class E2eException implements Exception {
  const E2eException(this.message);

  /// Developer-facing description (not localised).
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The passphrase or recovery code is wrong (or the wrapped key is damaged;
/// the two can't be told apart).
final class E2eWrongSecret extends E2eException {
  const E2eWrongSecret([super.message = 'wrong passphrase or recovery code']);
}

/// Data is malformed, was tampered with, or belongs to another key / note.
final class E2eCorrupt extends E2eException {
  const E2eCorrupt([super.message = 'corrupt or tampered data']);
}

/// Unknown version or algorithm, or KDF parameters outside the accepted
/// range (see the library docs).
final class E2eUnsupported extends E2eException {
  const E2eUnsupported(super.message);
}

// ------------------------------------------------------------------ header

/// Argon2id parameters of an [E2eHeader].
class E2eKdfParams {
  const E2eKdfParams({
    required this.salt,
    this.memoryKiB = e2eDefaultMemoryKiB,
    this.iterations = e2eDefaultIterations,
    this.parallelism = e2eDefaultParallelism,
  });

  /// Memory in KiB (`m`).
  final int memoryKiB;

  /// Iterations (`t`).
  final int iterations;

  /// Parallelism (`p`).
  final int parallelism;

  /// 16-byte random salt.
  final Uint8List salt;

  /// Throws [E2eUnsupported] if the parameters are outside the accepted range.
  void validate() {
    if (memoryKiB < e2eDefaultMemoryKiB || memoryKiB > e2eMaxMemoryKiB) {
      throw E2eUnsupported('argon2id m=$memoryKiB out of range');
    }
    if (iterations < e2eDefaultIterations || iterations > e2eMaxIterations) {
      throw E2eUnsupported('argon2id t=$iterations out of range');
    }
    if (parallelism < e2eDefaultParallelism ||
        parallelism > e2eMaxParallelism) {
      throw E2eUnsupported('argon2id p=$parallelism out of range');
    }
    if (memoryKiB < 8 * parallelism) {
      throw E2eUnsupported('argon2id m < 8*p');
    }
    if (salt.length != _saltLength) {
      throw const E2eUnsupported('argon2id salt must be 16 bytes');
    }
  }

  Map<String, Object?> toJson() => {
    'alg': 'argon2id',
    'm': memoryKiB,
    't': iterations,
    'p': parallelism,
    'salt': b64uEncode(salt),
  };

  /// Parses and validates. Throws [E2eUnsupported] or [E2eCorrupt].
  factory E2eKdfParams.fromJson(Object? json) {
    if (json is! Map) throw const E2eCorrupt('kdf: not an object');
    if (json['alg'] != 'argon2id') {
      throw E2eUnsupported('kdf alg ${json['alg']} not supported');
    }
    final m = json['m'], t = json['t'], p = json['p'], salt = json['salt'];
    if (m is! int || t is! int || p is! int || salt is! String) {
      throw const E2eCorrupt('kdf: bad fields');
    }
    final params = E2eKdfParams(
      memoryKiB: m,
      iterations: t,
      parallelism: p,
      salt: _b64uDecodeOrCorrupt(salt),
    );
    params.validate();
    return params;
  }
}

/// The E2E header stored on the server (readable by the server).
///
/// Wire format:
/// `{version, kdf: {alg: "argon2id", m, t, p, salt}, wrappedDek,
/// wrappedDekRecovery?, check, authHash}`; binary fields are base64url
/// without padding.
class E2eHeader {
  const E2eHeader({
    required this.kdf,
    required this.wrappedDek,
    required this.check,
    required this.authHash,
    this.wrappedDekRecovery,
    this.version = e2eVersion,
  });

  final int version;
  final E2eKdfParams kdf;

  /// Sealed box: the DEK under the passphrase KEK.
  final Uint8List wrappedDek;

  /// Sealed box: the DEK under the recovery KEK, or null without recovery.
  final Uint8List? wrappedDekRecovery;

  /// Sealed box: [_checkPlaintext] under the check subkey.
  final Uint8List check;

  /// SHA-256 of the auth key (32 bytes), see [E2eKeys.authHashB64].
  final Uint8List authHash;

  /// Whether a recovery code can unlock this header.
  bool get hasRecovery => wrappedDekRecovery != null;

  /// Throws [E2eUnsupported] / [E2eCorrupt] if the header can't be used.
  void validate() {
    if (version != e2eVersion) {
      throw E2eUnsupported('header version $version not supported');
    }
    kdf.validate();
    _checkBoxShape(wrappedDek, _keyLength, 'wrappedDek');
    final rec = wrappedDekRecovery;
    if (rec != null) _checkBoxShape(rec, _keyLength, 'wrappedDekRecovery');
    _checkBoxShape(check, utf8.encode(_checkPlaintext).length, 'check');
    if (authHash.length != _keyLength) {
      throw const E2eCorrupt('authHash: bad length');
    }
  }

  Map<String, Object?> toJson() => {
    'version': version,
    'kdf': kdf.toJson(),
    'wrappedDek': b64uEncode(wrappedDek),
    if (wrappedDekRecovery != null)
      'wrappedDekRecovery': b64uEncode(wrappedDekRecovery!),
    'check': b64uEncode(check),
    'authHash': b64uEncode(authHash),
  };

  /// Parses and validates. Throws [E2eUnsupported] or [E2eCorrupt].
  factory E2eHeader.fromJson(Object? json) {
    if (json is! Map) throw const E2eCorrupt('header: not an object');
    final version = json['version'];
    if (version is! int) throw const E2eCorrupt('header: bad version');
    if (version != e2eVersion) {
      throw E2eUnsupported('header version $version not supported');
    }
    final wrapped = json['wrappedDek'];
    final rec = json['wrappedDekRecovery'];
    final check = json['check'];
    final authHash = json['authHash'];
    if (wrapped is! String ||
        check is! String ||
        authHash is! String ||
        authHash.length != 43 ||
        (rec != null && rec is! String)) {
      throw const E2eCorrupt('header: bad fields');
    }
    final header = E2eHeader(
      version: version,
      kdf: E2eKdfParams.fromJson(json['kdf']),
      wrappedDek: _b64uDecodeOrCorrupt(wrapped),
      wrappedDekRecovery: rec == null
          ? null
          : _b64uDecodeOrCorrupt(rec as String),
      check: _b64uDecodeOrCorrupt(check),
      authHash: _b64uDecodeOrCorrupt(authHash),
    );
    header.validate();
    return header;
  }

  E2eHeader _copyWith({
    E2eKdfParams? kdf,
    Uint8List? wrappedDek,
    Uint8List? wrappedDekRecovery,
  }) => E2eHeader(
    version: version,
    kdf: kdf ?? this.kdf,
    wrappedDek: wrappedDek ?? this.wrappedDek,
    wrappedDekRecovery: wrappedDekRecovery ?? this.wrappedDekRecovery,
    check: check,
    authHash: authHash,
  );
}

// -------------------------------------------------------------------- keys

/// The unlocked DEK plus its derived subkeys. Create with [createE2e],
/// [unlockWithPassphrase], [unlockWithRecoveryCode] or [E2eKeys.fromDek]
/// (for a DEK cached in secure storage).
class E2eKeys {
  E2eKeys._(
    this._dek,
    this._noteKey,
    this._noteEnc,
    this._check,
    this._authKey,
    this._authHash,
  );

  final Uint8List _dek;
  final SecretKey _noteKey;
  final SecretKey _noteEnc;
  final SecretKey _check;
  final Uint8List _authKey;
  final Uint8List _authHash;

  /// Raw DEK bytes, for caching in secure storage. Handle with care.
  Uint8List get dekBytes => Uint8List.fromList(_dek);

  /// Header auth key, `HKDF-SHA256(DEK, info "bbu-header-auth-v1")` (32
  /// bytes). Sent to the server to change or delete the E2E header.
  Uint8List get authKey => Uint8List.fromList(_authKey);

  /// [authKey] as base64url without padding (43 characters).
  String get authKeyB64 => b64uEncode(_authKey);

  /// `base64url(SHA-256(authKey))` (43 characters), the header's `authHash`.
  String get authHashB64 => b64uEncode(_authHash);

  /// Derives the subkeys of a 32-byte [dek].
  static Future<E2eKeys> fromDek(List<int> dek) async {
    if (dek.length != _keyLength) {
      throw ArgumentError.value(dek.length, 'dek', 'must be 32 bytes');
    }
    final d = Uint8List.fromList(dek);
    final authKey = await _hkdf(d, _infoHeaderAuth);
    final authHash = await Sha256().hash(authKey);
    return E2eKeys._(
      d,
      SecretKey(await _hkdf(d, _infoNoteKey)),
      SecretKey(await _hkdf(d, _infoNoteEnc)),
      SecretKey(await _hkdf(d, _infoCheck)),
      authKey,
      Uint8List.fromList(authHash.bytes),
    );
  }

  /// Whether these keys belong to [header] (its `authHash` matches and its
  /// `check` decrypts). Use it to verify a cached DEK, e.g. after another
  /// device reset the account.
  Future<bool> matchesHeader(E2eHeader header) async {
    if (!_constantTimeEquals(_authHash, header.authHash)) return false;
    try {
      final plain = await _open(_check, header.check, utf8.encode(_aadCheck));
      return _constantTimeEquals(plain, utf8.encode(_checkPlaintext));
    } on E2eCorrupt {
      return false;
    }
  }
}

/// Result of [createE2e].
class E2eSetup {
  const E2eSetup(this.header, this.keys, this.recoveryCode);

  /// Upload with `PUT /api/sync/e2e`.
  final E2eHeader header;
  final E2eKeys keys;

  /// Formatted recovery code to show once, or null without recovery.
  final String? recoveryCode;
}

/// A decrypted note.
class E2eNote {
  const E2eNote({
    required this.noteKey,
    required this.exam,
    required this.text,
    this.homework = '',
  });

  final String noteKey;
  final bool exam;
  final String text;

  /// Empty for notes without homework (and those from older app versions).
  final String homework;
}

// ------------------------------------------------------------------- flows

/// Creates a new DEK and header protected by [passphrase] (at least
/// [e2eMinPassphraseLength] code points, else [ArgumentError]); with
/// [withRecovery] also a recovery code.
///
/// Random bytes are drawn in this order (relevant for test vectors only):
/// salt (16), DEK (32), wrappedDek nonce (24), check nonce (24), then with
/// recovery: recovery key (16), wrappedDekRecovery nonce (24).
Future<E2eSetup> createE2e(
  String passphrase, {
  bool withRecovery = true,
  E2eRandomBytes? random,
}) async {
  _checkNewPassphrase(passphrase);
  final rnd = random ?? _secureRandomBytes;
  final kdf = E2eKdfParams(salt: _take(rnd, _saltLength));
  final dek = _take(rnd, _keyLength);
  final kek = await deriveKek(passphrase, kdf);
  final wrappedDek = await _seal(
    SecretKey(kek),
    dek,
    utf8.encode(_aadDekWrap),
    _take(rnd, _nonceLength),
  );
  final keys = await E2eKeys.fromDek(dek);
  final check = await _seal(
    keys._check,
    utf8.encode(_checkPlaintext),
    utf8.encode(_aadCheck),
    _take(rnd, _nonceLength),
  );
  Uint8List? wrappedRec;
  String? code;
  if (withRecovery) {
    final recoveryKey = _take(rnd, _recoveryKeyLength);
    wrappedRec = await _wrapWithRecovery(dek, recoveryKey, rnd);
    code = formatRecoveryCode(recoveryKey);
  }
  final header = E2eHeader(
    kdf: kdf,
    wrappedDek: wrappedDek,
    wrappedDekRecovery: wrappedRec,
    check: check,
    authHash: Uint8List.fromList(keys._authHash),
  );
  return E2eSetup(header, keys, code);
}

/// Unwraps the DEK with [passphrase]. Throws [E2eWrongSecret] for a wrong
/// passphrase, [E2eCorrupt] if the header is inconsistent, [E2eUnsupported]
/// for unsupported headers.
Future<E2eKeys> unlockWithPassphrase(
  E2eHeader header,
  String passphrase,
) async {
  header.validate();
  final kek = await deriveKek(passphrase, header.kdf);
  return _unwrap(header, header.wrappedDek, kek);
}

/// Unwraps the DEK with a recovery [code] (tolerant parsing, see
/// [parseRecoveryCode]). Throws [E2eWrongSecret] for a wrong or malformed
/// code or if the header has no recovery wrap.
Future<E2eKeys> unlockWithRecoveryCode(E2eHeader header, String code) async {
  header.validate();
  final wrapped = header.wrappedDekRecovery;
  if (wrapped == null) {
    throw const E2eWrongSecret('header has no recovery code');
  }
  final Uint8List recoveryKey;
  try {
    recoveryKey = parseRecoveryCode(code);
  } on FormatException catch (e) {
    throw E2eWrongSecret('malformed recovery code: ${e.message}');
  }
  return _unwrap(header, wrapped, await _recoveryKek(recoveryKey));
}

/// Returns a new header where the DEK is wrapped with [newPassphrase] (fresh
/// salt, default KDF parameters). Notes stay valid; recovery wrap and check
/// are kept. Throws [E2eCorrupt] if [keys] don't belong to [header].
Future<E2eHeader> changePassphrase(
  E2eHeader header,
  E2eKeys keys,
  String newPassphrase, {
  E2eRandomBytes? random,
}) async {
  _checkNewPassphrase(newPassphrase);
  if (!await keys.matchesHeader(header)) {
    throw const E2eCorrupt('keys do not belong to this header');
  }
  final rnd = random ?? _secureRandomBytes;
  final kdf = E2eKdfParams(salt: _take(rnd, _saltLength));
  final kek = await deriveKek(newPassphrase, kdf);
  final wrapped = await _seal(
    SecretKey(kek),
    keys._dek,
    utf8.encode(_aadDekWrap),
    _take(rnd, _nonceLength),
  );
  return header._copyWith(kdf: kdf, wrappedDek: wrapped);
}

/// Returns a new header with a fresh recovery code (the old one stops
/// working) and the formatted code. Random order: recovery key (16), nonce
/// (24).
Future<(E2eHeader, String)> regenerateRecoveryCode(
  E2eHeader header,
  E2eKeys keys, {
  E2eRandomBytes? random,
}) async {
  if (!await keys.matchesHeader(header)) {
    throw const E2eCorrupt('keys do not belong to this header');
  }
  final rnd = random ?? _secureRandomBytes;
  final recoveryKey = _take(rnd, _recoveryKeyLength);
  final wrapped = await _wrapWithRecovery(keys._dek, recoveryKey, rnd);
  return (
    header._copyWith(wrappedDekRecovery: wrapped),
    formatRecoveryCode(recoveryKey),
  );
}

/// Argon2id KEK for [passphrase] (UTF-8, as typed). The slow step; exposed
/// for tests and benchmarks.
Future<Uint8List> deriveKek(String passphrase, E2eKdfParams kdf) async {
  final algo = Argon2id(
    memory: kdf.memoryKiB,
    iterations: kdf.iterations,
    parallelism: kdf.parallelism,
    hashLength: _keyLength,
  );
  final key = await algo.deriveKey(
    secretKey: SecretKey(utf8.encode(passphrase)),
    nonce: kdf.salt,
  );
  return Uint8List.fromList(await key.extractBytes());
}

// ------------------------------------------------------------------- notes

/// The server key for [noteKey]: base64url HMAC-SHA256, 43 characters.
Future<String> serverKey(E2eKeys keys, String noteKey) async =>
    b64uEncode(await _hmacKey(keys, noteKey));

/// Encrypts a note record. Returns the blob (base64url sealed box v2, see
/// library docs). Its AAD binds it to `serverKey(keys, noteKey)` and to
/// [updatedAt] (ms since epoch, 0..2^53-1) and [deleted], which must be the
/// values sent to the server with the blob. Tombstones: `deleted: true`,
/// `exam: false`, `text: ''`, `homework: ''`.
Future<String> encryptNote(
  E2eKeys keys, {
  required String noteKey,
  required bool exam,
  required String text,
  String homework = '',
  required int updatedAt,
  required bool deleted,
  E2eRandomBytes? random,
}) async {
  if (updatedAt < 0 || updatedAt > _maxSafeInt) {
    throw ArgumentError.value(updatedAt, 'updatedAt', 'out of range');
  }
  final sk = await serverKey(keys, noteKey);
  final plain = encodeNotePlaintext(
    noteKey: noteKey,
    exam: exam,
    text: text,
    homework: homework,
  );
  final nonce = _take(random ?? _secureRandomBytes, _nonceLength);
  final box = await _seal(
    keys._noteEnc,
    plain,
    noteAad(serverKey: sk, updatedAt: updatedAt, deleted: deleted),
    nonce,
    version: e2eNoteBlobVersion,
  );
  return b64uEncode(box);
}

/// Decrypts a note [blob] stored under [serverKey] with the server-reported
/// [updatedAt] and [deleted]. Throws [E2eCorrupt] if the blob is malformed,
/// tampered with, from another key, or doesn't match the server key,
/// `updatedAt` or `deleted` it was encrypted with; [E2eUnsupported] for
/// another blob version (including v1).
Future<E2eNote> decryptNote(
  E2eKeys keys,
  String serverKey,
  String blob, {
  required int updatedAt,
  required bool deleted,
}) async {
  final box = _b64uDecodeOrCorrupt(blob);
  if (box.length < 1 + _nonceLength + _tagLength) {
    throw const E2eCorrupt('box too short');
  }
  if (box[0] != e2eNoteBlobVersion) {
    throw E2eUnsupported('note blob version ${box[0]} not supported');
  }
  if (updatedAt < 0 || updatedAt > _maxSafeInt) {
    throw const E2eCorrupt('updatedAt out of range');
  }
  final plain = await _open(
    keys._noteEnc,
    box,
    noteAad(serverKey: serverKey, updatedAt: updatedAt, deleted: deleted),
    version: e2eNoteBlobVersion,
  );
  final note = decodeNotePlaintext(plain);
  final expected = await _hmacKey(keys, note.noteKey);
  final given = _b64uDecodeOrNull(serverKey);
  if (given == null || !_constantTimeEquals(expected, given)) {
    throw const E2eCorrupt('note key does not match server key');
  }
  return note;
}

/// Note AAD v2: `0x02 | u64 BE updatedAt | u8 deleted | UTF-8 serverKey`.
/// Exposed for tests.
Uint8List noteAad({
  required String serverKey,
  required int updatedAt,
  required bool deleted,
}) {
  final k = utf8.encode(serverKey);
  final out = Uint8List(10 + k.length);
  final bd = ByteData.sublistView(out);
  out[0] = e2eNoteBlobVersion;
  // Two u32 halves: ByteData.setUint64 is not supported on the web.
  bd.setUint32(1, updatedAt ~/ 0x100000000);
  bd.setUint32(5, updatedAt % 0x100000000);
  out[9] = deleted ? 1 : 0;
  out.setRange(10, out.length, k);
  return out;
}

/// Encodes the v1 note plaintext (padded); the homework part only when
/// [homework] isn't empty. Exposed for tests.
Uint8List encodeNotePlaintext({
  required String noteKey,
  required bool exam,
  required String text,
  String homework = '',
}) {
  final k = utf8.encode(noteKey);
  final t = utf8.encode(text);
  final h = utf8.encode(homework);
  if (k.length > 0xFFFF) {
    throw ArgumentError.value(noteKey, 'noteKey', 'too long');
  }
  final textEnd = 8 + k.length + t.length;
  final used = h.isEmpty ? textEnd : textEnd + 4 + h.length;
  final total = ((used + e2ePadBlock - 1) ~/ e2ePadBlock) * e2ePadBlock;
  final out = Uint8List(total);
  final bd = ByteData.sublistView(out);
  out[0] = e2eVersion;
  out[1] = (exam ? 1 : 0) | (h.isEmpty ? 0 : 2);
  bd.setUint16(2, k.length);
  out.setRange(4, 4 + k.length, k);
  bd.setUint32(4 + k.length, t.length);
  out.setRange(8 + k.length, textEnd, t);
  if (h.isNotEmpty) {
    bd.setUint32(textEnd, h.length);
    out.setRange(textEnd + 4, used, h);
  }
  return out;
}

/// Decodes a v1 note plaintext. Throws [E2eCorrupt]. Exposed for tests.
E2eNote decodeNotePlaintext(Uint8List p) {
  if (p.isEmpty || p.length % e2ePadBlock != 0) {
    throw const E2eCorrupt('plaintext: bad length');
  }
  if (p[0] != e2eVersion) throw const E2eCorrupt('plaintext: bad version');
  if (p[1] & ~3 != 0) throw const E2eCorrupt('plaintext: bad flags');
  final hasHomework = p[1] & 2 != 0;
  final bd = ByteData.sublistView(p);
  final kLen = bd.getUint16(2);
  if (8 + kLen > p.length) throw const E2eCorrupt('plaintext: bad key length');
  final tLen = bd.getUint32(4 + kLen);
  final textEnd = 8 + kLen + tLen;
  var used = textEnd;
  if (hasHomework) {
    if (textEnd + 4 > p.length) {
      throw const E2eCorrupt('plaintext: bad text length');
    }
    used = textEnd + 4 + bd.getUint32(textEnd);
  }
  if (used > p.length || p.length - used >= e2ePadBlock) {
    throw E2eCorrupt(
      hasHomework
          ? 'plaintext: bad homework length'
          : 'plaintext: bad text length',
    );
  }
  for (var i = used; i < p.length; i++) {
    if (p[i] != 0) throw const E2eCorrupt('plaintext: bad padding');
  }
  try {
    return E2eNote(
      noteKey: utf8.decode(Uint8List.sublistView(p, 4, 4 + kLen)),
      exam: p[1] & 1 == 1,
      text: utf8.decode(Uint8List.sublistView(p, 8 + kLen, textEnd)),
      homework: hasHomework
          ? utf8.decode(Uint8List.sublistView(p, textEnd + 4, used))
          : '',
    );
  } on FormatException {
    throw const E2eCorrupt('plaintext: bad UTF-8');
  }
}

// ----------------------------------------------------------- recovery code

const String _crockford = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

/// Formats a 16-byte recovery key as 26 Crockford base32 characters
/// (128 bits MSB first, followed by 2 zero bits), grouped
/// `XXXXX-XXXXX-XXXXX-XXXXX-XXXXXX`.
String formatRecoveryCode(List<int> key) {
  if (key.length != _recoveryKeyLength) {
    throw ArgumentError.value(key.length, 'key', 'must be 16 bytes');
  }
  var acc = BigInt.zero;
  for (final b in key) {
    acc = (acc << 8) | BigInt.from(b);
  }
  acc = acc << 2;
  final chars = List.filled(26, '');
  for (var i = 25; i >= 0; i--) {
    chars[i] = _crockford[(acc & BigInt.from(31)).toInt()];
    acc = acc >> 5;
  }
  final s = chars.join();
  return '${s.substring(0, 5)}-${s.substring(5, 10)}-${s.substring(10, 15)}-'
      '${s.substring(15, 20)}-${s.substring(20)}';
}

/// Parses a recovery code. Tolerant: case-insensitive; spaces, dashes,
/// underscores and dots are ignored; `I`/`L` read as `1`, `O` as `0`.
/// Throws [FormatException] if the result isn't 26 valid characters with
/// zero trailing bits.
Uint8List parseRecoveryCode(String code) {
  final buf = StringBuffer();
  for (final r in code.toUpperCase().runes) {
    final c = String.fromCharCode(r);
    if (c == ' ' || c == '-' || c == '_' || c == '.' || c == '\t') continue;
    buf.write(switch (c) {
      'I' || 'L' => '1',
      'O' => '0',
      _ => c,
    });
  }
  final s = buf.toString();
  if (s.length != 26) {
    throw FormatException('recovery code must have 26 characters', code);
  }
  var acc = BigInt.zero;
  for (var i = 0; i < s.length; i++) {
    final v = _crockford.indexOf(s[i]);
    if (v < 0) throw FormatException('invalid character ${s[i]}', code);
    acc = (acc << 5) | BigInt.from(v);
  }
  if (acc & BigInt.from(3) != BigInt.zero) {
    throw FormatException('invalid recovery code', code);
  }
  acc = acc >> 2;
  final out = Uint8List(_recoveryKeyLength);
  for (var i = _recoveryKeyLength - 1; i >= 0; i--) {
    out[i] = (acc & BigInt.from(255)).toInt();
    acc = acc >> 8;
  }
  return out;
}

// ----------------------------------------------------------------- base64url

/// base64url without padding.
String b64uEncode(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

/// Strict base64url-without-padding decoding; throws [FormatException].
Uint8List b64uDecode(String s) {
  if (!RegExp(r'^[A-Za-z0-9_-]*$').hasMatch(s) || s.length % 4 == 1) {
    throw FormatException('invalid base64url', s);
  }
  final bytes = base64Url.decode(s.padRight((s.length + 3) & ~3, '='));
  if (b64uEncode(bytes) != s) {
    throw FormatException('non-canonical base64url', s);
  }
  return bytes;
}

// ----------------------------------------------------------------- private

final Random _secure = Random.secure();

Uint8List _secureRandomBytes(int length) {
  final out = Uint8List(length);
  for (var i = 0; i < length; i++) {
    out[i] = _secure.nextInt(256);
  }
  return out;
}

Uint8List _take(E2eRandomBytes rnd, int length) {
  final b = rnd(length);
  if (b.length != length) {
    throw StateError('random source returned ${b.length} bytes');
  }
  return Uint8List.fromList(b);
}

void _checkNewPassphrase(String passphrase) {
  if (passphrase.runes.length < e2eMinPassphraseLength) {
    throw ArgumentError.value(
      '***',
      'passphrase',
      'at least $e2eMinPassphraseLength characters',
    );
  }
}

Future<Uint8List> _hkdf(List<int> ikm, String info) async {
  final key = await Hkdf(
    hmac: Hmac.sha256(),
    outputLength: _keyLength,
  ).deriveKey(secretKey: SecretKey(ikm), info: utf8.encode(info));
  return Uint8List.fromList(await key.extractBytes());
}

Future<Uint8List> _recoveryKek(List<int> recoveryKey) =>
    _hkdf(recoveryKey, _infoRecovery);

Future<Uint8List> _wrapWithRecovery(
  Uint8List dek,
  Uint8List recoveryKey,
  E2eRandomBytes rnd,
) async => _seal(
  SecretKey(await _recoveryKek(recoveryKey)),
  dek,
  utf8.encode(_aadDekWrap),
  _take(rnd, _nonceLength),
);

Future<E2eKeys> _unwrap(
  E2eHeader header,
  Uint8List wrapped,
  List<int> kek,
) async {
  final Uint8List dek;
  try {
    dek = await _open(SecretKey(kek), wrapped, utf8.encode(_aadDekWrap));
  } on E2eCorrupt {
    throw const E2eWrongSecret();
  }
  if (dek.length != _keyLength) throw const E2eCorrupt('bad DEK length');
  final keys = await E2eKeys.fromDek(dek);
  if (!await keys.matchesHeader(header)) {
    throw const E2eCorrupt('check / authHash do not match the unwrapped key');
  }
  return keys;
}

Future<Uint8List> _hmacKey(E2eKeys keys, String noteKey) async {
  final mac = await Hmac.sha256().calculateMac(
    utf8.encode(noteKey),
    secretKey: keys._noteKey,
  );
  return Uint8List.fromList(mac.bytes);
}

final _aead = Xchacha20.poly1305Aead();

Future<Uint8List> _seal(
  SecretKey key,
  List<int> plain,
  List<int> aad,
  List<int> nonce, {
  int version = e2eVersion,
}) async {
  final box = await _aead.encrypt(
    plain,
    secretKey: key,
    nonce: nonce,
    aad: aad,
  );
  return Uint8List.fromList([
    version,
    ...nonce,
    ...box.cipherText,
    ...box.mac.bytes,
  ]);
}

/// Opens a sealed box; any failure is [E2eCorrupt].
Future<Uint8List> _open(
  SecretKey key,
  Uint8List box,
  List<int> aad, {
  int version = e2eVersion,
}) async {
  if (box.length < 1 + _nonceLength + _tagLength) {
    throw const E2eCorrupt('box too short');
  }
  if (box[0] != version) throw const E2eCorrupt('box: unknown version');
  final nonce = box.sublist(1, 1 + _nonceLength);
  final ct = box.sublist(1 + _nonceLength, box.length - _tagLength);
  final tag = box.sublist(box.length - _tagLength);
  try {
    final plain = await _aead.decrypt(
      SecretBox(ct, nonce: nonce, mac: Mac(tag)),
      secretKey: key,
      aad: aad,
    );
    return Uint8List.fromList(plain);
  } on SecretBoxAuthenticationError {
    throw const E2eCorrupt('authentication failed');
  }
}

void _checkBoxShape(Uint8List box, int plainLength, String name) {
  if (box.length != 1 + _nonceLength + plainLength + _tagLength ||
      box[0] != e2eVersion) {
    throw E2eCorrupt('$name: bad length or version');
  }
}

Uint8List _b64uDecodeOrCorrupt(String s) {
  final b = _b64uDecodeOrNull(s);
  if (b == null) throw const E2eCorrupt('invalid base64url');
  return b;
}

Uint8List? _b64uDecodeOrNull(String s) {
  try {
    return b64uDecode(s);
  } on FormatException {
    return null;
  }
}

/// Compares without an early exit (length is not secret).
bool _constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}
