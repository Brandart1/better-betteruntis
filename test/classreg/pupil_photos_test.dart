import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:better_betteruntis/api/class_register_parsers.dart';
import 'package:better_betteruntis/api/untis_api_impl.dart';
import 'package:better_betteruntis/app/routing_api.dart';
import 'package:better_betteruntis/core/class_register.dart';
import 'package:better_betteruntis/core/interfaces.dart';
import 'package:better_betteruntis/core/models.dart';
import 'package:better_betteruntis/core/pupil_photos.dart';
import 'package:better_betteruntis/core/settings.dart';
import 'package:better_betteruntis/core/providers.dart';
import 'package:better_betteruntis/data/class_register_repository_impl.dart';
import 'package:better_betteruntis/data/pupil_photo_repository_impl.dart';
import 'package:better_betteruntis/dev/fake_accounts.dart';
import 'package:better_betteruntis/dev/fake_pupil_photos.dart';
import 'package:better_betteruntis/dev/fake_timetable.dart';
import 'package:better_betteruntis/ui/classreg/class_register_screen.dart';
import 'package:better_betteruntis/ui/classreg/pupil_avatar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'class_register_test.dart' show lesson, teacherAccount, week;

const creds = UntisCredentials.user('teacher', 'JBSWY3DPEHPK3PXP');
const host = 'neilo.webuntis.com';

/// A tiny valid image (the demo placeholder).
final jpegLike = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);

typedef Answer = ({int status, List<int> body, String type});

