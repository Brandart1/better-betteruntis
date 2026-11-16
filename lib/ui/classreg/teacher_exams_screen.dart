import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/class_register.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../infocenter/exams_tab.dart';
import '../infocenter/info_providers.dart';
import '../timetable/timetable_utils.dart';
import 'exam_editor_screen.dart';

/// "Exams" in the drawer for teachers with the class register: their
/// upcoming and past exams (the Info center's exam list, from their own
/// timetable element) and "New exam", which opens the exam editor.
class TeacherExamsScreen extends ConsumerWidget {
  const TeacherExamsScreen({super.key});

  /// Reloads the lists [ExamsTab] shows (same queries as the tab).
  static Future<void> refreshExams(WidgetRef ref, Account account) {
    final today = dateOnly(DateTime.now());
    final upQ = InfoQuery(account, start: today, end: addDays(today, 56));
    final pastQ = InfoQuery(account, start: addDays(today, -56), end: today);
    return Future.wait([
      forceRefresh(ref, #exams, examsProvider(upQ), upQ),
      forceRefresh(ref, #exams, examsProvider(pastQ), pastQ),
    ]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(activeAccountProvider).value;
    final teacher = account != null && hasClassRegister(account);
    return Scaffold(
      appBar: AppBar(title: const Text('Exams')),
      floatingActionButton: !teacher
          ? null
          : FloatingActionButton.extended(
              key: const ValueKey('exams-new'),
              onPressed: () async {
                final created = await openExamEditor(context, account: account);
                if (!created || !context.mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Exam created.')));
                await refreshExams(ref, account);
              },
              icon: const Icon(Icons.add),
              label: const Text('New exam'),
            ),
      body: !teacher
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Only teacher accounts can create exams.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : Padding(
              // Room for the button below the last exam.
              padding: const EdgeInsets.only(bottom: 72),
              child: ExamsTab(account: account),
            ),
    );
  }
}
