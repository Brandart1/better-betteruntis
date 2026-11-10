import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  Future<void> _probe() async {
    final account = ref.read(activeAccountProvider).value;
    if (account == null) return;
    setState(() => _probing = true);
    try {
      final creds = await ref.read(accountRepositoryProvider).credentials(account.id);
      final now = DateTime.now();
      final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
      await ref.read(untisApiProvider).probeTeacherSources(
        host: account.host,
        school: account.school.loginName,
        auth: creds,
        target: TimetableTarget(account.elementType, account.elementId),
        weekStart: monday,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Probe failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _probing = false);
    }
  }

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
          ? const Center(child: Text('No requests yet. Load a timetable first.'))
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
