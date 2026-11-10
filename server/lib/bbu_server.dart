/// Self-hosted web server for BetterBetterUntis: serves the Flutter web build
/// and proxies WebUntis requests (which browsers can't make directly because
/// of CORS).
library;

export 'src/app.dart' show buildHandler, constantTimeEquals, authCookieName;
export 'src/config.dart';
export 'src/host_allowlist.dart';
export 'src/proxy.dart';
export 'src/static_files.dart';
