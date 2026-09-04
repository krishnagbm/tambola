import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/mpt_user.dart';
import '../../../providers/app_providers.dart';

class ProfileEditDialog extends ConsumerStatefulWidget {
  final MptUser currentUser;

  const ProfileEditDialog({super.key, required this.currentUser});

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
      title: const Text('Player Profile', style: TextStyle(fontWeight: FontWeight.bold)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Choose your gameplay display name and avatar (no email or phone required).',
              style: TextStyle(fontSize: 13, color: Color(0xFFA0AEC0)),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Display Name',
                prefixIcon: Icon(Icons.person_outline),
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
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.darkSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF2E334D)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.shield_outlined, size: 18, color: AppTheme.secondaryColor),
                      SizedBox(width: 6),
                      Text(
                        'Account Protection (Optional)',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.secondaryColor),
                      ),
                    ],
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Link Google or Apple in settings to recover rewards if you change devices.',
                    style: TextStyle(fontSize: 12, color: Color(0xFFCBD5E1)),
                  ),
                ],
              ),
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
