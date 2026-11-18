/// Priority of requests to the school's server.
///
/// Work the user isn't waiting for (pupil photos, colleagues' lessons,
/// refreshing a week that is already on screen) runs inside
/// [inBackground]; the request throttle (lib/api/request_throttle.dart)
/// lets such requests wait behind everything else. The priority travels
/// with the zone, so every request started inside — also later, from
/// futures and streams created there — counts as background.
///
/// Pure Dart, no Flutter.
library;

import 'dart:async';

const _backgroundKey = #bbuBackgroundRequest;

/// Runs [f] with its requests at background priority.
T inBackground<T>(T Function() f) =>
    runZoned(f, zoneValues: {_backgroundKey: true});

/// Whether code running now is inside [inBackground].
bool get isBackgroundRequest => Zone.current[_backgroundKey] == true;
