/// Platform-specific services. Native builds use files, the keychain/keystore
/// and the share sheet; web builds use localStorage, browser downloads and
/// route WebUntis requests through the self-hosted proxy.
library;

export 'platform_services_io.dart'
    if (dart.library.js_interop) 'platform_services_web.dart';
