import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/mpt_game.dart';
import '../../../models/mpt_user.dart';
import '../../../providers/app_providers.dart';
import '../../../core/widgets/dabhousie_app_bar.dart';
import '../../auth/widgets/profile_edit_dialog.dart';

import '../../../core/widgets/ad_banner_slot.dart';

class JoinGameScreen extends ConsumerStatefulWidget {
  final String? initialCode;

  const JoinGameScreen({super.key, this.initialCode});

  @override
  ConsumerState<JoinGameScreen> createState() => _JoinGameScreenState();
}

class _JoinGameScreenState extends ConsumerState<JoinGameScreen> {
  late TextEditingController _codeController;
  final TextEditingController _otpController = TextEditingController();
  final TextEditingController _nameInputController = TextEditingController();
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
    _otpController.dispose();
    _nameInputController.dispose();
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
      } else if (game.isCancelled) {
        setState(() {
          _errorMessage = 'This game event ("${game.name}") was CANCELLED by the organizer and is no longer accepting players.';
          _previewGame = null;
        });
      } else if (game.isCompleted) {
        setState(() {
          _errorMessage = 'This game event ("${game.name}") has already concluded.';
          _previewGame = null;
        });
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
    if (_previewGame!.isCancelled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot register: This game has been cancelled.'),
          backgroundColor: AppTheme.accentDanger,
        ),
      );
      return;
    }

    // Validate OTP if private game
    if (_previewGame!.isPrivate) {
      final otpText = _otpController.text.trim();
      if (otpText.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This is a Private Party. Please enter your single-use Seat Passcode / OTP provided by your host.'),
            backgroundColor: AppTheme.accentDanger,
          ),
        );
        return;
      }
    }

    final user = ref.read(currentUserProvider).value;
    if (user == null) return;

    String effectiveDisplayName = user.displayName;
    String effectiveAvatar = user.avatar;

    // Check mandatory name before registering if still default 'My Name'
    final trimmedName = user.displayName.trim();
    final lowerName = trimmedName.toLowerCase();
    if (trimmedName.isEmpty || lowerName == 'my name' || lowerName == 'player' || lowerName == 'guest') {
      _nameInputController.text = '';
      final updatedName = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.darkCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.sports_esports_outlined, color: AppTheme.secondaryColor, size: 24),
              SizedBox(width: 8),
              Text('Choose Game Nickname', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Pick a fun nickname for this game room! We recommend choosing a nickname rather than your real name.',
                style: TextStyle(fontSize: 13, color: Color(0xFFCBD5E1)),
              ),
              const SizedBox(height: 14),
              TextField(
                autofocus: true,
                controller: _nameInputController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Game Nickname',
                  hintText: 'e.g. Tiger King, Lucky7, Party Animal',
                  helperText: 'This is shown to other players and on our public Recent Games page if you win.',
                  helperMaxLines: 2,
                  prefixIcon: Icon(Icons.sports_esports_outlined),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final newName = _nameInputController.text.trim();
                if (newName.isNotEmpty && newName.toLowerCase() != 'my name') {
                  await ref.read(currentUserProvider.notifier).updateProfile(
                        displayName: newName,
                        avatar: user.avatar,
                      );
                  if (ctx.mounted) Navigator.pop(ctx, newName);
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.secondaryColor, foregroundColor: Colors.black),
              child: const Text('Save & Join', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );

      if (updatedName == null || updatedName.trim().isEmpty) return;
      effectiveDisplayName = updatedName.trim();
    }

    setState(() => _isRegistering = true);
    try {
      final gameRepo = ref.read(gameRepositoryProvider);

      // If private party, claim seat OTP first
      if (_previewGame!.isPrivate) {
        final otpText = _otpController.text.trim();
        await gameRepo.claimSeatOtp(
          gameId: _previewGame!.id,
          otpCode: otpText,
        );
      }

      await gameRepo.registerPlayer(
        gameId: _previewGame!.id,
        displayName: effectiveDisplayName,
        avatar: effectiveAvatar,
      );

      if (!mounted) return;
      context.go('/game-status/${_previewGame!.id}');
    } catch (e) {
      if (!mounted) return;
      String errorMsg = e.toString();
      if (errorMsg.contains('OTP_ALREADY_CLAIMED')) {
        errorMsg = 'This seat passcode has already been claimed by another player.';
      } else if (errorMsg.contains('INVALID_OTP')) {
        errorMsg = 'Invalid seat passcode. Please verify the OTP given by your organizer.';
      } else if (errorMsg.contains('OTP_REVOKED')) {
        errorMsg = 'This seat passcode has been revoked by the organizer.';
      } else if (errorMsg.contains('PRIVATE_GAME_OTP_REQUIRED')) {
        errorMsg = 'A valid seat passcode is required to join this private party.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Join failed: $errorMsg'), backgroundColor: AppTheme.accentDanger),
      );
    } finally {
      if (mounted) setState(() => _isRegistering = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userState = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: const DabHousieAppBar(
        badgeText: 'Join',
        showBackButton: true,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Enter the 6-character invite code provided by your Game Organizer:',
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
                      color: AppTheme.accentDanger.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.accentDanger.withValues(alpha: 0.3)),
                    ),
                    child: Text(_errorMessage!, style: const TextStyle(color: AppTheme.accentDanger, fontSize: 13)),
                  ),
                ],
                const SizedBox(height: 24),

                // Game Preview Card
                if (_previewGame != null) ...[
                  _buildGamePreviewCard(_previewGame!),
                  const SizedBox(height: 20),

                  // Private Party Seat OTP Input
                  if (_previewGame!.isPrivate) ...[
                    _buildPrivateOtpCard(),
                    const SizedBox(height: 20),
                  ],

                  // Player Gameplay Identity Check
                  userState.when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Text('Error: $e'),
                    data: (user) => _buildPlayerProfileBar(user),
                  ),
                  const SizedBox(height: 20),

                  ElevatedButton(
                    onPressed: _isRegistering ? null : _handleRegister,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentSuccess,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _isRegistering
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Register & Get Ticket', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 20),
                ],

                // Always-Visible Sponsor / Ad Banner Slot
                const AdBannerSlot(
                  slotType: AdSlotType.banner,
                  title: 'DabHousie Live Tambola',
                  subtitle: 'Play live with family & friends • Instant web verification',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPrivateOtpCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.accentPartyPurple.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.accentPartyPurple.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.lock_rounded, color: AppTheme.accentPartyPurple, size: 22),
              SizedBox(width: 8),
              Text(
                'Private Party — Seat Passcode Required',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'This is a private corporate/team party. Enter the unique 6-digit seat passcode assigned to you by your organizer:',
            style: TextStyle(fontSize: 12.5, color: Color(0xFFCBD5E1)),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _otpController,
            keyboardType: TextInputType.text,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 2, color: AppTheme.accentPartyPurple),
            decoration: InputDecoration(
              labelText: 'Single-Use Seat Passcode / OTP',
              hintText: 'e.g. 581924',
              prefixIcon: const Icon(Icons.vpn_key_rounded, color: AppTheme.accentPartyPurple),
              filled: true,
              fillColor: AppTheme.darkSurface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.accentPartyPurple, width: 2),
              ),
            ),
          ),
        ],
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
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          game.name,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                      if (game.isPrivate) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.accentPartyPurple,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.lock_rounded, size: 10, color: Colors.white),
                              SizedBox(width: 4),
                              Text(
                                'PRIVATE',
                                style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
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
                  'Funded Capacity: ${game.fundedCapacity} Seats ${game.isPrivate ? "(Private OTP)" : ""}',
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
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
                      const Text('Playing as Game Nickname:', style: TextStyle(fontSize: 11, color: Color(0xFFA0AEC0))),
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
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Text(
            'This nickname is shown to other players and on our public Recent Games page if you win.',
            style: TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
          ),
        ),
      ],
    );
  }
}
