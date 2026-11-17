/// Web: no background checks (no service worker); the app checks while it
/// is open and shows changes in-app.
library;

bool get backgroundChecksSupported => false;

Future<void> scheduleBackgroundChecks({required bool enabled}) async {}