/// Answers JSON-RPC (auth token, login) and image GETs via [images].
class ImageAdapter implements HttpClientAdapter {
  ImageAdapter(this.images);
  final Answer Function(Uri uri, Map<String, dynamic> headers) images;
  Object? userData;
  final rpcMethods = <String>[];
  final gets = <Uri>[];
  final headers = <Map<String, dynamic>>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final sent = <int>[];
    await for (final c in requestStream ?? const Stream<Uint8List>.empty()) {
      sent.addAll(c);
    }
    if (o.uri.path.endsWith('jsonrpc_intern.do')) {
      final method = sent.isEmpty ? '' : utf8.decode(sent);
      rpcMethods.add(
        method.contains('getUserData2017') ? 'getUserData2017' : '',
      );
      return ResponseBody.fromString(
        jsonEncode({
          'id': '1',
          'jsonrpc': '2.0',
          'result': method.contains('getUserData2017')
              ? userData
              : {'token': 'jwt'},
        }),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
    }
    gets.add(o.uri);
    headers.add(o.headers);
    final a = images(o.uri, o.headers);
    return ResponseBody.fromBytes(
      a.body,
      a.status,
      headers: {
        Headers.contentTypeHeader: [a.type],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Answer image() => (status: 200, body: jpegLike, type: 'image/jpeg');
Answer notFound() => (status: 404, body: utf8.encode('{}'), type: 'json');

void main() {
  group('parsers', () {
    test('photo URL of a pupil: known keys, URLs and server paths only', () {
      expect(
        studentImageUrl({'imageUrl': 'https://x.webuntis.com/a.jpg'}),
        'https://x.webuntis.com/a.jpg',
      );
      expect(
        studentImageUrl({'imageUrl': '/WebUntis/img/5'}),
        '/WebUntis/img/5',
      );
      // Guessed keys are no longer read.
      expect(studentImageUrl({'photo': '/WebUntis/img/5'}), isNull);
      expect(studentImageUrl({'photoUrl': 'https://x/a.jpg'}), isNull);
      expect(studentImageUrl({'imageUrl': null}), isNull);
      expect(studentImageUrl({'imageUrl': 12}), isNull);
      expect(studentImageUrl({'imageUrl': 'data:image/png;base64,xx'}), isNull);
      expect(studentImageUrl({'imageUrl': '//evil.com/a'}), isNull);
      expect(studentImageUrl({'imageUrl': 'ftp://x/a'}), isNull);
      final s = parseClassRegStudent({
        'id': 1,
        'firstName': 'Lena',
        'lastName': 'Bauer',
        'imageUrl': '/p/1',
      })!;
      expect(s.imageUrl, '/p/1');
      expect(s.initials, 'LB');
    });

    test('initials', () {
      expect(
        const ClassRegStudent(
          id: 1,
          firstName: 'émile',
          lastName: 'zola',
        ).initials,
        'ÉZ',
      );
      expect(
        const ClassRegStudent(id: 1, firstName: '', lastName: '#1').initials,
        '',
      );
      expect(
        const ClassRegStudent(id: 1, firstName: '', lastName: 'Koch').initials,
        'K',
      );
    });

    test('image responses: type or magic bytes', () {
      expect(UntisApiImpl.isImageResponse(200, 'image/png', [1]), isTrue);
      expect(UntisApiImpl.isImageResponse(404, 'image/png', [1]), isFalse);
      expect(UntisApiImpl.isImageResponse(200, 'image/png', []), isFalse);
      expect(
        UntisApiImpl.isImageResponse(200, 'application/octet-stream', jpegLike),
        isTrue,
      );
      expect(
        UntisApiImpl.isImageResponse(200, null, placeholderPortrait(1)),
        isFalse, // BMP is not sniffed (the server won't send one)
      );
      expect(
        UntisApiImpl.isImageResponse(200, 'application/json', jpegLike),
        isFalse,
      );
      expect(
        UntisApiImpl.isImageResponse(200, 'text/html', utf8.encode('<html>')),
        isFalse,
      );
    });

    test('photo URL resolution', () {
      expect(
        UntisApiImpl.pupilPhotoUrl(host, '/WebUntis/x'),
        'https://$host/WebUntis/x',
      );
      expect(
        UntisApiImpl.pupilPhotoUrl(host, 'https://other/x'),
        'https://other/x',
      );
    });
  });

  group('api', () {
    Future<Uint8List?> photo(UntisApiImpl api, int id, {String? url}) =>
        api.pupilPhoto(
          host: host,
          school: 's',
          auth: creds,
          studentId: id,
          imageUrl: url,
        );

    test('no imageUrl in the master data: no photo, no guessing', () async {
      final adapter = ImageAdapter((_, _) => image())
        ..userData = {
          'masterData': {
            'students': [
              {'id': 9},
            ],
          },
        };
      final api = UntisApiImpl(dio: Dio()..httpClientAdapter = adapter);
      expect(await photo(api, 501), isNull);
      expect(adapter.gets, isEmpty);
    });

    test('masterData.students[].imageUrl is loaded, with the bearer', () async {
      final adapter = ImageAdapter((_, _) => image())
        ..userData = {
          'masterData': {
            'students': [
              {'id': 501, 'imageUrl': '/WebUntis/img/501.jpg'},
              {'id': 502, 'imageUrl': 'https://cdn.example.com/502.jpg'},
            ],
          },
        };
      final api = UntisApiImpl(dio: Dio()..httpClientAdapter = adapter);
      expect(await photo(api, 501), jpegLike);
      expect(
        adapter.gets.single.toString(),
        'https://$host/WebUntis/img/501.jpg',
      );
      expect(adapter.headers.first['Authorization'], 'Bearer jwt');
      expect(adapter.headers.first['Accept'], 'image/*');
      // Master data is read once; another host never gets the token.
      expect(await photo(api, 502), jpegLike);
      expect(
        adapter.rpcMethods.where((m) => m == 'getUserData2017'),
        hasLength(1),
      );
      expect(adapter.headers.last['Authorization'], isNull);
      // Log: status, type and size, no bytes.
      final log = api.debugLog
          .where((e) => e.method.startsWith('pupil photo'))
          .toList();
      final first = jsonDecode(log.first.json) as Map;
      expect(first['bytes'], jpegLike.length);
      expect(first['contentType'], 'image/jpeg');
      expect(first['url'], 'https://$host/WebUntis/img/501.jpg');
    });

    test('an image URL from the pupil is used as is', () async {
      final adapter = ImageAdapter((_, _) => image());
      final api = UntisApiImpl(dio: Dio()..httpClientAdapter = adapter);
      expect(await photo(api, 7, url: '/WebUntis/img/7.jpg'), jpegLike);
      expect(
        adapter.gets.single.toString(),
        'https://$host/WebUntis/img/7.jpg',
      );
      // Another host never gets the token.
      await photo(api, 7, url: 'https://cdn.example.com/7.jpg');
      expect(adapter.headers.last['Authorization'], isNull);
    });
  });

  group('api: fewer requests', () {
    Future<Uint8List?> photo(UntisApiImpl api, int id) => api.pupilPhoto(
      host: host,
      school: 's',
      auth: creds,
      studentId: id,
      imageUrl: '/WebUntis/img/$id.jpg',
    );

    test('photos loading at once share one token and one master data '
        'load', () async {
      final adapter = ImageAdapter((_, _) => image())
        ..userData = {
          'masterData': {
            'students': [
              for (var i = 1; i <= 6; i++)
                {'id': i, 'imageUrl': '/WebUntis/img/$i.jpg'},
            ],
          },
        };
      final api = UntisApiImpl(dio: Dio()..httpClientAdapter = adapter);
      final photos = await Future.wait([
        for (var i = 1; i <= 6; i++)
          api.pupilPhoto(host: host, school: 's', auth: creds, studentId: i),
      ]);
      expect(photos, everyElement(jpegLike));
      expect(
        adapter.rpcMethods.where((m) => m == 'getUserData2017'),
        hasLength(1),
      );
      expect(adapter.rpcMethods.where((m) => m == ''), hasLength(1));
      expect(adapter.gets, hasLength(6));
    });

    test('three photos in a row without an image: no more requests', () async {
      final adapter = ImageAdapter((_, _) => notFound());
      final api = UntisApiImpl(dio: Dio()..httpClientAdapter = adapter);
      for (var i = 1; i <= 3; i++) {
        expect(await photo(api, i), isNull);
      }
      expect(adapter.gets, hasLength(3));
      expect(await photo(api, 4), isNull);
      expect(adapter.gets, hasLength(3));
    });

    test('a working photo resets the count', () async {
      var n = 0;
      final adapter = ImageAdapter((_, _) => ++n == 3 ? image() : notFound());
      final api = UntisApiImpl(dio: Dio()..httpClientAdapter = adapter);
      for (var i = 1; i <= 5; i++) {
        await photo(api, i);
      }
      expect(adapter.gets, hasLength(5));
    });

    test('photos that work with the token: a refused one is not retried '
        'with the web session', () async {
      var n = 0;
      final adapter = ImageAdapter(
        (_, _) => ++n == 1
            ? image()
            : (status: 403, body: utf8.encode('{}'), type: 'json'),
      );
      final api = UntisApiImpl(dio: Dio()..httpClientAdapter = adapter);
      expect(await photo(api, 1), jpegLike);
      expect(await photo(api, 2), isNull);
      expect(adapter.gets, hasLength(2));
    });
  });

  group('repository', () {
    late FakeUntisApi api;
    late PupilPhotoRepositoryImpl repo;
    setUp(() {
      api = FakeUntisApi(latency: Duration.zero);
      final accounts = InMemoryAccountRepository(initial: [teacherAccount()]);
      accounts.secrets['teacher'] = 'S';
      repo = PupilPhotoRepositoryImpl(api: api, accounts: accounts);
    });
    const lena = ClassRegStudent(id: 501, firstName: 'Lena', lastName: 'B');
    const ben = ClassRegStudent(id: 506, firstName: 'Ben', lastName: 'W');

    test('through the app\'s routing API (as in the real app)', () async {
      final accounts = InMemoryAccountRepository(initial: [teacherAccount()]);
      accounts.secrets['teacher'] = 'S';
      final routed = PupilPhotoRepositoryImpl(
        api: RoutingUntisApi(real: api, demo: api),
        accounts: accounts,
      );
      expect(await routed.photo(teacherAccount(), lena), isNotNull);
    });

    test('demo photos, cached per session, "no photo" too', () async {
      final a = teacherAccount();
      final p = await repo.photo(a, lena);
      expect(p, isNotNull);
      expect(repo.cached(a, lena), same(p));
      expect(await repo.photo(a, ben), isNull);
      await repo.photo(a, lena);
      await repo.photo(a, ben);
      expect(api.pupilPhotoCalls, 2);
      repo.clear();
      expect(repo.cached(a, lena), isNull);
    });

    test('parallel loads of the same pupil share one request', () async {
      final a = teacherAccount();
      await Future.wait([repo.photo(a, lena), repo.photo(a, lena)]);
      expect(api.pupilPhotoCalls, 1);
    });

    test('no photos for non-teacher accounts', () async {
      expect(await repo.photo(demoAccount(), lena), isNull);
      expect(api.pupilPhotoCalls, 0);
    });

    test('demo placeholder is a decodable image', () async {
      final bytes = placeholderPortrait(501);
      expect(bytes.sublist(0, 2), [0x42, 0x4D]);
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, 96);
    });
  });

  group('avatar', () {
    const lena = ClassRegStudent(id: 501, firstName: 'Lena', lastName: 'Bauer');

    Widget app(
      PupilPhotoRepository repo, {
      bool absent = false,
      SettingsStore? store,
    }) => ProviderScope(
      overrides: [
        pupilPhotoRepositoryProvider.overrideWithValue(repo),
        settingsStoreProvider.overrideWithValue(store ?? MemorySettingsStore()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: PupilAvatar(
              account: teacherAccount(),
              student: lena,
              absent: absent,
            ),
          ),
        ),
      ),
    );

    testWidgets('initials when there is no photo', (t) async {
      await t.pumpWidget(app(const NoPupilPhotos()));
      await t.pump();
      expect(find.text('LB'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('photo when there is one', (t) async {
      await t.pumpWidget(app(_Fixed(placeholderPortrait(501))));
      await t.pump();
      expect(find.byKey(const ValueKey('pupil-photo-image')), findsOneWidget);
      expect(find.text('LB'), findsNothing);
    });

    testWidgets('initials when the photo can not be decoded', (t) async {
      await t.pumpWidget(app(_Fixed(Uint8List.fromList([1, 2, 3, 4]))));
      await t.pump();
      expect(find.byKey(const ValueKey('pupil-photo-image')), findsOneWidget);
      // Let the decoder fail.
      for (var i = 0; i < 5 && find.text('LB').evaluate().isEmpty; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await t.pump();
      }
      expect(find.text('LB'), findsOneWidget);
    });

    testWidgets('photos off: the plain status icon, stored', (t) async {
      final store = MemorySettingsStore()
        ..values[PupilPhotosSetting.storeKey] = false;
      await t.pumpWidget(
        app(_Fixed(placeholderPortrait(501)), absent: true, store: store),
      );
      await t.pump();
      expect(find.byIcon(Icons.close), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(find.text('LB'), findsNothing);
    });
  });

  group('screen (demo teacher)', () {
    testWidgets('photos, initials, large photo, toggle', (t) async {
      t.view.physicalSize = const Size(800, 2000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final api = FakeUntisApi(latency: Duration.zero);
      final accounts = InMemoryAccountRepository(initial: [teacherAccount()]);
      accounts.secrets['teacher'] = 'S';
      final store = MemorySettingsStore();
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            accountRepositoryProvider.overrideWithValue(accounts),
            settingsStoreProvider.overrideWithValue(store),
            classRegisterRepositoryProvider.overrideWithValue(
              ClassRegisterRepositoryImpl(
                api: api,
                accounts: accounts,
                timetables: FakeTimetableRepository(weekBuilder: week),
                clock: () => DateTime(2026, 11, 11, 12),
              ),
            ),
            pupilPhotoRepositoryProvider.overrideWithValue(
              PupilPhotoRepositoryImpl(api: api, accounts: accounts),
            ),
          ],
          child: MaterialApp(
            home: ClassRegisterScreen(
              account: teacherAccount(),
              periods: [lesson(11, DateTime(2026, 11, 10, 8))],
              title: 'Maths',
              subtitle: 'Tue 10 Nov',
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      Finder inTile(int id, Finder f) => find.descendant(
        of: find.byKey(ValueKey('classreg-student-$id')),
        matching: f,
      );
      expect(
        inTile(501, find.byKey(const ValueKey('pupil-photo-image'))),
        findsOneWidget,
      );
      await t.longPress(find.byKey(const ValueKey('classreg-student-501')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('pupil-photo-dialog')), findsOneWidget);
      await t.tap(find.text('Close'));
      await t.pumpAndSettle();
      // Ben Wagner has no demo photo.
      await t.scrollUntilVisible(
        find.byKey(const ValueKey('classreg-student-506')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      expect(inTile(506, find.text('BW')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('classreg-photos-toggle')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('pupil-photo-image')), findsNothing);
      expect(store.values[PupilPhotosSetting.storeKey], isFalse);
      // Long press does nothing with photos off.
      await t.longPress(find.byKey(const ValueKey('classreg-student-506')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('pupil-photo-dialog')), findsNothing);
    });
  });
}

class _Fixed implements PupilPhotoRepository {
  _Fixed(this.bytes);
  final Uint8List bytes;

  @override
  Uint8List? cached(Account account, ClassRegStudent student) => bytes;

  @override
  void clear() {}

  @override
  Future<Uint8List?> photo(Account account, ClassRegStudent student) async =>
      bytes;
}
