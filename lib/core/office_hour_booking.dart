/// Booking a time slot in a teacher's office hour ("Sprechstunde"), for
/// parents and pupils.
///
/// The calls are the official app 6.8.1's (JSON-RPC
/// getOfficeHourRegistrations2017, submitOfficeHourRegistration2017,
/// deleteOfficeHourRegistration2017); no real answer has been seen yet
/// (docs/API.md "Office hour booking"). Rendered by
/// lib/ui/infocenter/office_hour_booking_sheet.dart.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'info.dart';
import 'interfaces.dart';
import 'models.dart';

/// Who has a slot: nobody, someone else, or this account.
enum OfficeHourSlotState { free, other, self }

/// One bookable slot of an office hour.
class OfficeHourSlot {
  const OfficeHourSlot({
    required this.start,
    required this.end,
    required this.state,
  });

  final DateTime start;
  final DateTime end;
  final OfficeHourSlotState state;

  bool get isFree => state == OfficeHourSlotState.free;
  bool get isMine => state == OfficeHourSlotState.self;
}

/// The slots of one office hour, with the teacher's note and the note this
/// account left with its booking.
class OfficeHourSlots {
  const OfficeHourSlots({
    this.slots = const [],
    this.teacherText = '',
    this.userText = '',
  });

  final List<OfficeHourSlot> slots;
  final String teacherText;
  final String userText;

  OfficeHourSlot? get mine => slots.where((s) => s.isMine).firstOrNull;
}

/// Optional API capability.
abstract interface class OfficeHourBookingApi {
  Future<OfficeHourSlots> officeHourSlots({
    required String host,
    required String school,
    required UntisCredentials auth,
    required OfficeHourItem officeHour,
  });

  /// Books [slot]; returns the slots afterwards.
  Future<OfficeHourSlots> bookOfficeHour({
    required String host,
    required String school,
    required UntisCredentials auth,
    required OfficeHourItem officeHour,
    required OfficeHourSlot slot,
    required String userText,
    String teacherText = '',
  });

  /// Cancels this account's booking.
  Future<void> cancelOfficeHour({
    required String host,
    required String school,
    required UntisCredentials auth,
    required OfficeHourItem officeHour,
    String userText = '',
  });
}

abstract interface class OfficeHourBookingRepository {
  /// Whether [account]'s API can book office hours at all.
  bool supports(Account account);

  Future<OfficeHourSlots> slots(Account account, OfficeHourItem officeHour);

  Future<OfficeHourSlots> book(
    Account account,
    OfficeHourItem officeHour,
    OfficeHourSlot slot, {
    required String userText,
    String teacherText = '',
  });

  Future<void> cancel(
    Account account,
    OfficeHourItem officeHour, {
    String userText = '',
  });
}

/// Without a real implementation (tests, unsupported API).
class NoOfficeHourBooking implements OfficeHourBookingRepository {
  const NoOfficeHourBooking();

  static const _unsupported = UntisException(
    -1,
    'Booking office hours is not supported for this account.',
  );

  @override
  bool supports(Account account) => false;

  @override
  Future<OfficeHourSlots> slots(Account account, OfficeHourItem o) =>
      Future.error(_unsupported);

  @override
  Future<OfficeHourSlots> book(
    Account account,
    OfficeHourItem o,
    OfficeHourSlot slot, {
    required String userText,
    String teacherText = '',
  }) => Future.error(_unsupported);

  @override
  Future<void> cancel(
    Account account,
    OfficeHourItem o, {
    String userText = '',
  }) => Future.error(_unsupported);
}

/// Overridden in lib/data/data_providers.dart.
final officeHourBookingRepositoryProvider =
    Provider<OfficeHourBookingRepository>((ref) => const NoOfficeHourBooking());
