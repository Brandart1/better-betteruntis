import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/class_register.dart';
import '../../core/interfaces.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/substitution_planning.dart';
import 'excuses_screen.dart' show excuseTimeSpan;

/// "Substitution requests" in the drawer for teachers: the requests asking
/// this teacher to take over a lesson of an absent colleague ("Ask
/// teacher" in WebUntis), with Accept / Decline for the open ones.
class SubstitutionRequestsScreen extends ConsumerStatefulWidget {
  const SubstitutionRequestsScreen({super.key});

  @override
  ConsumerState<SubstitutionRequestsScreen> createState() =>
      _SubstitutionRequestsScreenState();
}

class _SubstitutionRequestsScreenState
    extends ConsumerState<SubstitutionRequestsScreen> {
  List<SubstitutionRequest>? _requests;
  Object? _error;

  /// Ids of requests being answered.
  final _busy = <int>{};

  /// Only the latest load may set state.
  int _generation = 0;
  String? _accountId;

  SubstitutionPlanningRepository get _repo =>
      ref.read(substitutionPlanningRepositoryProvider);

  Future<void> _load(Account account) async {
    final gen = ++_generation;
    setState(() {
      _requests = null;
      _error = null;
    });
    try {
      final list = await _repo.requests(account);
      if (mounted && gen == _generation) setState(() => _requests = list);
    } catch (e) {
      if (mounted && gen == _generation) setState(() => _error = e);
    }
  }

  static String _message(Object e) =>
      e is UntisException ? e.message : e.toString();

  static String _what(SubstitutionRequest r) => [
    if (r.subject.isNotEmpty) r.subject,
    if (r.classes.isNotEmpty) r.classes.join(', '),
  ].join(' · ');

  Future<void> _answer(
    Account account,
    SubstitutionRequest r, {
    required bool accept,
  }) async {
    final what = _what(r).isEmpty ? 'this lesson' : _what(r);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(accept ? 'Accept the request?' : 'Decline the request?'),
        content: Text(
          accept
              ? 'You will substitute $what on '
                    '${excuseTimeSpan(context, r.start, r.end)}.'
              : 'You will not substitute $what.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('substitution-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(accept ? 'Accept' : 'Decline'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy.add(r.id));
    try {
      final updated = await _repo.answer(account, r, accept: accept);
      if (!mounted) return;
      setState(() {
        _busy.remove(r.id);
        _requests = [
          for (final x in _requests ?? const <SubstitutionRequest>[])
            x.id == r.id ? updated : x,
        ];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            accept
                ? 'Accepted: you substitute $what. Your timetable is updated '
                      'once the substitution is published.'
                : 'Declined: $what.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy.remove(r.id));
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_message(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(activeAccountProvider).value;
    final teacher = account != null && hasClassRegister(account);
    if (teacher && account.id != _accountId) {
      _accountId = account.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load(account);
      });
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Substitution requests'),
        actions: [
          if (teacher)
            IconButton(
              key: const ValueKey('substitution-refresh'),
              tooltip: 'Reload',
              icon: const Icon(Icons.refresh),
              onPressed: () => _load(account),
            ),
        ],
      ),
      body: !teacher
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Only teacher accounts get substitution requests.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: () => _load(account),
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: _list(context, account),
              ),
            ),
    );
  }

  List<Widget> _list(BuildContext context, Account account) {
    final error = _error;
    if (error != null) {
      return [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Text(
                _message(error),
                key: const ValueKey('substitution-error'),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => _load(account),
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      ];
    }
    final list = _requests;
    if (list == null) {
      return [
        const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (list.isEmpty) {
      return [
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No substitution requests. When the school asks you to take over '
            'a lesson, it shows here.',
            key: ValueKey('substitution-empty'),
            textAlign: TextAlign.center,
          ),
        ),
      ];
    }
    return [
      for (final r in list)
        _RequestCard(
          key: ValueKey('substitution-${r.id}'),
          request: r,
          busy: _busy.contains(r.id),
          onAccept: () => _answer(account, r, accept: true),
          onDecline: () => _answer(account, r, accept: false),
        ),
    ];
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    super.key,
    required this.request,
    required this.busy,
    required this.onAccept,
    required this.onDecline,
  });

  final SubstitutionRequest request;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final r = request;
    final theme = Theme.of(context);
    final what = _SubstitutionRequestsScreenState._what(r);
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    what.isEmpty ? 'Lesson' : what,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: 8),
                _StateChip(request: r),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              [
                excuseTimeSpan(context, r.start, r.end),
                if (r.unitOfDay != null) 'lesson ${r.unitOfDay}',
              ].join(' · '),
            ),
            if (r.rooms.isNotEmpty) Text('Room ${r.rooms.join(', ')}'),
            if (r.absentTeacher.isNotEmpty)
              Text(
                'Instead of ${r.absentTeacher}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            if (r.isPending)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: busy
                    ? const Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: EdgeInsets.all(8),
                          child: SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      )
                    : Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          OutlinedButton.icon(
                            key: ValueKey('substitution-decline-${r.id}'),
                            onPressed: onDecline,
                            icon: const Icon(Icons.close),
                            label: const Text('Decline'),
                          ),
                          FilledButton.icon(
                            key: ValueKey('substitution-accept-${r.id}'),
                            onPressed: onAccept,
                            icon: const Icon(Icons.check),
                            label: const Text('Accept'),
                          ),
                        ],
                      ),
              )
            else
              const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}

class _StateChip extends StatelessWidget {
  const _StateChip({required this.request});

  final SubstitutionRequest request;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = switch (request.state) {
      SubstitutionRequestState.pending => (
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
      ),
      SubstitutionRequestState.accepted => (
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
      ),
      SubstitutionRequestState.declined => (
        scheme.errorContainer,
        scheme.onErrorContainer,
      ),
      _ => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
    };
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 160),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            request.state.label,
            key: ValueKey('substitution-state-${request.id}'),
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(color: fg),
          ),
        ),
      ),
    );
  }
}
