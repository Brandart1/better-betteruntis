import 'dart:async';
import 'dart:io';

import 'package:bbu_server/bbu_server.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

Future<void> main(List<String> args) async {
  if (args.contains('--healthcheck')) {
    // Used by the Docker HEALTHCHECK (the scratch image has no shell/curl).
    exit(await _healthcheck());
  }

  final ServerConfig config;
  try {
    config = ServerConfig.fromEnvironment(Platform.environment);
  } on FormatException catch (e) {
    stderr.writeln('Configuration error: ${e.message}');
    exitCode = 64;
    return;
  }

  void log(String message) =>
      stdout.writeln('${DateTime.now().toUtc().toIso8601String()} $message');

  final ioClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..idleTimeout = const Duration(seconds: 30)
    ..userAgent = upstreamUserAgent;
  final http.Client client = IOClient(ioClient);

  final server = await shelf_io.serve(
    buildHandler(config, client, log: log),
    InternetAddress.anyIPv4,
    config.port,
    poweredByHeader: null,
  );
  server.autoCompress = true;

  final webRoot = Directory(config.webRoot).absolute.path;
  log(
    'listening on 0.0.0.0:${server.port} '
    'webRoot=$webRoot allowedHosts=${config.allowlist} '
    'basicAuth=${config.basicAuth != null ? 'on' : 'off'} '
    'coep=${config.coep ?? '(none)'}',
  );
  if (!File('$webRoot/index.html').existsSync()) {
    log('warning: $webRoot/index.html not found');
  }

  Future<void> shutdown(ProcessSignal signal) async {
    log('received $signal, shutting down');
    await server.close();
    client.close();
    exit(0);
  }

  ProcessSignal.sigint.watch().listen(shutdown);
  if (!Platform.isWindows) ProcessSignal.sigterm.watch().listen(shutdown);
}

Future<int> _healthcheck() async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
  try {
    final req = await client
        .getUrl(
          Uri(scheme: 'http', host: '127.0.0.1', port: port, path: '/healthz'),
        )
        .timeout(const Duration(seconds: 3));
    final res = await req.close().timeout(const Duration(seconds: 3));
    await res.drain<void>();
    return res.statusCode == 200 ? 0 : 1;
  } catch (_) {
    return 1;
  } finally {
    client.close(force: true);
  }
}
