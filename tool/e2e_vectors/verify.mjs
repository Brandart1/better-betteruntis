// Independent cross-check of test/sync/e2e_vectors_v2.json using @noble
// (not package:cryptography). Re-derives every value from the inputs, decrypts
// and re-encrypts every box, and parses the note plaintext with its own code.
//
//   cd tool/e2e_vectors && npm install && node verify.mjs
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { argon2id } from '@noble/hashes/argon2.js';
import { hkdf } from '@noble/hashes/hkdf.js';
import { hmac } from '@noble/hashes/hmac.js';
import { sha256 } from '@noble/hashes/sha2.js';
import { xchacha20poly1305 } from '@noble/ciphers/chacha.js';

const path = fileURLToPath(new URL('../../test/sync/e2e_vectors_v2.json', import.meta.url));
const v = JSON.parse(readFileSync(path, 'utf8'));

const enc = new TextEncoder();
const dec = new TextDecoder('utf-8', { fatal: true });
const hex = (s) => Uint8Array.from(s.match(/../g) ?? [], (h) => parseInt(h, 16));
const toHex = (b) => Buffer.from(b).toString('hex');
const b64u = (b) => Buffer.from(b).toString('base64url'); // no padding
const unb64u = (s) => new Uint8Array(Buffer.from(s, 'base64url'));
const concat = (...a) => {
  const out = new Uint8Array(a.reduce((n, x) => n + x.length, 0));
  let o = 0;
  for (const x of a) { out.set(x, o); o += x.length; }
  return out;
};

let checks = 0;
let failures = 0;
function eq(label, got, want) {
  checks++;
  if (got !== want) {
    failures++;
    console.error(`FAIL ${label}\n  got  ${got}\n  want ${want}`);
  }
}

const C = v.constants;
const VERSION = 1; // header boxes
const NOTE_VERSION = 2; // note blobs
eq('constants.headerBoxVersion', C.headerBoxVersion, VERSION);
eq('constants.noteBlobVersion', C.noteBlobVersion, NOTE_VERSION);
const sub = (ikm, info) => hkdf(sha256, ikm, undefined, enc.encode(info), 32);
const seal = (key, nonce, plain, aad, version = VERSION) =>
  concat(Uint8Array.of(version), nonce, xchacha20poly1305(key, nonce, aad).encrypt(plain));
function open(key, box, aad, version = VERSION) {
  if (box[0] !== version) throw new Error('box version');
  const nonce = box.subarray(1, 25);
  return xchacha20poly1305(key, nonce, aad).decrypt(box.subarray(25));
}

// --- Crockford base32 (own implementation), 128 bits + 2 zero bits
const ALPH = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
function recoveryCode(key) {
  let n = 0n;
  for (const b of key) n = (n << 8n) | BigInt(b);
  n <<= 2n;
  let s = '';
  for (let i = 0; i < 26; i++) { s = ALPH[Number(n & 31n)] + s; n >>= 5n; }
  return [s.slice(0, 5), s.slice(5, 10), s.slice(10, 15), s.slice(15, 20), s.slice(20)].join('-');
}

// --- KDF
for (const [i, k] of v.kdf.entries()) {
  const kek = argon2id(enc.encode(k.passphrase), hex(k.salt), { m: k.m, t: k.t, p: k.p, dkLen: 32, version: 0x13 });
  eq(`kdf[${i}].kek`, toHex(kek), k.kek);
}

// --- setup
const s = v.setup;
const r = s.random;
const dek = hex(r.dek);
const kek = argon2id(enc.encode(s.passphrase), hex(r.salt), { m: 19456, t: 2, p: 1, dkLen: 32 });
eq('setup.kek', toHex(kek), s.kek);
const kNoteKey = sub(dek, C.infoNoteKey);
const kNoteEnc = sub(dek, C.infoNoteEnc);
const kCheck = sub(dek, C.infoCheck);
const recKek = sub(hex(r.recoveryKey), C.infoRecoveryKek);
eq('subkeys.noteKey', toHex(kNoteKey), s.subkeys.noteKey);
eq('subkeys.noteEnc', toHex(kNoteEnc), s.subkeys.noteEnc);
eq('subkeys.check', toHex(kCheck), s.subkeys.check);
eq('subkeys.recoveryKek', toHex(recKek), s.subkeys.recoveryKek);
const authKey = sub(dek, C.infoHeaderAuth);
eq('subkeys.authKey', toHex(authKey), s.subkeys.authKey);
eq('authKeyB64', b64u(authKey), s.authKeyB64);
eq('authKeyB64.length', s.authKeyB64.length, 43);
eq('authHashB64', b64u(sha256(authKey)), s.authHashB64);

