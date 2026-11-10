/// Layer contracts. Implementations:
///   UntisApi            -> lib/api/        (HTTP + JSON-RPC + OTP)
///   AccountRepository   -> lib/data/       (drift + secure storage)
///   TimetableRepository -> lib/data/       (cache-first, offline)
/// UI (lib/ui/) depends only on these interfaces via providers in
/// lib/core/providers.dart.
library;

import 'models.dart';

/// Thrown for JSON-RPC errors and transport failures.
class UntisException implements Exception {
  const UntisException(this.code, this.message);

  /// Untis error code (e.g. -8504), or 0 for network/parse errors.
  final int code;
  final String message;

  static const tooManyResults = -6003;
  static const invalidSchool = -8500;
  static const invalidPassword = -8504;
  static const noRight = -8509;
  static const locked = -8511;
  static const twoFactorRequired = -8519;
  static const noPublicAccess = -8523;
  static const invalidClientTime = -8524;

  bool get isNetwork => code == 0;

  @override
  String toString() => 'UntisException($code): $message';
}

/// Credentials used to sign each request.
class UntisCredentials {
  const UntisCredentials.user(this.username, this.secret) : anonymous = false;
  const UntisCredentials.anonymous()
    : username = '#anonymous#',
      secret = '',
      anonymous = true;

  final String username;
  final String secret;
  final bool anonymous;
}

/// Result of a successful login.
class LoginResult {
  const LoginResult({
    required this.secret,
    required this.displayName,
    required this.elementType,
    required this.elementId,
    required this.klassenIds,
    required this.rights,
    required this.masterData,
  });

  final String secret;
  final String displayName;
  final ElementType elementType;
  final int elementId;
  final List<int> klassenIds;
  final Set<String> rights;
  final MasterData masterData;
}

class TimetableResponse {
  const TimetableResponse(this.periods, this.masterDataDelta);
  final List<Period> periods;
  final MasterData? masterDataDelta;
}

class Message {
  const Message({
    required this.id,
    required this.subject,
    required this.bodyHtml,
    this.attachments = const [],
  });
  final int id;
  final String subject;
  final String bodyHtml;
  final List<({String name, String url})> attachments;
}

/// Stateless WebUntis API client. Every call takes the host/school explicitly
/// so one client serves all accounts.
abstract interface class UntisApi {
  Future<List<School>> searchSchools(String query);

  /// Full login: shared secret (password-as-secret fallback, 2FA via
  /// [twoFactorToken]) + user data + master data.
  Future<LoginResult> login({
    required School school,
    required String username,
    required String passwordOrKey,
    bool anonymous = false,
    String? twoFactorToken,
    bool skipAppSecret = false,
    String? hostOverride,
  });

  Future<TimetableResponse> timetable({
    required String host,
    required String school,
    required UntisCredentials auth,
    required TimetableTarget target,
    required DateTime start,
    required DateTime end,
    required int masterDataTimestamp,
  });

  Future<List<Message>> messagesOfDay({
    required String host,
    required String school,
    required UntisCredentials auth,
    required DateTime date,
  });

  /// Raw JSON of the last N responses, for the debug screen.
  List<({String method, DateTime at, String json})> get debugLog;
}

/// Stores accounts. Exactly one account is active at a time (or none).
abstract interface class AccountRepository {
  Stream<List<Account>> watchAccounts();
  Stream<Account?> watchActive();
  Future<void> setActive(String accountId);

  /// Persists a new account and its secret + full master data, and makes it
  /// active. Returns the stored account.
  Future<Account> add(Account account, String secret, MasterData masterData);
  Future<void> update(Account account);
  Future<void> delete(String accountId);
  Future<UntisCredentials> credentials(String accountId);
}

/// Name lookup with the fallback chain that fixes BetterUntis' missing
/// teachers. Built from ALL master-data entries (active or not).
abstract interface class NameResolver {
  String shortName(ElementRef ref, {bool original = false});
  String longName(ElementRef ref, {bool original = false});
  MasterElement? element(ElementType type, int id);
  List<MasterElement> elementsOf(ElementType type, {bool onlyActive = true});
  List<Holiday> get holidays;
  TimeGrid get timeGrid;
}

/// Cache-first timetable access. [watchWeek] emits cached data immediately
/// (if any), then fresh data after a background refresh.
abstract interface class TimetableRepository {
  Stream<List<Period>> watchWeek(
    Account account,
    TimetableTarget target,
    DateTime weekStart,
  );

  /// Forces a network refresh of that week. Throws [UntisException].
  Future<void> refresh(Account account, TimetableTarget target, DateTime weekStart);

  /// Emits a new resolver whenever master data changes (deltas applied before
  /// periods are emitted, so names are never stale).
  Stream<NameResolver> watchNames(Account account);

  DateTime? lastRefreshed(Account account, TimetableTarget target, DateTime weekStart);
}
