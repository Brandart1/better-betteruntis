/// In-memory fakes for demo mode, UI development and widget tests.
///
/// * [FakeUntisApi]: a handful of German schools, scripted login outcomes and
///   a generated demo week.
/// * [InMemoryAccountRepository]: accounts + active account kept in memory,
///   exposed as streams that emit the current value on listen.
library;

import 'dart:async';

import '../core/interfaces.dart';
import '../core/models.dart';

/// Scripted [UntisApi].
///
/// Login rules (checked in order):
/// * password `wrong` -> [UntisException.invalidPassword]
/// * username `locked` -> [UntisException.locked]
/// * username `clock` -> [UntisException.invalidClientTime]
/// * username `offline` -> network error (code 0)
/// * username `2fa` without token `123456` -> [UntisException.twoFactorRequired]
/// * anonymous login at a school whose loginName contains `private` ->
///   [UntisException.noPublicAccess]
/// * anything else (e.g. `demo`/`demo`) succeeds.
///
/// Search rules: queries shorter than 3 chars or matching more than
/// [maxResults] schools -> [UntisException.tooManyResults]; query `offline`
/// -> network error.
class FakeUntisApi implements UntisApi {
  FakeUntisApi({this.latency = const Duration(milliseconds: 400)});

  /// Artificial delay for every call. Use [Duration.zero] in widget tests.
  final Duration latency;

  static const maxResults = 6;
  static const twoFactorCode = '123456';

  static const schools = <School>[
    School(
      schoolId: 4201,
      loginName: 'goethe-gym-berlin',
      displayName: 'Goethe-Gymnasium',
      address: 'Gasteiner Str. 23, 10717 Berlin',
      host: 'neilo.webuntis.com',
    ),
    School(
      schoolId: 4202,
      loginName: 'humboldt-koeln',
      displayName: 'Humboldt-Gymnasium Köln',
      address: 'Kartäuserwall 40, 50678 Köln',
      host: 'ajax.webuntis.com',
    ),
    School(
      schoolId: 4203,
      loginName: 'einstein-muenchen',
      displayName: 'Albert-Einstein-Gymnasium',
      address: 'Simmernstr. 1, 80804 München',
      host: 'arche.webuntis.com',
    ),
    School(
      schoolId: 4204,
      loginName: 'max-planck-goettingen',
      displayName: 'Max-Planck-Gymnasium',
      address: 'Theaterplatz 10, 37073 Göttingen',
      host: 'herakles.webuntis.com',
    ),
    School(
      schoolId: 4205,
      loginName: 'stadtpark-hamburg',
      displayName: 'Realschule am Stadtpark',
      address: 'Otto-Wels-Str. 2, 22303 Hamburg',
      host: 'kephiso.webuntis.com',
    ),
    School(
      schoolId: 4206,
      loginName: 'bbs-private-hannover',
      displayName: 'Private Berufsschule Hannover',
      address: 'Lavesallee 12, 30169 Hannover',
      host: 'mese.webuntis.com',
    ),
    School(
      schoolId: 4207,
      loginName: 'geschwister-scholl-leipzig',
      displayName: 'Geschwister-Scholl-Gymnasium',
      address: 'Hans-Driesch-Str. 1, 04179 Leipzig',
      host: 'thalia.webuntis.com',
    ),
    School(
      schoolId: 4208,
      loginName: 'gesamtschule-musterstadt',
      displayName: 'Gesamtschule Musterstadt',
      address: 'Schulweg 1, 12345 Musterstadt',
      host: 'demo.webuntis.com',
    ),
  ];

  /// Every login attempt, for test assertions.
  final List<({String school, String username, String? token, bool anonymous})>
  loginCalls = [];

  /// Every search query, for test assertions.
  final List<String> searchCalls = [];

  Future<void> _delay() =>
      latency == Duration.zero ? Future.value() : Future.delayed(latency);

  @override
  Future<List<School>> searchSchools(String query) async {
    searchCalls.add(query);
    await _delay();
    final q = query.trim().toLowerCase();
    if (q == 'offline') {
      throw const UntisException(0, 'Network unreachable');
    }
    if (q.length < 3) {
      throw const UntisException(
        UntisException.tooManyResults,
        'too many results',
      );
    }
    final id = int.tryParse(q);
    final hits = schools.where((s) {
      if (id != null) return s.schoolId == id;
      final hay = '${s.displayName} ${s.address} ${s.loginName}'.toLowerCase();
      return q.split(RegExp(r'\s+')).every(hay.contains);
    }).toList();
    if (hits.length > maxResults) {
      throw const UntisException(
        UntisException.tooManyResults,
        'too many results',
      );
    }
    return hits;
  }

