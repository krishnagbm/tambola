import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/config/app_config.dart';
import '../../../core/constants/app_assets.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/live_display_helper.dart';
import '../../../core/utils/tambola_audio_caller.dart';
import '../../../models/mpt_claim.dart';
import '../../../models/mpt_game.dart';
import '../../../providers/app_providers.dart';

class LiveGameDisplayScreen extends ConsumerStatefulWidget {
  final String gameId;

  const LiveGameDisplayScreen({super.key, required this.gameId});

  @override
  ConsumerState<LiveGameDisplayScreen> createState() =>
      _LiveGameDisplayScreenState();
}

class _LiveGameDisplayScreenState extends ConsumerState<LiveGameDisplayScreen> {
  int _lastAnnouncedSeq = 0;
  bool _isMuted = false;
  Timer? _autoReconnectTimer;

  @override
  void initState() {
    super.initState();
    _isMuted = TambolaAudioCaller().isMuted;

    // Automatic periodic reconnect watchdog for TV displays
    _autoReconnectTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (!mounted) return;
      final gameState = ref.read(gameStreamProvider(widget.gameId));
      final calledState = ref.read(calledNumbersStreamProvider(widget.gameId));
      if (gameState.hasError || calledState.hasError) {
        _retryConnection();
      }
    });
  }

  @override
  void dispose() {
    _autoReconnectTimer?.cancel();
    super.dispose();
  }

  void _retryConnection() {
    ref.invalidate(gameStreamProvider(widget.gameId));
    ref.invalidate(calledNumbersStreamProvider(widget.gameId));
    ref.invalidate(claimsStreamProvider(widget.gameId));
  }

  void _showCastDialog() {
    LiveDisplayHelper.showDisplayOnTvDialog(context, widget.gameId);
  }

  @override
  Widget build(BuildContext context) {
    final gameStream = ref.watch(gameStreamProvider(widget.gameId));
    final calledStream = ref.watch(calledNumbersStreamProvider(widget.gameId));
    final claimsStream = ref.watch(claimsStreamProvider(widget.gameId));

    // Announce new number if sequence increased
    calledStream.whenData((calledNumbers) {
      if (calledNumbers.isNotEmpty &&
          calledNumbers.length > _lastAnnouncedSeq) {
        _lastAnnouncedSeq = calledNumbers.length;
        final latestNum = calledNumbers.last.number;
        TambolaAudioCaller().announceNumber(latestNum);
      }
    });

    return gameStream.when(
      loading: () => Scaffold(
        backgroundColor: AppTheme.primaryDark,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                AppAssets.horizontalLogo,
                height: 48,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 24),
              const CircularProgressIndicator(color: AppTheme.secondaryColor),
              const SizedBox(height: 16),
              const Text(
                'Connecting to Live Game Display...',
                style: TextStyle(
                  fontSize: 16,
                  color: Color(0xFFCBD5E1),
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Initializing real-time stream',
                style: TextStyle(fontSize: 12, color: Color(0xFFA0AEC0)),
              ),
            ],
          ),
        ),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: AppTheme.primaryDark,
        body: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 480),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: AppTheme.darkCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF2E334D)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.wifi_off_rounded,
                  size: 54,
                  color: AppTheme.accentWarning,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Connection Interrupted',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Attempting automatic reconnection to the game...',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Color(0xFFCBD5E1)),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _retryConnection,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reconnect Now'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.secondaryColor,
                    foregroundColor: AppTheme.primaryDark,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      data: (game) {
        return Scaffold(
          appBar: AppBar(
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  AppAssets.horizontalLogo,
                  height: 28,
                  fit: BoxFit.contain,
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    '• ${game.name}',
                    style: const TextStyle(
                      fontSize: 15,
                      color: Color(0xFFA0AEC0),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            actions: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.secondaryColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppTheme.secondaryColor.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.vpn_key_outlined,
                      size: 14,
                      color: AppTheme.secondaryColor,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      game.inviteCode,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: AppTheme.secondaryColor,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                icon: const Icon(Icons.tv, color: AppTheme.secondaryColor),
                tooltip: 'Display Game on TV / Projector',
                onPressed: _showCastDialog,
              ),
              IconButton(
                icon: Icon(
                  _isMuted ? Icons.volume_off : Icons.volume_up,
                  color: _isMuted ? Colors.grey : AppTheme.secondaryColor,
                ),
                tooltip: _isMuted ? 'Unmute Audio Caller' : 'Mute Audio Caller',
                onPressed: () {
                  setState(() {
                    _isMuted = !_isMuted;
                    TambolaAudioCaller().isMuted = _isMuted;
                  });
                },
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: calledStream.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.sync_problem,
                    size: 40,
                    color: AppTheme.accentWarning,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Reconnecting to numbers board...',
                    style: TextStyle(color: Color(0xFFCBD5E1)),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _retryConnection,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
            data: (calledNumbers) {
              final latest = calledNumbers.isNotEmpty
                  ? calledNumbers.last.number
                  : null;
              final calledSet = calledNumbers.map((e) => e.number).toSet();

              return LayoutBuilder(
                builder: (ctx, constraints) {
                  final isWide = constraints.maxWidth > 700;

                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: isWide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 3,
                                child: _buildBoardGrid(
                                  calledSet,
                                  calledNumbers,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                flex: 2,
                                child: Column(
                                  children: [
                                    _buildCurrentBallHero(
                                      game,
                                      latest,
                                      calledNumbers.length,
                                    ),
                                    const SizedBox(height: 14),
                                    Expanded(
                                      child: _buildLiveWinnersPanel(
                                        claimsStream,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          )
                        : SingleChildScrollView(
                            child: Column(
                              children: [
                                _buildCurrentBallHero(
                                  game,
                                  latest,
                                  calledNumbers.length,
                                ),
                                const SizedBox(height: 16),
                                _buildBoardGrid(calledSet, calledNumbers),
                                const SizedBox(height: 16),
                                _buildLiveWinnersPanel(claimsStream),
                              ],
                            ),
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

  Widget _buildCurrentBallHero(MptGame game, int? latest, int totalCalled) {
    final isGameEnded = game.status == 'COMPLETED' || totalCalled >= 90;
    final joinUrl = '${AppConfig.appBaseUrl}/#/join/${game.inviteCode}';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isGameEnded
              ? const [
                  Color(0xFF0F766E), // Emerald dark
                  Color(0xFF134E4A), // Emerald deep
                ]
              : const [
                  Color(0xFF4338CA), // AppTheme.primaryColor
                  Color(0xFF312E81), // AppTheme.primaryDark
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color:
                (isGameEnded
                        ? const Color(0xFF0F766E)
                        : const Color(0xFF4338CA))
                    .withValues(alpha: 0.45),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 1. LEFT SIDE: NOW CALLING / GAME OVER & BALL
          Expanded(
            flex: 4,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isGameEnded ? 'GAME CONCLUDED' : 'NOW CALLING',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.8,
                    color: isGameEnded
                        ? AppTheme.secondaryColor
                        : Colors.white70,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: 86,
                  height: 86,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: isGameEnded
                        ? const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.emoji_events_rounded,
                                color: Color(0xFF0F766E),
                                size: 26,
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Game Over',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF0F766E),
                                ),
                              ),
                            ],
                          )
                        : Text(
                            latest != null ? '$latest' : 'READY',
                            style: TextStyle(
                              fontSize: latest != null ? 42 : 16,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.primaryDark,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  isGameEnded
                      ? 'Game Over • $totalCalled Called'
                      : (totalCalled > 0
                            ? '$totalCalled / 90 Called'
                            : 'Waiting for Start'),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),

          // VERTICAL DIVIDER 1
          Container(
            height: 120,
            width: 1,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            color: Colors.white.withValues(alpha: 0.22),
          ),

          // 2. MIDDLE SIDE: JOIN QR CODE & INVITE CODE
          Expanded(
            flex: 4,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.qr_code_scanner,
                        size: 11,
                        color: AppTheme.secondaryColor,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'SCAN TO PLAY',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.6,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                // Crisp White QR Card
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 6,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: QrImageView(
                    data: joinUrl,
                    version: QrVersions.auto,
                    size: 72.0,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Code: ',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: Colors.white70,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SelectableText(
                      game.inviteCode,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                        color: AppTheme.secondaryColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // VERTICAL DIVIDER 2
          Container(
            height: 120,
            width: 1,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            color: Colors.white.withValues(alpha: 0.22),
          ),

          // 3. RIGHT SIDE: DABHOUSIE BRANDING LOGO (3rd Column)
          Expanded(
            flex: 4,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset(
                    AppAssets.dabhousieLogo600x400,
                    height: 70,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => Image.asset(
                      AppAssets.horizontalLogo,
                      height: 50,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Live Tambola, Housie & 90-Ball Bingo',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.secondaryColor,
                    letterSpacing: 0.2,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 2),
                const Text(
                  'dabhousie.com',
                  style: TextStyle(fontSize: 9.5, color: Colors.white60),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBoardGrid(Set<int> calledSet, List<dynamic> calledList) {
    final recentCalls = calledList.reversed.skip(1).take(5).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Called Numbers Board',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.secondaryColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${calledSet.length}/90',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.secondaryColor,
                        ),
                      ),
                    ),
                  ],
                ),
                if (recentCalls.isNotEmpty)
                  Flexible(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      reverse: true,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'RECENT: ',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.secondaryColor,
                              letterSpacing: 0.8,
                            ),
                          ),
                          ...recentCalls.map((item) {
                            final n = item.number;
                            return Container(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 2.5,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryLight.withValues(
                                  alpha: 0.25,
                                ),
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(
                                  color: AppTheme.primaryLight.withValues(
                                    alpha: 0.4,
                                  ),
                                ),
                              ),
                              child: Text(
                                '$n',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 90,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 10,
                childAspectRatio: 1.1,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemBuilder: (ctx, idx) {
                final num = idx + 1;
                final isCalled = calledSet.contains(num);
                return Container(
                  decoration: BoxDecoration(
                    color: isCalled
                        ? AppTheme.accentSuccess
                        : AppTheme.darkSurface,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isCalled
                          ? AppTheme.accentSuccess
                          : const Color(0xFF2E334D),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      '$num',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isCalled
                            ? Colors.white
                            : const Color(0xFFA0AEC0),
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

  Widget _buildLiveWinnersPanel(AsyncValue<List<MptClaim>> claimsStream) {
    return Card(
      color: AppTheme.darkSurface,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.emoji_events,
                  color: AppTheme.secondaryColor,
                  size: 20,
                ),
                SizedBox(width: 8),
                Text(
                  'Winners Board',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(color: Color(0xFF2E334D)),
            claimsStream.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => const Text('Unable to load winners'),
              data: (claims) {
                final winners = claims
                    .where((c) => c.status == 'APPROVED')
                    .toList();
                if (winners.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'No winners declared yet.',
                      style: TextStyle(color: Color(0xFFA0AEC0), fontSize: 12),
                    ),
                  );
                }

                final regList =
                    ref
                        .watch(registrationsStreamProvider(widget.gameId))
                        .value ??
                    [];
                final regMap = {for (final r in regList) r.userId: r};

                return Column(
                  children: winners.map((w) {
                    final playerReg = regMap[w.userId];
                    final displayName =
                        (playerReg?.displayName.isNotEmpty == true)
                        ? playerReg!.displayName
                        : (w.userName != null && w.userName != 'Player')
                        ? w.userName!
                        : 'Player';
                    final avatar =
                        playerReg?.avatar ?? w.userAvatar ?? 'avatar_1';

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.secondaryColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppTheme.secondaryColor.withOpacity(0.4),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: AppTheme.secondaryColor.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              Formatters.getAvatarEmoji(avatar),
                              style: const TextStyle(fontSize: 16),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  Formatters.formatPrizeName(w.prizeType),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: Colors.white,
                                  ),
                                ),
                                Text(
                                  'Won by: $displayName',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.secondaryColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            Formatters.formatShortDate(w.submittedAt),
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xFFA0AEC0),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
