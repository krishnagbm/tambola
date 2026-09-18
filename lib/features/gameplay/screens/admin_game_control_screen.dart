import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/config/app_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/live_display_helper.dart';
import '../../../core/utils/tambola_audio_caller.dart';
import '../../../models/mpt_claim.dart';
import '../../../models/mpt_game.dart';
import '../../../models/mpt_registration.dart';
import '../../../providers/app_providers.dart';

class AdminGameControlScreen extends ConsumerStatefulWidget {
  final String gameId;

  const AdminGameControlScreen({super.key, required this.gameId});

  @override
  ConsumerState<AdminGameControlScreen> createState() => _AdminGameControlScreenState();
}

class _AdminGameControlScreenState extends ConsumerState<AdminGameControlScreen> {
  bool _isCalling = false;
  bool _isMuted = false;

  @override
  void initState() {
    super.initState();
    _isMuted = TambolaAudioCaller().isMuted;
  }

  void _handleCopyCode(String inviteCode) {
    Clipboard.setData(ClipboardData(text: inviteCode));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Invite Code copied to clipboard!')),
    );
  }

  void _handleCopyLink(String inviteCode) {
    final link = '${AppConfig.appBaseUrl}/#/join/$inviteCode';
    Clipboard.setData(ClipboardData(text: link));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Direct join link copied to clipboard!')),
    );
  }

  Future<void> _handleShareInvite(MptGame game) async {
    final link = '${AppConfig.appBaseUrl}/#/join/${game.inviteCode}';
    final text = '🎉 You are invited to play DabHousie with me in "${game.name}"!\n\n'
        '🔑 Invite Code: ${game.inviteCode}\n\n'
        '👉 Tap the link below to join directly on web or in app:\n$link';
    await Share.share(text, subject: 'Join DabHousie: ${game.name}');
  }

  Future<void> _handleCallNext() async {
    setState(() => _isCalling = true);
    try {
      final num = await ref.read(gameplayRepositoryProvider).callNextNumber(widget.gameId);
      ref.invalidate(calledNumbersStreamProvider(widget.gameId));

      if (num != null) {
        TambolaAudioCaller().announceNumber(num);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All 90 numbers have been called! Game completed.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error calling number: $e'), backgroundColor: AppTheme.accentDanger),
      );
    } finally {
      if (mounted) setState(() => _isCalling = false);
    }
  }

  Future<void> _handleEndGame() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.flag_rounded, color: AppTheme.secondaryColor),
            SizedBox(width: 8),
            Text('End Game?'),
          ],
        ),
        content: const Text(
          'Are you sure you want to conclude this DabHousie game?\n\nThis will mark the game as COMPLETED and display final results to all players.',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentDanger,
              foregroundColor: Colors.white,
            ),
            child: const Text('End & Finalize Game'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await ref.read(gameplayRepositoryProvider).endGame(widget.gameId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Game concluded successfully! Final results published.')),
      );
      context.go('/');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to end game: $e'), backgroundColor: AppTheme.accentDanger),
      );
    }
  }

  void _showEditGameNameDialog(String currentGameName) {
    final controller = TextEditingController(text: currentGameName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Edit Event Name', style: TextStyle(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Event Name',
            hintText: 'e.g. Saturday Family DabHousie',
            prefixIcon: Icon(Icons.edit),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isNotEmpty && newName != currentGameName) {
                Navigator.pop(ctx);
                try {
                  await ref.read(gameRepositoryProvider).updateGameName(widget.gameId, newName);
                  ref.invalidate(gameStreamProvider(widget.gameId));
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Event name updated successfully!')),
                  );
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to update event name: $e'), backgroundColor: AppTheme.accentDanger),
                  );
                }
              } else {
                Navigator.pop(ctx);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showPlayersModal(BuildContext context, List<MptRegistration> registrations, MptGame? game) {
    final confirmed = registrations.where((r) => r.isConfirmed).toList();
    final waiting = registrations.where((r) => r.isWaiting).toList();
    final capacity = game?.fundedCapacity ?? 5;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.darkCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.65,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          expand: false,
          builder: (_, scrollController) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.groups_rounded, color: AppTheme.secondaryColor, size: 24),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Joined Players (${confirmed.length} / $capacity)',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (game != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppTheme.darkSurface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF2E334D)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('INVITE CODE', style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8), fontWeight: FontWeight.w700)),
                                Text(
                                  game.inviteCode,
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 1.2, color: AppTheme.secondaryColor),
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton.icon(
                            onPressed: () => _handleShareInvite(game),
                            icon: const Icon(Icons.share_rounded, size: 16),
                            label: const Text('Share Invite'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.secondaryColor,
                              foregroundColor: AppTheme.primaryDark,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  Expanded(
                    child: registrations.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.person_outline, size: 48, color: Color(0xFF64748B)),
                                const SizedBox(height: 12),
                                const Text(
                                  'No players have joined yet',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Share the invite code or direct link with your players so they can get their tickets.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                                ),
                                const SizedBox(height: 16),
                                if (game != null)
                                  ElevatedButton.icon(
                                    onPressed: () {
                                      Navigator.pop(ctx);
                                      _handleShareInvite(game);
                                    },
                                    icon: const Icon(Icons.share_rounded, size: 18),
                                    label: const Text('Share Invite Link'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.secondaryColor,
                                      foregroundColor: AppTheme.primaryDark,
                                    ),
                                  ),
                              ],
                            ),
                          )
                        : ListView(
                            controller: scrollController,
                            children: [
                              if (confirmed.isNotEmpty) ...[
                                Text(
                                  'CONFIRMED PLAYERS (${confirmed.length})',
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.accentSuccess, letterSpacing: 0.8),
                                ),
                                const SizedBox(height: 8),
                                ...confirmed.map((r) => _buildPlayerTile(r, isConfirmed: true)),
                                const SizedBox(height: 16),
                              ],
                              if (waiting.isNotEmpty) ...[
                                Text(
                                  'WAITING ROOM PLAYERS (${waiting.length})',
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.accentWarning, letterSpacing: 0.8),
                                ),
                                const SizedBox(height: 8),
                                ...waiting.map((r) => _buildPlayerTile(r, isConfirmed: false)),
                              ],
                            ],
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPlayerTile(MptRegistration r, {required bool isConfirmed}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isConfirmed ? const Color(0xFF2E334D) : AppTheme.accentWarning.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: isConfirmed ? AppTheme.primaryColor.withValues(alpha: 0.3) : AppTheme.accentWarning.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              Formatters.getAvatarEmoji(r.avatar),
              style: const TextStyle(fontSize: 16),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.displayName,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Ticket #${r.registrationSeq}',
                  style: const TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8)),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isConfirmed ? AppTheme.accentSuccess.withValues(alpha: 0.2) : AppTheme.accentWarning.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              isConfirmed ? 'CONFIRMED' : 'WAITING',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: isConfirmed ? AppTheme.accentSuccess : AppTheme.accentWarning,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final calledStream = ref.watch(calledNumbersStreamProvider(widget.gameId));
    final claimsStream = ref.watch(claimsStreamProvider(widget.gameId));
    final gameStream = ref.watch(gameStreamProvider(widget.gameId));
    final regStream = ref.watch(registrationsStreamProvider(widget.gameId));

    final game = gameStream.value;
    final registrations = regStream.value ?? [];
    final confirmedPlayers = registrations.where((r) => r.isConfirmed).toList();
    final isGameCompleted = game?.status == 'COMPLETED';
    final activePrizes = game?.prizesConfig ?? ['EARLY_FIVE', 'TOP_LINE', 'MIDDLE_LINE', 'BOTTOM_LINE', 'FOUR_CORNERS', 'FULL_HOUSE'];
    final claims = claimsStream.value ?? [];
    final approvedClaimPrizes = claims.where((c) => c.status == 'APPROVED').map((c) => c.prizeType).toSet();
    final allPrizesWon = activePrizes.isNotEmpty && activePrizes.every((p) => approvedClaimPrizes.contains(p));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back to Home',
          onPressed: () => context.go('/'),
        ),
        title: const Text('Organizer Game Control'),
        actions: [
          IconButton(
            icon: Icon(_isMuted ? Icons.volume_off : Icons.volume_up, color: _isMuted ? Colors.grey : AppTheme.secondaryColor),
            tooltip: _isMuted ? 'Unmute Audio Caller' : 'Mute Audio Caller',
            onPressed: () {
              setState(() {
                _isMuted = !_isMuted;
                TambolaAudioCaller().isMuted = _isMuted;
              });
            },
          ),
          if (game != null)
            IconButton(
              icon: const Icon(Icons.share_rounded, color: AppTheme.secondaryColor),
              tooltip: 'Share Invite Code & Link',
              onPressed: () => _handleShareInvite(game),
            ),
          IconButton(
            icon: Badge(
              isLabelVisible: registrations.isNotEmpty,
              label: Text('${registrations.length}'),
              backgroundColor: AppTheme.secondaryColor,
              textColor: AppTheme.primaryDark,
              child: const Icon(Icons.groups_rounded, color: Colors.white),
            ),
            tooltip: 'View Players (${registrations.length})',
            onPressed: () => _showPlayersModal(context, registrations, game),
          ),
          IconButton(
            icon: const Icon(Icons.tv, color: AppTheme.secondaryColor),
            tooltip: 'Live Display (Open in New Tab / Window)',
            onPressed: () => LiveDisplayHelper.openInNewWindow(context, widget.gameId),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () {
              ref.invalidate(calledNumbersStreamProvider(widget.gameId));
              ref.invalidate(claimsStreamProvider(widget.gameId));
              ref.invalidate(gameStreamProvider(widget.gameId));
              ref.invalidate(registrationsStreamProvider(widget.gameId));
            },
          ),
        ],
      ),
      body: calledStream.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (calledNumbers) {
          final latest = calledNumbers.isNotEmpty ? calledNumbers.last.number : null;
          final calledSet = calledNumbers.map((e) => e.number).toSet();
          final isMaxNumbers = calledNumbers.length >= 90;
          final disableCalling = _isCalling || isMaxNumbers || allPrizesWon || isGameCompleted;

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1800),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: LayoutBuilder(
                  builder: (ctx, constraints) {
                    final is3Column = constraints.maxWidth >= 1080;
                    final is2Column = constraints.maxWidth >= 750 && constraints.maxWidth < 1080;

                    // ========================================================
                    // 1. WIDE SCREEN: 3-COLUMN LAYOUT
                    // Left: Pre-Game Banner, Header, Waiting, Claims, End Game | Middle: Caller & Master Board (Full Visibility) | Right: Players List
                    // ========================================================
                    if (is3Column) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Left Column (Pre-Game Banner, Cards, Prize Claims & Winners, End Game)
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (calledNumbers.isEmpty && !isGameCompleted) ...[
                                  _buildPreGameBanner(game, confirmedPlayers.length),
                                  const SizedBox(height: 10),
                                ],
                                if (allPrizesWon && !isGameCompleted) ...[
                                  _buildAllPrizesWonBanner(),
                                  const SizedBox(height: 10),
                                ],
                                _buildGameHeaderAndInviteCard(game, registrations, isGameCompleted),
                                const SizedBox(height: 10),
                                _buildWaitingRoomCard(game, registrations),
                                const SizedBox(height: 12),
                                _buildClaimsQueue(claimsStream),
                                const SizedBox(height: 14),
                                OutlinedButton.icon(
                                  onPressed: isGameCompleted ? null : _handleEndGame,
                                  icon: const Icon(Icons.flag_outlined, color: AppTheme.accentDanger),
                                  label: Text(
                                    isGameCompleted ? 'Game Concluded' : 'End Game & Conclude Event',
                                    style: TextStyle(color: isGameCompleted ? Colors.grey : AppTheme.accentDanger),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(color: isGameCompleted ? Colors.grey : AppTheme.accentDanger),
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),

                          // Middle Column (Max Width: Latest Number, Call Button, Compact Master Board)
                          Expanded(
                            flex: 5,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildCallerHeader(latest, calledNumbers.length),
                                const SizedBox(height: 8),
                                ElevatedButton.icon(
                                  onPressed: disableCalling ? null : _handleCallNext,
                                  icon: Icon(
                                    allPrizesWon ? Icons.emoji_events : Icons.campaign_rounded,
                                    size: 24,
                                  ),
                                  label: _isCalling
                                      ? const Text('Selecting Number...')
                                      : Text(
                                          isGameCompleted
                                              ? 'Game Completed'
                                              : allPrizesWon
                                                  ? 'All Prizes Won (Conclude Below)'
                                                  : isMaxNumbers
                                                      ? 'All 90 Numbers Called'
                                                      : calledNumbers.isEmpty
                                                          ? 'CALL FIRST NUMBER'
                                                          : 'CALL NEXT NUMBER',
                                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                                        ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: allPrizesWon ? AppTheme.secondaryColor : AppTheme.accentSuccess,
                                    foregroundColor: allPrizesWon ? AppTheme.primaryDark : Colors.white,
                                    disabledBackgroundColor: const Color(0xFF222639),
                                    disabledForegroundColor: const Color(0xFF718096),
                                    padding: const EdgeInsets.symmetric(vertical: 13),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                _buildMasterBoard(calledSet),
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),

                          // Right Column (Compact Dedicated Players List with independent vertical scrollbar)
                          Expanded(
                            flex: 2,
                            child: _buildPlayersSidebar(game, registrations, height: 680),
                          ),
                        ],
                      );
                    }

                    // ========================================================
                    // 2. MEDIUM SCREEN (e.g. 800px monitor / Tablet): 2 COLUMNS
                    // ========================================================
                    if (is2Column) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildGameHeaderAndInviteCard(game, registrations, isGameCompleted),
                          const SizedBox(height: 12),
                          _buildWaitingRoomCard(game, registrations),
                          const SizedBox(height: 14),
                          if (allPrizesWon && !isGameCompleted) ...[
                            _buildAllPrizesWonBanner(),
                            const SizedBox(height: 14),
                          ],
                          if (calledNumbers.isEmpty && !isGameCompleted) ...[
                            _buildPreGameBanner(game, confirmedPlayers.length),
                            const SizedBox(height: 14),
                          ],
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 3,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    _buildCallerHeader(latest, calledNumbers.length),
                                    const SizedBox(height: 14),
                                    ElevatedButton.icon(
                                      onPressed: disableCalling ? null : _handleCallNext,
                                      icon: Icon(
                                        allPrizesWon ? Icons.emoji_events : Icons.campaign_rounded,
                                        size: 28,
                                      ),
                                      label: _isCalling
                                          ? const Text('Selecting Number...')
                                          : Text(
                                              isGameCompleted
                                                  ? 'Game Completed'
                                                  : allPrizesWon
                                                      ? 'All Prizes Won (Conclude Below)'
                                                      : isMaxNumbers
                                                          ? 'All 90 Numbers Called'
                                                          : calledNumbers.isEmpty
                                                              ? 'CALL FIRST NUMBER'
                                                              : 'CALL NEXT NUMBER',
                                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                                            ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: allPrizesWon ? AppTheme.secondaryColor : AppTheme.accentSuccess,
                                        foregroundColor: allPrizesWon ? AppTheme.primaryDark : Colors.white,
                                        disabledBackgroundColor: const Color(0xFF222639),
                                        disabledForegroundColor: const Color(0xFF718096),
                                        padding: const EdgeInsets.symmetric(vertical: 18),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    _buildMasterBoard(calledSet),
                                    const SizedBox(height: 16),
                                    OutlinedButton.icon(
                                      onPressed: isGameCompleted ? null : _handleEndGame,
                                      icon: const Icon(Icons.flag_outlined, color: AppTheme.accentDanger),
                                      label: Text(
                                        isGameCompleted ? 'Game Concluded' : 'End Game & Conclude Event',
                                        style: TextStyle(color: isGameCompleted ? Colors.grey : AppTheme.accentDanger),
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        side: BorderSide(color: isGameCompleted ? Colors.grey : AppTheme.accentDanger),
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                flex: 3,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    _buildClaimsQueue(claimsStream),
                                    const SizedBox(height: 16),
                                    _buildPlayersSidebar(game, registrations, height: 480),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    }

                    // ========================================================
                    // 3. MOBILE SCREEN (< 750px): STACKED 1 COLUMN
                    // ========================================================
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildGameHeaderAndInviteCard(game, registrations, isGameCompleted),
                        const SizedBox(height: 12),
                        _buildWaitingRoomCard(game, registrations),
                        const SizedBox(height: 14),
                        if (allPrizesWon && !isGameCompleted) ...[
                          _buildAllPrizesWonBanner(),
                          const SizedBox(height: 14),
                        ],
                        if (calledNumbers.isEmpty && !isGameCompleted) ...[
                          _buildPreGameBanner(game, confirmedPlayers.length),
                          const SizedBox(height: 14),
                        ],
                        _buildCallerHeader(latest, calledNumbers.length),
                        const SizedBox(height: 14),
                        ElevatedButton.icon(
                          onPressed: disableCalling ? null : _handleCallNext,
                          icon: Icon(
                            allPrizesWon ? Icons.emoji_events : Icons.campaign_rounded,
                            size: 28,
                          ),
                          label: _isCalling
                              ? const Text('Selecting Number...')
                              : Text(
                                  isGameCompleted
                                      ? 'Game Completed'
                                      : allPrizesWon
                                          ? 'All Prizes Won (Conclude Below)'
                                          : isMaxNumbers
                                              ? 'All 90 Numbers Called'
                                              : calledNumbers.isEmpty
                                                  ? 'CALL FIRST NUMBER'
                                                  : 'CALL NEXT NUMBER',
                                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                                ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: allPrizesWon ? AppTheme.secondaryColor : AppTheme.accentSuccess,
                            foregroundColor: allPrizesWon ? AppTheme.primaryDark : Colors.white,
                            disabledBackgroundColor: const Color(0xFF222639),
                            disabledForegroundColor: const Color(0xFF718096),
                            padding: const EdgeInsets.symmetric(vertical: 18),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildMasterBoard(calledSet),
                        const SizedBox(height: 16),
                        _buildClaimsQueue(claimsStream),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: isGameCompleted ? null : _handleEndGame,
                          icon: const Icon(Icons.flag_outlined, color: AppTheme.accentDanger),
                          label: Text(
                            isGameCompleted ? 'Game Concluded' : 'End Game & Conclude Event',
                            style: TextStyle(color: isGameCompleted ? Colors.grey : AppTheme.accentDanger),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: isGameCompleted ? Colors.grey : AppTheme.accentDanger),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAllPrizesWonBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.secondaryColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.secondaryColor, width: 1.5),
      ),
      child: const Row(
        children: [
          Icon(Icons.emoji_events, color: AppTheme.secondaryColor, size: 28),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'All Prizes Won! 🏆',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.secondaryColor),
                ),
                SizedBox(height: 2),
                Text(
                  'All configured prizes have approved winners. Number calling is paused. Conclude the game to finalize results.',
                  style: TextStyle(fontSize: 12, color: Color(0xFFCBD5E1)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayersSidebar(MptGame? game, List<MptRegistration> registrations, {double? height}) {
    final confirmed = registrations.where((r) => r.isConfirmed).toList();
    final waiting = registrations.where((r) => r.isWaiting).toList();
    final capacity = game?.fundedCapacity ?? 5;

    return Container(
      height: height,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2E334D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.groups_rounded, color: AppTheme.secondaryColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Players List (${confirmed.length}/$capacity)',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
              if (game != null)
                IconButton(
                  icon: const Icon(Icons.share_rounded, size: 16, color: AppTheme.secondaryColor),
                  tooltip: 'Share Invite',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => _handleShareInvite(game),
                ),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(color: Color(0xFF2E334D), height: 1),
          const SizedBox(height: 10),
          Expanded(
            child: registrations.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.person_add_alt_1_rounded, size: 36, color: Color(0xFF64748B)),
                          const SizedBox(height: 10),
                          const Text(
                            'No players joined yet',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Share your invite code or link with players to get tickets.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
                          ),
                          const SizedBox(height: 12),
                          if (game != null)
                            ElevatedButton.icon(
                              onPressed: () => _handleShareInvite(game),
                              icon: const Icon(Icons.share_rounded, size: 14),
                              label: const Text('Share Invite'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.secondaryColor,
                                foregroundColor: AppTheme.primaryDark,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                            ),
                        ],
                      ),
                    ),
                  )
                : Scrollbar(
                    thumbVisibility: true,
                    child: ListView(
                      padding: const EdgeInsets.only(right: 8),
                      children: [
                        if (confirmed.isNotEmpty) ...[
                          Text(
                            'CONFIRMED PLAYERS (${confirmed.length})',
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppTheme.accentSuccess, letterSpacing: 0.8),
                          ),
                          const SizedBox(height: 6),
                          ...confirmed.map((r) => _buildPlayerTile(r, isConfirmed: true)),
                          const SizedBox(height: 12),
                        ],
                        if (waiting.isNotEmpty) ...[
                          Text(
                            'WAITING ROOM (${waiting.length})',
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppTheme.accentWarning, letterSpacing: 0.8),
                          ),
                          const SizedBox(height: 6),
                          ...waiting.map((r) => _buildPlayerTile(r, isConfirmed: false)),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildGameHeaderAndInviteCard(MptGame? game, List<MptRegistration> registrations, bool isGameCompleted) {
    final capacity = game?.fundedCapacity ?? 5;
    final isFreeTier = capacity <= 5;
    final inviteCode = game?.inviteCode ?? '---';
    final confirmedCount = registrations.where((r) => r.isConfirmed).length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2E334D)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primaryColor.withValues(alpha: 0.15),
            AppTheme.darkCard,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Row: Title, Edit, Status & Tier badges + Players joined (x/y)
          Row(
            children: [
              const Icon(Icons.celebration, size: 22, color: AppTheme.secondaryColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  game?.name ?? 'DabHousie Event',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit, size: 18, color: AppTheme.primaryLight),
                tooltip: 'Edit Event Name',
                padding: const EdgeInsets.symmetric(horizontal: 6),
                constraints: const BoxConstraints(),
                onPressed: () => _showEditGameNameDialog(game?.name ?? ''),
              ),
              const SizedBox(width: 6),
              // Status Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isGameCompleted ? const Color(0xFF718096).withValues(alpha: 0.2) : AppTheme.accentSuccess.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isGameCompleted ? 'COMPLETED' : '🟢 LIVE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isGameCompleted ? const Color(0xFFA0AEC0) : AppTheme.accentSuccess,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Capacity Tier Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.secondaryColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.secondaryColor.withValues(alpha: 0.5), width: 0.8),
                ),
                child: Text(
                  isFreeTier ? '5-Player (Free)' : '$capacity-Member Game',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.secondaryColor,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Number of Players Joined Badge (x/y)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.primaryLight.withValues(alpha: 0.5), width: 0.8),
                ),
                child: Text(
                  '👥 $confirmedCount/$capacity Joined',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Bottom Bar: Invite Code Box + Action Buttons
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.darkSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF2E334D)),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                // Invite Code Box with Copy
                InkWell(
                  onTap: () => _handleCopyCode(inviteCode),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.secondaryColor.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'ROOM INVITE CODE',
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Color(0xFF94A3B8), letterSpacing: 0.5),
                            ),
                            Text(
                              inviteCode,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: AppTheme.secondaryColor,
                                letterSpacing: 1.5,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.copy_rounded, size: 16, color: AppTheme.secondaryColor),
                      ],
                    ),
                  ),
                ),

                // Action Buttons
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      onPressed: game != null ? () => _handleShareInvite(game) : null,
                      icon: const Icon(Icons.share_rounded, size: 16),
                      label: const Text('Share Invite'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.secondaryColor,
                        foregroundColor: AppTheme.primaryDark,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _handleCopyLink(inviteCode),
                      icon: const Icon(Icons.link_rounded, size: 16),
                      label: const Text('Copy Link'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFF475569)),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => context.push('/admin-lobby/${widget.gameId}'),
                      icon: const Icon(Icons.meeting_room_outlined, size: 16),
                      label: const Text('Lobby View'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF94A3B8),
                        side: const BorderSide(color: Color(0xFF334155)),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWaitingRoomCard(MptGame? game, List<MptRegistration> registrations) {
    final confirmed = registrations.where((r) => r.isConfirmed).toList();
    final waiting = registrations.where((r) => r.isWaiting).toList();
    final capacity = game?.fundedCapacity ?? 5;

    if (registrations.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.4), width: 1.2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B82F6).withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.person_add_alt_1_rounded, color: Color(0xFF60A5FA), size: 20),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Waiting for Players to Join (0 Joined)',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      Text(
                        'No family members or players have joined the game yet.',
                        style: TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Send a fresh invite link or share the 6-digit room code with your players so they can enter and receive their tickets before you call numbers.',
              style: TextStyle(fontSize: 12, color: Color(0xFFCBD5E1)),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (game != null) ...[
                  ElevatedButton.icon(
                    onPressed: () => _handleShareInvite(game),
                    icon: const Icon(Icons.share_rounded, size: 16),
                    label: const Text('Send Invite Now'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3B82F6),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                OutlinedButton.icon(
                  onPressed: () => _handleCopyLink(game?.inviteCode ?? ''),
                  icon: const Icon(Icons.copy_rounded, size: 14),
                  label: const Text('Copy Join Link'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF93C5FD),
                    side: const BorderSide(color: Color(0xFF3B82F6)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2E334D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.groups_rounded, color: AppTheme.secondaryColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Players in Game (${confirmed.length} / $capacity Joined)',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
              if (waiting.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.accentWarning.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${waiting.length} Waiting',
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.accentWarning),
                  ),
                ),
              TextButton(
                onPressed: () => _showPlayersModal(context, registrations, game),
                style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                child: const Text('View All', style: TextStyle(fontSize: 12, color: AppTheme.secondaryColor)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: registrations.take(8).map((r) {
                return Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.darkSurface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: r.isConfirmed ? const Color(0xFF334155) : AppTheme.accentWarning.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(Formatters.getAvatarEmoji(r.avatar), style: const TextStyle(fontSize: 14)),
                      const SizedBox(width: 6),
                      Text(
                        r.displayName,
                        style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                );
              }).toList()
                ..addAll(registrations.length > 8
                    ? [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.darkSurface,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '+${registrations.length - 8} more',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                          ),
                        )
                      ]
                    : []),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreGameBanner(MptGame? game, int confirmedCount) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.accentSuccess.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.accentSuccess.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          const Icon(Icons.campaign_outlined, color: AppTheme.accentSuccess, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Game is Ready to Start! 🎲',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: AppTheme.accentSuccess),
                ),
                const SizedBox(height: 2),
                Text(
                  confirmedCount > 0
                      ? '$confirmedCount players are in the game. When everyone is ready with their tickets, tap "CALL FIRST NUMBER" below to begin!'
                      : 'Invite your players first. When they have joined, tap "CALL FIRST NUMBER" below to begin drawing balls.',
                  style: const TextStyle(fontSize: 11.5, color: Color(0xFFCBD5E1)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCallerHeader(int? latest, int totalCalled) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.primaryDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2E334D)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('LATEST NUMBER', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white70)),
              Text(
                latest != null ? '$latest' : '---',
                style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: AppTheme.secondaryColor, height: 1.1),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$totalCalled / 90', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
              const Text('Total Called', style: TextStyle(fontSize: 11, color: Colors.white70)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMasterBoard(Set<int> calledSet) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Master Board (1–90)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                Text(
                  '${calledSet.length} Called',
                  style: const TextStyle(fontSize: 11, color: AppTheme.secondaryColor, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 6),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 90,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 10,
                childAspectRatio: 1.18,
                crossAxisSpacing: 3,
                mainAxisSpacing: 3,
              ),
              itemBuilder: (ctx, idx) {
                final num = idx + 1;
                final isCalled = calledSet.contains(num);
                return Container(
                  decoration: BoxDecoration(
                    color: isCalled ? AppTheme.accentSuccess : AppTheme.darkSurface,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: isCalled ? AppTheme.accentSuccess : const Color(0xFF2E334D), width: 0.8),
                  ),
                  child: Center(
                    child: Text(
                      '$num',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isCalled ? Colors.white : const Color(0xFFA0AEC0),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClaimsQueue(AsyncValue<List<MptClaim>> claimsStream) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Prize Claims & Winners', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        claimsStream.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('Error: $e'),
          data: (claims) {
            final approvedClaims = claims.where((c) => c.status == 'APPROVED').toList();

            if (approvedClaims.isEmpty) {
              return const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: Text('No approved winners yet. Announce prizes to your players!')),
                ),
              );
            }

            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: approvedClaims.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (ctx, idx) {
                final claim = approvedClaims[idx];
                return Card(
                  color: AppTheme.accentSuccess.withOpacity(0.12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: AppTheme.accentSuccess, width: 1.2),
                  ),
                  child: ListTile(
                    leading: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: AppTheme.secondaryColor.withOpacity(0.2),
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.secondaryColor),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        Formatters.getAvatarEmoji(claim.userAvatar),
                        style: const TextStyle(fontSize: 22),
                      ),
                    ),
                    title: Text(
                      '🏆 ${Formatters.formatPrizeName(claim.prizeType)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 2),
                        Text(
                          'Won by: ${claim.userName ?? "Player"}',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.secondaryColor),
                        ),
                        Text(
                          'Verified • ${Formatters.formatShortDate(claim.submittedAt)}',
                          style: const TextStyle(fontSize: 11, color: Color(0xFFCBD5E1)),
                        ),
                      ],
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.accentSuccess.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('APPROVED', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppTheme.accentSuccess)),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }
}
