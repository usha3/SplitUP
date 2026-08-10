import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/group_model.dart';
import '../../services/group_service.dart';
import '../../services/user_service.dart';

enum _AddMemberMode {
  registered,
  guest,
}

class ManageMembersScreen extends StatefulWidget {
  final GroupModel group;

  const ManageMembersScreen({
    super.key,
    required this.group,
  });

  @override
  State<ManageMembersScreen> createState() =>
      _ManageMembersScreenState();
}

class _ManageMembersScreenState extends State<ManageMembersScreen> {
  final GroupService _groupService = GroupService();
  final UserService _userService = UserService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<Map<String, _MemberViewData>> _loadMembers(
      GroupModel group,
      ) async {
    final registeredUsers =
    await _userService.getUsersByIds(group.members);

    final groupDocument =
    await _firestore.collection('groups').doc(group.id).get();

    final groupData = groupDocument.data() ?? {};
    final rawMemberDetails = groupData['memberDetails'];

    final memberDetails = rawMemberDetails is Map
        ? Map<String, dynamic>.from(rawMemberDetails)
        : <String, dynamic>{};

    final members = <String, _MemberViewData>{};

    for (final memberId in group.members) {
      final registeredUser = registeredUsers[memberId];

      final rawDetails = memberDetails[memberId];

      final details = rawDetails is Map
          ? Map<String, dynamic>.from(rawDetails)
          : <String, dynamic>{};

      final addedAt = _toDateTime(details['addedAt']);

      if (registeredUser != null) {
        members[memberId] = _MemberViewData(
          id: memberId,
          name: registeredUser.name.trim(),
          email: registeredUser.email.trim(),
          isGuest: false,

          // If the creator doesn't have addedAt,
          // use the group creation date.
          addedAt: addedAt ??
              (memberId == group.createdBy
                  ? group.createdAt
                  : null),
        );

        continue;
      }

      final name =
          details['name']?.toString().trim() ?? '';

      final email =
          details['email']?.toString().trim() ?? '';

      final isGuest =
          details['isGuest'] == true ||
              memberId.startsWith('guest_');

      members[memberId] = _MemberViewData(
        id: memberId,
        name: name.isEmpty
            ? (isGuest
            ? 'Guest member'
            : 'Unknown user')
            : name,
        email: email,
        isGuest: isGuest,
        addedAt: addedAt ??
            (memberId == group.createdBy
                ? group.createdAt
                : null),
      );
    }

    return members;
  }

