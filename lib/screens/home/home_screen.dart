import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/dashboard_summary.dart';
import '../../models/group_model.dart';
import '../../services/dashboard_service.dart';
import '../../services/group_service.dart';
import '../groups/create_group_screen.dart';
import '../groups/group_details_screen.dart';
import 'package:provider/provider.dart';

import '../../providers/theme_provider.dart';
import '../profile/change_password_screen.dart';
import '../profile/edit_profile_screen.dart';
import '../analytics/analytics_screen.dart';
import '../../services/notification_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../../services/in_app_notification_service.dart';
import '../notifications/notifications_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final DashboardService _dashboardService = DashboardService();
  final GroupService _groupService = GroupService();
  final NotificationService _notificationService =
  NotificationService();
  final InAppNotificationService
  _inAppNotificationService =
  InAppNotificationService();

  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeNotifications();
    });
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
  }

  Future<void> _openCreateGroup() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const CreateGroupScreen(),
      ),
    );
  }

  Future<void> _initializeNotifications() async {
    await _notificationService.initialize(
      onForegroundMessage: (message) {
        debugPrint(
          'Foreground notification received: ${message.messageId}',
        );

        // NotificationService now displays the Android
        // heads-up notification, so no SnackBar is needed here.
      },
      onNotificationOpened: (message) {
        if (!mounted) return;

        _handleNotificationNavigation(message);
      },
    );

    final token = await _notificationService.getToken();
    debugPrint('FCM TOKEN: $token');
  }

  void _handleNotificationNavigation(
      RemoteMessage message,
      ) {
    final type = message.data['type'];
    final groupId = message.data['groupId'];

    debugPrint(
      'Notification opened: type=$type, groupId=$groupId',
    );

    // We will connect group navigation after the
    // server notification payload is implemented.
  }

  @override
  void dispose() {
    _notificationService.dispose();
    super.dispose();
  }

  Future<void> _refreshProfile() async {
    await FirebaseAuth.instance.currentUser?.reload();

    if (!mounted) return;

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    final displayName = user?.displayName?.trim().isNotEmpty == true
        ? user!.displayName!.trim()
        : 'Usha';

    final photoUrl = user?.photoURL ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('SplitUP'),
        actions: [
          if (user != null)
            StreamBuilder<int>(
              stream: _inAppNotificationService
                  .getUnreadCount(user.uid),
              builder: (context, snapshot) {
                final unreadCount =
                    snapshot.data ?? 0;

                return IconButton(
                  tooltip: 'Notifications',
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                        const NotificationsScreen(),
                      ),
                    );
                  },
                  icon: Badge(
                    isLabelVisible:
                    unreadCount > 0,
                    label: Text(
                      unreadCount > 99
                          ? '99+'
                          : '$unreadCount',
                    ),
                    child: Icon(
                      unreadCount > 0
                          ? Icons.notifications_rounded
                          : Icons
                          .notifications_none_rounded,
                    ),
                  ),
                );
              },
            ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'logout') {
                _logout();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout_rounded),
                    SizedBox(width: 12),
                    Text('Logout'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _DashboardTab(
            displayName: displayName,
            photoUrl: photoUrl,
            dashboardService: _dashboardService,
            groupService: _groupService,
            onCreateGroup: _openCreateGroup,
          ),
          _GroupsTab(
            groupService: _groupService,
            onCreateGroup: _openCreateGroup,
          ),
          _ProfileTab(
            displayName: displayName,
            email: user?.email ?? '',
            photoUrl: photoUrl,
            onLogout: _logout,
            onProfileUpdated: _refreshProfile,
          ),
        ],
      ),
      floatingActionButton: _selectedIndex == 0
          ? FloatingActionButton.extended(
        onPressed: _openCreateGroup,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Group'),
      )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.groups_outlined),
            selectedIcon: Icon(Icons.groups_rounded),
            label: 'Groups',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class _DashboardTab extends StatelessWidget {
  final String displayName;
  final DashboardService dashboardService;
  final GroupService groupService;
  final VoidCallback onCreateGroup;
  final String photoUrl;

  const _DashboardTab({
    required this.displayName,
    required this.dashboardService,
    required this.groupService,
    required this.onCreateGroup,
    required this.photoUrl,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
        children: [
          _GreetingHeader(
            displayName: displayName,
            photoUrl: photoUrl,
          ),
          const SizedBox(height: 24),

          StreamBuilder<DashboardSummary>(
            stream: dashboardService.watchSummary(),
            builder: (context, snapshot) {
              if (snapshot.connectionState ==
                  ConnectionState.waiting) {
                return const _LoadingCard(
                  height: 260,
                );
              }

              if (snapshot.hasError) {
                return _ErrorCard(
                  message:
                  'Unable to load dashboard: ${snapshot.error}',
                );
              }

              final summary =
                  snapshot.data ?? const DashboardSummary.empty();

              return Column(
                children: [
                  _NetBalanceCard(
                    summary: summary,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          icon: Icons.arrow_upward_rounded,
                          label: 'You owe',
                          value:
                          '\$${summary.youOwe.toStringAsFixed(2)}',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatCard(
                          icon: Icons.arrow_downward_rounded,
                          label: 'You are owed',
                          value:
                          '\$${summary.youAreOwed.toStringAsFixed(2)}',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          icon: Icons.calendar_month_outlined,
                          label: 'This month',
                          value:
                          '\$${summary.monthlySpending.toStringAsFixed(2)}',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatCard(
                          icon: Icons.groups_outlined,
                          label: 'Active groups',
                          value: '${summary.activeGroups}',
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 24),

          const _InsightCard(),

          const SizedBox(height: 28),

          _SectionHeader(
            title: 'Your groups',
            actionLabel: 'Create',
            onPressed: onCreateGroup,
          ),

          const SizedBox(height: 12),

          StreamBuilder<List<GroupModel>>(
            stream: groupService.getCurrentUserGroups(),
            builder: (context, snapshot) {
              if (snapshot.connectionState ==
                  ConnectionState.waiting) {
                return const _LoadingCard(
                  height: 130,
                );
              }

              if (snapshot.hasError) {
                return _ErrorCard(
                  message:
                  'Unable to load groups: ${snapshot.error}',
                );
              }

              final groups = snapshot.data ?? [];

              if (groups.isEmpty) {
                return _EmptyGroupsCard(
                  onCreateGroup: onCreateGroup,
                );
              }

              final visibleGroups = groups.take(3).toList();

              return Column(
                children: visibleGroups
                    .map(
                      (group) => Padding(
                    padding:
                    const EdgeInsets.only(bottom: 12),
                    child: _PremiumGroupCard(
                      group: group,
                    ),
                  ),
                )
                    .toList(),
              );
            },
          ),

          const SizedBox(height: 12),

          _SectionHeader(
            title: 'Quick actions',
            actionLabel: '',
            onPressed: () {},
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: _QuickActionCard(
                  icon: Icons.group_add_outlined,
                  label: 'Create Group',
                  onTap: onCreateGroup,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _QuickActionCard(
                  icon: Icons.analytics_outlined,
                  label: 'Analytics',
                  onTap: () async {
                    final shouldAddExpense =
                    await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => const AnalyticsScreen(),
                      ),
                    );

                    if (!context.mounted) return;

                    if (shouldAddExpense == true) {
                      // For now, switch the user to the Groups tab or open
                      // the group-selection flow used by your app.
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GreetingHeader extends StatelessWidget {
  final String displayName;
  final String photoUrl;

  const _GreetingHeader({
    required this.displayName,
    required this.photoUrl,
  });

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;

    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
        ? 'Good afternoon'
        : 'Good evening';

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$greeting,',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$displayName 👋',
                style: Theme.of(context)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        CircleAvatar(
          radius: 28,
          backgroundColor:
          Theme.of(context).colorScheme.primaryContainer,
          backgroundImage: photoUrl.trim().isNotEmpty
              ? NetworkImage(photoUrl)
              : null,
          child: photoUrl.trim().isEmpty
              ? Text(
            displayName.isEmpty
                ? '?'
                : displayName[0].toUpperCase(),
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context)
                  .colorScheme
                  .onPrimaryContainer,
            ),
          )
              : null,
        ),
      ],
    );
  }
}

class _NetBalanceCard extends StatelessWidget {
  final DashboardSummary summary;

  const _NetBalanceCard({
    required this.summary,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final prefix = summary.netBalance > 0 ? '+' : '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.primary,
            colorScheme.tertiary,
          ],
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.account_balance_wallet_outlined,
                color: Colors.white,
              ),
              const SizedBox(width: 10),
              Text(
                'Net balance',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            '$prefix\$${summary.netBalance.toStringAsFixed(2)}',
            style: Theme.of(context)
                .textTheme
                .displaySmall
                ?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _balanceMessage(summary.netBalance),
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(
              color: Colors.white.withValues(
                alpha: 0.9,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _balanceMessage(double balance) {
    if (balance > 0.01) {
      return 'You are owed money overall';
    }

    if (balance < -0.01) {
      return 'You currently owe money';
    }

    return 'You are all settled up';
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: Theme.of(context)
                  .colorScheme
                  .secondaryContainer,
              child: Icon(
                icon,
                size: 20,
                color: Theme.of(context)
                    .colorScheme
                    .onSecondaryContainer,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              value,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(
                color: Theme.of(context)
                    .colorScheme
                    .onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      color: colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: colorScheme.surface,
              child: Icon(
                Icons.auto_awesome_rounded,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Smart insight',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Keep recording expenses to receive personalized '
                        'spending insights and recommendations.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PremiumGroupCard extends StatelessWidget {
  final GroupModel group;

  const _PremiumGroupCard({
    required this.group,
  });

  static String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => GroupDetailsScreen(
                group: group,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .primaryContainer,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  Icons.groups_rounded,
                  color: Theme.of(context)
                      .colorScheme
                      .onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.name,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      group.description.isEmpty
                          ? '${group.members.length} member(s)'
                          : group.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant,
                      ),
                    ),

                    if (group.createdAt != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.calendar_today_outlined,
                            size: 15,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'Created ${_formatDate(group.createdAt!)}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall,
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(
                          Icons.people_outline,
                          size: 17,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '${group.members.length} member(s)',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String actionLabel;
  final VoidCallback onPressed;

  const _SectionHeader({
    required this.title,
    required this.actionLabel,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        if (actionLabel.isNotEmpty)
          TextButton(
            onPressed: onPressed,
            child: Text(actionLabel),
          ),
      ],
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 20,
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 30,
                color:
                Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 10),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyGroupsCard extends StatelessWidget {
  final VoidCallback onCreateGroup;

  const _EmptyGroupsCard({
    required this.onCreateGroup,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            Icon(
              Icons.group_add_outlined,
              size: 54,
              color: Theme.of(context)
                  .colorScheme
                  .primary,
            ),
            const SizedBox(height: 16),
            Text(
              'No groups yet',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Create a group to begin sharing expenses.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onCreateGroup,
              icon: const Icon(Icons.add),
              label: const Text('Create Group'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  final double height;

  const _LoadingCard({
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: SizedBox(
        height: height,
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;

  const _ErrorCard({
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(message),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupsTab extends StatelessWidget {
  final GroupService groupService;
  final VoidCallback onCreateGroup;

  const _GroupsTab({
    required this.groupService,
    required this.onCreateGroup,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<GroupModel>>(
      stream: groupService.getCurrentUserGroups(),
      builder: (context, snapshot) {
        if (snapshot.connectionState ==
            ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Unable to load groups: ${snapshot.error}',
            ),
          );
        }

        final groups = snapshot.data ?? [];

        if (groups.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _EmptyGroupsCard(
                onCreateGroup: onCreateGroup,
              ),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(
            16,
            16,
            16,
            100,
          ),
          itemCount: groups.length,
          separatorBuilder: (_, _) =>
          const SizedBox(height: 12),
          itemBuilder: (context, index) {
            return _PremiumGroupCard(
              group: groups[index],
            );
          },
        );
      },
    );
  }
}

class _ProfileTab extends StatelessWidget {
  final String displayName;
  final String email;
  final Future<void> Function() onLogout;
  final String photoUrl;
  final Future<void> Function() onProfileUpdated;

  const _ProfileTab({
    required this.displayName,
    required this.email,
    required this.onLogout,
    required this.photoUrl,
    required this.onProfileUpdated,
  });

  static String _themeModeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
      case ThemeMode.system:
        return 'System default';
    }
  }

  static Future<void> _showThemeDialog(
      BuildContext context,
      ) async {
    final provider = context.read<ThemeProvider>();

    final selectedMode = await showDialog<ThemeMode>(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          title: const Text('Choose appearance'),
          children: [
            RadioGroup<ThemeMode>(
              groupValue: provider.themeMode,
              onChanged: (value) {
                Navigator.of(dialogContext).pop(value);
              },
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<ThemeMode>(
                    value: ThemeMode.system,
                    title: Text('System default'),
                    secondary: Icon(
                      Icons.settings_suggest_outlined,
                    ),
                  ),
                  RadioListTile<ThemeMode>(
                    value: ThemeMode.light,
                    title: Text('Light'),
                    secondary: Icon(
                      Icons.light_mode_outlined,
                    ),
                  ),
                  RadioListTile<ThemeMode>(
                    value: ThemeMode.dark,
                    title: Text('Dark'),
                    secondary: Icon(
                      Icons.dark_mode_outlined,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );

    if (selectedMode != null) {
      provider.setThemeMode(selectedMode);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 20),
        CircleAvatar(
          radius: 48,
          backgroundColor:
          Theme.of(context).colorScheme.primaryContainer,
          backgroundImage: photoUrl.trim().isNotEmpty
              ? NetworkImage(photoUrl)
              : null,
          child: photoUrl.trim().isEmpty
              ? Text(
            displayName.isEmpty
                ? '?'
                : displayName[0].toUpperCase(),
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          )
              : null,
        ),
        const SizedBox(height: 14),
        Text(
          displayName,
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          email,
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodyLarge
              ?.copyWith(
            color: Theme.of(context)
                .colorScheme
                .onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 28),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit profile'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final updated = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => const EditProfileScreen(),
                    ),
                  );

                  if (!context.mounted) return;

                  // Always reload because the photo may have been uploaded
                  // even when the screen was closed using the Back button.
                  await onProfileUpdated();

                  if (!context.mounted) return;

                  if (updated == true) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Profile updated.'),
                      ),
                    );
                  }
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.dark_mode_outlined),
                title: const Text('Appearance'),
                subtitle: Text(
                  _themeModeLabel(
                    context.watch<ThemeProvider>().themeMode,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  _showThemeDialog(context);
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.password_outlined),
                title: const Text('Change password'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ChangePasswordScreen(),
                    ),
                  );
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(
                  Icons.notifications_outlined,
                ),
                title: const Text('Notifications'),
                trailing:
                const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                      const NotificationsScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: onLogout,
          icon: const Icon(Icons.logout_rounded),
          label: const Text('Logout'),
        ),
      ],
    );
  }
}