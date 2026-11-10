import 'host_allowlist.dart';

/// Runtime configuration, read from environment variables.
class ServerConfig {
  ServerConfig({
    this.port = 8080,
    this.webRoot = 'web',
    HostAllowlist? allowlist,
    this.basicAuth,
    this.coep = defaultCoep,
    this.maxRequestBodyBytes = 1024 * 1024,
    this.maxResponseBodyBytes = 32 * 1024 * 1024,
    this.upstreamTimeout = const Duration(seconds: 45),
  }) : allowlist = allowlist ?? HostAllowlist.parse(defaultAllowedHosts);

  static const defaultAllowedHosts = 'webuntis.com,*.webuntis.com';
  static const defaultCoep = 'credentialless';

  final int port;

  /// Directory containing the Flutter web build (`build/web`).
  final String webRoot;

  final HostAllowlist allowlist;

  /// `user:password` for HTTP basic auth, or null to disable it.
  final String? basicAuth;

  /// Value of the `Cross-Origin-Embedder-Policy` header, or null to omit it.
  final String? coep;

  final int maxRequestBodyBytes;
  final int maxResponseBodyBytes;
  final Duration upstreamTimeout;

  /// Builds the config from [env] (normally `Platform.environment`).
  ///
  /// Throws [FormatException] on invalid values so the server refuses to
  /// start with a broken configuration.
  factory ServerConfig.fromEnvironment(Map<String, String> env) {
    final portRaw = env['PORT']?.trim();
    final port = (portRaw == null || portRaw.isEmpty)
        ? 8080
        : int.tryParse(portRaw);
    if (port == null || port < 1 || port > 65535) {
      throw FormatException('PORT must be 1-65535, got "$portRaw"');
    }

    final webRoot = env['BBU_WEB_ROOT']?.trim();

    final hostsRaw = env['BBU_ALLOWED_HOSTS']?.trim();
    final allowlist = HostAllowlist.parse(
      (hostsRaw == null || hostsRaw.isEmpty) ? defaultAllowedHosts : hostsRaw,
    );

    final authRaw = env['BBU_BASIC_AUTH'];
    String? basicAuth;
    if (authRaw != null && authRaw.isNotEmpty) {
      final i = authRaw.indexOf(':');
      if (i <= 0 || i == authRaw.length - 1) {
        throw const FormatException(
          'BBU_BASIC_AUTH must have the form user:password',
        );
      }
      basicAuth = authRaw;
    }

    // Unset -> default; set but empty -> header disabled.
    final coepRaw = env['BBU_COEP'];
    final String? coep;
    if (coepRaw == null) {
      coep = defaultCoep;
    } else if (coepRaw.trim().isEmpty) {
      coep = null;
    } else {
      coep = coepRaw.trim();
      if (!RegExp(r'^[A-Za-z0-9-]+$').hasMatch(coep)) {
        throw FormatException('BBU_COEP has an invalid value "$coep"');
      }
    }

    return ServerConfig(
      port: port,
      webRoot: (webRoot == null || webRoot.isEmpty) ? 'web' : webRoot,
      allowlist: allowlist,
      basicAuth: basicAuth,
      coep: coep,
    );
  }
}
