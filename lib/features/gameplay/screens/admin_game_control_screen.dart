import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/tambola_audio_caller.dart';
import '../../../models/mpt_claim.dart';
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
          'Are you sure you want to conclude this Tambola game?\n\nThis will mark the game as COMPLETED and display final results to all players.',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentDanger),
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

  @override
  Widget build(BuildContext context) {
    final calledStream = ref.watch(calledNumbersStreamProvider(widget.gameId));
    final claimsStream = ref.watch(claimsStreamProvider(widget.gameId));
    final gameStream = ref.watch(gameStreamProvider(widget.gameId));

    final prizesConfig = gameStream.value?.prizesConfig ?? ['EARLY_FIVE', 'TOP_LINE', 'MIDDLE_LINE', 'BOTTOM_LINE', 'FOUR_CORNERS', 'FULL_HOUSE'];
    final approvedPrizeTypes = claimsStream.value?.where((c) => c.status == 'APPROVED').map((c) => c.prizeType).toSet() ?? {};
    final allPrizesWon = prizesConfig.isNotEmpty && prizesConfig.every((p) => approvedPrizeTypes.contains(p));
    final isGameCompleted = gameStream.value?.status == 'COMPLETED';

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
          IconButton(
            icon: const Icon(Icons.tv, color: AppTheme.secondaryColor),
            tooltip: 'Live Display',
            onPressed: () => context.push('/live-display/${widget.gameId}'),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () {
              ref.invalidate(calledNumbersStreamProvider(widget.gameId));
              ref.invalidate(claimsStreamProvider(widget.gameId));
              ref.invalidate(gameStreamProvider(widget.gameId));
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

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // All Prizes Won Alert Banner
                if (allPrizesWon && !isGameCompleted) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.secondaryColor.withOpacity(0.15),
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
                  ),
                  const SizedBox(height: 14),
                ],

                // Caller Banner
                _buildCallerHeader(latest, calledNumbers.length),
                const SizedBox(height: 16),

                // Call Next Number Button
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
                                      : 'CALL NEXT NUMBER',
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                        ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: allPrizesWon ? AppTheme.secondaryColor : AppTheme.accentSuccess,
                    disabledBackgroundColor: const Color(0xFF222639),
                    disabledForegroundColor: const Color(0xFF718096),
                    padding: const EdgeInsets.symmetric(vertical: 18),
                  ),
                ),
                const SizedBox(height: 20),

                // Master 1–90 Board Matrix
                _buildMasterBoard(calledSet),
                const SizedBox(height: 24),

                // Live Claims & Winners List (Item 13 & 16: filtered approved winners)
                _buildClaimsQueue(claimsStream),
                const SizedBox(height: 24),

                // End Game Button (Item 20)
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
          );
        },
      ),
    );
  }

  Widget _buildCallerHeader(int? latest, int totalCalled) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.primaryDark,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('LATEST NUMBER', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70)),
              const SizedBox(height: 4),
              Text(
                latest != null ? '$latest' : '---',
                style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: AppTheme.secondaryColor),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$totalCalled / 90', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
              const Text('Total Called', style: TextStyle(fontSize: 12, color: Colors.white70)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMasterBoard(Set<int> calledSet) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Master Board (1–90)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 10),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 90,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 10,
                childAspectRatio: 1,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemBuilder: (ctx, idx) {
                final num = idx + 1;
                final isCalled = calledSet.contains(num);
                return Container(
                  decoration: BoxDecoration(
                    color: isCalled ? AppTheme.accentSuccess : AppTheme.darkSurface,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: isCalled ? AppTheme.accentSuccess : const Color(0xFF2E334D)),
                  ),
                  child: Center(
                    child: Text(
                      '$num',
                      style: TextStyle(
                        fontSize: 12,
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
