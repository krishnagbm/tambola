import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/config/app_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/mpt_game.dart';
import '../../../models/mpt_registration.dart';
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

  Future<void> _handleShareInvite(MptGame game) async {
    final link = 'https://tambola.digitalappstudio.com/#/join/${game.inviteCode}';
    final text = '🎉 You are invited to play DebHousie with me in "${game.name}"!\n\n'
        '🔑 Invite Code: ${game.inviteCode}\n\n'
        '👉 Tap the link below to open the app or download it:\n$link';
    await Share.share(text, subject: 'Join DebHousie: ${game.name}');
  }

  Future<void> _handleStartGame(MptGame game, int confirmedCount, int walletCredits) async {
    final tiers = ref.read(capacityTiersProvider).value;
    int creditsNeeded = 10;
    if (tiers != null && tiers.isNotEmpty) {
      final matchingTier = tiers.firstWhere(
        (t) => (confirmedCount == 0 && t.minPlayers <= 1) || (confirmedCount > 0 && confirmedCount >= t.minPlayers && confirmedCount <= t.maxPlayers),
        orElse: () => tiers.firstWhere((t) => t.maxPlayers >= confirmedCount, orElse: () => tiers.first),
      );
      creditsNeeded = matchingTier.creditsRequired;
    } else {
      creditsNeeded = confirmedCount <= 10
          ? 10
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
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentSuccess),
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
              'Add mock credits (for testing) or buy credits on the web to start the game.',
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
            tooltip: 'Live Display',
            onPressed: () => context.push('/live-display/${widget.gameId}'),
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
          if (game.isInProgress) {
            return Center(
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
            );
          }

          return regStream.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Center(child: Text('Error loading registrations: $err')),
            data: (registrations) {
              final confirmed = registrations.where((r) => r.isConfirmed).toList();
              final waiting = registrations.where((r) => r.isWaiting).toList();
              final walletCredits = walletState.value?.availableCredits ?? 0;

              return SingleChildScrollView(
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

                    _buildRegistrationsSection(registrations),
                  ],
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
            hintText: 'e.g. Saturday Family DebHousie',
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
                    icon: const Icon(Icons.copy, size: 20, color: AppTheme.primaryLight),
                    tooltip: 'Copy Code',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: game.inviteCode));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Invite code copied to clipboard!')),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.share, size: 20, color: AppTheme.secondaryColor),
                    tooltip: 'Share with WhatsApp/Telegram',
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
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
        const SizedBox(height: 10),

        if (AppConfig.enableMockCredits)
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isProcessing ? null : () => _handleExpandCapacity(25),
                  icon: const Icon(Icons.group_add, size: 18),
                  label: const Text('+25 Seats Capacity'),
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
            onPressed: _isProcessing ? null : () => _handleExpandCapacity(25),
            icon: const Icon(Icons.group_add, size: 18),
            label: const Text('+25 Seats Capacity'),
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          ),
      ],
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
}
