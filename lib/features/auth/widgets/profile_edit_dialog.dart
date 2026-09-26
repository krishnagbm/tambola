import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/mpt_user.dart';
import '../../../providers/app_providers.dart';
import 'auth_dialog.dart';

class ProfileEditDialog extends ConsumerStatefulWidget {
  final MptUser currentUser;
  final Set<String>? takenNames;

  const ProfileEditDialog({
    super.key,
    required this.currentUser,
    this.takenNames,
  });

  @override
  ConsumerState<ProfileEditDialog> createState() => _ProfileEditDialogState();
}

class _ProfileEditDialogState extends ConsumerState<ProfileEditDialog> {
  late TextEditingController _nameController;
  late String _selectedAvatar;

  final List<Map<String, String>> _avatars = [
    {'key': 'avatar_lion', 'emoji': '🦁', 'name': 'Lion'},
    {'key': 'avatar_tiger', 'emoji': '🐯', 'name': 'Tiger'},
    {'key': 'avatar_crown', 'emoji': '👑', 'name': 'Royal'},
    {'key': 'avatar_wizard', 'emoji': '🧙', 'name': 'Wizard'},
    {'key': 'avatar_rocket', 'emoji': '🚀', 'name': 'Rocket'},
    {'key': 'avatar_fox', 'emoji': '🦊', 'name': 'Fox'},
    {'key': 'avatar_panda', 'emoji': '🐼', 'name': 'Panda'},
    {'key': 'avatar_unicorn', 'emoji': '🦄', 'name': 'Unicorn'},
    {'key': 'avatar_cowboy', 'emoji': '🤠', 'name': 'Cowboy'},
    {'key': 'avatar_star', 'emoji': '🌟', 'name': 'Star'},
    {'key': 'avatar_bullseye', 'emoji': '🎯', 'name': 'Bullseye'},
    {'key': 'avatar_rocker', 'emoji': '🎸', 'name': 'Rocker'},
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.currentUser.displayName);
    _selectedAvatar = widget.currentUser.avatar;
    if (!_avatars.any((a) => a['key'] == _selectedAvatar)) {
      _selectedAvatar = 'avatar_lion';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.darkCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Your Nickname & Profile', style: TextStyle(fontWeight: FontWeight.bold)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Pick a fun nickname for this game and an avatar character (no email or phone required).',
              style: TextStyle(fontSize: 13, color: Color(0xFFA0AEC0)),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Your Nickname in this Game',
                hintText: 'e.g. Tiger King, Lucky7, Party Animal',
                helperText: 'This is shown to other players and on our public Recent Games page if you win.',
                helperMaxLines: 2,
                prefixIcon: Icon(Icons.sports_esports_outlined),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0x1A3B82F6),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0x333B82F6)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 16, color: Color(0xFF60A5FA)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Duplicate nicknames may occur with auto-generated names. If you don\'t want your own name shown, feel free to use your creativity to pick a unique nickname for this game!',
                      style: TextStyle(fontSize: 12, color: Color(0xFFCBD5E1), height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text('Choose Avatar Character', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _avatars.map((av) {
                final isSelected = av['key'] == _selectedAvatar;
                return GestureDetector(
                  onTap: () => setState(() => _selectedAvatar = av['key']!),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: isSelected ? AppTheme.primaryColor.withOpacity(0.2) : AppTheme.darkSurface,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? AppTheme.primaryColor : const Color(0xFF2E334D),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: CircleAvatar(
                      backgroundColor: isSelected ? AppTheme.primaryLight.withOpacity(0.4) : AppTheme.darkSurface,
                      radius: 20,
                      child: Text(
                        av['emoji']!,
                        style: const TextStyle(fontSize: 20),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            Builder(
              builder: (context) {
                final effectiveUser = ref.watch(currentUserProvider).value ?? widget.currentUser;
                final isRegistered = effectiveUser.isRegistered;

                if (isRegistered) {
                  final providerLabel = effectiveUser.provider != null && effectiveUser.provider!.isNotEmpty
                      ? effectiveUser.provider!
                      : 'verified account';
                  final emailOrProvider = effectiveUser.email != null && effectiveUser.email!.isNotEmpty
                      ? effectiveUser.email!
                      : 'Linked via $providerLabel';

                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.accentSuccess.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.accentSuccess.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.verified_user_outlined, size: 20, color: AppTheme.accentSuccess),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '✓ Account Protected',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.accentSuccess),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Protected & linked to $emailOrProvider',
                                style: const TextStyle(fontSize: 11.5, color: Color(0xFFCBD5E1)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.darkSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.secondaryColor.withValues(alpha: 0.4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.shield_outlined, size: 18, color: AppTheme.secondaryColor),
                          SizedBox(width: 6),
                          Text(
                            'Account Protection (Optional)',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.secondaryColor),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Link Google, Apple, Microsoft, or Email OTP to safeguard tickets, game history, and rewards against browser cache wipes or device changes.',
                        style: TextStyle(fontSize: 11.5, color: Color(0xFFCBD5E1), height: 1.3),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            await AuthDialog.show(context);
                            if (mounted) {
                              final updated = ref.read(currentUserProvider).value;
                              if (updated != null && _nameController.text.trim().isEmpty) {
                                _nameController.text = updated.displayName;
                              }
                              setState(() {});
                            }
                          },
                          icon: const Icon(Icons.login, size: 16),
                          label: const Text('Sign In / Protect Account'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.secondaryColor,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                            textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () async {
            final name = _nameController.text.trim();
            if (name.isNotEmpty) {
              if (widget.takenNames != null && widget.takenNames!.contains(name.toLowerCase())) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('"$name" is already in use in this game room. Please choose another nickname.'),
                    backgroundColor: AppTheme.accentDanger,
                  ),
                );
                return;
              }
              await ref.read(currentUserProvider.notifier).updateProfile(
                    displayName: name,
                    avatar: _selectedAvatar,
                  );
            }
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Save Profile'),
        ),
      ],
    );
  }
}