const h = s.header;
eq('header.version', h.version, 1);
eq('header.authHash', h.authHash, b64u(sha256(authKey)));
eq('header.authHash.length', h.authHash.length, 43);
eq('header.kdf', JSON.stringify(h.kdf), JSON.stringify({ alg: 'argon2id', m: 19456, t: 2, p: 1, salt: b64u(hex(r.salt)) }));
eq('header.wrappedDek', h.wrappedDek, b64u(seal(kek, hex(r.wrapNonce), dek, enc.encode(C.aadDekWrap))));
eq('header.wrappedDek opens', toHex(open(kek, unb64u(h.wrappedDek), enc.encode(C.aadDekWrap))), r.dek);
eq('header.check', h.check, b64u(seal(kCheck, hex(r.checkNonce), enc.encode(C.checkPlaintext), enc.encode(C.aadCheck))));
eq('header.check opens', dec.decode(open(kCheck, unb64u(h.check), enc.encode(C.aadCheck))), C.checkPlaintext);
eq('header.wrappedDekRecovery', h.wrappedDekRecovery, b64u(seal(recKek, hex(r.recoveryNonce), dek, enc.encode(C.aadDekWrap))));
eq('header.wrappedDekRecovery opens', toHex(open(recKek, unb64u(h.wrappedDekRecovery), enc.encode(C.aadDekWrap))), r.dek);
eq('recoveryCode', recoveryCode(hex(r.recoveryKey)), s.recoveryCode);

// wrong passphrase must fail authentication
{
  checks++;
  const bad = argon2id(enc.encode(s.passphrase + 'x'), hex(r.salt), { m: 19456, t: 2, p: 1, dkLen: 32 });
  let threw = false;
  try { open(bad, unb64u(h.wrappedDek), enc.encode(C.aadDekWrap)); } catch { threw = true; }
  if (!threw) { failures++; console.error('FAIL wrong passphrase opened wrappedDek'); }
}

// --- change passphrase
{
  const c = v.changePassphrase;
  const kek2 = argon2id(enc.encode(c.newPassphrase), hex(c.random.salt), { m: 19456, t: 2, p: 1, dkLen: 32 });
  eq('change.kek', toHex(kek2), v.kdf[1].kek);
  eq('change.salt', c.header.kdf.salt, b64u(hex(c.random.salt)));
  eq('change.wrappedDek', c.header.wrappedDek, b64u(seal(kek2, hex(c.random.wrapNonce), dek, enc.encode(C.aadDekWrap))));
  eq('change.check kept', c.header.check, h.check);
  eq('change.recovery kept', c.header.wrappedDekRecovery, h.wrappedDekRecovery);
  eq('change.authHash kept', c.header.authHash, h.authHash);
}

// --- server keys
const serverKey = (noteKey) => b64u(hmac(sha256, kNoteKey, enc.encode(noteKey)));
for (const [i, x] of v.serverKeys.entries()) {
  eq(`serverKeys[${i}]`, serverKey(x.noteKey), x.serverKey);
  eq(`serverKeys[${i}].length`, x.serverKey.length, 43);
}