  Future<void> _showAddMemberDialog(
      GroupModel currentGroup,
      ) async {
    final registeredEmailController = TextEditingController();
    final guestNameController = TextEditingController();
    final guestEmailController = TextEditingController();

    final formKey = GlobalKey<FormState>();

    var selectedMode = _AddMemberMode.registered;
    var isLoading = false;
    String? errorMessage;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submit() async {
              if (!(formKey.currentState?.validate() ?? false)) {
                return;
              }

              setDialogState(() {
                isLoading = true;
                errorMessage = null;
              });

              try {
                if (selectedMode == _AddMemberMode.registered) {
                  final user = await _userService.findUserByEmail(
                    registeredEmailController.text,
                  );

                  if (user == null) {
                    if (!dialogContext.mounted) return;

                    setDialogState(() {
                      isLoading = false;
                      errorMessage =
                      'No registered SplitUP user was found for this email.';
                    });

                    return;
                  }

                  if (currentGroup.members.contains(user.uid)) {
                    if (!dialogContext.mounted) return;

                    final displayName = user.name.trim().isEmpty
                        ? user.email
                        : user.name;

                    setDialogState(() {
                      isLoading = false;
                      errorMessage =
                      '$displayName is already a member of this group.';
                    });

                    return;
                  }

                  await _groupService.addRegisteredMember(
                    groupId: currentGroup.id,
                    user: user,
                  );

                  if (!dialogContext.mounted || !mounted) return;

                  final displayName = user.name.trim().isEmpty
                      ? user.email
                      : user.name;

                  Navigator.of(dialogContext).pop();

                  ScaffoldMessenger.of(this.context).showSnackBar(
                    SnackBar(
                      content: Text('$displayName added to the group.'),
                    ),
                  );

                  return;
                }

                final guestName = guestNameController.text.trim();
                final guestEmail =
                guestEmailController.text.trim().toLowerCase();

                await _groupService.addGuestMember(
                  groupId: currentGroup.id,
                  name: guestName,
                  email: guestEmail,
                );

                if (!dialogContext.mounted || !mounted) return;

                Navigator.of(dialogContext).pop();

                ScaffoldMessenger.of(this.context).showSnackBar(
                  SnackBar(
                    content: Text('$guestName added as a guest member.'),
                  ),
                );
              } catch (error) {
                if (!dialogContext.mounted) return;

                setDialogState(() {
                  isLoading = false;
                  errorMessage = 'Unable to add member: $error';
                });
              }
            }

            return AlertDialog(
              title: const Text('Add member'),
              content: SizedBox(
                width: 420,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment:
                      CrossAxisAlignment.stretch,
                      children: [
                        SegmentedButton<_AddMemberMode>(
                          segments: const [
                            ButtonSegment(
                              value: _AddMemberMode.registered,
                              icon: Icon(Icons.person_search_outlined),
                              label: Text('Registered'),
                            ),
                            ButtonSegment(
                              value: _AddMemberMode.guest,
                              icon: Icon(Icons.person_add_outlined),
                              label: Text('Guest'),
                            ),
                          ],
                          selected: {selectedMode},
                          onSelectionChanged: isLoading
                              ? null
                              : (selection) {
                            setDialogState(() {
                              selectedMode = selection.first;
                              errorMessage = null;
                            });
                          },
                        ),
                        const SizedBox(height: 20),
                        if (selectedMode ==
                            _AddMemberMode.registered) ...[
                          const Text(
                            'Enter the email address of an existing '
                                'SplitUP user.',
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller:
                            registeredEmailController,
                            enabled: !isLoading,
                            autofocus: true,
                            keyboardType:
                            TextInputType.emailAddress,
                            textInputAction: TextInputAction.done,
                            decoration: const InputDecoration(
                              labelText: 'Registered user email',
                              prefixIcon:
                              Icon(Icons.email_outlined),
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              if (selectedMode !=
                                  _AddMemberMode.registered) {
                                return null;
                              }

                              final email = value?.trim() ?? '';

                              if (email.isEmpty) {
                                return 'Enter the user’s email';
                              }

                              if (!_isValidEmail(email)) {
                                return 'Enter a valid email address';
                              }

                              return null;
                            },
                            onFieldSubmitted: (_) {
                              if (!isLoading) {
                                submit();
                              }
                            },
                          ),
                        ] else ...[
                          const Text(
                            'Add someone who does not yet have a '
                                'SplitUP account.',
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: guestNameController,
                            enabled: !isLoading,
                            autofocus: true,
                            textInputAction: TextInputAction.next,
                            textCapitalization:
                            TextCapitalization.words,
                            decoration: const InputDecoration(
                              labelText: 'Guest name',
                              prefixIcon:
                              Icon(Icons.person_outline),
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              if (selectedMode !=
                                  _AddMemberMode.guest) {
                                return null;
                              }

                              final name = value?.trim() ?? '';

                              if (name.isEmpty) {
                                return 'Enter the guest’s name';
                              }

                              if (name.length < 2) {
                                return 'Name must contain at least 2 characters';
                              }

                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: guestEmailController,
                            enabled: !isLoading,
                            keyboardType:
                            TextInputType.emailAddress,
                            textInputAction: TextInputAction.done,
                            decoration: const InputDecoration(
                              labelText: 'Email (optional)',
                              prefixIcon:
                              Icon(Icons.email_outlined),
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              if (selectedMode !=
                                  _AddMemberMode.guest) {
                                return null;
                              }

                              final email = value?.trim() ?? '';

                              if (email.isNotEmpty &&
                                  !_isValidEmail(email)) {
                                return 'Enter a valid email address';
                              }

                              return null;
                            },
                            onFieldSubmitted: (_) {
                              if (!isLoading) {
                                submit();
                              }
                            },
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Guest members can participate in expenses '
                                'and balances, but they cannot sign in.',
                            style: TextStyle(fontSize: 13),
                          ),
                        ],
                        if (errorMessage != null) ...[
                          const SizedBox(height: 16),
                          Text(
                            errorMessage!,
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .error,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isLoading
                      ? null
                      : () {
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: isLoading ? null : submit,
                  icon: isLoading
                      ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                      : Icon(
                    selectedMode ==
                        _AddMemberMode.registered
                        ? Icons.person_add_alt_1
                        : Icons.add,
                  ),
                  label: Text(
                    selectedMode == _AddMemberMode.registered
                        ? 'Add User'
                        : 'Add Guest',
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    registeredEmailController.dispose();
    guestNameController.dispose();
    guestEmailController.dispose();
  }

  Future<void> _confirmRemoveMember({
    required GroupModel group,
    required _MemberViewData member,
  }) async {
    final shouldRemove = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Remove member?'),
          content: Text(
            'Remove ${member.displayName} from this group?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );

    if (shouldRemove != true) {
      return;
    }

    try {
      await _groupService.removeMember(
        groupId: group.id,
        userId: member.id,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${member.displayName} removed.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to remove member: $error'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId =
        FirebaseAuth.instance.currentUser?.uid;

    return StreamBuilder<GroupModel?>(
      stream: _groupService.watchGroup(widget.group.id),
      builder: (context, groupSnapshot) {
        if (groupSnapshot.connectionState ==
            ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (groupSnapshot.hasError) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Members'),
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Unable to load group: '
                      '${groupSnapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        final group = groupSnapshot.data;

        if (group == null) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Members'),
            ),
            body: const Center(
              child: Text('This group no longer exists.'),
            ),
          );
        }

        final canManageMembers =
            currentUserId == group.createdBy;

        return Scaffold(
          appBar: AppBar(
            title: Text('${group.name} members'),
          ),
          floatingActionButton: canManageMembers
              ? FloatingActionButton.extended(
            onPressed: () {
              _showAddMemberDialog(group);
            },
            icon: const Icon(Icons.person_add_rounded),
            label: const Text('Add Member'),
          )
              : null,
          body: FutureBuilder<Map<String, _MemberViewData>>(
            future: _loadMembers(group),
            builder: (context, memberSnapshot) {
              if (memberSnapshot.connectionState ==
                  ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(),
                );
              }

              if (memberSnapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Unable to load members: '
                          '${memberSnapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }

              final members = memberSnapshot.data ?? {};

              if (group.members.isEmpty) {
                return const Center(
                  child: Text('No members found.'),
                );
              }

              return ListView.separated(
                padding:
                const EdgeInsets.fromLTRB(16, 16, 16, 100),
                itemCount: group.members.length,
                separatorBuilder: (_, _) =>
                const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final memberId = group.members[index];

                  final member = members[memberId] ??
                      _MemberViewData(
                        id: memberId,
                        name: memberId.startsWith('guest_')
                            ? 'Guest member'
                            : 'Unknown user',
                        email: '',
                        isGuest:
                        memberId.startsWith('guest_'),
                      );

                  final isCreator =
                      memberId == group.createdBy;
                  final isCurrentUser =
                      memberId == currentUserId;

                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        child: member.displayName.isEmpty
                            ? const Icon(Icons.person)
                            : Text(
                          member.displayName[0]
                              .toUpperCase(),
                        ),
                      ),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(
                              isCurrentUser
                                  ? '${member.displayName} (You)'
                                  : member.displayName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (member.isGuest) ...[
                            const SizedBox(width: 8),
                            const Chip(
                              label: Text('Guest'),
                              visualDensity:
                              VisualDensity.compact,
                            ),
                          ],
                        ],
                      ),
                      subtitle: Text(
                        _memberSubtitle(
                          member: member,
                          isCreator: isCreator,
                        ),
                      ),

                      trailing: isCreator
                          ? const Icon(
                        Icons
                            .admin_panel_settings_outlined,
                      )
                          : canManageMembers
                          ? PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'remove') {
                            _confirmRemoveMember(
                              group: group,
                              member: member,
                            );
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'remove',
                            child: Row(
                              children: [
                                Icon(
                                  Icons
                                      .person_remove_outlined,
                                ),
                                SizedBox(width: 10),
                                Text('Remove member'),
                              ],
                            ),
                          ),
                        ],
                      )
                          : null,
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  static DateTime? _toDateTime(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }

    return null;
  }

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

    return '${months[date.month - 1]} '
        '${date.day}, ${date.year}';
  }

  static bool _isValidEmail(String email) {
    return RegExp(
      r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
    ).hasMatch(email);
  }

  static String _memberSubtitle({
    required _MemberViewData member,
    required bool isCreator,
  }) {
    final parts = <String>[];

    if (member.email.isNotEmpty) {
      parts.add(member.email);
    }

    if (isCreator) {
      parts.add('Group creator');
    } else if (member.isGuest) {
      parts.add('Guest member');
    }

    if (member.addedAt != null) {
      parts.add(
        isCreator
            ? 'Created group: ${_formatDate(member.addedAt!)}'
            : 'Joined: ${_formatDate(member.addedAt!)}',
      );
    }

    return parts.isEmpty
        ? 'Member'
        : parts.join('\n');
  }
}

class _MemberViewData {
  final String id;
  final String name;
  final String email;
  final bool isGuest;
  final DateTime? addedAt;

  const _MemberViewData({
    required this.id,
    required this.name,
    required this.email,
    required this.isGuest,
    this.addedAt,
  });

  String get displayName {
    final trimmedName = name.trim();

    if (trimmedName.isNotEmpty) {
      return trimmedName;
    }

    final trimmedEmail = email.trim();

    if (trimmedEmail.isNotEmpty) {
      return trimmedEmail;
    }

    return isGuest ? 'Guest member' : 'Unknown user';
  }
}