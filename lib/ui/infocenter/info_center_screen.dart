import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import 'absences_tab.dart';
import 'exams_tab.dart';
import 'homework_tab.dart';
import 'info_common.dart';
import 'info_providers.dart';
import 'messages_tab.dart';
import 'office_hours_tab.dart';

extension on InfoTab {
  String get label => switch (this) {
    InfoTab.messages => 'Messages',
    InfoTab.homework => 'Homework',
    InfoTab.exams => 'Exams',
    InfoTab.absences => 'Absences',
    InfoTab.officeHours => 'Office hours',
  };

  (IconData, IconData) get icons => switch (this) {
    InfoTab.messages => (Icons.mail_outline, Icons.mail),
    InfoTab.homework => (Icons.assignment_outlined, Icons.assignment),
    InfoTab.exams => (Icons.quiz_outlined, Icons.quiz),
    InfoTab.absences => (Icons.event_busy_outlined, Icons.event_busy),
    InfoTab.officeHours => (Icons.support_agent_outlined, Icons.support_agent),
  };
}

/// `/info`: messages, homework, exams, absences and office hours of the
/// active account. Bottom navigation on phones, a rail from 600 dp.
class InfoCenterScreen extends ConsumerWidget {
  const InfoCenterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountAsync = ref.watch(activeAccountProvider);
    final account = accountAsync.value;
    if (account == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Info center')),
        body: accountAsync.isLoading
            ? const Center(child: CircularProgressIndicator())
            : const InfoEmptyState(
                icon: Icons.person_off_outlined,
                title: 'No account',
                message: 'Add an account to see its messages.',
              ),
      );
    }

    final tabs = visibleInfoTabs(account);
    final remembered = ref.watch(infoTabProvider);
    final tab = tabs.contains(remembered) ? remembered : tabs.first;
    final index = tabs.indexOf(tab);
    void select(int i) => ref.read(infoTabProvider.notifier).set(tabs[i]);

    final body = KeyedSubtree(
      key: ValueKey('info-tab-${tab.name}-${account.id}'),
      child: switch (tab) {
        InfoTab.messages => MessagesTab(account: account),
        InfoTab.homework => HomeworkTab(account: account),
        InfoTab.exams => ExamsTab(account: account),
        InfoTab.absences => AbsencesTab(account: account),
        InfoTab.officeHours => OfficeHoursTab(account: account),
      },
    );

    final wide = MediaQuery.sizeOf(context).width >= 600;
    final showNav = tabs.length > 1;
    final title = showNav ? tab.label : 'Messages of the day';

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: showNav && wide
          ? SafeArea(
              top: false,
              bottom: false,
              child: Row(
                children: [
                  NavigationRail(
                    selectedIndex: index,
                    onDestinationSelected: select,
                    labelType: NavigationRailLabelType.all,
                    destinations: [
                      for (final t in tabs)
                        NavigationRailDestination(
                          icon: Icon(t.icons.$1),
                          selectedIcon: Icon(t.icons.$2),
                          label: Text(t.label),
                        ),
                    ],
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: body),
                ],
              ),
            )
          : body,
      bottomNavigationBar: showNav && !wide
          ? NavigationBar(
              selectedIndex: index,
              onDestinationSelected: select,
              destinations: [
                for (final t in tabs)
                  NavigationDestination(
                    icon: Icon(t.icons.$1),
                    selectedIcon: Icon(t.icons.$2),
                    label: t.label,
                  ),
              ],
            )
          : null,
    );
  }
}
