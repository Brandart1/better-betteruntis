/// Contract between the sync engine (lib/sync/sync_engine.dart) and the sync
/// UI (lib/ui/sync/). Optional sync of the user's lesson notes (custom exams,
/// lesson details; lib/core/lesson_notes.dart) through the Cloudflare Worker,
/// see docs/SYNC-PLAN.md. Sync is per app account (each account is its own
/// WebUntis identity on the server).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where sync stands for one app account.
enum SyncPhase {
  /// Never turned on (or turned off).
  off,

  /// On and working (or idle between syncs).
  on,

  /// E2E is on for this identity and this device has no key yet: the user
  /// must enter the passphrase or recovery code ([SyncController.unlock]).
  locked,

  /// The server no longer accepts this device's session (expired, or sync
  /// was turned off / reset on another device). Local notes are untouched;
  /// the user decides whether to turn sync on again.
  signedOut,
}

/// Who the server thinks this account is (shown in the sync settings so
/// deletion requests can be matched).
class SyncIdentity {
  const SyncIdentity({
    required this.host,
    required this.school,
    required this.userId,
    this.epoch,
  });
  final String host;
  final String school;
  final String userId;

  /// Random id of this incarnation of the identity on the server: it
  /// changes when the identity is deleted (sync turned off or reset) and
  /// created again. Null if the server didn't send one.
  final String? epoch;

  @override
  String toString() => '$school · $userId · $host';
}

/// State of sync for one app account.
class SyncAccountState {
  const SyncAccountState({
    required this.accountId,
    this.phase = SyncPhase.off,
    this.identity,
    this.e2e = false,
    this.hasRecoveryCode = false,
    this.lastSync,
    this.syncing = false,
    this.error,
    this.e2eSetupPending = false,
  });

  final String accountId;
  final SyncPhase phase;
  final SyncIdentity? identity;

  /// End-to-end encryption is on for this identity.
  final bool e2e;

  /// The E2E header has a recovery-code wrap (UI: "Create recovery code" vs
  /// "New recovery code").
  final bool hasRecoveryCode;
  final DateTime? lastSync;

  /// A sync is running right now.
  final bool syncing;

  /// Last error as user-facing text (null after a successful sync).
  final String? error;

  /// Turning on E2E started on this device and finishes at the next sync
  /// (the UI doesn't offer to turn it on again meanwhile).
  final bool e2eSetupPending;

  bool get enabled => phase != SyncPhase.off;
}

/// What the user chose when turning sync on.
class SyncEnableOptions {
  const SyncEnableOptions({this.passphrase, this.withRecoveryCode = true});

  /// Non-null: turn on end-to-end encryption with this passphrase
  /// (min. 8 characters). Ignored if the server already has E2E for this
  /// identity (then [SyncController.unlock] is needed instead).
  final String? passphrase;
  final bool withRecoveryCode;
}

/// Result of turning sync or E2E on.
class SyncEnableResult {
  const SyncEnableResult({required this.state, this.recoveryCode});
  final SyncAccountState state;

  /// Shown to the user once (E2E with recovery code only).
  final String? recoveryCode;
}

/// Thrown by [SyncController] methods with a user-facing [message].
class SyncException implements Exception {
  const SyncException(this.message, {this.wrongSecret = false});
  final String message;

  /// The passphrase / recovery code was wrong (UI keeps the dialog open).
  final bool wrongSecret;
  @override
  String toString() => message;
}

/// The sync engine as seen by the UI: a Riverpod notifier whose state is the
/// [SyncAccountState] per account id (accounts missing from the map are
/// [SyncPhase.off]). Implemented by `SyncEngine`; tests override
/// [syncControllerProvider] with a fake subclass.
abstract class SyncController extends Notifier<Map<String, SyncAccountState>> {
  /// State of [accountId] ([SyncPhase.off] if unknown).
  SyncAccountState stateOf(String accountId) =>
      state[accountId] ?? SyncAccountState(accountId: accountId);

