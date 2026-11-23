import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/info.dart';
import '../../core/interfaces.dart';
import '../../core/models.dart';
import '../../core/office_hour_booking.dart';
import 'info_common.dart';

/// Book a time in office hour [item], or see / cancel the booking. Resolves
/// to true when a booking was made or cancelled.
Future<bool> showOfficeHourBooking(
  BuildContext context,
  Account account,
  OfficeHourItem item,
) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => OfficeHourBookingSheet(account: account, item: item),
    ) ??
    false;

class OfficeHourBookingSheet extends ConsumerStatefulWidget {
  const OfficeHourBookingSheet({
    super.key,
    required this.account,
    required this.item,
  });

  final Account account;
  final OfficeHourItem item;

  @override
  ConsumerState<OfficeHourBookingSheet> createState() =>
      _OfficeHourBookingSheetState();
}

class _OfficeHourBookingSheetState
    extends ConsumerState<OfficeHourBookingSheet> {
  final _note = TextEditingController();
  OfficeHourSlots? _slots;
  OfficeHourSlot? _picked;
  Object? _loadError;
  String? _saveError;
  bool _saving = false;

  OfficeHourBookingRepository get _repo =>
      ref.read(officeHourBookingRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _slots = null;
      _loadError = null;
    });
    try {
      final s = await _repo.slots(widget.account, widget.item);
      if (!mounted) return;
      setState(() {
        _slots = s;
        if (s.mine != null && _note.text.isEmpty) _note.text = s.userText;
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  static String _message(Object e) => e is UntisException ? e.message : '$e';

  Future<void> _book() async {
    final slot = _picked;
    if (slot == null) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await _repo.book(
        widget.account,
        widget.item,
        slot,
        userText: _note.text,
        teacherText: _slots?.teacherText ?? '',
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _saveError = _message(e);
        });
      }
    }
  }

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Cancel booking?'),
        content: const Text('Your time slot is given free again.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            key: const ValueKey('officehour-cancel-confirm'),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Cancel booking'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await _repo.cancel(
        widget.account,
        widget.item,
        userText: _slots?.userText ?? '',
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _saveError = _message(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final o = widget.item;
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final teacher = o.teacherName.trim().isEmpty
        ? 'Teacher'
        : o.teacherName.trim();
    final slots = _slots;
    final mine = slots?.mine;

    Widget body;
    if (_loadError != null) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Could not load the times: ${_message(_loadError!)}',
            style: muted,
          ),
          TextButton(onPressed: _load, child: const Text('Try again')),
        ],
      );
    } else if (slots == null) {
      body = const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (mine != null) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Booked: ${formatTimeRange(context, mine.start, mine.end)}',
            key: const ValueKey('officehour-booked'),
            style: theme.textTheme.titleMedium,
          ),
          if (slots.userText.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Your note: ${slots.userText}', style: muted),
          ],
          const SizedBox(height: 16),
          OutlinedButton.icon(
            key: const ValueKey('officehour-cancel'),
            onPressed: _saving ? null : _cancel,
            icon: const Icon(Icons.event_busy_outlined),
            label: const Text('Cancel booking'),
          ),
        ],
      );
    } else if (slots.slots.isEmpty) {
      body = Text(
        'The school sent no times for this office hour.',
        style: muted,
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Pick a time', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in slots.slots)
                ChoiceChip(
                  key: ValueKey(
                    'officehour-slot-${s.start.hour}-${s.start.minute}',
                  ),
                  label: Text(formatTimeRange(context, s.start, s.end)),
                  tooltip: s.isFree ? null : 'Taken',
                  selected: _picked?.start == s.start,
                  onSelected: s.isFree && !_saving
                      ? (on) => setState(() => _picked = on ? s : null)
                      : null,
                ),
            ],
          ),
          if (!slots.slots.any((s) => s.isFree)) ...[
            const SizedBox(height: 8),
            Text('All times are taken.', style: muted),
          ],
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('officehour-note'),
            controller: _note,
            minLines: 1,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Note for the teacher (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const ValueKey('officehour-book'),
            onPressed: _picked == null || _saving ? null : _book,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.event_available_outlined),
            label: const Text('Book'),
          ),
        ],
      );
    }

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Office hour · $teacher', style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                [
                  formatDay(context, o.start, DateTime.now()),
                  formatTimeRange(context, o.start, o.end),
                  if (o.rooms.trim().isNotEmpty) o.rooms.trim(),
                ].join(' · '),
                style: muted,
              ),
              if (slots != null && slots.teacherText.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  slots.teacherText,
                  key: const ValueKey('officehour-teacher-text'),
                  style: theme.textTheme.bodyMedium,
                ),
              ],
              const SizedBox(height: 16),
              body,
              if (_saveError != null) ...[
                const SizedBox(height: 12),
                Text(
                  _saveError!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
