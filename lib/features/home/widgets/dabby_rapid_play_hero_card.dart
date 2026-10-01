import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../../core/constants/app_assets.dart';
import '../../../core/theme/app_theme.dart';

/// Compact Hero Card showcasing Dabby the Mascot with a Play with Dabby button.
/// Keeps the dashboard compact and uncluttered so that the main business cards
/// (Classic Bingo & Skill Arena) remain immediately visible above the fold.
class DabbyRapidPlayHeroCard extends StatelessWidget {
  const DabbyRapidPlayHeroCard({super.key});

  void _openPlayDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => const Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: _DabbyPlayModal(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isCompact = screenWidth < 700;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.45),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Banner image container (compact height, constrained to avoid pushing content down)
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: isCompact ? 160 : 210,
              minHeight: 120,
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  AppAssets.dabbyShowcaseBanner,
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                  errorBuilder: (ctx, err, stack) => Image.asset(
                    AppAssets.dabbyTicketBanner,
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                  ),
                ),
                // Gradient overlay at bottom of banner for seamless transition
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          const Color(0xFF0F172A).withValues(alpha: 0.85),
                        ],
                        stops: const [0.6, 1.0],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Caption & Action row below the mascot banner
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const Text(
                  '⚡',
                  style: TextStyle(fontSize: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Warm Up with Dabby!',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Instant 15-number rapid solo game with Dabby the mascot • Practice your dabbing speed!',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade400,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () => _openPlayDialog(context),
                  icon: const Icon(Icons.play_arrow_rounded, size: 20),
                  label: const Text('Play with Dabby'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF59E0B),
                    foregroundColor: const Color(0xFF0F172A),
                    padding: EdgeInsets.symmetric(
                      horizontal: isCompact ? 14 : 20,
                      vertical: 10,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w900,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The interactive modal game simulation that pops up when user taps "Play with Dabby"
class _DabbyPlayModal extends StatefulWidget {
  const _DabbyPlayModal();

  @override
  State<_DabbyPlayModal> createState() => _DabbyPlayModalState();
}

class _DabbyPlayModalState extends State<_DabbyPlayModal>
    with SingleTickerProviderStateMixin {
  static const double _callDurationSec = 5.0;
  static const int _maxConsecutiveMisses = 5;

  static const List<List<int>> _colRanges = [
    [1, 9],
    [10, 19],
    [20, 29],
    [30, 39],
    [40, 49],
    [50, 59],
    [60, 69],
    [70, 79],
    [80, 90],
  ];

  List<List<int?>> _ticket = [
    List.filled(9, null),
    List.filled(9, null),
    List.filled(9, null),
  ];
  final Set<int> _ticketNums = <int>{};
  final Set<int> _dabbedNums = <int>{};
  final List<int> _calledHistory = <int>[];
  List<int> _uncalledPool = <int>[];

  int? _currentBall;
  int _score = 0;
  int _consecutiveMisses = 0;
  bool _isGameOver = false;
  String _gameOverReason = '';
  bool _isFullHouseWon = false;

  Timer? _countdownTimer;
  double _timeLeftSec = _callDurationSec;
  late AnimationController _ballPopController;
  late Animation<double> _ballPopScale;

  String? _feedbackText;
  Color _feedbackColor = Colors.white;
  Timer? _feedbackTimer;
  int _gameCode = 577873;

  @override
  void initState() {
    super.initState();
    _ballPopController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _ballPopScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.6, end: 1.25), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.25, end: 1.0), weight: 50),
    ]).animate(
      CurvedAnimation(parent: _ballPopController, curve: Curves.easeOutBack),
    );

    _startNewGame();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _feedbackTimer?.cancel();
    _ballPopController.dispose();
    super.dispose();
  }

  void _startNewGame() {
    _countdownTimer?.cancel();
    final random = Random();
    _gameCode = 100000 + random.nextInt(900000);
    _dabbedNums.clear();
    _calledHistory.clear();
    _score = 0;
    _consecutiveMisses = 0;
    _isGameOver = false;
    _gameOverReason = '';
    _isFullHouseWon = false;

    _uncalledPool = List.generate(90, (i) => i + 1)..shuffle(random);
    _generateAuthenticTicket();
    _callNextBall();
  }

  void _generateAuthenticTicket() {
    final random = Random();
    _ticket = List.generate(3, (_) => List<int?>.filled(9, null));
    _ticketNums.clear();

    List<int> colCounts = List.filled(9, 1);
    int remaining = 6;
    while (remaining > 0) {
      final col = random.nextInt(9);
      if (colCounts[col] < 3) {
        colCounts[col]++;
        remaining--;
      }
    }

    final colNumbers = <int, List<int>>{};
    for (int c = 0; c < 9; c++) {
      final minVal = _colRanges[c][0];
      final maxVal = _colRanges[c][1];
      final pool = List.generate(maxVal - minVal + 1, (i) => minVal + i);
      pool.shuffle(random);
      final picked = pool.take(colCounts[c]).toList()..sort();
      colNumbers[c] = picked;
      _ticketNums.addAll(picked);
    }

    for (int c = 0; c < 9; c++) {
      final nums = colNumbers[c]!;
      if (nums.length == 3) {
        _ticket[0][c] = nums[0];
        _ticket[1][c] = nums[1];
        _ticket[2][c] = nums[2];
      } else if (nums.length == 2) {
        final rows = [0, 1, 2]..shuffle(random);
        rows.sort();
        _ticket[rows[0]][c] = nums[0];
        _ticket[rows[1]][c] = nums[1];
      } else if (nums.length == 1) {
        final rowIdxs = [0, 1, 2]..sort((r1, r2) {
          final count1 = _ticket[r1].where((x) => x != null).length;
          final count2 = _ticket[r2].where((x) => x != null).length;
          return count1.compareTo(count2);
        });
        _ticket[rowIdxs[0]][c] = nums[0];
      }
    }
  }

  void _callNextBall() {
    if (_isFullHouseWon || _isGameOver) return;
    if (_uncalledPool.isEmpty) {
      _triggerGameOver('All 90 numbers called!');
      return;
    }

    final random = Random();
    final remainingTicketNums = _ticketNums.difference(_dabbedNums).difference(_calledHistory.toSet()).toList();

    int pick;
    if (remainingTicketNums.isNotEmpty && random.nextDouble() < 0.75) {
      pick = remainingTicketNums[random.nextInt(remainingTicketNums.length)];
      _uncalledPool.remove(pick);
    } else {
      pick = _uncalledPool.removeLast();
    }

    setState(() {
      _currentBall = pick;
      _calledHistory.add(pick);
      _timeLeftSec = _callDurationSec;
    });

    _ballPopController.forward(from: 0.0);
    _startCountdown();
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    const tickMs = 50;
    _countdownTimer = Timer.periodic(const Duration(milliseconds: tickMs), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _timeLeftSec -= (tickMs / 1000.0);
        if (_timeLeftSec <= 0) {
          _timeLeftSec = 0;
          timer.cancel();
          _onTimerExpired();
        }
      });
    });
  }

  void _onTimerExpired() {
    if (_isFullHouseWon || _isGameOver) return;
    _consecutiveMisses++;
    if (_consecutiveMisses >= _maxConsecutiveMisses) {
      _triggerGameOver('You missed $_maxConsecutiveMisses calls in a row without dabbing.');
      return;
    }

    if (_ticketNums.contains(_currentBall) && !_dabbedNums.contains(_currentBall)) {
      _showFeedback('⏰ MISSED CALL!', const Color(0xFFEF4444));
    }

    _callNextBall();
  }

  void _triggerGameOver(String reason) {
    _countdownTimer?.cancel();
    setState(() {
      _isGameOver = true;
      _gameOverReason = reason;
    });
  }

  void _onCellTapped(int number) {
    if (_isGameOver || _isFullHouseWon) return;

    if (_dabbedNums.contains(number)) {
      _showFeedback('ALREADY DABBED!', const Color(0xFFEAB308));
      return;
    }

    if (number == _currentBall) {
      setState(() {
        _dabbedNums.add(number);
        _score += 100;
        _consecutiveMisses = 0;
      });
      _showFeedback('🎯 PERFECT DAB! +100', const Color(0xFF10B981));

      if (_dabbedNums.length == _ticketNums.length) {
        _triggerFullHouseVictory();
        return;
      }
      _callNextBall();
      return;
    }

    if (_calledHistory.contains(number)) {
      setState(() {
        _dabbedNums.add(number);
        _score += 50;
        _consecutiveMisses = 0;
      });
      _showFeedback('⏱️ DELAYED DAB! +50', const Color(0xFF38BDF8));

      if (_dabbedNums.length == _ticketNums.length) {
        _triggerFullHouseVictory();
      }
      return;
    }

    _showFeedback('❌ NOT CALLED YET!', const Color(0xFFEF4444));
  }

  void _triggerFullHouseVictory() {
    _countdownTimer?.cancel();
    setState(() {
      _isFullHouseWon = true;
      _score += 500;
    });
    _showFeedback('🏆 FULL HOUSE! +500', const Color(0xFFFBBF24));
  }

  void _showFeedback(String msg, Color color) {
    _feedbackTimer?.cancel();
    setState(() {
      _feedbackText = msg;
      _feedbackColor = color;
    });
    _feedbackTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) {
        setState(() {
          _feedbackText = null;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isOnTicket = _currentBall != null &&
        _ticketNums.contains(_currentBall) &&
        !_dabbedNums.contains(_currentBall);

    return Container(
      constraints: const BoxConstraints(maxWidth: 780),
      decoration: BoxDecoration(
        color: const Color(0xFF090D1A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isOnTicket
              ? const Color(0xFFEF4444)
              : AppTheme.secondaryColor.withValues(alpha: 0.5),
          width: 2.0,
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black87,
            blurRadius: 28,
            offset: Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header with close button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Text('🦁', style: TextStyle(fontSize: 20)),
                  SizedBox(width: 8),
                  Text(
                    'Play with Dabby • Solo Simulation',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, color: Colors.white70),
                tooltip: 'Close Game',
              ),
            ],
          ),
          const SizedBox(height: 8),

          // 1. Caller & Pressure Bar
          _buildTopCallerBar(isOnTicket),
          const SizedBox(height: 10),

          // 2. 3x9 Ticket Banner
          AspectRatio(
            aspectRatio: 1536 / 1024,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    AppAssets.dabbyTicketBanner,
                    fit: BoxFit.contain,
                    errorBuilder: (ctx, err, stack) => Container(
                      color: const Color(0xFF1E293B),
                      child: const Center(
                        child: Text('Play with Dabby', style: TextStyle(color: Colors.white70)),
                      ),
                    ),
                  ),

                  // Game Code Overlay
                  Positioned(
                    top: 10,
                    right: 14,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.white24, width: 0.8),
                      ),
                      child: Text(
                        'Game Code: $_gameCode',
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),

                  // 3x9 Grid overlay
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final gridLeft = constraints.maxWidth * 0.2343;
                      final gridTop = constraints.maxHeight * 0.3184;
                      final gridWidth = constraints.maxWidth * 0.7305;
                      final gridHeight = constraints.maxHeight * 0.3945;

                      return Positioned(
                        left: gridLeft,
                        top: gridTop,
                        width: gridWidth,
                        height: gridHeight,
                        child: _buildGridCells(gridWidth, gridHeight),
                      );
                    },
                  ),

                  // Feedback Float
                  if (_feedbackText != null)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: _feedbackColor, width: 1.5),
                        ),
                        child: Text(
                          _feedbackText!,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: _feedbackColor,
                          ),
                        ),
                      ),
                    ),

                  // Victory Banner
                  if (_isFullHouseWon)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFEAB308), Color(0xFFCA8A04)],
                          ),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black54,
                              blurRadius: 16,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              '🏆 FULL HOUSE VICTORY! 🎉',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF451A03),
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'All 15 numbers dabbed with Dabby!',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF451A03),
                              ),
                            ),
                            const SizedBox(height: 10),
                            ElevatedButton.icon(
                              onPressed: _startNewGame,
                              icon: const Icon(Icons.replay_rounded, size: 18),
                              label: const Text('Play Another Round'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF451A03),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Game Over / Inactivity Banner
                  if (_isGameOver)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A).withValues(alpha: 0.95),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFEF4444), width: 1.5),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black87,
                              blurRadius: 20,
                              offset: Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              '⏰ GAME OVER',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFFF87171),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _gameOverReason,
                              style: const TextStyle(fontSize: 12, color: Color(0xFFCBD5E1)),
                            ),
                            const SizedBox(height: 10),
                            ElevatedButton.icon(
                              onPressed: _startNewGame,
                              icon: const Icon(Icons.refresh_rounded, size: 18),
                              label: const Text('Play Again'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF10B981),
                                foregroundColor: Colors.black,
                                textStyle: const TextStyle(fontWeight: FontWeight.w900),
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopCallerBar(bool isOnTicket) {
    final progress = (_timeLeftSec / _callDurationSec).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isOnTicket ? const Color(0xFFEF4444) : Colors.white12,
          width: isOnTicket ? 1.6 : 1.0,
        ),
      ),
      child: Row(
        children: [
          ScaleTransition(
            scale: _ballPopScale,
            child: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  center: Alignment(-0.3, -0.3),
                  colors: [Color(0xFFFF5252), Color(0xFFD32F2F), Color(0xFF8B0000)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Color(0xFFD32F2F),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  _currentBall != null ? '$_currentBall' : '--',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: isOnTicket
                            ? const Color(0xFFEF4444).withValues(alpha: 0.2)
                            : AppTheme.secondaryColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isOnTicket ? '🔥 ON TICKET' : 'CALLED',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          color: isOnTicket ? const Color(0xFFF87171) : AppTheme.secondaryColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '$_score Pts • ${_dabbedNums.length}/15',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _isGameOver
                      ? 'Game Over'
                      : (isOnTicket
                          ? 'DAB $_currentBall NOW!'
                          : 'Dabby called $_currentBall • Check ticket'),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    color: isOnTicket ? Colors.white : const Color(0xFFCBD5E1),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 38,
            height: 38,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 3.5,
                  backgroundColor: Colors.white12,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _timeLeftSec <= 2.0 ? const Color(0xFFEF4444) : const Color(0xFFFACC15),
                  ),
                ),
                Text(
                  '${_timeLeftSec.ceil()}s',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'New Ticket',
            onPressed: _startNewGame,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _buildGridCells(double width, double height) {
    final cellWidth = width / 9.0;
    final cellHeight = height / 3.0;

    return Stack(
      children: [
        for (int r = 0; r < 3; r++)
          for (int c = 0; c < 9; c++)
            if (_ticket[r][c] != null)
              Positioned(
                left: c * cellWidth,
                top: r * cellHeight,
                width: cellWidth,
                height: cellHeight,
                child: _buildCell(_ticket[r][c]!),
              ),
      ],
    );
  }

  Widget _buildCell(int num) {
    final isDabbed = _dabbedNums.contains(num);
    final isCurrent = num == _currentBall && !isDabbed;

    return Padding(
      padding: const EdgeInsets.all(1.5),
      child: InkWell(
        onTap: () => _onCellTapped(num),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          decoration: BoxDecoration(
            color: isDabbed
                ? const Color(0xFFFACC15).withValues(alpha: 0.88)
                : (isCurrent ? const Color(0xFFEF4444).withValues(alpha: 0.35) : Colors.transparent),
            borderRadius: BorderRadius.circular(6),
            border: isCurrent
                ? Border.all(color: const Color(0xFFEF4444), width: 1.8)
                : null,
          ),
          child: Center(
            child: Text(
              '$num',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
