import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/mpt_game.dart';
import '../../../models/mpt_user.dart';
import '../../../providers/app_providers.dart';
import '../../auth/widgets/profile_edit_dialog.dart';

class JoinGameScreen extends ConsumerStatefulWidget {
  final String? initialCode;

  const JoinGameScreen({super.key, this.initialCode});

  @override
  ConsumerState<JoinGameScreen> createState() => _JoinGameScreenState();
}

class _JoinGameScreenState extends ConsumerState<JoinGameScreen> {
  late TextEditingController _codeController;
  MptGame? _previewGame;
  bool _isSearching = false;
  bool _isRegistering = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _codeController = TextEditingController(text: widget.initialCode ?? '');
    if (widget.initialCode != null && widget.initialCode!.isNotEmpty) {
      _lookupGame(widget.initialCode!);
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _lookupGame(String code) async {
    final cleanCode = code.trim().toUpperCase();
    if (cleanCode.isEmpty) return;

    setState(() {
      _isSearching = true;
      _errorMessage = null;
      _previewGame = null;
    });

    try {
      final game = await ref.read(gameRepositoryProvider).getGameByInviteCode(cleanCode);
      if (game == null) {
        setState(() => _errorMessage = 'Game not found. Please verify the invite code.');
      } else {
        setState(() => _previewGame = game);
      }
    } catch (e) {
      setState(() => _errorMessage = 'Error finding game: $e');
    } finally {
      setState(() => _isSearching = false);
    }
  }

  Future<void> _handleRegister() async {
    if (_previewGame == null) return;
    final user = ref.read(currentUserProvider).value;
    if (user == null) return;

    setState(() => _isRegistering = true);
    try {
      await ref.read(gameRepositoryProvider).registerPlayer(
            gameId: _previewGame!.id,
            displayName: user.displayName,
            avatar: user.avatar,
          );

      if (!mounted) return;
      context.go('/game-status/${_previewGame!.id}');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Registration failed: $e'), backgroundColor: AppTheme.accentDanger),
      );
    } finally {
      if (mounted) setState(() => _isRegistering = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userState = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Join Tambola Game'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Enter the 6-character invite code provided by your Game Admin:',
              style: TextStyle(fontSize: 14, color: Color(0xFFA0AEC0)),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _codeController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      hintText: 'e.g. 7K9Q2X',
                      prefixIcon: const Icon(Icons.pin),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.search),
                        onPressed: () => _lookupGame(_codeController.text),
                      ),
                    ),
                    onSubmitted: _lookupGame,
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _isSearching ? null : () => _lookupGame(_codeController.text),
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14)),
                  child: _isSearching
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Find'),
                ),
              ],
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.accentDanger.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.accentDanger.withOpacity(0.3)),
                ),
                child: Text(_errorMessage!, style: const TextStyle(color: AppTheme.accentDanger, fontSize: 13)),
              ),
            ],
            const SizedBox(height: 24),

            // Game Preview Card
            if (_previewGame != null) ...[
              _buildGamePreviewCard(_previewGame!),
              const SizedBox(height: 20),

              // Player Gameplay Identity Check
              userState.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text('Error: $e'),
                data: (user) => _buildPlayerProfileBar(user),
              ),
              const SizedBox(height: 24),

              ElevatedButton(
                onPressed: _isRegistering ? null : _handleRegister,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentSuccess,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isRegistering
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Register & Get Ticket', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildGamePreviewCard(MptGame game) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    game.name,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.primaryColor),
                  ),
                  child: Text(
                    game.status,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primaryLight),
                  ),
                ),
              ],
            ),
            const Divider(color: Color(0xFF2E334D), height: 24),
            Row(
              children: [
                const Icon(Icons.people_outline, size: 18, color: AppTheme.secondaryColor),
                const SizedBox(width: 8),
                Text(
                  'Funded Capacity: ${game.fundedCapacity} Seats',
                  style: const TextStyle(fontSize: 14, color: Color(0xFFCBD5E1)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.emoji_events_outlined, size: 18, color: AppTheme.secondaryColor),
                const SizedBox(width: 8),
                Text(
                  '${game.prizesConfig.length} Prizes Configured',
                  style: const TextStyle(fontSize: 14, color: Color(0xFFCBD5E1)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerProfileBar(MptUser user) {
    return Card(
      color: AppTheme.darkSurface,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const CircleAvatar(
              radius: 20,
              backgroundColor: AppTheme.primaryColor,
              child: Text('🤹', style: TextStyle(fontSize: 18)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Playing as:', style: TextStyle(fontSize: 11, color: Color(0xFFA0AEC0))),
                  Text(
                    user.displayName,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => showDialog(
                context: context,
                builder: (_) => ProfileEditDialog(currentUser: user),
              ),
              child: const Text('Change'),
            ),
          ],
        ),
      ),
    );
  }
}
