/// Periodic background check for notifications (Android only; see
/// background_check_io.dart). Web builds get a no-op so the workmanager
/// plugin isn't part of the web bundle.
library;

export 'background_check_io.dart'
    if (dart.library.js_interop) 'background_check_web.dart';
