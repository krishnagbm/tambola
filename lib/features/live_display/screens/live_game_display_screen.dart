import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/config/app_config.dart';
import '../../../core/constants/app_assets.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/live_display_helper.dart';
import '../../../core/utils/tambola_audio_caller.dart';
import '../../../models/flash_housie_config.dart';
import '../../../models/mpt_called_number.dart';
import '../../../models/mpt_claim.dart';
import '../../../models/mpt_game.dart';
import '../../../models/mpt_game_trivia.dart';
import '../../../models/mpt_registration.dart';
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
  Timer? _neuroWaveTvTimer;

  // Post-Game Concluded State & Trivia TV Engine
  bool _forceShowBoardGridOnCompleted = false;
  int _triviaCountdownSecondsLeft = 15;
  Timer? _triviaCountdownTicker;
  int _triviaQuestionSecondsLeft = 15;
  Timer? _triviaQuestionTicker;
  int _lastHandledQuestionIndex = -1;
  bool _hasTriggeredTriviaGeneration = false;
  bool _hasTriggeredTriviaLaunch = false;
  bool _isReviewingQuestionsOnPodium = false;
  int _reviewQuestionIndex = 0;

  @override
  void initState() {
    super.initState();
    _isMuted = TambolaAudioCaller().isMuted;

    _neuroWaveTvTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (!mounted) return;
      final game = ref.read(gameStreamProvider(widget.gameId)).value;
      if (game?.isFlashHousie == true) {
        final neuro = game!.flashHousieConfig?.computeNeuroWaveState(
          DateTime.now().millisecondsSinceEpoch,
        );
        if (neuro != null && neuro.isRevealing) {
          setState(() {});
        }
      }
    });

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
    _triviaCountdownTicker?.cancel();
    _triviaQuestionTicker?.cancel();
    _neuroWaveTvTimer?.cancel();
    _autoReconnectTimer?.cancel();
    super.dispose();
  }

  void _retryConnection() {
    ref.invalidate(gameStreamProvider(widget.gameId));
    ref.invalidate(calledNumbersStreamProvider(widget.gameId));
    ref.invalidate(claimsStreamProvider(widget.gameId));
    ref.invalidate(memoryRoundScoresStreamProvider(widget.gameId));
  }

  void _showCastDialog() {
    LiveDisplayHelper.showDisplayOnTvDialog(context, widget.gameId);
  }

  @override
  Widget build(BuildContext context) {
    final gameStream = ref.watch(gameStreamProvider(widget.gameId));
    final calledStream = ref.watch(calledNumbersStreamProvider(widget.gameId));
    final claimsStream = ref.watch(claimsStreamProvider(widget.gameId));
    final registrationsStream =
        ref.watch(registrationsStreamProvider(widget.gameId));
    final ticketPoolAsync = ref.watch(gameTicketPoolProvider(widget.gameId));
    final quickPool = ticketPoolAsync.value ?? const <int>{};

    final confirmedPlayers = registrationsStream.value
            ?.where((r) => r.isConfirmed)
            .toList() ??
        [];
    final totalPlayers = confirmedPlayers.isNotEmpty
        ? confirmedPlayers.length
        : (gameStream.value?.fundedCapacity ?? 1);

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
                  Icons.error_outline,
                  color: AppTheme.accentDanger,
                  size: 48,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Game Not Found',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Could not load live game display: $e',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFFA0AEC0),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () => context.go('/'),
                  child: const Text('Back to Home'),
                ),
              ],
            ),
          ),
        ),
      ),
      data: (game) {
        return Scaffold(
          backgroundColor: AppTheme.primaryDark,
          appBar: AppBar(
            backgroundColor: AppTheme.darkCard,
            elevation: 2,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Back to Home',
              onPressed: () => context.go('/'),
            ),
            title: Row(
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
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFF38BDF8).withValues(alpha: 0.6),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.groups_rounded,
                      size: 14,
                      color: Color(0xFF38BDF8),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '$totalPlayers Players',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: Color(0xFF38BDF8),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
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
              if (game.isCompleted || game.status == 'COMPLETED')
                IconButton(
                  icon: Icon(
                    _forceShowBoardGridOnCompleted
                        ? Icons.emoji_events_rounded
                        : Icons.grid_view_rounded,
                    color: AppTheme.secondaryColor,
                  ),
                  tooltip: _forceShowBoardGridOnCompleted
                      ? 'Show Winners Podium & Trivia'
                      : 'Show Numbers Board Grid',
                  onPressed: () => setState(() => _forceShowBoardGridOnCompleted = !_forceShowBoardGridOnCompleted),
                ),
              const SizedBox(width: 4),
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
                  final newMuted = !_isMuted;
                  setState(() {
                    _isMuted = newMuted;
                    TambolaAudioCaller().isMuted = newMuted;
                  });
                  if (!newMuted) {
                    TambolaAudioCaller().testVoice();
                  } else {
                    TambolaAudioCaller().stop();
                  }
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

              final isGameCompleted = game.isCompleted || game.status == 'COMPLETED';
              if (isGameCompleted && !_forceShowBoardGridOnCompleted) {
                return _buildConcludedGameTvScreen(
                  game,
                  calledNumbers,
                  claimsStream,
                  totalPlayers,
                );
              }

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
                                child: SingleChildScrollView(
                                  child: _buildBoardGrid(
                                    calledSet,
                                    calledNumbers,
                                    game,
                                    quickPool,
                                  ),
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
                                      child: SingleChildScrollView(
                                        child: _buildLiveWinnersPanel(
                                          claimsStream,
                                          game,
                                        ),
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
                                _buildBoardGrid(
                                  calledSet,
                                  calledNumbers,
                                  game,
                                  quickPool,
                                ),
                                const SizedBox(height: 16),
                                _buildLiveWinnersPanel(claimsStream, game),
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

          // 3. RIGHT SIDE: DABBY MASCOT & DABHOUSIE BRANDING (3rd Column)
          Expanded(
            flex: 4,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Dabby Mascot
                Flexible(
                  flex: 5,
                  child: Hero(
                    tag: 'dabby_mascot_caller',
                    child: Image.asset(
                      AppAssets.dabbyMascot,
                      height: 98,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => Image.asset(
                        AppAssets.dabhousieLogo600x400,
                        height: 70,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Brand info & Dabby greeting
                Flexible(
                  flex: 6,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.secondaryColor.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: AppTheme.secondaryColor.withValues(alpha: 0.5),
                            width: 0.8,
                          ),
                        ),
                        child: const Text(
                          'MEET DABBY',
                          style: TextStyle(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                            color: AppTheme.secondaryColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        'Your Live Host!',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Live Tambola & Bingo',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.white70,
                        ),
                      ),
                      const Text(
                        'dabhousie.com',
                        style: TextStyle(
                          fontSize: 9.0,
                          color: AppTheme.secondaryColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBoardGrid(
    Set<int> calledSet,
    List<dynamic> calledList, [
    MptGame? game,
    Set<int> quickPool = const {},
  ]) {
    final recentCalls = calledList.reversed.skip(1).take(5).toList();
    final flashCfg = game?.flashHousieConfig;
    final activeCycle = flashCfg?.activeCycleSpec;
    final activeQuadrants = activeCycle?.activeQuadrants ?? const <int>[];
    final neuroState = flashCfg?.computeNeuroWaveState(
      DateTime.now().millisecondsSinceEpoch,
    );
    final isQuick = game?.isQuickDabby == true;
    final maxPool = isQuick && quickPool.isNotEmpty ? quickPool.length : 90;

    bool isNumberInActiveQuadrant(int num) {
      if (flashCfg == null || activeQuadrants.isEmpty) return true;
      final q = num <= 30 ? 1 : (num <= 60 ? 2 : 3);
      return activeQuadrants.contains(q);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (flashCfg != null && activeCycle != null && neuroState != null) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF141829),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppTheme.secondaryColor.withValues(alpha: 0.6),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          const Icon(
                            Icons.bolt_rounded,
                            color: AppTheme.secondaryColor,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              '${flashCfg.displayTitle} • Round ${flashCfg.currentCycle} of ${flashCfg.totalCycles} (${activeCycle.roundBadgeLabel})',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: neuroState.isRevealing
                            ? const Color(0xFF38BDF8).withValues(alpha: 0.2)
                            : AppTheme.accentSuccess.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        neuroState.isRevealing
                            ? '⚡ NeuroWave™ Spotlight (${(neuroState.remainingMsInPhase / 1000).ceil()}s)'
                            : '🎱 Round Pool: ${activeCycle.calledCount}/${activeCycle.drawPool.length}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: neuroState.isRevealing
                              ? const Color(0xFF38BDF8)
                              : AppTheme.accentSuccess,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
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
                    if (isQuick) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.secondaryColor.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: AppTheme.secondaryColor.withValues(alpha: 0.4),
                            width: 0.8,
                          ),
                        ),
                        child: const Text(
                          '⚡ QUICK DABBY',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.secondaryColor,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
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
                        '${calledSet.length}/$maxPool',
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
                childAspectRatio: 1.35,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemBuilder: (ctx, idx) {
                final num = idx + 1;
                final isCalled = calledSet.contains(num);
                final inActiveQuad = isNumberInActiveQuadrant(num);
                final isDeadNumber =
                    isQuick && quickPool.isNotEmpty && !quickPool.contains(num);
                final double cellOpacity = isDeadNumber
                    ? 0.18
                    : (inActiveQuad ? 1.0 : 0.32);

                return Opacity(
                  opacity: cellOpacity,
                  child: Container(
                    decoration: BoxDecoration(
                      color: isCalled
                          ? AppTheme.accentSuccess
                          : (isDeadNumber
                              ? const Color(0xFF141722)
                              : AppTheme.darkSurface),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isCalled
                            ? AppTheme.accentSuccess
                            : (isDeadNumber
                                ? const Color(0xFF1E2333)
                                : (flashCfg != null && inActiveQuad
                                    ? AppTheme.secondaryColor.withValues(
                                        alpha: 0.45,
                                      )
                                    : const Color(0xFF2E334D))),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '$num',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          decoration: isDeadNumber
                              ? TextDecoration.lineThrough
                              : null,
                          decorationColor: const Color(0xFF64748B),
                          color: isCalled
                              ? Colors.white
                              : (isDeadNumber
                                  ? const Color(0xFF475569)
                                  : const Color(0xFFA0AEC0)),
                        ),
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

  Widget _buildFlashHousieLiveTvStandings(MptGame game) {
    final flashCfg = game.flashHousieConfig;
    if (flashCfg == null) return const SizedBox.shrink();
    final cycle = flashCfg.activeCycleSpec;
    final scoresAsync = ref.watch(memoryRoundScoresStreamProvider(widget.gameId));
    final allScores = scoresAsync.value ?? const <MptMemoryRoundScore>[];

    final currentCycleScores = allScores
        .where((s) => s.cycleNumber == flashCfg.currentCycle)
        .toList()
      ..sort(MptMemoryRoundScore.compareStandings);

    // Fastest / latest recall ticker
    MptMemoryRoundScore? latestRecall;
    for (final s in currentCycleScores) {
      if (s.lastRecalledNumber != null && s.lastReactionMs != null) {
        if (latestRecall == null || s.updatedAt.isAfter(latestRecall.updatedAt)) {
          latestRecall = s;
        }
      }
    }

    // Aggregate cumulative Full House standings across all cycles
    final Map<String, MptMemoryRoundScore> cumulativeByUser = {};
    for (final s in allScores) {
      final existing = cumulativeByUser[s.userId];
      if (existing == null) {
        cumulativeByUser[s.userId] = s;
      } else {
        final combinedNums = <int>{
          ...existing.correctNumbers,
          ...s.correctNumbers,
        }.toList();
        cumulativeByUser[s.userId] = MptMemoryRoundScore(
          id: existing.id,
          gameId: existing.gameId,
          userId: existing.userId,
          displayName: s.displayName.isNotEmpty
              ? s.displayName
              : existing.displayName,
          avatar: s.avatar.isNotEmpty ? s.avatar : existing.avatar,
          cycleIndex: flashCfg.currentCycle,
          quadrantLabel: 'CUMULATIVE',
          correctNumbers: combinedNums,
          correctCount: existing.correctCount + s.correctCount,
          wrongTapCount: existing.wrongTapCount + s.wrongTapCount,
          totalReactionMs: existing.totalReactionMs + s.totalReactionMs,
          updatedAt: s.updatedAt,
        );
      }
    }
    final cumulativeStandings = cumulativeByUser.values.toList()
      ..sort(MptMemoryRoundScore.compareStandings);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF141829),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppTheme.secondaryColor.withValues(alpha: 0.55),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.psychology_rounded,
                    color: AppTheme.secondaryColor,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'LIVE ${cycle.roundBadgeLabel} MEMORY STANDINGS',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.secondaryColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  'Round ${flashCfg.currentCycle}/${flashCfg.totalCycles}',
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.secondaryColor,
                  ),
                ),
              ),
            ],
          ),
          if (latestRecall != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFF38BDF8).withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.bolt_rounded,
                    color: Color(0xFF38BDF8),
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Fastest Recall: ${latestRecall.displayName} locked #${latestRecall.lastRecalledNumber} in ${(latestRecall.lastReactionMs! / 1000).toStringAsFixed(2)}s!',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF38BDF8),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          if (currentCycleScores.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'Waiting for players to lock in recalled numbers...',
                style: TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
              ),
            )
          else
            ...currentCycleScores.take(4).toList().asMap().entries.map((entry) {
              final rank = entry.key + 1;
              final s = entry.value;
              final medal = rank == 1
                  ? '🥇'
                  : (rank == 2 ? '🥈' : (rank == 3 ? '🥉' : '#$rank'));
              return Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: AppTheme.darkSurface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '$medal ${s.displayName}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '✓ ${s.correctCount}  •  ✗ ${s.wrongTapCount}  •  ⚡ ${(s.cumulativeReactionMs / 1000).toStringAsFixed(1)}s',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.secondaryColor,
                      ),
                    ),
                  ],
                ),
              );
            }),
          if (cumulativeStandings.isNotEmpty && flashCfg.totalCycles > 1) ...[
            const SizedBox(height: 8),
            const Divider(color: Color(0xFF2E334D), height: 1),
            const SizedBox(height: 6),
            const Text(
              '🏆 CUMULATIVE FULL HOUSE RACE (ALL ROUNDS)',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: Color(0xFFA78BFA),
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 4),
            ...cumulativeStandings.take(3).toList().asMap().entries.map((entry) {
              final rank = entry.key + 1;
              final s = entry.value;
              final badge = rank == 1 ? '👑 1st FH' : (rank == 2 ? '🥈 2nd FH' : '3rd');
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '$badge • ${s.displayName}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFCBD5E1),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      'Total ✓ ${s.correctCount} (${(s.cumulativeReactionMs / 1000).toStringAsFixed(1)}s)',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFA78BFA),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildLiveWinnersPanel(
    AsyncValue<List<MptClaim>> claimsStream, [
    MptGame? game,
  ]) {
    return Card(
      color: AppTheme.darkSurface,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (game?.isFlashHousie == true)
              _buildFlashHousieLiveTvStandings(game!),
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
                final flashWinnerNames =
                    game?.flashHousieConfig?.awardedWinnerNames ??
                    const <String, String>{};
                if (winners.isEmpty && flashWinnerNames.isEmpty) {
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

                final claimedPrizeTypes = winners.map((w) => w.prizeType).toSet();
                final fallbackFlashEntries = flashWinnerNames.entries
                    .where((e) => !claimedPrizeTypes.contains(e.key))
                    .toList();

                return Column(
                  children: [
                    ...winners.map((w) {
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
                          color: AppTheme.secondaryColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AppTheme.secondaryColor.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: AppTheme.secondaryColor.withValues(
                                  alpha: 0.2,
                                ),
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
                    }),
                    ...fallbackFlashEntries.map((entry) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.secondaryColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AppTheme.secondaryColor.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.emoji_events_rounded,
                              color: AppTheme.secondaryColor,
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    Formatters.formatPrizeName(entry.key),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: Colors.white,
                                    ),
                                  ),
                                  Text(
                                    'Won by: ${entry.value}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.secondaryColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // Post-Game Concluded Screen: Winners Consolidation Table & Recall Trivia TV
  // ===========================================================================

  Widget _buildConcludedGameTvScreen(
    MptGame game,
    List<MptCalledNumber> calledNumbers,
    AsyncValue<List<MptClaim>> claimsStream,
    int totalPlayers,
  ) {
    final triviaRoundAsync = ref.watch(gameTriviaRoundStreamProvider(game.id));
    final triviaWinnersAsync = ref.watch(gameTriviaWinnersStreamProvider(game.id));
    final triviaRound = triviaRoundAsync.value;
    final triviaWinners = triviaWinnersAsync.value ?? const [];

    // Autonomous Trivia State Machine for Scheduled / Host TV screens
    if (game.isPostGameTriviaEnabled && !triviaRoundAsync.isLoading) {
      _syncAutonomousTrivia(triviaRound, game);
    }

    return LayoutBuilder(
      builder: (ctx, constraints) {
        final isWide = constraints.maxWidth >= 950;
        final winnersTable = _buildConsolidatedWinnersTable(
          game,
          calledNumbers,
          claimsStream,
        );
        final triviaStage = game.isPostGameTriviaEnabled
            ? _buildTvTriviaStage(game, triviaRound, triviaWinners)
            : null;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildConcludedGameHeader(game, totalPlayers, calledNumbers.length),
              const SizedBox(height: 18),
              if (isWide && triviaStage != null)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: winnersTable),
                    const SizedBox(width: 18),
                    Expanded(flex: 2, child: triviaStage),
                  ],
                )
              else ...[
                if (triviaStage != null &&
                    (triviaRound?.isActive == true ||
                        triviaRound?.isCountdown == true)) ...[
                  triviaStage,
                  const SizedBox(height: 18),
                ],
                winnersTable,
                if (triviaStage != null &&
                    (triviaRound?.isCompleted == true ||
                        triviaRound?.status == 'PENDING' ||
                        triviaRound == null)) ...[
                  const SizedBox(height: 18),
                  triviaStage,
                ],
              ],
            ],
          ),
        );
      },
    );
  }

  void _syncAutonomousTrivia(MptGameTriviaRound? round, MptGame game) {
    // 1. If trivia is already completed, cancel timers and exit
    if (round != null && (round.isCompleted || round.completedAt != null)) {
      _triviaCountdownTicker?.cancel();
      _triviaCountdownTicker = null;
      _triviaQuestionTicker?.cancel();
      _triviaQuestionTicker = null;
      return;
    }

    // 2. Historical closed game: If game completed > 5 mins ago, do not auto-restart countdown/trivia
    final isRecentGame = game.completedAt == null ||
        DateTime.now().toUtc().difference(game.completedAt!).inMinutes < 5;

    if (!isRecentGame) {
      _triviaCountdownTicker?.cancel();
      _triviaCountdownTicker = null;
      _triviaQuestionTicker?.cancel();
      _triviaQuestionTicker = null;
      if (round != null && !round.isCompleted) {
        Future.microtask(() async {
          try {
            await ref.read(gameplayRepositoryProvider).finalizeGameTrivia(game.id);
          } catch (_) {}
        });
      }
      return;
    }

    if (round == null) {
      if (!_hasTriggeredTriviaGeneration) {
        _hasTriggeredTriviaGeneration = true;
        Future.microtask(() async {
          try {
            await ref.read(gameplayRepositoryProvider).generateGameTrivia(game.id);
          } catch (_) {}
        });
      }
      return;
    }

    // Auto-launch countdown if PENDING and has time gap
    if (round.status == 'PENDING' && round.timeGapSeconds > 0) {
      if (_triviaCountdownTicker == null) {
        _triviaCountdownSecondsLeft = round.timeGapSeconds;
        Future.microtask(() async {
          try {
            await ref.read(gameplayRepositoryProvider).startTriviaCountdown(game.id, round.timeGapSeconds);
          } catch (_) {}
        });
      }
    }

    // Tick countdown down to 0, calculating true elapsed time
    if (round.isCountdown) {
      int secondsLeft = round.timeGapSeconds > 0 ? round.timeGapSeconds : 15;
      if (round.startsAt != null) {
        secondsLeft = round.startsAt!.difference(DateTime.now()).inSeconds;
      }
      if (secondsLeft <= 0) {
        _triviaCountdownTicker?.cancel();
        _triviaCountdownTicker = null;
        if (!_hasTriggeredTriviaLaunch) {
          _hasTriggeredTriviaLaunch = true;
          ref.read(gameplayRepositoryProvider).launchTriviaActive(game.id);
        }
        return;
      }

      if (!_hasTriggeredTriviaLaunch && _triviaCountdownTicker == null) {
        _triviaCountdownSecondsLeft = secondsLeft;
        _triviaCountdownTicker = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (!mounted) {
            timer.cancel();
            return;
          }
          if (_triviaCountdownSecondsLeft > 1) {
            setState(() => _triviaCountdownSecondsLeft--);
          } else {
            timer.cancel();
            _triviaCountdownTicker = null;
            _hasTriggeredTriviaLaunch = true;
            ref.read(gameplayRepositoryProvider).launchTriviaActive(game.id);
          }
        });
      }
    }

    // Tick active question down, then advance to next
    if (round.isActive) {
      if (_lastHandledQuestionIndex != round.currentQuestionIndex) {
        _lastHandledQuestionIndex = round.currentQuestionIndex;
        _triviaQuestionTicker?.cancel();
        _triviaQuestionSecondsLeft = round.secondsPerQuestion;

        _triviaQuestionTicker = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (!mounted) {
            timer.cancel();
            return;
          }
          if (_triviaQuestionSecondsLeft > 1) {
            setState(() => _triviaQuestionSecondsLeft--);
          } else {
            timer.cancel();
            _triviaQuestionTicker = null;
            final nextIdx = round.currentQuestionIndex + 1;
            final isLast = nextIdx >= round.questions.length;
            ref.read(gameplayRepositoryProvider).advanceTriviaQuestion(
              gameId: game.id,
              nextIndex: nextIdx,
              isLast: isLast,
            );
          }
        });
      }
    }
  }

  Widget _buildConcludedGameHeader(
    MptGame game,
    int totalPlayers,
    int totalCalls,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E1B4B), Color(0xFF0F172A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF818CF8).withValues(alpha: 0.6),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF818CF8).withValues(alpha: 0.15),
            blurRadius: 16,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF818CF8).withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.emoji_events_rounded,
              color: Color(0xFFFBBF24),
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Text(
                      '🎉 GAME CONCLUDED • OFFICIAL PRIZE WINNERS',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.6,
                      ),
                    ),
                    SizedBox(width: 8),
                    Icon(
                      Icons.verified_rounded,
                      color: AppTheme.accentSuccess,
                      size: 16,
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${game.name} • Room Code: ${game.inviteCode} • $totalPlayers Players • $totalCalls Numbers Drawn',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFFCBD5E1),
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: () => setState(() => _forceShowBoardGridOnCompleted = true),
            icon: const Icon(Icons.grid_view_rounded, size: 16),
            label: const Text('View Numbers Board', style: TextStyle(fontSize: 12)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.darkCard,
              foregroundColor: AppTheme.secondaryColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              side: BorderSide(color: AppTheme.secondaryColor.withValues(alpha: 0.5)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConsolidatedWinnersTable(
    MptGame game,
    List<MptCalledNumber> calledNumbers,
    AsyncValue<List<MptClaim>> claimsStream,
  ) {
    return Card(
      color: AppTheme.darkSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF2E334D)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.workspace_premium_rounded, color: Color(0xFFFBBF24), size: 22),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Consolidated Prize Winners Podium',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      Text(
                        'All verified winning claims recorded during the game session',
                        style: TextStyle(fontSize: 11.5, color: Color(0xFFA0AEC0)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(color: Color(0xFF2E334D), height: 24),
            claimsStream.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (e, _) => Center(
                child: Text('Error loading winners: $e', style: const TextStyle(color: AppTheme.accentDanger)),
              ),
              data: (claims) {
                final approvedWinners = claims.where((c) => c.status == 'APPROVED').toList();
                final flashWinnerNames = game.flashHousieConfig?.awardedWinnerNames ?? const <String, String>{};

                if (approvedWinners.isEmpty && flashWinnerNames.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        'No winning claims recorded in this game.',
                        style: TextStyle(color: Color(0xFFA0AEC0), fontSize: 13),
                      ),
                    ),
                  );
                }

                final List<MptRegistration> regList =
                    ref.watch(registrationsStreamProvider(widget.gameId)).value ?? [];
                final regMap = {for (final r in regList) r.userId: r};

                return ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFF2E334D)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        // Table Header
                        Container(
                          color: const Color(0xFF1E293B),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          child: const Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: Text('PRIZE PATTERN', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8))),
                              ),
                              Expanded(
                                flex: 3,
                                child: Text('WINNER', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8))),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text('BALL #', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8))),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text('CALL SEQ', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8))),
                              ),
                              Expanded(
                                flex: 3,
                                child: Text('STATUS & REWARD', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8))),
                              ),
                            ],
                          ),
                        ),
                        // Table Rows
                        ...approvedWinners.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final claim = entry.value;
                          final playerReg = regMap[claim.userId];
                          final displayName = (playerReg?.displayName.isNotEmpty == true)
                              ? playerReg!.displayName
                              : (claim.userName != null && claim.userName != 'Player')
                                  ? claim.userName!
                                  : 'Player';
                          final avatar = playerReg?.avatar ?? claim.userAvatar ?? 'avatar_1';
                          final callsBefore = calledNumbers
                              .where((c) => c.calledAt.isBefore(claim.submittedAt) || c.calledAt.isAtSameMomentAs(claim.submittedAt))
                              .toList();
                          final winningNum = callsBefore.isNotEmpty
                              ? callsBefore.last.number
                              : (calledNumbers.isNotEmpty ? calledNumbers.last.number : null);
                          final seqNum = callsBefore.isNotEmpty
                              ? callsBefore.last.callSeq
                              : (calledNumbers.isNotEmpty ? calledNumbers.last.callSeq : 1);


                          // Prize reward info if available in prizeGiftsConfig
                          final prizeCfg = game.prizeGiftsConfig[claim.prizeType];
                          String? prizeRewardLabel;
                          if (prizeCfg is Map) {
                            if (prizeCfg['title'] != null) {
                              prizeRewardLabel = prizeCfg['title'].toString();
                            } else if (prizeCfg['prize_value'] != null) {
                              final sym = prizeCfg['currency_symbol'] ?? '\$';
                              prizeRewardLabel = '$sym${prizeCfg['prize_value']}';
                            }
                          }

                          return Container(
                            color: idx.isEven ? const Color(0xFF0F172A) : const Color(0xFF131B2E),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            child: Row(
                              children: [
                                // Prize Pattern
                                Expanded(
                                  flex: 3,
                                  child: Row(
                                    children: [
                                      Text(
                                        _getPrizeEmoji(claim.prizeType),
                                        style: const TextStyle(fontSize: 18),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          Formatters.formatPrizeName(claim.prizeType),
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Winner Name & Avatar
                                Expanded(
                                  flex: 3,
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 28,
                                        height: 28,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF818CF8).withValues(alpha: 0.2),
                                          shape: BoxShape.circle,
                                        ),
                                        alignment: Alignment.center,
                                        child: Text(
                                          Formatters.getAvatarEmoji(avatar),
                                          style: const TextStyle(fontSize: 15),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          displayName,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFFF1F5F9),
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Winning Ball
                                Expanded(
                                  flex: 2,
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        winningNum != null ? '$winningNum' : '—',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                // Call Sequence
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    '#$seqNum',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF94A3B8),
                                    ),
                                  ),
                                ),
                                // Status & Reward
                                Expanded(
                                  flex: 3,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppTheme.accentSuccess.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: AppTheme.accentSuccess.withValues(alpha: 0.4)),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.check_circle_rounded, color: AppTheme.accentSuccess, size: 12),
                                            SizedBox(width: 4),
                                            Text(
                                              'VERIFIED',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: AppTheme.accentSuccess,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (prizeRewardLabel != null) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          prizeRewardLabel,
                                          style: const TextStyle(
                                            fontSize: 10.5,
                                            color: Color(0xFFFBBF24),
                                            fontWeight: FontWeight.w600,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
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

  String _getPrizeEmoji(String prizeType) {
    switch (prizeType) {
      case 'FULL_HOUSE':
        return '🏠🥇';
      case 'SECOND_FULL_HOUSE':
        return '🏠🥈';
      case 'EARLY_FIVE':
        return '⚡';
      case 'TOP_LINE':
        return '⬆️';
      case 'MIDDLE_LINE':
        return '↔️';
      case 'BOTTOM_LINE':
        return '⬇️';
      case 'CORNERS':
      case 'FOUR_CORNERS':
        return '🔲';
      default:
        return '🎖️';
    }
  }

  Widget _buildTvTriviaStage(
    MptGame game,
    MptGameTriviaRound? round,
    List<MptTriviaWinner> winners,
  ) {
    final isRecentGame = game.completedAt == null ||
        DateTime.now().toUtc().difference(game.completedAt!).inMinutes < 5;

    if (round == null) {
      if (!isRecentGame) {
        return const SizedBox.shrink();
      }
      return const Card(
        color: AppTheme.darkSurface,
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (round.status == 'PENDING') {
      if (!isRecentGame) {
        return const SizedBox.shrink();
      }
      return Card(
        color: AppTheme.darkSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF6366F1), width: 1.2),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.psychology_rounded, color: Color(0xFF818CF8), size: 36),
              ),
              const SizedBox(height: 14),
              const Text(
                '🧠 Up Next: DabHousie Recall Trivia Challenge!',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              const Text(
                'Automated cognitive recall challenge testing player observation and attention from today\'s game. 1 question per category.',
                style: TextStyle(fontSize: 12, color: Color(0xFFCBD5E1)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => ref.read(gameplayRepositoryProvider).startTriviaCountdown(game.id),
                icon: const Icon(Icons.play_arrow_rounded, size: 20),
                label: const Text('Start Trivia Countdown (15s)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (round.isCountdown) {
      if (!isRecentGame) {
        return const SizedBox.shrink();
      }
      return Card(
        color: AppTheme.darkSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF818CF8), width: 1.5),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.psychology_rounded, color: Color(0xFF818CF8), size: 22),
                  SizedBox(width: 8),
                  Text(
                    'RECALL TRIVIA STARTING SOON',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF818CF8), letterSpacing: 1.1),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF4F46E5)]),
                  boxShadow: [
                    BoxShadow(color: const Color(0xFF6366F1).withValues(alpha: 0.4), blurRadius: 18, spreadRadius: 4),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  '$_triviaCountdownSecondsLeft',
                  style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Get Ready On Your Devices!',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 4),
              const Text(
                '4 rapid-fire questions testing observation, draw milestones, and winners. Speed + accuracy scoring!',
                style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => ref.read(gameplayRepositoryProvider).launchTriviaActive(game.id),
                child: const Text('Launch Immediately →', style: TextStyle(color: Color(0xFF818CF8), fontSize: 12)),
              ),
            ],
          ),
        ),
      );
    }

    if (round.isActive) {
      if (round.questions.isEmpty || round.currentQuestionIndex >= round.questions.length) {
        return const Center(child: CircularProgressIndicator());
      }
      final currentQ = round.questions[round.currentQuestionIndex];
      final isLastQuestion = round.currentQuestionIndex + 1 >= round.questions.length;

      return Card(
        color: AppTheme.darkSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF6366F1), width: 1.5),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top Bar: Category + Question Number + Timer
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF818CF8).withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      currentQ.categoryName.toUpperCase(),
                      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFFC7D2FE)),
                    ),
                  ),
                  Text(
                    'Question ${round.currentQuestionIndex + 1} of ${round.questions.length}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _triviaQuestionSecondsLeft <= 5 ? AppTheme.accentDanger : const Color(0xFFFBBF24),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.timer_rounded, size: 14, color: Colors.black),
                        const SizedBox(width: 4),
                        Text(
                          '${_triviaQuestionSecondsLeft}s',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Progress Bar
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _triviaQuestionSecondsLeft / (round.secondsPerQuestion > 0 ? round.secondsPerQuestion : 15),
                  backgroundColor: const Color(0xFF1E293B),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _triviaQuestionSecondsLeft <= 5 ? AppTheme.accentDanger : const Color(0xFF818CF8),
                  ),
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 16),

              // Big Question Text
              Text(
                currentQ.question,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  height: 1.35,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),

              // 4 Fast-Recall Answer Tiles
              _buildKahootOptionTile(0, currentQ.options.isNotEmpty ? currentQ.options[0] : '', const Color(0xFFEF4444), '▲'),
              const SizedBox(height: 8),
              _buildKahootOptionTile(1, currentQ.options.length > 1 ? currentQ.options[1] : '', const Color(0xFF3B82F6), '◆'),
              const SizedBox(height: 8),
              _buildKahootOptionTile(2, currentQ.options.length > 2 ? currentQ.options[2] : '', const Color(0xFFF59E0B), '●'),
              const SizedBox(height: 8),
              _buildKahootOptionTile(3, currentQ.options.length > 3 ? currentQ.options[3] : '', const Color(0xFF10B981), '■'),
              const SizedBox(height: 14),

              // Host Manual Skip / Next button
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () {
                    final nextIdx = round.currentQuestionIndex + 1;
                    ref.read(gameplayRepositoryProvider).advanceTriviaQuestion(
                      gameId: game.id,
                      nextIndex: nextIdx,
                      isLast: isLastQuestion,
                    );
                  },
                  icon: Icon(isLastQuestion ? Icons.emoji_events_rounded : Icons.skip_next_rounded, size: 18, color: const Color(0xFF818CF8)),
                  label: Text(
                    isLastQuestion ? 'Show Final Podium 🏆' : 'Next Question ⏩',
                    style: const TextStyle(color: Color(0xFF818CF8), fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // COMPLETED: Grand Podium or Static Question Review
    if (_isReviewingQuestionsOnPodium && round.questions.isNotEmpty) {
      final safeIdx = _reviewQuestionIndex.clamp(0, round.questions.length - 1);
      final q = round.questions[safeIdx];
      return Card(
        color: AppTheme.darkSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF6366F1), width: 1.5),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      q.categoryName.toUpperCase(),
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFC7D2FE)),
                    ),
                  ),
                  Text(
                    'Question ${safeIdx + 1} of ${round.questions.length}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8)),
                  ),
                  TextButton.icon(
                    onPressed: () => setState(() => _isReviewingQuestionsOnPodium = false),
                    icon: const Icon(Icons.arrow_back, size: 14, color: Color(0xFFFBBF24)),
                    label: const Text('Podium', style: TextStyle(color: Color(0xFFFBBF24), fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                q.question,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white, height: 1.35),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ...q.options.asMap().entries.map((e) {
                final isCorrect = e.key == q.correctIndex;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: isCorrect ? AppTheme.accentSuccess.withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isCorrect ? AppTheme.accentSuccess : Colors.white.withValues(alpha: 0.1),
                      width: isCorrect ? 1.8 : 1.0,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(isCorrect ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                        color: isCorrect ? AppTheme.accentSuccess : Colors.white38, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(e.value, style: TextStyle(
                          fontSize: 13,
                          fontWeight: isCorrect ? FontWeight.bold : FontWeight.normal,
                          color: isCorrect ? Colors.white : const Color(0xFFCBD5E1),
                        )),
                      ),
                      if (isCorrect)
                        const Text('CORRECT', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppTheme.accentSuccess)),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: safeIdx > 0 ? () => setState(() => _reviewQuestionIndex = safeIdx - 1) : null,
                    child: const Text('← Previous'),
                  ),
                  TextButton(
                    onPressed: safeIdx < round.questions.length - 1 ? () => setState(() => _reviewQuestionIndex = safeIdx + 1) : null,
                    child: const Text('Next →'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    // COMPLETED: Grand Podium
    return Card(
      color: AppTheme.darkSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFFBBF24), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.workspace_premium_rounded, color: Color(0xFFFBBF24), size: 26),
                SizedBox(width: 8),
                Text(
                  'TRIVIA OBSERVATION CHAMPIONS',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFFFBBF24), letterSpacing: 0.8),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Recognizing top recall, speed, and accuracy from today\'s game',
              style: TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            if (winners.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Calculating trivia podium results...', style: TextStyle(color: Color(0xFFA0AEC0))),
              )
            else
              ...winners.map((w) {
                Color badgeColor;
                String emoji;
                switch (w.rank) {
                  case 1:
                    badgeColor = const Color(0xFFFBBF24); // Gold
                    emoji = '🥇';
                    break;
                  case 2:
                    badgeColor = const Color(0xFFCBD5E1); // Silver
                    emoji = '🥈';
                    break;
                  case 3:
                    badgeColor = const Color(0xFFF97316); // Bronze
                    emoji = '🥉';
                    break;
                  case 4:
                    badgeColor = const Color(0xFFA78BFA); // Purple
                    emoji = '🎖️';
                    break;
                  case 5:
                    badgeColor = const Color(0xFF38BDF8); // Sky Blue
                    emoji = '🌟';
                    break;
                  default:
                    badgeColor = const Color(0xFF94A3B8); // Slate
                    emoji = '#${w.rank}';
                }

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: badgeColor.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    children: [
                      Text(emoji, style: const TextStyle(fontSize: 22)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              w.userName,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              w.title,
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: badgeColor),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${w.totalScore} pts',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: badgeColor),
                          ),
                          Text(
                            '${w.correctCount} correct • ${(w.avgResponseTimeMs / 1000).toStringAsFixed(1)}s avg',
                            style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 10),
              Center(
                child: TextButton.icon(
                  onPressed: () => setState(() {
                    _isReviewingQuestionsOnPodium = true;
                    _reviewQuestionIndex = 0;
                  }),
                  icon: const Icon(Icons.quiz_rounded, size: 16, color: Color(0xFF818CF8)),
                  label: const Text('Review Questions & Answers 📝', style: TextStyle(color: Color(0xFF818CF8), fontSize: 12.5, fontWeight: FontWeight.bold)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildKahootOptionTile(int index, String optionText, Color color, String symbol) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.6), width: 1.2),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
            alignment: Alignment.center,
            child: Text(
              symbol,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              optionText,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

