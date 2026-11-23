import '../core/info.dart';
import '../core/interfaces.dart';
import '../core/models.dart';
import '../core/office_hour_booking.dart';

/// [OfficeHourBookingRepository] on top of [OfficeHourBookingApi]. Nothing
/// is cached: the slots change as others book.
class OfficeHourBookingRepositoryImpl implements OfficeHourBookingRepository {
  OfficeHourBookingRepositoryImpl({required this.api, required this.accounts});

  final UntisApi api;
  final AccountRepository accounts;

  OfficeHourBookingApi _api() {
    final Object a = api;
    if (a is OfficeHourBookingApi) return a;
    throw const UntisException(
      -1,
      'Booking office hours is not supported for this account.',
    );
  }

  @override
  bool supports(Account account) => api is OfficeHourBookingApi;

  @override
  Future<OfficeHourSlots> slots(Account account, OfficeHourItem o) async =>
      _api().officeHourSlots(
        host: account.host,
        school: account.school.loginName,
        auth: await accounts.credentials(account.id),
        officeHour: o,
      );

  @override
  Future<OfficeHourSlots> book(
    Account account,
    OfficeHourItem o,
    OfficeHourSlot slot, {
    required String userText,
    String teacherText = '',
  }) async => _api().bookOfficeHour(
    host: account.host,
    school: account.school.loginName,
    auth: await accounts.credentials(account.id),
    officeHour: o,
    slot: slot,
    userText: userText,
    teacherText: teacherText,
  );

  @override
  Future<void> cancel(
    Account account,
    OfficeHourItem o, {
    String userText = '',
  }) async => _api().cancelOfficeHour(
    host: account.host,
    school: account.school.loginName,
    auth: await accounts.credentials(account.id),
    officeHour: o,
    userText: userText,
  );
}
