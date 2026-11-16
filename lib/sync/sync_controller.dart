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

/// How long the web version keeps the end-to-end encryption key in the
/// browser (localStorage, readable by anything running on the page, e.g.
/// extensions, or by others using this browser). The phone apps keep it in
/// the system's secure storage and ignore this.
enum WebKeyRetention {
  /// Only in memory: never written to storage; a reload asks again.
  tab('Only while this tab is open'),
  day('1 day', Duration(days: 1)),
  week('7 days', Duration(days: 7)),
  month('30 days', Duration(days: 30)),

  /// No expiry: until sync is turned off or signed out on this device.
  untilSignOut('Until I turn off sync or sign out on this device');

  const WebKeyRetention(this.label, [this.maxAge]);

  /// User-facing name.
  final String label;

  /// How long the stored key is used (null: [tab], or no expiry).
  final Duration? maxAge;

  /// The default (the behaviour before the choice existed).
  static const standard = month;
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
    this.webKeyRetention = WebKeyRetention.standard,
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

  /// Web version: how long the browser remembers the E2E key (persisted per
  /// account; ignored by the phone apps).
  final WebKeyRetention webKeyRetention;

  bool get enabled => phase != SyncPhase.off;
}

/// What the user chose when turning sync on.
class SyncEnableOptions {
  const SyncEnableOptions({
    this.passphrase,
    this.withRecoveryCode = true,
    this.webKeyRetention = WebKeyRetention.standard,
  });

  /// Non-null: turn on end-to-end encryption with this passphrase
  /// (min. 8 characters). Ignored if the server already has E2E for this
  /// identity (then [SyncController.unlock] is needed instead).
  final String? passphrase;
  final bool withRecoveryCode;

  /// Web version: how long the browser remembers the E2E key.
  final WebKeyRetention webKeyRetention;
}

/// What the sync server already has for an account, found by
/// [SyncController.checkServer] before the user picks how to turn sync on.
class SyncServerCheck {
  const SyncServerCheck({required this.existing, required this.e2e});

  /// Nothing known (e.g. a test fake): the normal opt-in.
  static const unknown = SyncServerCheck(existing: false, e2e: false);

  /// This account already syncs (on another device, or did before).
  final bool existing;

  /// That sync uses end-to-end encryption (a passphrase).
  final bool e2e;
}

/// Result of turning sync or E2E on.
class SyncEnableResult {
  const SyncEnableResult({required this.state, this.recoveryCode});
  final SyncAccountState state;

  /// Shown to the user once (E2E with recovery code only).
  final String? recoveryCode;
}

/// Latest release page (Android/iOS apps), linked where the web version
/// can't do something the apps can.
const kLatestReleaseUrl =
    'https://github.com/Brandart1/better-betteruntis/releases/latest';

/// Shown when the web version refuses to sync a second account.
const kWebSingleAccountMessage =
    'The web version of BetterBetterUntis only supports one synced account. '
    'To sync more accounts, use the Android or iOS app '
    '($kLatestReleaseUrl).';

/// Shown for anonymous (public timetable) accounts: they have no WebUntis
/// user the sync server could tell apart, so they never sync.
const kAnonymousSyncMessage =
    "Public timetable logins can't sync: sync needs a personal WebUntis "
    'login.';

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

  /// Only one account can sync at a time (web version: one browser cookie).
  bool get singleAccountOnly => false;

  /// The E2E key is cached in browser storage (web version): the UI lets
  /// the user choose [SyncAccountState.webKeyRetention].
  bool get webKeyChoice => false;

  /// Turns sync on for [accountId]: logs in to the sync server with the
  /// account's WebUntis token, optionally sets up E2E, then syncs.
  /// If the server already has E2E for this identity, the result's phase is
  /// [SyncPhase.locked].
  Future<SyncEnableResult> enable(String accountId, SyncEnableOptions options);

  /// Before [enable]: logs in to the sync server and tells whether this
  /// account already syncs and whether with a passphrase. The session is
  /// kept for the following [enable]; call [discardCheck] if the user
  /// cancels instead. The default (fakes) knows nothing.
  Future<SyncServerCheck> checkServer(String accountId) async =>
      SyncServerCheck.unknown;

  /// The user cancelled after [checkServer]: drops its session and, if the
  /// check itself created this account on the server, that empty entry.
  Future<void> discardCheck(String accountId) async {}

  /// Unlocks E2E on this device with the passphrase or the recovery code.
  /// [webKeyRetention] (web): also sets how long the key is remembered.
  Future<SyncAccountState> unlock(
    String accountId,
    String passphraseOrCode, {
    WebKeyRetention? webKeyRetention,
  });

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
  /// data and uploads everything encrypted. [webKeyRetention] (web): also
  /// sets how long the key is remembered.
  Future<SyncEnableResult> enableE2e(
    String accountId,
    String passphrase, {
    bool withRecoveryCode = true,
    WebKeyRetention? webKeyRetention,
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

  /// Web version: changes how long the browser remembers the E2E key of
  /// [accountId] (sync must be on or locked). Applies right away: a stored
  /// key older than the new limit (or any stored key, for
  /// [WebKeyRetention.tab]) is removed from storage; the key in memory stays
  /// usable in this tab until it is reloaded.
  Future<void> setWebKeyRetention(String accountId, WebKeyRetention retention);
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
  Future<SyncAccountState> unlock(
    String accountId,
    String s, {
    WebKeyRetention? webKeyRetention,
  }) async => _unavailable();
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
    WebKeyRetention? webKeyRetention,
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
  @override
  Future<void> setWebKeyRetention(String accountId, WebKeyRetention r) async =>
      _unavailable();
}