  @override
  Future<LoginResult> login({
    required School school,
    required String username,
    required String passwordOrKey,
    bool anonymous = false,
    String? twoFactorToken,
    bool skipAppSecret = false,
    String? hostOverride,
  }) async {
    loginCalls.add((
      school: school.loginName,
      username: username,
      token: twoFactorToken,
      anonymous: anonymous,
    ));
    await _delay();
    if (anonymous) {
      if (school.loginName.contains('private')) {
        throw const UntisException(
          UntisException.noPublicAccess,
          'no public access',
        );
      }
    } else {
      if (passwordOrKey == 'wrong') {
        throw const UntisException(
          UntisException.invalidPassword,
          'bad credentials',
        );
      }
      switch (username.toLowerCase()) {
        case 'locked':
          throw const UntisException(UntisException.locked, 'locked');
        case 'clock':
          throw const UntisException(
            UntisException.invalidClientTime,
            'invalid client time',
          );
        case 'offline':
          throw const UntisException(0, 'Network unreachable');
        case '2fa' when twoFactorToken != twoFactorCode:
          throw const UntisException(
            UntisException.twoFactorRequired,
            'two factor required',
          );
      }
    }
    return LoginResult(
      secret: anonymous ? '' : 'FAKESECRET${username.toUpperCase()}',
      displayName: anonymous ? 'Public timetable' : _displayName(username),
      elementType: anonymous ? ElementType.klasse : ElementType.student,
      elementId: anonymous ? 1 : 1001,
      klassenIds: const [1],
      rights: const {'R_MY_TIMETABLE'},
      masterData: demoMasterData,
    );
  }

  static String _displayName(String username) {
    if (username.toLowerCase() == 'demo') return 'Demo Student';
    final parts = username
        .split(RegExp(r'[._\s-]+'))
        .where((p) => p.isNotEmpty)
        .map((p) => p[0].toUpperCase() + p.substring(1));
    return parts.isEmpty ? username : parts.join(' ');
  }

  static final demoMasterData = MasterData(
    timestamp: 1700000000000,
    elements: const [
      MasterElement(
        type: ElementType.klasse,
        id: 1,
        name: '9b',
        longName: 'Klasse 9b',
      ),
      MasterElement(
        type: ElementType.teacher,
        id: 11,
        name: 'MUE',
        longName: 'Anna Müller',
      ),
      MasterElement(
        type: ElementType.teacher,
        id: 12,
        name: 'SCH',
        longName: 'Jonas Schmidt',
      ),
      // Inactive on purpose: names must still be shown.
      MasterElement(
        type: ElementType.teacher,
        id: 13,
        name: 'WEB',
        longName: 'Lea Weber',
        active: false,
      ),
      MasterElement(
        type: ElementType.subject,
        id: 21,
        name: 'M',
        longName: 'Mathematik',
        backColor: 0xFF90CAF9,
      ),
      MasterElement(
        type: ElementType.subject,
        id: 22,
        name: 'D',
        longName: 'Deutsch',
        backColor: 0xFFFFCC80,
      ),
      MasterElement(
        type: ElementType.subject,
        id: 23,
        name: 'E',
        longName: 'Englisch',
        backColor: 0xFFA5D6A7,
      ),
      MasterElement(
        type: ElementType.subject,
        id: 24,
        name: 'PH',
        longName: 'Physik',
        backColor: 0xFFCE93D8,
      ),
      MasterElement(
        type: ElementType.room,
        id: 31,
        name: 'R101',
        longName: 'Raum 101',
      ),
      MasterElement(
        type: ElementType.room,
        id: 32,
        name: 'R204',
        longName: 'Raum 204',
      ),
      MasterElement(
        type: ElementType.room,
        id: 33,
        name: 'PH1',
        longName: 'Physiksaal',
      ),
    ],
    timeGrid: TimeGrid({
      for (var d = 1; d <= 5; d++)
        d: [
          for (var i = 0; i < 6; i++)
            TimeUnit(
              label: '${i + 1}',
              start: 8 * 60 + i * 50,
              end: 8 * 60 + i * 50 + 45,
            ),
        ],
    }),
  );

