import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/tambola_audio_caller.dart';
import '../../../core/utils/tambola_ticket.dart';
import '../../../models/mpt_called_number.dart';
import '../../../models/mpt_claim.dart';
import '../../../models/mpt_ticket.dart';
import '../../../models/mpt_user.dart';
import '../../../providers/app_providers.dart';

class PlayerTicketScreen extends ConsumerStatefulWidget {
  final String gameId;

  const PlayerTicketScreen({super.key, required this.gameId});

  @override
  ConsumerState<PlayerTicketScreen> createState() => _PlayerTicketScreenState();
}

class _PlayerTicketScreenState extends ConsumerState<PlayerTicketScreen> {
  final Set<int> _markedNumbers = {};
  bool _isClaiming = false;
  bool _voiceEnabled = false;
  int _lastAnnouncedSeq = 0;

  @override
  void initState() {
    super.initState();
    _loadSavedMarks();
  }

  Future<void> _loadSavedMarks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = ref.read(currentUserProvider).value?.id;
      List<String>? saved;
      if (uid != null) {
        saved = prefs.getStringList('mpt_marked_${widget.gameId}_$uid');
      }
      saved ??= prefs.getStringList('mpt_marked_${widget.gameId}');

      if (saved != null && saved.isNotEmpty && mounted) {
        setState(() {
          _markedNumbers.addAll(saved!.map(int.parse));
        });
      }
    } catch (_) {}
  }

  void _toggleMark(int number) {
    if (number == 0) return;
    setState(() {
      if (_markedNumbers.contains(number)) {
        _markedNumbers.remove(number);
      } else {
        _markedNumbers.add(number);
      }
    });
    _saveMarks();
  }

  Future<void> _saveMarks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = ref.read(currentUserProvider).value?.id;
      final list = _markedNumbers.map((n) => n.toString()).toList();
      if (uid != null) {
        await prefs.setStringList('mpt_marked_${widget.gameId}_$uid', list);
      }
      await prefs.setStringList('mpt_marked_${widget.gameId}', list);
    } catch (_) {}
  }

  Future<void> _handleClaimPrize({
    required String prizeType,
    required MptTicket ticket,
    required Set<int> calledSet,
  }) async {
    // 1. Strict validation: check for uncalled marked numbers (Bogey)
    final uncalled = _markedNumbers.where((n) => !calledSet.contains(n)).toList();
    if (uncalled.isNotEmpty) {
      _showBogeyDialog('Invalid Claim: You have marked numbers that have not been called yet: ${uncalled.join(', ')}');
      return;
    }

    // 2. Strict validation: check pattern is complete (Item 15)
    final isPatternValid = TambolaTicketHelper.validatePrizePattern(ticket.matrix, _markedNumbers, prizeType);
    if (!isPatternValid) {
      _showIncompletePatternDialog(prizeType);
      return;
    }

    setState(() => _isClaiming = true);
    try {
      final res = await ref.read(gameplayRepositoryProvider).submitClaim(
            gameId: widget.gameId,
            prizeType: prizeType,
            markedNumbers: _markedNumbers.toList(),
          );

      if (!mounted) return;
      final status = res['status'] as String? ?? 'UNKNOWN';

      if (status == 'APPROVED') {
        final refCode = res['claim_reference'] as String? ?? 'N/A';
        _showWinnerDialog(prizeType, refCode);
      } else if (status == 'BOGEY') {
        _showBogeyDialog(res['reason'] as String? ?? 'Invalid claim numbers');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Claim $status: ${res['reason'] ?? ''}'),
            backgroundColor: AppTheme.accentWarning,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Claim error: $e'), backgroundColor: AppTheme.accentDanger),
      );
    } finally {
      if (mounted) setState(() => _isClaiming = false);
    }
  }

  void _showWinnerDialog(String prizeType, String claimRef) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.emoji_events, color: AppTheme.secondaryColor, size: 28),
            SizedBox(width: 8),
            Text('WINNER! 🏆', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Congratulations! Your claim for "${Formatters.formatPrizeName(prizeType)}" is APPROVED.',
                style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 16),
            const Text('Voucher Claim Reference Code:', style: TextStyle(fontSize: 12, color: Color(0xFFA0AEC0))),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.darkSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.secondaryColor),
              ),
              child: SelectableText(
                claimRef,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.5, color: AppTheme.secondaryColor),
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentSuccess),
            child: const Text('Continue Playing (Stay on Game)'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.push('/rewards');
            },
            child: const Text('View in Rewards'),
          ),
        ],
      ),
    );
  }

  void _showIncompletePatternDialog(String prizeType) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: AppTheme.accentWarning, size: 26),
            SizedBox(width: 8),
            Text('Pattern Incomplete', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Your marked numbers do not yet complete "${Formatters.formatPrizeName(prizeType)}".\nPlease ensure all required numbers for this pattern have been called and marked on your ticket.',
          style: const TextStyle(fontSize: 14, color: Color(0xFFCBD5E1)),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK, Got It'),
          ),
        ],
      ),
    );
  }

  void _showBogeyDialog(String reason) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.cancel_outlined, color: AppTheme.accentDanger, size: 28),
            SizedBox(width: 8),
            Text('Bogey Claim ⚠️', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          reason,
          style: const TextStyle(fontSize: 14, color: Color(0xFFCBD5E1)),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Understood'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(currentUserProvider, (prev, next) {
      if (_markedNumbers.isEmpty && next.value != null) {
        _loadSavedMarks();
      }
    });

    final ticketAsync = ref.watch(playerTicketProvider(widget.gameId));
    final calledStream = ref.watch(calledNumbersStreamProvider(widget.gameId));
    final gameStream = ref.watch(gameStreamProvider(widget.gameId));
    final claimsStream = ref.watch(claimsStreamProvider(widget.gameId));
    final currentUserId = ref.watch(currentUserProvider).value?.id;

    // Announce number if voice enabled
    if (_voiceEnabled) {
      calledStream.whenData((calledNumbers) {
        if (calledNumbers.isNotEmpty && calledNumbers.length > _lastAnnouncedSeq) {
          _lastAnnouncedSeq = calledNumbers.length;
          final latestNum = calledNumbers.last.number;
          TambolaAudioCaller().announceNumber(latestNum);
        }
      });
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back to Home',
          onPressed: () => context.go('/'),
        ),
        title: const Text('DebHousie Ticket'),
        actions: [
          IconButton(
            icon: Icon(_voiceEnabled ? Icons.volume_up : Icons.volume_off, color: _voiceEnabled ? AppTheme.secondaryColor : Colors.grey),
            tooltip: _voiceEnabled ? 'Voice Calling ON' : 'Voice Calling OFF',
            onPressed: () {
              setState(() => _voiceEnabled = !_voiceEnabled);
            },
          ),
          IconButton(
            icon: const Icon(Icons.tv, color: AppTheme.secondaryColor),
            tooltip: 'Live Board',
            onPressed: () => context.push('/live-display/${widget.gameId}'),
          ),
          IconButton(
            icon: const Icon(Icons.emoji_events_outlined),
            tooltip: 'My Rewards',
            onPressed: () => context.push('/rewards'),
          ),
        ],
      ),
      body: ticketAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, color: AppTheme.accentDanger, size: 48),
                const SizedBox(height: 12),
                const Text(
                  'Unable to load your ticket',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 6),
                Text(
                  'Please tap retry to fetch your assigned ticket for this room.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.7)),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => ref.refresh(playerTicketProvider(widget.gameId)),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Retry Ticket'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryLight,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  ),
                ),
              ],
            ),
          ),
        ),
        data: (ticket) {
          return calledStream.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Center(child: Text('Error: $err')),
            data: (calledNumbers) {
              final latestCalled = calledNumbers.isNotEmpty ? calledNumbers.last.number : null;
              final calledSet = calledNumbers.map((e) => e.number).toSet();
              final isGameEnded = gameStream.value?.status == 'COMPLETED' || calledNumbers.length >= 90;

              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Player Identity & Ticket Number Card (Item 3 & 4)
                    _buildPlayerIdentityBanner(ref.watch(currentUserProvider).value, ticket),
                    const SizedBox(height: 10),

                    // Game Over Banner if ended (Item 20)
                    if (isGameEnded) ...[
                      _buildGameOverBanner(context),
                      const SizedBox(height: 14),
                    ],

                    // Latest Called Ball Banner
                    _buildLatestNumberBanner(latestCalled, calledNumbers.length),
                    const SizedBox(height: 12),

                    // Recent Calls List
                    if (calledNumbers.isNotEmpty) ...[
                      _buildRecentCallsBar(calledNumbers),
                      const SizedBox(height: 14),
                    ],

                    // Interactive 3x9 Ticket (Manual marking, no auto-yellow)
                    _buildTicketMatrix(ticket, calledSet, isGameEnded: isGameEnded),
                    const SizedBox(height: 20),

                    // Prize Claims Section (Item 17: Disabled won buttons & disabled when game ended)
                    claimsStream.when(
                      loading: () => _buildPrizeClaimsSection(
                        gameStream.value?.prizesConfig ?? ['EARLY_FIVE', 'TOP_LINE', 'MIDDLE_LINE', 'BOTTOM_LINE', 'FOUR_CORNERS', 'FULL_HOUSE'],
                        {},
                        currentUserId,
                        ticket,
                        calledSet,
                        isGameEnded: isGameEnded,
                      ),
                      error: (_, __) => _buildPrizeClaimsSection(
                        gameStream.value?.prizesConfig ?? ['EARLY_FIVE', 'TOP_LINE', 'MIDDLE_LINE', 'BOTTOM_LINE', 'FOUR_CORNERS', 'FULL_HOUSE'],
                        {},
                        currentUserId,
                        ticket,
                        calledSet,
                        isGameEnded: isGameEnded,
                      ),
                      data: (claims) {
                        final approvedClaims = <String, MptClaim>{};
                        for (final c in claims) {
                          if (c.status == 'APPROVED') {
                            approvedClaims[c.prizeType] = c;
                          }
                        }
                        return _buildPrizeClaimsSection(
                          gameStream.value?.prizesConfig ?? ['EARLY_FIVE', 'TOP_LINE', 'MIDDLE_LINE', 'BOTTOM_LINE', 'FOUR_CORNERS', 'FULL_HOUSE'],
                          approvedClaims,
                          currentUserId,
                          ticket,
                          calledSet,
                          isGameEnded: isGameEnded,
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildPlayerIdentityBanner(MptUser? user, MptTicket ticket) {
    final emoji = Formatters.getAvatarEmoji(user?.avatar);
    final name = (user?.displayName != null && user!.displayName.trim().isNotEmpty)
        ? user.displayName
        : 'Player';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2E334D)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withOpacity(0.2),
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.primaryLight.withOpacity(0.5)),
            ),
            alignment: Alignment.center,
            child: Text(emoji, style: const TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const Text(
                  'Playing Live Game',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFFA0AEC0),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppTheme.secondaryColor.withOpacity(0.18),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.secondaryColor.withOpacity(0.6)),
            ),
            child: Text(
              'Ticket #${ticket.ticketNumber}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppTheme.secondaryColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGameOverBanner(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.secondaryColor.withOpacity(0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.secondaryColor, width: 2),
      ),
      child: Column(
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.celebration, color: AppTheme.secondaryColor, size: 24),
              SizedBox(width: 8),
              Text(
                'GAME COMPLETED 🎉',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.secondaryColor),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'The game has concluded! Thank you for playing.',
            style: TextStyle(fontSize: 13, color: Color(0xFFCBD5E1)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: () => context.push('/rewards'),
                icon: const Icon(Icons.emoji_events, size: 18),
                label: const Text('View My Rewards'),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.secondaryColor, foregroundColor: Colors.black),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: () => context.go('/'),
                child: const Text('Return Home'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLatestNumberBanner(int? latestNumber, int totalCalled) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: AppTheme.primaryColor.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('CURRENT CALL', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1, color: Colors.white70)),
              const SizedBox(height: 4),
              Text(
                latestNumber != null ? '$latestNumber' : 'READY',
                style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w900, color: Colors.white),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Text('$totalCalled / 90', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                const Text('Called', style: TextStyle(fontSize: 11, color: Colors.white70)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentCallsBar(List<MptCalledNumber> called) {
    final recent = called.reversed.take(6).toList();
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: recent.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, idx) {
          final item = recent[idx];
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: idx == 0 ? AppTheme.secondaryColor : AppTheme.darkSurface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF2E334D)),
            ),
            child: Text(
              '${item.number}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: idx == 0 ? Colors.black : Colors.white,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTicketMatrix(MptTicket ticket, Set<int> calledSet, {bool isGameEnded = false}) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: AppTheme.primaryLight, width: 1.5)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('DEBHOUSIE TICKET #${ticket.ticketNumber}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.primaryLight)),
                Text(
                  isGameEnded ? '${_markedNumbers.length} / 15 Marked (Final)' : '${_markedNumbers.length} / 15 Marked',
                  style: const TextStyle(fontSize: 12, color: Color(0xFFA0AEC0)),
                ),
              ],
            ),
            const Divider(color: Color(0xFF2E334D), height: 16),
            for (int r = 0; r < 3; r++)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    for (int c = 0; c < 9; c++)
                      Expanded(
                        child: _buildTicketCell(ticket.matrix[r][c], calledSet, isGameEnded: isGameEnded),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTicketCell(int numVal, Set<int> calledSet, {bool isGameEnded = false}) {
    if (numVal == 0) {
      return Container(
        height: 48,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: AppTheme.darkBackground.withOpacity(0.6),
          borderRadius: BorderRadius.circular(6),
        ),
      );
    }

    final isMarked = _markedNumbers.contains(numVal);

    // Item 10: Manual green marking only (no auto-yellow)
    Color bgColor = isMarked ? AppTheme.accentSuccess : AppTheme.darkSurface;
    Color textColor = Colors.white;

    return GestureDetector(
      onTap: isGameEnded ? null : () => _toggleMark(numVal),
      child: Container(
        height: 48,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isMarked ? AppTheme.accentSuccess : const Color(0xFF3B4163),
            width: isMarked ? 1.5 : 1,
          ),
        ),
        child: Center(
          child: Text(
            '$numVal',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPrizeClaimsSection(
    List<String> activePrizes,
    Map<String, MptClaim> approvedClaims,
    String? currentUserId,
    MptTicket ticket,
    Set<int> calledSet, {
    bool isGameEnded = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Claim Winning Prize',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            if (isGameEnded)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF3B4163)),
                ),
                child: const Text(
                  'GAME CONCLUDED (CLAIMS CLOSED)',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFA0AEC0)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          isGameEnded
              ? 'Game is over. Prize claiming is closed for this session.'
              : 'Tap when you complete a pattern. Server will validate your marked numbers.',
          style: const TextStyle(fontSize: 12, color: Color(0xFFA0AEC0)),
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 2.3,
          children: activePrizes.map((prize) {
            final approvedClaim = approvedClaims[prize];
            final isApproved = approvedClaim != null;
            final isWonByMe = isApproved && approvedClaim.userId == currentUserId;

            if (isApproved) {
              return ElevatedButton(
                onPressed: null, // Disabled
                style: ElevatedButton.styleFrom(
                  backgroundColor: isWonByMe ? AppTheme.secondaryColor.withOpacity(0.2) : Colors.black26,
                  disabledBackgroundColor: isWonByMe ? AppTheme.secondaryColor.withOpacity(0.25) : const Color(0xFF222639),
                  disabledForegroundColor: isWonByMe ? AppTheme.secondaryColor : const Color(0xFF718096),
                  side: BorderSide(color: isWonByMe ? AppTheme.secondaryColor : const Color(0xFF2E334D)),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      Formatters.formatPrizeName(prize),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    Text(
                      isWonByMe ? '🏆 Won by You!' : '✓ Won by ${approvedClaim.userName ?? "Player"}',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isWonByMe ? AppTheme.secondaryColor : const Color(0xFFA0AEC0)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              );
            }

            if (isGameEnded) {
              return ElevatedButton(
                onPressed: null, // Disabled when game ended
                style: ElevatedButton.styleFrom(
                  disabledBackgroundColor: const Color(0xFF1E2235),
                  disabledForegroundColor: const Color(0xFF64748B),
                  side: const BorderSide(color: Color(0xFF2E334D)),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      Formatters.formatPrizeName(prize),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const Text(
                      'Unclaimed (Game Over)',
                      style: TextStyle(fontSize: 9, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              );
            }

            return ElevatedButton(
              onPressed: _isClaiming
                  ? null
                  : () => _handleClaimPrize(
                        prizeType: prize,
                        ticket: ticket,
                        calledSet: calledSet,
                      ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.darkSurface,
                foregroundColor: Colors.white,
                side: const BorderSide(color: AppTheme.primaryColor),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
              child: Text(
                Formatters.formatPrizeName(prize),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
