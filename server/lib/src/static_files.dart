import 'dart:io';

import 'package:shelf/shelf.dart';

/// Files that must always be revalidated so a new deployment is picked up.
const _noCacheFiles = {
  'index.html',
  'flutter_service_worker.js',
  'version.json',
  'flutter_bootstrap.js',
  'manifest.json',
};

/// Extensions whose filenames are not content-hashed in a Flutter web build
/// (e.g. `main.dart.js`), so they get `no-cache` + ETag revalidation.
const _revalidateExtensions = {'html', 'js', 'mjs', 'wasm', 'json', 'map'};

const mimeTypes = <String, String>{
  'html': 'text/html; charset=utf-8',
  'htm': 'text/html; charset=utf-8',
  'js': 'text/javascript; charset=utf-8',
  'mjs': 'text/javascript; charset=utf-8',
  'json': 'application/json',
  'map': 'application/json',
  'wasm': 'application/wasm',
  'css': 'text/css; charset=utf-8',
  'txt': 'text/plain; charset=utf-8',
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'svg': 'image/svg+xml',
  'ico': 'image/x-icon',
  'otf': 'font/otf',
  'ttf': 'font/ttf',
  'woff': 'font/woff',
  'woff2': 'font/woff2',
  'bin': 'application/octet-stream',
  'frag': 'application/octet-stream',
  'webmanifest': 'application/manifest+json',
};

String mimeTypeFor(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot < 0) return 'application/octet-stream';
  return mimeTypes[fileName.substring(dot + 1).toLowerCase()] ??
      'application/octet-stream';
}

/// Serves a Flutter web build from [root] with SPA fallback to `index.html`
/// for extension-less paths (go_router path URLs).
class StaticFiles {
  StaticFiles(String root) : _root = Directory(root).absolute.path;

  final String _root;

  Future<Response> call(Request request) async {
    if (request.method != 'GET' && request.method != 'HEAD') {
      return Response(
        405,
        body: 'Method not allowed',
        headers: {'allow': 'GET, HEAD', 'content-type': 'text/plain'},
      );
    }

    final segments = <String>[];
    try {
      for (final s in request.requestedUri.pathSegments) {
        // pathSegments are already percent-decoded.
        if (s.isEmpty) continue;
        if (s == '.' ||
            s == '..' ||
            s.contains('/') ||
            s.contains('\\') ||
            s.contains('\x00')) {
          return _notFound();
        }
        segments.add(s);
      }
    } on FormatException {
      return _notFound();
    }

    File? file;
    if (segments.isNotEmpty) {
      final candidate = File([_root, ...segments].join(Platform.pathSeparator));
      if (await _isFileInsideRoot(candidate)) file = candidate;
    }

    if (file == null) {
      final last = segments.isEmpty ? '' : segments.last;
      if (segments.isNotEmpty && last.contains('.')) return _notFound();
      // Root or app route -> index.html.
      file = File('$_root${Platform.pathSeparator}index.html');
      if (!await file.exists()) {
        return Response.notFound(
          'Web build not found. Set BBU_WEB_ROOT to the flutter build/web directory.',
          headers: {'content-type': 'text/plain; charset=utf-8'},
        );
      }
    }

    return _serve(request, file);
  }

  Future<bool> _isFileInsideRoot(File f) async {
    try {
      if (!await f.exists()) return false;
      final resolved = await f.resolveSymbolicLinks();
      final root = await Directory(_root).resolveSymbolicLinks();
      return resolved.startsWith('$root${Platform.pathSeparator}');
    } on FileSystemException {
      return false;
    }
  }

  Future<Response> _serve(Request request, File file) async {
    final stat = await file.stat();
    final name = file.uri.pathSegments.last;
    final ext = name.contains('.')
        ? name.substring(name.lastIndexOf('.') + 1).toLowerCase()
        : '';
    final etag =
        '"${stat.size.toRadixString(16)}-'
        '${stat.modified.millisecondsSinceEpoch.toRadixString(16)}"';

    final cacheControl =
        _noCacheFiles.contains(name) || _revalidateExtensions.contains(ext)
        ? 'no-cache'
        : 'public, max-age=86400';

    final headers = {
      'content-type': mimeTypeFor(name),
      'cache-control': cacheControl,
      'etag': etag,
    };

    final inm = request.headers['if-none-match'];
    if (inm != null && inm.split(',').map((e) => e.trim()).contains(etag)) {
      return Response.notModified(headers: headers);
    }

    headers['content-length'] = '${stat.size}';
    return Response.ok(
      request.method == 'HEAD' ? null : file.openRead(),
      headers: headers,
    );
  }

  Response _notFound() => Response.notFound(
    'Not found',
    headers: {'content-type': 'text/plain; charset=utf-8'},
  );
}
