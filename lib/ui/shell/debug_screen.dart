import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/absence_details.dart';
import '../../core/info.dart';
import '../../core/interfaces.dart';
import '../../core/models.dart';
import '../../core/providers.dart';

/// Shows the last raw API responses, for diagnosing missing data
/// (e.g. teachers) against what the server actually sent.
class DebugScreen extends ConsumerStatefulWidget {
  const DebugScreen({super.key});

  @override
  ConsumerState<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends ConsumerState<DebugScreen> {
  bool _probing = false;

  static String _pretty(String json) {
    try {
      return const JsonEncoder.withIndent('  ').convert(jsonDecode(json));
    } catch (_) {
      return json;
    }
  }

  static DateTime _monday() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day - (now.weekday - 1));
  }

  /// Runs [action] for the active account; failures show in a snack bar
  /// (the raw response is in the log anyway).
  Future<void> _run(
    String what,
    Future<void> Function(Account account, UntisCredentials creds) action,
  ) async {
    final account = ref.read(activeAccountProvider).value;
    if (account == null) return;
    setState(() => _probing = true);
    try {
      final creds = await ref.read(accountRepositoryProvider).credentials(account.id);
      await action(account, creds);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$what failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _probing = false);
    }
  }

  Future<void> _probe() => _run('Probe', (account, creds) async {
    final target = account.personalTarget;
    if (target == null) throw StateError('this account has no own timetable');
    await ref.read(untisApiProvider).probeTeacherSources(
      host: account.host,
      school: account.school.loginName,
      auth: creds,
      target: target,
      weekStart: _monday(),
    );
  });

  /// One getUserData2017 call (the login request), recorded in the log.
  Future<void> _fetchUserData() => _run('Loading user data', (account, creds) async {
    final Object api = ref.read(untisApiProvider);
    if (api is! AbsenceDetailsApi) throw StateError('not supported');
    await api.absenceLookups(
      host: account.host,
      school: account.school.loginName,
      auth: creds,
    );
  });

  /// getOfficeHours2017 for the account's class (if any) and for -1.
  Future<void> _fetchOfficeHours() => _run('Loading office hours', (account, creds) async {
    final Object api = ref.read(untisApiProvider);
    if (api is! InfoCenterApi) throw StateError('not supported');
    for (final k in {account.personalKlasseId ?? -1, -1}) {
      try {
        await api.officeHours(
          host: account.host,
          school: account.school.loginName,
          auth: creds,
          klasseId: k,
          start: _monday(),
        );
      } catch (_) {
        // Recorded in the log; try the next variant.
      }
    }
  });

  void _copy(String text, String what) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied $what. Careful, it contains personal data.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final log = ref.watch(untisApiProvider).debugLog.reversed.toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Raw API responses'),
        actions: [
          IconButton(
            tooltip: 'Copy list of requests',
            icon: const Icon(Icons.list_alt),
            onPressed: log.isEmpty
                ? null
                : () => _copy(
                    log.map((e) => '${e.at.toIso8601String()}  ${e.method}  (${e.json.length} B)').join('\n'),
                    'request list',
                  ),
          ),
          IconButton(
            tooltip: 'Reload',
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() {}),
          ),
          PopupMenuButton<void Function()>(
            key: const ValueKey('debug-menu'),
            tooltip: 'Fetch',
            enabled: !_probing,
            onSelected: (f) => f(),
            itemBuilder: (_) => [
              PopupMenuItem(
                key: const ValueKey('debug-fetch-userdata'),
                value: _fetchUserData,
                child: const Text('Fetch user data (getUserData2017)'),
              ),
              PopupMenuItem(
                key: const ValueKey('debug-fetch-officehours'),
                value: _fetchOfficeHours,
                child: const Text('Fetch office hours (getOfficeHours2017)'),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _probing ? null : _probe,
        icon: _probing
            ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.travel_explore),
        label: const Text('Probe teacher sources'),
      ),
      body: log.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No requests yet. Load a timetable first, or fetch user '
                  'data / office hours from the menu.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: log.length,
              itemBuilder: (context, i) {
                final e = log[i];
                final failed = e.json.contains('"_requestFailed"') ||
                    e.json.contains('"error"') ||
                    RegExp(r'\[HTTP [45]\d\d\]').hasMatch(e.method);
                return ExpansionTile(
                  leading: Icon(
                    failed ? Icons.error_outline : Icons.check_circle_outline,
                    color: failed ? Theme.of(context).colorScheme.error : null,
                  ),
                  title: Text(e.method),
                  subtitle: Text('${e.at.toLocal()} · ${e.json.length} bytes'),
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      // Compact JSON: about 3x smaller than pretty-printed,
                      // so large responses survive clipboard and paste limits.
                      child: TextButton.icon(
                        icon: const Icon(Icons.copy),
                        label: const Text('Copy'),
                        onPressed: () => _copy(e.json, 'response'),
                      ),
                    ),
                    Builder(
                      builder: (context) {
                        final pretty = _pretty(e.json);
                        return SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.all(12),
                          child: SelectableText(
                            pretty.length > 20000 ? '${pretty.substring(0, 20000)}\n…' : pretty,
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                          ),
                        );
                      },
                    ),
                  ],
                );
              },
            ),
    );
  }
}