// --- notes
function encodePlain(noteKey, exam, text) {
  const k = enc.encode(noteKey);
  const t = enc.encode(text);
  const used = 8 + k.length + t.length;
  const total = Math.ceil(used / C.padBlock) * C.padBlock;
  const out = new Uint8Array(total);
  const dv = new DataView(out.buffer);
  out[0] = 1;
  out[1] = exam ? 1 : 0;
  dv.setUint16(2, k.length, false);
  out.set(k, 4);
  dv.setUint32(4 + k.length, t.length, false);
  out.set(t, 8 + k.length);
  return out;
}
function decodePlain(p) {
  if (p.length % C.padBlock !== 0 || p[0] !== 1 || (p[1] & ~1) !== 0) throw new Error('layout');
  const dv = new DataView(p.buffer, p.byteOffset, p.byteLength);
  const kLen = dv.getUint16(2, false);
  const tLen = dv.getUint32(4 + kLen, false);
  const used = 8 + kLen + tLen;
  if (used > p.length || p.length - used >= C.padBlock) throw new Error('length');
  if (p.subarray(used).some((b) => b !== 0)) throw new Error('padding');
  return {
    noteKey: dec.decode(p.subarray(4, 4 + kLen)),
    exam: (p[1] & 1) === 1,
    text: dec.decode(p.subarray(8 + kLen, used)),
  };
}
// AAD v2: 0x02 | u64 BE updatedAt | u8 deleted | UTF-8 server key
function noteAad(sk, updatedAt, deleted) {
  const k = enc.encode(sk);
  const out = new Uint8Array(10 + k.length);
  out[0] = NOTE_VERSION;
  new DataView(out.buffer).setBigUint64(1, BigInt(updatedAt), false);
  out[9] = deleted ? 1 : 0;
  out.set(k, 10);
  return out;
}
function mustFail(label, f) {
  checks++;
  let threw = false;
  try { f(); } catch { threw = true; }
  if (!threw) { failures++; console.error(`FAIL ${label} did not fail`); }
}
for (const [i, n] of v.notes.entries()) {
  const sk = serverKey(n.noteKey);
  eq(`notes[${i}].serverKey`, n.serverKey, sk);
  const plain = encodePlain(n.noteKey, n.exam, n.text);
  eq(`notes[${i}].plaintext`, toHex(plain), n.plaintext);
  eq(`notes[${i}].paddedLength`, plain.length, n.paddedLength);
  const aad = noteAad(sk, n.updatedAt, n.deleted);
  eq(`notes[${i}].aad`, toHex(aad), n.aad);
  eq(`notes[${i}].blob`, b64u(seal(kNoteEnc, hex(n.nonce), plain, aad, NOTE_VERSION)), n.blob);
  const blob = unb64u(n.blob);
  eq(`notes[${i}].blob version`, blob[0], NOTE_VERSION);
  const got = decodePlain(open(kNoteEnc, blob, aad, NOTE_VERSION));
  eq(`notes[${i}].decrypt`, JSON.stringify(got), JSON.stringify({ noteKey: n.noteKey, exam: n.exam, text: n.text }));
  if (n.deleted) eq(`notes[${i}].tombstone`, JSON.stringify([got.exam, got.text]), JSON.stringify([false, '']));
  // AAD binding: another server key, updatedAt or deleted flag must fail
  mustFail(`notes[${i}] other server key`, () =>
    open(kNoteEnc, blob, noteAad(serverKey(n.noteKey + '!'), n.updatedAt, n.deleted), NOTE_VERSION));
  mustFail(`notes[${i}] updatedAt+1`, () =>
    open(kNoteEnc, blob, noteAad(sk, n.updatedAt + 1, n.deleted), NOTE_VERSION));
  if (n.updatedAt > 0) {
    mustFail(`notes[${i}] updatedAt-1`, () =>
      open(kNoteEnc, blob, noteAad(sk, n.updatedAt - 1, n.deleted), NOTE_VERSION));
  }
  mustFail(`notes[${i}] deleted flipped`, () =>
    open(kNoteEnc, blob, noteAad(sk, n.updatedAt, !n.deleted), NOTE_VERSION));
  // v1 AAD (0x01 | server key) must not open a v2 blob
  mustFail(`notes[${i}] v1 AAD`, () =>
    open(kNoteEnc, blob, concat(Uint8Array.of(1), enc.encode(sk)), NOTE_VERSION));
}

console.log(`${checks - failures}/${checks} checks passed`);
process.exit(failures ? 1 : 0);