  /// Whether this build can sync at all (the phone apps need a sync server
  /// URL at build time). Unavailable: the UI says so instead of offering
  /// the opt-in, and [enable] throws.
  bool get available => true;

  /// Turns sync on for [accountId]: logs in to the sync server with the
  /// account's WebUntis token, optionally sets up E2E, then syncs.
  /// If the server already has E2E for this identity, the result's phase is
  /// [SyncPhase.locked].
  Future<SyncEnableResult> enable(String accountId, SyncEnableOptions options);

  /// Unlocks E2E on this device with the passphrase or the recovery code.
  Future<SyncAccountState> unlock(String accountId, String passphraseOrCode);

  /// Syncs now (pull then push). Never throws (errors end up in the
  /// state). No-op when off or signed out; when locked it only checks
  /// whether E2E is still on (turned off elsewhere → syncs in plaintext).
  Future<SyncAccountState> syncNow(String accountId);

  /// Turns sync off: deletes everything about this identity on the server
  /// (notes, E2E header, sessions); local notes stay.
  Future<void> disable(String accountId);

  /// Forgets this device's session only (server data stays), e.g. before
  /// removing the account from the app.
  Future<void> signOutDevice(String accountId);

  /// Turns E2E on for an account that syncs in plaintext: resets the server
  /// data and uploads everything encrypted.
  Future<SyncEnableResult> enableE2e(
    String accountId,
    String passphrase, {
    bool withRecoveryCode = true,
  });

  /// Turns E2E off (needs the key on this device): the server deletes the
  /// header and the encrypted notes, this device uploads in plaintext.
  /// Other devices stay signed in and switch to plaintext when they see it.
  Future<void> disableE2e(String accountId);

  /// Changes the passphrase (re-wraps the key; notes stay as they are).
  Future<void> changePassphrase(String accountId, String newPassphrase);

  /// Creates a new recovery code (the old one stops working).
  Future<String> regenerateRecoveryCode(String accountId);

  /// The user confirmed saving the recovery code returned by [enable],
  /// [enableE2e] or [regenerateRecoveryCode] ("I saved it"). Until then the
  /// engine keeps reminding that the code may not be known.
  Future<void> acknowledgeRecoveryCode(String accountId);
}

/// The app-wide sync controller. The real engine is installed by overriding
/// this provider in main.dart (`syncControllerProvider.overrideWith(
/// SyncEngine.new)`); without an override sync is unavailable.
final syncControllerProvider =
    NotifierProvider<SyncController, Map<String, SyncAccountState>>(
      UnavailableSyncController.new,
    );

/// Default when no engine is installed (e.g. widget tests): everything off,
/// every action fails.
class UnavailableSyncController extends SyncController {
  @override
  Map<String, SyncAccountState> build() => const {};

  @override
  bool get available => false;

  Never _unavailable() =>
      throw const SyncException('Sync is not available in this build.');

  @override
  Future<SyncEnableResult> enable(
    String accountId,
    SyncEnableOptions o,
  ) async => _unavailable();
  @override
  Future<SyncAccountState> unlock(String accountId, String s) async =>
      _unavailable();
  @override
  Future<SyncAccountState> syncNow(String accountId) async => _unavailable();
  @override
  Future<void> disable(String accountId) async => _unavailable();
  @override
  Future<void> signOutDevice(String accountId) async => _unavailable();
  @override
  Future<SyncEnableResult> enableE2e(
    String accountId,
    String passphrase, {
    bool withRecoveryCode = true,
  }) async => _unavailable();
  @override
  Future<void> disableE2e(String accountId) async => _unavailable();
  @override
  Future<void> changePassphrase(String accountId, String p) async =>
      _unavailable();
  @override
  Future<String> regenerateRecoveryCode(String accountId) async =>
      _unavailable();
  @override
  Future<void> acknowledgeRecoveryCode(String accountId) async {}
}