  @override
  Future<TimetableResponse> timetable({
    required String host,
    required String school,
    required UntisCredentials auth,
    required TimetableTarget target,
    required DateTime start,
    required DateTime end,
    required int masterDataTimestamp,
  }) async {
    await _delay();
    const plan = [
      // (subject, teacher, room) per unit, cycling through the week.
      (21, 11, 31), (22, 12, 31), (23, 13, 32), (24, 11, 33), (21, 11, 31),
      (23, 13, 32),
    ];
    final periods = <Period>[];
    var id = 1;
    for (
      var day = DateTime(start.year, start.month, start.day);
      !day.isAfter(end);
      day = DateTime(day.year, day.month, day.day + 1)
    ) {
      if (day.weekday > 5) continue;
      for (var unit = 0; unit < 5; unit++) {
        final p = plan[(unit + day.weekday) % plan.length];
        final s = day.add(Duration(minutes: 8 * 60 + unit * 50));
        final substituted = day.weekday == 3 && unit == 1;
        periods.add(
          Period(
            id: id++,
            lessonId: p.$1,
            start: s,
            end: s.add(const Duration(minutes: 45)),
            elements: [
              const ElementRef(type: ElementType.klasse, id: 1, orgId: 1),
              ElementRef(
                type: ElementType.teacher,
                id: substituted ? 12 : p.$2,
                orgId: p.$2,
              ),
              ElementRef(type: ElementType.subject, id: p.$1, orgId: p.$1),
              ElementRef(type: ElementType.room, id: p.$3, orgId: p.$3),
            ],
            flags: {
              if (day.weekday == 5 && unit == 4)
                PeriodFlag.cancelled
              else if (substituted)
                PeriodFlag.irregular
              else
                PeriodFlag.regular,
            },
            substitutionText: substituted ? 'Vertretung' : '',
          ),
        );
      }
    }
    return TimetableResponse(periods, null);
  }

  @override
  Future<List<Message>> messagesOfDay({
    required String host,
    required String school,
    required UntisCredentials auth,
    required DateTime date,
  }) async {
    await _delay();
    return const [
      Message(
        id: 1,
        subject: 'Welcome to the demo',
        bodyHtml: '<p>This is sample data. Add your real school anytime.</p>',
      ),
    ];
  }

  @override
  List<({String method, DateTime at, String json})> get debugLog => const [];

  @override
  Future<void> probeTeacherSources({
    required String host,
    required String school,
    required UntisCredentials auth,
    required TimetableTarget target,
    required DateTime weekStart,
  }) async {}
}

/// [AccountRepository] kept in memory. Streams are broadcast and emit the
/// current value to every new listener.
class InMemoryAccountRepository implements AccountRepository {
  InMemoryAccountRepository({
    List<Account> initial = const [],
    String? activeId,
  }) : _accounts = [...initial],
       _activeId = activeId ?? (initial.isEmpty ? null : initial.first.id);

  final List<Account> _accounts;
  String? _activeId;
  final Map<String, String> secrets = {};
  final Map<String, MasterData> masterData = {};

  final _accountsCtrl = StreamController<List<Account>>.broadcast();
  final _activeCtrl = StreamController<Account?>.broadcast();

  List<Account> get accounts => List.unmodifiable(_accounts);
  Account? get active => _accounts.where((a) => a.id == _activeId).firstOrNull;

  void _emit() {
    _accountsCtrl.add(accounts);
    _activeCtrl.add(active);
  }

  @override
  Stream<List<Account>> watchAccounts() async* {
    yield accounts;
    yield* _accountsCtrl.stream;
  }

  @override
  Stream<Account?> watchActive() async* {
    yield active;
    yield* _activeCtrl.stream;
  }

  @override
  Future<void> setActive(String accountId) async {
    if (_accounts.any((a) => a.id == accountId)) {
      _activeId = accountId;
      _emit();
    }
  }

  @override
  Future<Account> add(Account account, String secret, MasterData data) async {
    _accounts.removeWhere((a) => a.id == account.id);
    _accounts.add(account);
    secrets[account.id] = secret;
    masterData[account.id] = data;
    _activeId = account.id;
    _emit();
    return account;
  }

  @override
  Future<void> update(Account account) async {
    final i = _accounts.indexWhere((a) => a.id == account.id);
    if (i < 0) return;
    _accounts[i] = account;
    _emit();
  }

  @override
  Future<void> delete(String accountId) async {
    _accounts.removeWhere((a) => a.id == accountId);
    secrets.remove(accountId);
    masterData.remove(accountId);
    if (_activeId == accountId) {
      _activeId = _accounts.isEmpty ? null : _accounts.first.id;
    }
    _emit();
  }

  @override
  Future<UntisCredentials> credentials(String accountId) async {
    final account = _accounts.firstWhere((a) => a.id == accountId);
    if (account.anonymous) return const UntisCredentials.anonymous();
    return UntisCredentials.user(account.username, secrets[accountId] ?? '');
  }

  Future<void> dispose() async {
    await _accountsCtrl.close();
    await _activeCtrl.close();
  }
}
