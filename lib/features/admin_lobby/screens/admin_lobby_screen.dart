import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/config/app_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/live_display_helper.dart';
import '../../../models/mpt_capacity_tier.dart';
import '../../../models/mpt_game.dart';
import '../../../models/mpt_registration.dart';
import '../../../models/mpt_seat_otp.dart';
import '../../../providers/app_providers.dart';

class AdminLobbyScreen extends ConsumerStatefulWidget {
  final String gameId;

  const AdminLobbyScreen({super.key, required this.gameId});

  @override
  ConsumerState<AdminLobbyScreen> createState() => _AdminLobbyScreenState();
}

class _AdminLobbyScreenState extends ConsumerState<AdminLobbyScreen> {
  bool _isProcessing = false;

  void _handleGoBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  void _handleCopyLink(MptGame game) {
    final link = '${AppConfig.appBaseUrl}/#/join/${game.inviteCode}';
    Clipboard.setData(ClipboardData(text: link));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Direct join link copied to clipboard!')),
    );
  }

  Future<void> _handleShareInvite(MptGame game) async {
    final link = '${AppConfig.appBaseUrl}/#/join/${game.inviteCode}';
    final text = '🎉 You are invited to play DabHousie with me in "${game.name}"!\n\n'
        '🔑 Invite Code: ${game.inviteCode}\n\n'
        '👉 Tap the link below to open the app or download it:\n$link';
    await Share.share(text, subject: 'Join DabHousie: ${game.name}');
  }

  Future<void> _handleCancelGame(MptGame game) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppTheme.accentDanger),
            SizedBox(width: 8),
            Text('Cancel Event?', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Are you sure you want to cancel "${game.name}"?\n\n'
          'This will close the lobby and deactivate the invite code (${game.inviteCode}). Any players currently in the lobby will be notified. No credits will be charged.',
          style: const TextStyle(fontSize: 14, color: Color(0xFFE2E8F0)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep Event'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentDanger,
              foregroundColor: Colors.white,
            ),
            child: const Text('Yes, Cancel Event'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isProcessing = true);
    try {
      await ref.read(gameRepositoryProvider).cancelGame(widget.gameId);
      ref.invalidate(myHostedGamesProvider);
      ref.invalidate(gameStreamProvider(widget.gameId));
      ref.invalidate(registrationsStreamProvider(widget.gameId));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Game event cancelled successfully.'),
          backgroundColor: AppTheme.accentSuccess,
        ),
      );
      context.go('/');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to cancel event: $e'),
          backgroundColor: AppTheme.accentDanger,
        ),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _handleStartGame(MptGame game, int confirmedCount, int walletCredits) async {
    final tiers = ref.read(capacityTiersProvider).value ?? MptCapacityTier.defaultTiers;
    int creditsNeeded = 0;
    if (tiers.isNotEmpty) {
      final matchingTier = tiers.firstWhere(
        (t) => (confirmedCount == 0 && t.minPlayers <= 1) || (confirmedCount > 0 && confirmedCount >= t.minPlayers && confirmedCount <= t.maxPlayers),
        orElse: () => tiers.firstWhere((t) => t.maxPlayers >= confirmedCount, orElse: () => tiers.last),
      );
      creditsNeeded = matchingTier.creditsRequired;
    } else {
      creditsNeeded = confirmedCount <= 5
          ? 0
          : confirmedCount <= 15
              ? 15
              : confirmedCount <= 25
                  ? 25
                  : confirmedCount <= 50
                      ? 50
                      : confirmedCount <= 100
                          ? 100
                          : 250;
    }


    if (walletCredits < creditsNeeded) {
      _showInsufficientCreditsDialog(creditsNeeded, walletCredits);
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Start Game & Charge Credits?', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text(
          'Starting the game will lock the room with $confirmedCount Confirmed players and charge $creditsNeeded credits.\n\n'
          'After start, no new registrations or capacity changes can be made for this game.',
          style: const TextStyle(fontSize: 14, color: Color(0xFFE2E8F0)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentSuccess,
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirm & Start Game'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isProcessing = true);
    try {
      await ref.read(gameplayRepositoryProvider).startGame(widget.gameId);
      ref.invalidate(walletProvider);
      ref.invalidate(gameStreamProvider(widget.gameId));

      if (!mounted) return;
      context.go('/admin-control/${widget.gameId}');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to start game: $e'),
          backgroundColor: AppTheme.accentDanger,
        ),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showInsufficientCreditsDialog(int required, int current) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppTheme.accentWarning),
            SizedBox(width: 8),
            Text('Insufficient Credits', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Starting this game requires $required credits for the confirmed players, but you only have $current credits.',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 14),
            const Text(
              'Credits can be added on the dabhousie.com website to host larger games.',
              style: TextStyle(fontSize: 12, color: Color(0xFFA0AEC0)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          if (AppConfig.enableMockCredits)
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                await _handleAddMockCredits(200);
              },
              icon: const Icon(Icons.flash_on, size: 16),
              label: const Text('Add 200 Mock Credits'),
            ),
        ],
      ),
    );
  }

  Future<void> _handleAddMockCredits(int amount) async {
    setState(() => _isProcessing = true);
    try {
      await ref.read(walletRepositoryProvider).addMockCredits(amount);
      ref.invalidate(walletProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added $amount Mock Credits to your wallet! 🎉'),
          backgroundColor: AppTheme.accentSuccess,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error adding credits: $e'), backgroundColor: AppTheme.accentDanger),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _handleExpandCapacity(int extraCapacity) async {
    setState(() => _isProcessing = true);
    try {
      await ref.read(gameRepositoryProvider).increaseCapacity(
            gameId: widget.gameId,
            additionalCapacity: extraCapacity,
          );
      ref.invalidate(gameStreamProvider(widget.gameId));
      ref.invalidate(registrationsStreamProvider(widget.gameId));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Capacity expanded by $extraCapacity seats! Waiting players promoted automatically. 🚀'),
          backgroundColor: AppTheme.accentSuccess,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error expanding capacity: $e'), backgroundColor: AppTheme.accentDanger),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final gameStream = ref.watch(gameStreamProvider(widget.gameId));
    final regStream = ref.watch(registrationsStreamProvider(widget.gameId));
    final walletState = ref.watch(walletProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back to Home',
          onPressed: _handleGoBack,
        ),
        title: const Text('Organizer Game Lobby'),
        actions: [
          IconButton(
            icon: const Icon(Icons.tv, color: AppTheme.secondaryColor),
            tooltip: 'Live Display (Open in New Tab / Window)',
            onPressed: () => LiveDisplayHelper.openInNewWindow(context, widget.gameId),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () {
              ref.invalidate(gameStreamProvider(widget.gameId));
              ref.invalidate(registrationsStreamProvider(widget.gameId));
              ref.invalidate(walletProvider);
            },
          ),
        ],
      ),
      body: gameStream.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.cloud_off, size: 56, color: AppTheme.accentWarning),
                const SizedBox(height: 16),
                const Text(
                  'Connecting to Game Lobby...',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  err.toString(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Color(0xFFA0AEC0)),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _handleGoBack,
                      icon: const Icon(Icons.home),
                      label: const Text('Home'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: () {
                        ref.invalidate(gameStreamProvider(widget.gameId));
                        ref.invalidate(registrationsStreamProvider(widget.gameId));
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        data: (game) {
          if (game.isCancelled) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.cancel_outlined, size: 64, color: AppTheme.accentDanger),
                      const SizedBox(height: 16),
                      const Text(
                        'Event Cancelled',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'This game event ("${game.name}") has been cancelled by the host. The lobby and invite code are deactivated.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 14, color: Color(0xFFA0AEC0)),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _handleGoBack,
                        icon: const Icon(Icons.home),
                        label: const Text('Return to Home'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.secondaryColor,
                          foregroundColor: AppTheme.primaryDark,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          if (game.isInProgress) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.play_circle_outline, size: 56, color: AppTheme.accentSuccess),
                      const SizedBox(height: 12),
                      const Text('Game is already in progress!', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => context.go('/admin-control/${widget.gameId}'),
                        child: const Text('Open Game Controls & Number Caller'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          return regStream.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Center(child: Text('Error loading registrations: $err')),
            data: (registrations) {
              final confirmed = registrations.where((r) => r.isConfirmed).toList();
              final waiting = registrations.where((r) => r.isWaiting).toList();
              final walletCredits = walletState.value?.availableCredits ?? 0;

              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildGameHeaderCard(game),
                        const SizedBox(height: 16),

                        _buildMetricsGrid(game, registrations.length, confirmed.length, waiting.length, walletCredits),
                        const SizedBox(height: 16),

                        if (waiting.isNotEmpty) ...[
                          _buildCapacityWarningBanner(waiting.length),
                          const SizedBox(height: 16),
                        ],

                        _buildActionButtons(game, confirmed.length, waiting.length, walletCredits),
                        const SizedBox(height: 24),

                        if (game.isPrivate) ...[
                          _buildPrivateSeatsManagementSection(game),
                          const SizedBox(height: 24),
                        ],

                        _buildRegistrationsSection(registrations),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showEditGameNameDialog(MptGame game) {
    final controller = TextEditingController(text: game.name);
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
              if (newName.isNotEmpty && newName != game.name) {
                Navigator.pop(ctx);
                try {
                  await ref.read(gameRepositoryProvider).updateGameName(game.id, newName);
                  ref.invalidate(gameStreamProvider(game.id));
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

  Widget _buildGameHeaderCard(MptGame game) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
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
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit, size: 16, color: AppTheme.primaryLight),
                        tooltip: 'Edit Event Name',
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        constraints: const BoxConstraints(),
                        onPressed: () => _showEditGameNameDialog(game),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'LOBBY OPEN',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryLight),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.darkSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF2E334D)),
              ),
              child: Row(
                children: [
                  const Text('Invite Code: ', style: TextStyle(color: Color(0xFFA0AEC0), fontSize: 13)),
                  Text(
                    game.inviteCode,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.secondaryColor, letterSpacing: 1.5),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 18, color: AppTheme.primaryLight),
                    tooltip: 'Copy Code Only',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: game.inviteCode));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Invite code copied to clipboard!')),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.link, size: 20, color: AppTheme.primaryLight),
                    tooltip: 'Copy Direct Join Link',
                    onPressed: () => _handleCopyLink(game),
                  ),
                  IconButton(
                    icon: const Icon(Icons.share, size: 20, color: AppTheme.secondaryColor),
                    tooltip: 'Share Invite',
                    onPressed: () => _handleShareInvite(game),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricsGrid(MptGame game, int totalCount, int confirmedCount, int waitingCount, int walletCredits) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                title: 'Confirmed',
                value: '$confirmedCount',
                subtitle: '${game.fundedCapacity} Cap',
                color: AppTheme.accentSuccess,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildMetricCard(
                title: 'Waiting',
                value: '$waitingCount',
                subtitle: 'Overflow',
                color: waitingCount > 0 ? AppTheme.accentWarning : const Color(0xFFA0AEC0),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildMetricCard(
                title: 'Credits',
                value: '$walletCredits',
                subtitle: 'Wallet',
                color: AppTheme.secondaryColor,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String subtitle,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2E334D)),
      ),
      child: Column(
        children: [
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color)),
          const SizedBox(height: 2),
          Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
          Text(subtitle, style: const TextStyle(fontSize: 11, color: Color(0xFFA0AEC0))),
        ],
      ),
    );
  }

  Widget _buildCapacityWarningBanner(int waitingCount) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.accentWarning.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.accentWarning),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: AppTheme.accentWarning, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Capacity Overflow ($waitingCount Waiting)',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.accentWarning, fontSize: 14),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Some players are in the waiting queue. Expand capacity below to confirm their seats before game start.',
                  style: TextStyle(fontSize: 12, color: Color(0xFFCBD5E1)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(MptGame game, int confirmedCount, int waitingCount, int walletCredits) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton.icon(
          onPressed: _isProcessing ? null : () => _handleStartGame(game, confirmedCount, walletCredits),
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('Start Game & Deduct Credits', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.accentSuccess,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
        const SizedBox(height: 10),

        if (AppConfig.enableMockCredits)
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isProcessing ? null : () => _showAddCapacityDialog(context, waitingCount),
                  icon: const Icon(Icons.group_add, size: 18),
                  label: const Text('+ Add Seats (+5, +10, +15, +25)'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isProcessing ? null : () => _handleAddMockCredits(200),
                  icon: const Icon(Icons.flash_on, size: 18, color: AppTheme.secondaryColor),
                  label: const Text('+200 Mock Credits'),
                ),
              ),
            ],
          )
        else
          OutlinedButton.icon(
            onPressed: _isProcessing ? null : () => _showAddCapacityDialog(context, waitingCount),
            icon: const Icon(Icons.group_add, size: 18),
            label: const Text('+ Add Seats (+5, +10, +15, +25)'),
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _isProcessing ? null : () => _handleCancelGame(game),
          icon: const Icon(Icons.cancel_outlined, size: 18, color: AppTheme.accentDanger),
          label: const Text('Cancel Event', style: TextStyle(color: AppTheme.accentDanger, fontWeight: FontWeight.bold)),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: AppTheme.accentDanger),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ],
    );
  }

  void _showAddCapacityDialog(BuildContext context, int waitingCount) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.group_add_rounded, color: AppTheme.secondaryColor, size: 26),
            SizedBox(width: 8),
            Text('Add Seats Capacity', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (waitingCount > 0) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.accentWarning.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.accentWarning.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: AppTheme.accentWarning, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$waitingCount player${waitingCount > 1 ? "s are" : " is"} waiting in the overflow queue and will be confirmed immediately upon adding seats.',
                        style: const TextStyle(fontSize: 12, color: Color(0xFFFDE68A)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],
            const Text(
              'Select seats boost to add to this room:',
              style: TextStyle(fontSize: 13, color: Color(0xFFA0AEC0)),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _buildCapacityOptionButton(ctx, '+5 Seats', 5, isRecommended: waitingCount > 0 && waitingCount <= 5),
                _buildCapacityOptionButton(ctx, '+10 Seats', 10, isRecommended: waitingCount > 5 && waitingCount <= 10),
                _buildCapacityOptionButton(ctx, '+15 Seats', 15, isRecommended: waitingCount > 10 && waitingCount <= 15),
                _buildCapacityOptionButton(ctx, '+25 Seats', 25, isRecommended: waitingCount > 15 && waitingCount <= 25),
                _buildCapacityOptionButton(ctx, '+50 Seats', 50, isRecommended: waitingCount > 25),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (Navigator.of(ctx, rootNavigator: true).canPop()) {
                Navigator.of(ctx, rootNavigator: true).pop();
              }
            },
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Widget _buildCapacityOptionButton(BuildContext ctx, String label, int seats, {bool isRecommended = false}) {
    return ElevatedButton(
      onPressed: () {
        if (Navigator.of(ctx, rootNavigator: true).canPop()) {
          Navigator.of(ctx, rootNavigator: true).pop();
        }
        _handleExpandCapacity(seats);
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: isRecommended ? AppTheme.secondaryColor : AppTheme.darkSurface,
        foregroundColor: isRecommended ? AppTheme.primaryDark : Colors.white,
        side: BorderSide(color: isRecommended ? AppTheme.secondaryColor : const Color(0xFF3B4163)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Text(
        label,
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isRecommended ? AppTheme.primaryDark : Colors.white),
      ),
    );
  }

  Widget _buildRegistrationsSection(List<MptRegistration> registrations) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Registered Participants (${registrations.length})',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        if (registrations.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text('No players have joined yet. Share the invite code!', style: TextStyle(color: Color(0xFFA0AEC0))),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: registrations.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (context, index) {
              final reg = registrations[index];
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.darkSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: reg.isConfirmed ? AppTheme.accentSuccess.withValues(alpha: 0.3) : AppTheme.accentWarning.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: reg.isConfirmed ? AppTheme.accentSuccess.withValues(alpha: 0.2) : AppTheme.accentWarning.withValues(alpha: 0.2),
                      child: Text(
                        '#${reg.registrationSeq}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: reg.isConfirmed ? AppTheme.accentSuccess : AppTheme.accentWarning,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        reg.displayName,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: reg.isConfirmed ? AppTheme.accentSuccess.withValues(alpha: 0.2) : AppTheme.accentWarning.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        reg.seatStatus,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: reg.isConfirmed ? AppTheme.accentSuccess : AppTheme.accentWarning,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildPrivateSeatsManagementSection(MptGame game) {
    final otpsStream = ref.watch(gameSeatOtpsStreamProvider(game.id));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.lock_rounded, color: AppTheme.accentPartyPurple, size: 22),
                    SizedBox(width: 8),
                    Text(
                      'Private Party Seat Passcodes',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.accentPartyPurple.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.accentPartyPurple),
                  ),
                  child: const Text(
                    'ZERO-PII',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.accentPartyPurple),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Distribute one unique passcode to each member. Once entered, the seat is bound to that player.',
              style: TextStyle(fontSize: 12.5, color: Color(0xFFA0AEC0)),
            ),
            const SizedBox(height: 14),

            otpsStream.when(
              loading: () => const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())),
              error: (e, _) => Text('Error loading seats: $e', style: const TextStyle(color: AppTheme.accentDanger)),
              data: (otps) {
                final claimedCount = otps.where((o) => o.isClaimed).length;
                final unclaimedCount = otps.where((o) => o.isUnclaimed).length;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Stats and Batch Actions Bar
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'Seats: ${otps.length} Total  •  $claimedCount Claimed  •  $unclaimedCount Unclaimed',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFE2E8F0)),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => _handleCopyAllOtps(game, otps),
                              icon: const Icon(Icons.copy, size: 14, color: AppTheme.secondaryColor),
                              label: const Text('Copy All', style: TextStyle(fontSize: 12, color: AppTheme.secondaryColor)),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                side: const BorderSide(color: AppTheme.secondaryColor),
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: () => _handleResendEmail(game),
                              icon: const Icon(Icons.email_outlined, size: 14, color: AppTheme.primaryLight),
                              label: const Text('Email List', style: TextStyle(fontSize: 12, color: AppTheme.primaryLight)),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                side: const BorderSide(color: AppTheme.primaryLight),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              onPressed: () => _handleAddPrivateSeatsDialog(game),
                              icon: const Icon(Icons.add, size: 14),
                              label: const Text('+ Add Seats', style: TextStyle(fontSize: 12)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.accentPartyPurple,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Grid / List of Seats
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 280),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: otps.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 6),
                        itemBuilder: (ctx, index) {
                          final seat = otps[index];
                          Color badgeBg;
                          Color badgeColor;
                          String badgeText;

                          if (seat.isClaimed) {
                            badgeBg = AppTheme.accentSuccess.withValues(alpha: 0.2);
                            badgeColor = AppTheme.accentSuccess;
                            badgeText = 'CLAIMED';
                          } else if (seat.isRevoked) {
                            badgeBg = Colors.grey.withValues(alpha: 0.2);
                            badgeColor = Colors.grey;
                            badgeText = 'REVOKED';
                          } else {
                            badgeBg = AppTheme.accentPartyPurple.withValues(alpha: 0.2);
                            badgeColor = AppTheme.accentPartyPurple;
                            badgeText = 'UNCLAIMED';
                          }

                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppTheme.darkSurface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFF2E334D)),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 13,
                                  backgroundColor: AppTheme.accentPartyPurple.withValues(alpha: 0.2),
                                  child: Text(
                                    '#${seat.seatNumber}',
                                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.accentPartyPurple),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: badgeBg,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    badgeText,
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: badgeColor),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: SelectableText(
                                    seat.isRevoked ? '---' : seat.otpCode,
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 2,
                                      color: seat.isClaimed ? const Color(0xFF94A3B8) : Colors.white,
                                      decoration: seat.isRevoked ? TextDecoration.lineThrough : null,
                                    ),
                                  ),
                                ),
                                if (seat.isUnclaimed)
                                  IconButton(
                                    icon: const Icon(Icons.copy, size: 16, color: AppTheme.primaryLight),
                                    tooltip: 'Copy Seat Passcode',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: () {
                                      Clipboard.setData(ClipboardData(text: seat.otpCode));
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Seat #${seat.seatNumber} passcode (${seat.otpCode}) copied!')),
                                      );
                                    },
                                  ),
                                const SizedBox(width: 8),
                                PopupMenuButton<String>(
                                  icon: const Icon(Icons.more_vert, size: 18, color: Color(0xFF94A3B8)),
                                  color: AppTheme.darkCard,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  onSelected: (val) {
                                    if (val == 'reissue') {
                                      _handleReissueSeatOtp(game, seat);
                                    } else if (val == 'revoke') {
                                      _handleRevokeSeatOtp(game, seat);
                                    }
                                  },
                                  itemBuilder: (_) => [
                                    const PopupMenuItem(
                                      value: 'reissue',
                                      child: Row(
                                        children: [
                                          Icon(Icons.refresh, size: 16, color: AppTheme.secondaryColor),
                                          SizedBox(width: 8),
                                          Text('Reissue Fresh Passcode', style: TextStyle(fontSize: 13)),
                                        ],
                                      ),
                                    ),
                                    if (!seat.isRevoked)
                                      const PopupMenuItem(
                                        value: 'revoke',
                                        child: Row(
                                          children: [
                                            Icon(Icons.block, size: 16, color: AppTheme.accentDanger),
                                            SizedBox(width: 8),
                                            Text('Revoke Seat', style: TextStyle(fontSize: 13, color: AppTheme.accentDanger)),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleReissueSeatOtp(MptGame game, MptSeatOtp seat) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.refresh, color: AppTheme.secondaryColor),
            SizedBox(width: 8),
            Text('Reissue Seat Passcode', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Reissue a brand new passcode for Seat #${seat.seatNumber}?\n\n'
          'The old passcode (${seat.otpCode}) will immediately stop working, and any player currently holding this seat will be removed.',
          style: const TextStyle(fontSize: 13.5, color: Color(0xFFCBD5E1)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.secondaryColor, foregroundColor: Colors.black),
            child: const Text('Reissue', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await ref.read(gameRepositoryProvider).reissueSeatOtp(gameId: game.id, seatId: seat.id);
      ref.invalidate(gameSeatOtpsStreamProvider(game.id));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Seat #${seat.seatNumber} passcode reissued successfully!')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to reissue passcode: $e'), backgroundColor: AppTheme.accentDanger),
      );
    }
  }

  Future<void> _handleRevokeSeatOtp(MptGame game, MptSeatOtp seat) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.block, color: AppTheme.accentDanger),
            SizedBox(width: 8),
            Text('Revoke Seat', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Revoke Seat #${seat.seatNumber}?\n\n'
          'This seat will be marked as REVOKED and cannot be used by anyone.',
          style: const TextStyle(fontSize: 13.5, color: Color(0xFFCBD5E1)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentDanger, foregroundColor: Colors.white),
            child: const Text('Revoke', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await ref.read(gameRepositoryProvider).revokeSeatOtp(gameId: game.id, seatId: seat.id);
      ref.invalidate(gameSeatOtpsStreamProvider(game.id));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Seat #${seat.seatNumber} revoked.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to revoke seat: $e'), backgroundColor: AppTheme.accentDanger),
      );
    }
  }

  void _handleAddPrivateSeatsDialog(MptGame game) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.add_circle_outline, color: AppTheme.accentPartyPurple),
            SizedBox(width: 8),
            Text('Add Private Seats', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select how many additional seats & single-use passcodes to generate:',
              style: TextStyle(fontSize: 13, color: Color(0xFFA0AEC0)),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [5, 10, 15, 25].map((count) {
                return ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    try {
                      await ref.read(gameRepositoryProvider).addSeatOtps(gameId: game.id, additionalSeats: count);
                      ref.invalidate(gameStreamProvider(game.id));
                      ref.invalidate(gameSeatOtpsStreamProvider(game.id));
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('+$count private seats added successfully!')),
                      );
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to add seats: $e'), backgroundColor: AppTheme.accentDanger),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryLight,
                    foregroundColor: Colors.white,
                  ),
                  child: Text('+$count Seats', style: const TextStyle(fontWeight: FontWeight.bold)),
                );
              }).toList(),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ],
      ),
    );
  }

  void _handleCopyAllOtps(MptGame game, List<MptSeatOtp> otps) {
    final joinUrl = '${AppConfig.appBaseUrl}/#/join/${game.inviteCode}';
    final buffer = StringBuffer();
    buffer.writeln('🔒 Private Party: ${game.name}');
    buffer.writeln('👉 Join Link: $joinUrl');
    buffer.writeln('🔑 Party Code: ${game.inviteCode}');
    buffer.writeln('\nSingle-Use Seat Passcodes:');

    for (final seat in otps) {
      if (!seat.isRevoked) {
        buffer.writeln('Seat #${seat.seatNumber}: ${seat.otpCode}');
      }
    }

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('All private party passcodes copied to clipboard!')),
    );
  }

  Future<void> _handleResendEmail(MptGame game) async {
    final user = ref.read(currentUserProvider).value;
    final email = user?.email ?? '';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.email_rounded, color: AppTheme.secondaryColor),
            SizedBox(width: 8),
            Text('Email Seat Passcodes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'A complete list of your single-use seat passcodes will be sent to your account email:',
              style: TextStyle(fontSize: 13, color: Color(0xFFCBD5E1)),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.darkSurface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.secondaryColor.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.account_circle_outlined, size: 16, color: AppTheme.secondaryColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      email.isNotEmpty ? email : 'Your registered host email',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryLight,
              foregroundColor: Colors.white,
            ),
            child: const Text('Send Email'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Sending passcodes to $email...')),
    );

    try {
      final res = await ref.read(gameRepositoryProvider).sendPrivatePartyEmail(
        gameId: game.id,
        targetEmail: email.isNotEmpty ? email : null,
      );
      if (!mounted) return;

      final success = res['success'] == true;
      final target = res['email'] ?? email;

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Passcodes successfully emailed to $target! 🎉'),
            backgroundColor: AppTheme.accentSuccess,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              target != null && target.toString().isNotEmpty
                  ? 'Attempted email to $target. (If using SES Sandbox, please verify $target in AWS SES Console).'
                  : 'Email delivery attempted. You can also copy all passcodes directly using "Copy All".',
            ),
            backgroundColor: AppTheme.accentWarning,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Email error: $e. You can use "Copy All" anytime.')),
      );
    }
  }
}
