import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

/// Shows the last raw API responses — for diagnosing missing data
/// (e.g. teachers) against what the server actually sent.
class DebugScreen extends ConsumerWidget {
  const DebugScreen({super.key});

  static String _pretty(String json) {
    try {
      return const JsonEncoder.withIndent('  ').convert(jsonDecode(json));
    } catch (_) {
      return json;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final log = ref.watch(untisApiProvider).debugLog.reversed.toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Raw API responses')),
      body: log.isEmpty
          ? const Center(child: Text('No requests yet. Load a timetable first.'))
          : ListView.builder(
              itemCount: log.length,
              itemBuilder: (context, i) {
                final e = log[i];
                final pretty = _pretty(e.json);
                return ExpansionTile(
                  title: Text(e.method),
                  subtitle: Text('${e.at.toLocal()} · ${e.json.length} bytes'),
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        icon: const Icon(Icons.copy),
                        label: const Text('Copy'),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: pretty));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Copied — careful, it contains personal data')),
                          );
                        },
                      ),
                    ),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.all(12),
                      child: SelectableText(
                        pretty.length > 20000 ? '${pretty.substring(0, 20000)}\n…' : pretty,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}
